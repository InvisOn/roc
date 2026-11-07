"""Classify the call sites of LirCodeGen's implicit-width helpers.

Usage:
  python3 -I w64_sites.py LirCodeGen.zig --calls <CALLEES> > calls.tsv
  python3 -I classify_calls.py calls.tsv
with CALLEES as printed by `python3 -I classify_calls.py --callees`.

Output TSV: line, function, callee, context, kind, code. The kind is that
of the value the call works on (README.md defines the kinds; `narrow` is
added here). Sites in `test` blocks are left out. A shared site without a
kind stops the script, and so do a line given two kinds and an entry that
matches no site.
"""
import collections
import sys

# Helpers whose width the caller's value decides. Left out on purpose:
# materializeVectorConstant, loadAndMaskDiscriminant and storeDiscriminant,
# whose callers pass no width-dependent value (their own .w64 and
# emitLoadImm sites are listed).
CALLEES = [
    "emitLoadImm", "emitCmpImm", "emitCmpRegImm64", "emitSetCond", "emitAddImm",
    "emitSaturatingSub", "emitLeaStack", "emitAddPtrImmAny", "emitAddUsizeImm",
    "emitSubStackPtr", "emitAddStackPtr", "emitTailBlockAddress",
    "emitMovRegReg", "emitCmpReg",
]
if sys.argv[1:] == ["--callees"]:
    print(",".join(CALLEES))
    sys.exit(0)

ISA, W, B64, SCALAR, NARROW, CHUNK, S8, MIXED = (
    "isa", "word", "64", "scalar", "narrow", "chunk", "size-8", "mixed")

# Address helpers: every call works on an address.
BY_CALLEE = {c: W for c in ("emitLeaStack", "emitAddPtrImmAny", "emitAddUsizeImm",
                            "emitSubStackPtr", "emitAddStackPtr", "emitTailBlockAddress")}

LINE = {}
seen = collections.Counter()
def lines(kind, *ns):
    for n in ns:
        seen[n] += 1
        LINE[n] = kind

# word: RocStr/RocList fields, pointers, sizes, counts, addresses
lines(W, 1949, 1951, 2073, 2275, 2375, 2413, 2463, 4516, 4528, 4621, 4630, 4776,
      4784, 8151, 8309, 8312, 8314, 8364, 8366, 8370, 8380, 8382, 8385, 8387, 8393,
      8395, 8406, 8408, 12556, 12732, 12734, 12737, 12841, 12899, 13182, 13611,
      13637, 13680, 13681, 14359, 14367, 14371, 14372, 14537, 14551, 14592, 14853,
      14856, 15699, 15712, 15937, 17207, 17209, 17211, 17218, 17249, 17251, 17256,
      17615, 17631, 17632, 17638, 17642, 17702, 17711, 18188, 18323, 21621, 21687,
      21689, 21695, 21697, 21700, 21716, 21735, 21763, 21898, 21965, 21976, 21992,
      21996, 22005, 22023, 22025, 22027, 22034, 22044, 22054, 22058, 22088)
# 64: U64 operands, i128/Dec halves, 64-bit masks, F64 bits
lines(B64, 2129, 2242, 2325, 3078, 5042, 5043, 6680, 6681, 6752, 7891, 7899, 8554,
      8556, 8567, 8569, 8588, 9306, 10451, 10453, 10467, 10492, 10501, 10502,
      10629, 10633, 10641, 10644, 10785, 10797, 10818, 10819, 10831, 10832, 10840,
      10842, 10844, 10877, 11269, 11271, 15347, 15384, 15545, 15547, 15726, 15727,
      15728, 15741, 15745, 15746, 15747, 15748, 16039, 16041, 16066, 16116, 16423,
      16633, 16637, 16679, 16682, 16728, 16751, 16753, 19512, 19514, 19675, 20311,
      20312, 20315, 20316, 20422, 20423, 20426, 20427, 20452, 20453, 10469, 10471,
      10473, 10494, 10496, 10498)
# scalar: a value whose width follows its layout (integers, immediates,
# discriminants, F32-or-F64 bits)
lines(SCALAR, 6438, 8262, 8267, 8270, 9087, 9100, 9180, 9187, 9189, 9321, 9346,
      10728, 10749, 11551, 11596, 11642, 11675, 13059, 13064, 15341, 15538, 16027,
      16058, 16719, 18307, 18518, 19670, 20542, 20617, 21186, 21227, 21230, 21304,
      21307, 21401, 9279, 9281, 9284, 9327, 9329, 9342, 9344, 11281)
# narrow: at most 32 bits on every target (Bools, flags, counts, u32 fields)
lines(NARROW, 3408, 3410, 3412, 3454, 3456, 3673, 4238, 4239, 4247, 4248,
      5554, 6287, 6426, 6428, 6444, 6682, 6694, 8996, 9020, 9150, 9151, 9578,
      9584, 9602, 10159, 10161, 10163, 10741, 15380, 16110, 16129, 16135, 16459,
      16771, 17734, 17898, 18317, 18319, 19582, 19587, 21065, 21693, 21712, 21714,
      21783, 21863)
# emitMovRegReg and emitCmpReg: a whole-register move or compare (always .w64)
lines(W, 1592, 4861, 8415, 12545, 17538, 17716, 18124, 21634, 21643, 21660, 21699,
      21736, 21739, 21741, 21764, 21767, 21772, 21775, 21860, 21892, 21895, 21911,
      21927)
lines(B64, 2131, 2245,              # U64 index (num_from_le_bytes, List.get)
      10626, 10848, 10873, 11272)   # popcount of a U64, i128 halves
lines(SCALAR, 8268,                 # F32 or F64 bits
      9084, 10723, 11593, 15337, 21225, 21302)
lines(NARROW, 6284, 6441,           # SIMD shift counts
      10438)                        # c_int overflow flag
lines(CHUNK, 21841)                 # emitCompareLiteralAtPtr's chunk
lines(MIXED, 9307)                  # emitCmpRegImm64's body: its callers are listed

# chunk: copy, fill and compare units
lines(CHUNK, 17215, 17216, 17243, 17254, 21840)
# size-8: chosen by an 8-byte size
lines(S8, 16757)

twice = [n for n, c in seen.items() if c > 1]
if twice:
    sys.exit(f"lines set twice: {sorted(twice)}")

out = []
used = set()
for row in open(sys.argv[1], encoding="utf-8"):
    line, fn, callee, ctx, code = row.rstrip("\n").split("\t")
    if fn == "test":
        continue
    n = int(line)
    if ctx != "shared":
        kind = ISA
    elif callee in BY_CALLEE:
        kind = BY_CALLEE[callee]
    elif n in LINE:
        kind = LINE[n]
        used.add(n)
    else:
        sys.exit(f"unclassified: {line} {fn} {callee}: {code}")
    out.append("\t".join([line, fn, callee, ctx, kind, code]))
unused = sorted(set(LINE) - used)
if unused:
    sys.exit(f"entries that match no shared site: {unused}")
print("line\tfunction\tcallee\tcontext\tkind\tcode")
print("\n".join(out))
