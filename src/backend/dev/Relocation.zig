//! Relocation types for the dev backend.
//!
//! Relocations represent places in the generated code that need to be
//! patched during linking to refer to the correct addresses.

const std = @import("std");
const Isa = @import("isa.zig").Isa;

/// Machine encoding used for a data-address relocation in generated code.
pub const DataRelocationKind = enum {
    abs64,
    rel32,
    page21,
    pageoff12,
    /// A 32-bit absolute address (arm32 pointer-sized data).
    abs32,
    /// The low half of an arm32 `movw`/`movt`/`add rX, pc, rX` address
    /// sequence: `movw` at the relocation offset, whose value is
    /// S - (P + 16) because the `add` reads PC as its own address + 8.
    arm_movw_prel,
    /// The high half of that sequence: `movt` at the relocation offset, four
    /// bytes after the `movw`, so its value is (S - (P + 12)) >> 16.
    arm_movt_prel,

    /// The addend a PC-relative arm32 `movw`/`movt` relocation carries, from
    /// the position of its instruction within the address sequence.
    pub fn armMovAddend(self: DataRelocationKind) i32 {
        return switch (self) {
            .arm_movw_prel => -16,
            .arm_movt_prel => -12,
            .abs64, .rel32, .page21, .pageoff12, .abs32 => unreachable,
        };
    }
};

/// A named relocation at a linker or process boundary. Machine-code producers
/// use IndexedRelocation and carry its symbol-name column alongside the code.
pub const Relocation = union(enum) {
    /// Inline data that should be placed in the data section.
    /// The offset is where in the code the reference to this data appears.
    local_data: struct {
        /// Offset in the code where the data reference appears
        offset: u64,
        /// The actual data bytes to be placed in the data section
        data: []const u8,
    },

    /// Reference to a function that will be linked.
    /// Used for calls to external functions or other Roc procedures.
    linked_function: struct {
        /// Offset in the code where the function address should be patched
        offset: u64,
        /// Name of the function to link to
        name: []const u8,
    },

    /// Reference to data that will be linked.
    /// Used for references to global data or string literals.
    linked_data: struct {
        /// Offset in the code where the data address should be patched
        offset: u64,
        /// Name of the data symbol to link to
        name: []const u8,
        kind: DataRelocationKind = .abs64,
    },

    /// A jump to the function's return sequence.
    /// Used for early returns in the middle of a function.
    jmp_to_return: struct {
        /// Location of the jump instruction
        inst_loc: u64,
        /// Size of the jump instruction (for calculating relative offset)
        inst_size: u64,
        /// Offset to the return sequence from the start of the function
        offset: u64,
    },

    /// Get the offset in the code where this relocation applies
    pub fn getOffset(self: Relocation) u64 {
        return switch (self) {
            inline .local_data, .linked_function, .linked_data => |r| r.offset,
            .jmp_to_return => |r| r.inst_loc,
        };
    }

    /// Adjust the offset of this relocation by the given amount
    pub fn adjustOffset(self: *Relocation, delta: u64) void {
        switch (self.*) {
            inline .local_data, .linked_function, .linked_data => |*r| r.offset += delta,
            .jmp_to_return => |*r| {
                r.inst_loc += delta;
                r.offset += delta;
            },
        }
    }
};

/// A relocation whose producer has already assigned its target identity.
/// Symbol IDs are scoped to the accompanying SymbolTable name column.
pub const IndexedRelocation = union(enum) {
    linked_function: struct { offset: u64, symbol: @import("SymbolTable.zig").Id },
    linked_data: struct {
        offset: u64,
        symbol: @import("SymbolTable.zig").Id,
        kind: DataRelocationKind = .abs64,
    },
    local_data: @FieldType(Relocation, "local_data"),
    jmp_to_return: @FieldType(Relocation, "jmp_to_return"),
    /// A relocation superseded by a stub that carries its own relocations.
    /// Consumers skip it; it keeps its slot so recorded relocation indices
    /// stay valid.
    retired,

    pub fn getOffset(self: IndexedRelocation) u64 {
        return switch (self) {
            inline .linked_function, .linked_data, .local_data => |r| r.offset,
            .jmp_to_return => |r| r.inst_loc,
            .retired => 0,
        };
    }

    pub fn adjustOffset(self: *IndexedRelocation, delta: u64) void {
        switch (self.*) {
            inline .linked_function, .linked_data, .local_data => |*r| r.offset += delta,
            .jmp_to_return => |*r| {
                r.inst_loc += delta;
                r.offset += delta;
            },
            .retired => {},
        }
    }
};

