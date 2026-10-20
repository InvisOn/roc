# Draft: The forbidden-pattern check skips lines by number, and the numbers are out of date

> **Upstream or ours:** Upstream. The bug is in upstream's code and has nothing to do with our arm32 work.

> **Relevance to our arm32 work:** Our changes move lines in the checked files. That moves the skipped lines onto the wrong code, so the check fails or passes for the wrong reason.

Not filed. For roc-lang/roc.

| | |
|---|---|
| Still an issue? | Yes (2026-10-20, upstream `main` at `5fc587cf51`). The script below finds four out-of-date entries. |
| Already upstream? | No issue or PR found (searched 2026-10-20). |
| Fixed on our reference branch? | No. Our branch has the same entries, shifted by one line. |
| Before filing | Nothing. |

---

**Title:** The forbidden-pattern check skips lines by number, and the numbers are out of date

**What happens**

`src/build/check_runner.zig` checks `src/` for forbidden patterns. A list called `excluded_ranges` lets specific lines through, by file name and line number, for example `.{ .file = "inspected.zig", .start = 3264, .end = 3275 }`. When someone edits a file, the numbers stay the same while the code moves. The exemption then lands on unrelated code, and the line it was written for is checked again.

Four of the entries are out of date on `5fc587cf51`:

- `cir_to_lir.zig` (lines 110-115) no longer exists.
- `inspected.zig` line 2474 is a lone `}`.
- `inspected.zig` lines 3264-3275 are past the end of the file, which has 3255 lines.
- `inspected_run.zig` line 109 is blank.

**Where** (upstream `main` at `5fc587cf51`)

- `src/build/check_runner.zig:193-225`, the `excluded_ranges` list. It is used at line 231.
- The out-of-date entries are at lines 208 (`cir_to_lir.zig`), 214 (`inspected.zig` 2474), 217 (`inspected.zig` 3264-3275) and 220 (`inspected_run.zig` 109).

**Why it matters**

The check stops doing its job without any sign. Code that should be checked is skipped, and the line an exemption was written for is checked again. The list stays correct only as long as nobody edits the lines above the listed ones.

**How to reproduce**

This script checks that every entry names a file that exists, lies inside it, and points at more than blank lines or braces. Run it from the repository root. It printed the following on `5fc587cf51` and exited with 1:

```
cir_to_lir.zig:110-115: no such file under src/
src/eval/inspected.zig:2474-2474: only blank lines or braces
src/eval/inspected.zig:3264-3275: past the end (3255 lines)
src/eval/inspected_run.zig:109-109: only blank lines or braces
```

```sh
#!/bin/sh
# Run from a roc checkout. Every excluded range in src/build/check_runner.zig
# must name an existing file, lie inside it and hold more than blank lines or
# braces. Prints each range that does not; exits 1 if any.
ranges=$(grep -o '\.file = "[^"]*", \.start = [0-9]*, \.end = [0-9]*' src/build/check_runner.zig |
  sed 's/.*"\(.*\)", .start = \([0-9]*\), .end = \([0-9]*\)/\1 \2 \3/')
bad=0
while read -r name start end; do
  file=$(find src -name "$name" | head -1)
  if [ -z "$file" ]; then echo "$name:$start-$end: no such file under src/"; bad=1; continue; fi
  lines=$(wc -l < "$file")
  if [ "$end" -gt "$lines" ]; then echo "$file:$start-$end: past the end ($lines lines)"; bad=1; continue; fi
  if ! sed -n "${start},${end}p" "$file" | grep -q '[^[:space:]{}]'; then
    echo "$file:$start-$end: only blank lines or braces"; bad=1
  fi
done <<RANGES
$ranges
RANGES
exit $bad
```

**Environment**

- OS: Pop!_OS 24.04 LTS, x86_64
- Roc compiler version `release-fast-a932c654`
