# Draft: upstream issue (not filed)

> **Upstream or ours:** Upstream, as far as we can tell: reproduced with a compiler built from upstream's code plus one unrelated local patch. The CI sightings are from our fork's branch. To be confirmed on clean upstream.

> **Relevance to our arm32 work:** It fails `eval-llvm (macos-15)` in our CI. arm32 does not use the LLVM backend, so it is unrelated to our code.

Personal note; not committed. For roc-lang/roc. Before filing, Claude
rechecks it on a clean checkout of current upstream `main` (see "To verify
first").

---

**Title:** LLVM eval backend aborts on "inspect: inclusive numeric ranges all iterate" on aarch64

**What happens**

The eval test `inspect: inclusive numeric ranges all iterate`
(`src/eval/test/eval_tests.zig`) aborts in the LLVM backend on aarch64. The
interpreter, the dev backend and the wasm backend pass the same case.

```
FAIL  inspect: inclusive numeric ranges all iterate
      expected:       (6, 0, 6, 0, 6, 0, 6, 0, 6, 0, 6.0)
      interpreter:    PASS
      dev:            PASS
      wasm:           PASS
      llvm:           FAIL 'signal: 6'
```

**Where seen**

- CI, `eval-llvm (macos-15)` (aarch64): this case and `inspect: exclusive
  numeric ranges all iterate` both abort with `signal: 6`.
- CI, `eval-llvm (ubuntu-24.04)` (x86_64): the inclusive case aborts too
  (among the failures of #11909 in the same run).
- Locally on a Raspberry Pi 5 (aarch64 Linux), Debug eval runner built for
  `aarch64-linux-musl` at `00cab95af8`: the inclusive case aborts; the
  exclusive case passes.

**Why it matters**

The compiler aborts instead of producing a program. Anyone using the LLVM backend on aarch64 with code like this would hit it, and the CI job that should catch it (`eval-llvm` on macOS) is failing because of it.

**How to reproduce** (aarch64 Linux)

```sh
zig build build-test-eval-runner -Dtarget=aarch64-linux-musl
./zig-out/bin/eval-test-runner --llvm --filter "numeric ranges all iterate" --verbose
```

On CI: `zig build run-test-eval -- --llvm`.

**Stack (aarch64 Linux, Debug)**

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

The LLVM step ran for about 12 seconds before aborting; the exclusive case
next to it takes under 1 second.

**The case**

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

The case was added by `641d298ae1` ("Integrate stored ranges with
iteration").

**Environment**

- OS: Pop!_OS 24.04 LTS, x86_64
- Roc compiler version `release-fast-a932c654`
- The aarch64 run: Raspberry Pi 5, Debian GNU/Linux 13 (trixie), aarch64; compiler cross-built on the machine above at upstream `00cab95af8`.

---

## To verify first (Claude, in the compute window)

- The Pi 5 run used upstream `00cab95af8` with one local patch applied (it
  adds a hash-writing mode to the eval runner and does not touch the LLVM
  path). Rerun on a clean checkout of current `main`, with no patch.
- Is it still present on current `main`? Last seen 2026-10-01.
- The macOS and Ubuntu observations are from CI on our fork's branch, which
  includes the arm32 changes; the Pi 5 run is what ties it to upstream. The
  macOS abort message itself was not captured (only `signal: 6`).
- Which of the eleven lines triggers it: cut the case down to one line.
- No existing upstream issue was found on 2026-10-02 (searched the test
  name, "incorrect alignment", the function name).