/// Function that resolves a symbol name to its address.
pub const SymbolResolver = *const fn (name: []const u8) ?usize;

/// Function that resolves a symbol name using caller-provided context.
pub const SymbolResolverContext = *const fn (ctx: *const anyopaque, name: []const u8) ?usize;

/// Errors that can occur when applying relocations to generated machine code.
pub const ApplyRelocationsError = error{
    UnresolvedSymbol,
    InvalidOffset,
    UnsupportedRelocationEncoding,
    MisalignedBranchTarget,
    BranchOutOfRange,
    OutOfMemory,
};

/// Apply relocations to a mutable code buffer.
/// The buffer should be writable. After this returns, the buffer can be
/// made executable via ExecutableMemory.
///
/// For x86_64 call instructions, this patches the 4-byte relative offset
/// after the E8 opcode.
pub fn applyRelocations(
    comptime isa: Isa,
    code: []u8,
    code_base_addr: usize,
    relocations: []const Relocation,
    resolver: SymbolResolver,
) ApplyRelocationsError!void {
    const ResolverBox = struct {
        resolver: SymbolResolver,

        fn resolve(ctx: *const anyopaque, name: []const u8) ?usize {
            const self: *const @This() = @ptrCast(@alignCast(ctx));
            return self.resolver(name);
        }
    };

    const box = ResolverBox{ .resolver = resolver };
    return applyRelocationsWithContext(isa, code, code_base_addr, relocations, &box, ResolverBox.resolve);
}

/// Apply relocations using a resolver that receives explicit caller context.
/// `isa` is the instruction set `code` was generated for; it decides how each
/// relocation site is encoded.
pub fn applyRelocationsWithContext(
    comptime isa: Isa,
    code: []u8,
    code_base_addr: usize,
    relocations: []const Relocation,
    resolver_ctx: *const anyopaque,
    resolver: SymbolResolverContext,
) ApplyRelocationsError!void {
    for (relocations) |reloc| {
        switch (reloc) {
            .linked_function => |func_reloc| {
                const target_addr = resolver(resolver_ctx, func_reloc.name) orelse {
                    return error.UnresolvedSymbol;
                };
                try patchLinkedFunctionRelocation(isa, code, code_base_addr, func_reloc.offset, target_addr);
            },
            .linked_data => |data_reloc| {
                const target_addr = resolver(resolver_ctx, data_reloc.name) orelse {
                    return error.UnresolvedSymbol;
                };
                try patchLinkedDataRelocation(code, code_base_addr, data_reloc.offset, target_addr, data_reloc.kind);
            },
            .local_data => |local_reloc| {
                // The data's address is baked into the generated code, so the
                // referenced bytes must outlive that code—the caller owns
                // that lifetime.
                const target_addr = @intFromPtr(local_reloc.data.ptr);
                const pointer_kind: DataRelocationKind = switch (isa) {
                    .x86_64, .aarch64 => .abs64,
                    .arm32 => .abs32,
                };
                try patchLinkedDataRelocation(code, code_base_addr, local_reloc.offset, target_addr, pointer_kind);
            },
            .jmp_to_return => |jmp_reloc| {
                try patchJumpToReturnRelocation(isa, code, code_base_addr, jmp_reloc.inst_loc, jmp_reloc.inst_size, jmp_reloc.offset);
            },
        }
    }
}

