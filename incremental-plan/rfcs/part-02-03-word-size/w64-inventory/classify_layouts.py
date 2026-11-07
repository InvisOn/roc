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
lines(NARROW, 3406, 3452, 3665, 3674, 10157, 10160, 10162, 10164, 17381, 17382,
      17733, 18318, 18320)
lines(HOST,
      8393, 8406,                                # pointer alignment as @alignOf(usize)
      14533,                                     # emitOwnPendingCell's word = @sizeOf(u64)
      14660, 14668, 14797, 14807,                # HotReloadCaptureHeader (two pointers)
      14788, 14813,                              # erased callable payload word 1 at @sizeOf(usize)
      17719,                                     # CompositionEntry.result (usize)
      17815, 17821, 17823,                       # FieldInput (two pointers)
      17841, 17856, 17858, 17860,                # DeclaredFieldInput (pointers, then u32)
      17889, 17897, 17899, 17901,                # VariantInput (pointer, u32, pointer)
      18314, 18322, 18325, 18345, 18352, 18363, 18365, 18377, 18381, 18391,
      18393)                                     # ListOpRequest after its two u32s
lines(COMPILER, 13961, 14197, 14455, 19753, 20787, 21606,   # stack-fallback buffers
      22110, 22113,                              # checks the compiler's static string bytes
      23750, 23760, 23768, 23778, 23787)         # in-process allocator helpers

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
