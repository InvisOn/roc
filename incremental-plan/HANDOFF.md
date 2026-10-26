# Incremental Plan: handoff

Written 2026-10-24, for picking the plan up on another machine. The plan
itself is in `README.md`. The review findings for each fork PR are in
`pr-review.md`. This page says where things stand, what to do next, and how
to set up and check the work.

Upstream `main` was at `9b119d59e4` when this was written, and at
`04d6133c76` later that day, when fork `main` was fast-forwarded to it. On
2026-10-25 upstream `main` is at `629c3e0e2d`, and on 2026-10-26 at
`26436de489` (28 commits past `dispatch/isa`'s base).

### Changes since `9b119d59e4`

- Upstream added 11 commits. One of them evaluates compile-time values in
  the interpreter on hosts without native code generation (`c6154cb220`). It
  matters for the sync, not for the fold.
- Of the files the fold changes, only `src/eval/test/lir_inline_test.zig`
  changed upstream, and that was a test appended at the end of the file. A
  conflict there, if any, is two tests side by side.
- Upstream PR 12546 fixed 12531 (merged as `8b2888516b`).

## Upstream `main` compiles again (2026-10-25)

Note: on 2026-10-25 the fork's history was rewritten to remove machine
names, so every commit on `claude/arm32-dev-backend-reference` got a new
hash. The hashes of our commits in this file are the new ones. Upstream
hashes did not change.

Upstream `main` did not compile from `6d72ef4d1b` until PR 12557 merged as
`f6c6cfb3d2` (draft 37). Rebase onto `upstream/main` again. The sync
machine merged `f6c6cfb3d2` as `04a0fb0ffc`, and it passed every check.
In that merge, both `LirCodeGen.zig` conflicts took upstream's side: the
128-bit `list_get_unsafe` index cases and the byte-store shifts are gone,
so a rebase hits the same two conflicts if `dispatch/isa` changed that code.

Also from upstream today:

- Upstream fixed draft 14 (fork PR #6, the `list_get_unsafe` index width)
  in `8a64a61258`. PR #6 can be closed once you've checked it.
- Upstream fixed draft 19 (the byte-store shifts) in `5300d1ee60`, and
  draft 10 (recursive keys in loaded images) in `6d72ef4d1b`.
- Boxy calls now pass layout numbers as patchable runtime references
  (`emitRuntimeRefInto`, `addRuntimeLayoutArg`). Every code generator needs
  `emitPatchableImm32` and `patchImm32`. The reference branch adds the arm32
  pair (MOVW/MOVT) in its merge of `414a19203e`.

## Step 5 will conflict with upstream `478cff9095` (2026-10-26)

Upstream `478cff9095` rewrote the erased-callable code that step 5 changes
(`772baf1e39`, the `erased_layout` helper, and `6f2b3a4efc`, sizing new
payloads). When `dispatch/isa` moves to an upstream at or past
`478cff9095`, expect conflicts in the same places.

- Upstream now writes the closure metadata only when the program uses the
  Boxy runtime (`self.store.runtime_contract == .boxy`). Keep upstream's
  checks and put the word-sized `erased_layout` code inside them.
- Upstream added a direct call of erased callables for programs without
  the Boxy runtime. It loads the function pointer with 8-byte loads and a
  store (`.w64`, `LirCodeGen.zig:14373-14377` on upstream). Step 5 must move
  those to the target word size too, or arm32 builds break there.
- Done in fold step 7's rebase (2026-10-26): the first point and the
  payload sizing as described. The direct-call `.w64` loads were left for
  part 3 instead (step 7, option 3): the same function's older closure
  pointer accesses are also `.w64`, and erased-call sites are part 3's
  "Classify" work. arm32 cannot build before part 6 lifts the 8-byte
  assert, so nothing breaks in between. They are on the "left for part 3"
  list in `rfcs/part-01-dispatch-isa/step-6-word-size.md`.
- The reference branch resolved this in its merge `f7c1244257`, which
  passed every check. One difference: the reference branch still sizes new
  payloads with `compilerPayloadSize` in the Boxy case. Keep step 5's
  `erased_layout` version there.

## Who does what

- **Desktop PC:** the Incremental Plan PRs (this page).
- **The sync machine** keeps `claude/arm32-dev-backend-reference` merged
  with upstream and fast-forwards fork `main`. It no longer touches the plan
  PR branches, so the two machines don't push to the same branches.
- The merges up to upstream `9b119d59e4` are pushed. The reference branch
  is at `54496c9614`. They carry a temporary fix for upstream issue 12531
  (`dev_object` hashes from a normal build, `3a807f3c88`).

## Set up on a new machine

```sh
git clone git@github.com:InvisOn/roc.git roc_32bit
cd roc_32bit
git remote add upstream https://github.com/roc-lang/roc.git
git fetch origin
git fetch upstream
git fetch origin notes:notes
mkdir -p .workspaces
git worktree add .workspaces/pr-isa dispatch/isa
git worktree add .workspaces/notes notes
```

Fetch each remote on its own, as above. `git fetch upstream origin` treats
`origin` as a refspec.

Install the git hooks from `tools/git-hooks/` on `notes` (its README says
how). They block upstream references, session trailers and unsigned
commits before they reach GitHub.

You need Zig 0.17.0, Python 3 and `gh`. Commits are signed with `-S`. Signing
is set up per machine, so check `git config user.signingkey` and
`gpg.format` first.

The tools from `incremental-plan/tools/` on `notes` (in the worktree above):

- `plan_table.py README.md <step>` prints the plan table for a PR
  description, with that step in bold and no draft numbers.
- `relative_oracle.py --upstream <commit> --merged <commit>` is the relative
  64-bit oracle. For a PR branch add `--apply-a0-to-merged`, which gives the
  PR side the hash mode too (sync merges already have it). It builds both commits as the same compiler version (the
  `git-shim/git` beside it fakes `git rev-parse --short=8 HEAD`) and checks
  that x86_64 and aarch64 output is byte-identical. Run it from the main
  checkout. Its work trees go in `.workspaces/relative-oracle`. It takes
  about 25 minutes with both sides built (about 18 with upstream reused)
  and up to about 18 GB of memory. The two sides build at the
  same time and print each phase's time. Each side's result is saved under
  a key of everything that reaches it, so a rerun on the same base reuses
  the upstream side and says so. A side hashes only once no build is
  running, and one side at a time, which keeps a run under the memory
  limit. Pass `--fresh` for the run before review.
  It needs Python 3.12 or newer. The patches in `tools/a0-patches/` are
  applied after A0, in name order: fixes to A0's own code that only the
  oracle uses (`0001` hashes the eval cases in round-robin shards; it
  halves the hashing). `--self-test` checks the
  script without building. The shim calls `/usr/bin/git`. Change that line
  if git lives somewhere else.

The other machines: the Pi 5 (`<user>@<aarch64-device>`, aarch64) and the Pi 3
(`<user>@<arm32-device>`, 32-bit ARM), on the home network.

## Where things stand

| PR | Branch | Head | Base | State |
|---|---|---|---|---|
| [#9](https://github.com/InvisOn/roc/pull/9) | `dispatch/isa` | local `8e9e512e0f`, pushed `127015276f` | local `26436de489` (rebased in step 7 on 2026-10-26; the old head is `backup/dispatch-isa-pre-rebase2-2026-10-26`), pushed `75d613ba5c` | Part 1. Fold steps 1 to 6 are done locally (15 signed commits), not pushed. Step 7 is in progress: sub-steps 1 (rebase) and 2 (full set, minici, oracle) are done. |
| [#8](https://github.com/InvisOn/roc/pull/8) | `fix/flush-jit-instruction-cache` | `5aa8ffecbf` | `73df27a5bb` (653 behind) | Draft 03. Folds into #9, then closes. |
| [#3](https://github.com/InvisOn/roc/pull/3) | `fix/abs64-relocation-width` | `9ee4d148e8` | `73df27a5bb` | Draft 12. Folds into #9, then closes. |
| [#4](https://github.com/InvisOn/roc/pull/4) | `fix/glibc-stub-arm-returns` | `4dffc5b3ea` | `73df27a5bb` | Draft 16. Closed. Its commit folds into #9. The same commit is open upstream as your 12513. |
| [#5](https://github.com/InvisOn/roc/pull/5) | `fix/stale-check-exclusions` | `80360119bf` | `73df27a5bb` | Draft 26. Not part of the plan. |
| [#6](https://github.com/InvisOn/roc/pull/6) | `fix/list-get-unsafe-i128-index` | `36e90a6776` | `73df27a5bb` | Draft 14 (filed as 12532). Not part of the plan. Conflicts with upstream. |
| [#7](https://github.com/InvisOn/roc/pull/7) | `fix/snapshot-dev-object-errors` | `f9e096039e` | `73df27a5bb` | Draft 02. Not part of the plan. |

Every open PR has a "How the code flows" section and a posted review (links
in `pr-review.md`). #9's recheck on `75d613ba5c` (when it was part 2) passed the build,
checks, backend tests, the `isaOf` test and snapshots. Its oracle result
does not count for the eval cases. The PR branch has no hash mode, so its
runner wrote nothing and the oracle compared a hash file left over from an
earlier sync run. The `dev_object` snapshot half of that run was real. The
oracle now deletes the old file and has `--apply-a0-to-merged` for PR
branches. Step 6 ran it on the whole branch (`629c3e0e2d` against
`0d8048aee4`); the result is in `rfcs/part-01-dispatch-isa/step-6-word-size.md`.
Step 7 ran it on the rebased branch (`26436de489` against `8e9e512e0f`),
twice, both PASS; the results are in
`rfcs/part-01-dispatch-isa/step-7-checks.md`.

## Next: fold part 1 into #9

Work in `.workspaces/pr-isa`.

Every fold step gets a step doc in `rfcs/part-01-dispatch-isa/` once it is
committed.
From step 6 on, each step also gets a planning doc made from
`templates/rfc.md` before its code work starts.

1. **Rebase** `dispatch/isa` onto `upstream/main` (it builds again since
   `f6c6cfb3d2`). Done on `3bb8f2ec6c`, before upstream built again, and
   again on `629c3e0e2d` on 2026-10-26, before step 6 (branch D3). Rebase
   once more before the checks in step 7 if upstream has moved.
2. **#8, instruction cache flush** (`5aa8ffecbf`). Cherry-pick it. It no
   longer compiles: upstream added `finishWriteExecutablePrefix`
   (`src/backend/dev/ExecutableMemory.zig`, about line 274), which calls
   `protectExecutable`. Add `FlushInstructionCacheFailed` to its error set,
   as #8 does for `finishWrite`.
3. **#4, glibc stub** (`4dffc5b3ea`). Cherry-pick it. If upstream merges
   12513 first, drop this piece.
4. **#3, abs64 width** (`9ee4d148e8`). Cherry-pick it.
5. **Draft 07, host word size.** Cut from the reference branch:
   - `cede2ab5b7` Fix target data sized by the host's usize in the dev backend driver
   - `2aecaa5529` Fix erased-callable payloads laid out with the host's word size
   - `be8a417829` Report the wasm eval backend unavailable on 32-bit hosts

   Draft 07 (`upstream-issue-drafts/07-32-bit-host-readiness.md`) lists
   where each site is on `9b119d59e4`. The capture prefix is now passed in
   as `erased_capture_prefix`, with a Debug check at `LirCodeGen.zig:1341`
   against the host-sized `hot_reload_capture_prefix_size`. That check
   needs the same fix.
6. **Word size (1 of 3).** Done 2026-10-26: five commits, from
   `84c8a5e582` to `0d8048aee4` (RocStr and RocList accesses, integer
   arithmetic, low-level pointers, conversions, bit counts). The plan is
   `rfcs/part-01-dispatch-isa/step-6-word-size-plan.md`, the write-up
   `step-6-word-size.md`, with the decisions made along the way, the
   word-sized sites left for part 3, and the arm32 tests that must cover
   step 6's sites before the 8-byte assert is lifted (part 6).
7. **Check** (see below). Run #8's flush on the Pi 5 too. It has only run
   on x86_64, which never needs a flush. Step 7 ends by force-pushing #9
   with the rebased branch, then closing #8 and #3, each with a comment
   linking its commit in #9 (decided 2026-10-26).
8. **Update #9's description.** Change section, the plan table
   (`plan_table.py`), "How the code flows", "How to test".
9. **Review #9 again** for the new diff, and add a dated entry to
   `pr-review.md`.

Then, off the plan: check #6 against upstream's fix of draft 14
(`8a64a61258`, see above), then close it. Rebase #5 and #7, and run each
one's "How to test".

## Open decisions

- **Reminder: add a plan step that tests the finished work on a real Roc
  project on arm32** (asked for 2026-10-26). Today's checks use the eval
  corpus, snapshots and the oracle; none builds and runs an actual Roc
  application, with a platform and a host, on the 32-bit ARM device. Still
  to decide: which project, where the step goes in the plan (after the
  part that makes arm32 a host, or as its own part), and its pass rule.
  Add it to the README's plan when decided.
- **Which A2 commits make up word size (1 of 3).** Decided 2026-10-25:
  option 1, done in fold step 6 (see above and its write-up; `word_size`
  below became upstream's `target_ptr_size`, and the structural equality
  commit had no code left upstream). The rest of this item is the record
  of the choice. The plan says part 1
  routes sizes, offsets and loops through `word`, `word_size` and
  `word_bits`. Part 3 takes the width vocabulary (`wide64_reg_width`,
  `wide64_store_width`), i128 by-pointer paths and the `isa` switches. The
  A2 commits on `origin/claude/arm32-dev-backend-reference`, oldest first:

  | Commit | Subject |
  |---|---|
  | `bf9d0e0d49` | Derive the word size and RocStr/RocList field offsets from the target |
  | `c38adf988b` | Classify list element access and copies as word operations |
  | `93c546d7b5` | Classify string and refcount helpers as word operations |
  | `1732f08923` | Classify list helpers and pointer-moving helpers as word operations |
  | `6a4fec0a76` | Classify Boxy descriptor and dictionary references as word operations |
  | `0676c747be` | Make one-register integer arithmetic word-relative and classify low-level pointer sites |
  | `75e30d5f49` | Make integer conversions word-relative and name the Wide64 register width |
  | `da4cb4a451` | Classify i128 halves and unary integer operations, copy i128 by words |
  | `b2ec6583e4` | Make structural equality word-relative |
  | `236042aa45` | Count call registers in words and classify return pairs |
  | `6f03627f1b` | Classify refcount, string and list helper sites |
  | `c4156ac121` | Classify value-location, parameter, erased-call and entry sites |
  | `e7d97b7d88` | Make scalar bit counts word-relative |
  | `152574b40d` | Classify the SIMD lowering's width sites, completing A2's classification |

  Part of `bf9d0e0d49` is already upstream: string and list field offsets
  now come from the builtins, scaled by the target word
  (`LirCodeGen.zig:506-522`). Only the `target_ptr_size == 8` assertion at
  line 504 is left. The "Make ... word-relative" commits fit part 1. The
  "Classify ..." commits name widths, and may fit part 3 better. The size
  estimate for part 1 (about 2,150 lines) assumes all of A2 is in it.
- **#9 review findings** (optional). `FrameBuilder` and `CallingConvention`
  still branch two-way on cached `is_x86_64` and `is_aarch64`, so a new ISA
  is not caught there. `aarch64_be` maps silently to `aarch64`. `comptime`
  is used on 197 sites and missing on 23.

## How to check a PR

The PR's own "How to test" commands come first. For #9 they are:

```sh
zig build run-check-zig-format run-check-unreachable-rationale
zig build run-test-zig-module-backend --summary all -- --test-filter "isaOf maps the native RocTargets"
zig build run-test-zig-module-backend
zig build run-check-snapshots
```

Then the full check, one heavy job at a time:

```sh
# from the main checkout
python3 .workspaces/notes/incremental-plan/tools/relative_oracle.py \
  --upstream <upstream base> --merged <PR head> --apply-a0-to-merged
# from .workspaces/pr-isa
zig build minici
```

minici's `run-check-glue-abi` needs two Rust targets, as upstream's CI
installs them: `rustup target add wasm32-unknown-unknown` and
`rustup target add x86_64-unknown-linux-musl` (`aarch64-unknown-linux-musl`
on an aarch64 machine). Without them minici stops at that phase.

The oracle must say `PASS` with 0 differences.

If A0's patch no longer applies to upstream, the oracle stops and leaves
the conflicts in `.workspaces/relative-oracle/upstream`. Resolve them there,
record the resolutions with `git -c rerere.enabled=true rerere` (before and
after resolving), and rerun the oracle with rerere on for its git calls:
`GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=rerere.enabled GIT_CONFIG_VALUE_0=true`
in front of the command. rerere replays only conflict hunks, so an edit A0's
code needs outside them goes into `A0_FOLLOWS` in `relative_oracle.py`. If one `zig build minici`
section fails, fix it and rerun only that section (for example
`zig build run-test-zig-snapshot-tool`) until it passes, then run minici
again.

Heavy builds can use 20 GB. The sync machine runs each one under
`systemd-run --user --scope -p MemoryMax=20G -p MemorySwapMax=4G nice -n 10`
so the machine stays usable.

## Rules for the PRs

- PRs go only to InvisOn/roc `main`, never upstream. You file upstream
  yourself.
- Sign every commit with `-S`. No Co-Authored-By or Claude-Session lines,
  and no session links in PR descriptions.
- No upstream references (`#NNNN`, roc-lang links) in commits, in files on
  code branches, or in fork PR bodies. Use commit hashes and words.
- Every plan PR description has the plan table, a "How the code flows"
  section (numbered steps, before "Tested") and ends with "How to test".
  Update the table in every open plan PR when it changes.
- Every PR gets a nitpicky review with inline comments marked **Attention**
  or **Nit**, redone when the diff changes. Read the PR body and finish
  every check before posting.
- `AGENTS.md`: no workarounds, fallbacks or heuristics. Compiler invariants
  are debug asserts or `base.invariant`. Every `unreachable` has a reason on
  the same line. Environment variables only through `base.dev_diagnostics`.
- C runtime binaries are built, not committed.
- Plain sentences in notes, commits and PR text.
- `notes` changes are committed and pushed straight away.
