"""Classify LirCodeGen's literal 8s used as offsets, strides and sizes.

Usage:
  python3 -I w64_sites.py LirCodeGen.zig --pattern '[-+*] 8\\b|\\b8 \\*' > eights.tsv
  python3 -I classify_offsets.py eights.tsv

Output TSV: line, function, context, kind, code. Kinds as in README.md, plus
`bits` (a byte count times 8 bits, no word assumption) and `compiler` (a
buffer for the compiler's own data, not target memory). Sites in `test`
blocks are left out. A shared line without a kind stops the script, and so do
a line given two kinds and an entry that matches no line.
"""
import collections
import sys

W, B64, PIECE, CHUNK, SCALAR, NARROW, BITS, COMPILER = (
    "word", "64", "piece", "chunk", "scalar", "narrow", "bits", "compiler")

LINE = {}
seen = collections.Counter()
def lines(kind, *ns):
    for n in ns:
        seen[n] += 1
        LINE[n] = kind

# 64: `+ 8` to the high half of a 16-byte value (i128, Dec, a SIMD vector), or
# the stride of ListOpRequest.n, a [3]u64
lines(B64, 3075, 3078, 3132, 3223, 4177, 4207, 6699, 6746, 8556, 8569, 8589,
      8596, 8597, 8604, 8605, 8900, 9540, 9803, 9817, 10364, 10372, 10382, 10400,
      10429, 10440, 10530, 10539, 10556, 10564, 10601, 10608, 10835, 11335, 11529,
      15547, 16041, 16650, 16665, 16728, 16753, 19319, 19514, 19826, 20300, 20304,
      20411, 20415, 20454, 20469, 18351, 18364)
# word: a word stride or size written as 8
lines(W, 3526,              # RocStr word copy, `word * 8`
      17443, 17452,         # emitLocalArray: one word per local
      17714,                # CompositionEntry operands (usize)
      17724, 17738,         # composition operand words
      17899,                # VariantInput payload pointers
      17952,                # dictionary method table (pointers)
      19836)                # RocStr/RocList second word at `+ 8`
# piece: register-sized argument and return pieces, 8-byte stack slots
lines(PIECE, 14285, 14903, 15507, 15521, 15531, 19264, 19331, 19453, 19501, 19728,
      19844, 19861, 19933, 19946, 20192, 20197, 20204, 20209, 22573)
lines(CHUNK, 17181, 17189)  # copyChunked's 8-byte steps
lines(SCALAR, 13037)        # bound for an 8-byte discriminant read (see 13051)
lines(NARROW, 3412)         # third u32 of a layout argument struct
lines(BITS, 360, 5069, 5077, 5090, 9868, 11611, 13056, 13334, 13344, 13584, 16769,
      21837)
lines(COMPILER, 13960, 14196, 14454, 19752, 21605)

twice = [n for n, c in seen.items() if c > 1]
if twice:
    sys.exit(f"lines set twice: {sorted(twice)}")

out = []
used = set()
for row in open(sys.argv[1], encoding="utf-8"):
    line, fn, _, ctx, code = row.rstrip("\n").split("\t")
    if fn == "test":
        continue
    n = int(line)
    if ctx != "shared":
        kind = "isa"
    elif n in LINE:
        kind = LINE[n]
        used.add(n)
    else:
        sys.exit(f"unclassified: {line} {fn}: {code}")
    out.append("\t".join([line, fn, ctx, kind, code]))
unused = sorted(set(LINE) - used)
if unused:
    sys.exit(f"entries that match no shared line: {unused}")
print("\n".join(out))
