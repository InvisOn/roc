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

        /// Emit the function prologue, with `stack_size` bytes of locals
        pub fn emitPrologueWithAlloc(self: *Self, stack_size: u32) Allocator.Error!void {
            try self.emitPrologueWithAllocAndStackProbe(stack_size, false);
        }

        /// Emit the function prologue, probing each page of the frame when LIR requires it
        pub fn emitPrologueWithAllocAndStackProbe(self: *Self, stack_size: u32, stack_probe_required: bool) Allocator.Error!void {
            var builder = DeferredFrameBuilder.init();
            builder.setCalleeSavedMask(self.callee_saved_used);
            builder.setStackSize(stack_size);
            builder.setStackProbeRequired(stack_probe_required);
            _ = try builder.emitPrologue(&self.emit);
        }

        /// Emit function epilogue and return
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

        /// Emit float64 compare and set: dst = (a cond b) ? 1 : 0
        pub fn emitCmpF64(self: *Self, dst: GeneralReg, a: FloatReg, b: FloatReg, cond: Condition) Allocator.Error!void {
            try self.emit.vcmpF64(a, b);
            try self.emit.vmrsApsrNzcv();
            try self.emitSetCond(dst, cond);
        }

        /// Emit float32 compare and set: dst = (a cond b) ? 1 : 0
        pub fn emitCmpF32(self: *Self, dst: GeneralReg, a: FloatReg, b: FloatReg, cond: Condition) Allocator.Error!void {
            try self.emit.vcmpF32(a.sLow(), b.sLow());
            try self.emit.vmrsApsrNzcv();
            try self.emitSetCond(dst, cond);
        }

        // Floating-point operations. An f32 lives in the low S half of its
        // D register.

        /// Emit float64 addition: dst = a + b
        pub fn emitAddF64(self: *Self, dst: FloatReg, a: FloatReg, b: FloatReg) Allocator.Error!void {
            try self.emit.vaddF64(dst, a, b);
        }

        /// Emit float64 subtraction: dst = a - b
        pub fn emitSubF64(self: *Self, dst: FloatReg, a: FloatReg, b: FloatReg) Allocator.Error!void {
            try self.emit.vsubF64(dst, a, b);
        }

        /// Emit float64 multiplication: dst = a * b
        pub fn emitMulF64(self: *Self, dst: FloatReg, a: FloatReg, b: FloatReg) Allocator.Error!void {
            try self.emit.vmulF64(dst, a, b);
        }

        /// Emit float64 division: dst = a / b
        pub fn emitDivF64(self: *Self, dst: FloatReg, a: FloatReg, b: FloatReg) Allocator.Error!void {
            try self.emit.vdivF64(dst, a, b);
        }

        /// Emit float64 negation: dst = -src, which flips the sign of -0.0 and NaN too
        pub fn emitNegF64(self: *Self, dst: FloatReg, src: FloatReg) Allocator.Error!void {
            try self.emit.vnegF64(dst, src);
        }

        /// Emit float64 absolute value: dst = |src|
        pub fn emitAbsF64(self: *Self, dst: FloatReg, src: FloatReg) Allocator.Error!void {
            try self.emit.vabsF64(dst, src);
        }

        /// Emit float32 addition: dst = a + b
        pub fn emitAddF32(self: *Self, dst: FloatReg, a: FloatReg, b: FloatReg) Allocator.Error!void {
            try self.emit.vaddF32(dst.sLow(), a.sLow(), b.sLow());
        }

        /// Emit float32 subtraction: dst = a - b
        pub fn emitSubF32(self: *Self, dst: FloatReg, a: FloatReg, b: FloatReg) Allocator.Error!void {
            try self.emit.vsubF32(dst.sLow(), a.sLow(), b.sLow());
        }

        /// Emit float32 multiplication: dst = a * b
        pub fn emitMulF32(self: *Self, dst: FloatReg, a: FloatReg, b: FloatReg) Allocator.Error!void {
            try self.emit.vmulF32(dst.sLow(), a.sLow(), b.sLow());
        }

        /// Emit float32 division: dst = a / b
        pub fn emitDivF32(self: *Self, dst: FloatReg, a: FloatReg, b: FloatReg) Allocator.Error!void {
            try self.emit.vdivF32(dst.sLow(), a.sLow(), b.sLow());
        }

        /// Emit float32 negation: dst = -src, which flips the sign of -0.0 and NaN too
        pub fn emitNegF32(self: *Self, dst: FloatReg, src: FloatReg) Allocator.Error!void {
            try self.emit.vnegF32(dst.sLow(), src.sLow());
        }

        /// Emit float32 absolute value: dst = |src|
        pub fn emitAbsF32(self: *Self, dst: FloatReg, src: FloatReg) Allocator.Error!void {
            try self.emit.vabsF32(dst.sLow(), src.sLow());
        }

        // Control flow. A32 branches and calls reach ±32 MiB from PC+8. The
        // check that tells the user when arm32 code needs more comes with
        // the arm32 driver path, before any code is patched; behind it,
        // `branchOffset` treats an out-of-reach distance as a compiler bug.

        /// The byte offset from the branch at `loc` to `target_loc`.
        fn branchOffset(loc: usize, target_loc: usize) i32 {
            const offset = @as(i64, @intCast(target_loc)) - @as(i64, @intCast(loc));
            // The same word displacement `Emit.encodeBranch` encodes.
            const disp = (offset - 8) >> 2;
            if (disp < -(1 << 23) or disp >= (1 << 23)) {
                invariant("arm32 invariant violated: branch at 0x{x} to 0x{x} is out of A32 reach", .{ loc, target_loc });
            }
            return @intCast(offset);
        }

        fn readInst(self: *Self, at: usize) u32 {
            return std.mem.readInt(u32, self.emit.buf.items[at..][0..4], .little);
        }

        fn writeInst(self: *Self, at: usize, inst: u32) void {
            std.mem.writeInt(u32, self.emit.buf.items[at..][0..4], inst, .little);
        }

        /// Whether the instruction at `loc` is a BL.
        fn isBlAt(self: *Self, loc: usize) bool {
            return (self.readInst(loc) >> 24) == 0xEB;
        }

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
            const inst = self.readInst(patch_loc);
            std.debug.assert((inst >> 24) & 0xF == 0b1010); // B<cond>, not BL
            const cond: Condition = @fromBackingInt(@as(u4, @truncate(inst >> 28)));
            self.writeInst(patch_loc, Emit.encodeBranch(cond, false, branchOffset(patch_loc, target_loc)));
        }

        // Calls

        /// How `emitDirectCall` reached its target, with the same members as
        /// aarch64's; arm32 always emits a direct BL.
        pub const CallKind = enum { call, inline_call };

        /// Emit a call placeholder to a procedure not placed yet; returns its
        /// location for `patchCall`.
        pub fn emitCallPlaceholder(self: *Self) Allocator.Error!usize {
            const loc = self.currentOffset();
            try self.emit.bl(0);
            return loc;
        }

        /// Patch a call emitted by `emitCallPlaceholder`.
        pub fn patchCall(self: *Self, patch_loc: usize, target_loc: usize) Allocator.Error!void {
            std.debug.assert(self.isBlAt(patch_loc));
            self.writeInst(patch_loc, Emit.encodeBranch(.al, true, branchOffset(patch_loc, target_loc)));
        }

        /// Call a procedure whose code offset is already known: always a
        /// direct BL, since arm32 code is kept within A32's branch reach.
        pub fn emitDirectCall(self: *Self, target_loc: usize) Allocator.Error!CallKind {
            const loc = self.currentOffset();
            try self.emit.bl(branchOffset(loc, target_loc));
            return .call;
        }

        /// Re-encode a call emitted by `emitDirectCall` after its site or its
        /// target moved because a prologue was prepended in front of a body.
        pub fn patchDirectCall(self: *Self, loc: usize, target_loc: usize) void {
            std.debug.assert(self.isBlAt(loc));
            self.writeInst(loc, Emit.encodeBranch(.al, true, branchOffset(loc, target_loc)));
        }

        /// Emit a BL to a linked symbol, recorded as an `arm32_call`
        /// relocation. The instruction holds the relocation's addend.
        pub fn emitExternCall(self: *Self, symbol: SymbolTable.Id) Allocator.Error!void {
            const loc = self.currentOffset();
            try self.emit.bl(0);
            try self.relocations.append(self.allocator, .{ .linked_function = .{ .offset = @intCast(loc), .symbol = symbol, .kind = .arm32_call } });
        }

        /// Emit a call to a linked symbol.
        pub fn emitCall(self: *Self, symbol: SymbolTable.Id) Allocator.Error!void {
            try self.emitExternCall(symbol);
        }

        /// dst = the address of `symbol`, by a PC-relative movw/movt/add
        /// sequence whose two halves are relocated.
        pub fn emitLoadDataAddress(self: *Self, dst: GeneralReg, symbol: SymbolTable.Id) Allocator.Error!void {
            const at = try self.emit.pcRelAddress(dst);
            try self.relocations.append(self.allocator, .{ .linked_data = .{ .offset = at, .symbol = symbol, .kind = .arm32_movw_prel } });
            try self.relocations.append(self.allocator, .{ .linked_data = .{ .offset = at + 4, .symbol = symbol, .kind = .arm32_movt_prel } });
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

        // Float and vector memory. VFP loads and stores reach ±1020 in words;
        // NEON's whole-register load and store take no offset, so their
        // address is formed first unless it is the base itself.

        /// Load float64 from stack slot
        pub fn emitLoadStackF64(self: *Self, dst: FloatReg, offset: i32) Allocator.Error!void {
            const at = try self.reachable(.vfp, fp, offset);
            try self.emit.vldrF64(dst, at.base, at.offset);
        }

        /// Store float64 to stack slot
        pub fn emitStoreStackF64(self: *Self, offset: i32, src: FloatReg) Allocator.Error!void {
            const at = try self.reachable(.vfp, fp, offset);
            try self.emit.vstrF64(src, at.base, at.offset);
        }

        /// Load float32 from stack slot.
        pub fn emitLoadStackF32(self: *Self, dst: FloatReg, offset: i32) Allocator.Error!void {
            const at = try self.reachable(.vfp, fp, offset);
            try self.emit.vldrF32(dst.sLow(), at.base, at.offset);
        }

        /// Store float32 to stack slot.
        pub fn emitStoreStackF32(self: *Self, offset: i32, src: FloatReg) Allocator.Error!void {
            const at = try self.reachable(.vfp, fp, offset);
            try self.emit.vstrF32(src.sLow(), at.base, at.offset);
        }

        /// Load a 128-bit vector from `base + offset`
        pub fn emitLoadV128(self: *Self, dst: FloatReg, base: GeneralReg, offset: i32) Allocator.Error!void {
            const at = try self.reachable(.neon, base, offset);
            try self.emit.vld1Q(dst.containingQ(), at.base);
        }

        /// Store a 128-bit vector to `base + offset`
        pub fn emitStoreV128(self: *Self, base: GeneralReg, offset: i32, src: FloatReg) Allocator.Error!void {
            const at = try self.reachable(.neon, base, offset);
            try self.emit.vst1Q(src.containingQ(), at.base);
        }

        /// Load a 128-bit vector from stack slot
        pub fn emitLoadStackV128(self: *Self, dst: FloatReg, offset: i32) Allocator.Error!void {
            try self.emitLoadV128(dst, fp, offset);
        }

        /// Store a 128-bit vector to stack slot
        pub fn emitStoreStackV128(self: *Self, offset: i32, src: FloatReg) Allocator.Error!void {
            try self.emitStoreV128(fp, offset, src);
        }

        /// Copy a 128-bit vector register
        pub fn emitMoveV128(self: *Self, dst: FloatReg, src: FloatReg) Allocator.Error!void {
            if (dst != src) try self.emit.vmovQ(dst.containingQ(), src.containingQ());
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

        /// Load byte (zero-extended) from stack slot
        pub fn emitLoadStackByte(self: *Self, dst: GeneralReg, offset: i32) Allocator.Error!void {
            try self.emitLoadMemByte(dst, fp, offset);
        }

        /// Store byte to stack slot
        pub fn emitStoreStackByte(self: *Self, offset: i32, src: GeneralReg) Allocator.Error!void {
            try self.emitStoreMemByte(fp, offset, src);
        }

        /// Load halfword (zero-extended) from stack slot
        pub fn emitLoadStackHalfword(self: *Self, dst: GeneralReg, offset: i32) Allocator.Error!void {
            try self.emitLoadMemHalfword(dst, fp, offset);
        }

        /// Store halfword (2 bytes) to stack slot
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

test "f64 operations use D registers, f32 operations their low S halves" {
    var cg = TestCodeGen.init(std.testing.allocator);
    defer cg.deinit();
    try cg.emitAddF64(.d0, .d2, .d4);
    try cg.emitSubF64(.d0, .d2, .d4);
    try cg.emitMulF64(.d0, .d2, .d4);
    try cg.emitDivF64(.d0, .d2, .d4);
    try cg.emitNegF64(.d6, .d0);
    try cg.emitAbsF64(.d6, .d0);
    try cg.emitAddF32(.d0, .d2, .d4);
    try cg.emitSubF32(.d0, .d2, .d4);
    try cg.emitMulF32(.d0, .d2, .d4);
    try cg.emitDivF32(.d0, .d2, .d4);
    try cg.emitNegF32(.d6, .d0);
    try cg.emitAbsF32(.d6, .d0);
    try expectCode(&cg, struct {
        fn build(e: *TestEmit) Allocator.Error!void {
            try e.vaddF64(.d0, .d2, .d4);
            try e.vsubF64(.d0, .d2, .d4);
            try e.vmulF64(.d0, .d2, .d4);
            try e.vdivF64(.d0, .d2, .d4);
            try e.vnegF64(.d6, .d0);
            try e.vabsF64(.d6, .d0);
            try e.vaddF32(.s0, .s4, .s8);
            try e.vsubF32(.s0, .s4, .s8);
            try e.vmulF32(.s0, .s4, .s8);
            try e.vdivF32(.s0, .s4, .s8);
            try e.vnegF32(.s12, .s0);
            try e.vabsF32(.s12, .s0);
        }
    }.build);
}

test "float compares copy the VFP flags to the core before setting the result" {
    var cg = TestCodeGen.init(std.testing.allocator);
    defer cg.deinit();
    try cg.emitCmpF64(.r0, .d0, .d2, .mi);
    try cg.emitCmpF32(.r1, .d4, .d6, .ge);
    try expectCode(&cg, struct {
        fn build(e: *TestEmit) Allocator.Error!void {
            try e.vcmpF64(.d0, .d2);
            try e.vmrsApsrNzcv();
            try e.movRegModImm(.r0, ModImm.of(0));
            try e.movRegModImmCond(.mi, .r0, ModImm.of(1));
            try e.vcmpF32(.s8, .s12);
            try e.vmrsApsrNzcv();
            try e.movRegModImm(.r1, ModImm.of(0));
            try e.movRegModImmCond(.ge, .r1, ModImm.of(1));
        }
    }.build);
}

test "float stack accesses reach ±1020 in words directly, then through lr" {
    var cg = TestCodeGen.init(std.testing.allocator);
    defer cg.deinit();
    try cg.emitLoadStackF64(.d0, -1020);
    try cg.emitStoreStackF64(-1024, .d2);
    try cg.emitStoreStackF32(-8, .d4);
    try cg.emitLoadStackF32(.d6, -1028);
    try expectCode(&cg, struct {
        fn build(e: *TestEmit) Allocator.Error!void {
            try e.vldrF64(.d0, .fp, -1020);
            try e.subRegRegModImm(.lr, .fp, ModImm.of(1024));
            try e.vstrF64(.d2, .lr, 0);
            try e.vstrF32(.s8, .fp, -8);
            // 1028 is not a modified immediate: the offset goes to lr first.
            try e.movRegImm32(.lr, @bitCast(@as(i32, -1028)));
            try e.addRegRegReg(.lr, .fp, .lr);
            try e.vldrF32(.s12, .lr, 0);
        }
    }.build);
}

test "vector accesses form any non-zero offset in lr, and a move to itself is nothing" {
    var cg = TestCodeGen.init(std.testing.allocator);
    defer cg.deinit();
    try cg.emitLoadV128(.d16, .r0, 0);
    try cg.emitStoreStackV128(-32, .d16);
    try cg.emitLoadStackV128(.d0, -48);
    try cg.emitMoveV128(.d2, .d16);
    try cg.emitMoveV128(.d2, .d2);
    try expectCode(&cg, struct {
        fn build(e: *TestEmit) Allocator.Error!void {
            try e.vld1Q(.q8, .r0);
            try e.subRegRegModImm(.lr, .fp, ModImm.of(32));
            try e.vst1Q(.q8, .lr);
            try e.subRegRegModImm(.lr, .fp, ModImm.of(48));
            try e.vld1Q(.q0, .lr);
            try e.vmovQ(.q1, .q8);
        }
    }.build);
}

test "calls to placed and unplaced procedures are BLs that patch in place" {
    var cg = TestCodeGen.init(std.testing.allocator);
    defer cg.deinit();
    try cg.emitAdd(.w32, .r0, .r0, .r1); // the callee, at 0
    const pending = try cg.emitCallPlaceholder();
    try std.testing.expectEqual(TestCodeGen.CallKind.call, try cg.emitDirectCall(0));
    try cg.patchCall(pending, 0);
    try expectCode(&cg, struct {
        fn build(e: *TestEmit) Allocator.Error!void {
            try e.addRegRegReg(.r0, .r0, .r1);
            try e.bl(-4);
            try e.bl(-8);
        }
    }.build);
    // A prologue prepended in front of the callee moves it to 16.
    cg.patchDirectCall(8, 16);
    try std.testing.expectEqual(TestEmit.encodeBranch(.al, true, 8), std.mem.readInt(u32, cg.getCode()[8..12], .little));
}

test "a call to a linked symbol and a data address carry their relocations" {
    var cg = TestCodeGen.init(std.testing.allocator);
    defer cg.deinit();
    const puts = try cg.symbols.internEmitted(std.testing.allocator, "puts");
    const table = try cg.symbols.internEmitted(std.testing.allocator, "table");
    try cg.emitCall(puts);
    try cg.emitLoadDataAddress(.r2, table);
    try expectCode(&cg, struct {
        fn build(e: *TestEmit) Allocator.Error!void {
            try e.bl(0); // holds the arm32_call addend, -8
            _ = try e.pcRelAddress(.r2);
        }
    }.build);
    try std.testing.expectEqualDeep(&[_]Relocation{
        .{ .linked_function = .{ .offset = 0, .symbol = puts, .kind = .arm32_call } },
        .{ .linked_data = .{ .offset = 4, .symbol = table, .kind = .arm32_movw_prel } },
        .{ .linked_data = .{ .offset = 8, .symbol = table, .kind = .arm32_movt_prel } },
    }, cg.relocations.items);
}

test "a branch reaches exactly as far as A32 encodes, measured from PC+8" {
    var cg = TestCodeGen.init(std.testing.allocator);
    defer cg.deinit();
    // The farthest targets: 2^23 - 1 words forward and 2^23 words back from PC+8.
    // Only the branches need to be in the buffer, not their targets.
    try cg.emit.buf.appendNTimes(std.testing.allocator, 0, 1 << 25);
    const back_loc: usize = (1 << 25) - 8;
    const forward_loc: usize = 4;
    std.mem.writeInt(u32, cg.emit.buf.items[back_loc..][0..4], TestEmit.encodeBranch(.al, false, 0), .little);
    std.mem.writeInt(u32, cg.emit.buf.items[forward_loc..][0..4], TestEmit.encodeBranch(.al, false, 0), .little);
    try cg.patchJump(back_loc, 0);
    try cg.patchJump(forward_loc, forward_loc + 8 + ((1 << 25) - 4));
    try std.testing.expectEqual(TestEmit.encodeBranch(.al, false, -((1 << 25) - 8)), std.mem.readInt(u32, cg.emit.buf.items[back_loc..][0..4], .little));
    try std.testing.expectEqual(TestEmit.encodeBranch(.al, false, (1 << 25) + 4), std.mem.readInt(u32, cg.emit.buf.items[forward_loc..][0..4], .little));
}
