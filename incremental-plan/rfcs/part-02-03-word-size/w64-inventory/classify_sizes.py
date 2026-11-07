"""Classify LirCodeGen's size and bit-count literals that the `.w64`, call and
`± 8` lists do not cover: compares with 8, `8 =>` arms, `/ 8` and `% 8`,
`alignForward(.., 8)`, `ValueSize.qword`, and register bit counts (`64 -`,
compares with 64, shift tables of 56, 48 and 32).

Usage:
  python3 -I w64_sites.py LirCodeGen.zig --pattern "$(python3 -I classify_sizes.py --pattern)" > sizes.tsv
  python3 -I classify_sizes.py sizes.tsv

Output TSV: line, function, context, kind, code. Kinds as in README.md, plus
`reg-bits` (a general register's bit count, 64, as a shift amount or a bound:
sign and zero extension by shifts, shift-count masks) and `neutral` (the
same at either word: type bit widths, SIMD lane bytes, a type's bounds).
Sites in `test` blocks are left out. A shared line without a kind stops the
script, and so do a line given two kinds and an entry that matches no line.
"""
import collections
import sys

PATTERN = (r"(==|!=|<=|>=|<|>) 8\b|\b8 =>|[/%] 8\b|alignForward\([^)]*\b8\)|\.qword\b"
           r"|\b64 - |(<|>=|>|==) 64\b|=> (56|48|32),")
if sys.argv[1:] == ["--pattern"]:
    print(PATTERN)
    sys.exit(0)

W, B64, SCALAR, PIECE, CHUNK, S8, REG_BITS, NEUTRAL, COMPILER = (
    "word", "64", "scalar", "piece", "chunk", "size-8", "reg-bits", "neutral", "compiler")

LINE = {}
seen = collections.Counter()
def lines(kind, *ns):
    for n in ns:
        seen[n] += 1
        LINE[n] = kind

lines(W, 352)                       # the gate: target_ptr_size == 8
# reg-bits: shift amounts and bounds taken from a 64-bit register
lines(REG_BITS,
      2673, 2698, 2749, 2750, 2776, 2777, 2819, 3058, 3059, 3140, 3141, 3162,
      3163, 3183, 3184, 3230, 3231,  # generateLowLevel int conversions: 64 - bits
      6268,                          # signExtendGeneral
      7787, 7788, 7789,              # normalizeIntegerWidthInReg: 56, 48, 32
      8922, 8923, 8924,              # generateIntBinop: narrow signed shift
      8947, 8948, 8949, 8950,        # generateIntBinop: shift-count keep, 64 - log2
      10005, 10006,                  # generateIntTryConversion: 64 - src bits
      10725, 10739, 10741, 10747,    # generateBitCountScalar: width < 64
      11427, 11428, 11429,           # generateAbsDiff: 56, 48, 32
      12056, 12057, 12058)           # emitValueLoadStack: 56, 48, 32
# size-8: a general register or immediate holds up to 8 bytes; a branch or
# check on an 8-byte size; ValueSize's 8-byte member
lines(S8, 1014, 1021, 1030,         # ValueSize.qword, fromByteCount, byteCount
      2155, 2423, 8041,             # load or store through one register when <= 8
      12046, 12091, 12119,          # sized loads and stores, .qword arm
      13330, 13341,                 # a struct field in a register is <= 8 bytes
      15516, 16019, 16724, 16756, 16765, 16813, 16825, 17357, 17520, 18509, 18515,
      19618, 19622, 20592, 20605, 20615)
# 64: F64 sizes, i128/Dec halves (>> 64), U64 record fields
lines(B64, 1070, 1074, 1847, 2976, 5041, 7957, 7958, 8551, 10830, 15367, 15544,
      16038, 16095, 16271, 16370, 16628, 16675, 16745, 19511, 19650, 20310, 20349,
      20421, 20453)
# scalar: any value up to 8 bytes in one register or stack slot
lines(SCALAR, 1091, 19494,          # ValueLocation.stack and FrozenCallArg default to .qword
      19698,                        # freezeCallArg spills a register or immediate as .qword
      9979,                         # generateIntTryConversion: > 64 bits takes the i128 path
      13056)                        # discriminant mask below 8 bytes
# piece: register counts and pieces of at most 8 bytes
lines(PIECE, 15462, 15463,          # aggregateArgRegisterPressure: (size + 7) / 8
      19371, 19373,                 # saveCallReturnValue
      20479, 20498,                 # moveToReturnRegisterWithLayout
      19631, 19639,                 # freezeCallArg: i128, Str, List first piece
      22818, 22823, 22841)          # generateEntrypointBodyCAbi: 8-byte slots and pieces
lines(CHUNK, 17148, 17153, 17201, 17211, 17223, 17251, 17259, 17269, 21818, 21829)
lines(NEUTRAL, 201, 203, 204,       # decToIntTruncBits: type widths
      351,                          # target_ptr_size from the target
      5067, 5084, 5097, 5116, 5117, 5252,  # SIMD lane bytes
      10021, 10027, 10032, 10049, 10053,   # a 64-bit destination type's bounds
      10715, 10717, 10718,          # generateBitCountScalar: type widths
      15812)                        # spillVectorLocalEntry: a vector slot, size unused
lines(COMPILER, 25496)              # ShiftHarness (test helper outside a test block)

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
print("line\tfunction\tcontext\tkind\tcode")
print("\n".join(out))
