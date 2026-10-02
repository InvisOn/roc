//! arm32 (A32) code generation: the per-ISA `CodeGen` that `LirCodeGen`
//! drives, providing register allocation, stack slots, and the ISA-neutral
//! instruction-selection facade with the same names and signatures as the
//! x86_64 and aarch64 code generators.
//!
//! Register pools (D5, D10 of projects/big/arm32-dev-backend.md): general
//! temporaries are r0-r3 (caller-saved) then r4-r10 (callee-saved, recorded
//! for the prologue); r11 is the frame pointer and r12 the scratch register,
//! never allocated. Float temporaries are the even D registers d0, d2, d4 and
//! d6: each is also a Q register (q0-q3) and has an S view, so any allocated
//! `FloatReg` can hold an f32, an f64 or a 128-bit vector. Vectors also have
//! q8-q15 (d16-d30 even, caller-saved under AAPCS32), which have no S view
//! and so are handed out only by `allocVector`.
//!
//! Every memory access honours its form's offset range (`fitsImmediate`);
//! out of range, the address is formed in LR first (`Call.ADDRESS_SCRATCH_REG`),
//! so r12 can be the base or the data register of any access. Division is not here:
//! ARMv7-A without the integer-divide extension divides by calling the
//! `__aeabi_*` helpers (D7), which the driver models as calls.

const std = @import("std");
const Allocator = std.mem.Allocator;
const RocTarget = @import("roc_target").RocTarget;
const CpuLevel = @import("roc_target").CpuLevel;

const EmitMod = @import("Emit.zig");
const Registers = @import("Registers.zig");
const Call = @import("Call.zig");
const Relocation = @import("../Relocation.zig").IndexedRelocation;
const SymbolTable = @import("../SymbolTable.zig");
const FrameBuilderMod = @import("../FrameBuilder.zig");

const GeneralReg = Registers.GeneralReg;
const FloatReg = Registers.FloatReg;
const DReg = Registers.DReg;
const QReg = Registers.QReg;
const RegisterWidth = Registers.RegisterWidth;
const ModImm = EmitMod.ModImm;
const MemForm = EmitMod.MemForm;
const fitsImmediate = EmitMod.fitsImmediate;
const Condition = EmitMod.Condition;

