//! arm32 (A32) instruction encoding.
//!
//! This module provides low-level A32 instruction encoding for the dev backend.
//! It generates machine code bytes for ARMv7-A with NEON (VFPv3-D32) and
//! without the optional integer-divide extension.
//!
//! Note: All A32 instructions are 32 bits (4 bytes), little-endian, and must be
//! 4-byte aligned. A32 reads PC as the instruction's own address + 8.
//!
//! Emitters encode exactly what they are asked to. Immediates that A32 cannot
//! encode are rejected by the argument types (`ModImm`) or by assertions.
//!
//! The Emit function is parameterized by RocTarget to enable full cross-compilation.

const std = @import("std");
const Allocator = std.mem.Allocator;
const RocTarget = @import("roc_target").RocTarget;
const Registers = @import("Registers.zig");

/// A32 condition codes.
pub const Condition = enum(u4) {
    eq = 0x0, // Z set
    ne = 0x1, // Z clear
    hs = 0x2, // C set (unsigned >=)
    lo = 0x3, // C clear (unsigned <)
    mi = 0x4, // N set
    pl = 0x5, // N clear
    vs = 0x6, // V set
    vc = 0x7, // V clear
    hi = 0x8, // C set and Z clear (unsigned >)
    ls = 0x9, // C clear or Z set (unsigned <=)
    ge = 0xA, // N == V (signed >=)
    lt = 0xB, // N != V (signed <)
    gt = 0xC, // Z clear and N == V (signed >)
    le = 0xD, // Z set or N != V (signed <=)
    al = 0xE, // always

    /// The condition that holds exactly when this one does not. `al` has no
    /// inverse.
    pub fn invert(self: Condition) Condition {
        std.debug.assert(self != .al);
        return @fromBackingInt(@backingInt(self) ^ 1);
    }
};

/// A32 data-processing opcodes.
pub const DataOp = enum(u4) {
    @"and" = 0x0,
    eor = 0x1,
    sub = 0x2,
    rsb = 0x3,
    add = 0x4,
    adc = 0x5,
    sbc = 0x6,
    rsc = 0x7,
    tst = 0x8,
    teq = 0x9,
    cmp = 0xA,
    cmn = 0xB,
    orr = 0xC,
    mov = 0xD,
    bic = 0xE,
    mvn = 0xF,

    /// Comparison opcodes write only flags: Rd must be 0 and S must be set.
    fn isCompare(self: DataOp) bool {
        return switch (self) {
            .tst, .teq, .cmp, .cmn => true,
            .@"and", .eor, .sub, .rsb, .add, .adc, .sbc, .rsc, .orr, .mov, .bic, .mvn => false,
        };
    }

    /// Move opcodes take no first operand: Rn must be 0.
    fn isMove(self: DataOp) bool {
        return self == .mov or self == .mvn;
    }
};

/// A32 shift types.
pub const ShiftKind = enum(u2) {
    lsl = 0,
    lsr = 1,
    asr = 2,
    ror = 3,
};

/// An A32 "modified immediate": an 8-bit value rotated right by an even
/// amount. Only values of that form can be data-processing immediates.
pub const ModImm = struct {
    /// rotate(4):imm8(8), as encoded in bits 11:0
    bits: u12,

    /// Encode `value`, or return null when it has no modified-immediate form.
    /// The encoding with the smallest rotation is chosen, matching the
    /// assembler's canonical encoding.
    pub fn encode(imm: u32) ?ModImm {
        var rot: u5 = 0;
        while (true) : (rot += 1) {
            // imm8 ROR (2*rot) == value  <=>  imm8 == value ROL (2*rot)
            const imm8 = std.math.rotl(u32, imm, @as(u32, rot) * 2);
            if (imm8 <= 0xFF) {
                return .{ .bits = (@as(u12, @intCast(rot)) << 8) | @as(u12, @intCast(imm8)) };
            }
            if (rot == 15) return null;
        }
    }

    /// Encode a value known at compile time to have a modified-immediate form.
    pub fn of(comptime imm: u32) ModImm {
        return comptime encode(imm) orelse @compileError("value has no A32 modified-immediate encoding");
    }

    /// The 32-bit value this immediate denotes.
    pub fn decode(self: ModImm) u32 {
        const imm8: u32 = self.bits & 0xFF;
        const rot: u32 = self.bits >> 8;
        return std.math.rotr(u32, imm8, rot * 2);
    }
};

/// The second operand of a data-processing instruction.
pub const Operand2 = union(enum) {
    /// Modified immediate
    imm: ModImm,
    /// Register, unshifted
    reg: Registers.GeneralReg,
    /// Register shifted by an immediate. `lsl` takes 0-31, `lsr`/`asr` take
    /// 1-32, `ror` takes 1-31.
    shift_imm: struct { rm: Registers.GeneralReg, kind: ShiftKind, amount: u6 },
    /// Register shifted by the bottom byte of another register
    shift_reg: struct { rm: Registers.GeneralReg, kind: ShiftKind, rs: Registers.GeneralReg },
};

