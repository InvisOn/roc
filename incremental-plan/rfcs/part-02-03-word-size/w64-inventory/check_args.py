"""Cross-check classify_args.py against the builtin signatures.

Usage: python3 -I check_args.py LirCodeGen.zig dev_wrappers.zig exports.zig LowLevelBuiltins.zig args_classified.tsv

For every builder whose call names its target directly (a `.name` builtin,
`LowLevelBuiltins.xxxOp(.op)` resolved through that function's lookup table,
or a boxy runtime string) and whose
arguments are added without branches, lines the arguments up with the
target's parameters and compares each parameter's kind with the kind
classify_args.py gave the line. Prints mismatches and a summary.
"""
import re
import sys

src = open(sys.argv[1], encoding="utf-8").read().split("\n")
ab = {"usize": "word", "isize": "word", "u64": "64", "i64": "64", "u32": "narrow",
      "u8": "narrow", "bool": "narrow", "i32": "narrow", "u16": "narrow",
      "utils.UpdateMode": "narrow", "f64": "float", "f32": "float"}

def sigs(path, pattern):
    out = {}
    for m in re.finditer(pattern, open(path, encoding="utf-8").read(), re.S):
        kinds = []
        for p in m.group(2).split(","):
            if ":" not in p:
                continue
            ty = p.split(":", 1)[1].strip()
            kinds.append(ab.get(ty, "word" if ("*" in ty or "Fn" in ty or "[" in ty or "anyopaque" in ty) else "?" + ty))
        out[m.group(1)] = kinds
    return out

targets = sigs(sys.argv[2], r"pub (?:noinline )?fn roc_builtins_(\w+)\(([^)]*)\)")
targets.update(sigs(sys.argv[3], r"pub fn (roc_desc_\w+)\(([^)]*)\)"))

# LowLevelBuiltins lookup tables: function -> {LowLevel op: BuiltinFn}
tables = {}
cur = None
for s in open(sys.argv[4], encoding="utf-8"):
    m = re.match(r"pub fn (\w+)\(", s)
    if m:
        cur = m.group(1)
    m = re.search(r"\.\{ LowLevel\.(\w+), BuiltinFn\.(\w+) \}", s)
    if m and cur:
        tables.setdefault(cur, {})[m.group(1)] = m.group(2)

kind_of = {}
for row in open(sys.argv[5], encoding="utf-8"):
    f = row.rstrip("\n").split("\t")
    if f[0] == "line":
        continue  # header
    kind_of.setdefault(int(f[0]), set()).add(f[4])

add_re = re.compile(r"\b(addImmArg|addRegArg|addMemArg|addLeaArg|addListBytesLenCapMemArgs|"
                    r"addStrBytesLenCapMemArgs|addWordArg|addBytesArg|addTargetArg|"
                    r"addF64RegArg|addF32RegArg|addF64MemArg|addF32MemArg)\(")
checked = mismatches = skipped = 0
i = 0
while i < len(src):
    if "Builder.init(" not in src[i]:
        i += 1
        continue
    args = []      # (line, method)
    branchy = False
    j = i + 1
    target = None
    while j < len(src) and j < i + 80:
        s = src[j]
        if "Builder.init(" in s:
            break
        if re.search(r"\b(if|else|switch|for|while)\b", s) and add_re.search(s):
            branchy = True
        for m in add_re.finditer(s):
            args.append((j + 1, m.group(1)))
        m = re.search(r"callBuiltin\w*\([^,]+,\s*(?:[^,]+,\s*)?\.(\w+)\)", s)
        mt = re.search(r"callBuiltin\w*\([^,]+,\s*(?:[^,]+,\s*)?LowLevelBuiltins\.(\w+)\(\.(\w+)\)\)", s)
        mb = re.search(r"callBoxyRuntime\([^,]+,\s*\"(\w+)\"\)", s)
        if m or mt or mb or "callBuiltin" in s or "callBoxyRuntime" in s or "builder.call" in s:
            if m:
                target = m.group(1)
            elif mt:
                target = tables.get(mt.group(1), {}).get(mt.group(2))
            elif mb:
                target = mb.group(1)
            break
        j += 1
    i = j
    if target is None or target not in targets or branchy:
        skipped += 1
        continue
    flat = []
    for line, meth in args:
        if meth in ("addListBytesLenCapMemArgs", "addStrBytesLenCapMemArgs"):
            flat += [(line, meth)] * 3
        else:
            flat.append((line, meth))
    params = targets[target]
    if len(flat) != len(params):
        skipped += 1
        continue
    for (line, meth), want in zip(flat, params):
        if want == "float" or meth.startswith("addF"):
            continue
        checked += 1
        have = kind_of.get(line, set())
        if want not in have:
            mismatches += 1
            print(f"{line} {meth} -> {target}: parameter is {want}, classified {sorted(have)}")
print(f"checked {checked} arguments, {mismatches} mismatches; {skipped} builders not checkable "
      f"(target named indirectly, branches, or argument count differs)")