/// Parameterized arm32 code generator. All arm32 targets use AAPCS32 with the
/// VFP (hard-float) variant.
pub fn CodeGen(comptime target: RocTarget) type {
    if (target.toCpuArch() != .arm) {
        @compileError("arm32.CodeGen requires an arm target");
    }

    const Emit = EmitMod.Emit(target);
    const scratch: GeneralReg = Call.SCRATCH_REG;
    const address_scratch: GeneralReg = Call.ADDRESS_SCRATCH_REG;
    const fp: GeneralReg = Call.BASE_PTR_REG;

    return struct {
        const Self = @This();

        /// The target this CodeGen was instantiated for
        pub const roc_target = target;

        /// Number of general-purpose registers
        pub const NUM_GENERAL_REGS = 16;
        /// Number of float registers (D view)
        pub const NUM_FLOAT_REGS = 32;

        /// Caller-saved general registers available as temporaries: r0-r3.
        pub const INITIAL_FREE_GENERAL: u32 = Call.CALLER_SAVED_GENERAL_MASK;

        /// Float temporaries with S views: d0, d2, d4, d6 (q0-q3). Odd D
        /// registers are the high halves of those Q registers and are never
        /// allocated alone.
        pub const SCALAR_FLOAT_MASK: u32 =
            (1 << @intFromEnum(DReg.d0)) |
            (1 << @intFromEnum(DReg.d2)) |
            (1 << @intFromEnum(DReg.d4)) |
            (1 << @intFromEnum(DReg.d6));

        /// Vector-only temporaries: d16, d18, ..., d30 (q8-q15). They have no
        /// S view, so an f32 never lives there.
        pub const VECTOR_ONLY_FLOAT_MASK: u32 = 0x5555_0000;

        /// Every float temporary.
        pub const INITIAL_FREE_FLOAT: u32 = SCALAR_FLOAT_MASK | VECTOR_ONLY_FLOAT_MASK;

        /// Callee-saved general registers available after r0-r3: r4-r10.
        pub const CALLEE_SAVED_GENERAL_MASK: u32 = Call.CALLEE_SAVED_GENERAL_MASK;

        /// Size of the callee-saved area below fp (r4-r10 at fixed slots);
        /// the driver starts local slots below it.
        pub const CALLEE_SAVED_AREA_SIZE: i32 = 28;

        /// Most general registers that can be in use at once, pinned or
        /// temporary: the whole allocatable pool (D10). There is no spill
        /// path.
        pub const MAX_TEMP_GENERAL: u8 = @popCount(INITIAL_FREE_GENERAL | CALLEE_SAVED_GENERAL_MASK);

        /// Most float registers that can be in use at once.
        pub const MAX_TEMP_FLOAT: u8 = @popCount(INITIAL_FREE_FLOAT);

        /// How old a CPU the emitted instructions must run on. arm32 has one
        /// level (the D2 floor); the field keeps the shared signature.
        cpu_level: CpuLevel,

        /// The most general registers in use at once when a temporary was
        /// allocated (D10 budget measurement).
        general_high_water: u8 = 0,

        /// The float-register counterpart of `general_high_water`.
        float_high_water: u8 = 0,

        emit: Emit,
        allocator: Allocator,
        stack_offset: i32,
        relocations: std.ArrayList(Relocation),
        symbols: SymbolTable.Table = .{},
        free_general: u32,
        free_float: u32,
        /// Callee-saved general registers used, as an r0-r15 bit mask.
        callee_saved_used: u32,
        /// Remaining callee-saved registers available for allocation.
        callee_saved_available: u32,

        pub fn init(allocator: Allocator, cpu_level: CpuLevel) Self {
            return .{
                .cpu_level = cpu_level,
                .emit = Emit.init(allocator),
                .allocator = allocator,
                .stack_offset = 0,
                .relocations = .empty,
                .free_general = INITIAL_FREE_GENERAL,
                .free_float = INITIAL_FREE_FLOAT,
                .callee_saved_used = 0,
                .callee_saved_available = CALLEE_SAVED_GENERAL_MASK,
            };
        }

        pub fn deinit(self: *Self) void {
            self.emit.deinit();
            self.relocations.deinit(self.allocator);
            self.symbols.deinit(self.allocator);
        }

        pub fn reset(self: *Self) void {
            self.emit.buf.clearRetainingCapacity();
            self.relocations.clearRetainingCapacity();
            self.symbols.clearRetainingCapacity();
            self.stack_offset = 0;
            self.free_general = INITIAL_FREE_GENERAL;
            self.free_float = INITIAL_FREE_FLOAT;
            self.callee_saved_used = 0;
            self.callee_saved_available = CALLEE_SAVED_GENERAL_MASK;
        }

        /// Get the generated code
        pub fn getCode(self: *Self) []const u8 {
            return self.emit.buf.items;
        }

        /// Get current code offset
        pub fn currentOffset(self: *Self) usize {
            return self.emit.buf.items.len;
        }

        // Register allocation. LirCodeGen keeps every semantic local in its
        // stable-location table; these masks manage only bounded, short-lived
        // instruction-selection temporaries.

        /// Allocate a short-lived general register. Exhausting the bounded
        /// pool is a lifetime-invariant failure, never a reason to spill.
        pub fn allocTempGeneral(self: *Self) GeneralReg {
            const reg = self.allocGeneral() orelse std.debug.panic(
                "LirCodeGen invariant violated: bounded instruction selection exhausted the general-register pool",
                .{},
            );
            const free = (self.free_general & INITIAL_FREE_GENERAL) | (self.callee_saved_available & CALLEE_SAVED_GENERAL_MASK);
            const in_use: u8 = MAX_TEMP_GENERAL - @as(u8, @popCount(free));
            self.general_high_water = @max(self.general_high_water, in_use);
            return reg;
        }

        /// Allocate a short-lived float register; see `allocTempGeneral`.
        pub fn allocTempFloat(self: *Self) FloatReg {
            const reg = self.allocFloat() orelse std.debug.panic(
                "LirCodeGen invariant violated: bounded instruction selection exhausted the float-register pool",
                .{},
            );
            const in_use: u8 = MAX_TEMP_FLOAT - @as(u8, @popCount(self.free_float & INITIAL_FREE_FLOAT));
            self.float_high_water = @max(self.float_high_water, in_use);
            return reg;
        }

        pub fn allocGeneral(self: *Self) ?GeneralReg {
            if (takeLowest(&self.free_general)) |bit| return @enumFromInt(bit);
            if (takeLowest(&self.callee_saved_available)) |bit| {
                self.callee_saved_used |= @as(u32, 1) << bit;
                return @enumFromInt(bit);
            }
            return null;
        }

        fn takeLowest(mask: *u32) ?u5 {
            if (mask.* == 0) return null;
            const bit: u5 = @intCast(@ctz(mask.*));
            mask.* &= ~(@as(u32, 1) << bit);
            return bit;
        }

        /// Free a general-purpose register.
        pub fn freeGeneral(self: *Self, reg: GeneralReg) void {
            const bit = @as(u32, 1) << @intCast(reg.enc());
            if ((CALLEE_SAVED_GENERAL_MASK & bit) != 0) {
                self.callee_saved_available |= bit;
            } else {
                self.free_general |= bit;
            }
        }

        /// Mark a register as in use so it won't be allocated.
        pub fn markRegisterInUse(self: *Self, reg: GeneralReg) void {
            const bit = @as(u32, 1) << @intCast(reg.enc());
            self.free_general &= ~bit;
            self.callee_saved_available &= ~bit;
        }

        /// A float register for an f32 or f64: one with an S view.
        pub fn allocFloat(self: *Self) ?FloatReg {
            return self.takeFloat(SCALAR_FLOAT_MASK);
        }

        /// A float register for a 128-bit vector: q8-q15 first, keeping
        /// q0-q3 for scalars.
        pub fn allocVector(self: *Self) ?FloatReg {
            return self.takeFloat(VECTOR_ONLY_FLOAT_MASK) orelse self.takeFloat(SCALAR_FLOAT_MASK);
        }

        fn takeFloat(self: *Self, pool: u32) ?FloatReg {
            var available = self.free_float & pool;
            const bit = takeLowest(&available) orelse return null;
            self.free_float &= ~(@as(u32, 1) << bit);
            return @enumFromInt(bit);
        }

        pub fn freeFloat(self: *Self, reg: FloatReg) void {
            std.debug.assert((INITIAL_FREE_FLOAT & (@as(u32, 1) << reg.enc())) != 0);
            self.free_float |= @as(u32, 1) << reg.enc();
        }

        // Stack management

        pub fn allocStack(self: *Self, size: u32) i32 {
            // 16-byte alignment for vectors and 128-bit values, 8 otherwise
            // (doubleword and VFP accesses).
            const alignment: u32 = if (size > 8) 16 else 8;
            const aligned_size = (size + alignment - 1) & ~(alignment - 1);
            self.stack_offset -= @intCast(aligned_size);
            self.stack_offset &= ~@as(i32, @intCast(alignment - 1));
            return self.stack_offset;
        }

        /// Alias for allocStack - allocate a stack slot of the given size
        pub fn allocStackSlot(self: *Self, size: u32) i32 {
            return self.allocStack(size);
        }

        pub fn getStackSize(self: *Self) u32 {
            const size: u32 = @intCast(-self.stack_offset);
            return Emit.CC.alignStackSize(size);
        }

        // Function prologue/epilogue

        /// Deferred frame builder type for this architecture.
        pub const DeferredFrameBuilder = FrameBuilderMod.DeferredFrameBuilder(Emit);

        pub fn emitPrologueWithAlloc(self: *Self, stack_size: u32) Allocator.Error!void {
            try self.emitPrologueWithAllocAndStackProbe(stack_size, false);
        }

        pub fn emitPrologueWithAllocAndStackProbe(self: *Self, stack_size: u32, stack_probe_required: bool) Allocator.Error!void {
            var builder = DeferredFrameBuilder.init();
            builder.setCalleeSavedMask(self.callee_saved_used);
            builder.setStackSize(stack_size);
            builder.setStackProbeRequired(stack_probe_required);
            _ = try builder.emitPrologue(&self.emit);
        }

        pub fn emitEpilogue(self: *Self) Allocator.Error!void {
            var builder = DeferredFrameBuilder.init();
            builder.setCalleeSavedMask(self.callee_saved_used);
            try builder.emitEpilogue(&self.emit);
        }

        // Immediates and addresses

        /// Load a constant that fits a word (as a signed or an unsigned
        /// 32-bit value) into `dst`. A value that fits neither is a Wide64
        /// reaching a single register, which the driver never produces.
        pub fn emitLoadImm(self: *Self, dst: GeneralReg, value: i64) Allocator.Error!void {
            try self.emit.movRegImm32(dst, wordBits(value));
        }

        /// The 32-bit pattern of an immediate that fits a word.
        fn wordBits(value: i64) u32 {
            if (value < std.math.minInt(i32) or value > std.math.maxInt(u32)) {
                std.debug.panic("arm32 invariant violated: immediate {d} does not fit a 32-bit register", .{value});
            }
            return @truncate(@as(u64, @bitCast(value)));
        }

        /// dst = base + offset, for any offset. Uses `dst` for the constant
        /// when it cannot be an immediate, so `dst` must differ from `base`
        /// in that case.
        fn emitAddrOf(self: *Self, dst: GeneralReg, base: GeneralReg, offset: i32) Allocator.Error!void {
            const magnitude: u32 = @abs(offset);
            if (ModImm.encode(magnitude)) |imm| {
                if (offset >= 0) {
                    try self.emit.addRegRegModImm(dst, base, imm);
                } else {
                    try self.emit.subRegRegModImm(dst, base, imm);
                }
                return;
            }
            std.debug.assert(dst != base);
            try self.emit.movRegImm32(dst, @bitCast(offset));
            try self.emit.addRegRegReg(dst, base, dst);
        }

        /// The base and offset an access of `form` at `base + offset` uses:
        /// the original pair when the offset is in range, otherwise LR
        /// holding the address and offset 0.
        fn reachable(self: *Self, form: MemForm, base: GeneralReg, offset: i32) Allocator.Error!struct { base: GeneralReg, offset: i32 } {
            if (fitsImmediate(form, offset)) return .{ .base = base, .offset = offset };
            std.debug.assert(base != address_scratch);
            try self.emitAddrOf(address_scratch, base, offset);
            return .{ .base = address_scratch, .offset = 0 };
        }

        pub fn emitLoadDataAddress(self: *Self, dst: GeneralReg, symbol: SymbolTable.Id) Allocator.Error!void {
            const at = try self.emit.pcRelAddress(dst);
            try self.relocations.append(self.allocator, .{ .linked_data = .{ .offset = at, .symbol = symbol, .kind = .arm_movw_prel } });
            try self.relocations.append(self.allocator, .{ .linked_data = .{ .offset = at + 4, .symbol = symbol, .kind = .arm_movt_prel } });
        }

        /// Rewrite the `pcRelAddress` sequence at `instr_offset` to address
        /// code offset `target_offset` of this buffer.
        pub fn patchInternalCodeAddress(self: *Self, instr_offset: usize, target_offset: usize) void {
            // The ADD reads PC as the MOVW's address + 16.
            const value: u32 = @bitCast(@as(i32, @intCast(@as(i64, @intCast(target_offset)) - @as(i64, @intCast(instr_offset + 16)))));
            const dst = regAt(self.readInst(instr_offset));
            self.writeInst(instr_offset, Emit.encodeMovwMovt(false, dst, @truncate(value)));
            self.writeInst(instr_offset + 4, Emit.encodeMovwMovt(true, dst, @truncate(value >> 16)));
        }

        /// The Rd field of a data-processing or MOVW/MOVT instruction.
        fn regAt(inst: u32) GeneralReg {
            return @enumFromInt(@as(u4, @truncate(inst >> 12)));
        }

        fn readInst(self: *Self, at: usize) u32 {
            return std.mem.readInt(u32, self.emit.buf.items[at..][0..4], .little);
        }

        fn writeInst(self: *Self, at: usize, inst: u32) void {
            std.mem.writeInt(u32, self.emit.buf.items[at..][0..4], inst, .little);
        }

        // Integer operations (3-operand; `width` is always the word)

        pub fn emitAdd(self: *Self, _: RegisterWidth, dst: GeneralReg, a: GeneralReg, b: GeneralReg) Allocator.Error!void {
            try self.emit.addRegRegReg(dst, a, b);
        }

        pub fn emitSub(self: *Self, _: RegisterWidth, dst: GeneralReg, a: GeneralReg, b: GeneralReg) Allocator.Error!void {
            try self.emit.subRegRegReg(dst, a, b);
        }

        pub fn emitMul(self: *Self, _: RegisterWidth, dst: GeneralReg, a: GeneralReg, b: GeneralReg) Allocator.Error!void {
            try self.emit.mulRegRegReg(dst, a, b);
        }

        pub fn emitNeg(self: *Self, _: RegisterWidth, dst: GeneralReg, src: GeneralReg) Allocator.Error!void {
            try self.emit.rsbRegRegModImm(dst, src, ModImm.of(0));
        }

        pub fn emitAnd(self: *Self, _: RegisterWidth, dst: GeneralReg, a: GeneralReg, b: GeneralReg) Allocator.Error!void {
            try self.emit.andRegRegReg(dst, a, b);
        }

        pub fn emitOr(self: *Self, _: RegisterWidth, dst: GeneralReg, a: GeneralReg, b: GeneralReg) Allocator.Error!void {
            try self.emit.orrRegRegReg(dst, a, b);
        }

        pub fn emitXor(self: *Self, _: RegisterWidth, dst: GeneralReg, a: GeneralReg, b: GeneralReg) Allocator.Error!void {
            try self.emit.eorRegRegReg(dst, a, b);
        }

        pub fn emitNot(self: *Self, _: RegisterWidth, dst: GeneralReg, src: GeneralReg) Allocator.Error!void {
            try self.emit.mvnRegReg(dst, src);
        }

        pub fn emitAddRegs(self: *Self, comptime _: anytype, dst: GeneralReg, src1: GeneralReg, src2: GeneralReg) Allocator.Error!void {
            try self.emit.addRegRegReg(dst, src1, src2);
        }

        pub fn emitSubRegs(self: *Self, comptime _: anytype, dst: GeneralReg, src1: GeneralReg, src2: GeneralReg) Allocator.Error!void {
            try self.emit.subRegRegReg(dst, src1, src2);
        }

        pub fn emitMulRegs(self: *Self, comptime _: anytype, dst: GeneralReg, src1: GeneralReg, src2: GeneralReg) Allocator.Error!void {
            try self.emit.mulRegRegReg(dst, src1, src2);
        }

        pub fn emitAndRegs(self: *Self, comptime _: anytype, dst: GeneralReg, src1: GeneralReg, src2: GeneralReg) Allocator.Error!void {
            try self.emit.andRegRegReg(dst, src1, src2);
        }

        pub fn emitOrRegs(self: *Self, comptime _: anytype, dst: GeneralReg, src1: GeneralReg, src2: GeneralReg) Allocator.Error!void {
            try self.emit.orrRegRegReg(dst, src1, src2);
        }

        /// dst = src + imm
        pub fn emitAddImm(self: *Self, dst: GeneralReg, src: GeneralReg, imm: i32) Allocator.Error!void {
            try self.emitAddSignedImm(dst, src, imm);
        }

        /// dst = src - imm
        pub fn emitSubImm(self: *Self, comptime _: anytype, dst: GeneralReg, src: GeneralReg, imm: i32) Allocator.Error!void {
            try self.emitAddSignedImm(dst, src, -imm);
        }

        fn emitAddSignedImm(self: *Self, dst: GeneralReg, src: GeneralReg, imm: i32) Allocator.Error!void {
            if (ModImm.encode(@abs(imm))) |mod| {
                if (imm >= 0) {
                    try self.emit.addRegRegModImm(dst, src, mod);
                } else {
                    try self.emit.subRegRegModImm(dst, src, mod);
                }
                return;
            }
            std.debug.assert(src != scratch);
            try self.emit.movRegImm32(scratch, @bitCast(imm));
            try self.emit.addRegRegReg(dst, src, scratch);
        }

        /// dst = max(a - b, 0) for unsigned words
        pub fn emitSaturatingSub(self: *Self, dst: GeneralReg, a: GeneralReg, b: GeneralReg) Allocator.Error!void {
            try self.emit.subsRegRegReg(dst, a, b);
            try self.emit.movRegModImmCond(.lo, dst, ModImm.of(0));
        }

        pub fn emitShlImm(self: *Self, comptime _: anytype, dst: GeneralReg, src: GeneralReg, amount: u8) Allocator.Error!void {
            try self.emit.lslRegRegImm(dst, src, @intCast(amount));
        }

        pub fn emitLsrImm(self: *Self, comptime _: anytype, dst: GeneralReg, src: GeneralReg, amount: u8) Allocator.Error!void {
            try self.emit.lsrRegRegImm(dst, src, @intCast(amount));
        }

        pub fn emitAsrImm(self: *Self, comptime _: anytype, dst: GeneralReg, src: GeneralReg, amount: u8) Allocator.Error!void {
            try self.emit.asrRegRegImm(dst, src, @intCast(amount));
        }

        /// dst = number of trailing zero bits of the word `src` (32 when
        /// `src` is zero): reverse the bits, then count leading zeros.
        pub fn emitCtzWord(self: *Self, dst: GeneralReg, src: GeneralReg) Allocator.Error!void {
            try self.emit.rbitRegReg(dst, src);
            try self.emit.clzRegReg(dst, dst);
        }

        // Comparisons

        /// dst = (a cond b) ? 1 : 0
        pub fn emitCmp(self: *Self, _: RegisterWidth, dst: GeneralReg, a: GeneralReg, b: GeneralReg, cond: Condition) Allocator.Error!void {
            try self.emit.cmpRegReg(a, b);
            try self.emitSetCond(dst, cond);
        }

        /// dst = cond ? 1 : 0 from the current flags
        pub fn emitSetCond(self: *Self, dst: GeneralReg, cond: Condition) Allocator.Error!void {
            try self.emit.movRegModImm(dst, ModImm.of(0));
            try self.emit.movRegModImmCond(cond, dst, ModImm.of(1));
        }

        /// Compare a general register against an immediate that fits a word.
        pub fn emitCmpImm(self: *Self, reg: GeneralReg, value: i64) Allocator.Error!void {
            const bits = wordBits(value);
            if (ModImm.encode(bits)) |imm| {
                try self.emit.cmpRegModImm(reg, imm);
            } else if (ModImm.encode(-%bits)) |imm| {
                try self.emit.cmnRegModImm(reg, imm);
            } else {
                std.debug.assert(reg != scratch);
                try self.emit.movRegImm32(scratch, bits);
                try self.emit.cmpRegReg(reg, scratch);
            }
        }

        /// dst = (a cond b) ? 1 : 0 for f64 (VCMP, flags to APSR)
        pub fn emitCmpF64(self: *Self, dst: GeneralReg, a: FloatReg, b: FloatReg, cond: Condition) Allocator.Error!void {
            try self.emit.vcmpF64(a, b);
            try self.emit.vmrsApsrNzcv();
            try self.emitSetCond(dst, cond);
        }

        /// dst = (a cond b) ? 1 : 0 for f32
        pub fn emitCmpF32(self: *Self, dst: GeneralReg, a: FloatReg, b: FloatReg, cond: Condition) Allocator.Error!void {
            try self.emit.vcmpF32(a.sLow(), b.sLow());
            try self.emit.vmrsApsrNzcv();
            try self.emitSetCond(dst, cond);
        }

        pub fn condEqual() Condition {
            return .eq;
        }

        pub fn condNotEqual() Condition {
            return .ne;
        }

        pub fn condLess() Condition {
            return .lt;
        }

        pub fn condLessOrEqual() Condition {
            return .le;
        }

        pub fn condGreater() Condition {
            return .gt;
        }

        pub fn condGreaterOrEqual() Condition {
            return .ge;
        }

        pub fn condBelow() Condition {
            return .lo;
        }

        pub fn condBelowOrEqual() Condition {
            return .ls;
        }

        pub fn condAbove() Condition {
            return .hi;
        }

        pub fn condAboveOrEqual() Condition {
            return .hs;
        }

        pub fn condOverflow() Condition {
            return .vs;
        }

        /// ADDS sets C on unsigned overflow.
        pub fn condUnsignedAddOverflow() Condition {
            return .hs;
        }

        /// SUBS clears C on unsigned borrow.
        pub fn condUnsignedSubOverflow() Condition {
            return .lo;
        }

        // After VCMP + VMRS an unordered result sets C and V and clears N and
        // Z, so each of these is false when either operand is NaN.

        /// Condition testing `lhs < rhs` after a float compare.
        pub fn condFloatLess() Condition {
            return .mi;
        }

        /// Condition testing `lhs <= rhs` after a float compare.
        pub fn condFloatLessOrEqual() Condition {
            return .ls;
        }

        /// Condition testing `lhs > rhs` after a float compare.
        pub fn condFloatGreater() Condition {
            return .gt;
        }

        /// Condition testing `lhs >= rhs` after a float compare.
        pub fn condFloatGreaterOrEqual() Condition {
            return .ge;
        }

        // Floating point. f32 values live in the S view of their D register.

        pub fn emitAddF64(self: *Self, dst: FloatReg, a: FloatReg, b: FloatReg) Allocator.Error!void {
            try self.emit.vaddF64(dst, a, b);
        }

        pub fn emitSubF64(self: *Self, dst: FloatReg, a: FloatReg, b: FloatReg) Allocator.Error!void {
            try self.emit.vsubF64(dst, a, b);
        }

        pub fn emitMulF64(self: *Self, dst: FloatReg, a: FloatReg, b: FloatReg) Allocator.Error!void {
            try self.emit.vmulF64(dst, a, b);
        }

        pub fn emitDivF64(self: *Self, dst: FloatReg, a: FloatReg, b: FloatReg) Allocator.Error!void {
            try self.emit.vdivF64(dst, a, b);
        }

        pub fn emitNegF64(self: *Self, dst: FloatReg, src: FloatReg) Allocator.Error!void {
            try self.emit.vnegF64(dst, src);
        }

        pub fn emitAbsF64(self: *Self, dst: FloatReg, src: FloatReg) Allocator.Error!void {
            try self.emit.vabsF64(dst, src);
        }

        pub fn emitAddF32(self: *Self, dst: FloatReg, a: FloatReg, b: FloatReg) Allocator.Error!void {
            try self.emit.vaddF32(dst.sLow(), a.sLow(), b.sLow());
        }

        pub fn emitSubF32(self: *Self, dst: FloatReg, a: FloatReg, b: FloatReg) Allocator.Error!void {
            try self.emit.vsubF32(dst.sLow(), a.sLow(), b.sLow());
        }

        pub fn emitMulF32(self: *Self, dst: FloatReg, a: FloatReg, b: FloatReg) Allocator.Error!void {
            try self.emit.vmulF32(dst.sLow(), a.sLow(), b.sLow());
        }

        pub fn emitDivF32(self: *Self, dst: FloatReg, a: FloatReg, b: FloatReg) Allocator.Error!void {
            try self.emit.vdivF32(dst.sLow(), a.sLow(), b.sLow());
        }

        pub fn emitNegF32(self: *Self, dst: FloatReg, src: FloatReg) Allocator.Error!void {
            try self.emit.vnegF32(dst.sLow(), src.sLow());
        }

        pub fn emitAbsF32(self: *Self, dst: FloatReg, src: FloatReg) Allocator.Error!void {
            try self.emit.vabsF32(dst.sLow(), src.sLow());
        }

        // Memory: general registers

        /// Load a word from [base_reg + offset]
        pub fn emitLoad(self: *Self, comptime _: anytype, dst: GeneralReg, base_reg: GeneralReg, offset: i32) Allocator.Error!void {
            const at = try self.reachable(.word, base_reg, offset);
            try self.emit.ldrRegMem(dst, at.base, at.offset);
        }

        /// Store a word to [base_reg + offset]
        pub fn emitStore(self: *Self, comptime _: anytype, base_reg: GeneralReg, offset: i32, src: GeneralReg) Allocator.Error!void {
            const at = try self.reachable(.word, base_reg, offset);
            try self.emit.strRegMem(src, at.base, at.offset);
        }

        pub fn emitLoadW8(self: *Self, dst: GeneralReg, base_reg: GeneralReg, offset: i32) Allocator.Error!void {
            const at = try self.reachable(.byte, base_reg, offset);
            try self.emit.ldrbRegMem(dst, at.base, at.offset);
        }

        pub fn emitLoadW16(self: *Self, dst: GeneralReg, base_reg: GeneralReg, offset: i32) Allocator.Error!void {
            const at = try self.reachable(.halfword, base_reg, offset);
            try self.emit.ldrhRegMem(dst, at.base, at.offset);
        }

        pub fn emitStoreW8(self: *Self, base_reg: GeneralReg, offset: i32, src: GeneralReg) Allocator.Error!void {
            const at = try self.reachable(.byte, base_reg, offset);
            try self.emit.strbRegMem(src, at.base, at.offset);
        }

        pub fn emitStoreW16(self: *Self, base_reg: GeneralReg, offset: i32, src: GeneralReg) Allocator.Error!void {
            const at = try self.reachable(.halfword, base_reg, offset);
            try self.emit.strhRegMem(src, at.base, at.offset);
        }

        pub fn emitLoadStack(self: *Self, comptime width: anytype, dst: GeneralReg, offset: i32) Allocator.Error!void {
            try self.emitLoad(width, dst, fp, offset);
        }

        pub fn emitStoreStack(self: *Self, comptime width: anytype, offset: i32, src: GeneralReg) Allocator.Error!void {
            try self.emitStore(width, fp, offset, src);
        }

        pub fn emitLoadStackW8(self: *Self, dst: GeneralReg, offset: i32) Allocator.Error!void {
            try self.emitLoadW8(dst, fp, offset);
        }

        pub fn emitLoadStackW16(self: *Self, dst: GeneralReg, offset: i32) Allocator.Error!void {
            try self.emitLoadW16(dst, fp, offset);
        }

        pub fn emitStoreStackW8(self: *Self, offset: i32, src: GeneralReg) Allocator.Error!void {
            try self.emitStoreW8(fp, offset, src);
        }

        pub fn emitStoreStackW16(self: *Self, offset: i32, src: GeneralReg) Allocator.Error!void {
            try self.emitStoreW16(fp, offset, src);
        }

        pub fn emitLoadStackByte(self: *Self, dst: GeneralReg, offset: i32) Allocator.Error!void {
            try self.emitLoadW8(dst, fp, offset);
        }

        pub fn emitLoadStackHalfword(self: *Self, dst: GeneralReg, offset: i32) Allocator.Error!void {
            try self.emitLoadW16(dst, fp, offset);
        }

        /// dst = fp + offset
        pub fn emitLeaStack(self: *Self, dst: GeneralReg, offset: i32) Allocator.Error!void {
            try self.emitAddrOf(dst, fp, offset);
        }

        /// sp += imm
        pub fn emitAddStackPtr(self: *Self, imm: i32) Allocator.Error!void {
            try self.emitAddSignedImm(Call.STACK_PTR_REG, Call.STACK_PTR_REG, imm);
        }

        /// Store a discriminant value at [fp + offset]. A discriminant is a
        /// variant index, so the high word of an eight-byte one is zero.
        pub fn storeDiscriminant(self: *Self, offset: i32, value: u32, disc_size: u8) Allocator.Error!void {
            if (disc_size == 0) return;
            const reg = self.allocTempGeneral();
            defer self.freeGeneral(reg);
            try self.emitLoadImm(reg, value);
            switch (disc_size) {
                1 => try self.emitStoreStackW8(offset, reg),
                2 => try self.emitStoreStackW16(offset, reg),
                4 => try self.emitStoreStack(.w32, offset, reg),
                8 => {
                    try self.emitStoreStack(.w32, offset, reg);
                    try self.emitLoadImm(reg, 0);
                    try self.emitStoreStack(.w32, offset + 4, reg);
                },
                else => unreachable,
            }
        }

        // Memory: VFP and NEON registers

        pub fn emitLoadStackF64(self: *Self, dst: FloatReg, offset: i32) Allocator.Error!void {
            const at = try self.reachable(.vfp, fp, offset);
            try self.emit.vldrF64(dst, at.base, at.offset);
        }

        pub fn emitStoreStackF64(self: *Self, offset: i32, src: FloatReg) Allocator.Error!void {
            const at = try self.reachable(.vfp, fp, offset);
            try self.emit.vstrF64(src, at.base, at.offset);
        }

        pub fn emitLoadStackF32(self: *Self, dst: FloatReg, offset: i32) Allocator.Error!void {
            const at = try self.reachable(.vfp, fp, offset);
            try self.emit.vldrF32(dst.sLow(), at.base, at.offset);
        }

        pub fn emitStoreStackF32(self: *Self, offset: i32, src: FloatReg) Allocator.Error!void {
            const at = try self.reachable(.vfp, fp, offset);
            try self.emit.vstrF32(src.sLow(), at.base, at.offset);
        }

        /// Store the f64 in `src_reg` to [ptr_reg]
        pub fn emitStoreFloatToMem(self: *Self, ptr_reg: GeneralReg, src_reg: FloatReg) Allocator.Error!void {
            try self.emit.vstrF64(src_reg, ptr_reg, 0);
        }

        /// The Q register whose low half is `reg`.
        fn quad(reg: FloatReg) QReg {
            std.debug.assert(reg.enc() % 2 == 0);
            return reg.containingQ();
        }

        pub fn emitLoadV128(self: *Self, dst: FloatReg, base: GeneralReg, offset: i32) Allocator.Error!void {
            const at = try self.reachable(.neon, base, offset);
            try self.emit.vld1Q(quad(dst), at.base);
        }

        pub fn emitStoreV128(self: *Self, base: GeneralReg, offset: i32, src: FloatReg) Allocator.Error!void {
            const at = try self.reachable(.neon, base, offset);
            try self.emit.vst1Q(quad(src), at.base);
        }

        pub fn emitLoadStackV128(self: *Self, dst: FloatReg, offset: i32) Allocator.Error!void {
            try self.emitLoadV128(dst, fp, offset);
        }

        pub fn emitStoreStackV128(self: *Self, offset: i32, src: FloatReg) Allocator.Error!void {
            try self.emitStoreV128(fp, offset, src);
        }

        pub fn emitMoveV128(self: *Self, dst: FloatReg, src: FloatReg) Allocator.Error!void {
            if (dst != src) try self.emit.neonLogicQ(.vorr, quad(dst), quad(src), quad(src));
        }

        // C-ABI float registers (AAPCS32 VFP: an f32 homogeneous aggregate
        // uses s0-s3, an f64 one d0-d3, a vector q0-q1).

        /// Store piece `index` of a hosted call's float result to the frame.
        pub fn emitHostedFloatResultStore(self: *Self, dst_off: i32, index: usize, size: u8) Allocator.Error!void {
            try self.storeFloatPiece(dst_off, index, size);
        }

        /// Store an incoming VFP argument to [fp + dest_off]. `s_index` is
        /// the value's first S register, AAPCS32's numbering of the VFP
        /// argument registers: an f64 starts at an even one (d = s/2), a
        /// vector at a multiple of four.
        pub fn emitEntryVfpArgStore(self: *Self, dest_off: i32, s_index: u16, size: u8) Allocator.Error!void {
            switch (size) {
                4 => {
                    const at = try self.reachable(.vfp, fp, dest_off);
                    try self.emit.vstrF32(@enumFromInt(@as(u5, @intCast(s_index))), at.base, at.offset);
                },
                8 => try self.emitStoreStackF64(dest_off, @enumFromInt(@as(u5, @intCast(s_index / 2)))),
                16 => try self.emitStoreStackV128(dest_off, @enumFromInt(@as(u5, @intCast(s_index / 2)))),
                else => unreachable,
            }
        }

        /// Load C-ABI float return piece `index` from the frame into its
        /// return register.
        pub fn emitEntryFloatLoad(self: *Self, src_off: i32, index: usize, size: u8) Allocator.Error!void {
            switch (size) {
                4 => {
                    const at = try self.reachable(.vfp, fp, src_off);
                    try self.emit.vldrF32(@enumFromInt(@as(u5, @intCast(index))), at.base, at.offset);
                },
                8 => try self.emitLoadStackF64(@enumFromInt(@as(u5, @intCast(index))), src_off),
                16 => try self.emitLoadStackV128(@enumFromInt(@as(u5, @intCast(index * 2))), src_off),
                else => unreachable,
            }
        }

        fn storeFloatPiece(self: *Self, dst_off: i32, index: usize, size: u8) Allocator.Error!void {
            switch (size) {
                4 => {
                    const at = try self.reachable(.vfp, fp, dst_off);
                    try self.emit.vstrF32(@enumFromInt(@as(u5, @intCast(index))), at.base, at.offset);
                },
                8 => try self.emitStoreStackF64(dst_off, @enumFromInt(@as(u5, @intCast(index)))),
                16 => try self.emitStoreStackV128(dst_off, @enumFromInt(@as(u5, @intCast(index * 2)))),
                else => unreachable,
            }
        }

        // Control flow. A32 B/BL/Bcc reach ±32 MiB, so no site needs an
        // island or a veneer. A patch location is the branch instruction's
        // own offset.

        /// Emit an unconditional branch placeholder; returns its location.
        pub fn emitJump(self: *Self) Allocator.Error!usize {
            const at = self.currentOffset();
            try self.emit.b(0);
            return at;
        }

        /// Emit a conditional branch placeholder; returns its location.
        pub fn emitCondJump(self: *Self, cond: Condition) Allocator.Error!usize {
            const at = self.currentOffset();
            try self.emit.bcond(cond, 0);
            return at;
        }

        pub fn emitJumpIfNotEqual(self: *Self) Allocator.Error!usize {
            return self.emitCondJump(.ne);
        }

        pub fn emitJumpIfEqual(self: *Self) Allocator.Error!usize {
            return self.emitCondJump(.eq);
        }

        pub fn emitJumpPlaceholder(self: *Self) Allocator.Error!usize {
            return self.emitJump();
        }

        /// Point the branch at `patch_loc` to `target_loc`, keeping its
        /// condition and link bit.
        pub fn patchJump(self: *Self, patch_loc: usize, target_loc: usize) Allocator.Error!void {
            self.retargetBranch(patch_loc, target_loc);
        }

        fn retargetBranch(self: *Self, loc: usize, target_loc: usize) void {
            const inst = self.readInst(loc);
            std.debug.assert((inst >> 25) & 7 == 0b101);
            const cond: Condition = @enumFromInt(@as(u4, @truncate(inst >> 28)));
            const link = (inst >> 24) & 1 == 1;
            const offset: i32 = @intCast(@as(i64, @intCast(target_loc)) - @as(i64, @intCast(loc)));
            self.writeInst(loc, Emit.encodeBranch(cond, link, offset));
        }

        /// Emit a BL to code offset `target_loc` of this buffer.
        pub fn emitDirectCall(self: *Self, target_loc: usize) Allocator.Error!enum { call, inline_call } {
            const offset: i32 = @intCast(@as(i64, @intCast(target_loc)) - @as(i64, @intCast(self.currentOffset())));
            try self.emit.bl(offset);
            return .call;
        }

        /// Re-encode a call emitted by `emitDirectCall` after its site or its
        /// target moved.
        pub fn patchDirectCall(self: *Self, loc: usize, target_loc: usize) void {
            self.retargetBranch(loc, target_loc);
        }

        /// Emit a BL placeholder; returns its location for `patchCall`.
        pub fn emitCallPlaceholder(self: *Self) Allocator.Error!usize {
            const at = self.currentOffset();
            try self.emit.bl(0);
            return at;
        }

        /// Point the BL at `patch_loc` to `target_loc`.
        pub fn patchCall(self: *Self, patch_loc: usize, target_loc: usize) Allocator.Error!void {
            self.retargetBranch(patch_loc, target_loc);
        }

        /// Emit a BL to a linked symbol, recorded as an `R_ARM_CALL`
        /// relocation.
        pub fn emitCall(self: *Self, symbol: SymbolTable.Id) Allocator.Error!void {
            const at = self.currentOffset();
            try self.emit.bl(0);
            try self.relocations.append(self.allocator, .{ .linked_function = .{ .offset = at, .symbol = symbol } });
        }

        /// Whether the instruction at `loc` is a BL.
        pub fn isBlAt(self: *Self, loc: usize) bool {
            return (self.readInst(loc) & 0x0F000000) == 0x0B000000;
        }

        /// Raise SIGILL (`UDF #0`), like x86's UD2.
        pub fn emitTrap(self: *Self) Allocator.Error!void {
            try self.emit.udf(0);
        }

        /// The register holding a scalar C-ABI result.
        pub fn getReturnRegister(_: *Self) GeneralReg {
            return .r0;
        }

        /// Producer-authored placement metadata: A32 calls reach every target
        /// in a buffer directly, so no site has a veneer.
        pub fn codeRefVeneer(_: *const Self, _: usize) ?usize {
            return null;
        }

        /// Record the veneer an assembled reference uses. arm32 has none.
        pub fn registerAssembledRefVeneer(_: *Self, _: usize, _: ?usize) Allocator.Error!void {}

        /// Remove placement-specific stub displacements. arm32 emits none.
        pub fn normalizeArtifactCode(_: *const Self, _: usize, _: []u8) void {}
    };
}