/// ARM32 instruction emitter for generating machine code.
/// Parameterized by target for cross-compilation support.
pub fn Emit(comptime target: RocTarget) type {
    // Validate this is an arm32 target
    if (target.toCpuArch() != .arm) {
        @compileError("arm32.Emit requires an arm32 target");
    }
    // The CPU floor: NEON holds vector locals, and without `hwdiv` word
    // division calls `__aeabi_*` helpers. Roc names no CPU floor of its own
    // for arm32 (`RocTarget.cpuContract`), so the target gets Zig's arm
    // baseline; if a Zig upgrade moves that baseline, the code generated here
    // must move with it.
    comptime {
        const arch = target.toCpuArch();
        const os: std.Target.Os = .{ .tag = target.toOsTag(), .version_range = .{ .none = {} } };
        const baseline = std.Target.Cpu.baseline(arch, os);
        if (target.requiredRuntimeCpuFeatures().count() != 0)
            @compileError("arm32.Emit assumes Zig's arm baseline, but " ++ target.toName() ++ " names CPU features of its own");
        if (!baseline.has(.arm, .neon))
            @compileError("arm32.Emit lowers SIMD to NEON, but Zig's arm baseline for " ++ target.toName() ++ " lacks NEON");
        if (baseline.hasAny(.arm, &.{ .hwdiv, .hwdiv_arm }))
            @compileError("arm32.Emit divides through __aeabi helpers, but Zig's arm baseline for " ++ target.toName() ++ " has hwdiv");
    }

    return struct {
        const Self = @This();

        // Re-export register types so callers can reach them through the Emit type
        pub const GeneralReg = Registers.GeneralReg;
        pub const FloatReg = Registers.FloatReg;
        pub const SReg = Registers.SReg;
        pub const DReg = Registers.DReg;
        pub const QReg = Registers.QReg;
        pub const RegisterWidth = Registers.RegisterWidth;

        /// The target this Emit was instantiated for
        pub const roc_target = target;

        allocator: std.mem.Allocator,
        buf: std.ArrayList(u8),

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
                .buf = .empty,
            };
        }

        pub fn deinit(self: *Self) void {
            self.buf.deinit(self.allocator);
        }

        /// Get the current code offset
        pub fn codeOffset(self: *const Self) u64 {
            return @intCast(self.buf.items.len);
        }

        /// Emit a 32-bit instruction (little-endian)
        fn emit32(self: *Self, inst: u32) Allocator.Error!void {
            try self.buf.appendSlice(self.allocator, &@as([4]u8, @bitCast(inst)));
        }

        fn condBits(cond: Condition) u32 {
            return @as(u32, @backingInt(cond)) << 28;
        }

        // Data processing

        /// Encode the operand-2 field (bit 25 and bits 11:0).
        fn operand2Bits(op2: Operand2) u32 {
            return switch (op2) {
                .imm => |imm| (1 << 25) | @as(u32, imm.bits),
                .reg => |rm| rm.enc(),
                .shift_imm => |s| blk: {
                    const imm5: u32 = switch (s.kind) {
                        .lsl => inner: {
                            std.debug.assert(s.amount <= 31);
                            break :inner s.amount;
                        },
                        .lsr, .asr => inner: {
                            std.debug.assert(s.amount >= 1 and s.amount <= 32);
                            break :inner s.amount & 31; // 32 encodes as 0
                        },
                        .ror => inner: {
                            std.debug.assert(s.amount >= 1 and s.amount <= 31); // 0 would be RRX
                            break :inner s.amount;
                        },
                    };
                    break :blk (imm5 << 7) | (@as(u32, @backingInt(s.kind)) << 5) | s.rm.enc();
                },
                .shift_reg => |s| blk: {
                    std.debug.assert(s.rm != .r15 and s.rs != .r15);
                    break :blk (@as(u32, s.rs.enc()) << 8) | (@as(u32, @backingInt(s.kind)) << 5) | (1 << 4) | s.rm.enc();
                },
            };
        }

        /// Generic data-processing instruction:
        /// cond 00 I opcode(4) S Rn(4) Rd(4) operand2(12)
        pub fn dataProc(self: *Self, cond: Condition, op: DataOp, set_flags: bool, rd: GeneralReg, rn: GeneralReg, op2: Operand2) Allocator.Error!void {
            if (op.isCompare()) std.debug.assert(set_flags and rd == .r0);
            if (op.isMove()) std.debug.assert(rn == .r0);
            const inst: u32 = condBits(cond) |
                (@as(u32, @backingInt(op)) << 21) |
                (@as(u32, @intFromBool(set_flags)) << 20) |
                (@as(u32, rn.enc()) << 16) |
                (@as(u32, rd.enc()) << 12) |
                operand2Bits(op2);
            try self.emit32(inst);
        }

        /// MOV rd, rm
        pub fn movRegReg(self: *Self, dst: GeneralReg, src: GeneralReg) Allocator.Error!void {
            try self.dataProc(.al, .mov, false, dst, .r0, .{ .reg = src });
        }

        /// MOV<cond> rd, rm
        pub fn movRegRegCond(self: *Self, cond: Condition, dst: GeneralReg, src: GeneralReg) Allocator.Error!void {
            try self.dataProc(cond, .mov, false, dst, .r0, .{ .reg = src });
        }

        /// MOV rd, #imm
        pub fn movRegModImm(self: *Self, dst: GeneralReg, imm: ModImm) Allocator.Error!void {
            try self.dataProc(.al, .mov, false, dst, .r0, .{ .imm = imm });
        }

        /// MOV<cond> rd, #imm
        pub fn movRegModImmCond(self: *Self, cond: Condition, dst: GeneralReg, imm: ModImm) Allocator.Error!void {
            try self.dataProc(cond, .mov, false, dst, .r0, .{ .imm = imm });
        }

        /// MVN rd, #imm (rd = ~imm)
        pub fn mvnRegModImm(self: *Self, dst: GeneralReg, imm: ModImm) Allocator.Error!void {
            try self.dataProc(.al, .mvn, false, dst, .r0, .{ .imm = imm });
        }

        /// MVN rd, rm (rd = ~rm)
        pub fn mvnRegReg(self: *Self, dst: GeneralReg, src: GeneralReg) Allocator.Error!void {
            try self.dataProc(.al, .mvn, false, dst, .r0, .{ .reg = src });
        }

        /// MOVW rd, #imm16 (rd = imm16, zero-extended)
        /// cond 0011 0000 imm4 Rd imm12
        pub fn movw(self: *Self, dst: GeneralReg, imm: u16) Allocator.Error!void {
            std.debug.assert(dst != .r15);
            try self.emit32(encodeMovwMovt(false, dst, imm));
        }

        /// MOVT rd, #imm16 (rd[31:16] = imm16, low half kept)
        /// cond 0011 0100 imm4 Rd imm12
        pub fn movt(self: *Self, dst: GeneralReg, imm: u16) Allocator.Error!void {
            std.debug.assert(dst != .r15);
            try self.emit32(encodeMovwMovt(true, dst, imm));
        }

        /// Encode MOVW (top = false) or MOVT (top = true).
        pub fn encodeMovwMovt(top: bool, dst: GeneralReg, imm: u16) u32 {
            return condBits(.al) |
                (0b0011 << 24) |
                (@as(u32, @intFromBool(top)) << 22) |
                (@as(u32, imm >> 12) << 16) |
                (@as(u32, dst.enc()) << 12) |
                (imm & 0xFFF);
        }

        /// Load a 32-bit constant: MOV #imm or MVN #~imm when one instruction
        /// encodes it, otherwise MOVW followed by MOVT when the top half is
        /// non-zero. The instruction choice depends only on the value.
        pub fn movRegImm32(self: *Self, dst: GeneralReg, imm: u32) Allocator.Error!void {
            if (ModImm.encode(imm)) |mod| {
                try self.movRegModImm(dst, mod);
            } else if (ModImm.encode(~imm)) |mod| {
                try self.mvnRegModImm(dst, mod);
            } else {
                try self.movw(dst, @truncate(imm));
                const hi: u16 = @truncate(imm >> 16);
                if (hi != 0) try self.movt(dst, hi);
            }
        }

        /// ADD rd, rn, rm
        pub fn addRegRegReg(self: *Self, dst: GeneralReg, src1: GeneralReg, src2: GeneralReg) Allocator.Error!void {
            try self.dataProc(.al, .add, false, dst, src1, .{ .reg = src2 });
        }

        /// ADDS rd, rn, rm (sets flags; carry out feeds ADC)
        pub fn addsRegRegReg(self: *Self, dst: GeneralReg, src1: GeneralReg, src2: GeneralReg) Allocator.Error!void {
            try self.dataProc(.al, .add, true, dst, src1, .{ .reg = src2 });
        }

        /// ADC rd, rn, rm (add with carry)
        pub fn adcRegRegReg(self: *Self, dst: GeneralReg, src1: GeneralReg, src2: GeneralReg) Allocator.Error!void {
            try self.dataProc(.al, .adc, false, dst, src1, .{ .reg = src2 });
        }

        /// ADCS rd, rn, rm (add with carry, sets flags)
        pub fn adcsRegRegReg(self: *Self, dst: GeneralReg, src1: GeneralReg, src2: GeneralReg) Allocator.Error!void {
            try self.dataProc(.al, .adc, true, dst, src1, .{ .reg = src2 });
        }

        /// SUB rd, rn, rm
        pub fn subRegRegReg(self: *Self, dst: GeneralReg, src1: GeneralReg, src2: GeneralReg) Allocator.Error!void {
            try self.dataProc(.al, .sub, false, dst, src1, .{ .reg = src2 });
        }

        /// SUBS rd, rn, rm (sets flags; borrow feeds SBC)
        pub fn subsRegRegReg(self: *Self, dst: GeneralReg, src1: GeneralReg, src2: GeneralReg) Allocator.Error!void {
            try self.dataProc(.al, .sub, true, dst, src1, .{ .reg = src2 });
        }

        /// SBC rd, rn, rm (subtract with carry)
        pub fn sbcRegRegReg(self: *Self, dst: GeneralReg, src1: GeneralReg, src2: GeneralReg) Allocator.Error!void {
            try self.dataProc(.al, .sbc, false, dst, src1, .{ .reg = src2 });
        }

        /// SBCS rd, rn, rm (subtract with carry, sets flags)
        pub fn sbcsRegRegReg(self: *Self, dst: GeneralReg, src1: GeneralReg, src2: GeneralReg) Allocator.Error!void {
            try self.dataProc(.al, .sbc, true, dst, src1, .{ .reg = src2 });
        }

        /// ADD rd, rn, #imm
        pub fn addRegRegModImm(self: *Self, dst: GeneralReg, src: GeneralReg, imm: ModImm) Allocator.Error!void {
            try self.dataProc(.al, .add, false, dst, src, .{ .imm = imm });
        }

        /// ADDS rd, rn, #imm
        pub fn addsRegRegModImm(self: *Self, dst: GeneralReg, src: GeneralReg, imm: ModImm) Allocator.Error!void {
            try self.dataProc(.al, .add, true, dst, src, .{ .imm = imm });
        }

        /// SUB rd, rn, #imm
        pub fn subRegRegModImm(self: *Self, dst: GeneralReg, src: GeneralReg, imm: ModImm) Allocator.Error!void {
            try self.dataProc(.al, .sub, false, dst, src, .{ .imm = imm });
        }

        /// SUBS rd, rn, #imm
        pub fn subsRegRegModImm(self: *Self, dst: GeneralReg, src: GeneralReg, imm: ModImm) Allocator.Error!void {
            try self.dataProc(.al, .sub, true, dst, src, .{ .imm = imm });
        }

        /// RSB rd, rn, #imm (rd = imm - rn; `#0` negates)
        pub fn rsbRegRegModImm(self: *Self, dst: GeneralReg, src: GeneralReg, imm: ModImm) Allocator.Error!void {
            try self.dataProc(.al, .rsb, false, dst, src, .{ .imm = imm });
        }

        /// RSBS rd, rn, #imm (sets flags; low half of a 64-bit negate)
        pub fn rsbsRegRegModImm(self: *Self, dst: GeneralReg, src: GeneralReg, imm: ModImm) Allocator.Error!void {
            try self.dataProc(.al, .rsb, true, dst, src, .{ .imm = imm });
        }

        /// RSC rd, rn, #imm (reverse subtract with carry; high half of a
        /// 64-bit negate)
        pub fn rscRegRegModImm(self: *Self, dst: GeneralReg, src: GeneralReg, imm: ModImm) Allocator.Error!void {
            try self.dataProc(.al, .rsc, false, dst, src, .{ .imm = imm });
        }

        /// AND rd, rn, rm
        pub fn andRegRegReg(self: *Self, dst: GeneralReg, src1: GeneralReg, src2: GeneralReg) Allocator.Error!void {
            try self.dataProc(.al, .@"and", false, dst, src1, .{ .reg = src2 });
        }

        /// ORR rd, rn, rm
        pub fn orrRegRegReg(self: *Self, dst: GeneralReg, src1: GeneralReg, src2: GeneralReg) Allocator.Error!void {
            try self.dataProc(.al, .orr, false, dst, src1, .{ .reg = src2 });
        }

        /// EOR rd, rn, rm
        pub fn eorRegRegReg(self: *Self, dst: GeneralReg, src1: GeneralReg, src2: GeneralReg) Allocator.Error!void {
            try self.dataProc(.al, .eor, false, dst, src1, .{ .reg = src2 });
        }

        /// BIC rd, rn, rm (rd = rn & ~rm)
        pub fn bicRegRegReg(self: *Self, dst: GeneralReg, src1: GeneralReg, src2: GeneralReg) Allocator.Error!void {
            try self.dataProc(.al, .bic, false, dst, src1, .{ .reg = src2 });
        }

        /// AND rd, rn, #imm
        pub fn andRegRegModImm(self: *Self, dst: GeneralReg, src: GeneralReg, imm: ModImm) Allocator.Error!void {
            try self.dataProc(.al, .@"and", false, dst, src, .{ .imm = imm });
        }

        /// ORR rd, rn, #imm
        pub fn orrRegRegModImm(self: *Self, dst: GeneralReg, src: GeneralReg, imm: ModImm) Allocator.Error!void {
            try self.dataProc(.al, .orr, false, dst, src, .{ .imm = imm });
        }

        /// EOR rd, rn, #imm
        pub fn eorRegRegModImm(self: *Self, dst: GeneralReg, src: GeneralReg, imm: ModImm) Allocator.Error!void {
            try self.dataProc(.al, .eor, false, dst, src, .{ .imm = imm });
        }

        /// BIC rd, rn, #imm
        pub fn bicRegRegModImm(self: *Self, dst: GeneralReg, src: GeneralReg, imm: ModImm) Allocator.Error!void {
            try self.dataProc(.al, .bic, false, dst, src, .{ .imm = imm });
        }

        /// CMP rn, rm
        pub fn cmpRegReg(self: *Self, lhs: GeneralReg, rhs: GeneralReg) Allocator.Error!void {
            try self.dataProc(.al, .cmp, true, .r0, lhs, .{ .reg = rhs });
        }

        /// CMP rn, #imm
        pub fn cmpRegModImm(self: *Self, lhs: GeneralReg, imm: ModImm) Allocator.Error!void {
            try self.dataProc(.al, .cmp, true, .r0, lhs, .{ .imm = imm });
        }

        /// CMN rn, #imm (compare against -imm)
        pub fn cmnRegModImm(self: *Self, lhs: GeneralReg, imm: ModImm) Allocator.Error!void {
            try self.dataProc(.al, .cmn, true, .r0, lhs, .{ .imm = imm });
        }

        /// TST rn, rm (flags from rn & rm)
        pub fn tstRegReg(self: *Self, lhs: GeneralReg, rhs: GeneralReg) Allocator.Error!void {
            try self.dataProc(.al, .tst, true, .r0, lhs, .{ .reg = rhs });
        }

        /// TST rn, #imm
        pub fn tstRegModImm(self: *Self, lhs: GeneralReg, imm: ModImm) Allocator.Error!void {
            try self.dataProc(.al, .tst, true, .r0, lhs, .{ .imm = imm });
        }

        /// TEQ rn, rm (flags from rn ^ rm)
        pub fn teqRegReg(self: *Self, lhs: GeneralReg, rhs: GeneralReg) Allocator.Error!void {
            try self.dataProc(.al, .teq, true, .r0, lhs, .{ .reg = rhs });
        }

        // Shifts (MOV with a shifted register operand)

        /// LSL rd, rm, #amount (0-31)
        pub fn lslRegRegImm(self: *Self, dst: GeneralReg, src: GeneralReg, amount: u5) Allocator.Error!void {
            try self.dataProc(.al, .mov, false, dst, .r0, .{ .shift_imm = .{ .rm = src, .kind = .lsl, .amount = amount } });
        }

        /// LSR rd, rm, #amount (1-32)
        pub fn lsrRegRegImm(self: *Self, dst: GeneralReg, src: GeneralReg, amount: u6) Allocator.Error!void {
            try self.dataProc(.al, .mov, false, dst, .r0, .{ .shift_imm = .{ .rm = src, .kind = .lsr, .amount = amount } });
        }

        /// ASR rd, rm, #amount (1-32)
        pub fn asrRegRegImm(self: *Self, dst: GeneralReg, src: GeneralReg, amount: u6) Allocator.Error!void {
            try self.dataProc(.al, .mov, false, dst, .r0, .{ .shift_imm = .{ .rm = src, .kind = .asr, .amount = amount } });
        }

        /// ROR rd, rm, #amount (1-31)
        pub fn rorRegRegImm(self: *Self, dst: GeneralReg, src: GeneralReg, amount: u5) Allocator.Error!void {
            try self.dataProc(.al, .mov, false, dst, .r0, .{ .shift_imm = .{ .rm = src, .kind = .ror, .amount = amount } });
        }

        /// LSL rd, rm, rs (shift by the bottom byte of rs; >= 32 gives 0)
        pub fn lslRegRegReg(self: *Self, dst: GeneralReg, src: GeneralReg, amount: GeneralReg) Allocator.Error!void {
            try self.dataProc(.al, .mov, false, dst, .r0, .{ .shift_reg = .{ .rm = src, .kind = .lsl, .rs = amount } });
        }

        /// LSR rd, rm, rs (shift by the bottom byte of rs; >= 32 gives 0)
        pub fn lsrRegRegReg(self: *Self, dst: GeneralReg, src: GeneralReg, amount: GeneralReg) Allocator.Error!void {
            try self.dataProc(.al, .mov, false, dst, .r0, .{ .shift_reg = .{ .rm = src, .kind = .lsr, .rs = amount } });
        }

        /// ASR rd, rm, rs (shift by the bottom byte of rs; >= 32 gives the sign)
        pub fn asrRegRegReg(self: *Self, dst: GeneralReg, src: GeneralReg, amount: GeneralReg) Allocator.Error!void {
            try self.dataProc(.al, .mov, false, dst, .r0, .{ .shift_reg = .{ .rm = src, .kind = .asr, .rs = amount } });
        }

        /// ROR rd, rm, rs
        pub fn rorRegRegReg(self: *Self, dst: GeneralReg, src: GeneralReg, amount: GeneralReg) Allocator.Error!void {
            try self.dataProc(.al, .mov, false, dst, .r0, .{ .shift_reg = .{ .rm = src, .kind = .ror, .rs = amount } });
        }

        // Multiply

        /// cond 0000 opc(4) 0 Rd/RdHi(4) Ra/RdLo(4) Rm(4) 1001 Rn(4), flags never set
        fn multiply(self: *Self, opc: u4, hi: GeneralReg, lo: GeneralReg, rm: GeneralReg, rn: GeneralReg) Allocator.Error!void {
            std.debug.assert(hi != .r15 and lo != .r15 and rm != .r15 and rn != .r15);
            const inst: u32 = condBits(.al) |
                (@as(u32, opc) << 21) |
                (@as(u32, hi.enc()) << 16) |
                (@as(u32, lo.enc()) << 12) |
                (@as(u32, rm.enc()) << 8) |
                (0b1001 << 4) |
                rn.enc();
            try self.emit32(inst);
        }

        /// MUL rd, rn, rm (low 32 bits of the product)
        pub fn mulRegRegReg(self: *Self, dst: GeneralReg, src1: GeneralReg, src2: GeneralReg) Allocator.Error!void {
            try self.multiply(0b0000, dst, .r0, src2, src1);
        }

        /// MLA rd, rn, rm, ra (rd = ra + rn * rm)
        pub fn mlaRegRegRegReg(self: *Self, dst: GeneralReg, src1: GeneralReg, src2: GeneralReg, addend: GeneralReg) Allocator.Error!void {
            try self.multiply(0b0001, dst, addend, src2, src1);
        }

        /// MLS rd, rn, rm, ra (rd = ra - rn * rm)
        pub fn mlsRegRegRegReg(self: *Self, dst: GeneralReg, src1: GeneralReg, src2: GeneralReg, minuend: GeneralReg) Allocator.Error!void {
            try self.multiply(0b0011, dst, minuend, src2, src1);
        }

        /// UMULL rdlo, rdhi, rn, rm (unsigned 32x32 -> 64)
        pub fn umull(self: *Self, dst_lo: GeneralReg, dst_hi: GeneralReg, src1: GeneralReg, src2: GeneralReg) Allocator.Error!void {
            std.debug.assert(dst_lo != dst_hi);
            try self.multiply(0b0100, dst_hi, dst_lo, src2, src1);
        }

        /// UMLAL rdlo, rdhi, rn, rm (rdhi:rdlo += unsigned rn * rm)
        pub fn umlal(self: *Self, dst_lo: GeneralReg, dst_hi: GeneralReg, src1: GeneralReg, src2: GeneralReg) Allocator.Error!void {
            std.debug.assert(dst_lo != dst_hi);
            try self.multiply(0b0101, dst_hi, dst_lo, src2, src1);
        }

        /// UMAAL rdlo, rdhi, rn, rm (rdhi:rdlo = rn * rm + rdlo + rdhi, unsigned;
        /// the sum cannot overflow 64 bits)
        pub fn umaal(self: *Self, dst_lo: GeneralReg, dst_hi: GeneralReg, src1: GeneralReg, src2: GeneralReg) Allocator.Error!void {
            std.debug.assert(dst_lo != dst_hi);
            try self.multiply(0b0010, dst_hi, dst_lo, src2, src1);
        }

        /// SMULL rdlo, rdhi, rn, rm (signed 32x32 -> 64)
        pub fn smull(self: *Self, dst_lo: GeneralReg, dst_hi: GeneralReg, src1: GeneralReg, src2: GeneralReg) Allocator.Error!void {
            std.debug.assert(dst_lo != dst_hi);
            try self.multiply(0b0110, dst_hi, dst_lo, src2, src1);
        }

        /// SMLAL rdlo, rdhi, rn, rm (rdhi:rdlo += signed rn * rm)
        pub fn smlal(self: *Self, dst_lo: GeneralReg, dst_hi: GeneralReg, src1: GeneralReg, src2: GeneralReg) Allocator.Error!void {
            std.debug.assert(dst_lo != dst_hi);
            try self.multiply(0b0111, dst_hi, dst_lo, src2, src1);
        }

        // Bit manipulation

        /// cond op(8) 1111 Rd 1111 op2(4) Rm, the shared shape of CLZ, RBIT,
        /// REV and REV16.
        fn bitOp(self: *Self, op: u8, op2: u4, dst: GeneralReg, src: GeneralReg) Allocator.Error!void {
            std.debug.assert(dst != .r15 and src != .r15);
            const inst: u32 = condBits(.al) |
                (@as(u32, op) << 20) |
                (0xF << 16) |
                (@as(u32, dst.enc()) << 12) |
                (0xF << 8) |
                (@as(u32, op2) << 4) |
                src.enc();
            try self.emit32(inst);
        }

        /// CLZ rd, rm (count leading zeros)
        pub fn clzRegReg(self: *Self, dst: GeneralReg, src: GeneralReg) Allocator.Error!void {
            try self.bitOp(0b0001_0110, 0b0001, dst, src);
        }

        /// RBIT rd, rm (reverse bits)
        pub fn rbitRegReg(self: *Self, dst: GeneralReg, src: GeneralReg) Allocator.Error!void {
            try self.bitOp(0b0110_1111, 0b0011, dst, src);
        }

        /// REV rd, rm (reverse bytes)
        pub fn revRegReg(self: *Self, dst: GeneralReg, src: GeneralReg) Allocator.Error!void {
            try self.bitOp(0b0110_1011, 0b0011, dst, src);
        }

        /// REV16 rd, rm (reverse bytes in each halfword)
        pub fn rev16RegReg(self: *Self, dst: GeneralReg, src: GeneralReg) Allocator.Error!void {
            try self.bitOp(0b0110_1011, 0b1011, dst, src);
        }

        /// cond 01101 op(3) 1111 Rd 00 00 0111 Rm (rotation 0)
        fn extend(self: *Self, op: u3, dst: GeneralReg, src: GeneralReg) Allocator.Error!void {
            std.debug.assert(dst != .r15 and src != .r15);
            const inst: u32 = condBits(.al) |
                (0b01101 << 23) |
                (@as(u32, op) << 20) |
                (0xF << 16) |
                (@as(u32, dst.enc()) << 12) |
                (0b0111 << 4) |
                src.enc();
            try self.emit32(inst);
        }

        /// UXTB rd, rm (zero-extend the low byte)
        pub fn uxtbRegReg(self: *Self, dst: GeneralReg, src: GeneralReg) Allocator.Error!void {
            try self.extend(0b110, dst, src);
        }

        /// UXTH rd, rm (zero-extend the low halfword)
        pub fn uxthRegReg(self: *Self, dst: GeneralReg, src: GeneralReg) Allocator.Error!void {
            try self.extend(0b111, dst, src);
        }

        /// SXTB rd, rm (sign-extend the low byte)
        pub fn sxtbRegReg(self: *Self, dst: GeneralReg, src: GeneralReg) Allocator.Error!void {
            try self.extend(0b010, dst, src);
        }

        /// SXTH rd, rm (sign-extend the low halfword)
        pub fn sxthRegReg(self: *Self, dst: GeneralReg, src: GeneralReg) Allocator.Error!void {
            try self.extend(0b011, dst, src);
        }

        /// cond 0111 1 op(2) widthm1(5) Rd lsb(5) 101 Rn
        fn bitfieldExtract(self: *Self, signed: bool, dst: GeneralReg, src: GeneralReg, lsb: u5, width: u6) Allocator.Error!void {
            std.debug.assert(dst != .r15 and src != .r15);
            std.debug.assert(width >= 1 and @as(u7, lsb) + width <= 32);
            const inst: u32 = condBits(.al) |
                (0b01111 << 23) |
                (@as(u32, if (signed) 0b01 else 0b11) << 21) |
                (@as(u32, width - 1) << 16) |
                (@as(u32, dst.enc()) << 12) |
                (@as(u32, lsb) << 7) |
                (0b101 << 4) |
                src.enc();
            try self.emit32(inst);
        }

        /// UBFX rd, rn, #lsb, #width (unsigned bitfield extract)
        pub fn ubfx(self: *Self, dst: GeneralReg, src: GeneralReg, lsb: u5, width: u6) Allocator.Error!void {
            try self.bitfieldExtract(false, dst, src, lsb, width);
        }

        /// SBFX rd, rn, #lsb, #width (signed bitfield extract)
        pub fn sbfx(self: *Self, dst: GeneralReg, src: GeneralReg, lsb: u5, width: u6) Allocator.Error!void {
            try self.bitfieldExtract(true, dst, src, lsb, width);
        }

        // Branches and calls

        /// Encode B<cond> (link = false) or BL (link = true, cond must be
        /// `al`). `offset_bytes` is relative to the branch instruction itself.
        pub fn encodeBranch(cond: Condition, link: bool, offset_bytes: i32) u32 {
            std.debug.assert(!link or cond == .al);
            std.debug.assert(@mod(offset_bytes, 4) == 0);
            const disp = (offset_bytes - 8) >> 2;
            std.debug.assert(disp >= -(1 << 23) and disp < (1 << 23));
            const imm24: u32 = @as(u24, @bitCast(@as(i24, @intCast(disp))));
            return condBits(cond) |
                (0b101 << 25) |
                (@as(u32, @intFromBool(link)) << 24) |
                imm24;
        }

        /// B label (unconditional branch)
        pub fn b(self: *Self, offset_bytes: i32) Allocator.Error!void {
            try self.emit32(encodeBranch(.al, false, offset_bytes));
        }

        /// B<cond> label
        pub fn bcond(self: *Self, cond: Condition, offset_bytes: i32) Allocator.Error!void {
            try self.emit32(encodeBranch(cond, false, offset_bytes));
        }

        /// BL label (branch with link). For a call through an `R_ARM_CALL`
        /// relocation the displacement is 0, which encodes the REL-form
        /// addend -8 (0xEBFFFFFE).
        pub fn bl(self: *Self, offset_bytes: i32) Allocator.Error!void {
            try self.emit32(encodeBranch(.al, true, offset_bytes));
        }

        /// BX rm (branch to register; bit 0 selects Thumb state)
        pub fn bxReg(self: *Self, reg: GeneralReg) Allocator.Error!void {
            // cond 0001 0010 1111 1111 1111 0001 Rm
            try self.emit32(condBits(.al) | 0x012FFF10 | @as(u32, reg.enc()));
        }

        /// BX lr: return
        pub fn ret(self: *Self) Allocator.Error!void {
            try self.bxReg(.lr);
        }

        /// BLX rm (call register; bit 0 selects Thumb state)
        pub fn blxReg(self: *Self, reg: GeneralReg) Allocator.Error!void {
            std.debug.assert(reg != .r15);
            // cond 0001 0010 1111 1111 1111 0011 Rm
            try self.emit32(condBits(.al) | 0x012FFF30 | @as(u32, reg.enc()));
        }

        /// UDF #imm16 (permanently undefined; traps)
        pub fn udf(self: *Self, imm16: u16) Allocator.Error!void {
            // 1110 0111 1111 imm12 1111 imm4
            try self.emit32(0xE7F000F0 | (@as(u32, imm16 >> 4) << 8) | (imm16 & 0xF));
        }

        /// BKPT #imm16 (breakpoint)
        pub fn bkpt(self: *Self, imm16: u16) Allocator.Error!void {
            // 1110 0001 0010 imm12 0111 imm4
            try self.emit32(0xE1200070 | (@as(u32, imm16 >> 4) << 8) | (imm16 & 0xF));
        }

        /// NOP (architectural hint)
        pub fn nop(self: *Self) Allocator.Error!void {
            try self.emit32(condBits(.al) | 0x0320F000);
        }

        /// Materialize the address of a data symbol position-independently:
        ///   MOVW rd, #0xFFF0   @ R_ARM_MOVW_PREL_NC at the returned offset
        ///   MOVT rd, #0xFFF4   @ R_ARM_MOVT_PREL at the returned offset + 4
        ///   ADD  rd, pc, rd
        /// PC reads as the ADD's address + 8, i.e. MOVW's address + 16, so the
        /// REL-form addends are -16 and -12, carried in the immediates.
        /// Returns the offset of the MOVW.
        pub fn pcRelAddress(self: *Self, dst: GeneralReg) Allocator.Error!u64 {
            std.debug.assert(dst != .r15);
            const offset = self.codeOffset();
            try self.movw(dst, 0xFFF0);
            try self.movt(dst, 0xFFF4);
            try self.addRegRegReg(dst, .r15, dst);
            return offset;
        }
    };
}

