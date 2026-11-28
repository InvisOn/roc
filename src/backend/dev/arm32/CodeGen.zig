//! arm32 (A32) code generation: the per-instruction-set `CodeGen` that the
//! shared driver calls for register allocation, stack slots, frames, and the
//! instructions it asks for by name, with the same names and signatures as the
//! x86_64 and aarch64 code generators.
//!
//! Register pools: general temporaries are r0-r3 (caller-saved), then r4-r10
//! (callee-saved, recorded for the prologue); r11 is the frame pointer and r12
//! the scratch register, never allocated. Float temporaries are the even D
//! registers d0, d2, d4 and d6: each is also a Q register (q0-q3) and has S
//! views, so an allocated `FloatReg` can hold an f32, an f64 or a 128-bit
//! vector. Vectors also have q8-q15 (the even D registers d16-d30), which have
//! no S view and so are handed out only by `allocVector`.
//!
//! Every memory access honours its form's offset range (`fitsImmediate`); out
//! of range, the address is formed in LR first (`Call.ADDRESS_SCRATCH_REG`),
//! so r12 can be the base or the data register of any access.

const std = @import("std");
const invariant = @import("base").invariant;
const Allocator = std.mem.Allocator;
const Abi = @import("../isa.zig").Abi;

const EmitMod = @import("Emit.zig");
const Registers = @import("Registers.zig");
const Call = @import("Call.zig");
const Relocation = @import("../Relocation.zig").IndexedRelocation;
const SymbolTable = @import("../SymbolTable.zig");
const FrameBuilderMod = @import("../FrameBuilder.zig");
const RegisterPool = @import("../RegisterPool.zig");

const GeneralReg = Registers.GeneralReg;
const FloatReg = Registers.FloatReg;
const RegisterWidth = Registers.RegisterWidth;
const Condition = EmitMod.Condition;
const ModImm = EmitMod.ModImm;
const MemForm = EmitMod.MemForm;
const fitsImmediate = EmitMod.fitsImmediate;

