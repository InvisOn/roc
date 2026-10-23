# Incremental Plan PR reviews

## 2026-10-24, correction: #9's oracle did not check the eval cases

The step-2 recheck said the relative oracle passed for #9 against
`75d613ba5c`. Only the `dev_object` snapshot half of that is true. The oracle
gives the hash mode (A0) to the upstream side only. #9's branch has no hash
mode, and upstream's test harness takes an unknown flag as a filter, so its
eval runner wrote no hashes. The oracle then read the hash file a sync run
had left in the reused work tree, and compared upstream with that.

The tool now deletes the old file before each run, stops if the runner
writes none, and has `--apply-a0-to-merged` for PR branches. Sync merges
were not affected: the reference branch has the hash mode. Run the oracle on
#9 again after the fold.

## 2026-10-24, full nitpicky review posted on each PR

Each PR now has a "How the code flows" section in its description and a
review with inline comments marked **Attention** or **Nit**.

| PR | Review | Main points |
|---|---|---|
| #3 | [review](https://github.com/InvisOn/roc/pull/3#pullrequestreview-5629380923) | No upstream path applies abs64 on a 32-bit host today, so it fixes a contract. Only the 32-bit x86 run proves it, and CI can't. |
| #5 | [review](https://github.com/InvisOn/roc/pull/5#pullrequestreview-5629399294) | Module-level `var` is safe (own process) but hidden state. Stale check runs only when there are no violations. Only three directories are scanned, and comments and tests are skipped. |
| #6 | [review](https://github.com/InvisOn/roc/pull/6#pullrequestreview-5629416407) | Rebase onto `unexpectedLocation`. The invariant holds: U64 values never take an i128 location. |
| #7 | [review](https://github.com/InvisOn/roc/pull/7#pullrequestreview-5629426908) | Safe: upstream's `NOT_IMPLEMENTED` lines are all arm32 and wasm32 targets, which the architecture check skips. |
| #8 | [review](https://github.com/InvisOn/roc/pull/8#pullrequestreview-5629449425) | Doesn't compile on current `main` (`finishWriteExecutablePrefix`). No double flush. Non-Linux aarch64 hosts now fail to compile the whole compiler. Not yet run on aarch64. |
| #9 | [review](https://github.com/InvisOn/roc/pull/9#pullrequestreview-5629470770) | The per-site guarantee holds in `LirCodeGen` only. `FrameBuilder` and `CallingConvention` cache `is_x86_64` and `is_aarch64` and branch two-way on them. `aarch64_be` maps silently. 197 against 23 `comptime` uses. |

Two review texts were corrected after posting (#3: the 32-bit x86 run had
been done; #7: upstream does have `NOT_IMPLEMENTED` lines, for skipped
targets). Lesson: read the PR description and finish every check before
posting.

Code review and recheck of the open fork PRs. Newest first. "Read" means the
diff was read and compared with current upstream code; "run" means its tests
were run.

## 2026-10-24, against upstream `main` at `b9ec1d6645` (read only)

The chain for our own merge was running, so nothing was rebuilt or run yet.
Each PR was merged with upstream `main` in memory (`git merge-tree`) and its
changed code compared with upstream's.

| PR | Merges with `b9ec1d6645`? | Review | Needs |
|---|---|---|---|
| [#3](https://github.com/InvisOn/roc/pull/3) abs64 width | yes | Correct. Upstream still sizes the write by `@sizeOf(usize)`, so the fix still applies. | Rerun its test after a rebase. |
| [#5](https://github.com/InvisOn/roc/pull/5) stale exclusions | yes | Correct, and the 10 stale entries are still the same 10 (script in draft 26). (An earlier note here said the flags are never reset under `zig build --watch`. That was wrong: the check runs as its own process, so they start fresh every run.) | Rerun `run-check-type-checker-patterns`. |
| [#6](https://github.com/InvisOn/roc/pull/6) i128 index | **no, conflicts** | Correct when written. Upstream since added `unexpectedLocation(consumer, loc)` for impossible location kinds, and changed `.immediate_i128` to carry a wrapped value (`imm.get()`). | Rebase: drop our two prongs and add `.stack_i128` and `.immediate_i128` to the existing `unexpectedLocation("list_get_unsafe index", index_loc)` prong. The death test then matches "list_get_unsafe index received a". Smaller than before. Also filed upstream as #12532 by the owner. |
| [#7](https://github.com/InvisOn/roc/pull/7) snapshot errors | yes | Correct. Upstream's snapshot tool still records both errors as "not implemented" (`main.zig:3953-3955`, `3978-3980`), and `return false` is how the function reports its other failures. | Rerun `run-check-snapshots` after a rebase. |
| [#8](https://github.com/InvisOn/roc/pull/8) icache flush | yes, **but does not compile** | Correct when written: a pure move of the shim's helper, plus the call in `protectExecutable`. Upstream since added `finishWriteExecutablePrefix` (`ExecutableMemory.zig:275`), which calls `protectExecutable` but lacks `FlushInstructionCacheFailed` in its error set. | Rebase, add the error to that function and its callers' error sets. Still untested on aarch64: the Pi 5 can run its flush test. |
| [#9](https://github.com/InvisOn/roc/pull/9) Isa dispatch | yes | No new two-way target check in `LirCodeGen`, `FrameBuilder` or `CallingConvention` after the merge. The `builtin.cpu.arch` checks left are host checks in tests, which the PR leaves alone on purpose. | Rerun its checks after a rebase. |

Next: once no heavy job runs, rebase each PR onto upstream `main`, apply the
fixes above, and run each PR's "How to test" commands. Since the folding the
same day, #9 also takes #8's commit (with its fix above) and the glibc stub
commit from closed #4, and is then rerun as one PR; #8 closes after that.
Later the same day step 3 merged into step 2, so #9 also takes #3's commit,
the first word-size change (sizes through `word`) and the draft 07 fixes, cut
from the reference branch; #3 closes after that too.
