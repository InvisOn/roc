//! Generate the byte-exact arm32 encoder tests from the assembler.
//!
//! Each entry of ci/arm32_encoding_oracle.s pairs A32 assembly with the arm32
//! `Emit` call that must produce the same bytes:
//!
//!     add r0, r1, r2                      | addRegRegReg(.r0, .r1, .r2)
//!     movw r3, #0x5678; movt r3, #0x1234  | movRegImm32(.r3, 0x12345678)
//!
//! `;` separates the instructions of one entry. The call's arguments follow
//! it as written, so a struct or union argument names its type
//! (`Operand2{ ... }`). Lines starting with `@` are comments.
//!
//! The entries are assembled with `zig cc -target arm-linux-musleabihf`
//! (LLVM's assembler), and the expected bytes are written to
//! src/backend/dev/arm32/encoding_oracle_tests.zig as one Zig test per entry,
//! so `zig build test` needs no external tool.
//!
//!     zig build run-arm32-encoding-oracle         # regenerate
//!     zig build run-check-arm32-encoding-oracle   # fail if out of date
//!
//! Both also fail when an emitter of arm32 `Emit` has no entry.
//!
//! Usage: arm32-encoding-oracle <zig executable> <work directory> [--check]

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const usage = "usage: arm32-encoding-oracle <zig executable> <work directory> [--check]";

const source_path = "ci/arm32_encoding_oracle.s";
const output_path = "src/backend/dev/arm32/encoding_oracle_tests.zig";
const emit_path = "src/backend/dev/arm32/Emit.zig";

const asm_prelude =
    \\.syntax unified
    \\.arch armv7-a
    \\.fpu neon-vfpv3
    \\.arm
    \\.text
    \\
;

/// ELF machine number of 32-bit ARM.
const em_arm = 40;
/// ELF section types read here.
const sht_symtab = 2;
const sht_nobits = 8;
/// The ARM relocation type LLVM leaves on every `bl`.
const r_arm_call = 28;

/// `Emit` methods taking `self: *Self` that emit nothing.
const non_emitting = [_][]const u8{"deinit"};

const Entry = struct {
    /// Line in the `.s` file, for messages.
    line: usize,
    instructions: []const []const u8,
    call: []const u8,
    bytes: []const u8 = &.{},
};

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
    const check = if (args.next()) |flag| blk: {
        if (!std.mem.eql(u8, flag, "--check")) return report.fail("unknown option `{s}`\n" ++ usage, .{flag});
        break :blk true;
    } else false;
    if (args.next()) |extra| return report.fail("unexpected argument `{s}`\n" ++ usage, .{extra});

    const cwd = Io.Dir.cwd();
    const source = try cwd.readFileAlloc(io, source_path, gpa, .unlimited);
    const entries = try parseSource(gpa, source, report);
    const emit_source = try cwd.readFileAlloc(io, emit_path, gpa, .unlimited);
    try checkCoverage(gpa, emit_source, entries, report);
    try assemble(gpa, io, zig_exe, work_dir, entries, report);
    const generated = try render(gpa, entries, report);

    if (check) {
        const current = cwd.readFileAlloc(io, output_path, gpa, .unlimited) catch |err| switch (err) {
            error.FileNotFound => null,
            else => return err,
        };
        if (current == null or !std.mem.eql(u8, current.?, generated)) {
            return report.fail("{s} is out of date; run `zig build run-arm32-encoding-oracle`", .{output_path});
        }
        try report.writer.print("arm32 encoding oracle: {d} entries up to date\n", .{entries.len});
        return;
    }
    try cwd.writeFile(io, .{ .sub_path = output_path, .data = generated });
    try report.writer.print("wrote {s} ({d} entries)\n", .{ output_path, entries.len });
}