// Tests: each facade method emits exactly the Emit sequence it documents
// (whose bytes the encoding oracle pins).

const MuslCodeGen = CodeGen(.arm32musl);
const MuslEmit = EmitMod.Emit(.arm32musl);

fn expectCode(cg: *MuslCodeGen, expected: *MuslEmit) error{TestExpectedEqual}!void {
    try std.testing.expectEqualSlices(u8, expected.buf.items, cg.getCode());
}

test "temporaries come from r0-r3, then r4-r10, recorded as callee-saved" {
    var cg = MuslCodeGen.init(std.testing.allocator, .default);
    defer cg.deinit();
    try std.testing.expectEqual(@as(u8, 11), MuslCodeGen.MAX_TEMP_GENERAL);
    var regs: [11]GeneralReg = undefined;
    for (&regs) |*reg| reg.* = cg.allocTempGeneral();
    try std.testing.expectEqual(GeneralReg.r0, regs[0]);
    try std.testing.expectEqual(GeneralReg.r3, regs[3]);
    try std.testing.expectEqual(GeneralReg.r4, regs[4]);
    try std.testing.expectEqual(GeneralReg.r10, regs[10]);
    try std.testing.expect(cg.allocGeneral() == null);
    try std.testing.expectEqual(@as(u8, 11), cg.general_high_water);
    try std.testing.expectEqual(Call.CALLEE_SAVED_GENERAL_MASK, @as(u16, @intCast(cg.callee_saved_used)));
    for (regs) |reg| cg.freeGeneral(reg);
    try std.testing.expectEqual(GeneralReg.r0, cg.allocTempGeneral());
}

