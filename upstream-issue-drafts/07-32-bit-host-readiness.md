# Draft: The dev backend sizes target data with the compiler's own word size

> **Upstream or ours:** Upstream's code, but nothing goes wrong today. Upstream's dev backend only builds for 64-bit targets on 64-bit machines, where the two word sizes are the same.

> **Relevance to our arm32 work:** A 64-bit machine compiling for arm32 is exactly the case where the two word sizes differ. Our reference branch fixes these places.

Not filed. For roc-lang/roc.

| | |
|---|---|
| Still an issue? | Yes (2026-10-24, upstream `main` at `9b119d59e4`, by reading the code). It can't be seen on upstream's supported targets. Upstream's 32-bit compile fixes (`03f133636a`) do not touch these places. |
| Already upstream? | No issue or PR found (searched 2026-10-20). #9436 (closed) was the same mistake in the LIR interpreter. |
| Fixed on our reference branch? | Yes, in `f4af9e372d`, `d69fb5eb7f` and `1344ce3159` (the wasm part). |
| Before filing | Decide whether it is worth filing, since nothing upstream fails. If so, file it as a code-health note, not a bug. |

---

**Title:** The dev backend sizes target data with the compiler's own word size

**What happens**

`LirCodeGen` writes code that works with the *target* program's memory. In a few places it takes sizes and offsets from the machine the compiler runs on instead:

- The Debug check of a string's allocation tests its alignment against `@alignOf(usize) - 1`.
- The erased-call descriptor array is sized and indexed with `@sizeOf(usize)`.
- The erased-callable heap cell stores its drop pointer at offset `@sizeOf(usize)`.
- Erased-callable payloads are laid out with `@sizeOf` and `@offsetOf` of the builtins' structs, as compiled for the compiler's machine.

Today the compiler's machine and the target always have the same word size, so the generated code is correct. If they differed, the compiler would write fields where the target's runtime does not look for them.

A separate, related problem: `eval.backendAvailable(.wasm)` returns `true` on every machine. The wasm eval backend reserves a module's whole memory up front, which is 4 GiB for wasm32. A 32-bit process can't do that. On a 32-bit machine the wasm eval tests therefore fail, when they should be reported as unavailable.

**Where** (upstream `main` at `9b119d59e4`)

- Debug string check: `src/backend/dev/LirCodeGen.zig:8406` and `8419` (`@alignOf(usize) - 1`), in `emitDebugAssertValidStrLocal` (line 8337).
- Erased-call descriptor array: `LirCodeGen.zig:14288` and `14295` (`@sizeOf(usize)`), in `generateErasedCall` (line 14259).
- Erased-callable drop pointer: `LirCodeGen.zig:14746` and `14771` (offset `@sizeOf(usize)`, stored with an 8-byte `.w64` store), in `generatePackedErasedFn` (line 14545).
- Erased-callable payload layout: `LirCodeGen.zig:14595`, `14605`, `14613`, `14755`, `14765` and `14806` (`@sizeOf` and `@offsetOf` of the `builtins.erased_callable` structs). The capture prefix size now arrives as `erased_capture_prefix`, but the Debug check at line 1341 still compares it with the compiler machine's `hot_reload_capture_prefix_size`.
- wasm eval availability: `src/eval/mod.zig:18` (`.interpreter, .wasm => true`), in `backendAvailable` (line 15).

**Why it matters**

Nothing breaks upstream today. These sizes are right only because the two machines happen to match. The day the dev backend gains a target with a different word size, each one becomes a silent miscompile. Fixing them changes no 64-bit output.

**How to reproduce**

It can't be seen on upstream's supported targets. It shows up when reading the code:

```sh
grep -n '@sizeOf(usize)\|@alignOf(usize)' src/backend/dev/LirCodeGen.zig
grep -n '@sizeOf(builtins.erased_callable\|@offsetOf(builtins.erased_callable' src/backend/dev/LirCodeGen.zig
grep -n -A8 'fn backendAvailable' src/eval/mod.zig
```

In the first command's output, the affected lines are the ones listed under "Where". The matches near the end of the file are helpers for the compiler's own memory and are correct.

**Environment**

- OS: Pop!_OS 24.04 LTS, x86_64
- Roc compiler version `release-fast-a932c654`
