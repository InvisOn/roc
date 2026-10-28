//! The instruction sets the dev backend emits, and the rule for deciding
//! between them.

const std = @import("std");
const roc_target = @import("roc_target");
const RocTarget = roc_target.RocTarget;

/// The instruction set a dev-backend component is instantiated for. Every
/// architecture decision in the shared driver (`LirCodeGen`, `FrameBuilder`,
/// `CallingConvention`) is either an exhaustive `switch` on this or a
/// `binaryIs` test, which refuses to compile for an ISA the site was not
/// written for; neither can silently route one ISA into another's code path.
pub const Isa = enum {
    x86_64,
    aarch64,
    arm32,

    /// A two-way x86_64/aarch64 decision written before arm32 existed. It is a
    /// compile error on arm32, so arm32 support must first turn the calling
    /// site into an exhaustive `switch` on the ISA.
    pub inline fn binaryIs(comptime self: Isa, comptime which: Isa) bool {
        comptime std.debug.assert(which != .arm32);
        if (self == .arm32) {
            @compileError("arm32: a two-way x86_64/aarch64 decision in the dev backend was reached; convert the calling site to an exhaustive switch on the ISA");
        }
        return self == which;
    }
};

/// The instruction set that `target` compiles to in the dev backend.
pub fn isaOf(comptime target: RocTarget) Isa {
    return switch (roc_target.classifyCpuArch(target.toCpuArch())) {
        .x86_64 => .x86_64,
        .aarch64, .aarch64_be => .aarch64,
        .arm => .arm32,
        .wasm32, .other => @compileError("the dev backend serves only x86_64, aarch64 and arm32 targets"),
    };
}

test "isaOf maps every native RocTarget" {
    try std.testing.expectEqual(Isa.x86_64, comptime isaOf(.x64musl));
    try std.testing.expectEqual(Isa.aarch64, comptime isaOf(.arm64mac));
    try std.testing.expectEqual(Isa.arm32, comptime isaOf(.arm32musl));
    try std.testing.expect(comptime Isa.aarch64.binaryIs(.aarch64));
    try std.testing.expect(comptime !Isa.x86_64.binaryIs(.aarch64));
}
