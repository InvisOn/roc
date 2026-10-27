# Fold step 7 of 9: checks, rebase and ARM hardware

The step's checks are complete; only sub-step 7 (the force-push and closing
#8 and #3) remains. Planning doc: `step-7-checks-plan.md` (decisions D1 to
D3 accepted 2026-10-26).

Branch `dispatch/isa`, 15 commits, rebased onto upstream `26436de489`;
head `15e8146634` after the reference check's `exit_group` change.

| Sub-step | State |
|---|---|
| 1. Rebase | done |
| 2. Full set, minici, oracle | done |
| 3. Reference check | done; three findings, all decided |
| 4. aarch64 device | done: 10 runs and the unit tests passed (with a separate 16 KiB-page fix) |
| 5. 32-bit ARM device | done: every difference from the base is step 5's; ReleaseSafe runners |
| 6. This write-up | in progress |
| 7. Force-push #9; close #8 and #3 | pending, after the checks |

## 1. Rebase

`dispatch/isa` moved from `629c3e0e2d` to `26436de489` (28 upstream
commits). Head `0d8048aee4` became `8e9e512e0f`; the old head is kept as
`backup/dispatch-isa-pre-rebase2-2026-10-26`. All 15 commits are re-signed
and keep their author dates. Three commits changed; the other twelve
applied unchanged.

Upstream `478cff9095` rewrote the erased-callable code step 5 changes, as
the sync machine's HANDOFF note predicted:

- **Step 5, "Lay out erased-callable payloads by the target's word"** (3
  conflicts). Upstream now writes the closure metadata only when the
  program uses the Boxy runtime. Resolved: upstream's Boxy check, with
  step 5's `erased_layout` values inside.
- **Step 5, "Size new erased-callable payloads by the target's layout".**
  Upstream picks one of two payload sizes, with and without Boxy; the
  second used the host's `capture_offset`. Resolved: both use the target's
  `erased_layout`.
- **Step 6 commit 3, "Compute low-level pointers at the target's word
  width".** The same payload line. Resolved: upstream's two-branch line,
  with the slot sized `target_ptr_size`.

The 28 commits add 7 `.w64` lines to `LirCodeGen.zig`: the 3 in the new
direct call (below) and 4 in the rewritten closure-metadata code, the same
metadata stores step 5 left at `.w64`. None touches RocStr or RocList. Their
new dev backend files (`NativeProcDomain.zig`, `NativeProcCompiler.zig`)
make no assumption about the target's word.

### Upstream's new direct call of erased callables

`478cff9095` also added a direct call for programs without the Boxy
runtime. It reloads the saved closure pointer, loads the function pointer
from the closure's first word and saves it in an 8-byte slot, all at
`.w64`. The same function's older code saves and reloads that closure
pointer in four more `.w64` places.

Three options were weighed: fix the three new lines (cheap, but leaves a
half-converted function), fix the whole function in step 6 commit 3
(complete, but takes erased-call sites into part 1 against the agreed
split), or leave all of it for part 3. Chosen: **leave it for part 3**. It
follows the split (erased-call sites are the reference's "Classify" work,
`c4156ac121`), keeps the reviewed commits as they are, and nothing breaks
before part 6 lifts the 8-byte assert. The function is on the "left for
part 3" list in `step-6-word-size.md`, and HANDOFF records why the sync
machine's "must" was not followed in part 1.

### The reference check's change

After the reference check (section 3), the glibc stub commit
(`e83ca1565b`, now `ba3824ab2f`) exits `abort` with `exit_group` (248) on
32-bit ARM instead of `exit` (1). Folded into that commit with a signed
fixup and an autosquash rebase; the twelve commits after it got new hashes
with unchanged content. Head `8e9e512e0f` became `15e8146634`; the old head
is kept as `backup/dispatch-isa-pre-exit-group-2026-10-26`. All 15 commits
are signed and keep their author dates, and the only content change
against the old head is that one line.

## 2. Checks on the rebased branch

On this machine (x86_64, `-j14`, under the memory limit), from
`.workspaces/pr-isa`.

