//! ARM32 (A32) register definitions.
//!
//! Defines the core registers and the banked VFP/NEON register file available
//! on ARMv7-A with NEON (VFPv3-D32).
//!
//! The VFP/NEON file is a single bank viewed three ways: S registers s0-s31,
//! D registers d0-d31 and Q registers q0-q15, where s[2n] and s[2n+1] are the
//! low and high halves of d[n] (n < 16), and d[2n] and d[2n+1] are the low and
//! high halves of q[n]. `FloatReg` is the D view, the unit a register allocator
//! owns; the S and Q views are derived from it so that one allocator owns every
//! view of the bank.

const std = @import("std");

/// ARM32 core registers r0-r15.
///
/// AAPCS32 roles (Linux EABI): r0-r3 arguments/results (caller-saved), r4-r10
/// callee-saved variable registers (r9 is an ordinary variable register on
/// Linux), r11 frame pointer, r12 (IP) intra-procedure-call scratch, r13 stack
/// pointer, r14 link register, r15 program counter.
pub const GeneralReg = enum(u4) {
    r0 = 0,
    r1 = 1,
    r2 = 2,
    r3 = 3,
    r4 = 4,
    r5 = 5,
    r6 = 6,
    r7 = 7,
    r8 = 8,
    r9 = 9,
    r10 = 10,
    r11 = 11,
    r12 = 12,
    r13 = 13,
    r14 = 14,
    r15 = 15,

    /// Frame pointer.
    pub const fp = GeneralReg.r11;
    /// Intra-procedure-call scratch register. Linker veneers and PLT stubs
    /// clobber it, so it is never live across a call.
    pub const ip = GeneralReg.r12;
    /// Stack pointer.
    pub const sp = GeneralReg.r13;
    /// Link register. Clobbered by every call.
    pub const lr = GeneralReg.r14;
    /// Program counter. Reads as the instruction's address + 8 in A32.
    pub const pc = GeneralReg.r15;

    /// Get the 4-bit register encoding
    pub fn enc(self: GeneralReg) u4 {
        return @intFromEnum(self);
    }

    /// Get the assembler register name
    pub fn name(self: GeneralReg) []const u8 {
        const names = [_][]const u8{
            "r0", "r1", "r2",  "r3",  "r4",  "r5", "r6", "r7",
            "r8", "r9", "r10", "r11", "r12", "sp", "lr", "pc",
        };
        return names[@intFromEnum(self)];
    }

    /// Bit for this register in an LDM/STM/PUSH/POP register list.
    pub fn listBit(self: GeneralReg) u16 {
        return @as(u16, 1) << self.enc();
    }
};

/// Single-precision VFP view s0-s31.
pub const SReg = enum(u5) {
    s0 = 0,
    s1 = 1,
    s2 = 2,
    s3 = 3,
    s4 = 4,
    s5 = 5,
    s6 = 6,
    s7 = 7,
    s8 = 8,
    s9 = 9,
    s10 = 10,
    s11 = 11,
    s12 = 12,
    s13 = 13,
    s14 = 14,
    s15 = 15,
    s16 = 16,
    s17 = 17,
    s18 = 18,
    s19 = 19,
    s20 = 20,
    s21 = 21,
    s22 = 22,
    s23 = 23,
    s24 = 24,
    s25 = 25,
    s26 = 26,
    s27 = 27,
    s28 = 28,
    s29 = 29,
    s30 = 30,
    s31 = 31,

    pub fn enc(self: SReg) u5 {
        return @intFromEnum(self);
    }

    /// The D register this S register is a half of.
    pub fn containingD(self: SReg) DReg {
        return @enumFromInt(self.enc() >> 1);
    }
};