/// The entries of the `.s` file, in order.
fn parseSource(gpa: Allocator, source: []const u8, report: Report) ![]Entry {
    var entries: std.ArrayList(Entry) = .empty;
    var lines = std.mem.splitScalar(u8, source, '\n');
    var line_number: usize = 0;
    while (lines.next()) |raw| {
        line_number += 1;
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0 or line[0] == '@') continue;
        const bar = std.mem.findScalar(u8, line, '|') orelse
            return report.fail("{s}:{d}: expected `asm | zig call`", .{ source_path, line_number });
        const call = std.mem.trim(u8, line[bar + 1 ..], " \t");
        var instructions: std.ArrayList([]const u8) = .empty;
        var parts = std.mem.splitScalar(u8, line[0..bar], ';');
        while (parts.next()) |part| {
            const instruction = std.mem.trim(u8, part, " \t");
            if (instruction.len != 0) try instructions.append(gpa, instruction);
        }
        if (instructions.items.len == 0 or call.len == 0) {
            return report.fail("{s}:{d}: empty assembly or Zig call", .{ source_path, line_number });
        }
        try entries.append(gpa, .{ .line = line_number, .instructions = instructions.items, .call = call });
    }
    return entries.items;
}

/// The method an entry's call names: the text before its `(`.
fn callName(entry: Entry, report: Report) ![]const u8 {
    const paren = std.mem.findScalar(u8, entry.call, '(') orelse
        return report.fail("{s}:{d}: expected `method(args)`, got `{s}`", .{ source_path, entry.line, entry.call });
    if (entry.call[entry.call.len - 1] != ')') {
        return report.fail("{s}:{d}: expected `method(args)`, got `{s}`", .{ source_path, entry.line, entry.call });
    }
    return entry.call[0..paren];
}

/// The public methods of `Emit` that take `self: *Self` and emit bytes.
fn emitterNames(gpa: Allocator, emit_source: []const u8) ![]const []const u8 {
    var names: std.ArrayList([]const u8) = .empty;
    var lines = std.mem.splitScalar(u8, emit_source, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trimStart(u8, raw, " ");
        if (!std.mem.startsWith(u8, line, "pub fn ")) continue;
        const rest = line["pub fn ".len..];
        const paren = std.mem.findScalar(u8, rest, '(') orelse continue;
        if (!std.mem.startsWith(u8, rest[paren + 1 ..], "self: *Self")) continue;
        const name = rest[0..paren];
        for (non_emitting) |skip| {
            if (std.mem.eql(u8, name, skip)) break;
        } else try names.append(gpa, name);
    }
    return names.items;
}

fn contains(names: []const []const u8, name: []const u8) bool {
    for (names) |candidate| {
        if (std.mem.eql(u8, candidate, name)) return true;
    }
    return false;
}

/// Fail unless every emitter has an entry and every entry calls an emitter.
fn checkCoverage(gpa: Allocator, emit_source: []const u8, entries: []const Entry, report: Report) !void {
    const emitters = try emitterNames(gpa, emit_source);
    var called: std.ArrayList([]const u8) = .empty;
    for (entries) |entry| try called.append(gpa, try callName(entry, report));

    var missing: Io.Writer.Allocating = .init(gpa);
    for (emitters) |name| {
        if (!contains(called.items, name)) try missing.writer.print(" {s}", .{name});
    }
    if (missing.written().len != 0) return report.fail("arm32 Emit methods without an oracle entry:{s}", .{missing.written()});

    var unknown: Io.Writer.Allocating = .init(gpa);
    for (called.items) |name| {
        if (!contains(emitters, name)) try unknown.writer.print(" {s}", .{name});
    }
    if (unknown.written().len != 0) return report.fail("oracle entries call unknown Emit methods:{s}", .{unknown.written()});
}

/// Assemble every entry and set its `bytes`.
fn assemble(gpa: Allocator, io: Io, zig_exe: []const u8, work_dir: []const u8, entries: []Entry, report: Report) !void {
    var text: Io.Writer.Allocating = .init(gpa);
    try text.writer.writeAll(asm_prelude);
    for (entries, 0..) |entry, i| {
        try text.writer.print("oracle_{d}:\n", .{i});
        for (entry.instructions) |instruction| try text.writer.print("    {s}\n", .{instruction});
    }
    try text.writer.writeAll("oracle_end:\n");

    const cwd = Io.Dir.cwd();
    try cwd.createDirPath(io, work_dir);
    const asm_path = try std.fs.path.join(gpa, &.{ work_dir, "oracle.s" });
    const obj_path = try std.fs.path.join(gpa, &.{ work_dir, "oracle.o" });
    try cwd.writeFile(io, .{ .sub_path = asm_path, .data = text.written() });

    const result = try std.process.run(gpa, io, .{
        .argv = &.{ zig_exe, "cc", "-target", "arm-linux-musleabihf", "-c", asm_path, "-o", obj_path },
    });
    if (result.term != .exited or result.term.exited != 0) {
        return report.fail("assembler failed:\n{s}", .{result.stderr});
    }
    const object = try cwd.readFileAlloc(io, obj_path, gpa, .unlimited);
    try splitObject(gpa, object, entries, report);
}

