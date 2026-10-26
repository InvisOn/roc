# Fold step 7: checks, rebase and ARM hardware

- **Status:** Accepted (2026-10-26)
- **Scope:** Step
- **Plan row:** 1 dispatch/isa
- **Branch:** `dispatch/isa`
- **Fork PR:** #9
- **Parent:** `dispatch-isa-rfc.md`
- **Base:** `629c3e0e2d` today; current `upstream/main` (`26436de489` on
  2026-10-26) if D1 is accepted
- **Head:** `0d8048aee4` (before this step)

## Abstract

This step proves the finished part 1 branch before its description is
rewritten and it goes up for review: it rebases onto current upstream,
reruns every check on the result (the full test set, minici, the relative
oracle and the reference check), and runs the instruction cache flush
(draft 03, from #8) on real ARM hardware, which no check has done yet. Test
binaries are built on this machine for the ARM devices and copied there,
since building on the devices is slow or impossible. It needs three
decisions: whether to rebase first (D1, yes), what runs on the aarch64
device (D2, the eval runner at head and at the base), and what runs on the
32-bit ARM device, where the flush cannot run yet (D3).

## Problem

`ExecutableMemory` writes generated code and then makes it executable.
x86_64 keeps its instruction cache coherent with data writes, so a missing
flush never shows there, and every check so far ran on x86_64. aarch64 and
32-bit ARM do not: a CPU may execute stale bytes from memory it just wrote.
#8 adds the flush (now `f3118ae736` on `dispatch/isa`), but nothing has run
it on ARM. HANDOFF item 7 asks for that run on the aarch64 device.

The branch also sits on `629c3e0e2d`, 28 commits behind upstream, one of
them in `LirCodeGen.zig`. #9 should be reviewed on the code it will merge
onto, so the checks belong after a rebase.

### Breakages you can run

Commit: `629c3e0e2d` (upstream, no flush). On the aarch64 device, the eval
runner built from upstream runs each eval case's generated code in-process.
Without the flush, a case can execute stale instruction bytes. The failure
is timing-dependent: a crash or a wrong result in some runs, none in others,
so it is not a reliable reproduction. D2 runs it anyway, next to the
branch's runner, as a comparison.

## What this enables

- **Follows directly:** step 8 (#9's description, closing #8 and #3) and
  step 9 (the second review), on a branch that is current and proven.
- **Follows directly:** the first run of the compiler's own code generation
  on ARM hardware from a part 1 branch; any aarch64-only failure shows up
  before review, not after.
- **Possible later, not planned:** the same build-here, run-there commands
  serve parts 6, 10 and 11 on the 32-bit ARM device.

## Background

- **The devices:** an aarch64 device (4 cores, 8 GB, 51 GB disk free) and
  a 32-bit ARM device (armv7l, 4 cores, 920 MB, 24 GB disk free), such as
  Raspberry Pis (which we do). Both are reachable from this
  machine over SSH without a password. Neither has a Zig toolchain on its
  `PATH`, and the 32-bit one is too small to build the compiler.
- **The eval runner** (`build-test-eval-runner`, `zig-out/bin/eval-test-runner`)
  runs the eval corpus on every enabled backend, each case in a forked
  child. Its test cases are compiled in, and it needs no other files:
  checked on 2026-10-26 by running this machine's runner from an empty
  folder (166 cases on the interpreter, dev and wasm backends, 161 passed,
  5 skipped, nothing written to the folder). On a host with a native dev
  backend it runs generated code through `ExecutableMemory`
  (`inspected_run.zig`): the path the flush is on. It links LLVM
  statically. The aarch64 cross build works: a 349 MB static Debug binary
  with symbols.
- **The 32-bit ARM host:** the dev backend has no 32-bit ARM code generator
  until part 6, so the flush never runs there in part 1. What part 1 adds
  for 32-bit hosts is step 5's code: the wasm backend reported unavailable,
  and the wasm32 CLI tests skipped. Those branches have only been compiled
  (an x86 32-bit check on step 5), never run.
- **The x86 32-bit check (part 1 RFC, risk R4, on step 5's head):**
  `run-test-zig-module-eval` for
  `x86-linux-musl` gave 61 passed, 1 skipped and 9 crashed, the same at the
  branch and its base; the crashes are older 32-bit host problems.

## Discussion

- **Acceptable upstream:** the rebase resolves toward upstream's code, and
  each rebased commit still builds and passes alone.
- **No machine details in the notes:** the devices are named by kind, never
  by address or user.
- **Evidence over hope:** a flush that is only reasoned about is not
  checked; it has to run on a CPU that needs it.
- **Cost:** the heavy checks (oracle, minici, cross builds) run one at a
  time under the memory limit.

### Alternatives considered

- **Build on the aarch64 device.** Rejected because a full compiler build
  there is far slower than building here, and the 32-bit device cannot
  build it at all.
- **Run under qemu here instead of on hardware.** Rejected because qemu does
  not model the instruction cache, so it cannot show a missing flush.

## Decisions

### D1. Rebase before the checks

- **Status:** Accepted (2026-10-26)
- **Context:** upstream moved 28 commits past `629c3e0e2d`; one touches
  `LirCodeGen.zig`. HANDOFF item 1 says to rebase again before step 7's
  checks if upstream moved.
- **Alternatives:**
  1. Rebase onto current `upstream/main`, then run every check on the
     result. Implications: conflicts resolved now, on the code #9 merges
     onto; the oracle reruns (rerere holds A0's resolutions).
  2. Check on `629c3e0e2d` and rebase later. Implications: the checks
     prove a base #9 will not merge onto; they would rerun after the rebase
     anyway.
- **Recommendation:** Alternative 1.
- **Consequences:** every hash on `dispatch/isa` changes again; the step 6
  write-up keeps the hashes it was written with.

### D2. What runs on the aarch64 device

- **Status:** Accepted (2026-10-26)
- **Context:** the flush is the reason for the run; the eval corpus
  exercises it on every case that runs generated code.
- **Alternatives:**
  1. The eval runner built from the rebased head only. Implications: shows
     the branch passes on aarch64; says nothing about whether the flush is
     what makes it pass.
  2. The eval runner from the head and from the rebased base (upstream,
     no flush), each run 5 times. Implications: one more cross build; the
     base may or may not fail (timing-dependent), so its result is a
     comparison, not a proof.
  3. Option 2 plus the backend module's unit-test binary. Implications: a
     cross build of the unit tests too. `ExecutableMemory.zig`'s test
     "execute aarch64 code" only runs on an aarch64 CPU, so it has never
     run. `build-test-zig` compiles the unit-test binaries without
     installing them, so the binary comes from Zig's build cache; the exact
     way is confirmed in sub-step 4.
- **Recommendation:** Alternative 3.
- **Consequences:** the pass rule: every one of the 5 head runs passes,
  with no failure or crash, and the same pass and skip counts as this
  machine's `run-test-eval` at the head except for cases that skip on
  aarch64. A base failure is recorded as supporting evidence; its absence
  proves nothing.

### D3. What runs on the 32-bit ARM device

- **Status:** Accepted (2026-10-26)
- **Context:** the flush cannot run on 32-bit ARM until part 6. Step 5
  added two kinds of 32-bit host branch, never run: the eval runner
  reporting the wasm backend unavailable (`backendAvailable`), and the CLI
  tests that skip wasm32 instantiation. Only the first can run here; the
  second needs `roc` and the CLI test runner on the device, which stays for
  part 11.
- **Alternatives:**
  1. Nothing now; part 11 (arm32 as a host) runs them. Implications: no
     cost; the step 5 branches stay compiled but unrun until then.
  2. Cross-build the eval runner for 32-bit ARM, at the head and the base,
     and run both (interpreter only, no dev backend). Implications: two
     more cross builds; it may not build at all (LLVM for a 32-bit host);
     older 32-bit host failures appear at both commits, so only a
     difference counts.
- **Recommendation:** Alternative 2, and if the 32-bit ARM build is not
  supported, record why and fall back to alternative 1.
- **Consequences:** step 5's "never run" note is closed for the eval
  runner, or given a concrete reason; the CLI test skips stay for part 11
  either way.

## Risks

### R1. The rebase conflicts in `LirCodeGen.zig`

- **Likelihood:** Medium
- **Impact:** Low
- **How we'd notice:** the rebase stops.
- **Mitigation:** resolve toward upstream; the full set and the oracle run
  after.
- **If it happens:** each resolution is described in the step write-up.

### R2. A failure only on aarch64

- **Likelihood:** Low
- **Impact:** High
- **How we'd notice:** the eval runner or unit tests fail on the device.
- **Mitigation:** run the base too, so a failure can be placed: in the
  branch, or already upstream.
- **If it happens:** stop, report, and fix in the commit it belongs to.

### R3. The 32-bit device runs out of memory

- **Likelihood:** Medium
- **Impact:** Low
- **How we'd notice:** the runner is killed.
- **Mitigation:** one thread (`--threads 1`).
- **If it happens:** record it under D3 and fall back to part 11.

## Testing

On this machine, from `.workspaces/pr-isa`, after the rebase (one heavy
job at a time, each under the memory limit):

```
zig build run-check-zig-format run-check-unreachable-rationale run-test-zig-module-builtins run-test-zig-module-backend roc run-test-zig-module-check run-test-zig-module-compile run-test-zig-module-eval run-test-zig-lir-inline run-test-zig-snapshot-tool run-check-snapshots
```
```
zig build minici
```

From the main checkout, the relative oracle (base against rebased head):

```
python3 .workspaces/notes/incremental-plan/tools/relative_oracle.py --upstream <base> --merged <head> --apply-a0-to-merged
```

The reference check: each line `dispatch/isa` changes, compared with the
reference's final state (`e0fa273ebf`); every difference explained.

The aarch64 runners. The base gets its own worktree, removed afterwards.
From the main checkout:

```
git worktree add --detach .workspaces/step7-base <rebased base>
```

From `.workspaces/pr-isa`, then from `.workspaces/step7-base`:

```
zig build build-test-eval-runner -Dtarget=aarch64-linux-musl --prefix ../step7-out/head
```
```
zig build build-test-eval-runner -Dtarget=aarch64-linux-musl --prefix ../step7-out/base
```

On the device, through the `pi5` SSH command from this machine, in a new
folder `~/step7` (the Roc checkouts already there stay untouched), from
`.workspaces`:

```
pi5 mkdir -p step7/head step7/base
```
```
scp step7-out/head/bin/eval-test-runner <aarch64 device>:step7/head/
```
```
scp step7-out/base/bin/eval-test-runner <aarch64 device>:step7/base/
```
```
pi5 'cd step7/head && ./eval-test-runner --threads 4'
```
```
pi5 'cd step7/base && ./eval-test-runner --threads 4'
```

Each run 5 times; the last line of each is the summary. Expected: every
head run ends with `0 failed, 0 crashed`. Then the backend unit tests the
same way, and afterwards:

```
pi5 rm -r step7
```

The 32-bit ARM commands are the same with `-Dtarget=arm-linux-musleabihf`,
`pi3`, `--threads 1`, once its trial build shows the runner builds for it.

## Recommendation

D1 alternative 1, D2 alternative 3, D3 alternative 2 (falling back to 1).
Sub-steps, each reported before the next:

1. Rebase `dispatch/isa` onto current `upstream/main`.
2. The full set, then minici, then the oracle, on the rebased head.
3. The reference check.
4. Cross-build the aarch64 runners (head and base) and the backend unit
   tests; run them on the aarch64 device (4 cores, 8 GB) through the `pi5`
   SSH command from this machine, so no one has to relay commands.
5. Cross-build the 32-bit ARM runners (head and base); run them on the
   32-bit ARM device (armv7l, 4 cores, 920 MB) through `pi3`, or record why
   not.
6. The step write-up (`step-7-checks.md`) in the next `notes` commit.