/// Double-precision VFP / 64-bit NEON view d0-d31.
pub const DReg = enum(u5) {
    d0 = 0,
    d1 = 1,
    d2 = 2,
    d3 = 3,
    d4 = 4,
    d5 = 5,
    d6 = 6,
    d7 = 7,
    d8 = 8,
    d9 = 9,
    d10 = 10,
    d11 = 11,
    d12 = 12,
    d13 = 13,
    d14 = 14,
    d15 = 15,
    d16 = 16,
    d17 = 17,
    d18 = 18,
    d19 = 19,
    d20 = 20,
    d21 = 21,
    d22 = 22,
    d23 = 23,
    d24 = 24,
    d25 = 25,
    d26 = 26,
    d27 = 27,
    d28 = 28,
    d29 = 29,
    d30 = 30,
    d31 = 31,

    pub fn enc(self: DReg) u5 {
        return @intFromEnum(self);
    }

    /// Whether this D register has S-register halves (d0-d15 only).
    pub fn hasSViews(self: DReg) bool {
        return self.enc() < 16;
    }

    /// The low S half s[2n]. Only d0-d15 have S views.
    pub fn sLow(self: DReg) SReg {
        std.debug.assert(self.hasSViews());
        return @enumFromInt(@as(u5, self.enc()) * 2);
    }

    /// The high S half s[2n+1]. Only d0-d15 have S views.
    pub fn sHigh(self: DReg) SReg {
        std.debug.assert(self.hasSViews());
        return @enumFromInt(@as(u5, self.enc()) * 2 + 1);
    }

    /// The Q register this D register is a half of.
    pub fn containingQ(self: DReg) QReg {
        return @enumFromInt(self.enc() >> 1);
    }
};

/// 128-bit NEON view q0-q15.
pub const QReg = enum(u4) {
    q0 = 0,
    q1 = 1,
    q2 = 2,
    q3 = 3,
    q4 = 4,
    q5 = 5,
    q6 = 6,
    q7 = 7,
    q8 = 8,
    q9 = 9,
    q10 = 10,
    q11 = 11,
    q12 = 12,
    q13 = 13,
    q14 = 14,
    q15 = 15,

    pub fn enc(self: QReg) u4 {
        return @intFromEnum(self);
    }

    /// The low D half d[2n].
    pub fn dLow(self: QReg) DReg {
        return @enumFromInt(@as(u5, self.enc()) * 2);
    }

    /// The high D half d[2n+1].
    pub fn dHigh(self: QReg) DReg {
        return @enumFromInt(@as(u5, self.enc()) * 2 + 1);
    }
};

/// The allocation unit of the VFP/NEON bank. See the module doc.
pub const FloatReg = DReg;

/// Register width for operations. A32 core registers are 32 bits wide; values
/// whose Roc type is 64 bits wide occupy a register pair or memory.
pub const RegisterWidth = enum {
    w32,

    /// Get the operand size in bytes
    pub fn bytes(self: RegisterWidth) u8 {
        return switch (self) {
            .w32 => 4,
        };
    }
};

// Tests

test "general register encoding and aliases" {
    try std.testing.expectEqual(@as(u4, 0), GeneralReg.r0.enc());
    try std.testing.expectEqual(@as(u4, 11), GeneralReg.fp.enc());
    try std.testing.expectEqual(@as(u4, 12), GeneralReg.ip.enc());
    try std.testing.expectEqual(@as(u4, 13), GeneralReg.sp.enc());
    try std.testing.expectEqual(@as(u4, 14), GeneralReg.lr.enc());
    try std.testing.expectEqual(@as(u4, 15), GeneralReg.pc.enc());
    try std.testing.expectEqualStrings("sp", GeneralReg.r13.name());
    try std.testing.expectEqual(@as(u16, 0x4010), GeneralReg.r4.listBit() | GeneralReg.lr.listBit());
}

test "float bank aliasing" {
    try std.testing.expectEqual(SReg.s6, DReg.d3.sLow());
    try std.testing.expectEqual(SReg.s7, DReg.d3.sHigh());
    try std.testing.expectEqual(DReg.d3, SReg.s7.containingD());
    try std.testing.expectEqual(DReg.d30, QReg.q15.dLow());
    try std.testing.expectEqual(DReg.d31, QReg.q15.dHigh());
    try std.testing.expectEqual(QReg.q15, DReg.d31.containingQ());
    try std.testing.expect(DReg.d15.hasSViews());
    try std.testing.expect(!DReg.d16.hasSViews());
}

test "register width" {
    try std.testing.expectEqual(@as(u8, 4), RegisterWidth.w32.bytes());
}
