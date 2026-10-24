# Incremental Plan: handoff

Written 2026-10-24, for picking the plan up on another machine. The plan
itself is in `README.md`. The review findings for each fork PR are in
`pr-review.md`. This page says where things stand, what to do next, and how
to set up and check the work.

Upstream `main` was at `9b119d59e4` when this was written. Updated the
same day: upstream `main` is now `04d6133c76`, and fork `main` has been
fast-forwarded to it.

### Changes since `9b119d59e4`

- Upstream added 11 commits. One of them evaluates compile-time values in
  the interpreter on hosts without native code generation (`c6154cb220`). It
  matters for the sync, not for the fold.
- Of the files the fold changes, only `src/eval/test/lir_inline_test.zig`
  changed upstream, and that was a test appended at the end of the file. A
  conflict there, if any, is two tests side by side.
- Upstream PR 12546 fixed 12531 (merged as `8b2888516b`).

## Upstream `main` compiles again (2026-10-25)

Upstream `main` did not compile from `6d72ef4d1b` until PR 12557 merged as
`f6c6cfb3d2` (draft 37). Rebase onto `upstream/main` again. The sync
machine merged `f6c6cfb3d2` as `f84787b815` and is running the checks.
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

## Who does what

- **Desktop PC:** the Incremental Plan PRs (this page).
- **The sync machine** keeps `claude/arm32-dev-backend-reference` merged
  with upstream and fast-forwards fork `main`. It no longer touches the plan
  PR branches, so the two machines don't push to the same branches.
- The merges up to upstream `9b119d59e4` are pushed. The reference branch
  is at `a5666157e7`. They carry a temporary fix for upstream issue 12531
  (`dev_object` hashes from a normal build, `606eaf8310`).

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
  about an hour and up to about 20 GB of memory. `--self-test` checks the
  script without building. The shim calls `/usr/bin/git`. Change that line
  if git lives somewhere else.

The other machines: the Pi 5 (`<user>@<aarch64-device>`, aarch64) and the Pi 3
(`<user>@<arm32-device>`, 32-bit ARM), on the home network.

## Where things stand

