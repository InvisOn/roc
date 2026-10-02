//! arm32 (AAPCS32, VFP hard-float variant) C-ABI parameter/return
//! classification for Roc layouts.
//!
//! See D3/D4 of projects/big/arm32-dev-backend.md and the AAPCS32
//! specification (IHI0042). The classification is by kind, and the register
//! and stack assignment (`call.assignPhysicalArgs`) applies the allocation
//! rules:
//! - a fundamental integer or pointer of at most four bytes is one core
//!   register word; a 64-bit integer is an even core-register pair (C.3) and
//!   is never split;
//! - f32/f64 values and homogeneous floating-point aggregates of one to four
//!   members of one width, and a 128-bit vector (or an aggregate wrapping
//!   exactly one), are co-processor register candidates (VFP registers, with
//!   back-filling);
//! - every other composite is a sequence of words that may be split between
//!   the last core registers and the stack (C.5);
//! - a composite result wider than four bytes is returned in memory through
//!   a pointer in r0.
//!
//! Roc's I128/U128/Dec have no C fundamental type on arm32: glue exposes them
//! as 16-byte, 8-aligned composites.

const std = @import("std");

const layout = @import("../layout.zig");
const store_mod = @import("../store.zig");

const Store = store_mod.Store;
const Idx = layout.Idx;
const Layout = layout.Layout;

/// How a value is passed or returned under AAPCS32 VFP.
pub const Class = union(enum) {
    /// Core-register words: `count` of them, holding the value's bytes in
    /// order. `fundamental` is a C integer or pointer, which is never split
    /// between registers and the stack; a composite may be.
    words: Words,
    /// f32/f64 scalars and homogeneous floating-point aggregates, in VFP
    /// registers.
    float_array: FloatArray,
    /// A 128-bit vector (or an aggregate transparently wrapping exactly one),
    /// in one Q register.
    vector: layout.Vector,
    /// Returned in memory through a result pointer (results only).
    memory,
};

/// A value's core-register words; see `Class.words`.
pub const Words = struct {
    count: u8,
    fundamental: bool,
};

/// A homogeneous aggregate of `count` floats, each `elem_bits` wide (32 or 64).
pub const FloatArray = struct {
    count: u8,
    elem_bits: u16,
};

const max_hfa_members = 4;

/// Whether a value is an argument or the result.
pub const Position = enum { arg, ret };

/// Classify how the value of layout `idx` is passed (`.arg`) or returned
/// (`.ret`) under AAPCS32 VFP. The layout must have runtime bits.
pub fn classifyType(store: *const Store, idx: Idx, position: Position) Class {
    const lay = store.getLayout(idx);
    const size = store.layoutSize(lay);
    std.debug.assert(size > 0);

    if (fundamentalKind(store, idx)) |kind| return switch (kind) {
        .word => .{ .words = .{ .count = 1, .fundamental = true } },
        .doubleword => .{ .words = .{ .count = 2, .fundamental = true } },
        .float => |bits| .{ .float_array = .{ .count = 1, .elem_bits = bits } },
        .vector => |vector| .{ .vector = vector },
    };

    // Composites.
    var maybe_vector_kind: ?layout.Vector = null;
    if (countVectors(store, idx, &maybe_vector_kind) == 1) return .{ .vector = maybe_vector_kind.? };
    var maybe_float_bits: ?u16 = null;
    const float_count = countFloats(store, idx, &maybe_float_bits);
    if (float_count >= 1 and float_count <= max_hfa_members) {
        return .{ .float_array = .{ .count = float_count, .elem_bits = maybe_float_bits.? } };
    }
    if (position == .ret and size > 4) return .memory;
    return .{ .words = .{ .count = @intCast((size + 3) / 4), .fundamental = false } };
}

const Fundamental = union(enum) {
    word,
    doubleword,
    float: u16,
    vector: layout.Vector,
};