test "float temporaries are the even D registers d0-d6, each a Q register" {
    var cg = MuslCodeGen.init(std.testing.allocator, .default);
    defer cg.deinit();
    const expected = [_]FloatReg{ .d0, .d2, .d4, .d6 };
    for (expected) |reg| {
        const got = cg.allocTempFloat();
        try std.testing.expectEqual(reg, got);
        try std.testing.expect(got.hasSViews());
    }
    try std.testing.expect(cg.allocFloat() == null);
    cg.freeFloat(.d4);
    try std.testing.expectEqual(FloatReg.d4, cg.allocTempFloat());
}

test "vectors take q8-q15 first, then the scalar pool; scalars never get q8-q15" {
    var cg = MuslCodeGen.init(std.testing.allocator, .default);
    defer cg.deinit();
    var index: u6 = 16;
    while (index <= 30) : (index += 2) {
        const got = cg.allocVector().?;
        try std.testing.expectEqual(@as(FloatReg, @enumFromInt(@as(u5, @intCast(index)))), got);
        try std.testing.expect(!got.hasSViews());
    }
    // The vector-only pool is empty: vectors fall back to d0.
    try std.testing.expectEqual(FloatReg.d0, cg.allocVector().?);
    // Scalars still get only registers with S views.
    try std.testing.expectEqual(FloatReg.d2, cg.allocFloat().?);
    cg.freeFloat(.d20);
    try std.testing.expectEqual(FloatReg.d4, cg.allocFloat().?);
    try std.testing.expectEqual(FloatReg.d20, cg.allocVector().?);
}

