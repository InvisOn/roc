"""Apply the rename PR's commit 3 mechanical edits from the TSVs.

Usage: python3 -I apply_commit3.py <worktree> <base rev>

- `.w64` sites of kind 64 or size-8 (LirCodeGen.tsv) and the raw `.w64`
  that commit 2 gave the helper calls of kind 64 or size-8
  (LirCodeGen-calls.tsv) become `widths.wide64_width`.
- Builder arguments of kind 64 (LirCodeGen-args.tsv) call the `…Wide64`
  method: `addRegArg` -> `addRegArgWide64`, likewise `addMemArg`,
  `addImmArg`. Other callees (`addWordArg`) are listed, not edited.

Line numbers are the base's. A base line is mapped to the working tree
through `git diff -U0 <base>`, as in apply_commit2_literals.py, and must
equal the base line once commit 2's renames are normalized away. A line is
edited only when its raw `.w64` count equals its commit-3 rows and it has
no rows of other `.w64` kinds; any other line is listed and nothing is
written.
"""
import csv
import os
import re
import subprocess
import sys
from collections import defaultdict

root, base_rev = sys.argv[1], sys.argv[2]
here = os.path.dirname(os.path.abspath(__file__))
rel = "src/backend/dev/LirCodeGen.zig"
WIDE = "widths.wide64_width"
KINDS = {"64", "size-8"}
WIDTH_HELPERS = {
    "emitLoadImm", "emitCmpImm", "emitMovRegReg", "emitCmpRegImm64",
    "emitCmpReg", "emitSaturatingSub", "emitAddImm", "emitSetCond",
}
ARG_METHODS = {"addRegArg", "addMemArg", "addImmArg"}


def git(*args):
    return subprocess.run(["git", "-C", root, *args], check=True, capture_output=True, text=True).stdout


def rows(name):
    with open(os.path.join(here, name), newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f, delimiter="\t", quoting=csv.QUOTE_NONE))


base = git("show", f"{base_rev}:{rel}").split("\n")
with open(os.path.join(root, rel), encoding="utf-8") as f:
    cur = f.read().split("\n")

hunks = []
for m in re.finditer(r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@", git("diff", "-U0", base_rev, "--", rel), re.M):
    o, oc, n, nc = int(m[1]), int(m[2] or 1), int(m[3]), int(m[4] or 1)
    if oc == 0:
        o += 1
    hunks.append((o, oc, n, nc))


def map_line(b):
    shift = 0
    for o, oc, n, nc in hunks:
        if oc and o <= b < o + oc:
            return n + (b - o) if oc == nc else None
        if o + oc <= b or (oc == 0 and o <= b):
            shift += nc - oc
    return b + shift


def norm(s):
    s = s.replace("widths.word_width", ".w64")
    s = s.replace("self.emitLoadImm(.w64, ", "self.codegen.emitLoadImm(")
    s = re.sub(r"(emit\w+)\(\.w64, ", r"\1(", s)
    return s


errors, manual = [], []
mine = defaultdict(int)    # base line -> commit-3 `.w64`s
others = defaultdict(int)  # base line -> `.w64`s of other kinds
for r in rows("LirCodeGen.tsv"):
    n = int(r["line"])
    if r["kind"] in KINDS:
        mine[n] += 1
    elif r["kind"] not in {"word", "piece", "chunk"}:  # still a raw `.w64`
        others[n] += 1
for r in rows("LirCodeGen-calls.tsv"):
    if r["callee"] not in WIDTH_HELPERS:
        continue
    n = int(r["line"])
    if r["kind"] in KINDS:
        mine[n] += 1
    elif r["kind"] in {"scalar", "mixed"} or (r["kind"] == "isa" and r["callee"] != "emitLoadImm"):
        others[n] += 1

# Calls commit 2 already gave the helper's own width parameter (D2).
DONE = {9306: "emitCmpRegImm64 passes its `width` to emitLoadImm"}

n_sites = 0
for b in sorted(mine):
    if b in DONE:
        continue
    c = map_line(b)
    if c is None:
        errors.append(f"{b}: inside a hunk that changed its size")
        continue
    line = cur[c - 1]
    if norm(line) != norm(base[b - 1]):
        errors.append(f"{b}->{c}: line differs from base: {line.strip()!r}")
        continue
    raw = len(re.findall(r"(?<![\w.])\.w64\b", line))
    if others[b] or raw != mine[b]:
        manual.append(f"{b}->{c}: {raw} raw .w64, {mine[b]} commit-3, {others[b]} other: {line.strip()}")
        continue
    cur[c - 1] = re.sub(r"(?<![\w.])\.w64\b", WIDE, line)
    n_sites += mine[b]

n_args = 0
for r in rows("LirCodeGen-args.tsv"):
    if r["kind"] != "64":
        continue
    b, callee = int(r["line"]), r["callee"]
    c = map_line(b)
    if c is None:
        errors.append(f"args:{b}: inside a hunk that changed its size")
        continue
    line = cur[c - 1]
    if callee not in ARG_METHODS:
        manual.append(f"args:{b}->{c}: {callee}: {line.strip()}")
        continue
    needle = f".{callee}("
    if line.count(needle) != 1:
        errors.append(f"args:{b}->{c}: {line.count(needle)} of {needle}: {line.strip()!r}")
        continue
    cur[c - 1] = line.replace(needle, f".{callee}Wide64(")
    n_args += 1

if errors:
    print("\n".join(errors))
    sys.exit(1)
with open(os.path.join(root, rel), "w", encoding="utf-8") as f:
    f.write("\n".join(cur))
print(f"{n_sites} sites, {n_args} arguments")
if manual:
    print("by hand:")
    print("\n".join(manual))
