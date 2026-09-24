//! ARM32 (A32) instruction encoding.
//!
//! This module provides low-level A32 instruction encoding for the dev backend.
//! It generates machine code bytes for ARMv7-A with NEON (VFPv3-D32) and
//! without the optional integer-divide extension.
//!
//! Note: All A32 instructions are 32 bits (4 bytes), little-endian, and must be
//! 4-byte aligned. A32 reads PC as the instruction's own address + 8; every
//! branch displacement taken here is relative to the instruction's own
//! address and the encoder applies that bias.
//!
//! Emitters encode exactly what they are asked to. Immediates that A32 cannot
//! encode are rejected by the argument types (`ModImm`) or by assertions whose
//! preconditions callers check with `fitsImmediate`; forming out-of-range
//! addresses in the scratch register is the caller's decision.
//!
//! The Emit function is parameterized by RocTarget to enable full cross-compilation.

const std = @import("std");
const Allocator = std.mem.Allocator;
const RocTarget = @import("roc_target").RocTarget;
const Registers = @import("Registers.zig");
const Call = @import("Call.zig");

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
        return @enumFromInt(@intFromEnum(self) ^ 1);
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

/// Load/store addressing forms, which differ in immediate-offset range.
pub const MemForm = enum {
    /// LDR/STR: ±4095
    word,
    /// LDRB/STRB: ±4095
    byte,
    /// LDRH/STRH: ±255
    halfword,
    /// LDRSB: ±255
    signed_byte,
    /// LDRSH: ±255
    signed_halfword,
    /// LDRD/STRD: ±255
    doubleword,
    /// VLDR/VSTR: ±1020 in multiples of 4
    vfp,
    /// NEON VLD1/VST1: no immediate offset
    neon,
};

/// Whether `offset` is encodable as the immediate offset of `form`.
pub fn fitsImmediate(form: MemForm, offset: i32) bool {
    return switch (form) {
        .word, .byte => offset >= -4095 and offset <= 4095,
        .halfword, .signed_byte, .signed_halfword, .doubleword => offset >= -255 and offset <= 255,
        .vfp => offset >= -1020 and offset <= 1020 and @mod(offset, 4) == 0,
        .neon => offset == 0,
    };
}

