# Draft: Dev backend: `list_get_unsafe` silently truncates an i128/Dec index

> **Upstream or ours:** Upstream. The defect is in upstream's code and does not depend on our arm32 work.

> **Relevance to our arm32 work:** It does not affect arm32 in particular. Found while reading the driver for word-size assumptions; the reference leaves it as it is.

Not filed. For roc-lang/roc.

| | |
|---|---|
| Still an issue? | Yes, by code reading: `src/backend/dev/LirCodeGen.zig` still has "Dec/i128 index - just load the low 64 bits as U64". |
| Already upstream? | None found (searched issues and PRs, 2026-10-02). |
| Fix on our reference branch | Not fixed by us. |
| Before filing | Nothing. |

Checked 2026-10-02 against upstream `main` at `d16a6598e4`.

---

**Title:** Dev backend: `list_get_unsafe` silently truncates an i128/Dec index

**What happens**

When the index operand of `list_get_unsafe` arrives as an i128 or Dec value, the driver loads its low 64 bits and carries on. An index of that type is a bug in an earlier stage; the backend recovers from it silently instead of reporting it. AGENTS.md forbids best-effort recovery here.

**Where** (upstream `main` at `5fc587cf51`)

- `src/backend/dev/LirCodeGen.zig:2228-2231`, in `generateLowLevel` (line 1850), the `list_get_unsafe` index: `.stack_i128` loads the low 64 bits ("Dec/i128 index - just load the low 64 bits as U64").
- `LirCodeGen.zig:2232-2236`: `.immediate_i128` is truncated to 64 bits the same way.

**Why it matters**

An index of that type means an earlier stage produced wrong LIR. Truncating it and continuing hides that bug and can read the wrong element, where failing loudly would point straight at the producer.

**How to reproduce**

No program is known that produces such an index, so this is seen by reading the code:

```sh
grep -n -B6 -A8 'just load the low' src/backend/dev/LirCodeGen.zig
```

**Environment**

- OS: Pop!_OS 24.04 LTS, x86_64
- Roc compiler version `release-fast-a932c654`
