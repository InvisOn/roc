"""Check the rename PR's `…Wide64` builder arguments against the signatures.

Usage: python3 -I check_wide64_args.py <worktree>

Reads the working tree's LirCodeGen.zig (not the inventory). For every
call whose target is named directly, lines each integer argument up with
the target's parameter and checks one rule: the parameter is `u64` or
`i64` exactly when the argument is added through a `…Wide64` method (or,
in a `callListBuiltin` argument list, is `.mem` or `.imm_wide64`).

Two shapes are lined up:
- a `Builder.init` builder whose arguments are added without branches and
  whose call names its target (`.name`, `LowLevelBuiltins.xxxOp(.op)`, or
  a boxy runtime string), as check_args.py does;
- a `callListBuiltin(list_abi, rc, &.{ ... }, LowLevelBuiltins.listOp(.op))`
  call: `.lea` 1 parameter, `.list` 3, `.mem` 1, `.imm` 1, `.imm_wide64`
  1, `.elem_abi` 2, `.elem_rc` 1 plus one per callback the `rc` above it
  asks for.

A builder whose target is not named directly is lined up against every
target it can call: each `LowLevelBuiltins.xxx(.op)` in the call, every
entry of `xxx`'s table when the op is a variable, every name any other
`LowLevelBuiltins` function returns, and, for a `builtin_fn` parameter, every
target its enclosing function's callers pass.

Everything else is listed, with the lines of its `…Wide64` arguments, for
reading by hand.
"""
import os
import re
import sys

root = sys.argv[1]
p = lambda *a: os.path.join(root, *a)
src = open(p("src/backend/dev/LirCodeGen.zig"), encoding="utf-8").read().split("\n")


def kind(ty):
    ty = ty.strip()
    if ty in ("u64", "i64"):
        return "64"
    if ty in ("f64", "f32"):
        return "float"
    return "other"


def sigs(path, pattern):
    out = {}
    for m in re.finditer(pattern, open(path, encoding="utf-8").read(), re.S):
        tys = [a.split(":", 1)[1].strip() for a in m.group(2).split(",") if ":" in a]
        out[m.group(1)] = tys
    return out


targets = sigs(p("src/builtins/dev_wrappers.zig"), r"pub (?:noinline )?fn roc_builtins_(\w+)\(([^)]*)\)")
targets.update(sigs(p("src/boxy_runtime/exports.zig"), r"pub fn (roc_desc_\w+)\(([^)]*)\)"))
# Generated wrappers, `pub const roc_builtins_x = gen(..)`: the parameter
# types are the generator's return type, `fn gen(..) fn (T, ..) callconv`.
dw = open(p("src/builtins/dev_wrappers.zig"), encoding="utf-8").read()
gens = {m.group(1): [t.strip() for t in m.group(2).split(",") if t.strip()]
        for m in re.finditer(r"\bfn (\w+)\([^)]*\) fn \(([^)]*)\) callconv", dw)}
for m in re.finditer(r"^pub const roc_builtins_(\w+) = (\w+)\(", dw, re.M):
    if m.group(2) in gens:
        targets[m.group(1)] = gens[m.group(2)]

tables, cur = {}, None
for s in open(p("src/base/LowLevelBuiltins.zig"), encoding="utf-8"):
    m = re.match(r"pub fn (\w+)\(", s)
    if m:
        cur = m.group(1)
    m = re.search(r"\.\{ LowLevel\.(\w+), BuiltinFn\.(\w+) \}", s)
    if m and cur:
        tables.setdefault(cur, {})[m.group(1)] = m.group(2)


# Other `pub fn f(..) BuiltinFn` functions: every name the body can return.
simple_fns, prongs = {}, {}
lb = open(p("src/base/LowLevelBuiltins.zig"), encoding="utf-8").read()
for m in re.finditer(r"pub fn (\w+)\([^)]*\) BuiltinFn \{(.*?)\n\}", lb, re.S):
    if m.group(1) not in tables:
        simple_fns[m.group(1)] = set(re.findall(r"(?:BuiltinFn)?\.([a-z]\w*)\b", m.group(2))) & set(targets)
        # A switch on the argument: `.arg => .name` prongs.
        prongs[m.group(1)] = dict(re.findall(r"\.(\w+) => (?:BuiltinFn)?\.(\w+)", m.group(2)))


