# Draft: The build's forbidden-pattern check excludes lines by number, and the numbers have gone stale

> **Upstream or ours:** Upstream. The defect is in upstream's code and does not depend on our arm32 work.

> **Relevance to our arm32 work:** Our changes move lines in the checked files, which shifts the exemptions onto the wrong lines and makes the check fail or pass for the wrong reason.

Not filed. For roc-lang/roc.

| | |
|---|---|
| Still an issue? | Yes (2026-10-20, `5fc587cf51`, checked by the script below): the ranges are now in `src/build/check_runner.zig`, and four entries are stale: `cir_to_lir.zig` no longer exists; `inspected.zig` 2474 is a lone `}` and 3264-3275 is past the end of its 3255 lines; `inspected_run.zig` 109 is blank. |
| Already upstream? | None found (searched issues and PRs, 2026-10-02). |
| Fix on our reference branch | Not fixed by us. |
| Before filing | Nothing. |

Checked 2026-10-02 against upstream `main` at `d16a6598e4`.

---

**Title:** The build's forbidden-pattern check excludes lines by number, and the numbers have gone stale

**What happens**

`src/build/check_runner.zig` has `excluded_ranges` entries like `.{ .file = "inspected.zig", .start = 3264, .end = 3275 }` that exempt specific lines from a forbidden-pattern check. When the file changes, the numbers keep pointing at the old positions: the exemption silently moves to unrelated code, and the line it was meant for is no longer exempt (or the check no longer covers what it should).

**Where** (upstream `main` at `5fc587cf51`)

- `src/build/check_runner.zig:193-225`, `excluded_ranges`; the `inspected.zig` entries are at lines 211 (226-232), 214 (2474) and 217 (3264-3275).
- `src/eval/inspected.zig` is 3255 lines: 2474 is a lone `}` and 3264-3275 is past the end of the file.
- `check_runner.zig:208` names `cir_to_lir.zig`, which no longer exists; `:216` points at `inspected_run.zig:109`, a blank line.
- Used at `check_runner.zig:231`.

**Why it matters**

The check stops doing its job without any sign of it: lines that should be checked are exempt, and the line the exemption was written for is checked again. It only stays correct as long as nobody edits the file above those lines.

**How to reproduce**

```sh
grep -n -A32 'excluded_ranges = ' src/build/check_runner.zig
sed -n '2474p;3264,3275p' src/eval/inspected.zig; wc -l src/eval/inspected.zig
```

The first command shows the ranges and the comment saying what each allows; the second shows what those lines hold now: a lone `}`, and nothing (the file has 3255 lines).

**A check that fails** (run on upstream `main` at `5fc587cf51`): every excluded range should name an existing file, lie inside it, and hold more than blank lines or braces. Run from the repository root:

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

Output on `5fc587cf51` (exit 1): four of the entries are stale, not two.

```
cir_to_lir.zig:110-115: no such file under src/
src/eval/inspected.zig:2474-2474: only blank lines or braces
src/eval/inspected.zig:3264-3275: past the end (3255 lines)
src/eval/inspected_run.zig:109-109: only blank lines or braces
```

**Environment**

- OS: Pop!_OS 24.04 LTS, x86_64
- Roc compiler version `release-fast-a932c654`
