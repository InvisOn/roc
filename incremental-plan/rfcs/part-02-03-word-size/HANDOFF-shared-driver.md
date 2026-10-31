# Shared-driver work: handoff

Written 2026-11-01, after step 1 was pushed. For whoever picks up step 2.
The plan-wide handoff is `../../HANDOFF.md`; the decisions are in
`word-size-2-3-plan.md` (every "Decided" section); last night's
experiments are in `overnight-2026-10-29-report.md`. Read `AGENTS.md` and
`design.md` (dev backend parts) first.

## Where things stand

- Upstream `main`: `9eb3762719`. Local `main` and fork `main` were
  fast-forwarded to it.
- **Step 1 is done and pushed:** branch `isa-switch` on `InvisOn/roc`, one
  signed commit `5cd707b9b8`, title only:
  "Choose the dev backend's instruction set by exhaustive switch over Isa".
  Fork PR: InvisOn/roc#11 (base `main`, 1 commit, 13 files).
- **Upstream PR 12740** (roc-lang/roc), opened by the owner on 2026-11-01
  from `InvisOn:isa-switch` at `5cd707b9b8`: same commit, the owner's own
  description. Upstream CI runs on it. Every push to `isa-switch` now
  updates the upstream PR, so push nothing there without the owner's OK,
  and treat any force-push as visible to upstream reviewers.
- It contains: `isa.zig` (`Isa`, `isaOf`, `isaOfOrNull`, `isa.host`), every
  instruction-set choice in `LirCodeGen`, `FrameBuilder` and
  `CallingConvention` as an exhaustive `switch (isa)`, the same for
  `ObjectWriter`, `ExecutableMemory`, `HostSplice` (U2),
  `ObjectFileCompiler`, `host_lir_codegen_available`, the CLI's
  `devCapturePrefix`, `LirCodeGen`'s test host checks (3a, 4a), the
  little-endian assert, aarch64 guards rejecting `aarch64_be`, and the
  `design.md` section "Dev Backend Instruction Sets".
