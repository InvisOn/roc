"""List every `.w64` site in a Zig file with its function and ISA context.

Usage: python3 -I w64_sites.py <file.zig>
Prints TSV: line, function, helper, context, code.

Usage: python3 -I w64_sites.py <file.zig> --calls name1,name2,...
Lists the call sites of those functions instead (not their definitions),
same columns, `helper` being the callee and `code` the whole call on one
line.

Usage: python3 -I w64_sites.py <file.zig> --pattern <regex>
Lists every non-comment line matching the regex, same columns, `helper`
being `-`.
context is `x86_64` / `aarch64` when the site is inside that arm of a
`switch (isa)`, `fn:<name>` when the enclosing function's name names one
instruction set, else `shared`.
"""
import re
import sys

path = sys.argv[1]
lines = open(path, encoding="utf-8").read().split("\n")

def indent(s):
    return len(s) - len(s.lstrip(" "))

fn_re = re.compile(r"^\s*(?:pub )?(?:inline )?fn ([A-Za-z0-9_]+)\(")
arm_re = re.compile(r"^\s*\.(x86_64|aarch64)\s*(?:,\s*\.\w+\s*)*=>")
helper_re = re.compile(r"([A-Za-z0-9_]+)\((?:[^()]*,\s*)?\.w64\b")
arch_fn_re = re.compile(r"(X86|x86|Aarch64|aarch64|Arm64|arm64|Sse|Avx|Neon)")

def ancestors(i):
    """Indices of enclosing lines, nearest first, by zig-fmt indentation."""
    cur = indent(lines[i]) if lines[i].strip() else 0
    out = []
    j = i - 1
    while j >= 0 and cur > 0:
        s = lines[j]
        if s.strip() and not s.strip().startswith("//") and not s.strip().startswith(")") and indent(s) < cur:
            out.append(j)
            cur = indent(s)
        j -= 1
    return out

# Tail regions: a statement `switch (isa) {` whose arms all end in `return`
# except one empty arm (`=> {}`); the lines after the switch, up to the end
# of the enclosing block, run only for that empty arm's instruction set.
tail = {}  # line index -> isa
for i, s in enumerate(lines):
    if not re.match(r"^\s*switch \(isa\) \{\s*$", s):
        continue
    base = indent(s)
    j = i + 1
    arms = []  # (isa names, body lines)
    while j < len(lines) and not (indent(lines[j]) == base and lines[j].strip().startswith("}")):
        t = lines[j]
        m = re.match(r"^\s*((?:\.\w+\s*,\s*)*\.\w+)\s*=>\s*(.*)$", t)
        if m and indent(t) == base + 4:
            arms.append([re.findall(r"\.(\w+)", m.group(1)), [m.group(2)]])
        elif arms:
            arms[-1][1].append(t.strip())
        j += 1
    end = j
    empty = [a for a in arms if a[1][0].strip() in ("{},", "{}")]
    rest = [a for a in arms if a not in empty]
    def returns(body):
        stmts = [b for b in body if b and b not in ("},", "}") and not b.startswith("//")]
        return bool(stmts) and stmts[-1].startswith("return")
    if len(empty) == 1 and len(empty[0][0]) == 1 and rest and all(returns(a[1]) for a in rest):
        k = end + 1
        while k < len(lines) and (not lines[k].strip() or indent(lines[k]) >= base):
            tail[k] = empty[0][0][0]
            k += 1

def site_context(i):
    anc = ancestors(i)
    func = "?"
    for j in anc:
        m = fn_re.match(lines[j])
        if m:
            func = m.group(1)
            break
        if lines[j].startswith("test \""):
            func = "test"
            break
    ctx = "shared"
    chain = [i] + anc
    for k, j in enumerate(chain):
        m = arm_re.match(lines[j])
        if m and any("switch (isa)" in lines[a] for a in chain[k + 1:k + 3]):
            ctx = m.group(1)
            break
    if ctx == "shared":
        # `if (comptime target.toCpuArch() == .X) {A} else {B}`
        cmp_re = re.compile(r"^\s*(?:\} else )?if \(comptime target\.toCpuArch\(\) == \.(\w+)\)")
        for j in chain:
            m = cmp_re.match(lines[j])
            if m:
                ctx = m.group(1)
                break
            if re.match(r"^\s*\} else \{", lines[j]):
                k = j - 1
                while k >= 0 and not (indent(lines[k]) == indent(lines[j]) and lines[k].strip().startswith(("if (", "} else if ("))):
                    k -= 1
                m = cmp_re.match(lines[k]) if k >= 0 else None
                if m:
                    ctx = {"aarch64": "x86_64", "x86_64": "aarch64"}[m.group(1)]
                break
    if ctx == "shared" and i in tail:
        ctx = tail[i] + "-tail"
    if ctx == "shared" and arch_fn_re.search(func):
        ctx = "fn:" + func
    return func, ctx


def whole_call(i, start):
    """The call starting at lines[i][start:], joined onto one line."""
    text = lines[i][start:]
    depth = 0
    out = ""
    k = i
    while True:
        for ch in text:
            out += ch
            if ch == "(":
                depth += 1
            elif ch == ")":
                depth -= 1
                if depth == 0:
                    return " ".join(out.split())
        k += 1
        text = " " + lines[k].strip()


if len(sys.argv) > 3 and sys.argv[2] == "--pattern":
    pat = re.compile(sys.argv[3])
    for i, s in enumerate(lines):
        if s.strip().startswith("//") or not pat.search(s):
            continue
        func, ctx = site_context(i)
        print(f"{i + 1}\t{func}\t-\t{ctx}\t{s.strip()}")
    sys.exit(0)

if len(sys.argv) > 3 and sys.argv[2] == "--calls":
    names = sys.argv[3].split(",")
    call_re = re.compile(r"\b(" + "|".join(map(re.escape, names)) + r")\(")
    for i, s in enumerate(lines):
        if s.strip().startswith("//") or fn_re.match(s):
            continue
        for m in call_re.finditer(s):
            func, ctx = site_context(i)
            print(f"{i + 1}\t{func}\t{m.group(1)}\t{ctx}\t{whole_call(i, m.start())}")
    sys.exit(0)

for i, s in enumerate(lines):
    if not re.search(r"\.w64\b", s) or s.strip().startswith("//"):
        continue
    func, ctx = site_context(i)
    for m in re.finditer(r"\.w64\b", s):
        hm = None
        for h in helper_re.finditer(s):
            if h.start() <= m.start() < h.end() + 5:
                hm = h.group(1)
        print(f"{i + 1}\t{func}\t{hm or '-'}\t{ctx}\t{s.strip()}")