fn patchLinkedFunctionRelocation(comptime isa: Isa, code: []u8, code_base_addr: usize, reloc_offset_u64: u64, target_addr: usize) ApplyRelocationsError!void {
    const reloc_offset = try asCodeOffset(reloc_offset_u64, code.len);
    if (reloc_offset + 4 > code.len) return error.InvalidOffset;

    switch (isa) {
        // The offset names the rel32 operand of an E8 `call`.
        .x86_64 => {
            if (reloc_offset == 0 or code[reloc_offset - 1] != 0xE8) return error.UnsupportedRelocationEncoding;
            const next_instr = code_base_addr + reloc_offset + 4;
            return patchX86Rel32Operand(code, reloc_offset, next_instr, target_addr);
        },
        // The offset names a `bl`.
        .aarch64 => {
            const inst = std.mem.readInt(u32, code[reloc_offset..][0..4], .little);
            if ((inst >> 26) != 0b100101) return error.UnsupportedRelocationEncoding;
            return patchAarch64BranchInstruction(code, reloc_offset, code_base_addr + reloc_offset, target_addr);
        },
        // The offset names an A32 `bl` (R_ARM_CALL).
        .arm32 => {
            const inst = std.mem.readInt(u32, code[reloc_offset..][0..4], .little);
            if ((inst & 0x0F00_0000) != 0x0B00_0000) return error.UnsupportedRelocationEncoding;
            return patchArm32BranchInstruction(code, reloc_offset, code_base_addr + reloc_offset, target_addr);
        },
    }
}

/// Point an A32 `b`/`bl` at `target_addr`. The 24-bit word displacement is
/// relative to the instruction's address plus 8 (the A32 PC offset).
fn patchArm32BranchInstruction(code: []u8, inst_offset: usize, inst_addr: usize, target_addr: usize) ApplyRelocationsError!void {
    if (inst_offset + 4 > code.len) return error.InvalidOffset;
    const inst = std.mem.readInt(u32, code[inst_offset..][0..4], .little);
    const rel_bytes = @as(i128, @intCast(target_addr)) - (@as(i128, @intCast(inst_addr)) + 8);
    if ((rel_bytes & 0b11) != 0) return error.MisalignedBranchTarget;
    const rel_words = rel_bytes >> 2;
    if (!fitsSignedBits(rel_words, 24)) return error.BranchOutOfRange;
    const imm24: u24 = @bitCast(@as(i24, @intCast(rel_words)));
    std.mem.writeInt(u32, code[inst_offset..][0..4], (inst & 0xFF00_0000) | imm24, .little);
}

fn patchLinkedDataRelocation(
    code: []u8,
    code_base_addr: usize,
    reloc_offset_u64: u64,
    target_addr: usize,
    kind: DataRelocationKind,
) ApplyRelocationsError!void {
    const reloc_offset = try asCodeOffset(reloc_offset_u64, code.len);

    switch (kind) {
        .abs64 => return patchAbsolutePointerOperand(code, reloc_offset, target_addr),
        .rel32 => {
            const next_instr = code_base_addr + reloc_offset + 4;
            return patchX86Rel32Operand(code, reloc_offset, next_instr, target_addr);
        },
        .page21 => return patchAarch64AdrpRelocation(code, reloc_offset, code_base_addr + reloc_offset, target_addr),
        .pageoff12 => return patchAarch64PageOffset12Relocation(code, reloc_offset, target_addr),
        .abs32 => return patchAbsolute32Operand(code, reloc_offset, target_addr),
        .arm_movw_prel, .arm_movt_prel => return patchArmMovPrel(code, reloc_offset, code_base_addr + reloc_offset, target_addr, kind),
    }
}

fn patchAbsolute32Operand(code: []u8, operand_offset: usize, target_addr: usize) ApplyRelocationsError!void {
    if (operand_offset + 4 > code.len) return error.InvalidOffset;
    if (target_addr > std.math.maxInt(u32)) return error.BranchOutOfRange;
    std.mem.writeInt(u32, code[operand_offset..][0..4], @intCast(target_addr), .little);
}

