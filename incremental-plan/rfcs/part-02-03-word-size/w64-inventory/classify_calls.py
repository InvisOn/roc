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
]
if sys.argv[1:] == ["--callees"]:
    print(",".join(CALLEES))
    sys.exit(0)

ISA, W, B64, SCALAR, NARROW, CHUNK, S8 = "isa", "word", "64", "scalar", "narrow", "chunk", "size-8"

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
lines(W, 1948, 1950, 2072, 2274, 2374, 2412, 2462, 4515, 4527, 4620, 4629, 4775,
      4783, 8150, 8308, 8311, 8313, 8363, 8365, 8369, 8379, 8381, 8384, 8386, 8392,
      8394, 8405, 8407, 12555, 12731, 12733, 12736, 12840, 12898, 13181, 13610,
      13636, 13679, 13680, 14358, 14366, 14370, 14371, 14536, 14550, 14591, 14852,
      14855, 15698, 15711, 15936, 17206, 17208, 17210, 17217, 17248, 17250, 17255,
      17614, 17630, 17631, 17637, 17641, 17701, 17710, 18187, 18322, 21620, 21686,
      21688, 21694, 21696, 21699, 21715, 21734, 21762, 21897, 21964, 21975, 21991,
      21995, 22004, 22022, 22024, 22026, 22033, 22043, 22053, 22057, 22087)
# 64: U64 operands, i128/Dec halves, 64-bit masks, F64 bits
lines(B64, 2128, 2241, 2324, 3077, 5041, 5042, 6679, 6680, 6751, 7890, 7898, 8553,
      8555, 8566, 8568, 8587, 9305, 10450, 10452, 10466, 10491, 10500, 10501,
      10628, 10632, 10640, 10643, 10784, 10796, 10817, 10818, 10830, 10831, 10839,
      10841, 10843, 10876, 11268, 11270, 15346, 15383, 15544, 15546, 15725, 15726,
      15727, 15740, 15744, 15745, 15746, 15747, 16038, 16040, 16065, 16115, 16422,
      16632, 16636, 16678, 16681, 16727, 16750, 16752, 19511, 19513, 19674, 20310,
      20311, 20314, 20315, 20421, 20422, 20425, 20426, 20451, 20452, 10468, 10470,
      10472, 10493, 10495, 10497)
# scalar: a value whose width follows its layout (integers, immediates,
# discriminants, F32-or-F64 bits)
lines(SCALAR, 6437, 8261, 8266, 8269, 9086, 9099, 9179, 9186, 9188, 9320, 9345,
      10727, 10748, 11550, 11595, 11641, 11674, 13058, 13063, 15340, 15537, 16026,
      16057, 16718, 18306, 18517, 19669, 20541, 20616, 21185, 21226, 21229, 21303,
      21306, 21400, 9278, 9280, 9283, 9326, 9328, 9341, 9343, 11280)
# narrow: at most 32 bits on every target (Bools, flags, counts, u32 fields)
lines(NARROW, 3407, 3409, 3411, 3453, 3455, 3672, 4237, 4238, 4246, 4247, 5521,
      5553, 6038, 6286, 6425, 6427, 6443, 6681, 6693, 8995, 9019, 9149, 9150, 9577,
      9583, 9601, 10158, 10160, 10162, 10740, 15379, 16109, 16128, 16134, 16458,
      16770, 17733, 17897, 18316, 18318, 19581, 19586, 21064, 21692, 21711, 21713,
      21782, 21862)
# chunk: copy, fill and compare units
lines(CHUNK, 17214, 17215, 17242, 17253, 21839)
# size-8: chosen by an 8-byte size
lines(S8, 16756)

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
print("\n".join(out))