/// Little-endian ELF32 reads that fail on a truncated object.
const Elf = struct {
    data: []const u8,
    report: Report,

    fn int(self: Elf, comptime T: type, offset: usize) Failure!T {
        if (offset + @sizeOf(T) > self.data.len) return self.report.fail("malformed object: read past its end", .{});
        return std.mem.readInt(T, self.data[offset..][0..@sizeOf(T)], .little);
    }

    fn bytes(self: Elf, offset: usize, len: usize) Failure![]const u8 {
        if (offset + len > self.data.len) return self.report.fail("malformed object: section past its end", .{});
        return self.data[offset..][0..len];
    }

    fn string(self: Elf, table: []const u8, offset: usize) Failure![]const u8 {
        if (offset >= table.len) return self.report.fail("malformed object: name past its string table", .{});
        const end = std.mem.findScalarPos(u8, table, offset, 0) orelse
            return self.report.fail("malformed object: unterminated name", .{});
        return table[offset..end];
    }
};

const Section = struct {
    name: []const u8,
    type: u32,
    link: u32,
    data: []const u8,
};

const Symbol = struct {
    name: []const u8,
    value: u32,
    shndx: u16,
};

/// Read the assembler's object and cut its `.text` into the entries' bytes.
fn splitObject(gpa: Allocator, object: []const u8, entries: []Entry, report: Report) !void {
    const elf: Elf = .{ .data = object, .report = report };
    if (object.len < 52 or !std.mem.eql(u8, object[0..4], "\x7fELF")) return report.fail("assembler output is not an ELF file", .{});
    if (object[4] != 1 or object[5] != 1) return report.fail("assembler output is not little-endian ELF32", .{});
    const machine = try elf.int(u16, 18);
    if (machine != em_arm) return report.fail("assembler produced e_machine {d}, expected {d} (ARM)", .{ machine, em_arm });

    const shoff = try elf.int(u32, 32);
    const shentsize = try elf.int(u16, 46);
    const shnum = try elf.int(u16, 48);
    const shstrndx = try elf.int(u16, 50);
    const sections = try gpa.alloc(Section, shnum);
    const name_offsets = try gpa.alloc(u32, shnum);
    for (sections, name_offsets, 0..) |*section, *name_offset, i| {
        const header = shoff + i * shentsize;
        name_offset.* = try elf.int(u32, header);
        const sh_type = try elf.int(u32, header + 4);
        const offset = try elf.int(u32, header + 16);
        const size = try elf.int(u32, header + 20);
        section.* = .{
            .name = "",
            .type = sh_type,
            .link = try elf.int(u32, header + 24),
            .data = if (sh_type == sht_nobits) &.{} else try elf.bytes(offset, size),
        };
    }
    if (shstrndx >= shnum) return report.fail("malformed object: no section name table", .{});
    for (sections, name_offsets) |*section, name_offset| {
        section.name = try elf.string(sections[shstrndx].data, name_offset);
    }

    var text_index: ?usize = null;
    var rel_text: ?Section = null;
    var symtab: ?Section = null;
    for (sections, 0..) |section, i| {
        if (std.mem.eql(u8, section.name, ".text")) text_index = i;
        if (std.mem.eql(u8, section.name, ".rel.text")) rel_text = section;
        if (std.mem.eql(u8, section.name, ".rela.text")) return report.fail("assembler emitted RELA records; expected REL", .{});
        if (section.type == sht_symtab) symtab = section;
    }
    const text = sections[text_index orelse return report.fail("assembler output has no .text", .{})];
    const table = symtab orelse return report.fail("assembler output has no symbol table", .{});
    if (table.link >= shnum) return report.fail("malformed object: bad symbol string table", .{});
    const strtab = sections[table.link].data;

    const symbols = try gpa.alloc(Symbol, table.data.len / 16);
    const table_elf: Elf = .{ .data = table.data, .report = report };
    for (symbols, 0..) |*symbol, i| {
        symbol.* = .{
            .name = try elf.string(strtab, try table_elf.int(u32, i * 16)),
            .value = try table_elf.int(u32, i * 16 + 4),
            .shndx = try table_elf.int(u16, i * 16 + 14),
        };
    }

    if (rel_text) |rel| {
        // LLVM keeps every BL relocatable (R_ARM_CALL) so the linker can
        // interwork, even for local targets. When the target symbol is the
        // instruction itself, the REL addend in the instruction already equals
        // the resolved displacement, so the bytes are final. Anything else
        // would make the bytes depend on the link.
        const rel_elf: Elf = .{ .data = rel.data, .report = report };
        var offset: usize = 0;
        while (offset + 8 <= rel.data.len) : (offset += 8) {
            const r_offset = try rel_elf.int(u32, offset);
            const r_info = try rel_elf.int(u32, offset + 4);
            const symbol_index = r_info >> 8;
            if (symbol_index >= symbols.len) return report.fail("malformed object: relocation names no symbol", .{});
            const symbol = symbols[symbol_index];
            if ((r_info & 0xFF) != r_arm_call or symbol.shndx != text_index.? or symbol.value != r_offset) {
                return report.fail("an entry needs a relocation at .text+0x{x}; oracle entries must be self-contained", .{r_offset});
            }
        }
    }

    // bounds[i] is where entry i starts; bounds[entries.len] is `oracle_end`.
    const bounds = try gpa.alloc(?u32, entries.len + 1);
    @memset(bounds, null);
    for (symbols) |symbol| {
        if (!std.mem.startsWith(u8, symbol.name, "oracle_")) continue;
        const suffix = symbol.name["oracle_".len..];
        const index = if (std.mem.eql(u8, suffix, "end")) entries.len else std.fmt.parseInt(usize, suffix, 10) catch continue;
        if (index <= entries.len) bounds[index] = symbol.value;
    }
    for (entries, 0..) |*entry, i| {
        const start = bounds[i] orelse return report.fail("assembler output lacks the symbol of entry {d}", .{i});
        const end = bounds[i + 1] orelse return report.fail("assembler output lacks the symbol after entry {d}", .{i});
        if (end < start or end > text.data.len) return report.fail("malformed object: entry {d} lies outside .text", .{i});
        entry.bytes = text.data[start..end];
        if (entry.bytes.len != 4 * entry.instructions.len) {
            return report.fail("{s}:{d}: assembled to {d} bytes, expected {d}", .{ source_path, entry.line, entry.bytes.len, 4 * entry.instructions.len });
        }
    }
}

