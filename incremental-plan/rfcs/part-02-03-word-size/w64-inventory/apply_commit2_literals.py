"""Apply the rename PR's commit 2 literal edits: word, piece and chunk 8s.

Usage: python3 -I apply_commit2_literals.py <worktree>

Run after apply_commit2.py and the helper edits. Each edit names a base
(HEAD) line of LirCodeGen.zig, a substring and its replacement. The base
line is mapped to the working tree through `git diff -U0 HEAD`: a line
outside every hunk shifts by the hunks before it, a line inside a hunk with
as many new lines as old maps by position. The mapped line must equal the
base line once `.w64`, `widths.word_width` and the emitLoadImm wrapper are
normalized away, and must hold the substring exactly once; otherwise the
script stops before writing anything.

Rows are LirCodeGen-eights.tsv and LirCodeGen-sizes.tsv's word, piece and
chunk rows (not the 8-byte gate at 352, which stays; not 21818 and 21829,
edited by hand), plus six lines the inventory does not list: the third word
of a RocStr or RocList at 19838 (`+ 16`), and the chunk steps of copyLoop
(17215, 17216), fillMem (17254) and fillSmall (17271, 17272).
"""
import os
import re
import subprocess
import sys

root = sys.argv[1]
rel = "src/backend/dev/LirCodeGen.zig"
P = "target_ptr_size"
CEIL = f"+ {P} - 1) / {P}"

EDITS = [
    # LirCodeGen-eights.tsv
    (3527, "word * 8", f"word * {P}"),
    (14286, "@as(i32, ri) * 8", f"@as(i32, ri) * {P}"),
    (14902, "Pad by 8 bytes so register pieces loaded as full 64-bit words", "Pad by a word so register pieces loaded as full words"),
    (14904, "total_args_size + 8", f"total_args_size + {P}"),
    (15508, "@as(i32, ri) * 8", f"@as(i32, ri) * {P}"),
    (15522, "@as(i32, ri) * 8", f"@as(i32, ri) * {P}"),
    (15532, "@as(i32, ri) * 8", f"@as(i32, ri) * {P}"),
    (17182, "while (copied + 8 <= size) : (copied += 8)", f"while (copied + {P} <= size) : (copied += {P})"),
    (17190, "size - 8", f"size - {P}"),
    (17444, "@max(locals.len, 1) * 8", f"@max(locals.len, 1) * {P}"),
    (17453, "i * 8", f"i * {P}"),
    (17715, "(i + 1) * 8", f"(i + 1) * {P}"),
    (17725, "@max(operands.items.len, 1) * 8", f"@max(operands.items.len, 1) * {P}"),
    (17739, "i * 8", f"i * {P}"),
    (17900, "next * 8", f"next * {P}"),
    (17953, "d.index * 8", f"d.index * {P}"),
    (19265, "max_internal_return_words * 8", f"max_internal_return_words * {P}"),
    (19332, "stack_offset + 8", f"stack_offset + {P}"),
    (19454, "@as(u32, nr) * 8", f"@as(u32, nr) * {P}"),
    (19502, "@as(u32, info.num_regs) * 8", f"@as(u32, info.num_regs) * {P}"),
    (19729, "@as(i32, nr) * 8", f"@as(i32, nr) * {P}"),
    (19837, "frozen.stack_offset + 8", f"frozen.stack_offset + {P}"),
    (19838, "frozen.stack_offset + 16", f"frozen.stack_offset + 2 * {P}"),
    (19845, "@as(i32, ri) * 8", f"@as(i32, ri) * {P}"),
    (19862, "@as(i32, info.num_regs) * 8", f"@as(i32, info.num_regs) * {P}"),
    (19934, "@as(i32, ri) * 8", f"@as(i32, ri) * {P}"),
    (19947, "@as(i32, arg_index - max_arg_regs) * 8", f"@as(i32, arg_index - max_arg_regs) * {P}"),
    (20193, "@as(u32, num_regs) * 8", f"@as(u32, num_regs) * {P}"),
    (20198, "@as(i32, ri) * 8", f"@as(i32, ri) * {P}"),
    (20205, "@as(u32, num_regs) * 8", f"@as(u32, num_regs) * {P}"),
    (20210, "@as(i32, num_regs) * 8", f"@as(i32, num_regs) * {P}"),
    (22586, "calcParamRegCount(layout_idx)) * 8", f"calcParamRegCount(layout_idx)) * {P}"),
    # LirCodeGen-sizes.tsv
    (15462, "size <= 8", f"size <= {P}"),
    (15463, "+ 7) / 8", CEIL),
    (17148, "size == 8", f"size == {P}"),
    (17153, "size < 8", f"size < {P}"),
    (17201, "size >= 8", f"size >= {P}"),
    (17211, "size / 8", f"size / {P}"),
    (17223, "size % 8", f"size % {P}"),
    (17251, "size / 8", f"size / {P}"),
    (17259, "size % 8", f"size % {P}"),
    (17269, "remaining >= 8", f"remaining >= {P}"),
    (19371, "size_align.size > 8", f"size_align.size > {P}"),
    (19373, "+ 7) / 8", CEIL),
    (19631, ".value_size = .qword", f".value_size = ValueSize.fromByteCount({P})"),
    (19639, ".value_size = .qword", f".value_size = ValueSize.fromByteCount({P})"),
    (20479, "size_align.size <= 8", f"size_align.size <= {P}"),
    (20498, "+ 7) / 8", CEIL),
    (22818, "alignForward(u32, raw_size, 8)", f"alignForward(u32, raw_size, {P})"),
    (22823, "if (remaining >= 8) 8 else", f"if (remaining >= {P}) {P} else"),
    (22841, "alignForward(u32, raw_size, 8)", f"alignForward(u32, raw_size, {P})"),
    # Not in the inventory: the same loops' chunk steps.
    (17215, "emitAddImm(widths.word_width, src, src, 8)", f"emitAddImm(widths.word_width, src, src, {P})"),
    (17216, "emitAddImm(widths.word_width, dst, dst, 8)", f"emitAddImm(widths.word_width, dst, dst, {P})"),
    (17254, "emitAddImm(widths.word_width, dst, dst, 8)", f"emitAddImm(widths.word_width, dst, dst, {P})"),
    (17271, "off += 8", f"off += {P}"),
    (17272, "remaining -= 8", f"remaining -= {P}"),
]


