# Draft: ARC dismantling panics with "owned-only field binding had conflicting parameter roots"

> **Upstream or ours:** Very likely upstream, not yet confirmed there. The panic is in `src/lir/arc_dismantle.zig`, which our branch does not change, and it fires during compile-time finalization, before any backend runs. To confirm: rerun the inputs on a clean upstream build of `repro-build`.

> **Relevance to our arm32 work:** Found by our fuzzing of the dev backend (the build fuzzer with the dev-backend compile added). It is not an arm32 problem: it fired for x64musl and arm64glibc. It matters to us only because it stops a fuzzed program before it reaches the dev backend, so it hides whatever the dev backend would do with that program.

**Files and where to find them** (local, not in upstream)

- The two crashing inputs and what the fuzzer printed for them: `/home/aj/repos/roc_32bit/.git/verify-tools/fuzz/run-20261004/crashes/`
  - `0001-crash-x64musl.in`, `0002-crash-arm64glibc.in`: raw bytes. The ticket below carries 0001 as base64, so it does not depend on this copy.
  - `0001-crash-x64musl.out`, `0002-crash-arm64glibc.out`: the generated Roc modules at the top, the panic and stack at the bottom.
  - `../summary.txt`: the whole run (10,674 inputs, per target).
- The script that made them: `/home/aj/repos/roc_32bit/.git/verify-tools/fuzz_random.sh <deadline HH:MM> <out dir>`. It feeds 100 to 4,099 random bytes at a time to `zig-out/bin/repro-build` and keeps every input that exits non-zero.

> **Status (2026-10-05):** Already reported upstream as #12042 (opened 2026-10-03, from upstream's own build fuzzer) and fixed by #12054 (merged in upstream `eb0118a071`; it changes the owned-only binding override in `arc_dismantle.zig`). Do not file. Rechecked 2026-10-06 on our branch at `405a2e9d0f` (has the fix): both inputs now compile through the dev backend, exit 0.

Not filed. For roc-lang/roc.

| | |
|---|---|
| Still an issue? | Yes on our reference branch (merged with upstream `c50792641a`), 2026-10-04. Not yet run on clean upstream. |
| Already upstream? | Yes: #12042, fixed by #12054 (upstream `eb0118a071`). |
| Fix on our reference branch | None (upstream code; not ours to fix). |
| Before filing | Confirm on clean upstream; search issues and PRs; shrink the generated program to a small Roc file. |

Found 2026-10-04 by random-input fuzzing: 2 of 10,674 inputs, both this panic.

---

**Title:** ARC dismantling panics: "ARC owned-only field binding had conflicting parameter roots"

**What happens**

Building a program made by the build fuzzer panics with `reached unreachable code` in ARC insertion:

```
src/lir/arc_dismantle.zig:356   dismantleInvariant  (unreachable)
src/lir/arc_dismantle.zig:2730  compute  "ARC owned-only field binding had conflicting parameter roots"
src/lir/arc.zig:554             insert
src/lir/checked_pipeline.zig:1724  finishLoweredOutput
src/lir/checked_pipeline.zig:1531  lowerFinalConsumerToLir
src/eval/compile_time_finalization.zig:691  finalizeProgram
src/compile/coordinator.zig:3059  evaluatePreparedModules
```

The program type-checks; the panic is in lowering, so the compiler crashes on a valid program instead of building it or reporting an error.

**Where**

`src/lir/arc_dismantle.zig`, `compute`, the invariant at line 2730.

**Why it matters**

It is a compiler crash on a well-typed program. Two of about 10,700 random programs hit it, so ordinary code may hit it too.

**How to reproduce**

The program comes from the build fuzzer. Its input is 3,620 bytes (sha256 `2a1a85bf...fd8ae73`), here as base64. In a roc-lang/roc checkout:

```sh
base64 -d > /tmp/arc-crash.in <<'EOF'
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
HnjLkhymqptJ0xnlDfIqBGPv5Ith9FZ/qQgGXx8=
EOF
zig build build-repro-build                                   # writes zig-out/bin/repro-build
./zig-out/bin/repro-build --verbose /tmp/arc-crash.in > /tmp/arc-crash.out 2>&1
grep -a -A3 'panic:' /tmp/arc-crash.out
```

`/tmp/arc-crash.out` starts with the Roc modules the fuzzer generated from the bytes (`T0.roc` and two more) and ends with the panic.

Before filing: run this on clean upstream, then cut the generated `T0.roc` down to a small program that `roc build` alone crashes on, and put that program here instead of the bytes.

**Environment**

- OS: Pop!_OS 24.04 LTS, x86_64
- Roc compiler version: to fill in after the upstream recheck