- **Full set** (format, unreachable rationale, builtins, backend, `roc`,
  check, compile, eval, LIR inline, snapshot tool, snapshots): passed, in
  8.3 minutes. The compile tests print "Roc cache writes are failing" and
  Zig shows the command that printed it; that is upstream's
  `cache_test.zig` checking the warning on purpose. Rerun alone: 38/38
  steps, 986/986 tests passed.
- **minici:** first run stopped at phase 17 of 98, `run-check-glue-abi`,
  because this machine's Rust lacked the `wasm32-unknown-unknown` and
  `x86_64-unknown-linux-musl` targets (upstream's CI installs both). The
  owner installed both on 2026-10-26; the phase then passed (211/211
  steps). HANDOFF's "How to check a PR" now lists both targets. Second run:
  98 of 98 phases passed (0 failed, 0 crashed, 0 skipped), in 80
  minutes; the strategy differential alone took 14.
- **Relative oracle** (`26436de489` against `8e9e512e0f`): PASS. 2373 eval
  cases and 16 `dev_object` snapshots compared, 0 differ, none on one side
  only. A0's patch applied to both sides with the conflicts rerere had
  recorded in step 6. 51 minutes; each side spent about 10 minutes
  building and 16 hashing, most of the hashing time on one slow shard
  (see "Other findings"). Rerun with the new
  oracle script and A0 patch (`--fresh`, see "Other findings"): PASS
  again, the same counts, in 24.9 minutes; the builds ran side by side
  (9.3 and 9.6 minutes), then each side's hashing (7.8 and 7.7).

**On `15e8146634`, after the `exit_group` change:**

- **Full set:** passed, in 8.2 minutes (the same expected cache warning).
- **Relative oracle:** PASS, the same counts, in 24.8 minutes; peak 14.3 GB
  (systemd's count, file cache included), 183 CPU-minutes, swap up to
  1.2 GB. Upstream's side was rebuilt, not reused: its key includes the
  oracle script, which had changed since the last saved result.
- **minici:** split into its six Linux shards across two machines (upstream's
  "MiniCI shards cover" tests prove the six together are one full run).
  All passed, 0 failed and 0 crashed:

  | Shard | Machine | Minutes | Peak GB |
  |---|---|---|---|
  | source | this one | 0.8 | 0.3 |
  | linux-core | this one | 49.2 | 19.4 |
  | linux-simd | this one | 14.7 | 2.5 |
  | linux-harness | this one | 12.9 | 3.7 |
  | linux-strategy | this one | 14.0 | 18.6 |
  | linux-eval | sync machine | 54.0 | 15.9 |

  The stub change rebuilt CI's binaries (`build-ci`) on both machines,
  about 30 minutes each. `linux-core` and `linux-strategy` came within
  about 1.5 GB of the 20 GB memory limit.

## 3. Reference check

Every line `dispatch/isa` adds, compared with the reference's final state
(`e0fa273ebf`): first by file, then, for `LirCodeGen.zig`, by function
after translating names the two sides spell differently (upstream's
`target_ptr_size` for the reference's `word_size`, upstream's `self.emit*`
helpers for the reference's `self.codegen.emit*`). Then the lines the
branch removes that the reference still has in the same function.

**The same as the reference:** `instruction_cache.zig` (the flush, line for
line), the flush call in `ExecutableMemory.zig`, the one-line `isa` imports
in the eval, CLI and compile files, the shift masks, the Dec conversions'
64-bit argument shifts, and every RocStr and RocList load and store at
`word` (the reference calls the same helper through `self.codegen`).

**Different on purpose:**

- **Upstream's names and newer code** (step 6's write-up): field offsets
  from upstream's `targetFieldOffset` instead of the reference's
  `wordOffset`, `target_ptr_size` instead of `word_size`, `word` as a
  `switch` on the word size, `intOverflowCheck` and `wordOfU128` at file
  level with tests, the merged unsigned-to-float conversion, and the loop
  syntax of upstream's newer Zig.
- **Two instruction sets, not three.** The branch's `Isa` has `x86_64` and
  `aarch64`; arm32 arrives in part 6. Its `binaryIs` is a compile error as
  soon as a third instruction set exists (the reference's errors only on
  arm32), and big-endian aarch64 is rejected instead of mapped to aarch64.
  The branch keeps upstream's two-way tests as `binaryIs` (223 sites); the
  reference turned most into `switch (isa)` with an arm32 case (45
  switches, 34 `binaryIs` left), which is part 6's work. Four tests the
  reference still writes as `toCpuArch() == .aarch64` (`boolRetReg`,
  `condCode`, `compileProcSpecsInOrder`, `deadTempChainFrameSize`) go
  through `isa` on the branch. `CallingConvention` and `FrameBuilder` keep
  their two-way tests too (the reference switches; part 7).
- **Fixes the reference does not have:** the abs64 relocation writes its
  eight bytes on any host (the reference writes four on a 32-bit host and
  added a separate `abs32` kind for arm32 instead); and a freestanding
  build keeps the wasm backend (the reference's `@sizeOf(usize) >= 8` turns
  off the only backend a 32-bit freestanding build has). Step 5's write-up
  explains the second.
- **New on the branch:** the RocStr and RocList `targetFieldOffset` tests
  (upstream added the function after the reference) and the CLI test
  skips for wasm32 on 32-bit hosts (step 5, "new").
- **Not converted yet:** the base has 803 `.w64` sites in `LirCodeGen.zig`,
  the branch 538, the reference 24. The rest are part 3's (and part 7's)
  "Classify" work, as agreed.

**Findings:**

1. **The glibc stub's `abort` on 32-bit ARM** exits through syscall 1,
   `exit`; the reference uses 248, `exit_group` (its comment:
   "exit_group(1): syscall 248 in the ARM EABI"). The branch matches the
   x86_64 and aarch64 stubs beside it, which also call `exit` (60 and
   93), and it is the commit open upstream as 12513. Step 3's write-up
   records syscall 1 but not that the reference differs. `exit_group` ends
   every thread, `exit` only the calling one. Upstream itself mixes them:
   the LLVM backend's `_start` calls `exit` on x86_64 and `exit_group` on
   aarch64, and the default Linux runtime calls `exit_group` everywhere.
   Decided 2026-10-26: `exit_group` (248) for 32-bit ARM, as the
   reference has it, to fold into the glibc stub commit; making the rest
   consistent is upstream issue draft 41.
2. **`generatePackedErasedFn` is still `.w64` throughout:** 16 pointer
   accesses (the procedure address, the drop functions, the reuse and heap
   pointers) that the reference moved to `word` in its "Classify" commits
   (`93c546d7b5`, `c4156ac121`). Part 3 by the agreed split, but step 6's
   "left for part 3" list does not name the function, and step 5's write-up
   says these store widths "change with the word-size steps". Decided
   2026-10-26: added to step 6's "left for part 3" list.
3. **For sub-step 5:** the reference has two commits that make
   deep-nesting eval cases shallower on 32-bit hosts (`f100fb4984`,
   `a46ddacb69`). Upstream has neither, so those cases may fail on the
   32-bit ARM device at both the branch and its base; only a difference
   between them counts.

## 4. aarch64 device

Passed. The Debug eval runners for aarch64, at the base and the head,
were cross-built on the sync machine (16.7 and 13.9 minutes) and copied
to the device; checksums matched on all three machines. Those runners,
without the fix below, gave only the first, crashing head run; the ten
runs used runners with the fix (14.1 and 14.0 minutes to build).

**An upstream bug on 16 KiB pages.** The device's default kernel uses 16 KiB
pages (`getconf PAGESIZE` = 16384). On it, every case that goes through
compile-time evaluation segfaulted in `StaticDataImage.place`, at an
address on a 4 KiB boundary but not a 16 KiB one. `HostSplice.link` puts
the static data after the code on a boundary of `std.heap.page_size_min`
(4 KiB), then makes the code executable; the kernel protects whole 16 KiB
pages, so the start of the static data turns read-only. Upstream code that
part 1 does not touch, so the base is affected the same way. Decided
2026-10-26 (option C of three, against changing the device's kernel or
comparing two crashing runs): a separate fix, branch `fix/runtime-page-size`
(`559316ddbb` then, now `b1df3f9f18` as fork PR #10; two lines: align to
`std.heap.pageSize()`), not part of #9;
upstream issue draft 42. The runs use runners with the fix: the base plus
the fix, and `dispatch/isa` plus the fix (throwaway branch
`step7/head-page-fix`, `1a7135504b`).

**Results** (4 threads, measured with `timings/measure.py`; the device has no
`/usr/bin/time`). Every run, at the head and at the base, gave the same
counts as the eval runner on this machine at the head (19.2 minutes on 14
threads): **2593 passed, 0 failed, 0 crashed, 47 skipped** of 2640. No case
skips only on aarch64.

| Run | Head + fix | Base + fix |
|---|---|---|
| 1 | 66.1 min | 67.0 min |
| 2 | 66.1 min | 67.0 min |
| 3 | 66.1 min | 67.0 min |
| 4 | 66.1 min | 67.0 min |
| 5 | 66.1 min | 67.0 min |

Each run used 2.6 cores on average and about 4.3 GB at its peak; the
device never had less than 3.1 GB free.

- **The flush passes on hardware that needs it.** The device's caches for
  instructions and data are separate, so the five head runs (13,200 case
  runs, whose dev-backend parts write, flush and run fresh code through
  `ExecutableMemory`) are the first evidence that #8's
  flush works where it matters. The plan's pass rule holds: every head run
  passed with this machine's counts.
- **The base, without the flush, did not fail either.** A missing flush
  fails only some of the time; five base runs passing here means the
  device did not show the problem in practice, which, as the plan said,
  proves nothing about whether the flush is needed (the architecture
  requires it).
- **The backend's unit tests** (cross-built for aarch64 at the head plus
  the fix; the binary came from Zig's cache, because `build-test-zig`
  does not install unit-test binaries and the run step skips binaries this
  machine cannot run): 517 passed, 0 failed, 4 skipped, in 6.6 seconds,
  including `dev.ExecutableMemory.test.execute aarch64 code`, which had
  never run on an aarch64 machine.
