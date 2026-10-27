//! The instruction sets the dev backend emits, and the rule for deciding
//! between them.

const std = @import("std");
const roc_target = @import("roc_target");
const RocTarget = roc_target.RocTarget;

/// The instruction set a dev-backend component is instantiated for. Every
/// instruction-set decision in the shared driver (`LirCodeGen`,
/// `FrameBuilder`, `CallingConvention`) is either an exhaustive `switch` on
/// this or a `binaryIs` test.
pub const Isa = enum {
    x86_64,
    aarch64,

    /// A two-way x86_64/aarch64 decision, valid only while the backend has
    /// exactly these two instruction sets. Adding a third makes every call a
    /// compile error, so each calling site has to become a `switch` with its
    /// own answer for the new ISA rather than silently taking whichever
    /// branch its `else` happens to be.
    pub inline fn binaryIs(comptime self: Isa, comptime which: Isa) bool {
        if (@typeInfo(Isa).@"enum".field_names.len != 2) {
            @compileError("binaryIs is a two-way test; replace it with a switch over Isa at this site");
        }
        return self == which;
    }
};

/// The instruction set that `target` compiles to in the dev backend. Both
/// emitters write little-endian code, so big-endian aarch64 is rejected with
/// the other architectures.
pub fn isaOf(comptime target: RocTarget) Isa {
    return switch (roc_target.classifyCpuArch(target.toCpuArch())) {
        .x86_64 => .x86_64,
        .aarch64 => .aarch64,
        .aarch64_be, .arm, .wasm32, .other => @compileError("the dev backend serves only x86_64 and little-endian aarch64 targets"),
    };
}

test "isaOf maps the native RocTargets" {
    try std.testing.expectEqual(Isa.x86_64, comptime isaOf(.x64musl));
    try std.testing.expectEqual(Isa.x86_64, comptime isaOf(.x64v1win));
    try std.testing.expectEqual(Isa.aarch64, comptime isaOf(.arm64mac));
}

test "binaryIs answers each pair of instruction sets" {
    try std.testing.expect(comptime Isa.x86_64.binaryIs(.x86_64));
    try std.testing.expect(comptime !Isa.x86_64.binaryIs(.aarch64));
}