/// ARM32 instruction emitter for generating machine code.
/// Parameterized by target for cross-compilation support.
pub fn Emit(comptime target: RocTarget) type {
    // Validate this is an arm32 target
    if (target.toCpuArch() != .arm) {
        @compileError("arm32.Emit requires an arm32 target");
    }

    return struct {
        const Self = @This();

        // Re-export register types so CallBuilder can access them via EmitType
        pub const GeneralReg = Registers.GeneralReg;
        pub const FloatReg = Registers.FloatReg;
        pub const SReg = Registers.SReg;
        pub const DReg = Registers.DReg;
        pub const QReg = Registers.QReg;
        pub const RegisterWidth = Registers.RegisterWidth;

        /// The target this Emit was instantiated for
        pub const roc_target = target;

        /// Calling convention constants derived from target (AAPCS32, VFP
        /// variant).
        pub const CC = struct {
            pub const PARAM_REGS = Call.GENERAL_PARAM_REGS;

            pub const FLOAT_PARAM_REGS = Call.FLOAT_PARAM_REGS;

            /// C-ABI return registers: r0, or r0:r1 for 64-bit scalars.
            pub const RETURN_REGS = Call.GENERAL_RETURN_REGS;

            /// Roc-internal return registers for RocStr/RocList results of
            /// compiled-proc calls. Not subject to the C-ABI rule that
            /// composites wider than one word return through a hidden pointer.
            pub const ROC_RET_REGS = [3]Registers.GeneralReg{ .r0, .r1, .r2 };

            /// Operand width of every usize-typed value.
            pub const WORD: Registers.RegisterWidth = .w32;

            pub const SHADOW_SPACE: u8 = Call.SHADOW_SPACE_SIZE;
            /// C-ABI composites wider than one word return through a hidden
            /// pointer in r0. 64-bit *scalars* return in r0:r1 and are not
            /// subject to this threshold.
            pub const RETURN_BY_PTR_THRESHOLD: usize = 4;
            pub const PASS_BY_PTR_THRESHOLD: usize = std.math.maxInt(usize); // AAPCS32: composites are never passed by pointer

            pub const SCRATCH_REG = Call.SCRATCH_REG;
            pub const BASE_PTR = Call.BASE_PTR_REG;
            pub const STACK_PTR = Call.STACK_PTR_REG;
            pub const STACK_ALIGNMENT: u32 = Call.STACK_ALIGNMENT;

            /// Result-pointer save register (the X19/RBX analogue).
            pub const RESULT_PTR_SAVE_REG = Registers.GeneralReg.r9;
            /// RocOps save register (the X20/R12 analogue).
            pub const ROC_OPS_SAVE_REG = Registers.GeneralReg.r10;

            /// The frame pushes {fp, lr} and then sets fp = sp before pushing
            /// callee-saved registers, so incoming stack arguments start at
            /// [fp, #8].
            pub const INCOMING_STACK_ARG_BASE_OFFSET: u32 = 8;

            /// Align a stack size to the platform's required alignment.
            pub fn alignStackSize(size: u32) u32 {
                return (size + STACK_ALIGNMENT - 1) & ~(STACK_ALIGNMENT - 1);
            }
        };

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
            return @as(u32, @intFromEnum(cond)) << 28;
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
                    break :blk (imm5 << 7) | (@as(u32, @intFromEnum(s.kind)) << 5) | s.rm.enc();
                },
                .shift_reg => |s| blk: {
                    std.debug.assert(s.rm != .r15 and s.rs != .r15);
                    break :blk (@as(u32, s.rs.enc()) << 8) | (@as(u32, @intFromEnum(s.kind)) << 5) | (1 << 4) | s.rm.enc();
                },
            };
        }

        /// Generic data-processing instruction:
        /// cond 00 I opcode(4) S Rn(4) Rd(4) operand2(12)
        pub fn dataProc(self: *Self, cond: Condition, op: DataOp, set_flags: bool, rd: GeneralReg, rn: GeneralReg, op2: Operand2) Allocator.Error!void {
            if (op.isCompare()) std.debug.assert(set_flags and rd == .r0);
            if (op.isMove()) std.debug.assert(rn == .r0);
            const inst: u32 = condBits(cond) |
                (@as(u32, @intFromEnum(op)) << 21) |
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

        /// cond 0000 opc(4) Rd/RdHi(4) Ra/RdLo(4) Rm(4) 1001 Rn(4)
        fn multiply(self: *Self, opc: u4, set_flags: bool, hi: GeneralReg, lo: GeneralReg, rm: GeneralReg, rn: GeneralReg) Allocator.Error!void {
            std.debug.assert(hi != .r15 and lo != .r15 and rm != .r15 and rn != .r15);
            const inst: u32 = condBits(.al) |
                (@as(u32, opc) << 21) |
                (@as(u32, @intFromBool(set_flags)) << 20) |
                (@as(u32, hi.enc()) << 16) |
                (@as(u32, lo.enc()) << 12) |
                (@as(u32, rm.enc()) << 8) |
                (0b1001 << 4) |
                rn.enc();
            try self.emit32(inst);
        }

        /// MUL rd, rn, rm (low 32 bits of the product)
        pub fn mulRegRegReg(self: *Self, dst: GeneralReg, src1: GeneralReg, src2: GeneralReg) Allocator.Error!void {
            try self.multiply(0b0000, false, dst, .r0, src2, src1);
        }

        /// MLA rd, rn, rm, ra (rd = ra + rn * rm)
        pub fn mlaRegRegRegReg(self: *Self, dst: GeneralReg, src1: GeneralReg, src2: GeneralReg, addend: GeneralReg) Allocator.Error!void {
            try self.multiply(0b0001, false, dst, addend, src2, src1);
        }

        /// MLS rd, rn, rm, ra (rd = ra - rn * rm)
        pub fn mlsRegRegRegReg(self: *Self, dst: GeneralReg, src1: GeneralReg, src2: GeneralReg, minuend: GeneralReg) Allocator.Error!void {
            try self.multiply(0b0011, false, dst, minuend, src2, src1);
        }

        /// UMULL rdlo, rdhi, rn, rm (unsigned 32x32 -> 64)
        pub fn umull(self: *Self, dst_lo: GeneralReg, dst_hi: GeneralReg, src1: GeneralReg, src2: GeneralReg) Allocator.Error!void {
            std.debug.assert(dst_lo != dst_hi);
            try self.multiply(0b0100, false, dst_hi, dst_lo, src2, src1);
        }

        /// UMLAL rdlo, rdhi, rn, rm (rdhi:rdlo += unsigned rn * rm)
        pub fn umlal(self: *Self, dst_lo: GeneralReg, dst_hi: GeneralReg, src1: GeneralReg, src2: GeneralReg) Allocator.Error!void {
            std.debug.assert(dst_lo != dst_hi);
            try self.multiply(0b0101, false, dst_hi, dst_lo, src2, src1);
        }

        /// SMULL rdlo, rdhi, rn, rm (signed 32x32 -> 64)
        pub fn smull(self: *Self, dst_lo: GeneralReg, dst_hi: GeneralReg, src1: GeneralReg, src2: GeneralReg) Allocator.Error!void {
            std.debug.assert(dst_lo != dst_hi);
            try self.multiply(0b0110, false, dst_hi, dst_lo, src2, src1);
        }

        /// SMLAL rdlo, rdhi, rn, rm (rdhi:rdlo += signed rn * rm)
        pub fn smlal(self: *Self, dst_lo: GeneralReg, dst_hi: GeneralReg, src1: GeneralReg, src2: GeneralReg) Allocator.Error!void {
            std.debug.assert(dst_lo != dst_hi);
            try self.multiply(0b0111, false, dst_hi, dst_lo, src2, src1);
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
            try self.emit32(0xE320F000);
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

        // Loads and stores

        /// cond 010 P U B W L Rn Rt imm12, offset addressing (P=1, W=0)
        fn loadStoreWordByte(self: *Self, load: bool, byte: bool, rt: GeneralReg, rn: GeneralReg, offset: i32) Allocator.Error!void {
            std.debug.assert(fitsImmediate(if (byte) .byte else .word, offset));
            const up = offset >= 0;
            const inst: u32 = condBits(.al) |
                (0b010 << 25) |
                (1 << 24) |
                (@as(u32, @intFromBool(up)) << 23) |
                (@as(u32, @intFromBool(byte)) << 22) |
                (@as(u32, @intFromBool(load)) << 20) |
                (@as(u32, rn.enc()) << 16) |
                (@as(u32, rt.enc()) << 12) |
                @as(u32, @abs(offset));
            try self.emit32(inst);
        }

        /// LDR rt, [rn, #offset]
        pub fn ldrRegMem(self: *Self, dst: GeneralReg, base: GeneralReg, offset: i32) Allocator.Error!void {
            try self.loadStoreWordByte(true, false, dst, base, offset);
        }

        /// STR rt, [rn, #offset]
        pub fn strRegMem(self: *Self, src: GeneralReg, base: GeneralReg, offset: i32) Allocator.Error!void {
            try self.loadStoreWordByte(false, false, src, base, offset);
        }

        /// LDRB rt, [rn, #offset] (zero-extending)
        pub fn ldrbRegMem(self: *Self, dst: GeneralReg, base: GeneralReg, offset: i32) Allocator.Error!void {
            std.debug.assert(dst != .r15);
            try self.loadStoreWordByte(true, true, dst, base, offset);
        }

        /// STRB rt, [rn, #offset]
        pub fn strbRegMem(self: *Self, src: GeneralReg, base: GeneralReg, offset: i32) Allocator.Error!void {
            std.debug.assert(src != .r15);
            try self.loadStoreWordByte(false, true, src, base, offset);
        }

        /// cond 000 P U 1 W L Rn Rt imm4H 1 op2(2) 1 imm4L, offset addressing
        fn loadStoreMisc(self: *Self, form: MemForm, load: bool, op2: u2, rt: GeneralReg, rn: GeneralReg, offset: i32) Allocator.Error!void {
            std.debug.assert(fitsImmediate(form, offset));
            std.debug.assert(rt != .r15);
            const up = offset >= 0;
            const mag: u32 = @abs(offset);
            const inst: u32 = condBits(.al) |
                (1 << 24) |
                (@as(u32, @intFromBool(up)) << 23) |
                (1 << 22) |
                (@as(u32, @intFromBool(load)) << 20) |
                (@as(u32, rn.enc()) << 16) |
                (@as(u32, rt.enc()) << 12) |
                ((mag >> 4) << 8) |
                (1 << 7) |
                (@as(u32, op2) << 5) |
                (1 << 4) |
                (mag & 0xF);
            try self.emit32(inst);
        }

        /// LDRH rt, [rn, #offset] (zero-extending)
        pub fn ldrhRegMem(self: *Self, dst: GeneralReg, base: GeneralReg, offset: i32) Allocator.Error!void {
            try self.loadStoreMisc(.halfword, true, 0b01, dst, base, offset);
        }

        /// STRH rt, [rn, #offset]
        pub fn strhRegMem(self: *Self, src: GeneralReg, base: GeneralReg, offset: i32) Allocator.Error!void {
            try self.loadStoreMisc(.halfword, false, 0b01, src, base, offset);
        }

        /// LDRSB rt, [rn, #offset] (sign-extending)
        pub fn ldrsbRegMem(self: *Self, dst: GeneralReg, base: GeneralReg, offset: i32) Allocator.Error!void {
            try self.loadStoreMisc(.signed_byte, true, 0b10, dst, base, offset);
        }

        /// LDRSH rt, [rn, #offset] (sign-extending)
        pub fn ldrshRegMem(self: *Self, dst: GeneralReg, base: GeneralReg, offset: i32) Allocator.Error!void {
            try self.loadStoreMisc(.signed_halfword, true, 0b11, dst, base, offset);
        }

        /// LDRD rt, rt+1, [rn, #offset]. rt must be even and not r14; the
        /// address must be 4-byte aligned.
        pub fn ldrdRegMem(self: *Self, dst_lo: GeneralReg, base: GeneralReg, offset: i32) Allocator.Error!void {
            std.debug.assert(dst_lo.enc() % 2 == 0 and dst_lo != .r14);
            // LDRD is encoded with L=0, op2=10.
            try self.loadStoreMisc(.doubleword, false, 0b10, dst_lo, base, offset);
        }

        /// STRD rt, rt+1, [rn, #offset]. rt must be even and not r14; the
        /// address must be 4-byte aligned.
        pub fn strdRegMem(self: *Self, src_lo: GeneralReg, base: GeneralReg, offset: i32) Allocator.Error!void {
            std.debug.assert(src_lo.enc() % 2 == 0 and src_lo != .r14);
            // STRD is encoded with L=0, op2=11.
            try self.loadStoreMisc(.doubleword, false, 0b11, src_lo, base, offset);
        }

        /// PUSH {list} (STMDB sp!, {list}). The list names at least two
        /// registers; a single-register push has a different encoding.
        pub fn push(self: *Self, list: u16) Allocator.Error!void {
            std.debug.assert(@popCount(list) >= 2);
            std.debug.assert(list & GeneralReg.sp.listBit() == 0);
            try self.emit32(condBits(.al) | 0x092D0000 | @as(u32, list));
        }

        /// POP {list} (LDMIA sp!, {list}). The list names at least two
        /// registers; a single-register pop has a different encoding.
        pub fn pop(self: *Self, list: u16) Allocator.Error!void {
            std.debug.assert(@popCount(list) >= 2);
            std.debug.assert(list & GeneralReg.sp.listBit() == 0);
            try self.emit32(condBits(.al) | 0x08BD0000 | @as(u32, list));
        }

        // VFP
        //
        // A VFP register number splits into a 4-bit field and a 1-bit field
        // whose positions depend on precision: an S register s[n] is
        // Vx = n >> 1 with the extra bit n & 1, a D register d[n] is
        // Vx = n & 15 with the extra bit n >> 4.

        const VfpPrecision = enum(u1) { f32 = 0, f64 = 1 };

        const VfpField = struct {
            four: u4,
            one: u1,

            fn s(reg: SReg) VfpField {
                return .{ .four = @intCast(reg.enc() >> 1), .one = @intCast(reg.enc() & 1) };
            }

            fn d(reg: DReg) VfpField {
                return .{ .four = @intCast(reg.enc() & 15), .one = @intCast(reg.enc() >> 4) };
            }
        };

        /// cond 1110 opc1(4 with D at bit 22) Vn Vd 101 sz N opc3 M 0 Vm
        /// `base` supplies bits 27:20 (minus D), 19:16 when Vn is fixed, and
        /// the opcode bits 7:6.
        fn vfpDataProc(self: *Self, base: u32, sz: VfpPrecision, vd: VfpField, vn: VfpField, vm: VfpField) Allocator.Error!void {
            const inst: u32 = condBits(.al) |
                base |
                (@as(u32, vd.one) << 22) |
                (@as(u32, vn.four) << 16) |
                (@as(u32, vd.four) << 12) |
                (0b101 << 9) |
                (@as(u32, @intFromEnum(sz)) << 8) |
                (@as(u32, vn.one) << 7) |
                (@as(u32, vm.one) << 5) |
                vm.four;
            try self.emit32(inst);
        }

        const vfp_zero: VfpField = .{ .four = 0, .one = 0 };

        const VADD = 0x0E300000;
        const VSUB = 0x0E300040;
        const VMUL = 0x0E200000;
        const VDIV = 0x0E800000;
        const VMOV = 0x0EB00040;
        const VABS = 0x0EB000C0;
        const VNEG = 0x0EB10040;
        const VSQRT = 0x0EB100C0;
        const VCMP = 0x0EB40040;
        const VCMPE = 0x0EB400C0;
        const VCMP_ZERO = 0x0EB50040;
        const VCVT_PRECISION = 0x0EB700C0;

        /// VADD.F32 sd, sn, sm
        pub fn vaddF32(self: *Self, dst: SReg, src1: SReg, src2: SReg) Allocator.Error!void {
            try self.vfpDataProc(VADD, .f32, .s(dst), .s(src1), .s(src2));
        }

        /// VADD.F64 dd, dn, dm
        pub fn vaddF64(self: *Self, dst: DReg, src1: DReg, src2: DReg) Allocator.Error!void {
            try self.vfpDataProc(VADD, .f64, .d(dst), .d(src1), .d(src2));
        }

        /// VSUB.F32 sd, sn, sm
        pub fn vsubF32(self: *Self, dst: SReg, src1: SReg, src2: SReg) Allocator.Error!void {
            try self.vfpDataProc(VSUB, .f32, .s(dst), .s(src1), .s(src2));
        }

        /// VSUB.F64 dd, dn, dm
        pub fn vsubF64(self: *Self, dst: DReg, src1: DReg, src2: DReg) Allocator.Error!void {
            try self.vfpDataProc(VSUB, .f64, .d(dst), .d(src1), .d(src2));
        }

        /// VMUL.F32 sd, sn, sm
        pub fn vmulF32(self: *Self, dst: SReg, src1: SReg, src2: SReg) Allocator.Error!void {
            try self.vfpDataProc(VMUL, .f32, .s(dst), .s(src1), .s(src2));
        }

        /// VMUL.F64 dd, dn, dm
        pub fn vmulF64(self: *Self, dst: DReg, src1: DReg, src2: DReg) Allocator.Error!void {
            try self.vfpDataProc(VMUL, .f64, .d(dst), .d(src1), .d(src2));
        }

        /// VDIV.F32 sd, sn, sm
        pub fn vdivF32(self: *Self, dst: SReg, src1: SReg, src2: SReg) Allocator.Error!void {
            try self.vfpDataProc(VDIV, .f32, .s(dst), .s(src1), .s(src2));
        }

        /// VDIV.F64 dd, dn, dm
        pub fn vdivF64(self: *Self, dst: DReg, src1: DReg, src2: DReg) Allocator.Error!void {
            try self.vfpDataProc(VDIV, .f64, .d(dst), .d(src1), .d(src2));
        }

        /// VMOV.F32 sd, sm
        pub fn vmovF32(self: *Self, dst: SReg, src: SReg) Allocator.Error!void {
            try self.vfpDataProc(VMOV, .f32, .s(dst), vfp_zero, .s(src));
        }

        /// VMOV.F64 dd, dm
        pub fn vmovF64(self: *Self, dst: DReg, src: DReg) Allocator.Error!void {
            try self.vfpDataProc(VMOV, .f64, .d(dst), vfp_zero, .d(src));
        }

        /// VABS.F32 sd, sm
        pub fn vabsF32(self: *Self, dst: SReg, src: SReg) Allocator.Error!void {
            try self.vfpDataProc(VABS, .f32, .s(dst), vfp_zero, .s(src));
        }

        /// VABS.F64 dd, dm
        pub fn vabsF64(self: *Self, dst: DReg, src: DReg) Allocator.Error!void {
            try self.vfpDataProc(VABS, .f64, .d(dst), vfp_zero, .d(src));
        }

        /// VNEG.F32 sd, sm
        pub fn vnegF32(self: *Self, dst: SReg, src: SReg) Allocator.Error!void {
            try self.vfpDataProc(VNEG, .f32, .s(dst), vfp_zero, .s(src));
        }

        /// VNEG.F64 dd, dm
        pub fn vnegF64(self: *Self, dst: DReg, src: DReg) Allocator.Error!void {
            try self.vfpDataProc(VNEG, .f64, .d(dst), vfp_zero, .d(src));
        }

        /// VSQRT.F32 sd, sm
        pub fn vsqrtF32(self: *Self, dst: SReg, src: SReg) Allocator.Error!void {
            try self.vfpDataProc(VSQRT, .f32, .s(dst), vfp_zero, .s(src));
        }

        /// VSQRT.F64 dd, dm
        pub fn vsqrtF64(self: *Self, dst: DReg, src: DReg) Allocator.Error!void {
            try self.vfpDataProc(VSQRT, .f64, .d(dst), vfp_zero, .d(src));
        }

        /// VCMP.F32 sd, sm (quiet NaNs do not raise Invalid Operation)
        pub fn vcmpF32(self: *Self, lhs: SReg, rhs: SReg) Allocator.Error!void {
            try self.vfpDataProc(VCMP, .f32, .s(lhs), vfp_zero, .s(rhs));
        }

        /// VCMP.F64 dd, dm (quiet NaNs do not raise Invalid Operation)
        pub fn vcmpF64(self: *Self, lhs: DReg, rhs: DReg) Allocator.Error!void {
            try self.vfpDataProc(VCMP, .f64, .d(lhs), vfp_zero, .d(rhs));
        }

        /// VCMPE.F32 sd, sm (any NaN raises Invalid Operation)
        pub fn vcmpeF32(self: *Self, lhs: SReg, rhs: SReg) Allocator.Error!void {
            try self.vfpDataProc(VCMPE, .f32, .s(lhs), vfp_zero, .s(rhs));
        }

        /// VCMPE.F64 dd, dm (any NaN raises Invalid Operation)
        pub fn vcmpeF64(self: *Self, lhs: DReg, rhs: DReg) Allocator.Error!void {
            try self.vfpDataProc(VCMPE, .f64, .d(lhs), vfp_zero, .d(rhs));
        }

        /// VCMP.F32 sd, #0.0
        pub fn vcmpZeroF32(self: *Self, lhs: SReg) Allocator.Error!void {
            try self.vfpDataProc(VCMP_ZERO, .f32, .s(lhs), vfp_zero, vfp_zero);
        }

        /// VCMP.F64 dd, #0.0
        pub fn vcmpZeroF64(self: *Self, lhs: DReg) Allocator.Error!void {
            try self.vfpDataProc(VCMP_ZERO, .f64, .d(lhs), vfp_zero, vfp_zero);
        }

        /// VMRS APSR_nzcv, FPSCR (copy the VFP comparison flags to the core
        /// flags; required between VCMP and a conditional instruction)
        pub fn vmrsApsrNzcv(self: *Self) Allocator.Error!void {
            try self.emit32(0xEEF1FA10);
        }

        /// VCVT.F64.F32 dd, sm
        pub fn vcvtF64FromF32(self: *Self, dst: DReg, src: SReg) Allocator.Error!void {
            // sz names the source precision: 0 = single to double.
            try self.vfpDataProc(VCVT_PRECISION, .f32, .d(dst), vfp_zero, .s(src));
        }

        /// VCVT.F32.F64 sd, dm
        pub fn vcvtF32FromF64(self: *Self, dst: SReg, src: DReg) Allocator.Error!void {
            try self.vfpDataProc(VCVT_PRECISION, .f64, .s(dst), vfp_zero, .d(src));
        }

        /// VCVT between float and 32-bit integer:
        /// cond 1110 1D11 1 opc2(3) Vd 101 sz op 1 M 0 Vm
        /// To integer: opc2 = 10 signed, op = 1 (round toward zero); the
        /// integer is always in an S register. To float: opc2 = 000, op =
        /// signed.
        fn vcvtInt(self: *Self, opc2: u3, op: u1, sz: VfpPrecision, vd: VfpField, vm: VfpField) Allocator.Error!void {
            const base: u32 = 0x0EB80040 | (@as(u32, opc2) << 16) | (@as(u32, op) << 7);
            try self.vfpDataProc(base, sz, vd, vfp_zero, vm);
        }

        /// VCVT.S32.F32 sd, sm (round toward zero)
        pub fn vcvtS32FromF32(self: *Self, dst: SReg, src: SReg) Allocator.Error!void {
            try self.vcvtInt(0b101, 1, .f32, .s(dst), .s(src));
        }

        /// VCVT.U32.F32 sd, sm (round toward zero)
        pub fn vcvtU32FromF32(self: *Self, dst: SReg, src: SReg) Allocator.Error!void {
            try self.vcvtInt(0b100, 1, .f32, .s(dst), .s(src));
        }

        /// VCVT.S32.F64 sd, dm (round toward zero)
        pub fn vcvtS32FromF64(self: *Self, dst: SReg, src: DReg) Allocator.Error!void {
            try self.vcvtInt(0b101, 1, .f64, .s(dst), .d(src));
        }

        /// VCVT.U32.F64 sd, dm (round toward zero)
        pub fn vcvtU32FromF64(self: *Self, dst: SReg, src: DReg) Allocator.Error!void {
            try self.vcvtInt(0b100, 1, .f64, .s(dst), .d(src));
        }

        /// VCVT.F32.S32 sd, sm
        pub fn vcvtF32FromS32(self: *Self, dst: SReg, src: SReg) Allocator.Error!void {
            try self.vcvtInt(0b000, 1, .f32, .s(dst), .s(src));
        }

        /// VCVT.F32.U32 sd, sm
        pub fn vcvtF32FromU32(self: *Self, dst: SReg, src: SReg) Allocator.Error!void {
            try self.vcvtInt(0b000, 0, .f32, .s(dst), .s(src));
        }

        /// VCVT.F64.S32 dd, sm
        pub fn vcvtF64FromS32(self: *Self, dst: DReg, src: SReg) Allocator.Error!void {
            try self.vcvtInt(0b000, 1, .f64, .d(dst), .s(src));
        }

        /// VCVT.F64.U32 dd, sm
        pub fn vcvtF64FromU32(self: *Self, dst: DReg, src: SReg) Allocator.Error!void {
            try self.vcvtInt(0b000, 0, .f64, .d(dst), .s(src));
        }

        /// cond 1110 000 op Vn Rt 1010 N 001 0000
        fn vmovCoreSingle(self: *Self, to_core: bool, rt: GeneralReg, sn: SReg) Allocator.Error!void {
            std.debug.assert(rt != .r13 and rt != .r15);
            const vn = VfpField.s(sn);
            const inst: u32 = condBits(.al) |
                0x0E000A10 |
                (@as(u32, @intFromBool(to_core)) << 20) |
                (@as(u32, vn.four) << 16) |
                (@as(u32, rt.enc()) << 12) |
                (@as(u32, vn.one) << 7);
            try self.emit32(inst);
        }

        /// VMOV rt, sn (core register from S register bits)
        pub fn vmovCoreFromS(self: *Self, dst: GeneralReg, src: SReg) Allocator.Error!void {
            try self.vmovCoreSingle(true, dst, src);
        }

        /// VMOV sn, rt (S register from core register bits)
        pub fn vmovSFromCore(self: *Self, dst: SReg, src: GeneralReg) Allocator.Error!void {
            try self.vmovCoreSingle(false, src, dst);
        }

        /// cond 1100 010 op Rt2 Rt 1011 00 M 1 Vm
        fn vmovCorePairDouble(self: *Self, to_core: bool, rt: GeneralReg, rt2: GeneralReg, dm: DReg) Allocator.Error!void {
            std.debug.assert(rt != .r13 and rt != .r15 and rt2 != .r13 and rt2 != .r15);
            if (to_core) std.debug.assert(rt != rt2);
            const vm = VfpField.d(dm);
            const inst: u32 = condBits(.al) |
                0x0C400B10 |
                (@as(u32, @intFromBool(to_core)) << 20) |
                (@as(u32, rt2.enc()) << 16) |
                (@as(u32, rt.enc()) << 12) |
                (@as(u32, vm.one) << 5) |
                vm.four;
            try self.emit32(inst);
        }

        /// VMOV rt, rt2, dm (core pair from D register bits; rt gets the
        /// low word)
        pub fn vmovCorePairFromD(self: *Self, dst_lo: GeneralReg, dst_hi: GeneralReg, src: DReg) Allocator.Error!void {
            try self.vmovCorePairDouble(true, dst_lo, dst_hi, src);
        }

        /// VMOV dm, rt, rt2 (D register bits from a core pair; rt is the low
        /// word)
        pub fn vmovDFromCorePair(self: *Self, dst: DReg, src_lo: GeneralReg, src_hi: GeneralReg) Allocator.Error!void {
            try self.vmovCorePairDouble(false, src_lo, src_hi, dst);
        }

        /// cond 1101 U D 0 L Rn Vd 101 sz imm8
        fn vfpLoadStore(self: *Self, load: bool, sz: VfpPrecision, vd: VfpField, rn: GeneralReg, offset: i32) Allocator.Error!void {
            std.debug.assert(fitsImmediate(.vfp, offset));
            const up = offset >= 0;
            const inst: u32 = condBits(.al) |
                0x0D000A00 |
                (@as(u32, @intFromBool(up)) << 23) |
                (@as(u32, vd.one) << 22) |
                (@as(u32, @intFromBool(load)) << 20) |
                (@as(u32, rn.enc()) << 16) |
                (@as(u32, vd.four) << 12) |
                (@as(u32, @intFromEnum(sz)) << 8) |
                (@as(u32, @abs(offset)) >> 2);
            try self.emit32(inst);
        }

        /// VLDR sd, [rn, #offset]
        pub fn vldrF32(self: *Self, dst: SReg, base: GeneralReg, offset: i32) Allocator.Error!void {
            try self.vfpLoadStore(true, .f32, .s(dst), base, offset);
        }

        /// VSTR sd, [rn, #offset]
        pub fn vstrF32(self: *Self, src: SReg, base: GeneralReg, offset: i32) Allocator.Error!void {
            try self.vfpLoadStore(false, .f32, .s(src), base, offset);
        }

        /// VLDR dd, [rn, #offset]
        pub fn vldrF64(self: *Self, dst: DReg, base: GeneralReg, offset: i32) Allocator.Error!void {
            try self.vfpLoadStore(true, .f64, .d(dst), base, offset);
        }

        /// VSTR dd, [rn, #offset]
        pub fn vstrF64(self: *Self, src: DReg, base: GeneralReg, offset: i32) Allocator.Error!void {
            try self.vfpLoadStore(false, .f64, .d(src), base, offset);
        }

        /// cond 110 P U D W L 1101 Vd 1011 imm8 (imm8 = 2 * count)
        fn vfpPushPop(self: *Self, base: u32, first: DReg, count: u5) Allocator.Error!void {
            std.debug.assert(count >= 1 and count <= 16 and @as(u6, first.enc()) + count <= 32);
            const vd = VfpField.d(first);
            const inst: u32 = condBits(.al) |
                base |
                (@as(u32, vd.one) << 22) |
                (@as(u32, vd.four) << 12) |
                (@as(u32, count) * 2);
            try self.emit32(inst);
        }

        /// VPUSH {d<first>-d<first+count-1>} (VSTMDB sp!)
        pub fn vpush(self: *Self, first: DReg, count: u5) Allocator.Error!void {
            try self.vfpPushPop(0x0D2D0B00, first, count);
        }

        /// VPOP {d<first>-d<first+count-1>} (VLDMIA sp!)
        pub fn vpop(self: *Self, first: DReg, count: u5) Allocator.Error!void {
            try self.vfpPushPop(0x0CBD0B00, first, count);
        }
    }; // end of struct returned by Emit
}

