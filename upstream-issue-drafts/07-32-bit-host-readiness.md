# Draft: The dev backend sizes target data with the compiler host's word

> **Upstream or ours:** Upstream code, but it has no effect while the compiler's host and the target have the same word size. Upstream's dev backend only targets 64-bit machines from 64-bit hosts, so nothing upstream is wrong today.

> **Relevance to our arm32 work:** A 64-bit host compiling for arm32 is exactly the case where host and target words differ. The reference fixes these places.

Not filed. For roc-lang/roc.

| | |
|---|---|
| Still an issue? | Yes, by reading upstream `main` at `d16a6598e4` (2026-10-02). It cannot be observed on upstream's supported targets. |
| Already upstream? | None found. (Two related compile breaks on 32-bit hosts were fixed upstream by `516295113d` and are not part of this draft.) |
| Fix on our reference branch | `f4af9e372d`, `d69fb5eb7f`; `1344ce3159` (wasm eval). |
| Before filing | Decide whether it is worth filing at all: it cannot be observed on upstream. If so, file it as a code-health note, not a bug. |

---

**Title:** The dev backend sizes target data with the compiler host's word

**What happens**

`LirCodeGen` describes memory of the *target* program, but in some places it takes sizes and offsets from the machine the compiler itself runs on:

- the Debug check of a string's allocation tests alignment against `@alignOf(usize) - 1`;
- the erased-call descriptor array is sized and indexed by `@sizeOf(usize)`;
- the erased-callable heap cell stores its drop pointer at offset `@sizeOf(usize)`;
- erased-callable payloads are laid out with `@sizeOf` and `@offsetOf` of the builtins' structs as compiled for the host.

Host and target word sizes agree for every combination upstream supports, so the generated code is correct today. With a host and target of different word sizes, the compiler would write fields where the runtime, compiled for the target, does not look.

Separately, `eval.backendAvailable(.wasm)` returns `true` on every host. The wasm eval backend reserves a module's full linear memory (4 GiB for wasm32), which a 32-bit process cannot do, so on a 32-bit host the wasm eval tests fail instead of being reported as unavailable.

**Why it matters**

Nothing breaks upstream today. It matters as a habit worth removing: sizes of target data taken from the host are right only by coincidence, and they become silent miscompiles the moment a target with a different word size is added to the dev backend. The fixes change no 64-bit output.

**How to reproduce**

It cannot be observed on upstream's supported targets. By reading the code:

```sh
grep -n '@sizeOf(usize)\|@alignOf(usize)' src/backend/dev/LirCodeGen.zig
grep -n '@sizeOf(builtins.erased_callable\|@offsetOf(builtins.erased_callable' src/backend/dev/LirCodeGen.zig
grep -n -A8 'fn backendAvailable' src/eval/mod.zig
```

In the first command's output, the lines in the string validity check, the descriptor array and the heap-cell stores are the affected ones; the ones near the end of the file are host-memory helpers and are correct.

**Environment**

- OS: Pop!_OS 24.04 LTS, x86_64
- Roc compiler version `release-fast-a932c654`
