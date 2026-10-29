const std = @import("std");
fn Gen(comptime word_bits: u8) type {
    return struct {
        inline fn exceedsWord(bits: u8) bool {
            return word_bits < 64 and bits > word_bits;
        }
        fn binop(bits: u8) u32 {
            if (exceedsWord(bits)) return wide64Binop(bits);
            return 1;
        }
        fn wide64Binop(bits: u8) u32 {
            _ = bits;
            @compileError("64-bit integers on a 4-byte word need the register-pair lowering (part 10)");
        }
    };
}
test "inline helper prunes on 8-byte words" {
    var bits: u8 = 64;
    _ = &bits;
    try std.testing.expectEqual(@as(u32, 1), Gen(64).binop(bits));
}
