//! AAPCS32 VFP variant (32-bit Arm Procedure Call Standard, hard-float).
//!
//! Used by the `arm-*-linux-gnueabihf` and `arm-*-linux-musleabihf` targets.
//! See: https://github.com/ARM-software/abi-aa/blob/main/aapcs32/aapcs32.rst
//!
//! Integer facts that differ from the 64-bit ABIs: 64-bit scalars occupy an
//! even-aligned core register pair (r0:r1 or r2:r3) and are never split
//! between registers and the stack; composites may be split (rule C.5); stack
//! argument slots are 4 bytes with doublewords 8-byte aligned; SP is 8-byte
//! aligned at every public interface. f32 arguments use s0-s15 and f64 use
//! d0-d7 with back-filling.

const std = @import("std");
const Registers = @import("Registers.zig");
const GeneralReg = Registers.GeneralReg;
const FloatReg = Registers.FloatReg;

/// AAPCS32 calling convention
pub const Call = @This();

/// Frame pointer register
pub const BASE_PTR_REG: GeneralReg = .r11;

/// Stack pointer register
pub const STACK_PTR_REG: GeneralReg = .r13;

/// Link register (return address)
pub const LINK_REG: GeneralReg = .r14;

/// Intra-procedure-call scratch register. Linker veneers and PLT stubs may
/// clobber it, so it is never live across a call.
pub const SCRATCH_REG: GeneralReg = .r12;

/// Registers used for passing integer/pointer arguments (in order)
pub const GENERAL_PARAM_REGS = [_]GeneralReg{ .r0, .r1, .r2, .r3 };

/// Registers used for returning integer/pointer values (r0:r1 for 64-bit
/// scalars)
pub const GENERAL_RETURN_REGS = [_]GeneralReg{ .r0, .r1 };

/// Registers used for passing floating-point arguments, as D registers.
/// f32 arguments use the S halves s0-s15 of these.
pub const FLOAT_PARAM_REGS = [_]FloatReg{ .d0, .d1, .d2, .d3, .d4, .d5, .d6, .d7 };

/// Registers used for returning floating-point values (homogeneous
/// floating-point aggregates use up to four consecutive S or D registers)
pub const FLOAT_RETURN_REGS = [_]FloatReg{ .d0, .d1, .d2, .d3 };

/// Caller-saved (volatile) general registers
pub const CALLER_SAVED_GENERAL = [_]GeneralReg{ .r0, .r1, .r2, .r3, .r12 };

/// Callee-saved (non-volatile) general registers
pub const CALLEE_SAVED_GENERAL = [_]GeneralReg{
    .r4, .r5, .r6, .r7, .r8, .r9, .r10,
    // r11 (FP) and r14 (LR) are also preserved but handled by the frame
};

/// Caller-saved floating-point registers
pub const CALLER_SAVED_FLOAT = [_]FloatReg{
    .d0,  .d1,  .d2,  .d3,  .d4,  .d5,  .d6,  .d7,
    .d16, .d17, .d18, .d19, .d20, .d21, .d22, .d23,
    .d24, .d25, .d26, .d27, .d28, .d29, .d30, .d31,
};

/// Callee-saved floating-point registers
pub const CALLEE_SAVED_FLOAT = [_]FloatReg{ .d8, .d9, .d10, .d11, .d12, .d13, .d14, .d15 };

/// No shadow space required
pub const SHADOW_SPACE_SIZE: u8 = 0;

/// Stack alignment at public interfaces (8 bytes)
pub const STACK_ALIGNMENT: u8 = 8;

/// Check if a general register is callee-saved
pub fn isCalleeSaved(reg: GeneralReg) bool {
    return switch (reg) {
        .r4, .r5, .r6, .r7, .r8, .r9, .r10, .r11, .r14 => true,
        .r0, .r1, .r2, .r3, .r12, .r13, .r15 => false,
    };
}

/// Check if a float register is callee-saved
pub fn isFloatCalleeSaved(reg: FloatReg) bool {
    return reg.enc() >= 8 and reg.enc() <= 15;
}

/// Bitmask of caller-saved general registers available for allocation.
/// r12 is excluded because it is reserved as the scratch register (the
/// x86_64 R11 and aarch64 X9 analogue).
pub const CALLER_SAVED_GENERAL_MASK: u16 =
    GeneralReg.r0.listBit() |
    GeneralReg.r1.listBit() |
    GeneralReg.r2.listBit() |
    GeneralReg.r3.listBit();

/// Bitmask of callee-saved general registers available for allocation.
/// r11 is the frame pointer and is not allocatable.
pub const CALLEE_SAVED_GENERAL_MASK: u16 =
    GeneralReg.r4.listBit() |
    GeneralReg.r5.listBit() |
    GeneralReg.r6.listBit() |
    GeneralReg.r7.listBit() |
    GeneralReg.r8.listBit() |
    GeneralReg.r9.listBit() |
    GeneralReg.r10.listBit();

/// Bitmask of caller-saved float registers (D view)
/// d0-d7 and d16-d31 are caller-saved
pub const CALLER_SAVED_FLOAT_MASK: u32 =
    0x000000FF | // d0-d7
    0xFFFF0000; // d16-d31

/// Bitmask of callee-saved float registers (D view): d8-d15
pub const CALLEE_SAVED_FLOAT_MASK: u32 = 0x0000FF00;

test "calling convention constants" {
    try std.testing.expectEqual(GeneralReg.fp, BASE_PTR_REG);
    try std.testing.expectEqual(GeneralReg.sp, STACK_PTR_REG);
    try std.testing.expectEqual(GeneralReg.ip, SCRATCH_REG);
    try std.testing.expectEqual(@as(usize, 4), GENERAL_PARAM_REGS.len);
    try std.testing.expectEqual(@as(usize, 8), FLOAT_PARAM_REGS.len);
}

test "callee-saved detection" {
    try std.testing.expect(isCalleeSaved(.r4));
    try std.testing.expect(isCalleeSaved(.r10));
    try std.testing.expect(isCalleeSaved(.fp));
    try std.testing.expect(!isCalleeSaved(.r0));
    try std.testing.expect(!isCalleeSaved(.ip));

    try std.testing.expect(isFloatCalleeSaved(.d8));
    try std.testing.expect(isFloatCalleeSaved(.d15));
    try std.testing.expect(!isFloatCalleeSaved(.d0));
    try std.testing.expect(!isFloatCalleeSaved(.d16));
}

test "allocation masks match the register lists" {
    var callee: u16 = 0;
    for (CALLEE_SAVED_GENERAL) |reg| callee |= reg.listBit();
    try std.testing.expectEqual(callee, CALLEE_SAVED_GENERAL_MASK);

    var caller_float: u32 = 0;
    for (CALLER_SAVED_FLOAT) |reg| caller_float |= @as(u32, 1) << reg.enc();
    try std.testing.expectEqual(caller_float, CALLER_SAVED_FLOAT_MASK);

    var callee_float: u32 = 0;
    for (CALLEE_SAVED_FLOAT) |reg| callee_float |= @as(u32, 1) << reg.enc();
    try std.testing.expectEqual(callee_float, CALLEE_SAVED_FLOAT_MASK);

    // The scratch register is never allocatable.
    try std.testing.expectEqual(@as(u16, 0), (CALLER_SAVED_GENERAL_MASK | CALLEE_SAVED_GENERAL_MASK) & SCRATCH_REG.listBit());
}