test "stack accesses in range use fp directly, out of range go through lr" {
    // LR, not r12, forms the address, so r12 stays usable as a base or
    // data register at any offset.
    var cg = MuslCodeGen.init(std.testing.allocator, .default);
    defer cg.deinit();
    var e = MuslEmit.init(std.testing.allocator);
    defer e.deinit();

    try cg.emitLoadStack(.w32, .r0, -4095);
    try e.ldrRegMem(.r0, .r11, -4095);
    try cg.emitLoadStack(.w32, .r1, -4096);
    try e.subRegRegModImm(.lr, .r11, ModImm.of(4096));
    try e.ldrRegMem(.r1, .lr, 0);
    try cg.emitStoreStackW16(-255, .r2);
    try e.strhRegMem(.r2, .r11, -255);
    try cg.emitStoreStackW16(-257, .r2);
    try e.movRegImm32(.lr, @bitCast(@as(i32, -257)));
    try e.addRegRegReg(.lr, .r11, .lr);
    try e.strhRegMem(.r2, .lr, 0);
    try cg.emitStoreStackF64(-1020, .d2);
    try e.vstrF64(.d2, .r11, -1020);
    try cg.emitLoadStackF32(.d4, -1022);
    try e.movRegImm32(.lr, @bitCast(@as(i32, -1022)));
    try e.addRegRegReg(.lr, .r11, .lr);
    try e.vldrF32(.s8, .lr, 0);
    try cg.emitLoadStackV128(.d6, -32);
    try e.subRegRegModImm(.lr, .r11, ModImm.of(32));
    try e.vld1Q(.q3, .lr);
    try cg.emitStore(.w32, .r11, -8192, .r12);
    try e.subRegRegModImm(.lr, .r11, ModImm.of(8192));
    try e.strRegMem(.r12, .lr, 0);
    try expectCode(&cg, &e);
}