def call_text(k):
    """The text of the call that opens on line k (0-based), parens balanced."""
    out, depth, started = [], 0, False
    for s in src[k:k + 40]:
        out.append(s)
        for ch in s:
            if ch == "(":
                depth += 1
                started = True
            elif ch == ")":
                depth -= 1
        if started and depth <= 0:
            break
    return "\n".join(out)


def enclosing_fn(k):
    for j in range(k, -1, -1):
        m = re.search(r"\bfn (\w+)\(", src[j])
        if m:
            return m.group(1)
    return None


def resolve(text, k, seen=()):
    """Every target the call `text` (at line k, 0-based) can name."""
    names = set()
    for m in re.finditer(r"LowLevelBuiltins\.(\w+)\(([^()]*)\)", text):
        t, arg = m.group(1), m.group(2).strip()
        if t in simple_fns and re.fullmatch(r"\.\w+", arg) and arg[1:] in prongs.get(t, {}):
            names.add(prongs[t][arg[1:]])
        elif t in simple_fns:
            names |= simple_fns[t]
        elif re.fullmatch(r"\.\w+", arg):
            names.add(tables.get(t, {}).get(arg[1:]))
        else:
            names |= set(tables.get(t, {}).values())
    rest = re.sub(r"LowLevelBuiltins\.\w+\([^()]*\)", "", text)
    for m in re.finditer(r"(?<![\w)\]])\.([a-z]\w*)\b(?!\s*=)", rest):
        if m.group(1) in targets:
            names.add(m.group(1))
    if re.search(r"\bbuiltin_fn\b", rest):
        f = enclosing_fn(k)
        if f and f not in seen:
            for j, s in enumerate(src):
                if f"self.{f}(" in s:
                    names |= resolve(call_text(j), j, seen + (f,))
    names.discard(None)
    return names


def drop_ops(tys, n):
    """The call appends `roc_ops` itself when the signature has one more."""
    if len(tys) == n + 1 and "RocOps" in tys[-1]:
        return tys[:-1]
    return tys


wide_lines = {i + 1 for i, s in enumerate(src) if re.search(r"\badd\w*Wide64\(|\.imm_wide64 = ", s)}
checked, bad, manual, covered = 0, [], [], set()


def check(line, is_wide, ty, target):
    global checked
    k = kind(ty)
    if k == "float":
        return
    checked += 1
    if (k == "64") != is_wide:
        bad.append(f"{line}: {target} parameter `{ty}`, argument {'Wide64' if is_wide else 'not Wide64'}")
    if is_wide:
        covered.add(line)


# Builders.
add_re = re.compile(r"\b(addImmArg|addRegArg|addMemArg|addLeaArg|addListBytesLenCapMemArgs|"
                    r"addStrBytesLenCapMemArgs|addWordArg|addBytesArg|addTargetArg|"
                    r"addF64RegArg|addF32RegArg|addF64MemArg|addF32MemArg)(Wide64)?\(")
i = 0
while i < len(src):
    if "Builder.init(" not in src[i]:
        i += 1
        continue
    start, args, branchy, target, cands, j = i + 1, [], False, None, set(), i + 1
    while j < len(src) and j < i + 400:
        s = src[j]
        if "Builder.init(" in s:
            break
        if re.search(r"\b(if|else|switch|for|while)\b", s) and add_re.search(s):
            branchy = True
        for m in add_re.finditer(s):
            args.append((j + 1, m.group(1), bool(m.group(2))))
        m = re.search(r"callBuiltin\w*\([^,]+,\s*(?:[^,]+,\s*)?\.(\w+)\)", s)
        mt = re.search(r"callBuiltin\w*\([^,]+,\s*(?:[^,]+,\s*)?LowLevelBuiltins\.(\w+)\(\.(\w+)\)\)", s)
        mb = re.search(r"callBoxyRuntime\([^,]+,\s*\"(\w+)\"\)", s)
        if m or mt or mb or "callBuiltin" in s or "callBoxyRuntime" in s or "builder.call" in s:
            target = m.group(1) if m else tables.get(mt.group(1), {}).get(mt.group(2)) if mt else mb.group(1) if mb else None
            cands = {target} if target in targets else resolve(call_text(j), j)
            break
        j += 1
    i = j
    wides = [a[0] for a in args if a[2]]
    flat = []
    for line, meth, wide in args:
        flat += [(line, meth, wide)] * (3 if meth.endswith("LenCapMemArgs") else 1)
    cands = {c for c in cands if c in targets}
    lined = {c: drop_ops(targets[c], len(flat)) for c in cands}
    # A candidate of another arity cannot be the call's target.
    lined = {c: t for c, t in lined.items() if len(t) == len(flat)} or lined
    if branchy or not cands or any(len(t) != len(flat) for t in lined.values()):
        why = "branches" if branchy else "target not found" if not cands else \
            "arity: " + ", ".join(f"{c} {len(t)}" for c, t in lined.items() if len(t) != len(flat)) + f" vs {len(flat)} args"
        ints = [a[0] for a in args if not a[1].startswith("addF")]
        if ints:
            manual.append(f"builder at {start} ({','.join(sorted(cands)) or '?'}; {why}): Wide64 lines {wides}")
        continue
    for c, tys in sorted(lined.items()):
        for (line, meth, wide), ty in zip(flat, tys):
            if not meth.startswith("addF"):
                check(line, wide, ty, c)

