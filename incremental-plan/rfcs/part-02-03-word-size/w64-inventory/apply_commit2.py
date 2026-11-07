"""Apply the rename PR's commit 2 mechanical edits from the TSVs.

Usage: python3 -I apply_commit2.py <worktree>

- `.w64` sites of kind word, piece or chunk (LirCodeGen.tsv,
  CallingConvention.tsv) become `widths.word_width`.
- Every call of the helpers that gain a width parameter (LirCodeGen-calls.tsv)
  gets one as its first argument: `widths.word_width` for word, narrow and
  chunk values, a raw `.w64` for the kinds later commits rename (64, scalar,
  size-8, mixed) and for calls in instruction-set code. Shared calls of the
  instruction set's `emitLoadImm` go to the driver's wrapper instead;
  instruction-set calls of it stay as they are.

Line numbers are the base's (ad3a5d2830). Any row whose line no longer
holds its code stops the script before anything is written.
"""
import csv
import os
import sys

root = sys.argv[1]
here = os.path.dirname(os.path.abspath(__file__))

WIDTH_HELPERS = {
    "emitLoadImm", "emitCmpImm", "emitMovRegReg", "emitCmpRegImm64",
    "emitCmpReg", "emitSaturatingSub", "emitAddImm", "emitSetCond",
}
WORD = "widths.word_width"
RAW = ".w64"
CALL_WIDTH = {
    "word": WORD, "narrow": WORD, "chunk": WORD,
    "64": RAW, "scalar": RAW, "size-8": RAW, "mixed": RAW, "isa": RAW,
}
SITE_KINDS = {"word", "piece", "chunk"}

errors = []


def rows(name):
    with open(os.path.join(here, name), newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f, delimiter="\t", quoting=csv.QUOTE_NONE))


def load(rel):
    with open(os.path.join(root, rel), encoding="utf-8") as f:
        return f.read().split("\n")


def apply_sites(lines, tsv):
    by_line = {}
    for r in rows(tsv):
        by_line.setdefault(int(r["line"]), []).append(r)
    count = 0
    for n, rs in sorted(by_line.items()):
        line = lines[n - 1]
        if line.strip() != rs[0]["code"].strip():
            errors.append(f"{tsv}:{n}: code changed: {line.strip()!r}")
            continue
        kinds = {r["kind"] for r in rs}
        if not kinds & SITE_KINDS:
            continue
        if len(kinds) != 1:
            errors.append(f"{tsv}:{n}: mixed kinds {sorted(kinds)}")
            continue
        if line.count(".w64") != len(rs):
            errors.append(f"{tsv}:{n}: {line.count('.w64')} .w64 for {len(rs)} rows")
            continue
        lines[n - 1] = line.replace(".w64", WORD)
        count += len(rs)
    return count


def apply_calls(lines):
    count = 0
    for r in rows("LirCodeGen-calls.tsv"):
        callee = r["callee"]
        if callee not in WIDTH_HELPERS:
            continue
        n = int(r["line"])
        line = lines[n - 1]
        needle = callee + "("
        if line.count(needle) != 1:
            errors.append(f"calls:{n}: {line.count(needle)} calls of {callee}")
            continue
        # The row's code is the whole call joined on one line; the part of it
        # on this line must match.
        on_line = line[line.index(needle):].rstrip()
        joined = r["code"]
        if not (joined.startswith(on_line.rstrip(";").rstrip(")").rstrip(",")) or on_line.startswith(joined)):
            errors.append(f"calls:{n}: code changed: {on_line!r} vs {joined!r}")
            continue
        kind = r["kind"]
        if kind not in CALL_WIDTH:
            errors.append(f"calls:{n}: unknown kind {kind}")
            continue
        width = CALL_WIDTH[kind]
        if callee == "emitLoadImm":
            if kind == "isa":
                continue
            old = "self.codegen.emitLoadImm("
            if line.count(old) != 1:
                errors.append(f"calls:{n}: emitLoadImm not called as {old}")
                continue
            lines[n - 1] = line.replace(old, f"self.emitLoadImm({width}, ")
        else:
            lines[n - 1] = line.replace(needle, f"{needle}{width}, ")
        count += 1
    return count


lir = load("src/backend/dev/LirCodeGen.zig")
cc = load("src/backend/dev/CallingConvention.zig")
n_sites = apply_sites(lir, "LirCodeGen.tsv")
n_cc = apply_sites(cc, "CallingConvention.tsv")
n_calls = apply_calls(lir)

if errors:
    print("\n".join(errors))
    sys.exit(1)

for rel, lines in (("src/backend/dev/LirCodeGen.zig", lir), ("src/backend/dev/CallingConvention.zig", cc)):
    with open(os.path.join(root, rel), "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
print(f"LirCodeGen sites {n_sites}, CallingConvention sites {n_cc}, helper calls {n_calls}")
