"""Classify LirCodeGen's @offsetOf, @sizeOf and @alignOf uses.

Usage:
  python3 -I w64_sites.py LirCodeGen.zig --pattern '@(offsetOf|sizeOf|alignOf)\\(' > layouts.tsv
  python3 -I classify_layouts.py layouts.tsv

Output TSV: line, function, context, kind, code. Kinds:
- host-layout: lays out memory the generated code reads with the compiler's
  own Zig type, and the result depends on the word (a pointer or usize in or
  before the field, or `usize` itself). Needs the target's layout.
- narrow: the same at either word: a struct of u32s, or u32 fields before
  any pointer.
- compiler: the compiler's own memory (buffers, in-process helpers).
Sites in `test` blocks are left out. A shared line without a kind stops the
script, and so do a line given two kinds and an entry that matches no line.
"""
import collections
import sys

HOST, NARROW, COMPILER = "host-layout", "narrow", "compiler"

LINE = {}
seen = collections.Counter()
def lines(kind, *ns):
    for n in ns:
        seen[n] += 1
        LINE[n] = kind

# u32-only builtin layout structs; TypeDesc.size and .alignment (offsets 0
# and 4); ListOpRequest.op (enum(u32)) and .unique_args (offsets 0 and 4)
lines(NARROW, 3405, 3451, 3664, 3673, 10156, 10159, 10161, 10163, 17380, 17381,
      17732, 18317, 18319)
lines(HOST,
      8392, 8405,                                # pointer alignment as @alignOf(usize)
      14532,                                     # emitOwnPendingCell's word = @sizeOf(u64)
      14659, 14667, 14796, 14806,                # HotReloadCaptureHeader (two pointers)
      14787, 14812,                              # erased callable payload word 1 at @sizeOf(usize)
      17718,                                     # CompositionEntry.result (usize)
      17814, 17820, 17822,                       # FieldInput (two pointers)
      17840, 17855, 17857, 17859,                # DeclaredFieldInput (pointers, then u32)
      17888, 17896, 17898, 17900,                # VariantInput (pointer, u32, pointer)
      18313, 18321, 18324, 18344, 18351, 18362, 18364, 18376, 18380, 18390,
      18392)                                     # ListOpRequest after its two u32s
lines(COMPILER, 13960, 14196, 14454, 19752, 20786, 21605,   # stack-fallback buffers
      22109, 22112,                              # checks the compiler's static string bytes
      23704, 23714, 23722, 23732, 23741)         # in-process allocator helpers

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
