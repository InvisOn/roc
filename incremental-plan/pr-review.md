# Incremental Plan PR reviews

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
| [#5](https://github.com/InvisOn/roc/pull/5) stale exclusions | yes | Correct, and the 10 stale entries are still the same 10 (script in draft 26). One small point: `excluded_range_used` is a file-level `var` that is never reset, so a second run in the same process (`zig build --watch`) would keep the first run's flags and could miss a stale entry. It can never fail wrongly. Resetting it at the start of the step, or returning the flags instead of keeping state, would fix that. | Optional fix above. Rerun `run-check-type-checker-patterns`. |
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