/// Resolve one instruction of an arm32 PC-relative `movw`/`movt` address
/// sequence: write the relevant 16 bits of S + A - P into its imm4:imm12
/// fields (bits 19:16 and 11:0).
fn patchArmMovPrel(code: []u8, inst_offset: usize, inst_addr: usize, target_addr: usize, kind: DataRelocationKind) ApplyRelocationsError!void {
    if (inst_offset + 4 > code.len) return error.InvalidOffset;
    const value = @as(i128, @intCast(target_addr)) + kind.armMovAddend() - @as(i128, @intCast(inst_addr));
    if (!fitsSignedBits(value, 32)) return error.BranchOutOfRange;
    const bits: u32 = @bitCast(@as(i32, @intCast(value)));
    const imm16: u32 = switch (kind) {
        .arm_movw_prel => bits & 0xFFFF,
        .arm_movt_prel => bits >> 16,
        .abs64, .rel32, .page21, .pageoff12, .abs32 => unreachable,
    };
    var inst = std.mem.readInt(u32, code[inst_offset..][0..4], .little);
    inst = (inst & 0xFFF0F000) | ((imm16 >> 12) << 16) | (imm16 & 0xFFF);
    std.mem.writeInt(u32, code[inst_offset..][0..4], inst, .little);
}

fn patchJumpToReturnRelocation(
    comptime isa: Isa,
    code: []u8,
    code_base_addr: usize,
    inst_loc_u64: u64,
    inst_size_u64: u64,
    target_offset_u64: u64,
) ApplyRelocationsError!void {
    const inst_loc = try asCodeOffset(inst_loc_u64, code.len);
    const inst_size = try asCodeSize(inst_size_u64);
    if (inst_loc + inst_size > code.len) return error.InvalidOffset;

    const target_offset = try asCodeOffset(target_offset_u64, code.len);
    const target_addr = code_base_addr + target_offset;
    const inst_addr = code_base_addr + inst_loc;

    switch (inst_size) {
        2 => {
            if (inst_loc + 2 > code.len) return error.InvalidOffset;
            const opcode = code[inst_loc];
            if (opcode == 0xEB or (opcode >= 0x70 and opcode <= 0x7F)) {
                return patchX86Rel8Operand(code, inst_loc + 1, inst_addr + 2, target_addr);
            }
            return error.UnsupportedRelocationEncoding;
        },
        4 => switch (isa) {
            .aarch64 => return patchAarch64BranchInstruction(code, inst_loc, inst_addr, target_addr),
            .arm32 => return patchArm32BranchInstruction(code, inst_loc, inst_addr, target_addr),
            .x86_64 => return error.UnsupportedRelocationEncoding,
        },
        5 => {
            if (inst_loc + 5 > code.len) return error.InvalidOffset;
            const opcode = code[inst_loc];
            if (opcode == 0xE9 or opcode == 0xE8) {
                return patchX86Rel32Operand(code, inst_loc + 1, inst_addr + 5, target_addr);
            }
            return error.UnsupportedRelocationEncoding;
        },
        6 => {
            if (inst_loc + 6 > code.len) return error.InvalidOffset;
            const first = code[inst_loc];
            const second = code[inst_loc + 1];
            if (first == 0x0F and second >= 0x80 and second <= 0x8F) {
                return patchX86Rel32Operand(code, inst_loc + 2, inst_addr + 6, target_addr);
            }
            return error.UnsupportedRelocationEncoding;
        },
        else => return error.UnsupportedRelocationEncoding,
    }
}

fn patchX86Rel32Operand(code: []u8, operand_offset: usize, next_instr_addr: usize, target_addr: usize) ApplyRelocationsError!void {
    if (operand_offset + 4 > code.len) return error.InvalidOffset;

    const rel_i128 = @as(i128, @intCast(target_addr)) - @as(i128, @intCast(next_instr_addr));
    if (rel_i128 < std.math.minInt(i32) or rel_i128 > std.math.maxInt(i32)) return error.BranchOutOfRange;

    const rel: i32 = @intCast(rel_i128);
    const rel_bytes: [4]u8 = @bitCast(rel);
    @memcpy(code[operand_offset..][0..4], &rel_bytes);
}

