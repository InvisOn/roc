# Draft: The glibc stub emits `ret` for architectures where it is not an instruction

> **Upstream or ours:** Upstream. Unreached there today: the affected architectures do not use the stub. Our arm32 work would have reached it for `.arm`.

> **Relevance to our arm32 work:** `arm32linux` uses the glibc stub, and `ret` is not an A32 instruction. The reference gives arm its own stub body.

Not filed. For roc-lang/roc.

| | |
|---|---|
| Still an issue? | Yes, by code reading: `src/build/glibc_stub.zig` emits `ret` for `.aarch64_be, .arm, .wasm32, .other`. |
| Already upstream? | None found (searched issues and PRs, 2026-10-02). |
| Fix on our reference branch | Our reference gives arm its own stub body. |
| Before filing | Nothing. |

Checked 2026-10-02 against upstream `main` at `d16a6598e4`.

---

**Title:** The glibc stub emits `ret` for architectures where it is not an instruction

**What happens**

The generated glibc stub writes `ret` as the body of every stub function for `.aarch64_be`, `.arm`, `.wasm32` and `.other`. `ret` is not an A32 instruction (it would be `bx lr`) and means nothing for wasm32. Unreached today because those targets do not use the stub, but it would assemble wrongly or not at all if they did.

**Where** (upstream `main` at `5fc587cf51`)

- `src/build/glibc_stub.zig:24`, `:93` and `:100`, in `generateComprehensiveStub` (line 7): `.aarch64_be, .arm, .wasm32, .other => "    ret\n\n"`.
- `src/build/glibc_stub.zig:14`: the same group is given a 4-byte size.

**Why it matters**

Nobody upstream is affected: those architectures do not use the stub. It mattered for arm32, which does, and it would produce a wrong or unassemblable stub for any of the others the moment they used it.

**How to reproduce**

Unreached today, so this is seen by reading the code:

```sh
grep -n 'ret' src/build/glibc_stub.zig
```

It shows `ret` written for `.aarch64_be, .arm, .wasm32, .other`.

**Environment**

- OS: Pop!_OS 24.04 LTS, x86_64
- Roc compiler version `release-fast-a932c654`