- The runs were alternated (head, head, head, base, head, base, head,
  base, base) and queued on the device, so they did not depend on this
  machine overnight.

## 5. 32-bit ARM device

Passed (only differences between head and base count, as planned).
**A Debug eval runner for 32-bit ARM does not link:** LLD stops
with "InputSection too large for range extension thunk", because the
Debug image's one code section is larger than an A32 branch (about
±32 MB) and its thunks can bridge. The reference recorded the same and
built ReleaseFast or ReleaseSafe runners. Decided 2026-10-26: ReleaseSafe
(safety checks stay on), without the 16 KiB-page fix (the device uses
4 KiB pages). HANDOFF has a reminder to investigate the Debug link.

The reference made two deep-nesting eval cases shallower on 32-bit hosts
(`a46ddacb69`, `f100fb4984`). Not ported (decided 2026-10-26): measured at
full depth on x86_64 today they peak at 1.56 GB and 0.68 GB, not the
reference's 4.6 GB, so a 32-bit process should fit them; what may still
fail is the device's 920 MB of memory, which is not a reason to change
the code. Failures at both head and base do not count.

**Results** (ReleaseSafe runners, 1 thread, measured):

| | Base | Head |
|---|---|---|
| passed | 143 | 2582 |
| failed | 2453 | 11 |
| crashed | 4 | 4 |
| skipped | 40 | 43 |
| minutes | 112.4 | 109.0 |

