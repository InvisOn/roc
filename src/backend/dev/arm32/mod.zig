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

/// Target-parameterized Emit function. Use Emit(target) to get a specialized type.
pub const Emit = @import("Emit.zig").Emit;
pub const Condition = @import("Emit.zig").Condition;
pub const ModImm = @import("Emit.zig").ModImm;
pub const DataOp = @import("Emit.zig").DataOp;
pub const ShiftKind = @import("Emit.zig").ShiftKind;
pub const Operand2 = @import("Emit.zig").Operand2;

/// Emit type for musl (static) arm32 Linux
pub const MuslEmit = Emit(.arm32musl);
/// Emit type for glibc (dynamic) arm32 Linux
pub const LinuxEmit = Emit(.arm32linux);

test "arm32 module imports" {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(MuslEmit);
    std.testing.refAllDecls(LinuxEmit);
}