// Tests for the pure helpers. Every emitter is covered byte-exactly by
// encoding_oracle_tests.zig, generated from ci/arm32_encoding_oracle.s.

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

test "immediate offset ranges per form" {
    try std.testing.expect(fitsImmediate(.word, 4095));
    try std.testing.expect(fitsImmediate(.word, -4095));
    try std.testing.expect(!fitsImmediate(.word, 4096));
    try std.testing.expect(fitsImmediate(.doubleword, -255));
    try std.testing.expect(!fitsImmediate(.doubleword, 256));
    try std.testing.expect(!fitsImmediate(.halfword, -256));
    try std.testing.expect(fitsImmediate(.vfp, 1020));
    try std.testing.expect(!fitsImmediate(.vfp, 1024));
    try std.testing.expect(!fitsImmediate(.vfp, 2));
    try std.testing.expect(fitsImmediate(.neon, 0));
    try std.testing.expect(!fitsImmediate(.neon, 4));
}

test "branch encoding applies the PC bias" {
    const E = Emit(.arm32musl);
    // BL to itself: imm24 = -2
    try std.testing.expectEqual(@as(u32, 0xEBFFFFFE), E.encodeBranch(.al, true, 0));
    // B to the next-but-one instruction: imm24 = 0
    try std.testing.expectEqual(@as(u32, 0xEA000000), E.encodeBranch(.al, false, 8));
}

test "stack size alignment" {
    const CC = Emit(.arm32musl).CC;
    try std.testing.expectEqual(@as(u32, 8), CC.alignStackSize(4));
    try std.testing.expectEqual(@as(u32, 16), CC.alignStackSize(16));
}
