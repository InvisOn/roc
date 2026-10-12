# Draft: Relocation patching guesses the instruction set from the code bytes

> **Upstream or ours:** Upstream. The defect is in upstream's code and does not depend on our arm32 work.

> **Relevance to our arm32 work:** A third instruction set cannot be told apart by a byte test, so arm32 needed the caller to pass the ISA. The reference does that (mixed into an arm32 commit).

Not filed. For roc-lang/roc.

| | |
|---|---|
| Still an issue? | Yes, by code reading: `src/backend/dev/Relocation.zig` still tests `prev == 0xE8`. |
| Already upstream? | None found (searched issues and PRs, 2026-10-02). |
| Fix on our reference branch | `e865de0a8a` (mixed with arm32's relocation rules; would need splitting). |
| Before filing | Nothing; code reading is enough. |

Checked 2026-10-02 against upstream `main` at `d16a6598e4`.

---

**Title:** Relocation patching guesses the instruction set from the code bytes

**What happens**

When applying a relocation, `Relocation.zig` decides between x86_64 and aarch64 by looking at the byte before the operand: `0xE8` means an x86_64 call. If that byte is not `0xE8`, it reads the four bytes as an aarch64 instruction and checks for a `bl`. That is a heuristic: the function is never told the target, and it is correct only as long as no other instruction set puts `0xE8` in that position. On 32-bit ARM it does: `pop {...}` encodes as `0xE8BD....`, so a `pop` followed by a call would be patched as an x86_64 call. AGENTS.md forbids heuristics outside parsing and error reporting.

**Why it matters**

For x86_64 and aarch64 the guess happens to work today. It stops working with any further instruction set: a wrong guess patches the call with another architecture's encoding and the generated code is silently corrupt. The caller already knows the target, so the guess is unnecessary, and AGENTS.md forbids heuristics in this stage.

**How to reproduce**

By reading the code:

```sh
grep -n -i '0xe8' src/backend/dev/Relocation.zig
```

The `prev == 0xE8` test decides between the x86_64 and aarch64 patching paths.

**Environment**

- OS: Pop!_OS 24.04 LTS, x86_64
- Roc compiler version `release-fast-a932c654`
