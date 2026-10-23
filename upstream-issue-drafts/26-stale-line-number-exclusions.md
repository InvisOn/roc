# Draft: The forbidden-pattern check skips lines by number, and 10 of its 11 entries no longer skip anything

> **Upstream or ours:** Upstream. The bug is in upstream's code and has nothing to do with our arm32 work.

> **Relevance to our arm32 work:** Our changes move lines in the checked files. That moves the skipped lines onto other code, so the check can fail or pass for the wrong reason.

Not filed. For roc-lang/roc.

| | |
|---|---|
| Still an issue? | Yes (2026-10-24, upstream `main` at `b9ec1d6645`). The script below finds 10 stale entries out of 11. |
| Already upstream? | No issue or PR found (searched 2026-10-24 for `excluded_ranges`). |
| Fixed on our reference branch? | No. Fork PR #5 has the fix: the check fails on any entry that excused nothing, and the ten stale entries are removed. |
| Before filing | Rerun the script on current `main`. |

---

**Title:** `check-type-checker-patterns` skips lines by number, and 10 of its 11 exemptions no longer exempt anything

**What happens**

`src/build/check_runner.zig` checks `src/canonicalize/`, `src/check/`, `src/layout/` and `src/eval/` for raw string comparison: a `std.mem.` call outside an allowed list, or `findByString`, `findIdent` or `getMethodIdent`. A list called `excluded_ranges` lets specific lines through, by file name and line number. When someone edits a file, the code moves and the numbers stay.

On `b9ec1d6645`, 10 of the 11 entries point at lines with nothing the check would flag:

- `cir_to_lir.zig` no longer exists in the scanned directories.
- `inspected.zig` 3264-3275 is past the end of the file (3229 lines).
- The other eight point at unrelated code. For example, `inspected.zig` 2474 is meant to cover "trims the trailing newline off a rendered report", but it now holds an event callback. `inspected_run.zig` 109 is meant for "dispatches on a hosted function's ABI symbol", but it now holds a union declaration.
- In most of these files, the pattern the entry was written for is gone altogether. `boxy_runtime.zig`, `report.zig`, `compile_time_finalization.zig`, `Check.zig` and the three `store.zig` files have no flagged line anywhere.

Only `inspected.zig` 226-232 still excuses something (`findIdent` at line 227).

**Where** (upstream `main` at `b9ec1d6645`)

- `src/build/check_runner.zig:196-230`, the `excluded_ranges` list, used by `isInExcludedRange` at lines 273 and 279.
- The stale entries are at lines 197, 198, 202, 206, 210, 216, 219, 222, 225 and 229.

**Why it matters**

- A stale entry exempts whatever lands on its lines later. Anyone who adds a forbidden pattern there gets no error.
- The list gives a wrong picture of where the code compares strings.
- Nothing notices when an entry goes stale.

**How to reproduce**

This script looks at every entry and every scanned file that the entry's name matches. It reports an entry when none of those files has a line in its range that the check would flag. Run it from the repository root. On `b9ec1d6645` it printed the following and exited with 1:

```
boxy_runtime.zig:5614-5614: nothing the check would flag (src/eval/boxy_runtime.zig)
boxy_runtime.zig:5624-5624: nothing the check would flag (src/eval/boxy_runtime.zig)
Check.zig:5530-5547: nothing the check would flag (src/check/Check.zig)
store.zig:340-355: nothing the check would flag (src/check/problem/store.zig,src/check/const_store.zig,src/layout/store.zig)
cir_to_lir.zig:110-115: no matching file in the scanned directories
inspected.zig:2474-2474: nothing the check would flag (src/eval/inspected.zig)
inspected.zig:3264-3275: nothing the check would flag (src/eval/inspected.zig)
inspected_run.zig:109-109: nothing the check would flag (src/eval/inspected_run.zig)
compile_time_finalization.zig:171-183: nothing the check would flag (src/eval/compile_time_finalization.zig)
report.zig:615-615: nothing the check would flag (src/check/report.zig)
```

```sh
#!/bin/sh
# Run from a roc checkout. An entry in excluded_ranges (src/build/check_runner.zig)
# is stale unless one of the files it matches (by name suffix, in the four
# scanned directories) has a line in its range that the check would flag:
# a std.mem. call outside the allowed list, or findByString, findIdent or
# getMethodIdent. Prints each stale entry; exits 1 if any.
ranges=$(grep -o '\.file = "[^"]*", \.start = [0-9]*, \.end = [0-9]*' src/build/check_runner.zig |
  sed 's/.*"\(.*\)", .start = \([0-9]*\), .end = \([0-9]*\)/\1 \2 \3/')
allowed='Allocator|Alignment|sort|asBytes|bytesAsValue\(|readInt\(|writeInt\(|reverse|alignForward|order|copyForwards'
bad=0
while read -r name start end; do
  files=$(find src/canonicalize src/check src/layout src/eval -name "*$name" 2>/dev/null)
  if [ -z "$files" ]; then echo "$name:$start-$end: no matching file in the scanned directories"; bad=1; continue; fi
  hit=0
  for f in $files; do
    if sed -n "${start},${end}p" "$f" | awk -v allowed="^($allowed)" '
      { i = index($0, "std.mem."); if (i > 0 && substr($0, i + 8) !~ allowed) found = 1 }
      /findByString|findIdent|getMethodIdent/ { found = 1 }
      END { exit !found }'; then hit=1; fi
  done
  if [ $hit -eq 0 ]; then echo "$name:$start-$end: nothing the check would flag ($(echo $files | tr ' ' ','))"; bad=1; fi
done <<RANGES
$ranges
RANGES
exit $bad
```

The allowed list mirrors `lineViolations` in `check_runner.zig`. Like the check, the script looks only at the first `std.mem.` on a line.

**Possible fix** (offered, tested on a fork)

Have the check record which entries excused a forbidden pattern, and fail on any entry that excused none. Then remove the ten stale entries. With that, `zig build run-check-type-checker-patterns` passes, and putting back any removed entry makes it fail and name that entry.

**Environment**

- OS: Pop!_OS 24.04 LTS, x86_64
- Upstream `main` at `b9ec1d6645`, Zig 0.17.0
