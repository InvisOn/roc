# Draft: `build.zig`'s pattern checks exclude lines by number, and the numbers have gone stale

> **Upstream or ours:** Upstream. The defect is in upstream's code and does not depend on our arm32 work.

> **Relevance to our arm32 work:** Our changes move lines in the checked files, which shifts the exemptions onto the wrong lines and makes the check fail or pass for the wrong reason.

Not filed. For roc-lang/roc.

| | |
|---|---|
| Still an issue? | Yes: of the three `inspected.zig` ranges in `excluded_ranges`, two now point at unrelated lines (2474 is a blank line; 3264-3275 is allocation code, not the dylib-path conversion the comment describes). |
| Already upstream? | None found (searched issues and PRs, 2026-10-02). |
| Fix on our reference branch | Not fixed by us. |
| Before filing | Nothing. |

Checked 2026-10-02 against upstream `main` at `d16a6598e4`.

---

**Title:** `build.zig`'s pattern checks exclude lines by number, and the numbers have gone stale

**What happens**

`build.zig` has `excluded_ranges` entries like `.{ .file = "inspected.zig", .start = 3264, .end = 3275 }` that exempt specific lines from a forbidden-pattern check. When the file changes, the numbers keep pointing at the old positions: the exemption silently moves to unrelated code, and the line it was meant for is no longer exempt (or the check no longer covers what it should).

**Why it matters**

The check stops doing its job without any sign of it: lines that should be checked are exempt, and the line the exemption was written for is checked again. It only stays correct as long as nobody edits the file above those lines.

**How to reproduce**

```sh
grep -n -A24 'excluded_ranges = ' build.zig
sed -n '2474p;3264,3275p' src/eval/inspected.zig
```

The first command shows the ranges and the comment saying what each allows; the second shows what those lines hold now (a blank line, and allocation code).

**Environment**

- OS: Pop!_OS 24.04 LTS, x86_64
- Roc compiler version `release-fast-a932c654`
