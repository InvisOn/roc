//! The instruction sets the dev backend emits, and the rule for deciding
//! between them.

const std = @import("std");
const roc_target = @import("roc_target");
const RocTarget = roc_target.RocTarget;

/// The instruction set a dev-backend component is instantiated for. Every
/// architecture decision in the shared driver (`LirCodeGen`, `FrameBuilder`,
/// `CallingConvention`) is either an exhaustive `switch` on this or a
/// `binaryIs` test.
pub const Isa = enum {
    x86_64,
    aarch64,

    /// A two-way x86_64/aarch64 decision. The `switch` lists every ISA, so
    /// adding an ISA makes this a compile error until each calling site has
    /// been given its own answer for the new ISA, rather than silently taking
    /// whichever branch its `else` happens to be.
    pub inline fn binaryIs(comptime self: Isa, comptime which: Isa) bool {
        return switch (self) {
            .x86_64, .aarch64 => self == which,
        };
    }
};

/// The instruction set that `target` compiles to in the dev backend.
pub fn isaOf(comptime target: RocTarget) Isa {
    return switch (roc_target.classifyCpuArch(target.toCpuArch())) {
        .x86_64 => .x86_64,
        .aarch64, .aarch64_be => .aarch64,
        .arm, .wasm32, .other => @compileError("the dev backend serves only x86_64 and aarch64 targets"),
    };
}

test "isaOf maps the native RocTargets" {
    try std.testing.expectEqual(Isa.x86_64, comptime isaOf(.x64musl));
    try std.testing.expectEqual(Isa.x86_64, comptime isaOf(.x64v1win));
    try std.testing.expectEqual(Isa.aarch64, comptime isaOf(.arm64mac));
    try std.testing.expect(comptime Isa.aarch64.binaryIs(.aarch64));
    try std.testing.expect(comptime !Isa.x86_64.binaryIs(.aarch64));
}
