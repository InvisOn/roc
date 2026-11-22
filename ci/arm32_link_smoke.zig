//! Link an arm32 object written by the dev backend, and check what the linker
//! resolved.
//!
//! The object is built with the arm32 encoder and `ElfWriter`. Its function
//! `roc_link_smoke(void) -> int` uses each arm32 relocation kind the dev
//! backend emits:
//!
//! - `R_ARM_MOVW_PREL_NC` and `R_ARM_MOVT_PREL`: the pc-relative address of a
//!   table in read-only data;
//! - `R_ARM_ABS32`: the table's entry, the address of a message;
//! - `R_ARM_CALL`: a call to the C library's `puts` with that message.
//!
//! It then returns 42.
//!
//! The tool checks the object's header and its hard-float attribute, links
//! it with a C `main` through `zig cc -target arm-linux-musleabihf`, and
//! reads the executable back: the `bl` must reach `puts`, the `movw`/`movt`
//! pair the table, and the table entry the message. Nothing here runs the
//! executable.
//!
//!     zig build run-check-arm32-link-smoke
//!
//! Usage: arm32-link-smoke <zig executable> <work directory>

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const backend = @import("backend");
const arm32 = backend.dev.arm32;
const elf = backend.dev.object.elf;
const UnitImage = backend.dev.UnitImage;

const usage = "usage: arm32-link-smoke <zig executable> <work directory>";

/// The message the smoke function prints.
const message = "arm32 link smoke: encoder, ELF writer and relocations work";

const main_c =
    \\#include <stdio.h>
    \\extern int roc_link_smoke(void);
    \\int main(void) {
    \\    int result = roc_link_smoke();
    \\    printf("roc_link_smoke returned %d\n", result);
    \\    return result == 42 ? 0 : 1;
    \\}
    \\
;

/// A failure the tool reports to the person running it, with the message
/// already written to the output.
const Failure = error{Reported};

const Report = struct {
    writer: *Io.Writer,

    fn fail(self: Report, comptime fmt: []const u8, args: anytype) Failure {
        self.writer.print(fmt ++ "\n", args) catch {};
        return error.Reported;
    }
};

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    const io = init.io;
    var buffer: [4096]u8 = undefined;
    var output = Io.File.stderr().writer(io, &buffer);
    const writer = &output.interface;
    const report: Report = .{ .writer = writer };

    run(gpa, io, init, report) catch |err| switch (err) {
        error.Reported => {
            try writer.flush();
            std.process.exit(1);
        },
        else => return err,
    };
    try writer.flush();
}

fn run(gpa: Allocator, io: Io, init: std.process.Init, report: Report) !void {
    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, gpa);
    defer args.deinit();
    _ = args.next();
    const zig_exe = args.next() orelse return report.fail(usage, .{});
    const work_dir = args.next() orelse return report.fail(usage, .{});
    if (args.next()) |extra| return report.fail("unexpected argument `{s}`\n" ++ usage, .{extra});

    const smoke = try buildObject(gpa);
    try checkObject(Reader{ .data = smoke.bytes, .report = report });

    const cwd = Io.Dir.cwd();
    try cwd.createDirPath(io, work_dir);
    const obj_path = try std.fs.path.join(gpa, &.{ work_dir, "arm32_link_smoke.o" });
    const main_path = try std.fs.path.join(gpa, &.{ work_dir, "main.c" });
    const exe_path = try std.fs.path.join(gpa, &.{ work_dir, "arm32_link_smoke" });
    try cwd.writeFile(io, .{ .sub_path = obj_path, .data = smoke.bytes });
    try cwd.writeFile(io, .{ .sub_path = main_path, .data = main_c });

    const result = try std.process.run(gpa, io, .{
        .argv = &.{ zig_exe, "cc", "-target", "arm-linux-musleabihf", main_path, obj_path, "-o", exe_path },
    });
    if (result.term != .exited or result.term.exited != 0) {
        return report.fail("linking the arm32 smoke object failed:\n{s}", .{result.stderr});
    }

    const executable = try cwd.readFileAlloc(io, exe_path, gpa, .unlimited);
    try checkExecutable(Reader{ .data = executable, .report = report }, smoke);
    try report.writer.print("arm32 link smoke: linked; bl, movw/movt and abs32 resolve to their targets\n", .{});
}