fn patchX86Rel8Operand(code: []u8, operand_offset: usize, next_instr_addr: usize, target_addr: usize) ApplyRelocationsError!void {
    if (operand_offset + 1 > code.len) return error.InvalidOffset;

    const rel_i128 = @as(i128, @intCast(target_addr)) - @as(i128, @intCast(next_instr_addr));
    if (rel_i128 < std.math.minInt(i8) or rel_i128 > std.math.maxInt(i8)) return error.BranchOutOfRange;

    const rel: i8 = @intCast(rel_i128);
    code[operand_offset] = @bitCast(rel);
}

fn patchAarch64BranchInstruction(code: []u8, inst_offset: usize, inst_addr: usize, target_addr: usize) ApplyRelocationsError!void {
    if (inst_offset + 4 > code.len) return error.InvalidOffset;

    var inst = std.mem.readInt(u32, code[inst_offset..][0..4], .little);
    const rel_bytes_i128 = @as(i128, @intCast(target_addr)) - @as(i128, @intCast(inst_addr));
    if ((rel_bytes_i128 & 0b11) != 0) return error.MisalignedBranchTarget;
    // Alignment is established above. Arithmetic shift expresses the signed
    // word displacement directly, without a debug-build i128 division libcall.
    const rel_words_i128 = rel_bytes_i128 >> 2;

    if ((inst >> 26) == 0b000101 or (inst >> 26) == 0b100101) {
        if (!fitsSignedBits(rel_words_i128, 26)) return error.BranchOutOfRange;
        const rel_words_i26: i26 = @intCast(rel_words_i128);
        const imm26: u26 = @bitCast(rel_words_i26);
        inst = (inst & 0xFC000000) | @as(u32, imm26);
    } else if ((inst >> 24) == 0b01010100 or (((inst >> 24) & 0b01111111) == 0b0110100) or (((inst >> 24) & 0b01111111) == 0b0110101)) {
        if (!fitsSignedBits(rel_words_i128, 19)) return error.BranchOutOfRange;
        const rel_words_i19: i19 = @intCast(rel_words_i128);
        const imm19: u19 = @bitCast(rel_words_i19);
        inst = (inst & 0xFF00001F) | (@as(u32, imm19) << 5);
    } else {
        return error.UnsupportedRelocationEncoding;
    }

    std.mem.writeInt(u32, code[inst_offset..][0..4], inst, .little);
}

fn patchAbsolutePointerOperand(code: []u8, operand_offset: usize, target_addr: usize) ApplyRelocationsError!void {
    if (@sizeOf(usize) == 8) {
        if (operand_offset + 8 > code.len) return error.InvalidOffset;
        std.mem.writeInt(u64, code[operand_offset..][0..8], @intCast(target_addr), .little);
        return;
    }

    if (@sizeOf(usize) == 4) {
        if (operand_offset + 4 > code.len) return error.InvalidOffset;
        if (target_addr > std.math.maxInt(u32)) return error.BranchOutOfRange;
        std.mem.writeInt(u32, code[operand_offset..][0..4], @intCast(target_addr), .little);
        return;
    }

    @compileError("Unsupported pointer size");
}

fn patchAarch64AdrpRelocation(code: []u8, inst_offset: usize, inst_addr: usize, target_addr: usize) ApplyRelocationsError!void {
    if (inst_offset + 4 > code.len) return error.InvalidOffset;

    var inst = std.mem.readInt(u32, code[inst_offset..][0..4], .little);
    if ((inst & 0x9F00_0000) != 0x9000_0000) return error.UnsupportedRelocationEncoding;

    const page_mask: usize = ~@as(usize, 0xFFF);
    const inst_page = inst_addr & page_mask;
    const target_page = target_addr & page_mask;
    // Both addresses have their low twelve bits cleared. This signed shift
    // is exact for backward as well as forward page displacements.
    const delta_pages_i128 = (@as(i128, @intCast(target_page)) - @as(i128, @intCast(inst_page))) >> 12;
    if (!fitsSignedBits(delta_pages_i128, 21)) return error.BranchOutOfRange;

    const delta_pages_i21: i21 = @intCast(delta_pages_i128);
    const imm21: u21 = @bitCast(delta_pages_i21);
    const immlo: u32 = @as(u32, imm21 & 0b11);
    const immhi: u32 = @as(u32, imm21 >> 2);

    inst &= ~(@as(u32, 0b11) << 29);
    inst &= ~(@as(u32, 0x7FFFF) << 5);
    inst |= immlo << 29;
    inst |= immhi << 5;

    std.mem.writeInt(u32, code[inst_offset..][0..4], inst, .little);
}

