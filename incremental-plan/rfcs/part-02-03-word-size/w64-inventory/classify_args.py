"""Classify the integer arguments LirCodeGen passes to builtins and runtime
functions through the call builder.

Usage:
  python3 -I w64_sites.py LirCodeGen.zig --calls <CALLEES> > args.tsv
  python3 -I classify_args.py args.tsv
with CALLEES as printed by `python3 -I classify_args.py --callees`.

Output TSV: line, function, callee, context, kind, code. The kind is that of
the parameter the argument fills, from the callee's Zig signature
(`builtins/dev_wrappers.zig`, `boxy_runtime/exports.zig`,
`builtins/in_process_host.zig`): u64 and i64 are `64`; usize, isize and
pointers are `word`; u32, u8, bool, i32 and UpdateMode are `narrow`. C ABI
pieces are `piece`. `mixed` marks the one forwarder whose callers pass both
(README.md lists them). Float arguments go in float registers and are not
listed. Sites in `test` blocks and the bodies of the three wrappers are left
out; the wrappers are listed by their callers. A shared site without a kind
stops the script, and so do a line given two kinds and an entry that
matches no site.
"""
import collections
import sys

CALLEES = [
    "addImmArg", "addRegArg", "addMemArg", "addMemArgAt", "addStackMemArgAt",
    "addLeaArg", "addLeaArgAt", "addStackLeaArgAt",
    "addListBytesLenCapMemArgs", "addStrBytesLenCapMemArgs",
    "addWordArg", "addBytesArg", "addTargetArg",
]
if sys.argv[1:] == ["--callees"]:
    print(",".join(CALLEES))
    sys.exit(0)

ISA, W, B64, NARROW, PIECE, MIXED = "isa", "word", "64", "narrow", "piece", "mixed"

# Pointers and RocStr/RocList words by definition.
BY_CALLEE = {c: W for c in ("addLeaArg", "addLeaArgAt", "addStackLeaArgAt",
                            "addListBytesLenCapMemArgs", "addStrBytesLenCapMemArgs",
                            "addBytesArg", "addTargetArg")}
WRAPPER_BODIES = {"addWordArg", "addBytesArg", "addTargetArg"}

LINE = {}
seen = collections.Counter()
def lines(kind, *ns):
    for n in ns:
        seen[n] += 1
        LINE[n] = kind

lines(B64, 1989, 2587, 2588, 3575, 4925, 4927, 4938, 4939, 4952, 4954, 4955, 7363,
      7364, 7366, 7381, 7382, 7423, 7475, 7490, 7660, 7700, 7701, 7702, 7703, 7715,
      7716, 7717, 7764, 7778, 7779, 7826, 7827, 7844, 7845, 7862, 7987, 7988, 8461,
      8462, 9819, 9829, 9830, 9991, 9992, 10040, 10041, 10042, 10061, 10062, 10240,
      10241, 10298, 10299, 10344, 10345, 10366, 10367, 10368, 10369, 10384, 10385,
      10402, 10403, 10404, 10405, 10431, 10432, 10433, 10434, 10532, 10533, 10534,
      10535, 10558, 10559, 10560, 10561, 10603, 10604,
      12669,   # callListBuiltin `.mem`: every forwarded value is a U64 operand
      17984,   # addWordArg(e.index): roc_desc_list_item_addr's index is u64
      18097)   # roc_desc_hash's hasher is u64
lines(W, 1992, 2107, 3538, 4537, 4652, 4653, 4656, 4657, 4792, 7477, 7478, 7986,
      11903, 12683, 12686, 12779, 12781, 12804, 12805, 12806, 12807, 12846, 12847,
      12848, 12850, 12851, 12871, 12872, 12904, 12906, 12924, 13643, 13718, 13839,
      14384, 14504, 14505, 14507, 14508, 14509, 14513, 14514, 14515, 14516, 14546,
      14598, 14599, 14739, 14740, 14741, 14743, 14756, 15990, 17569, 17744, 17747,
      17919, 17928, 18139, 18151, 18152, 18154, 18155, 18193, 18194, 18195, 18198,
      18200, 18201, 18211, 18212, 18213, 18214, 18217, 19204, 22132, 22133, 22314,
      22315,
      # addWordArg callers other than 17983: descriptors, names, pointers
      17549, 17567, 17576, 17763, 17768, 17773, 17779, 17787, 17788, 17789, 17797,
      17805, 17806, 17807, 17829, 17909, 17917, 17918, 17936, 17939, 17961, 17968,
      17975, 17977, 17982, 17989, 17995, 18001, 18002, 18007, 18016, 18027, 18029,
      18040, 18041, 18051, 18060, 18067, 18076, 18083, 18096, 18105, 18112, 18113,
      18142)
lines(NARROW, 1991, 1993, 2589, 2590, 4538, 4539, 4654, 4655, 4658, 4793, 4794,
      4926, 4928, 4953, 7367, 7384, 7476, 7564, 7743, 7765, 7828, 7829, 7863, 7989,
      8458, 8459, 8460, 9869, 9870, 9993, 9994, 9995, 9996, 10043, 10044, 10063,
      10064, 10100, 10108, 10109, 10117, 10118, 10119, 10180, 10181, 10185, 10242,
      10243, 10244, 10245, 10246, 10279, 10280, 10281, 10282, 10283, 10300, 10301,
      10328, 10329, 10346, 10347, 10605, 11904, 11905, 12783, 12784, 12808, 12849,
      12905, 13644, 13645, 13719, 13720, 13840, 13841, 14510, 14744, 14757, 14758,
      17745, 17780, 17790, 17798, 17799, 17826, 17863, 17870, 17877, 17906, 17920,
      17929, 17930, 17937, 17938, 17945, 17970, 18009, 18018, 18031, 18043, 18053,
      18143, 18205, 21059, 21060, 22287, 22288)
lines(PIECE, 14969, 14982)      # generateCAbiCall: C ABI pieces
lines(MIXED, 12670)             # callListBuiltin `.imm`: see README.md
lines(NARROW, 12672, 12676)     # callListBuiltin `.elem_abi` alignment, `.elem_rc` flag
lines(W, 12673)                 # callListBuiltin `.elem_abi` element size

twice = [n for n, c in seen.items() if c > 1]
if twice:
    sys.exit(f"lines set twice: {sorted(twice)}")

out = []
used = set()
for row in open(sys.argv[1], encoding="utf-8"):
    line, fn, callee, ctx, code = row.rstrip("\n").split("\t")
    if fn == "test" or fn in WRAPPER_BODIES:
        continue
    n = int(line)
    if ctx != "shared":
        kind = ISA
    elif n in LINE:
        kind = LINE[n]
        used.add(n)
    elif callee in BY_CALLEE:
        kind = BY_CALLEE[callee]
    else:
        sys.exit(f"unclassified: {line} {fn} {callee}: {code}")
    out.append("\t".join([line, fn, callee, ctx, kind, code]))
unused = sorted(set(LINE) - used)
if unused:
    sys.exit(f"entries that match no shared site: {unused}")
print("\n".join(out))