/// The generated test file, formatted as `zig fmt` would.
fn render(gpa: Allocator, entries: []const Entry, report: Report) ![]const u8 {
    var out: Io.Writer.Allocating = .init(gpa);
    const w = &out.writer;
    try w.writeAll(
        \\//! Byte-exact A32 encoding tests for arm32 `Emit`.
        \\//!
        \\//! GENERATED by ci/arm32_encoding_oracle.zig from ci/arm32_encoding_oracle.s;
        \\//! do not edit. The expected words are what `zig cc -target
        \\//! arm-linux-musleabihf` assembles each entry to. Regenerate with
        \\//! `zig build run-arm32-encoding-oracle`; CI runs
        \\//! `zig build run-check-arm32-encoding-oracle`.
        \\
        \\const std = @import("std");
        \\const emit = @import("Emit.zig");
        \\const E = emit.Emit(.arm32musl);
        \\const ModImm = emit.ModImm;
        \\const Operand2 = emit.Operand2;
        \\
        \\/// Call `method` with `args` on a fresh emitter and expect exactly the
        \\/// little-endian `words`.
        \\fn expectEncoding(comptime method: anytype, args: anytype, words: []const u32) (std.mem.Allocator.Error || error{TestExpectedEqual})!void {
        \\    var e = E.init(std.testing.allocator);
        \\    defer e.deinit();
        \\    _ = try @call(.auto, method, .{&e} ++ args);
        \\    try std.testing.expectEqual(words.len * 4, e.buf.items.len);
        \\    for (words, 0..) |word, i| {
        \\        const got = std.mem.readInt(u32, e.buf.items[i * 4 ..][0..4], .little);
        \\        if (got != word) {
        \\            std.debug.print("word {d}: expected 0x{x:0>8}, found 0x{x:0>8}\n", .{ i, word, got });
        \\            return error.TestExpectedEqual;
        \\        }
        \\    }
        \\}
        \\
        \\
    );
    var seen: std.StringHashMapUnmanaged(usize) = .empty;
    for (entries) |entry| {
        var name: Io.Writer.Allocating = .init(gpa);
        try name.writer.writeAll("arm32 encoding: ");
        for (entry.instructions, 0..) |instruction, i| {
            if (i != 0) try name.writer.writeAll("; ");
            try name.writer.writeAll(instruction);
        }
        const count = try seen.getOrPut(gpa, try gpa.dupe(u8, name.written()));
        if (count.found_existing) {
            count.value_ptr.* += 1;
            try name.writer.print(" ({d})", .{count.value_ptr.*});
        } else count.value_ptr.* = 1;

        const method = try callName(entry, report);
        const call_args = std.mem.trim(u8, entry.call[method.len + 1 .. entry.call.len - 1], " ");

        try w.writeAll("test \"");
        for (name.written()) |c| switch (c) {
            '\\' => try w.writeAll("\\\\"),
            '"' => try w.writeAll("\\\""),
            else => try w.writeByte(c),
        };
        try w.print("\" {{ try expectEncoding(E.{s}, .{{ {s} }}, &.{{ ", .{ method, call_args });
        var i: usize = 0;
        while (i < entry.bytes.len) : (i += 4) {
            if (i != 0) try w.writeAll(", ");
            try w.print("0x{x:0>8}", .{std.mem.readInt(u32, entry.bytes[i..][0..4], .little)});
        }
        try w.writeAll(" }); }\n");
    }

    const source = try gpa.dupeSentinel(u8, out.written(), 0);
    var tree = try std.zig.Ast.parse(gpa, source, .{ .mode = .zig });
    if (tree.errors.len != 0) return report.fail("the generated tests do not parse; check the Zig calls in {s}", .{source_path});
    return tree.renderAlloc(gpa);
}