/// The smoke object and where its relocated instructions are.
const SmokeObject = struct {
    bytes: []u8,
    /// Offset in `roc_link_smoke` of the `movw`; the `movt` and `add` follow.
    address_at: u64,
    /// Offset in `roc_link_smoke` of the `bl puts`.
    call_at: u64,
};

fn buildObject(gpa: Allocator) Allocator.Error!SmokeObject {
    var e = arm32.MuslEmit.init(gpa);
    defer e.deinit();
    // push {r4, lr}: keeps SP 8-byte aligned across the call (AAPCS32).
    try e.push(arm32.GeneralReg.r4.listBit() | arm32.GeneralReg.lr.listBit());
    // r0 = &table
    const address_at = try e.pcRelAddress(.r0);
    // r0 = table[0], the message address
    try e.ldrRegMem(.r0, .r0, 0);
    const call_at = e.codeOffset();
    try e.bl(0);
    try e.movRegImm32(.r0, 42);
    try e.pop(arm32.GeneralReg.r4.listBit() | arm32.GeneralReg.pc.listBit());

    // Read-only data: the message, then a word-aligned table holding its
    // address.
    const message_z = message ++ "\x00";
    const table_offset = comptime std.mem.alignForward(usize, message_z.len, 4);
    var rodata: [table_offset + 4]u8 = @splat(0);
    @memcpy(rodata[0..message_z.len], message_z);

    var w = try elf.ElfWriter.init(gpa, .arm32, .none);
    defer w.deinit();
    w.setCode(e.buf.items);
    const rodata_piece = [1]UnitImage.SectionPiece{.{ .offset = 0, .bytes = &rodata }};
    w.setRodata(.whole(&rodata_piece));
    // Local symbols precede global ones, as ELF requires.
    const message_sym = try w.addSymbol(.{ .name = "roc_link_smoke_message", .section = .rodata, .offset = 0, .size = message_z.len, .is_global = false, .is_function = false });
    const table_sym = try w.addSymbol(.{ .name = "roc_link_smoke_table", .section = .rodata, .offset = table_offset, .size = 4, .is_global = false, .is_function = false });
    _ = try w.addSymbol(.{ .name = "roc_link_smoke", .section = .text, .offset = 0, .size = e.buf.items.len, .is_global = true, .is_function = true });
    const puts_sym = try w.addExternalSymbol("puts");
    try w.addTextDataRelocation(address_at, table_sym, .arm32_movw_prel);
    try w.addTextDataRelocation(address_at + 4, table_sym, .arm32_movt_prel);
    try w.addTextRelocation(call_at, puts_sym, .arm32_call);
    try w.addRodataRelocation(table_offset, message_sym, 0);

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    try w.write(&out);
    return .{ .bytes = try out.toOwnedSlice(gpa), .address_at = address_at, .call_at = call_at };
}

