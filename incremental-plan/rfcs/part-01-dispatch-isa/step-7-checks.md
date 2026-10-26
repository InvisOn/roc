# Fold step 7 of 9: checks, rebase and ARM hardware

Draft, filled in as the sub-steps finish. Planning doc:
`step-7-checks-plan.md` (decisions D1 to D3 accepted 2026-10-26).

Branch `dispatch/isa`, 15 commits, rebased onto upstream `26436de489`.

| Sub-step | State |
|---|---|
| 1. Rebase | done |
| 2. Full set, minici, oracle | done |
| 3. Reference check | pending |
| 4. aarch64 device | pending |
| 5. 32-bit ARM device | pending |
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

## 3. Reference check

Pending.

## 4. aarch64 device

Pending. The aarch64 eval runner cross-builds on this machine (a trial on
the pre-rebase head: a 349 MB static Debug binary). Run from an empty
folder on this machine, the runner needs no other files (166 cases on the
interpreter, dev and wasm backends: 161 passed, 5 skipped).

## 5. 32-bit ARM device

Pending.

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
- **Timings** of builds and checks are kept outside the repository, to
  improve estimates; this step's numbers are above.

## Open

- Close #8 and #3 after #9 is force-pushed with the rebased branch, each
  with a comment linking its commit in #9 (decided 2026-10-26). This ends
  step 7, after its checks.
- The owner to look at GitHub Actions on the fork (the repository's
  Settings -> Actions and the account's billing page), since the API does
  not show why nothing has run since 2026-10-08.
- Step 5's write-up says its 32-bit host branches (`8ea2423294`,
  `e65824d17e` at the time) "have never been compiled". Partly out of date:
  the part 1 RFC's x86 32-bit check compiled the eval one. Sub-step 5 may
  run it on the 32-bit ARM device; the CLI test skips stay for part 11.
  Update step 5's note once sub-step 5 is done.