test "parse entries, comments and multi-instruction lines" {
    var buffer: [256]u8 = undefined;
    var discard: Io.Writer = .fixed(&buffer);
    const report: Report = .{ .writer = &discard };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const entries = try parseSource(arena.allocator(),
        \\@ a comment
        \\
        \\add r0, r1, r2   | addRegRegReg(.r0, .r1, .r2)
        \\movw r3, #1; movt r3, #2 | movRegImm32(.r3, 0x20001)
    , report);
    try std.testing.expectEqual(@as(usize, 2), entries.len);
    try std.testing.expectEqual(@as(usize, 3), entries[0].line);
    try std.testing.expectEqualStrings("addRegRegReg(.r0, .r1, .r2)", entries[0].call);
    try std.testing.expectEqual(@as(usize, 2), entries[1].instructions.len);
    try std.testing.expectEqualStrings("movt r3, #2", entries[1].instructions[1]);
}

test "a line without a bar is rejected" {
    var buffer: [256]u8 = undefined;
    var messages: Io.Writer = .fixed(&buffer);
    const report: Report = .{ .writer = &messages };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectError(error.Reported, parseSource(arena.allocator(), "add r0, r1, r2\n", report));
    try std.testing.expectEqualStrings("ci/arm32_encoding_oracle.s:1: expected `asm | zig call`\n", messages.buffered());
}

test "emitters are the pub methods taking self: *Self" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const names = try emitterNames(arena.allocator(),
        \\        pub fn init(allocator: std.mem.Allocator) Self {
        \\        pub fn deinit(self: *Self) void {
        \\        pub fn codeOffset(self: *const Self) u64 {
        \\        fn emit32(self: *Self, inst: u32) Allocator.Error!void {
        \\        pub fn movRegReg(self: *Self, dst: GeneralReg, src: GeneralReg) Allocator.Error!void {
        \\        pub fn encodeMovwMovt(top: bool, dst: GeneralReg, imm: u16) u32 {
    );
    try std.testing.expectEqual(@as(usize, 1), names.len);
    try std.testing.expectEqualStrings("movRegReg", names[0]);
}
