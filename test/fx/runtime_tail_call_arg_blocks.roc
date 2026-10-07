app [main!] { pf: platform "./platform/main.roc" }

import pf.Stdin
import pf.Stdout

# Tail calls between functions whose argument blocks differ in size, driven by
# a runtime value so the calls reach the backends instead of being folded.
# `ping` takes enough arguments that some are passed on the stack on every
# target; `pong` takes few enough that none are. A frame-replacing call from
# `ping` to `pong` drops a block, one from `pong` to `ping` grows one, and a
# million of them run in constant stack.

ping : U64, U64, U64, U64, U64, U64, U64 -> U64
ping = |n, a, b, c, d, e, acc| if n == 0 acc + a + b + c + d + e else pong(n - 1, acc + 1)

pong : U64, U64 -> U64
pong = |n, acc| if n == 0 acc else ping(n - 1, 1, 2, 3, 4, 5, acc + 2)

main! = || {
    n = match U64.from_str(Stdin.line!()) {
        Ok(number) => number
        Err(_) => 0
    }
    Stdout.line!("ping first: ${ping(n, 1, 2, 3, 4, 5, 0).to_str()}")
    Stdout.line!("pong first: ${pong(n, 0).to_str()}")
}