/// The C fundamental type glue gives `idx`, or null for a composite.
fn fundamentalKind(store: *const Store, idx: Idx) ?Fundamental {
    const lay = store.getLayout(idx);
    return switch (lay.tag) {
        .scalar => {
            const scalar = lay.getScalar();
            return switch (scalar.tag) {
                .int => switch (store.layoutSize(lay)) {
                    1, 2, 4 => .word,
                    8 => .doubleword,
                    // I128/U128 are composites on arm32.
                    else => null,
                },
                .opaque_ptr => .word,
                .frac => switch (scalar.getFrac()) {
                    .f32 => .{ .float = 32 },
                    .f64 => .{ .float = 64 },
                    // Dec is a 16-byte composite on arm32.
                    .dec => null,
                },
                .vector => .{ .vector = scalar.getVector() },
                // RocStr is a three-word composite.
                .str => null,
            };
        },
        .box, .box_of_zst, .erased_box, .ptr, .erased_callable => .word,
        .tag_union => {
            const info = store.getTagUnionInfo(lay);
            // Glue unwraps a single-variant union to its payload.
            if (info.variants.len == 1 and info.data.discriminant_size == 0) {
                return fundamentalKind(store, info.variants.get(0).payload_layout);
            }
            // A payload-free union is its unsigned discriminant integer.
            for (0..info.variants.len) |i| {
                if (store.layoutSize(store.getLayout(info.variants.get(i).payload_layout)) != 0) return null;
            }
            return switch (store.layoutSize(lay)) {
                1, 2, 4 => .word,
                8 => .doubleword,
                else => null,
            };
        },
        .list, .list_of_zst, .struct_, .closure => null,
        .zst => unreachable,
    };
}

const invalid_count = std.math.maxInt(u8);

/// Count the vector leaves of an aggregate made only of vectors; stops at
/// two, since more classify alike (as ordinary composites).
fn countVectors(store: *const Store, idx: Idx, maybe_kind: *?layout.Vector) u8 {
    const lay = store.getLayout(idx);
    switch (lay.tag) {
        .struct_ => {
            const struct_idx = lay.getStruct().idx;
            const field_count = store.getStructData(struct_idx).fields.count;
            var count: u8 = 0;
            var i: u32 = 0;
            while (i < field_count) : (i += 1) {
                if (store.getStructFieldIsPadding(struct_idx, i)) return invalid_count;
                const field = countVectors(store, store.getStructFieldLayout(struct_idx, i), maybe_kind);
                if (field == invalid_count) return invalid_count;
                count += field;
                if (count > 1) return count;
            }
            return count;
        },
        .scalar => {
            const scalar = lay.getScalar();
            if (scalar.tag != .vector) return invalid_count;
            if (maybe_kind.* == null) maybe_kind.* = scalar.getVector();
            return 1;
        },
        .tag_union => {
            const info = store.getTagUnionInfo(lay);
            if (info.variants.len != 1 or info.data.discriminant_size != 0) return invalid_count;
            return countVectors(store, info.variants.get(0).payload_layout, maybe_kind);
        },
        .box, .box_of_zst, .erased_box, .list, .list_of_zst, .closure, .erased_callable, .zst, .ptr => return invalid_count,
    }
}

/// Count the float members of a homogeneous aggregate, or `invalid_count`
/// when a member is not an f32/f64 of the aggregate's one width or there are
/// more than four.
fn countFloats(store: *const Store, idx: Idx, maybe_bits: *?u16) u8 {
    const lay = store.getLayout(idx);
    switch (lay.tag) {
        .struct_ => {
            const struct_idx = lay.getStruct().idx;
            const field_count = store.getStructData(struct_idx).fields.count;
            var count: u8 = 0;
            var i: u32 = 0;
            while (i < field_count) : (i += 1) {
                if (store.getStructFieldIsPadding(struct_idx, i)) return invalid_count;
                const field = countFloats(store, store.getStructFieldLayout(struct_idx, i), maybe_bits);
                if (field == invalid_count) return invalid_count;
                count += field;
                if (count > max_hfa_members) return invalid_count;
            }
            return count;
        },
        .scalar => {
            const scalar = lay.getScalar();
            if (scalar.tag != .frac) return invalid_count;
            const bits: u16 = switch (scalar.getFrac()) {
                .f32 => 32,
                .f64 => 64,
                .dec => return invalid_count,
            };
            if (maybe_bits.*) |existing| {
                if (existing != bits) return invalid_count;
            } else maybe_bits.* = bits;
            return 1;
        },
        .tag_union => {
            const info = store.getTagUnionInfo(lay);
            if (info.variants.len != 1 or info.data.discriminant_size != 0) return invalid_count;
            return countFloats(store, info.variants.get(0).payload_layout, maybe_bits);
        },
        .box, .box_of_zst, .erased_box, .list, .list_of_zst, .closure, .erased_callable, .zst, .ptr => return invalid_count,
    }
}

const testing = std.testing;