/// Parameterized arm32 code generator. Every arm32 ABI is AAPCS32 with the
/// VFP variant.
pub fn CodeGen(comptime machine_abi: Abi) type {
    if (machine_abi.isa() != .arm32) {
        @compileError("arm32.CodeGen requires an arm32 ABI");
    }

    const Emit = EmitMod.Emit(machine_abi);
    const address_scratch = Call.ADDRESS_SCRATCH_REG;
    const fp = Call.BASE_PTR_REG;

    return struct {
        const Self = @This();

        /// The ABI this CodeGen was instantiated for
        pub const code_abi = machine_abi;

        /// Number of general-purpose registers
        pub const NUM_GENERAL_REGS = 16;
        /// Number of float registers (D view)
        pub const NUM_FLOAT_REGS = 32;

        /// Caller-saved general registers available as temporaries: r0-r3.
        pub const INITIAL_FREE_GENERAL: u32 = Call.CALLER_SAVED_GENERAL_MASK;

        /// Float temporaries with S views: d0, d2, d4, d6 (q0-q3). The odd D
        /// registers are the high halves of those Q registers and are never
        /// allocated alone.
        pub const SCALAR_FLOAT_MASK: u32 = floatBit(.d0) | floatBit(.d2) | floatBit(.d4) | floatBit(.d6);

        /// Vector-only temporaries: d16, d18, ..., d30 (q8-q15). They have no
        /// S view, so an f32 never lives there.
        pub const VECTOR_ONLY_FLOAT_MASK: u32 = 0x5555_0000;

        /// Every float temporary.
        pub const INITIAL_FREE_FLOAT: u32 = SCALAR_FLOAT_MASK | VECTOR_ONLY_FLOAT_MASK;

        /// Callee-saved general registers available after r0-r3: r4-r10.
        pub const CALLEE_SAVED_GENERAL_MASK: u32 = Call.CALLEE_SAVED_GENERAL_MASK;

        /// Size of the callee-saved area below fp; the driver starts local
        /// slots below it.
        pub const CALLEE_SAVED_AREA_SIZE: i32 = DeferredFrameBuilder.CALLEE_SAVED_AREA_SIZE;

        emit: Emit,
        allocator: Allocator,
        stack_offset: i32,
        relocations: std.ArrayList(Relocation),
        symbols: SymbolTable.Table = .{},
        free_general: u32,
        free_float: u32,
        /// Callee-saved general registers used, as an r0-r15 bit mask.
        callee_saved_used: u32,
        /// Remaining callee-saved registers available (used after caller-saved exhausted)
        callee_saved_available: u32,

        pub fn init(allocator: Allocator) Self {
            return .{
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

        // Register allocation. The shared pool hands out general registers;
        // float registers are arm32's own, since only some of them have the S
        // views an f32 needs.

        const Pool = RegisterPool.Methods(Self, GeneralReg, FloatReg, CALLEE_SAVED_GENERAL_MASK);
        pub const getCode = Pool.getCode;
        pub const currentOffset = Pool.currentOffset;
        pub const allocGeneral = Pool.allocGeneral;
        pub const freeGeneral = Pool.freeGeneral;
        pub const markRegisterInUse = Pool.markRegisterInUse;

        /// A float register for an f32 or f64: one with S views.
        pub fn allocFloat(self: *Self) ?FloatReg {
            return self.takeFloat(SCALAR_FLOAT_MASK);
        }

        /// A float register for a 128-bit vector: q8-q15 first, keeping
        /// q0-q3 for scalars.
        pub fn allocVector(self: *Self) ?FloatReg {
            return self.takeFloat(VECTOR_ONLY_FLOAT_MASK) orelse self.takeFloat(SCALAR_FLOAT_MASK);
        }

        fn takeFloat(self: *Self, pool: u32) ?FloatReg {
            const available = self.free_float & pool;
            if (available == 0) return null;
            const bit: u5 = @intCast(@ctz(available));
            self.free_float &= ~(@as(u32, 1) << bit);
            return @fromBackingInt(bit);
        }

        pub fn freeFloat(self: *Self, reg: FloatReg) void {
            std.debug.assert(INITIAL_FREE_FLOAT & floatBit(reg) != 0);
            self.free_float |= floatBit(reg);
        }

        fn floatBit(reg: FloatReg) u32 {
            return @as(u32, 1) << reg.enc();
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

        /// Deferred frame builder type for this architecture (mask-based, body generated first)
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

        // Immediates

        /// Load a constant that fits a word, as a signed or an unsigned 32-bit
        /// value, into `dst`, with the shortest move that produces it.
        pub fn emitLoadImm(self: *Self, dst: GeneralReg, value: i64) Allocator.Error!void {
            try self.emit.movRegImm32(dst, wordBits(value));
        }

        /// The 32-bit pattern of an immediate that fits a word. A 64-bit value
        /// reaches a register pair, never one register.
        fn wordBits(value: i64) u32 {
            if (value < std.math.minInt(i32) or value > std.math.maxInt(u32)) {
                invariant("arm32 invariant violated: immediate {d} does not fit a 32-bit register", .{value});
            }
            return @truncate(@as(u64, @bitCast(value)));
        }

        // Integer operations. Every operand is one word, so `width` is
        // always `.w32`.

        /// Emit integer addition: dst = a + b
        pub fn emitAdd(self: *Self, _: RegisterWidth, dst: GeneralReg, a: GeneralReg, b: GeneralReg) Allocator.Error!void {
            try self.emit.addRegRegReg(dst, a, b);
        }

        /// Emit integer subtraction: dst = a - b
        pub fn emitSub(self: *Self, _: RegisterWidth, dst: GeneralReg, a: GeneralReg, b: GeneralReg) Allocator.Error!void {
            try self.emit.subRegRegReg(dst, a, b);
        }

        /// Emit integer multiplication: dst = a * b (the low word)
        pub fn emitMul(self: *Self, _: RegisterWidth, dst: GeneralReg, a: GeneralReg, b: GeneralReg) Allocator.Error!void {
            try self.emit.mulRegRegReg(dst, a, b);
        }

        /// Emit integer negation: dst = 0 - src
        pub fn emitNeg(self: *Self, _: RegisterWidth, dst: GeneralReg, src: GeneralReg) Allocator.Error!void {
            try self.emit.rsbRegRegModImm(dst, src, ModImm.of(0));
        }

        /// Emit bitwise AND: dst = a & b
        pub fn emitAnd(self: *Self, _: RegisterWidth, dst: GeneralReg, a: GeneralReg, b: GeneralReg) Allocator.Error!void {
            try self.emit.andRegRegReg(dst, a, b);
        }

        /// Emit bitwise OR: dst = a | b
        pub fn emitOr(self: *Self, _: RegisterWidth, dst: GeneralReg, a: GeneralReg, b: GeneralReg) Allocator.Error!void {
            try self.emit.orrRegRegReg(dst, a, b);
        }

        /// Emit bitwise XOR: dst = a ^ b
        pub fn emitXor(self: *Self, _: RegisterWidth, dst: GeneralReg, a: GeneralReg, b: GeneralReg) Allocator.Error!void {
            try self.emit.eorRegRegReg(dst, a, b);
        }

        /// Emit bitwise NOT: dst = ~src
        pub fn emitNot(self: *Self, _: RegisterWidth, dst: GeneralReg, src: GeneralReg) Allocator.Error!void {
            try self.emit.mvnRegReg(dst, src);
        }

        // Comparison operations

        /// Emit comparison and set condition: dst = (a op b) ? 1 : 0
        pub fn emitCmp(self: *Self, _: RegisterWidth, dst: GeneralReg, a: GeneralReg, b: GeneralReg, cond: Condition) Allocator.Error!void {
            try self.emit.cmpRegReg(a, b);
            try self.emitSetCond(dst, cond);
        }

        /// dst = cond ? 1 : 0, from the current flags
        fn emitSetCond(self: *Self, dst: GeneralReg, cond: Condition) Allocator.Error!void {
            try self.emit.movRegModImm(dst, ModImm.of(0));
            try self.emit.movRegModImmCond(cond, dst, ModImm.of(1));
        }

        // Control flow. A32 branches reach ±32 MiB; `encodeBranch` asserts
        // that the distance fits.

        /// Emit unconditional jump (returns patch location for fixup)
        pub fn emitJump(self: *Self) Allocator.Error!usize {
            const at = self.currentOffset();
            try self.emit.b(0);
            return at;
        }

        /// Emit conditional jump (returns patch location for fixup)
        pub fn emitCondJump(self: *Self, cond: Condition) Allocator.Error!usize {
            const at = self.currentOffset();
            try self.emit.bcond(cond, 0);
            return at;
        }

        /// Point the branch at `patch_loc` to `target_loc`, keeping its
        /// condition.
        pub fn patchJump(self: *Self, patch_loc: usize, target_loc: usize) Allocator.Error!void {
            const inst = std.mem.readInt(u32, self.emit.buf.items[patch_loc..][0..4], .little);
            std.debug.assert((inst >> 24) & 0xF == 0b1010); // B<cond>, not BL
            const cond: Condition = @fromBackingInt(@as(u4, @truncate(inst >> 28)));
            const offset: i32 = @intCast(@as(i64, @intCast(target_loc)) - @as(i64, @intCast(patch_loc)));
            std.mem.writeInt(u32, self.emit.buf.items[patch_loc..][0..4], Emit.encodeBranch(cond, false, offset), .little);
        }

        // Memory access

        /// dst = base + offset, for any offset. When the offset is not a
        /// modified immediate, `dst` holds it first, so `dst` must differ from
        /// `base` then.
        fn emitAddrOf(self: *Self, dst: GeneralReg, base: GeneralReg, offset: i32) Allocator.Error!void {
            if (ModImm.encode(@abs(offset))) |imm| {
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
        /// the same pair when the offset is in range, otherwise LR holding the
        /// address and offset 0.
        fn reachable(self: *Self, form: MemForm, base: GeneralReg, offset: i32) Allocator.Error!struct { base: GeneralReg, offset: i32 } {
            if (fitsImmediate(form, offset)) return .{ .base = base, .offset = offset };
            std.debug.assert(base != address_scratch);
            try self.emitAddrOf(address_scratch, base, offset);
            return .{ .base = address_scratch, .offset = 0 };
        }

        /// Load a word from `base + offset`.
        pub fn emitLoadMem(self: *Self, dst: GeneralReg, base: GeneralReg, offset: i32) Allocator.Error!void {
            const at = try self.reachable(.word, base, offset);
            try self.emit.ldrRegMem(dst, at.base, at.offset);
        }

        /// Store a word to `base + offset`.
        pub fn emitStoreMem(self: *Self, base: GeneralReg, offset: i32, src: GeneralReg) Allocator.Error!void {
            const at = try self.reachable(.word, base, offset);
            try self.emit.strRegMem(src, at.base, at.offset);
        }

        /// Load a byte from `base + offset`, zero-extended.
        pub fn emitLoadMemByte(self: *Self, dst: GeneralReg, base: GeneralReg, offset: i32) Allocator.Error!void {
            const at = try self.reachable(.byte, base, offset);
            try self.emit.ldrbRegMem(dst, at.base, at.offset);
        }

        /// Store the low byte of `src` to `base + offset`.
        pub fn emitStoreMemByte(self: *Self, base: GeneralReg, offset: i32, src: GeneralReg) Allocator.Error!void {
            const at = try self.reachable(.byte, base, offset);
            try self.emit.strbRegMem(src, at.base, at.offset);
        }

        /// Load a halfword from `base + offset`, zero-extended.
        pub fn emitLoadMemHalfword(self: *Self, dst: GeneralReg, base: GeneralReg, offset: i32) Allocator.Error!void {
            const at = try self.reachable(.halfword, base, offset);
            try self.emit.ldrhRegMem(dst, at.base, at.offset);
        }

        /// Store the low halfword of `src` to `base + offset`.
        pub fn emitStoreMemHalfword(self: *Self, base: GeneralReg, offset: i32, src: GeneralReg) Allocator.Error!void {
            const at = try self.reachable(.halfword, base, offset);
            try self.emit.strhRegMem(src, at.base, at.offset);
        }

        // Stack slots, at negative offsets from fp

        /// Load register from stack slot
        pub fn emitLoadStack(self: *Self, _: RegisterWidth, dst: GeneralReg, offset: i32) Allocator.Error!void {
            try self.emitLoadMem(dst, fp, offset);
        }

        /// Store register to stack slot
        pub fn emitStoreStack(self: *Self, _: RegisterWidth, offset: i32, src: GeneralReg) Allocator.Error!void {
            try self.emitStoreMem(fp, offset, src);
        }

        pub fn emitLoadStackByte(self: *Self, dst: GeneralReg, offset: i32) Allocator.Error!void {
            try self.emitLoadMemByte(dst, fp, offset);
        }

        pub fn emitStoreStackByte(self: *Self, offset: i32, src: GeneralReg) Allocator.Error!void {
            try self.emitStoreMemByte(fp, offset, src);
        }

        pub fn emitLoadStackHalfword(self: *Self, dst: GeneralReg, offset: i32) Allocator.Error!void {
            try self.emitLoadMemHalfword(dst, fp, offset);
        }

        pub fn emitStoreStackHalfword(self: *Self, offset: i32, src: GeneralReg) Allocator.Error!void {
            try self.emitStoreMemHalfword(fp, offset, src);
        }
    };
}

const TestCodeGen = CodeGen(.arm32_aapcs_vfp);
const TestEmit = EmitMod.Emit(.arm32_aapcs_vfp);

/// Expect `cg`'s code to be exactly the instructions `build` emits.
fn expectCode(cg: *TestCodeGen, build: fn (*TestEmit) Allocator.Error!void) (Allocator.Error || error{TestExpectedEqual})!void {
    var want = TestEmit.init(std.testing.allocator);
    defer want.deinit();
    try build(&want);
    try std.testing.expectEqualSlices(u8, want.buf.items, cg.getCode());
}

test "general registers come from r0-r3, then r4-r10, which the prologue saves" {
    var cg = TestCodeGen.init(std.testing.allocator);
    defer cg.deinit();
    for ([_]GeneralReg{ .r0, .r1, .r2, .r3, .r4, .r5, .r6, .r7, .r8, .r9, .r10 }) |want| {
        try std.testing.expectEqual(@as(?GeneralReg, want), cg.allocGeneral());
    }
    try std.testing.expectEqual(@as(?GeneralReg, null), cg.allocGeneral());
    try std.testing.expectEqual(TestCodeGen.CALLEE_SAVED_GENERAL_MASK, cg.callee_saved_used);
    cg.freeGeneral(.r5);
    cg.freeGeneral(.r2);
    try std.testing.expectEqual(@as(?GeneralReg, .r2), cg.allocGeneral());
    try std.testing.expectEqual(@as(?GeneralReg, .r5), cg.allocGeneral());
}

test "scalar floats get registers with S views, vectors prefer q8-q15" {
    var cg = TestCodeGen.init(std.testing.allocator);
    defer cg.deinit();
    try std.testing.expectEqual(@as(?FloatReg, .d16), cg.allocVector());
    for ([_]FloatReg{ .d0, .d2, .d4, .d6 }) |want| {
        try std.testing.expectEqual(@as(?FloatReg, want), cg.allocFloat());
    }
    // With d16-d30 still free, an f32 still finds no register.
    try std.testing.expectEqual(@as(?FloatReg, null), cg.allocFloat());
    cg.freeFloat(.d4);
    try std.testing.expectEqual(@as(?FloatReg, .d4), cg.allocFloat());
}

test "stack slots are 8-aligned, or 16-aligned above 8 bytes, below fp" {
    var cg = TestCodeGen.init(std.testing.allocator);
    defer cg.deinit();
    try std.testing.expectEqual(@as(i32, -8), cg.allocStack(4));
    try std.testing.expectEqual(@as(i32, -32), cg.allocStack(12));
    try std.testing.expectEqual(@as(i32, -40), cg.allocStackSlot(8));
    try std.testing.expectEqual(@as(u32, 40), cg.getStackSize());
}

test "emitLoadImm picks the shortest move for a word, signed or unsigned" {
    var cg = TestCodeGen.init(std.testing.allocator);
    defer cg.deinit();
    try cg.emitLoadImm(.r0, 0xFF00);
    try cg.emitLoadImm(.r1, -1);
    try cg.emitLoadImm(.r2, 0x1234_5678);
    try cg.emitLoadImm(.r3, std.math.maxInt(u32));
    try expectCode(&cg, struct {
        fn build(e: *TestEmit) Allocator.Error!void {
            try e.movRegImm32(.r0, 0xFF00);
            try e.movRegImm32(.r1, 0xFFFF_FFFF);
            try e.movRegImm32(.r2, 0x1234_5678);
            try e.movRegImm32(.r3, 0xFFFF_FFFF);
        }
    }.build);
}

test "word and byte stack accesses reach ±4095 directly, then through lr" {
    var cg = TestCodeGen.init(std.testing.allocator);
    defer cg.deinit();
    try cg.emitLoadStack(.w32, .r0, -4095);
    try cg.emitStoreStack(.w32, -4096, .r1);
    try cg.emitStoreStackByte(-4095, .r2);
    try cg.emitLoadStackByte(.r3, -4100);
    try expectCode(&cg, struct {
        fn build(e: *TestEmit) Allocator.Error!void {
            try e.ldrRegMem(.r0, .fp, -4095);
            // 4096 is a modified immediate: one sub forms the address.
            try e.subRegRegModImm(.lr, .fp, ModImm.of(4096));
            try e.strRegMem(.r1, .lr, 0);
            try e.strbRegMem(.r2, .fp, -4095);
            // 4100 is not: the offset goes to lr first.
            try e.movRegImm32(.lr, @bitCast(@as(i32, -4100)));
            try e.addRegRegReg(.lr, .fp, .lr);
            try e.ldrbRegMem(.r3, .lr, 0);
        }
    }.build);
}

test "halfword stack accesses reach ±255 directly, then through lr" {
    var cg = TestCodeGen.init(std.testing.allocator);
    defer cg.deinit();
    try cg.emitLoadStackHalfword(.r0, -255);
    try cg.emitStoreStackHalfword(-256, .r12);
    try expectCode(&cg, struct {
        fn build(e: *TestEmit) Allocator.Error!void {
            try e.ldrhRegMem(.r0, .fp, -255);
            try e.subRegRegModImm(.lr, .fp, ModImm.of(256));
            // r12 can be the data register of an out-of-range access.
            try e.strhRegMem(.r12, .lr, 0);
        }
    }.build);
}

test "the prologue saves the callee-saved registers the body used" {
    var cg = TestCodeGen.init(std.testing.allocator);
    defer cg.deinit();
    for (0..5) |_| _ = cg.allocGeneral(); // r0-r3, then r4
    try cg.emitPrologueWithAlloc(16);
    try cg.emitEpilogue();
    try expectCode(&cg, struct {
        fn build(e: *TestEmit) Allocator.Error!void {
            try e.push(GeneralReg.fp.listBit() | GeneralReg.lr.listBit());
            try e.movRegReg(.fp, .sp);
            try e.subRegRegModImm(.sp, .sp, ModImm.of(48));
            try e.strRegMem(.r4, .fp, -4);
            try e.ldrRegMem(.r4, .fp, -4);
            try e.movRegReg(.sp, .fp);
            try e.pop(GeneralReg.fp.listBit() | GeneralReg.pc.listBit());
        }
    }.build);
}

test "integer operations are one A32 instruction each" {
    var cg = TestCodeGen.init(std.testing.allocator);
    defer cg.deinit();
    try cg.emitAdd(.w32, .r0, .r1, .r2);
    try cg.emitSub(.w32, .r0, .r1, .r2);
    try cg.emitMul(.w32, .r0, .r1, .r2);
    try cg.emitNeg(.w32, .r3, .r4);
    try cg.emitAnd(.w32, .r0, .r1, .r2);
    try cg.emitOr(.w32, .r0, .r1, .r2);
    try cg.emitXor(.w32, .r0, .r1, .r2);
    try cg.emitNot(.w32, .r5, .r6);
    try expectCode(&cg, struct {
        fn build(e: *TestEmit) Allocator.Error!void {
            try e.addRegRegReg(.r0, .r1, .r2);
            try e.subRegRegReg(.r0, .r1, .r2);
            try e.mulRegRegReg(.r0, .r1, .r2);
            try e.rsbRegRegModImm(.r3, .r4, ModImm.of(0));
            try e.andRegRegReg(.r0, .r1, .r2);
            try e.orrRegRegReg(.r0, .r1, .r2);
            try e.eorRegRegReg(.r0, .r1, .r2);
            try e.mvnRegReg(.r5, .r6);
        }
    }.build);
}

test "emitCmp sets 0, then 1 under the condition" {
    var cg = TestCodeGen.init(std.testing.allocator);
    defer cg.deinit();
    try cg.emitCmp(.w32, .r0, .r1, .r2, .lt);
    try expectCode(&cg, struct {
        fn build(e: *TestEmit) Allocator.Error!void {
            try e.cmpRegReg(.r1, .r2);
            try e.movRegModImm(.r0, ModImm.of(0));
            try e.movRegModImmCond(.lt, .r0, ModImm.of(1));
        }
    }.build);
}

test "patchJump points a branch forward or backward and keeps its condition" {
    var cg = TestCodeGen.init(std.testing.allocator);
    defer cg.deinit();
    const loop = cg.currentOffset();
    try cg.emitAdd(.w32, .r0, .r0, .r1);
    const exit = try cg.emitCondJump(.hs);
    const back = try cg.emitJump();
    try cg.patchJump(back, loop);
    try cg.patchJump(exit, cg.currentOffset());
    try std.testing.expectEqual(@as(usize, 4), exit);
    try expectCode(&cg, struct {
        fn build(e: *TestEmit) Allocator.Error!void {
            try e.addRegRegReg(.r0, .r0, .r1);
            try e.bcond(.hs, 8); // past the backward branch
            try e.b(-8); // back to the add
        }
    }.build);
}
