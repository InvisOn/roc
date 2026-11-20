//! arm32 (32-bit ARM, A32) architecture support for the dev backend.
//!
//! This module provides arm32-specific:
//! - Register definitions (GeneralReg, the banked S/D/Q float file)

const std = @import("std");

pub const GeneralReg = @import("Registers.zig").GeneralReg;
pub const FloatReg = @import("Registers.zig").FloatReg;
pub const SReg = @import("Registers.zig").SReg;
pub const DReg = @import("Registers.zig").DReg;
pub const QReg = @import("Registers.zig").QReg;
pub const RegisterWidth = @import("Registers.zig").RegisterWidth;

test "arm32 module imports" {
    std.testing.refAllDecls(@This());
}