def git(*args):
    return subprocess.run(["git", "-C", root, *args], check=True, capture_output=True, text=True).stdout


base = git("show", f"HEAD:{rel}").split("\n")
with open(os.path.join(root, rel), encoding="utf-8") as f:
    cur = f.read().split("\n")

hunks = []
for m in re.finditer(r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@", git("diff", "-U0", "HEAD", "--", rel), re.M):
    o, oc, n, nc = int(m[1]), int(m[2] or 1), int(m[3]), int(m[4] or 1)
    if oc == 0:
        o += 1  # a pure insertion is reported after line o
    hunks.append((o, oc, n, nc))


def map_line(b):
    shift = 0
    for o, oc, n, nc in hunks:
        if oc and o <= b < o + oc:
            if oc != nc:
                return None
            return n + (b - o)
        if o + oc <= b or (oc == 0 and o <= b):
            shift += nc - oc
    return b + shift


def norm(s):
    s = s.replace("widths.word_width", ".w64")
    s = s.replace("self.emitLoadImm(.w64, ", "self.codegen.emitLoadImm(")
    s = re.sub(r"(emit\w+)\(\.w64, ", r"\1(", s)
    return s


errors = []
for b, old, new in EDITS:
    c = map_line(b)
    if c is None:
        errors.append(f"{b}: inside a hunk that changed its size")
        continue
    line = cur[c - 1]
    if norm(line) != norm(base[b - 1]):
        errors.append(f"{b}->{c}: line differs from base: {line.strip()!r}")
        continue
    if line.count(old) != 1:
        errors.append(f"{b}->{c}: {line.count(old)} of {old!r} in {line.strip()!r}")
        continue
    cur[c - 1] = line.replace(old, new)

if errors:
    print("\n".join(errors))
    sys.exit(1)
with open(os.path.join(root, rel), "w", encoding="utf-8") as f:
    f.write("\n".join(cur))
print(f"{len(EDITS)} literal edits")
