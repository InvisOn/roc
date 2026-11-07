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
lines(B64, 3076, 3079, 3133, 3224, 4178, 4208, 6700, 6747, 8557, 8570, 8590,
      8597, 8598, 8605, 8606, 8901, 9541, 9804, 9818, 10365, 10373, 10383, 10401,
      10430, 10441, 10531, 10540, 10557, 10565, 10602, 10609, 10836, 11336, 11530,
      15548, 16042, 16651, 16666, 16729, 16754, 19320, 19515, 19827, 20301, 20305,
      20412, 20416, 20455, 20470, 18352, 18365)
# word: a word stride or size written as 8
lines(W, 3527,              # RocStr word copy, `word * 8`
      17444, 17453,         # emitLocalArray: one word per local
      17715,                # CompositionEntry operands (usize)
      17725, 17739,         # composition operand words
      17900,                # VariantInput payload pointers
      17953,                # dictionary method table (pointers)
      19837)                # RocStr/RocList second word at `+ 8`
# piece: register-sized argument and return pieces, 8-byte stack slots
lines(PIECE, 14286, 14904, 15508, 15522, 15532, 19265, 19332, 19454, 19502, 19729,
      19845, 19862, 19934, 19947, 20193, 20198, 20205, 20210, 22586)
lines(CHUNK, 17182, 17190)  # copyChunked's 8-byte steps
lines(SCALAR, 13038)        # bound for an 8-byte discriminant read (see 13051)
lines(NARROW, 3413)         # third u32 of a layout argument struct
lines(BITS, 361, 5070, 5078, 5091, 9869, 11612, 13057, 13335, 13345, 13585, 16770,
      21838)
lines(COMPILER, 13961, 14197, 14455, 19753, 21606)

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
