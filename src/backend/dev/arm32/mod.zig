//! ARM32 (A32, ARMv7-A + NEON) architecture support for the dev backend.
//!
//! This module provides arm32-specific:
//! - Register definitions (GeneralReg, the banked S/D/Q float file)
//! - Instruction encoding (Emit)
//! - Calling convention (Call - AAPCS32, VFP variant)
//!
//! Nothing outside this directory uses it yet; see
//! projects/big/arm32-dev-backend.md for the plan that wires it in.

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
pub const MemForm = @import("Emit.zig").MemForm;
pub const fitsImmediate = @import("Emit.zig").fitsImmediate;
pub const NeonSize = @import("Emit.zig").NeonSize;
pub const NeonThreeSame = @import("Emit.zig").NeonThreeSame;
pub const NeonLogic = @import("Emit.zig").NeonLogic;
pub const NeonThreeDiff = @import("Emit.zig").NeonThreeDiff;
pub const NeonTwoMisc = @import("Emit.zig").NeonTwoMisc;
pub const NeonNarrow = @import("Emit.zig").NeonNarrow;
pub const NeonShiftRight = @import("Emit.zig").NeonShiftRight;
pub const NeonShiftNarrow = @import("Emit.zig").NeonShiftNarrow;

/// Emit type for musl (static) arm32 Linux
pub const MuslEmit = Emit(.arm32musl);
/// Emit type for glibc (dynamic) arm32 Linux
pub const LinuxEmit = Emit(.arm32linux);

pub const Call = @import("Call.zig");

test "arm32 module imports" {
    std.testing.refAllDecls(@This());
    _ = @import("encoding_oracle_tests.zig");
}
