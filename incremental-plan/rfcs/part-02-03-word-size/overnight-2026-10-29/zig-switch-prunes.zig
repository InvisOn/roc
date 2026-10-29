// Does a switch on a comptime-known enum analyze only the taken prong,
// like `if (comptime cond)` does? Each backend has its own register enum,
// so `.RAX` must not be analyzed when the target is aarch64.
const std = @import("std");

const Isa = enum { x86_64, aarch64 };
const X86Reg = enum { RAX, R11 };
const A64Reg = enum { X0, X9 };

fn Gen(comptime isa: Isa) type {
    const Reg = switch (isa) {
        .x86_64 => X86Reg,
        .aarch64 => A64Reg,
    };
    return struct {
        // Expression form: picks a register literal of the right enum.
        const scratch: Reg = switch (isa) {
            .x86_64 => .R11,
            .aarch64 => .X9,
        };

        // Statement form inside a runtime function, with arch-only calls.
        fn emit(out: *std.ArrayList(u8), gpa: std.mem.Allocator) !void {
            switch (isa) {
                .x86_64 => try out.appendSlice(gpa, x86Only(.RAX)),
                .aarch64 => try out.appendSlice(gpa, a64Only(.X0)),
            }
        }

        // Combined condition written as a bool-valued switch.
        fn sret(indirect: bool) bool {
            return switch (isa) {
                .aarch64 => indirect,
                .x86_64 => false,
            };
        }
    };
}

fn x86Only(r: X86Reg) []const u8 {
    return @tagName(r);
}
fn a64Only(r: A64Reg) []const u8 {
    return @tagName(r);
}

test "comptime switch prunes the other backend's prong" {
    const gpa = std.testing.allocator;
    inline for (.{ Isa.x86_64, Isa.aarch64 }) |isa| {
        const G = Gen(isa);
        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(gpa);
        try G.emit(&out, gpa);
        _ = G.scratch;
        try std.testing.expectEqual(isa == .aarch64, G.sret(true));
    }
}