test "immediates, comparisons and conditional sets" {
    var cg = MuslCodeGen.init(std.testing.allocator, .default);
    defer cg.deinit();
    var e = MuslEmit.init(std.testing.allocator);
    defer e.deinit();

    try cg.emitLoadImm(.r0, -1);
    try e.mvnRegModImm(.r0, ModImm.of(0));
    try cg.emitLoadImm(.r1, 0xFFFF_FFFF);
    try e.mvnRegModImm(.r1, ModImm.of(0));
    try cg.emitLoadImm(.r2, 0x12345678);
    try e.movw(.r2, 0x5678);
    try e.movt(.r2, 0x1234);
    try cg.emitCmpImm(.r3, -2);
    try e.cmnRegModImm(.r3, ModImm.of(2));
    try cg.emitCmpImm(.r3, 0x12345);
    try e.movRegImm32(.r12, 0x12345);
    try e.cmpRegReg(.r3, .r12);
    try cg.emitCmp(.w32, .r0, .r1, .r2, MuslCodeGen.condBelow());
    try e.cmpRegReg(.r1, .r2);
    try e.movRegModImm(.r0, ModImm.of(0));
    try e.movRegModImmCond(.lo, .r0, ModImm.of(1));
    try cg.emitSaturatingSub(.r4, .r5, .r6);
    try e.subsRegRegReg(.r4, .r5, .r6);
    try e.movRegModImmCond(.lo, .r4, ModImm.of(0));
    try cg.emitCtzWord(.r1, .r2);
    try e.rbitRegReg(.r1, .r2);
    try e.clzRegReg(.r1, .r1);
    try expectCode(&cg, &e);
}

