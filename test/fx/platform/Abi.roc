## Three I32s in declared order; the host reads it as `extern struct { a, b, c: i32 }`.
Triple : { a : I32, b : I32, c : I32 }

## Hosted functions whose C signatures are the argument and result shapes a
## native backend's call lowering must place exactly (on arm32, the AAPCS32
## cases listed under "Link-and-run conformance" in
## projects/big/arm32-dev-backend.md). Each host function folds its arguments
## with distinct weights, so an argument read from the wrong register or stack
## slot changes the result.
Abi := [].{
    ## (i32, i64): the i64 is a register pair; on arm32 r0 then r2:r3, r1 unused.
    i32_i64! : I32, I64 => I64

    ## (i32, i32, i32, i64): on arm32 r0-r2, r3 unused, the i64 on the stack.
    three_i32_i64! : I32, I32, I32, I64 => I64

    ## (i32, i32, Triple): on arm32 r0, r1, then the record split across r2,
    ## r3 and the stack (AAPCS32 rule C.5).
    two_i32_triple! : I32, I32, Triple => I64

    ## (f64, f32, f64): on arm32 d0, s2, d2 (the f32 back-fills).
    f64_f32_f64! : F64, F32, F64 => F64

    ## Nine f64 arguments: on arm32 d0-d7, then the ninth on the stack.
    nine_f64! : F64, F64, F64, F64, F64, F64, F64, F64, F64 => F64

    ## A 12-byte composite result, returned through a hidden result pointer.
    triple_from! : I32 => Triple

    ## An F64 to its I64 bit pattern, and back: an F64 -> I64 -> F64 round
    ## trip across the boundary.
    f64_bits! : F64 => I64
    f64_from_bits! : I64 => F64
}