- **GitHub Actions is disabled for the fork** (HTTP 422 "Actions has been
  disabled for this repository"; the owner is contacting GitHub support).
  Step 1's CI runs on upstream PR 12740 instead
  (`gh pr checks 12740 --repo roc-lang/roc`). When the fork's Actions is
  back: close and reopen PR #11, or
  `gh workflow run ci_zig.yml --repo InvisOn/roc --ref isa-switch`.
- **Later steps go on a new branch `isa-word-size`, cut from `main`**
  (owner's decision, 2026-11-01). Upstream `main` is now `f7bef6b38f`.
  `isa-switch` stays as it is for PR 12740. The old
  `shared-driver/isa-word-size` (`10c3438d94`, no commits) is replaced by
  `isa-word-size` and is no longer used.
- Step 1 (`5cd707b9b8`) is not in `main` yet, so a branch cut from `main`
  does not contain it. Steps 2 onward build on step 1. How
  `isa-word-size` gets step 1 until PR 12740 merges is not decided.

## Checks step 1 passed

On `5cd707b9b8`'s tree (`98db3d3cae`, tag `scratch/step1-u2-9eb3762719`):

- relative oracle against `9eb3762719`: PASS, 0 of 2,394 eval cases and 0
  snapshot lines differ
- all 97 minici phases (shared between this machine and `laptop`)
- format, unreachable rationale, zig lints, backend tests (525/526), `roc`,
  snapshots; backend tests cross-compiled for Windows x86_64 and aarch64

On the earlier step 1 commit `c498de1d61` (same change minus U2): full
minici 98/98; Pi 5 backend and eval (base and head identical, 0 failed);
Pi 3 backend and eval (same failures as base, by name); qemu on `laptop`.

## How a step is built (method (b); decided 2026-10-29)

The real branch is generated, never hand-merged. Never resolve a conflict
by hand: it lost word-size changes before, and no test or oracle can see
that.

1. Work in the `binaryIs` form: worktree `.workspaces/pr-shared-driver-binaryis`,
   branch `scratch/shared-driver-binaryis` (2 signed commits on
   `9eb3762719`: `04f208c2fe` commit 1 replayed, `fc1227ca1b` all step 1
   edits in `binaryIs` form). Before commit 2, move it onto `f7bef6b38f`,
   the base of `isa-word-size`, or its regenerated trees will not match.
2. Take the next #9 commit with rerere off:
   `git -c rerere.enabled=false cherry-pick -S <commit>`. If it conflicts,
   stop and tell the owner.
3. Apply the step's decided fixes as scripted, count-checked edits in the
   `binaryIs` form; commit (signed, scratch). Owner edits to the generated
   tree must be carried here too, or the next regeneration drops them.
4. Regenerate: in the PR worktree (branch `isa-word-size`), `git checkout <scratch commit> -- .`, run
   `python3 -I <notes>/incremental-plan/rfcs/part-02-03-word-size/overnight-2026-10-29/to_switch.py .`,
   `git add -A`. The converter stops on any shape it does not know and
   checks that no `binaryIs`, cached flag or true/false switch is left.
5. Run the checks (below), show the owner the staged diff, commit only on
   their OK (signed, no Co-Authored-By, title-only message; the long text
   goes in a PR draft file like `pr-isa-switch-draft.md`), push only on OK.

The remaining #9 commits, replayed on `0c440e5f31` in
`.workspaces/exp-replay2` (detached, `215ef8cc8c`); they were written on top
of the original commit 1, so expect to check each against the step 1 edits:

| # | Commit | Subject (short) |
|---|---|---|
| 2 | `b896ee2908` | instruction cache flush |
| 4 | `627cde654b` | target data by the target's word |
| 5 | `2cf6fb2412` | erased-callable payload layout |
| 6 | `4a75df9abc` | hot-reload capture prefix |
| 7 | `668643f374` | new erased-callable payload size |
| 10 | `aab64ac737` | RocStr and RocList at the word width |
| 11 | `64ab7930eb` | one-register integer arithmetic |
| 12 | `4a78eeb865` | low-level pointers |
| 13 | `67597c87f3` | integer conversions |
| 14 | `215ef8cc8c` | scalar bit counts |

Proposed order (overnight report, not decided): 2; 4; 5+6+7 squashed;
10 with `word` / `word_bits`; multi-register arguments in words; Wide64
routing; 11 to 14; `CC` register facts; part 3's remaining `.w64` sites;
the lint and `design.md`'s word-size paragraph last. Last night's
prototypes for most of these are commits on `exp/shared-driver-overnight`
(`.workspaces/exp-shared`, old base `bad769be8e`).

## Checks for each step

- `zig build run-check-zig-format run-check-unreachable-rationale
  run-check-zig-lints run-test-zig-module-backend roc run-check-snapshots`
  (each through `.workspaces/timings/measure.py`; about 4 min warm).
- Relative oracle, from the main checkout, with rerere off:
  `GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=rerere.enabled GIT_CONFIG_VALUE_0=false python3 .workspaces/notes/incremental-plan/tools/relative_oracle.py --upstream <main> --merged <throwaway commit> --apply-a0-to-merged`.
  Make the throwaway commit with `git commit-tree -S -p <main> $(git write-tree)`
  and tag it `scratch/...`; never commit to the PR branch before review.
  About 28 min, 15 GB.
- minici, shared with `laptop`: a queue of phases, longest first, each run
  with `zig build minici -- --minici-only <phase> --minici-skip-build`.
  Each machine first runs `--minici-only <cheap phase>` without the skip
  flag (that does `build-ci`). Scripts:
  `/tmp/claude-1000/.../scratchpad/queue/` is temporary; rebuild from this
  description. About 50 min with two machines.
- Pis (`pi5` aarch64, `pi3` 32-bit ARM): only when the owner asks. Cross-
  build on `laptop` (it has `qemu-arm` and `qemu-aarch64`, so its backend
  test step also runs the tests), copy to `~/step1`-style folders, run
  backend tests and the eval runner for base and head; only differences
  between base and head count.

## Pitfalls met in step 1

- **rerere** is on for every worktree (shared cache). Turn it off per
  command. On step 1 it replayed an A0 resolution that carried an edit
  outside the conflict hunk.
- **A0 on a new base:** the oracle now applies `1f461d76df` (tag
  `scratch/a0-on-10c3438d94`): A0 with its conflicts on `10c3438d94`
  resolved by explicit rules. It applies cleanly to `9eb3762719`. When it
  stops applying, make a new one the same way and get the owner's OK. It
  must be made with `git commit-tree -S` (owner's decision H1), because
  A0's `eval.blake3` holds upstream test names with issue numbers that the
  fork-rules pre-commit hook rejects. Local only, never pushed.
- **Remote commands:** `pi3`, `pi5` and `laptop` are nushell aliases. Call
  them as `nu -l -c "laptop -o BatchMode=yes \"bash -lc '...'\""`. Over SSH
  the remote nushell runs `nu -c`, which skips `env.nu`, so `zig`, `node`,
  `rustc` and `nu` itself are not on PATH; `bash -lc` loads the profile
  that adds them. Nothing needs installing on `laptop`.
- **Never `git reset --hard` a worktree with unstaged changes:** the owner
  edits the generated tree directly (one edit was lost that way).
- **`pgrep -f` / `pkill -f`** match their own command line; anchor the
  pattern (for example `^/bin/bash ./build.sh`).
- **Force-push** only with `--force-with-lease=<branch>:<expected sha>`, and
  check first whether the owner pushed in between (they did once).
- Background commands: create log folders before redirecting into them.

## Open points

From the plan (decide with the step they affect):

- erased-callable layout location (commits 5 to 7; overnight recommends
  `builtins.erased_callable.TargetLayout.of`)
- Wide64 routing, and how wider sources are kept off one-word paths
  (commits 11, 13, 14)
- signedness source (11), in-bounds index helper (12), `word_bits: u8` in
  commit 10 (13), 128-bit bit-count helpers and `wordOfU128` (14)
- names `target_ptr_size` / `target_word_size` / `word` / `word_bits` (10)
- the `.w64` lint's rule (overnight: only bare `.w64` passed to an
  architecture-neutral helper)
- destinations of #9's commits 3 (abs64) and 8, 9 (wasm on 32-bit hosts)

New from step 1:

- Neither PR description mentions U2 (`isa.host`, `ObjectWriter`,
  `ExecutableMemory`, `HostSplice`): not the fork draft
  (`pr-isa-switch-draft.md`, which also says "the other lists" are only
  `ObjectFileCompiler`, `host_lir_codegen_available` and the CLI), and not
  the owner's description on upstream PR 12740. The owner decides whether
  to update them.
- Watch upstream PR 12740's CI and review; review changes go into the
  `binaryIs` form first (method (b)), then regenerate.
- `design.md`: "Code that builds a backend for a specific target asks" is
  81 columns; the paragraph wraps at 80.
- `host_lir_codegen_available` uses `RocTarget.detectNative()`, which maps
  an unknown architecture (riscv64, ppc64) to an x64 target, so it reports
  a code generator there. `isa.host != null` would fix it; behaviour change
  on those hosts, so not done without a decision.
- On 32-bit ARM (Pi 3, qemu) 9 backend tests fail on upstream and on ours:
  8 `wasm.WasmCodeGen` "issue 12198" tests (`Uninstantiable64BitLimitsOn32BitArch`,
  bytebox), not covered by #9's commits 8 and 9; and
  `dev.SymbolTable` "retain IDs across growth and reset"
  (`NondeterministicMemoryUsage`), not investigated.
- Uncommitted in the notes worktree, waiting for the owner's OK:
  `to_switch.py` (complete converter), `relative_oracle.py` (`A0_COMMIT`),
  `word-size-2-3-plan.md` (decisions of 2026-10-31), `pr-isa-switch-draft.md`,
  this file.

## Leftovers to clean up (ask first)

- Pis: `~/step1` (binaries and logs, about 0.9 GB on Pi 5, 0.45 GB on Pi 3).
- `laptop`: `~/pi-step1` (Pi build worktrees), `~/step1-ci` (detached
  worktree of `98db3d3cae`) and `~/step1-ci-logs`. Also `~/ci-isa` and
  `~/ci-isa-logs`, from a `build-ci` run started outside this session and
  stopped on the owner's request.
- Local tags `scratch/*` and worktrees `.workspaces/exp-*`,
  `.workspaces/relative-oracle/*` (the oracle reuses the last two).

## How to work with the owner

- Label every message with the step (`## ▶️ Step N, part M: …`,
  `## ⏸️ Waiting for …`), plain language, narrow tables, lists.
- Ask in plain chat, never the multiple-choice popup; each option with its
  cost and benefit, then a recommendation; keep item numbers stable.
- Give an ETA for every build, test or oracle run; record time, memory and
  CPU in `.workspaces/timings/timings.csv`; push a notification when a
  long run finishes.
- Record decisions in `word-size-2-3-plan.md` only after the owner makes
  them. No commit, push or PR without explicit OK; PRs only to InvisOn/roc.
- No machine usernames, hostnames or addresses in any file.