test "branch placeholders are retargeted with their condition and link bit" {
    var cg = MuslCodeGen.init(std.testing.allocator, .default);
    defer cg.deinit();
    const jump = try cg.emitJump();
    const cond = try cg.emitJumpIfNotEqual();
    const call = try cg.emitCallPlaceholder();
    try cg.emit.nop();
    try cg.patchJump(jump, 16);
    try cg.patchJump(cond, 0);
    try cg.patchCall(call, 16);
    try std.testing.expect(cg.isBlAt(call));
    try std.testing.expect(!cg.isBlAt(jump));

    var e = MuslEmit.init(std.testing.allocator);
    defer e.deinit();
    try e.b(16);
    try e.bcond(.ne, -4);
    try e.bl(8);
    try e.nop();
    try expectCode(&cg, &e);
}

test "data addresses carry the movw/movt relocation pair" {
    var cg = MuslCodeGen.init(std.testing.allocator, .default);
    defer cg.deinit();
    try cg.emit.nop();
    try cg.emitLoadDataAddress(.r3, @enumFromInt(7));
    try std.testing.expectEqual(@as(usize, 2), cg.relocations.items.len);
    const lo = cg.relocations.items[0].linked_data;
    const hi = cg.relocations.items[1].linked_data;
    try std.testing.expectEqual(@as(u64, 4), lo.offset);
    try std.testing.expectEqual(@import("../Relocation.zig").DataRelocationKind.arm_movw_prel, lo.kind);
    try std.testing.expectEqual(@as(u64, 8), hi.offset);
    try std.testing.expectEqual(@import("../Relocation.zig").DataRelocationKind.arm_movt_prel, hi.kind);
}