| PR | Branch | Head | Base | State |
|---|---|---|---|---|
| [#9](https://github.com/InvisOn/roc/pull/9) | `dispatch/isa` | `127015276f` | `75d613ba5c` (61 behind) | Step 2. Only the dispatch commit so far. The fold has not started. |
| [#8](https://github.com/InvisOn/roc/pull/8) | `fix/flush-jit-instruction-cache` | `5aa8ffecbf` | `73df27a5bb` (653 behind) | Draft 03. Folds into #9, then closes. |
| [#3](https://github.com/InvisOn/roc/pull/3) | `fix/abs64-relocation-width` | `9ee4d148e8` | `73df27a5bb` | Draft 12. Folds into #9, then closes. |
| [#4](https://github.com/InvisOn/roc/pull/4) | `fix/glibc-stub-arm-returns` | `4dffc5b3ea` | `73df27a5bb` | Draft 16. Closed. Its commit folds into #9. The same commit is open upstream as your 12513. |
| [#5](https://github.com/InvisOn/roc/pull/5) | `fix/stale-check-exclusions` | `80360119bf` | `73df27a5bb` | Draft 26. Not part of the plan. |
| [#6](https://github.com/InvisOn/roc/pull/6) | `fix/list-get-unsafe-i128-index` | `36e90a6776` | `73df27a5bb` | Draft 14 (filed as 12532). Not part of the plan. Conflicts with upstream. |
| [#7](https://github.com/InvisOn/roc/pull/7) | `fix/snapshot-dev-object-errors` | `f9e096039e` | `73df27a5bb` | Draft 02. Not part of the plan. |

Every open PR has a "How the code flows" section and a posted review (links
in `pr-review.md`). #9's step-2 recheck on `75d613ba5c` passed the build,
checks, backend tests, the `isaOf` test and snapshots. Its oracle result
does not count for the eval cases. The PR branch has no hash mode, so its
runner wrote nothing and the oracle compared a hash file left over from an
earlier sync run. The `dev_object` snapshot half of that run was real. The
oracle now deletes the old file and has `--apply-a0-to-merged` for PR
branches. Run it again on #9 after the fold.

## Next: fold step 2 into #9

Work in `.workspaces/pr-isa`.

1. **Rebase** `dispatch/isa` onto `upstream/main` (it builds again since
   `f6c6cfb3d2`).
2. **#8, instruction cache flush** (`5aa8ffecbf`). Cherry-pick it. It no
   longer compiles: upstream added `finishWriteExecutablePrefix`
   (`src/backend/dev/ExecutableMemory.zig`, about line 274), which calls
   `protectExecutable`. Add `FlushInstructionCacheFailed` to its error set,
   as #8 does for `finishWrite`.
3. **#4, glibc stub** (`4dffc5b3ea`). Cherry-pick it. If upstream merges
   12513 first, drop this piece.
4. **#3, abs64 width** (`9ee4d148e8`). Cherry-pick it.
5. **Draft 07, host word size.** Cut from the reference branch:
   - `722823bb21` Fix target data sized by the host's usize in the dev backend driver
   - `bcce4ac18a` Fix erased-callable payloads laid out with the host's word size
   - `c0b0981ec2` Report the wasm eval backend unavailable on 32-bit hosts

   Draft 07 (`upstream-issue-drafts/07-32-bit-host-readiness.md`) lists
   where each site is on `9b119d59e4`. The capture prefix is now passed in
   as `erased_capture_prefix`, with a Debug check at `LirCodeGen.zig:1341`
   against the host-sized `hot_reload_capture_prefix_size`. That check
   needs the same fix.
6. **Word size (1 of 3).** See "Open decisions" below. The source is the
   "A2" commits on the reference branch.
7. **Check** (see below). Run #8's flush on the Pi 5 too. It has only run
   on x86_64, which never needs a flush.
8. **Update #9's description.** Change section, the plan table
   (`plan_table.py`), "How the code flows", "How to test". Then close #8 and
   #3 with a comment that says they are in #9.
9. **Review #9 again** for the new diff, and add a dated entry to
   `pr-review.md`.

Then, off the plan: rebase #6. Upstream now has
`unexpectedLocation("list_get_unsafe index", index_loc)`. Add `.stack_i128`
and `.immediate_i128` to that prong. The death test then expects
"list_get_unsafe index received a". Rebase #5 and #7 too, and run each one's
"How to test".

## Open decisions

- **Which A2 commits make up word size (1 of 3).** The plan says step 2
  routes sizes, offsets and loops through `word`, `word_size` and
  `word_bits`. Step 5 takes the width vocabulary (`wide64_reg_width`,
  `wide64_store_width`), i128 by-pointer paths and the `isa` switches. The
  A2 commits on `origin/claude/arm32-dev-backend-reference`, oldest first:

  | Commit | Subject |
  |---|---|
  | `4a7408a857` | Derive the word size and RocStr/RocList field offsets from the target |
  | `c1140085d8` | Classify list element access and copies as word operations |
  | `a0438eb306` | Classify string and refcount helpers as word operations |
  | `1081022320` | Classify list helpers and pointer-moving helpers as word operations |
  | `6725f7be01` | Classify Boxy descriptor and dictionary references as word operations |
  | `dab7396781` | Make one-register integer arithmetic word-relative and classify low-level pointer sites |
  | `67a9276423` | Make integer conversions word-relative and name the Wide64 register width |
  | `5221a28d09` | Classify i128 halves and unary integer operations, copy i128 by words |
  | `d51ce605f8` | Make structural equality word-relative |
  | `1f97737f48` | Count call registers in words and classify return pairs |
  | `f3f72e0ed4` | Classify refcount, string and list helper sites |
  | `e14500f4e7` | Classify value-location, parameter, erased-call and entry sites |
  | `70c3bba0ee` | Make scalar bit counts word-relative |
  | `203855803c` | Classify the SIMD lowering's width sites, completing A2's classification |

  Part of `4a7408a857` is already upstream: string and list field offsets
  now come from the builtins, scaled by the target word
  (`LirCodeGen.zig:506-522`). Only the `target_ptr_size == 8` assertion at
  line 504 is left. The "Make ... word-relative" commits fit step 2. The
  "Classify ..." commits name widths, and may fit step 5 better. The size
  estimate for step 2 (about 2,150 lines) assumes all of A2 is in it.
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

The oracle must say `PASS` with 0 differences. If one `zig build minici`
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
