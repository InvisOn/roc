//! arm32 (32-bit ARM, A32) architecture support for the dev backend.
//!
//! This module provides arm32-specific:
//! - Register definitions (GeneralReg, the banked S/D/Q float file)
//! - Instruction encoding (Emit)

const std = @import("std");

pub const GeneralReg = @import("Registers.zig").GeneralReg;
pub const FloatReg = @import("Registers.zig").FloatReg;
pub const SReg = @import("Registers.zig").SReg;
pub const DReg = @import("Registers.zig").DReg;
pub const QReg = @import("Registers.zig").QReg;
pub const RegisterWidth = @import("Registers.zig").RegisterWidth;

/// ABI-parameterized Emit function. Use Emit(abi) to get a specialized type.
pub const Emit = @import("Emit.zig").Emit;
pub const Condition = @import("Emit.zig").Condition;
pub const ModImm = @import("Emit.zig").ModImm;
pub const DataOp = @import("Emit.zig").DataOp;
pub const ShiftKind = @import("Emit.zig").ShiftKind;
pub const Operand2 = @import("Emit.zig").Operand2;
pub const MemForm = @import("Emit.zig").MemForm;
pub const fitsImmediate = @import("Emit.zig").fitsImmediate;

/// The AAPCS32 registers and the roles the dev backend gives them.
pub const Call = @import("Call.zig");

/// Emit type for arm32 Linux (AAPCS32, VFP variant), musl or glibc
pub const LinuxEmit = Emit(.arm32_aapcs_vfp);

/// ABI-parameterized CodeGen function. Use CodeGen(abi) to get a specialized type.
pub const CodeGen = @import("CodeGen.zig").CodeGen;

/// CodeGen type for arm32 Linux (AAPCS32, VFP variant), musl or glibc
pub const LinuxCodeGen = CodeGen(.arm32_aapcs_vfp);

test "arm32 module imports" {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(LinuxEmit);
    std.testing.refAllDecls(LinuxCodeGen);
    _ = @import("encoding_oracle_tests.zig");
}