fn patchAarch64PageOffset12Relocation(code: []u8, inst_offset: usize, target_addr: usize) ApplyRelocationsError!void {
    if (inst_offset + 4 > code.len) return error.InvalidOffset;

    var inst = std.mem.readInt(u32, code[inst_offset..][0..4], .little);
    if ((inst & 0x7F00_0000) != 0x1100_0000) return error.UnsupportedRelocationEncoding;

    const lo12: u32 = @intCast(target_addr & 0xFFF);
    inst &= ~(@as(u32, 0xFFF) << 10);
    inst |= lo12 << 10;

    std.mem.writeInt(u32, code[inst_offset..][0..4], inst, .little);
}

fn asCodeOffset(offset: u64, code_len: usize) ApplyRelocationsError!usize {
    if (offset > std.math.maxInt(usize)) return error.InvalidOffset;
    const idx: usize = @intCast(offset);
    if (idx > code_len) return error.InvalidOffset;
    return idx;
}

fn asCodeSize(size: u64) ApplyRelocationsError!usize {
    if (size > std.math.maxInt(usize)) return error.InvalidOffset;
    return @intCast(size);
}

fn fitsSignedBits(value: i128, comptime bits: comptime_int) bool {
    const min = -(@as(i128, 1) << (bits - 1));
    const max = (@as(i128, 1) << (bits - 1)) - 1;
    return value >= min and value <= max;
}

test "relocation creation" {
    const data = [_]u8{ 1, 2, 3, 4 };
    const local = Relocation{ .local_data = .{
        .offset = 100,
        .data = &data,
    } };
    try std.testing.expectEqual(@as(u64, 100), local.getOffset());

    const func = Relocation{ .linked_function = .{
        .offset = 200,
        .name = @import("builtins").shim_symbols.roc_alloc,
    } };
    try std.testing.expectEqual(@as(u64, 200), func.getOffset());
}

fn testNullResolver(_: []const u8) ?usize {
    return null;
}

fn readPointerFromCode(bytes: []const u8) usize {
    if (@sizeOf(usize) == 8) {
        return @intCast(std.mem.readInt(u64, bytes[0..8], .little));
    }

    if (@sizeOf(usize) == 4) {
        return @intCast(std.mem.readInt(u32, bytes[0..4], .little));
    }

    @compileError("Unsupported pointer size");
}

test "applyRelocations patches x86_64 linked_function call" {
    var code = [_]u8{ 0xE8, 0x00, 0x00, 0x00, 0x00 };
    const code_base: usize = 0x1000;
    const target_addr: usize = 0x1020;

    const resolver: SymbolResolver = struct {
        fn resolve(name: []const u8) ?usize {
            if (std.mem.eql(u8, name, "callee")) return target_addr;
            return null;
        }
    }.resolve;

    const relocs = [_]Relocation{
        .{ .linked_function = .{ .offset = 1, .name = "callee" } },
    };

    try applyRelocations(.x86_64, &code, code_base, &relocs, resolver);

    const patched = std.mem.readInt(i32, code[1..5], .little);
    try std.testing.expectEqual(@as(i32, 27), patched); // 0x1020 - (0x1000 + 5)
}

