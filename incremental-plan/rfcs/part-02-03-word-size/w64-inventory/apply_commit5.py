"""Apply the rename PR's commit 5 mechanical edits from the TSVs.

Usage: python3 -I apply_commit5.py <worktree> <base rev> [--dry-run]

- `.w64` sites of kind scalar (LirCodeGen.tsv) and the raw `.w64` that
  commit 2 gave the helper calls of kind scalar (LirCodeGen-calls.tsv)
  become `widths.scalar_width`.
- Register bit counts (LirCodeGen-sizes.tsv, kind reg-bits) use
  `widths.scalar_bits`: `64 - n` becomes `widths.scalar_bits - n`, `< 64`
  becomes `< widths.scalar_bits`, and the shift tables' `56`, `48`, `32`
  become `widths.scalar_bits - 8`, `- 16`, `- 32`.

Line numbers are the base's. A base line is mapped to the working tree
through `git diff -U0 <base>`, and must equal the base line once commits 2
to 4's renames are normalized away. A `.w64` line is edited only when its
raw `.w64` count equals its scalar rows and it has no instruction-set rows;
a reg-bits line only when exactly one of the shapes above matches it once.
Any other line is listed, and with errors nothing is written.

Not applied here: the three scalar register-size checks in the sizes and
eights TSVs (base 9979, 13038, 13056). Commit 5's review (R1) renamed them
by hand to `> widths.scalar_bits`, `+ widths.scalar_bits / 8` and
`disc_size * 8 < widths.scalar_bits`. The value-model `.qword` rows stay
(plan D6).
"""
import csv
import os
import re
import subprocess
import sys
from collections import defaultdict

root, base_rev = sys.argv[1], sys.argv[2]
dry_run = "--dry-run" in sys.argv[3:]
here = os.path.dirname(os.path.abspath(__file__))
rel = "src/backend/dev/LirCodeGen.zig"
SCALAR = "widths.scalar_width"
BITS = "widths.scalar_bits"
WIDTH_HELPERS = {
    "emitLoadImm", "emitCmpImm", "emitMovRegReg", "emitCmpRegImm64",
    "emitCmpReg", "emitSaturatingSub", "emitAddImm", "emitSetCond",
}


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
    s = s.replace("widths.word_width", ".w64").replace("widths.wide64_width", ".w64")
    s = re.sub(r"\.add(Reg|Mem|Imm)ArgWide64\(", r".add\1Arg(", s)
    s = s.replace("self.emitLoadImm(.w64, ", "self.codegen.emitLoadImm(")
    s = re.sub(r"(emit\w+)\(\.w64, ", r"\1(", s)
    return s


errors, manual = [], []
mine = defaultdict(int)    # base line -> scalar `.w64`s
others = defaultdict(int)  # base line -> instruction-set `.w64`s
for r in rows("LirCodeGen.tsv"):
    n = int(r["line"])
    if r["kind"] == "scalar":
        mine[n] += 1
    elif r["kind"] == "isa":
        others[n] += 1
for r in rows("LirCodeGen-calls.tsv"):
    if r["callee"] not in WIDTH_HELPERS:
        continue
    n = int(r["line"])
    if r["kind"] == "scalar":
        mine[n] += 1
    elif r["kind"] == "isa" and r["callee"] != "emitLoadImm":
        others[n] += 1


def current(b, tag=""):
    c = map_line(b)
    if c is None:
        errors.append(f"{tag}{b}: inside a hunk that changed its size")
        return None, None
    line = cur[c - 1]
    if norm(line) != norm(base[b - 1]):
        errors.append(f"{tag}{b}->{c}: line differs from base: {line.strip()!r}")
        return None, None
    return c, line


n_sites = 0
for b in sorted(mine):
    c, line = current(b)
    if c is None:
        continue
    raw = len(re.findall(r"(?<![\w.])\.w64\b", line))
    if others[b] or raw != mine[b]:
        manual.append(f"{b}->{c}: {raw} raw .w64, {mine[b]} scalar, {others[b]} isa: {line.strip()}")
        continue
    cur[c - 1] = re.sub(r"(?<![\w.])\.w64\b", SCALAR, line)
    n_sites += mine[b]

# Register bit counts. Each shape matches the 64 (or 56/48/32) that is a
# register's bit count, and must match exactly once on its line.
SHAPES = [
    (re.compile(r"(?<![\w.])64 - (?=[\w@(])"), BITS + " - "),
    (re.compile(r"< 64\)"), f"< {BITS})"),
    (re.compile(r"=> 56,"), f"=> {BITS} - 8,"),
    (re.compile(r"=> 48,"), f"=> {BITS} - 16,"),
    (re.compile(r"=> 32,"), f"=> {BITS} - 32,"),
]
n_bits = 0
for r in rows("LirCodeGen-sizes.tsv"):
    if r["kind"] != "reg-bits":
        continue
    b = int(r["line"])
    c, line = current(b, "bits:")
    if c is None:
        continue
    hits = [(pat, rep) for pat, rep in SHAPES if pat.search(line)]
    if len(hits) != 1 or len(hits[0][0].findall(line)) != 1:
        manual.append(f"bits:{b}->{c}: {len(hits)} shapes: {line.strip()}")
        continue
    pat, rep = hits[0]
    cur[c - 1] = pat.sub(rep, line)
    n_bits += 1

if errors:
    print("\n".join(errors))
    sys.exit(1)
if not dry_run:
    with open(os.path.join(root, rel), "w", encoding="utf-8") as f:
        f.write("\n".join(cur))
print(f"{n_sites} sites, {n_bits} bit counts" + (" (dry run, nothing written)" if dry_run else ""))
if manual:
    print("by hand:")
    print("\n".join(manual))