// Tests for the pure helpers.

test "modified immediate encoding" {
    try std.testing.expectEqual(@as(u12, 0x0FF), ModImm.encode(0xFF).?.bits);
    try std.testing.expectEqual(@as(u12, 0x4FF), ModImm.encode(0xFF000000).?.bits);
    try std.testing.expectEqual(@as(u12, 0x0), ModImm.encode(0).?.bits);
    try std.testing.expect(ModImm.encode(0x101) == null);
    try std.testing.expect(ModImm.encode(0x12345678) == null);

    // Every encodable value round-trips.
    var rot: u32 = 0;
    while (rot < 16) : (rot += 1) {
        var imm8: u32 = 0;
        while (imm8 < 256) : (imm8 += 1) {
            const v = std.math.rotr(u32, imm8, rot * 2);
            try std.testing.expectEqual(v, ModImm.encode(v).?.decode());
        }
    }
}

test "condition inversion" {
    try std.testing.expectEqual(Condition.ne, Condition.eq.invert());
    try std.testing.expectEqual(Condition.lt, Condition.ge.invert());
    try std.testing.expectEqual(Condition.ls, Condition.hi.invert());
}

test "branch encoding applies the PC bias" {
    const E = Emit(.arm32musl);
    // BL to itself: imm24 = -2
    try std.testing.expectEqual(@as(u32, 0xEBFFFFFE), E.encodeBranch(.al, true, 0));
    // B to the next-but-one instruction: imm24 = 0
    try std.testing.expectEqual(@as(u32, 0xEA000000), E.encodeBranch(.al, false, 8));
}