test "applyRelocations patches aarch64 linked_function bl" {
    var code = [_]u8{ 0x00, 0x00, 0x00, 0x94 }; // BL #0
    const code_base: usize = 0x2000;
    const target_addr: usize = code_base + 16;

    const resolver: SymbolResolver = struct {
        fn resolve(name: []const u8) ?usize {
            if (std.mem.eql(u8, name, "callee")) return target_addr;
            return null;
        }
    }.resolve;

    const relocs = [_]Relocation{
        .{ .linked_function = .{ .offset = 0, .name = "callee" } },
    };

    try applyRelocations(.aarch64, &code, code_base, &relocs, resolver);

    const inst = std.mem.readInt(u32, &code, .little);
    try std.testing.expectEqual(@as(u32, 0b100101), inst >> 26);
    try std.testing.expectEqual(@as(u32, 4), inst & 0x03FF_FFFF); // 16-byte delta / 4
}

test "applyRelocations patches arm32 linked_function bl" {
    // bl #0 at 0x1000, target 0x2008: displacement (0x2008 - 0x1008) / 4.
    var code = [_]u8{ 0xFE, 0xFF, 0xFF, 0xEB };
    const relocs = [_]Relocation{.{ .linked_function = .{ .offset = 0, .name = "target" } }};
    const resolver = struct {
        fn resolve(name: []const u8) ?usize {
            return if (std.mem.eql(u8, name, "target")) 0x2008 else null;
        }
    }.resolve;
    try applyRelocations(.arm32, &code, 0x1000, &relocs, resolver);
    try std.testing.expectEqual(@as(u32, 0xEB00_0400), std.mem.readInt(u32, &code, .little));
    // A backward target encodes a negative displacement.
    const back = struct {
        fn resolve(_: []const u8) ?usize {
            return 0x0800;
        }
    }.resolve;
    try applyRelocations(.arm32, &code, 0x1000, &relocs, back);
    try std.testing.expectEqual(@as(u32, 0xEBFF_FDFE), std.mem.readInt(u32, &code, .little));
    // An x86 `call` opcode is not an A32 branch.
    var not_bl = [_]u8{ 0x00, 0x00, 0x00, 0xE8 };
    try std.testing.expectError(error.UnsupportedRelocationEncoding, applyRelocations(.arm32, &not_bl, 0x1000, &relocs, resolver));
}

test "applyRelocations patches linked_data absolute pointer operand" {
    var code = [_]u8{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };
    const target_addr: usize = if (@sizeOf(usize) == 8) 0x1122334455667788 else 0x11223344;

    const resolver: SymbolResolver = struct {
        fn resolve(name: []const u8) ?usize {
            if (std.mem.eql(u8, name, "global_data")) return target_addr;
            return null;
        }
    }.resolve;

    const relocs = [_]Relocation{
        .{ .linked_data = .{ .offset = 4, .name = "global_data" } },
    };

    try applyRelocations(.x86_64, &code, 0, &relocs, resolver);
    try std.testing.expectEqual(target_addr, readPointerFromCode(code[4..]));
}

test "applyRelocations patches local_data pointer and stores bytes" {
    var code = [_]u8{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };
    const bytes = [_]u8{ 'a', 'b', 'c' };

    const relocs = [_]Relocation{
        .{ .local_data = .{ .offset = 0, .data = &bytes } },
    };

    try applyRelocations(.x86_64, &code, 0, &relocs, testNullResolver);

    const ptr_value = readPointerFromCode(code[0..]);
    try std.testing.expect(ptr_value != 0);
    const data_ptr: [*]const u8 = @ptrFromInt(ptr_value);
    try std.testing.expectEqualSlices(u8, &bytes, data_ptr[0..bytes.len]);
}

test "applyRelocations patches x86_64 jmp_to_return" {
    var code = [_]u8{
        0xE9, 0x00, 0x00, 0x00, 0x00, // jmp rel32
        0x90, // nop
        0xC3, // ret
    };
    const relocs = [_]Relocation{
        .{
            .jmp_to_return = .{
                .inst_loc = 0,
                .inst_size = 5,
                .offset = 6, // target ret
            },
        },
    };

    try applyRelocations(.x86_64, &code, 0, &relocs, testNullResolver);
    try std.testing.expectEqual(@as(i32, 1), std.mem.readInt(i32, code[1..5], .little));
}

