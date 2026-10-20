# Draft: LLVM eval backend aborts on "inspect: inclusive numeric ranges all iterate" on aarch64

> **Upstream or ours:** Upstream, as far as we can tell. We reproduced it with a compiler built from upstream's code plus one unrelated local patch. The CI failures were on our fork's branch. Still to be confirmed on clean upstream.

> **Relevance to our arm32 work:** It failed `eval-llvm (macos-15)` in our CI. arm32 doesn't use the LLVM backend, so it is unrelated to our code.

Not filed. For roc-lang/roc.

| | |
|---|---|
| Still an issue? | Probably fixed. Upstream's Nightly Gate on 2026-10-19 (`eval-llvm (macos-15)`) does not list either range case among its 17 failures. Not rerun on the Pi 5. |
| Already upstream? | No issue or PR found (searched 2026-10-20). |
| Fixed on our reference branch? | Not ours to fix (upstream's LLVM backend). |
| Before filing | See "To check first" at the end. Don't file unless it still fails on clean upstream. |

---

**Title:** LLVM eval backend aborts on "inspect: inclusive numeric ranges all iterate" on aarch64

**What happens**

The eval test `inspect: inclusive numeric ranges all iterate` aborts in the LLVM backend on aarch64. The interpreter, the dev backend and the wasm backend all pass it.

```
FAIL  inspect: inclusive numeric ranges all iterate
      expected:       (6, 0, 6, 0, 6, 0, 6, 0, 6, 0, 6.0)
      interpreter:    PASS
      dev:            PASS
      wasm:           PASS
      llvm:           FAIL 'signal: 6'
```

**Where it was seen**

- CI, `eval-llvm (macos-15)` (aarch64). This case and `inspect: exclusive numeric ranges all iterate` both aborted with `signal: 6`.
- CI, `eval-llvm (ubuntu-24.04)` (x86_64). The inclusive case aborted too, along with the failures of #11909 in the same run.
- A Raspberry Pi 5 (aarch64 Linux), with a Debug eval runner built for `aarch64-linux-musl` at `00cab95af8`. The inclusive case aborted and the exclusive case passed.

**Where** (upstream `main` at `5fc587cf51`)

- The test: `src/eval/test/eval_tests.zig:6942` ("inclusive"). The "exclusive" one is at line 6962.
- Where it aborted on 2026-10-01 (Debug, aarch64): `src/llvm_compile/compile.zig:483`, in `emitMergedBitcodeModulesToObjectFile`. On `5fc587cf51` that line is inside the loop that links bitcode modules (lines 480-485).

**Why it matters**

The compiler aborts instead of producing a program. Anyone using the LLVM backend on aarch64 with code like this would hit it. It also kept the macOS `eval-llvm` CI job failing.

**How to reproduce** (aarch64 Linux)

```sh
zig build build-test-eval-runner -Dtarget=aarch64-linux-musl
./zig-out/bin/eval-test-runner --llvm --filter "numeric ranges all iterate" --verbose
```

On CI: `zig build run-test-eval -- --llvm`.

**Stack trace (aarch64 Linux, Debug)**

```
thread 58070 panic: incorrect alignment
zig/lib/c/malloc.zig:91:47: in malloc
zig/lib/c/malloc.zig:116:24: in calloc
???: (LLVM frames without symbols)
src/llvm_compile/compile.zig:483:44: in emitMergedBitcodeModulesToObjectFile
src/llvm_compile/compile.zig:726:45: in compileBitcodeModulesToObject
src/eval/inspected_run.zig:655:72: in runLlvm
src/eval/inspected.zig:3923:42: in llvmEvaluatorInspectedStr
```

The LLVM step ran for about 12 seconds before aborting. The exclusive case next to it takes under a second.

**The test case**

```roc
{
    u8 = Iter.fold((1.U8..=3.U8).iter(), 0.U8, |acc, item| acc + item)
    i8 = Iter.fold(((-1.I8)..=1.I8).iter(), 0.I8, |acc, item| acc + item)
    u16 = Iter.fold((1.U16..=3.U16).iter(), 0.U16, |acc, item| acc + item)
    i16 = Iter.fold(((-1.I16)..=1.I16).iter(), 0.I16, |acc, item| acc + item)
    u32 = Iter.fold((1.U32..=3.U32).iter(), 0.U32, |acc, item| acc + item)
    i32 = Iter.fold(((-1.I32)..=1.I32).iter(), 0.I32, |acc, item| acc + item)
    u64 = Iter.fold((1.U64..=3.U64).iter(), 0.U64, |acc, item| acc + item)
    i64 = Iter.fold(((-1.I64)..=1.I64).iter(), 0.I64, |acc, item| acc + item)
    u128 = Iter.fold((1.U128..=3.U128).iter(), 0.U128, |acc, item| acc + item)
    i128 = Iter.fold(((-1.I128)..=1.I128).iter(), 0.I128, |acc, item| acc + item)
    dec = Iter.fold((1.0..=3.0).iter(), 0.0.Dec, |acc, item| acc + item)
    (u8, i8, u16, i16, u32, i32, u64, i64, u128, i128, dec)
}
```

The test was added in `641d298ae1` ("Integrate stored ranges with iteration").

**Environment**

- OS: Pop!_OS 24.04 LTS, x86_64
- Roc compiler version `release-fast-a932c654`
- The aarch64 run: Raspberry Pi 5, Debian GNU/Linux 13 (trixie), aarch64. The compiler was cross-built on the machine above at upstream `00cab95af8`.

---

## To check first

- The Pi 5 run used upstream `00cab95af8` plus one local patch. The patch adds a hash-writing mode to the eval runner and doesn't touch the LLVM code. Rerun on a clean checkout of current `main`, without the patch.
- Check whether it still fails on current `main`. It was last seen on 2026-10-01, and upstream's 2026-10-19 nightly no longer shows it.
- The macOS and Ubuntu failures were on our fork's branch, which includes the arm32 changes. Only the Pi 5 run ties it to upstream. The macOS abort message itself was not captured, only `signal: 6`.
- Find which of the eleven lines triggers it by cutting the test down to one line.