# callListBuiltin argument lists.
text = "\n".join(src)
for m in re.finditer(r"self\.callListBuiltin\((\w+),\s*(\w+),\s*&\.\{(.*?)\},\s*(\w+(?:\.\w+\(\.\w+\))?)\)", text, re.S):
    line0 = text[:m.start()].count("\n") + 1
    rc_var, body, fn = m.group(2), m.group(3), m.group(4)
    mt = re.match(r"LowLevelBuiltins\.(\w+)\(\.(\w+)\)", fn)
    target = tables.get(mt.group(1), {}).get(mt.group(2)) if mt else None
    if target not in targets:
        manual.append(f"callListBuiltin at {line0}: target {fn}")
        continue
    # The callbacks `rc` asks for, from the nearest `listElemCallbacks` above.
    ncb = None
    for k in range(line0 - 1, max(0, line0 - 40), -1):
        mk = re.search(rf"const {rc_var} = try self\.listElemCallbacks\([^,]+,\s*\.(\w+)\)", src[k - 1])
        if mk:
            ncb = {"incref_and_decref": 2, "incref": 1, "decref": 1}[mk.group(1)]
            break
    entries = []  # (line, tag)
    for e in re.finditer(r"\.\{\s*\.(\w+)\s*=|\.(elem_abi|elem_rc)\b|(?<![.\w])(start|len)(?=\s*,)", body):
        entries.append((line0 + body[:e.start()].count("\n"), e.group(1) or e.group(2) or e.group(3)))
    flat = []
    for line, tag in entries:
        n = {"lea": 1, "list": 3, "mem": 1, "imm": 1, "imm_wide64": 1, "elem_abi": 2, "start": 1, "len": 1}.get(tag)
        if tag == "elem_rc":
            if ncb is None:
                flat = None
                break
            n = 1 + ncb
        flat += [(line, tag)] * n
    tys = drop_ops(targets[target], len(flat)) if flat is not None else None
    if flat is None or len(tys) != len(flat):
        manual.append(f"callListBuiltin at {line0} ({target}): could not line up")
        continue
    for (line, tag), ty in zip(flat, tys):
        # `start` and `len` are callListSublistWindow's forwarded arguments;
        # its callers are checked below.
        wide = tag in ("mem", "imm_wide64", "start", "len")
        check(line, wide, ty, target)

# callListSublistWindow's callers pass its `start` and `len`.
for i, s in enumerate(src):
    if "self.callListSublistWindow(" in s:
        for e in re.finditer(r"\.\{\s*\.(\w+)\s*=", s):
            checked += 1
            if e.group(1) not in ("mem", "imm_wide64"):
                bad.append(f"{i + 1}: callListSublistWindow start/len passed as .{e.group(1)}")
            else:
                covered.add(i + 1)

print(f"checked {checked} integer arguments, {len(bad)} mismatches")
print("\n".join(bad))
left = sorted(wide_lines - covered)
print(f"Wide64 lines: {len(wide_lines)}; lined up: {len(wide_lines & covered)}; not lined up: {len(left)}")
print("not lined up:", left)
print("for reading by hand:")
print("\n".join(manual))
