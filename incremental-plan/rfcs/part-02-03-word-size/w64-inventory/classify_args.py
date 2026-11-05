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

lines(B64, 1988, 2586, 2587, 3574, 4924, 4926, 4937, 4938, 4951, 4953, 4954, 7362,
      7363, 7365, 7380, 7381, 7422, 7474, 7489, 7659, 7699, 7700, 7701, 7702, 7714,
      7715, 7716, 7763, 7777, 7778, 7825, 7826, 7843, 7844, 7861, 7986, 7987, 8460,
      8461, 9818, 9828, 9829, 9990, 9991, 10039, 10040, 10041, 10060, 10061, 10239,
      10240, 10297, 10298, 10343, 10344, 10365, 10366, 10367, 10368, 10383, 10384,
      10401, 10402, 10403, 10404, 10430, 10431, 10432, 10433, 10531, 10532, 10533,
      10534, 10557, 10558, 10559, 10560, 10602, 10603,
      12668,   # callListBuiltin `.mem`: every forwarded value is a U64 operand
      17983,   # addWordArg(e.index): roc_desc_list_item_addr's index is u64
      18096)   # roc_desc_hash's hasher is u64
lines(W, 1991, 2106, 3537, 4536, 4651, 4652, 4655, 4656, 4791, 7476, 7477, 7985,
      11902, 12682, 12685, 12778, 12780, 12803, 12804, 12805, 12806, 12845, 12846,
      12847, 12849, 12850, 12870, 12871, 12903, 12905, 12923, 13642, 13717, 13838,
      14383, 14503, 14504, 14506, 14507, 14508, 14512, 14513, 14514, 14515, 14545,
      14597, 14598, 14738, 14739, 14740, 14742, 14755, 15989, 17568, 17743, 17746,
      17918, 17927, 18138, 18150, 18151, 18153, 18154, 18192, 18193, 18194, 18197,
      18199, 18200, 18210, 18211, 18212, 18213, 18216, 19203, 22131, 22132, 22301,
      22302,
      # addWordArg callers other than 17983: descriptors, names, pointers
      17548, 17566, 17575, 17762, 17767, 17772, 17778, 17786, 17787, 17788, 17796,
      17804, 17805, 17806, 17828, 17908, 17916, 17917, 17935, 17938, 17960, 17967,
      17974, 17976, 17981, 17988, 17994, 18000, 18001, 18006, 18015, 18026, 18028,
      18039, 18040, 18050, 18059, 18066, 18075, 18082, 18095, 18104, 18111, 18112,
      18141)
lines(NARROW, 1990, 1992, 2588, 2589, 4537, 4538, 4653, 4654, 4657, 4792, 4793,
      4925, 4927, 4952, 7366, 7383, 7475, 7563, 7742, 7764, 7827, 7828, 7862, 7988,
      8457, 8458, 8459, 9868, 9869, 9992, 9993, 9994, 9995, 10042, 10043, 10062,
      10063, 10099, 10107, 10108, 10116, 10117, 10118, 10179, 10180, 10184, 10241,
      10242, 10243, 10244, 10245, 10278, 10279, 10280, 10281, 10282, 10299, 10300,
      10327, 10328, 10345, 10346, 10604, 11903, 11904, 12782, 12783, 12807, 12848,
      12904, 13643, 13644, 13718, 13719, 13839, 13840, 14509, 14743, 14756, 14757,
      17744, 17779, 17789, 17797, 17798, 17825, 17862, 17869, 17876, 17905, 17919,
      17928, 17929, 17936, 17937, 17944, 17969, 18008, 18017, 18030, 18042, 18052,
      18142, 18204, 21058, 21059, 22274, 22275)
lines(PIECE, 14968, 14981)      # generateCAbiCall: C ABI pieces
lines(MIXED, 12669)             # callListBuiltin `.imm`: see README.md
lines(NARROW, 12671, 12675)     # callListBuiltin `.elem_abi` alignment, `.elem_rc` flag
lines(W, 12672)                 # callListBuiltin `.elem_abi` element size

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