- **Step 5's commit works on the device.** At the base, all 2451 wasm
  results fail with `WasmExecFailed` (bytebox cannot reserve wasm32's 4 GiB
  in a 32-bit process). At the head the wasm backend is reported
  unavailable and skipped. The 3 extra skips at the head are the 3 tests
  that run only on wasm (the "overflows wasm32" capacity checks), which
  have no backend left there. The first run of step 5's 32-bit host branch
  on real hardware.
- **The same at both commits**, so not part 1: 9 interpreter failures, all
  "LIR/interpreter invariant violated: roc_crashed fired without an active
  jump buffer"; 4 interpreter segfaults in `evalProcActivation` (they look
  like deep recursion running out of stack); and the two "issue 11698:
  closures nested as call arguments" cases, which fail after about 51
  seconds before any backend runs, most likely out of the device's memory
  (its free memory fell to 0.02 GB in both runs). Upstream 32-bit host
  problems; see Open.

## Other findings

- **GitHub Actions on the fork** is enabled, but no workflow run of any
  kind exists after 2026-10-08, and #9's commit has no check suite at all.
  The cause is not visible through the API (repository or account
  settings, limits, or how the pull requests were opened). Its last minici
  runs took 3h13 to 3h39 end to end.
- **The oracle's hashing ran mostly on one shard.** A0's hash mode splits
  the 2373 eval cases into 16 contiguous blocks, and the expensive "issue
  11698" stress cases (about 70, at 3 to 70 seconds each) sit together at
  the end of the corpus: the last shard took 957 seconds, the other 15
  took 288 to 322. Decided 2026-10-26 (a cost-benefit check: 10 to 20
  minutes saved per oracle run, an estimated 10 to 30 runs ahead): a fix
  to A0 in the notes, `tools/a0-patches/0001-round-robin-shards.patch`,
  which the oracle applies after A0 (a patch beside the oracle rather
  than a new branch, so the oracle and what it applies stay in one
  place). Shard k takes cases k, k + 16, ..., and the parent restores case
  order. Measured: 474 seconds instead of 957, the hash file byte-identical
  (and identical at 1, 3 and 7 shards on a 26-case subset); peak memory
  13.8 GB instead of 9.0.
