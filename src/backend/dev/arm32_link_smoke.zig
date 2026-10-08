//! End-to-end smoke program for the arm32 encoder and ELF32 writer.
//!
//! Builds one relocatable arm32 object with `arm32.Emit` and `ElfWriter` and
//! writes it to the path given as the only argument. The object defines
//! `roc_link_smoke(void) -> int`, which exercises every arm32 relocation kind
//! the dev backend emits:
//!
//! - `R_ARM_MOVW_PREL_NC` / `R_ARM_MOVT_PREL`: the PC-relative address of a
//!   pointer table in `.rodata`;
//! - `R_ARM_ABS32`: the table's entry, the address of a message string;
//! - `R_ARM_CALL`: a call to the C library's `puts` with that string.
//!
//! It then returns 42. `ci/arm32_link_smoke.py` links the object with a C
//! `main` through `zig cc -target arm-linux-musleabihf` (LLD) and runs it under
//! `qemu-arm-static`. It lives in `src/backend/dev/` so that `zig run` can
//! import both `arm32/` and `object/` from one module root.

const std = @import("std");
const arm32 = @import("arm32/mod.zig");
const elf = @import("object/elf.zig");

/// The message the smoke function prints.
pub const message = "arm32 link smoke: encoder, ELF32 writer and relocations work";

/// Write the smoke object to the absolute path in the first argument.
pub fn main(init: std.process.Init) void {
    const gpa = init.gpa;
    const args = init.minimal.args.toSlice(gpa) catch |err| die("read arguments", err);
    defer gpa.free(args);
    if (args.len != 2 or !std.fs.path.isAbsolute(args[1])) {
        std.debug.print("usage: arm32_link_smoke <absolute path of output.o>\n", .{});
        std.process.exit(2);
    }

    const object = buildObject(gpa) catch |err| die("build the object", err);
    defer gpa.free(object);
    const file = std.Io.Dir.createFileAbsolute(init.io, args[1], .{}) catch |err| die("create the output file", err);
    defer file.close(init.io);
    file.writeStreamingAll(init.io, object) catch |err| die("write the output file", err);
}

/// The smoke object's bytes, owned by the caller.
pub fn buildObject(gpa: std.mem.Allocator) std.mem.Allocator.Error![]u8 {
    var e = arm32.MuslEmit.init(gpa);
    defer e.deinit();
    // push {r4, lr}: keeps SP 8-byte aligned across the call (AAPCS32).
    try e.push(arm32.GeneralReg.r4.listBit() | arm32.GeneralReg.lr.listBit());
    // r0 = &table
    const table_addr_at = try e.pcRelAddress(.r0);
    // r0 = table[0] (the message address, relocated by R_ARM_ABS32)
    try e.ldrRegMem(.r0, .r0, 0);
    // puts(r0)
    const call_at = e.codeOffset();
    try e.bl(0);
    // return 42
    try e.movRegImm32(.r0, 42);
    try e.pop(arm32.GeneralReg.r4.listBit() | arm32.GeneralReg.pc.listBit());

    // .rodata: the message, then a word-aligned table holding its address.
    const message_z = message ++ "\x00";
    const table_offset = comptime std.mem.alignForward(usize, message_z.len, 4);
    var rodata: [table_offset + 4]u8 = @splat(0);
    @memcpy(rodata[0..message_z.len], message_z);

    var w = try elf.ElfWriter.init(gpa, .arm, .none);
    defer w.deinit();
    w.setCode(e.buf.items);
    w.setRodata(&rodata);
    // Local symbols precede global ones, as ELF requires.
    const message_sym = try w.addSymbol(.{ .name = "roc_link_smoke_message", .section = .rodata, .offset = 0, .size = message_z.len, .is_global = false, .is_function = false });
    const table_sym = try w.addSymbol(.{ .name = "roc_link_smoke_table", .section = .rodata, .offset = table_offset, .size = 4, .is_global = false, .is_function = false });
    _ = try w.addSymbol(.{ .name = "roc_link_smoke", .section = .text, .offset = 0, .size = e.buf.items.len, .is_global = true, .is_function = true });
    const puts_sym = try w.addExternalSymbol("puts");
    try w.addTextDataRelocation(table_addr_at, table_sym, .arm_movw_prel);
    try w.addTextDataRelocation(table_addr_at + 4, table_sym, .arm_movt_prel);
    try w.addTextRelocation(call_at, puts_sym, -8);
    try w.addRodataRelocation(table_offset, message_sym, 0);

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    try w.write(&out);
    return out.toOwnedSlice(gpa);
}

fn die(what: []const u8, err: anytype) noreturn {
    std.debug.print("arm32_link_smoke: failed to {s}: {s}\n", .{ what, @errorName(err) });
    std.process.exit(1);
}

test "the smoke object is an ARM ELF32 relocatable with the hard-float EABI flags" {
    const object = try buildObject(std.testing.allocator);
    defer std.testing.allocator.free(object);
    try std.testing.expectEqualSlices(u8, "\x7fELF", object[0..4]);
    try std.testing.expectEqual(@as(u8, 1), object[4]); // ELFCLASS32
    try std.testing.expectEqual(@as(u8, 1), object[5]); // little-endian
    try std.testing.expectEqual(@as(u16, 1), std.mem.readInt(u16, object[16..18], .little)); // ET_REL
    try std.testing.expectEqual(@as(u16, 40), std.mem.readInt(u16, object[18..20], .little)); // EM_ARM
    try std.testing.expectEqual(@as(u32, 0x0500_0400), std.mem.readInt(u32, object[36..40], .little)); // EABI5, hard float
    try std.testing.expect(std.mem.find(u8, object, message) != null);
}