test "internal code addresses are written as PC-relative movw/movt values" {
    var cg = MuslCodeGen.init(std.testing.allocator, .default);
    defer cg.deinit();
    const at: usize = @intCast(try cg.emit.pcRelAddress(.r5));
    cg.patchInternalCodeAddress(at, 0x10000 + 4);
    // target - (at + 16) = 0x10000 + 4 - 16 = 0xFFF4
    var e = MuslEmit.init(std.testing.allocator);
    defer e.deinit();
    try e.movw(.r5, 0xFFF4);
    try e.movt(.r5, 0x0000);
    try e.addRegRegReg(.r5, .r15, .r5);
    try expectCode(&cg, &e);
}

test "an eight-byte discriminant stores the index and a zero high word" {
    var cg = MuslCodeGen.init(std.testing.allocator, .default);
    defer cg.deinit();
    try cg.storeDiscriminant(-16, 3, 8);
    var e = MuslEmit.init(std.testing.allocator);
    defer e.deinit();
    try e.movRegImm32(.r0, 3);
    try e.strRegMem(.r0, .r11, -16);
    try e.movRegImm32(.r0, 0);
    try e.strRegMem(.r0, .r11, -12);
    try expectCode(&cg, &e);
}

test "deferred prologue size matches the bytes emitted, for every frame shape" {
    const Builder = MuslCodeGen.DeferredFrameBuilder;
    const masks = [_]u32{ 0, GeneralReg.r4.listBit(), Call.CALLEE_SAVED_GENERAL_MASK };
    const sizes = [_]u32{ 0, 100, 0x1234, 4072, 70000, 1 << 20 };
    for (masks) |mask| {
        for (sizes) |size| {
            var e = MuslEmit.init(std.testing.allocator);
            defer e.deinit();
            var builder = Builder.init();
            builder.setCalleeSavedMask(mask);
            builder.setStackSize(size);
            const predicted = builder.calculatePrologueSize();
            _ = try builder.emitPrologue(&e);
            try std.testing.expectEqual(@as(usize, predicted), e.buf.items.len);
            try std.testing.expectEqual(@as(u32, 0), builder.actual_stack_alloc % 8);
        }
    }
}

test "deferred prologue and epilogue follow D5" {
    var cg = MuslCodeGen.init(std.testing.allocator, .default);
    defer cg.deinit();
    cg.callee_saved_used = GeneralReg.r4.listBit() | GeneralReg.r9.listBit();
    try cg.emitPrologueWithAlloc(12);
    try cg.emitEpilogue();

    var e = MuslEmit.init(std.testing.allocator);
    defer e.deinit();
    try e.push(GeneralReg.fp.listBit() | GeneralReg.lr.listBit());
    try e.movRegReg(.fp, .sp);
    try e.subRegRegModImm(.sp, .sp, ModImm.of(40)); // 12 + 28, rounded to 8
    try e.strRegMem(.r4, .fp, -4);
    try e.strRegMem(.r9, .fp, -24);
    try e.ldrRegMem(.r4, .fp, -4);
    try e.ldrRegMem(.r9, .fp, -24);
    try e.movRegReg(.sp, .fp);
    try e.pop(GeneralReg.fp.listBit() | GeneralReg.pc.listBit());
    try expectCode(&cg, &e);
}

test "a frame of a page or more probes each page" {
    var e = MuslEmit.init(std.testing.allocator);
    defer e.deinit();
    var builder = MuslCodeGen.DeferredFrameBuilder.init();
    builder.setStackSize(8192);
    _ = try builder.emitPrologue(&e);

    var expected = MuslEmit.init(std.testing.allocator);
    defer expected.deinit();
    const page = ModImm.of(4096);
    try expected.push(GeneralReg.fp.listBit() | GeneralReg.lr.listBit());
    try expected.movRegReg(.fp, .sp);
    try expected.movw(.r12, 8192 + 32);
    try expected.movt(.r12, 0);
    try expected.subRegRegModImm(.sp, .sp, page);
    try expected.strRegMem(.r12, .sp, 0);
    try expected.subRegRegModImm(.r12, .r12, page);
    try expected.cmpRegModImm(.r12, page);
    try expected.bcond(.hi, -16);
    try expected.subRegRegReg(.sp, .sp, .r12);
    try expected.strRegMem(.r12, .sp, 0);
    try std.testing.expectEqualSlices(u8, expected.buf.items, e.buf.items);
}

test "forward frame pushes its registers and keeps sp 8-aligned" {
    var e = MuslEmit.init(std.testing.allocator);
    defer e.deinit();
    var builder = FrameBuilderMod.ForwardFrameBuilder(MuslEmit).init(&e);
    builder.saveViaPush(.r4);
    builder.saveViaPush(.r5);
    builder.saveViaPush(.r6);
    builder.setStackSize(16);
    try std.testing.expectEqual(@as(i32, -12), try builder.emitPrologue());
    try builder.emitEpilogue();

    var expected = MuslEmit.init(std.testing.allocator);
    defer expected.deinit();
    const regs = GeneralReg.r4.listBit() | GeneralReg.r5.listBit() | GeneralReg.r6.listBit();
    try expected.push(GeneralReg.fp.listBit() | GeneralReg.lr.listBit());
    try expected.movRegReg(.fp, .sp);
    try expected.push(regs);
    try expected.subRegRegModImm(.sp, .sp, ModImm.of(20)); // 16 + 4 padding
    try expected.addRegRegModImm(.sp, .sp, ModImm.of(20));
    try expected.pop(regs);
    try expected.pop(GeneralReg.fp.listBit() | GeneralReg.pc.listBit());
    try std.testing.expectEqualSlices(u8, expected.buf.items, e.buf.items);
}