/// Little-endian ELF32 reads that fail on a truncated file.
const Reader = struct {
    data: []const u8,
    report: Report,

    fn int(self: Reader, comptime T: type, offset: usize) Failure!T {
        if (offset + @sizeOf(T) > self.data.len) return self.report.fail("malformed ELF file: read past its end", .{});
        return std.mem.readInt(T, self.data[offset..][0..@sizeOf(T)], .little);
    }

    /// Field `name` of the `Record` at `offset`, read as an integer of the
    /// field's size.
    fn field(self: Reader, comptime Record: type, comptime name: []const u8, offset: usize) Failure!@Int(.unsigned, @bitSizeOf(@FieldType(Record, name))) {
        return self.int(@Int(.unsigned, @bitSizeOf(@FieldType(Record, name))), offset + @offsetOf(Record, name));
    }

    fn sectionOffset(self: Reader, index: usize) Failure!usize {
        const shoff = try self.field(std.elf.Elf32.Ehdr, "shoff", 0);
        return shoff + index * @sizeOf(std.elf.Elf32.Shdr);
    }

    fn sectionCount(self: Reader) Failure!u16 {
        return self.field(std.elf.Elf32.Ehdr, "shnum", 0);
    }

    fn string(self: Reader, offset: usize) Failure![]const u8 {
        if (offset >= self.data.len) return self.report.fail("malformed ELF file: string past its end", .{});
        const len = std.mem.findScalar(u8, self.data[offset..], 0) orelse return self.report.fail("malformed ELF file: unterminated string", .{});
        return self.data[offset..][0..len];
    }

    /// The value of the symbol named `name`.
    fn symbol(self: Reader, name: []const u8) Failure!u32 {
        for (0..try self.sectionCount()) |i| {
            const header = try self.sectionOffset(i);
            if (try self.field(std.elf.Elf32.Shdr, "type", header) != @backingInt(std.elf.SHT.SYMTAB)) continue;
            const offset = try self.field(std.elf.Elf32.Shdr, "offset", header);
            const size = try self.field(std.elf.Elf32.Shdr, "size", header);
            const strtab = try self.field(std.elf.Elf32.Shdr, "offset", try self.sectionOffset(try self.field(std.elf.Elf32.Shdr, "link", header)));
            var at: usize = offset;
            while (at + @sizeOf(std.elf.Elf32.Sym) <= offset + size) : (at += @sizeOf(std.elf.Elf32.Sym)) {
                const sym_name = try self.string(strtab + try self.field(std.elf.Elf32.Sym, "name", at));
                if (std.mem.eql(u8, sym_name, name)) return self.field(std.elf.Elf32.Sym, "value", at);
            }
        }
        return self.report.fail("the executable has no symbol `{s}`", .{name});
    }

    /// The word at virtual address `address`, from the section holding it.
    fn word(self: Reader, address: u32) Failure!u32 {
        for (0..try self.sectionCount()) |i| {
            const header = try self.sectionOffset(i);
            if (try self.field(std.elf.Elf32.Shdr, "type", header) == @backingInt(std.elf.SHT.NOBITS)) continue;
            const sh_addr = try self.field(std.elf.Elf32.Shdr, "addr", header);
            const size = try self.field(std.elf.Elf32.Shdr, "size", header);
            if (sh_addr == 0 or address < sh_addr or address + 4 > sh_addr + size) continue;
            return self.int(u32, try self.field(std.elf.Elf32.Shdr, "offset", header) + (address - sh_addr));
        }
        return self.report.fail("no section of the executable holds address 0x{x}", .{address});
    }
};

/// The object is an ARM ELF32 relocatable for the hard-float EABI, and its
/// `.ARM.attributes` say arguments go in VFP registers. The writer's own tests
/// pin the section's other attributes.
fn checkObject(r: Reader) Failure!void {
    const Ehdr = std.elf.Elf32.Ehdr;
    if (r.data.len < @sizeOf(Ehdr) or !std.mem.eql(u8, r.data[0..4], std.elf.MAGIC)) return r.report.fail("the smoke object is not ELF", .{});
    if (r.data[std.elf.EI.CLASS] != @backingInt(std.elf.CLASS.@"32")) return r.report.fail("the smoke object is not ELF32", .{});
    if (try r.field(Ehdr, "type", 0) != @backingInt(std.elf.ET.REL)) return r.report.fail("the smoke object is not relocatable", .{});
    if (try r.field(Ehdr, "machine", 0) != @backingInt(std.elf.EM.ARM)) return r.report.fail("the smoke object's machine is not ARM", .{});
    const flags = try r.field(Ehdr, "flags", 0);
    if (flags != 0x0500_0400) return r.report.fail("the smoke object's flags are 0x{x}, expected 0x5000400 (EABI5, hard float)", .{flags});
    for (0..try r.sectionCount()) |i| {
        const header = try r.sectionOffset(i);
        if (try r.field(std.elf.Elf32.Shdr, "type", header) != sht_arm_attributes) continue;
        const offset = try r.field(std.elf.Elf32.Shdr, "offset", header);
        const size = try r.field(std.elf.Elf32.Shdr, "size", header);
        if (offset + size > r.data.len) return r.report.fail("malformed ELF file: section past its end", .{});
        const vfp_args = try fileAttribute(r.data[offset..][0..size], tag_abi_vfp_args, r.report) orelse
            return r.report.fail("the smoke object's attributes have no Tag_ABI_VFP_args", .{});
        if (vfp_args != 1) return r.report.fail("the smoke object's Tag_ABI_VFP_args is {d}, expected 1 (hard float)", .{vfp_args});
        return;
    }
    return r.report.fail("the smoke object has no .ARM.attributes section", .{});
}

