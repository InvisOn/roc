app [main!] { pf: platform "./platform/main.roc" }

import pf.Stdout
import pf.Abi

## Call-shape battery: each hosted call below has a C signature whose
## arguments or result a native backend must place exactly. The host folds
## the arguments with distinct weights, so any argument read from the wrong
## register or stack slot prints a different number.
main! = || {
    # (i32, i64), including a negative i64 whose high word is all ones.
    Stdout.line!("i32_i64: ${Str.inspect(Abi.i32_i64!(3, 5_000_000_000))} ${Str.inspect(Abi.i32_i64!(-3, -5_000_000_000))}")

    # (i32, i32, i32, i64): the i64 goes past the argument registers on arm32.
    Stdout.line!("three_i32_i64: ${Str.inspect(Abi.three_i32_i64!(1, 2, 3, 4_000_000_000))}")

    # (i32, i32, Triple): the record splits between registers and the stack.
    Stdout.line!("two_i32_triple: ${Str.inspect(Abi.two_i32_triple!(1, 2, { a: 3, b: 4, c: 5 }))}")

    # (f64, f32, f64): the f32 back-fills a single-precision register.
    Stdout.line!("f64_f32_f64: ${Str.inspect(Abi.f64_f32_f64!(1.5, 2.25, 3.125))}")

    # Nine f64 arguments: one more than the floating-point argument registers.
    Stdout.line!("nine_f64: ${Str.inspect(Abi.nine_f64!(1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0))}")

    # A 12-byte record result through a hidden result pointer.
    triple = Abi.triple_from!(7)
    Stdout.line!("triple_from: ${Str.inspect(triple.a)} ${Str.inspect(triple.b)} ${Str.inspect(triple.c)}")

    # F64 -> I64 -> F64 across the boundary.
    bits = Abi.f64_bits!(-1.5)
    Stdout.line!("f64 round trip: ${Str.inspect(bits)} ${Str.inspect(Abi.f64_from_bits!(bits))}")
}