- **The oracle script** now builds both sides at the same time, prints
  each phase's time, saves each side's result under a key of every input
  (reusing it on a rerun; `--fresh` builds anyway), and stops both sides
  when one fails. A side hashes only once no build is running, and one
  side at a time: hashing peaks at 13.8 GB and a build at about 7 GB,
  against the 20 GB limit.
- **The sync machine helped** while its sync work was paused (until 1am):
  it built the device runners and ran minici's `linux-eval` shard, in its
  own folder with its own Zig cache. Removed at about 22:25 (47 GB); its
  own Zig cache was still 5.3 GB, and its logs and resource samples are
  kept with the timings.
- **Timings** of builds and checks, with peak memory and CPU time, are kept
  outside the repository, to improve estimates; this step's numbers are
  above.

## Open

- The Pi 3 runs found three upstream problems on 32-bit hosts (the
  interpreter's `roc_crashed` invariant, its segfaults, and the closures
  cases running out of the device's memory). Decided 2026-10-27: draft
  them when the plan reaches 32-bit hosts (part 11); the logs are kept
  with the timings.
- The 16 KiB-page fix is fork PR #10 (`b1df3f9f18`, rebased onto the
  fork's `main`, upstream `3c0fffe7bd`); nothing filed upstream (decided
  2026-10-27).
- Both devices keep `~/step7` until #9 merges (decided 2026-10-27). The
  throwaway branch `step7/head-page-fix` and its worktree are deleted.
- Close #8 and #3 after #9 is force-pushed with the rebased branch, each
  with a comment linking its commit in #9 (decided 2026-10-26). This ends
  step 7, after its checks.
- The owner to look at GitHub Actions on the fork (the repository's
  Settings -> Actions and the account's billing page), since the API does
  not show why nothing has run since 2026-10-08.
- Step 5's write-up said its 32-bit host branches "have never been
  compiled". Updated 2026-10-27: the eval runner's branch ran on the
  32-bit ARM device in sub-step 5 and works; the CLI test skips are still
  unrun (part 11).