/// The ELF section type of `.ARM.attributes`.
const sht_arm_attributes = 0x7000_0003;
/// The attribute tags read here.
const tag_file = 1;
const tag_abi_vfp_args = 28;

/// The value of integer attribute `wanted` in the file-scope set of the
/// "aeabi" subsection, or null when the set does not state it. The layout:
/// format version 'A', then subsections (size, vendor name, then attribute
/// sets, each a tag, a size and tag/value pairs). Tags 4, 5 and 67, and odd
/// tags above 32, carry a string; the others a ULEB128 number.
fn fileAttribute(section: []const u8, wanted: u64, report: Report) Failure!?u64 {
    var at: usize = 0;
    if (section.len == 0 or section[0] != 'A') return report.fail("malformed .ARM.attributes: no format version 'A'", .{});
    at += 1;
    while (at < section.len) {
        const subsection_end = try attributeEnd(section, at, at, report);
        at += 4;
        const vendor_len = std.mem.findScalar(u8, section[at..subsection_end], 0) orelse return report.fail("malformed .ARM.attributes: unterminated vendor name", .{});
        const vendor = section[at..][0..vendor_len];
        at += vendor_len + 1;
        if (!std.mem.eql(u8, vendor, "aeabi")) {
            at = subsection_end;
            continue;
        }
        while (at < subsection_end) {
            const set_start = at;
            const set_tag = try uleb(section[0..subsection_end], &at, report);
            const set_end = try attributeEnd(section[0..subsection_end], set_start, at, report);
            at += 4;
            if (set_tag != tag_file) {
                at = set_end;
                continue;
            }
            while (at < set_end) {
                const tag = try uleb(section[0..set_end], &at, report);
                if (tag == 4 or tag == 5 or tag == 67 or (tag > 32 and tag % 2 == 1)) {
                    const len = std.mem.findScalar(u8, section[at..set_end], 0) orelse return report.fail("malformed .ARM.attributes: unterminated string", .{});
                    at += len + 1;
                    continue;
                }
                const value = try uleb(section[0..set_end], &at, report);
                if (tag == wanted) return value;
            }
        }
    }
    return null;
}

/// Where a subsection or attribute set starting at `start` ends, from the
/// little-endian size at `size_at`, which counts from `start`. Fails when
/// that end falls before the size's own end or past `bytes`.
fn attributeEnd(bytes: []const u8, start: usize, size_at: usize, report: Report) Failure!usize {
    if (size_at + 4 > bytes.len) return report.fail("malformed .ARM.attributes: size past its end", .{});
    const end = start + std.mem.readInt(u32, bytes[size_at..][0..4], .little);
    if (end < size_at + 4 or end > bytes.len) return report.fail("malformed .ARM.attributes: size out of range", .{});
    return end;
}

/// A ULEB128 number at `at`, which moves past it.
fn uleb(bytes: []const u8, at: *usize, report: Report) Failure!u64 {
    var value: u64 = 0;
    var shift: u7 = 0;
    while (at.* < bytes.len and shift < 64) : (shift += 7) {
        const byte = bytes[at.*];
        at.* += 1;
        value |= @as(u64, byte & 0x7F) << @intCast(shift);
        if (byte & 0x80 == 0) return value;
    }
    return report.fail("malformed .ARM.attributes: number past its end", .{});
}