fn testStruct(store: *Store, field_idxs: []const Idx) std.mem.Allocator.Error!Idx {
    var fields: [16]layout.StructField = undefined;
    for (field_idxs, 0..) |field_idx, i| {
        fields[i] = .{ .index = @intCast(i), .layout = field_idx };
    }
    return store.putStructFields(fields[0..field_idxs.len]);
}

test "arm32 classify: fundamental types" {
    var store = try Store.init(testing.allocator, .u32);
    defer store.deinit();

    const word: Class = .{ .words = .{ .count = 1, .fundamental = true } };
    const pair: Class = .{ .words = .{ .count = 2, .fundamental = true } };
    try testing.expectEqual(word, classifyType(&store, .u8, .arg));
    try testing.expectEqual(word, classifyType(&store, .i32, .ret));
    try testing.expectEqual(word, classifyType(&store, .opaque_ptr, .arg));
    try testing.expectEqual(pair, classifyType(&store, .u64, .arg));
    try testing.expectEqual(pair, classifyType(&store, .i64, .ret));
    try testing.expectEqual(Class{ .float_array = .{ .count = 1, .elem_bits = 32 } }, classifyType(&store, .f32, .arg));
    try testing.expectEqual(Class{ .float_array = .{ .count = 1, .elem_bits = 64 } }, classifyType(&store, .f64, .ret));
    try testing.expectEqual(Class{ .vector = .u8x16 }, classifyType(&store, .u8x16, .arg));
    // Bool is a payload-free union: its one-byte discriminant integer.
    try testing.expectEqual(word, classifyType(&store, .bool, .ret));
}

test "arm32 classify: 128-bit integers and Dec are composites" {
    var store = try Store.init(testing.allocator, .u32);
    defer store.deinit();

    const four: Class = .{ .words = .{ .count = 4, .fundamental = false } };
    try testing.expectEqual(four, classifyType(&store, .i128, .arg));
    try testing.expectEqual(four, classifyType(&store, .dec, .arg));
    try testing.expectEqual(Class.memory, classifyType(&store, .u128, .ret));
}

test "arm32 classify: RocStr and RocList are three-word composites" {
    var store = try Store.init(testing.allocator, .u32);
    defer store.deinit();

    const three: Class = .{ .words = .{ .count = 3, .fundamental = false } };
    try testing.expectEqual(three, classifyType(&store, .str, .arg));
    const list_idx = try store.insertLayout(Layout.list(.u8));
    try testing.expectEqual(three, classifyType(&store, list_idx, .arg));
    try testing.expectEqual(Class.memory, classifyType(&store, .str, .ret));
}

test "arm32 classify: small composites return in r0, larger ones in memory" {
    var store = try Store.init(testing.allocator, .u32);
    defer store.deinit();

    const small = try testStruct(&store, &.{ .u16, .u8 });
    try testing.expectEqual(Class{ .words = .{ .count = 1, .fundamental = false } }, classifyType(&store, small, .ret));
    // A struct wrapping a U64 is a composite, unlike a bare U64.
    const wrapped = try testStruct(&store, &.{.u64});
    try testing.expectEqual(Class.memory, classifyType(&store, wrapped, .ret));
    try testing.expectEqual(Class{ .words = .{ .count = 2, .fundamental = false } }, classifyType(&store, wrapped, .arg));
}

test "arm32 classify: homogeneous float aggregates and vectors" {
    var store = try Store.init(testing.allocator, .u32);
    defer store.deinit();

    const two_f32 = try testStruct(&store, &.{ .f32, .f32 });
    try testing.expectEqual(Class{ .float_array = .{ .count = 2, .elem_bits = 32 } }, classifyType(&store, two_f32, .ret));
    const four_f64 = try testStruct(&store, &.{ .f64, .f64, .f64, .f64 });
    try testing.expectEqual(Class{ .float_array = .{ .count = 4, .elem_bits = 64 } }, classifyType(&store, four_f64, .arg));
    const five_f32 = try testStruct(&store, &.{ .f32, .f32, .f32, .f32, .f32 });
    try testing.expectEqual(Class{ .words = .{ .count = 5, .fundamental = false } }, classifyType(&store, five_f32, .arg));
    const mixed = try testStruct(&store, &.{ .f32, .f64 });
    try testing.expectEqual(Class.memory, classifyType(&store, mixed, .ret));
    const one_vector = try testStruct(&store, &.{.i32x4});
    try testing.expectEqual(Class{ .vector = .i32x4 }, classifyType(&store, one_vector, .ret));
}
