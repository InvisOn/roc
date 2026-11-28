//! The registers of the AAPCS32 VFP variant (32-bit Arm Procedure Call
//! Standard, hard-float), as used by the `arm-*-linux-gnueabihf` and
//! `arm-*-linux-musleabihf` targets, and the roles the dev backend gives them.
//! See: https://github.com/ARM-software/abi-aa/blob/main/aapcs32/aapcs32.rst
//!
//! This file names registers only. Which register or stack slot each argument
//! takes (64-bit scalars in an even register pair, composites split by rule
//! C.5, VFP back-filling) belongs to the calling convention's call builder.

const std = @import("std");
const Registers = @import("Registers.zig");
const GeneralReg = Registers.GeneralReg;
const FloatReg = Registers.FloatReg;

/// Frame pointer register.
pub const BASE_PTR_REG: GeneralReg = .fp;

/// Stack pointer register.
pub const STACK_PTR_REG: GeneralReg = .sp;

/// Link register: the return address on entry.
pub const LINK_REG: GeneralReg = .lr;

/// Intra-procedure-call scratch register. Linker veneers and PLT stubs may
/// clobber it, so it is never live across a call.
pub const SCRATCH_REG: GeneralReg = .ip;

/// The register an out-of-range memory access forms its address in. Every
/// procedure saves LR in its prologue and returns by popping PC, so LR is free
/// inside a body; a formed address is consumed by the very next load or store,
/// so it is never live across a call. Using LR rather than `SCRATCH_REG`
/// leaves r12 usable as the base or the data register of any access.
pub const ADDRESS_SCRATCH_REG: GeneralReg = LINK_REG;

/// Registers that pass integer and pointer arguments, in order.
pub const GENERAL_PARAM_REGS = [_]GeneralReg{ .r0, .r1, .r2, .r3 };

/// Registers that return integer and pointer values: r0, or r0:r1 for a
/// 64-bit scalar.
pub const GENERAL_RETURN_REGS = [_]GeneralReg{ .r0, .r1 };

/// Registers that pass floating-point arguments, as D registers. An f32
/// argument uses an S half of one of these.
pub const FLOAT_PARAM_REGS = [_]FloatReg{ .d0, .d1, .d2, .d3, .d4, .d5, .d6, .d7 };

/// Registers that return floating-point values; a homogeneous floating-point
/// aggregate uses up to four consecutive S or D registers.
pub const FLOAT_RETURN_REGS = [_]FloatReg{ .d0, .d1, .d2, .d3 };

/// Caller-saved general registers.
pub const CALLER_SAVED_GENERAL = [_]GeneralReg{ .r0, .r1, .r2, .r3, .ip };

/// Callee-saved general registers the allocator may hand out. The frame
/// pointer and the link register are also callee-saved; the frame saves them.
pub const CALLEE_SAVED_GENERAL = [_]GeneralReg{ .r4, .r5, .r6, .r7, .r8, .r9, .r10 };

/// Caller-saved floating-point registers.
pub const CALLER_SAVED_FLOAT = [_]FloatReg{
    .d0,  .d1,  .d2,  .d3,  .d4,  .d5,  .d6,  .d7,
    .d16, .d17, .d18, .d19, .d20, .d21, .d22, .d23,
    .d24, .d25, .d26, .d27, .d28, .d29, .d30, .d31,
};

/// Callee-saved floating-point registers.
pub const CALLEE_SAVED_FLOAT = [_]FloatReg{ .d8, .d9, .d10, .d11, .d12, .d13, .d14, .d15 };

/// AAPCS32 reserves no shadow space for arguments.
pub const SHADOW_SPACE_SIZE: u8 = 0;

/// Stack alignment at every public interface.
pub const STACK_ALIGNMENT: u8 = 8;

/// Caller-saved general registers the allocator may hand out: r0-r3. r12 is
/// the scratch register and is never allocated.
pub const CALLER_SAVED_GENERAL_MASK: u32 = maskOf(&.{ .r0, .r1, .r2, .r3 });

/// Callee-saved general registers the allocator may hand out: r4-r10. The
/// entry code takes r9 and r10 back out of the pool, to hold the result and
/// RocOps pointers (`Emit.CC`).
pub const CALLEE_SAVED_GENERAL_MASK: u32 = maskOf(&CALLEE_SAVED_GENERAL);

/// Caller-saved floating-point registers, as a D-register mask.
pub const CALLER_SAVED_FLOAT_MASK: u32 = floatMaskOf(&CALLER_SAVED_FLOAT);

/// Callee-saved floating-point registers, as a D-register mask.
pub const CALLEE_SAVED_FLOAT_MASK: u32 = floatMaskOf(&CALLEE_SAVED_FLOAT);

fn maskOf(regs: []const GeneralReg) u32 {
    var mask: u32 = 0;
    for (regs) |reg| mask |= reg.listBit();
    return mask;
}

fn floatMaskOf(regs: []const FloatReg) u32 {
    var mask: u32 = 0;
    for (regs) |reg| mask |= @as(u32, 1) << reg.enc();
    return mask;
}

test "the fixed-role registers are never allocatable" {
    const allocatable = CALLER_SAVED_GENERAL_MASK | CALLEE_SAVED_GENERAL_MASK;
    inline for (.{ BASE_PTR_REG, STACK_PTR_REG, LINK_REG, SCRATCH_REG, ADDRESS_SCRATCH_REG, GeneralReg.pc }) |reg| {
        try std.testing.expectEqual(@as(u32, 0), allocatable & reg.listBit());
    }
}

test "the general registers are each caller-saved, callee-saved or fixed, once" {
    var seen: u32 = 0;
    for (CALLER_SAVED_GENERAL ++ CALLEE_SAVED_GENERAL ++ [_]GeneralReg{ .fp, .sp, .lr, .pc }) |reg| {
        try std.testing.expectEqual(@as(u32, 0), seen & reg.listBit());
        seen |= reg.listBit();
    }
    try std.testing.expectEqual(@as(u32, 0xFFFF), seen);
}

test "the float registers are each caller-saved or callee-saved, once" {
    try std.testing.expectEqual(@as(u32, 0), CALLER_SAVED_FLOAT_MASK & CALLEE_SAVED_FLOAT_MASK);
    try std.testing.expectEqual(@as(u32, 0xFFFF_FFFF), CALLER_SAVED_FLOAT_MASK | CALLEE_SAVED_FLOAT_MASK);
}

test "arguments and results use the caller-saved registers" {
    for (GENERAL_PARAM_REGS ++ GENERAL_RETURN_REGS) |reg| {
        try std.testing.expect(CALLER_SAVED_GENERAL_MASK & reg.listBit() != 0);
    }
    for (FLOAT_PARAM_REGS ++ FLOAT_RETURN_REGS) |reg| {
        try std.testing.expect(CALLER_SAVED_FLOAT_MASK & (@as(u32, 1) << reg.enc()) != 0);
    }
}