/// The linker resolved each relocation to its target: the `bl` reaches
/// `puts`, the `movw`/`movt`/`add` sequence the table, and the table entry
/// the message.
fn checkExecutable(r: Reader, smoke: SmokeObject) Failure!void {
    const function: u32 = try r.symbol("roc_link_smoke");
    const puts = try r.symbol("puts");
    const table = try r.symbol("roc_link_smoke_table");
    const message_addr = try r.symbol("roc_link_smoke_message");

    // A32 reads PC as the instruction's address plus 8.
    const call_addr = function + @as(u32, @intCast(smoke.call_at));
    const bl = try r.word(call_addr);
    if (bl >> 24 != 0xEB) return r.report.fail("the call at 0x{x} is 0x{x:0>8}, not a bl", .{ call_addr, bl });
    const words: i24 = @bitCast(@as(u24, @truncate(bl)));
    const call_target = call_addr +% 8 +% @as(u32, @bitCast(@as(i32, words) * 4));
    if (call_target != puts) return r.report.fail("the bl at 0x{x} reaches 0x{x}, but puts is at 0x{x}", .{ call_addr, call_target, puts });

    const movw_addr = function + @as(u32, @intCast(smoke.address_at));
    const movw = try r.word(movw_addr);
    const movt = try r.word(movw_addr + 4);
    if (movw & 0xFFF0_0000 != 0xE300_0000) return r.report.fail("the instruction at 0x{x} is 0x{x:0>8}, not a movw", .{ movw_addr, movw });
    if (movt & 0xFFF0_0000 != 0xE340_0000) return r.report.fail("the instruction at 0x{x} is 0x{x:0>8}, not a movt", .{ movw_addr + 4, movt });
    const offset = @as(u32, movImmediate(movt)) << 16 | movImmediate(movw);
    // The add is two instructions after the movw, and reads PC as its own
    // address plus 8.
    const add_pc = movw_addr + 8 + 8;
    if (add_pc +% offset != table) return r.report.fail("the movw/movt at 0x{x} reach 0x{x}, but the table is at 0x{x}", .{ movw_addr, add_pc +% offset, table });

    const entry = try r.word(table);
    if (entry != message_addr) return r.report.fail("the table entry holds 0x{x}, but the message is at 0x{x}", .{ entry, message_addr });
}

/// The 16-bit immediate of an A32 `movw` or `movt`: imm4 (bits 19:16) and
/// imm12.
fn movImmediate(inst: u32) u16 {
    return @intCast(((inst >> 4) & 0xF000) | (inst & 0x0FFF));
}

test "the smoke object passes its own header check" {
    const smoke = try buildObject(std.testing.allocator);
    defer std.testing.allocator.free(smoke.bytes);
    var buffer: [256]u8 = undefined;
    var discard = Io.Writer.fixed(&buffer);
    try checkObject(.{ .data = smoke.bytes, .report = .{ .writer = &discard } });
}

test "movImmediate joins imm4 and imm12" {
    try std.testing.expectEqual(@as(u16, 0xFFF0), movImmediate(0xE30F0FF0));
    try std.testing.expectEqual(@as(u16, 0x1234), movImmediate(0xE3410234));
}

test "fileAttribute finds Tag_ABI_VFP_args past string and number attributes" {
    // 'A', subsection size 27, "aeabi", Tag_File size 17:
    // Tag_CPU_name "7-A", Tag_CPU_arch 10, Tag_ABI_VFP_args 1, then a
    // number needing two ULEB128 bytes (Tag_ABI_align_needed 200).
    const section = "A" ++ "\x1b\x00\x00\x00" ++ "aeabi\x00" ++ "\x01\x11\x00\x00\x00" ++
        "\x05" ++ "7-A\x00" ++ "\x06\x0a" ++ "\x1c\x01" ++ "\x18\xc8\x01";
    var buffer: [256]u8 = undefined;
    var discard = Io.Writer.fixed(&buffer);
    const report: Report = .{ .writer = &discard };
    try std.testing.expectEqual(@as(?u64, 1), try fileAttribute(section, tag_abi_vfp_args, report));
    try std.testing.expectEqual(@as(?u64, 200), try fileAttribute(section, 24, report));
    try std.testing.expectEqual(@as(?u64, null), try fileAttribute(section, 12, report));
    try std.testing.expectError(error.Reported, fileAttribute(section[0 .. section.len - 1], tag_abi_vfp_args, report));
}
