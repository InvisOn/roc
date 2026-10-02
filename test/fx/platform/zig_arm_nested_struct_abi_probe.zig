//! Detector for the Zig bug that `host.zig` works around (search it for
//! `work_around_zig_arm_nested_struct_bug`).
//!
//! Zig 0.16 passes a by-value `extern struct` that contains another struct at
//! an even core register on arm, as if it were 8-byte aligned. AAPCS32 (and
//! clang) start it at the next free register. Zig issue:
//! https://codeberg.org/ziglang/zig/issues/37018. See also "Zig 0.16 passes nested
//! `extern struct` arguments off-ABI on arm" in
//! `projects/big/arm32-dev-backend-issues.md`.
//!
//! The test calls a nested-struct function through a flat signature whose
//! argument placement Zig gets right: the result pointer in r0 and the three
//! words in r1-r3, exactly where AAPCS32 puts the nested struct. It EXPECTS
//! the bug. When a Zig upgrade fixes it, this test fails and says to remove
//! the workaround.
//!
//! Run it on arm (under qemu here, or natively on an arm32 board):
//!
//!     zig test -target arm-linux-musleabihf --test-cmd qemu-arm-static \
//!         --test-cmd-bin test/fx/platform/zig_arm_nested_struct_abi_probe.zig
//!
//! On any other architecture the test is skipped.

const std = @import("std");
const builtin = @import("builtin");

const Words = extern struct { a: u32, b: u32, c: u32 };
const Nested = extern struct { inner: Words };

/// Zig lowers `nested`'s parameter the buggy way on arm.
fn takeNested(nested: Nested) callconv(.c) Words {
    return nested.inner;
}

/// The same call as AAPCS32 lays it out: result pointer, then three words.
const FlatAbi = *const fn (u32, u32, u32) callconv(.c) Words;

test "Zig still passes a nested extern struct off-ABI on arm (the fx host works around this)" {
    if (builtin.cpu.arch != .arm) return error.SkipZigTest;

    const call: FlatAbi = @ptrCast(&takeNested);
    const got = call(1, 2, 3);

    if (got.a == 1 and got.b == 2 and got.c == 3) {
        std.debug.print(
            \\
            \\Zig now passes nested extern structs per AAPCS32: the bug is FIXED.
            \\Remove the workaround in test/fx/platform/host.zig (see the comment at
            \\`work_around_zig_arm_nested_struct_bug`), delete this probe, and update
            \\projects/big/arm32-dev-backend-issues.md.
            \\
        , .{});
        return error.ZigNestedStructAbiBugFixed;
    }
    // The bug reads the struct one register late: r2, r3, then the stack.
    try std.testing.expectEqual(@as(u32, 2), got.a);
    try std.testing.expectEqual(@as(u32, 3), got.b);
}