test "applyRelocations patches aarch64 jmp_to_return" {
    var code = [_]u8{
        0x00, 0x00, 0x00, 0x14, // B #0
        0x1F, 0x20, 0x03, 0xD5, // NOP
        0xC0, 0x03, 0x5F, 0xD6, // RET
    };

    const relocs = [_]Relocation{
        .{ .jmp_to_return = .{
            .inst_loc = 0,
            .inst_size = 4,
            .offset = 8,
        } },
    };

    try applyRelocations(.aarch64, &code, 0, &relocs, testNullResolver);

    const inst = std.mem.readInt(u32, code[0..4], .little);
    try std.testing.expectEqual(@as(u32, 0b000101), inst >> 26); // B
    try std.testing.expectEqual(@as(u32, 2), inst & 0x03FF_FFFF); // 8-byte delta / 4
}

test "aarch64 signed branch and page displacements preserve exact units" {
    var code: [4]u8 = undefined;
    for ([_]i64{ -0x8000000, -4, 0, 4, 0x7fffffc }) |displacement| {
        std.mem.writeInt(u32, &code, 0x94000000, .little); // BL
        const base: usize = 0x8000000;
        const target: usize = @intCast(@as(i64, base) + displacement);
        try patchAarch64BranchInstruction(&code, 0, base, target);
        const words: i26 = @bitCast(@as(u26, @truncate(std.mem.readInt(u32, &code, .little))));
        try std.testing.expectEqual(displacement, @as(i64, words) * 4);
    }
    std.mem.writeInt(u32, &code, 0x94000000, .little);
    try std.testing.expectError(error.MisalignedBranchTarget, patchAarch64BranchInstruction(&code, 0, 0, 2));
    try std.testing.expectError(error.BranchOutOfRange, patchAarch64BranchInstruction(&code, 0, 0, 0x8000000));
    if (@sizeOf(usize) < 8) return;
    for ([_]i64{ -0x100000, -1, 0, 1, 0xfffff }) |pages| {
        std.mem.writeInt(u32, &code, 0x90000000, .little); // ADRP
        const base: usize = 0x100000000;
        const target: usize = @intCast(@as(i64, base) + pages * 4096 + 7);
        try patchAarch64AdrpRelocation(&code, 0, base + 3, target);
        const inst = std.mem.readInt(u32, &code, .little);
        const imm: u21 = @intCast(((inst >> 29) & 3) | (((inst >> 5) & 0x7ffff) << 2));
        try std.testing.expectEqual(pages, @as(i64, @as(i21, @bitCast(imm))));
    }
    std.mem.writeInt(u32, &code, 0x90000000, .little);
    try std.testing.expectError(error.BranchOutOfRange, patchAarch64AdrpRelocation(&code, 0, 0, 0x100000000));
}

test "arm32 movw/movt PC-relative relocations resolve the address sequence" {
    // movw r4, #0; movt r4, #0; add r4, pc, r4
    var code = [_]u8{
        0x00, 0x40, 0x00, 0xE3,
        0x00, 0x40, 0x40, 0xE3,
        0x04, 0x40, 0x8F, 0xE0,
    };
    const base: usize = 0x10000;
    const target: usize = 0x2345678;
    try patchLinkedDataRelocation(&code, base, 0, target, .arm_movw_prel);
    try patchLinkedDataRelocation(&code, base, 4, target, .arm_movt_prel);
    const movw = std.mem.readInt(u32, code[0..4], .little);
    const movt = std.mem.readInt(u32, code[4..8], .little);
    const lo = ((movw >> 4) & 0xF000) | (movw & 0xFFF);
    const hi = ((movt >> 4) & 0xF000) | (movt & 0xFFF);
    // The add at base+8 reads PC as base+16; r4 must end up as the target.
    try std.testing.expectEqual(@as(u32, @intCast(target - (base + 16))), (hi << 16) | lo);
}

test "arm32 abs32 relocation writes a 32-bit address" {
    var code = [_]u8{0} ** 4;
    try patchLinkedDataRelocation(&code, 0, 0, 0x89ABCDEF, .abs32);
    try std.testing.expectEqual(@as(u32, 0x89ABCDEF), std.mem.readInt(u32, &code, .little));
}
