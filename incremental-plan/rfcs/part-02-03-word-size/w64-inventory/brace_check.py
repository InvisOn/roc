"""Independent ISA-context check by brace matching (not indentation).

Usage: python3 -I brace_check.py <file.zig> <sites.tsv>
Prints every site whose context differs from the sites.tsv context.
"""
import re
import sys

src = open(sys.argv[1], encoding="utf-8").read()
n = len(src)

# Blank out comments and string/char literals, keeping offsets and newlines.
clean = list(src)
i = 0
while i < n:
    c = src[i]
    if src.startswith("//", i) or src.startswith("\\\\", i):
        j = src.find("\n", i)
        j = n if j < 0 else j
        for k in range(i, j):
            clean[k] = " "
        i = j
    elif c == '"' or c == "'":
        q = c
        j = i + 1
        while j < n and src[j] != q:
            j += 2 if src[j] == "\\" else 1
        for k in range(i + 1, j):
            if clean[k] != "\n":
                clean[k] = " "
        i = j + 1
    else:
        i += 1
clean = "".join(clean)

line_of = []
ln = 1
for ch in clean:
    line_of.append(ln)
    if ch == "\n":
        ln += 1

match = {}
stack = []
for i, ch in enumerate(clean):
    if ch in "({[":
        stack.append(i)
    elif ch in ")}]":
        match[stack.pop()] = i
assert not stack

def enclosing_block_end(pos):
    """End of the innermost `{...}` containing pos."""
    best = None
    for o, c in match.items():
        if clean[o] == "{" and o < pos < c and (best is None or o > best[0]):
            best = (o, c)
    return best[1]

ctx = {}  # offset range -> label
ranges = []

def arms_of(open_brace):
    """Yield (names, body_start, body_end) for a switch body."""
    close = match[open_brace]
    i = open_brace + 1
    while True:
        m = re.compile(r"\s*((?:\.\w+\s*,\s*)*\.\w+|else)\s*=>").match(clean, i)
        if not m or m.start() >= close:
            return
        names = re.findall(r"\.(\w+)", m.group(1)) or ["else"]
        j = m.end()
        depth = 0
        while j < close:
            ch = clean[j]
            if ch in "({[":
                j = match[j] + 1
                continue
            if ch == ",":
                break
            j += 1
        yield names, m.end(), j
        i = j + 1

def last_stmt_returns(start, end):
    body = clean[start:end].strip()
    if body.startswith("{") and body.endswith("}"):
        inner = body[1:-1].strip()
        stmts = [s.strip() for s in re.split(r";", inner) if s.strip()]
        return bool(stmts) and stmts[-1].startswith("return")
    return body.startswith("return")

for m in re.finditer(r"switch \(isa\) \{", clean):
    ob = m.end() - 1
    arms = list(arms_of(ob))
    for names, s, e in arms:
        if len(names) == 1 and names[0] in ("x86_64", "aarch64"):
            ranges.append((s, e, names[0]))
    # tail: statement switch whose arms all return except one empty arm
    before = clean[:m.start()].rstrip()
    is_stmt = before.endswith((";", "{", "}"))
    empty = [a for a in arms if clean[a[1]:a[2]].strip() == "{}"]
    others = [a for a in arms if a not in empty]
    if is_stmt and len(empty) == 1 and others and all(last_stmt_returns(s, e) for _, s, e in others):
        ranges.append((match[ob] + 1, enclosing_block_end(m.start()), empty[0][0][0] + "-tail"))

for m in re.finditer(r"if \(comptime target\.toCpuArch\(\) == \.(\w+)\)", clean):
    arch = m.group(1)
    other = {"aarch64": "x86_64", "x86_64": "aarch64"}[arch]
    j = m.end()
    while clean[j].isspace():
        j += 1
    if clean[j] == "{":
        then_end = match[j]
    else:
        k = j
        while clean[k] != ";" and not clean.startswith("else", k):
            k = match[k] + 1 if clean[k] in "({[" else k + 1
        then_end = k - 1
    ranges.append((j, then_end + 1, arch))
    k = then_end + 1
    while clean[k].isspace():
        k += 1
    if clean.startswith("else", k):
        k += 4
        while clean[k].isspace():
            k += 1
        if clean[k] == "{":
            ranges.append((k, match[k] + 1, other))
        else:
            e = k
            while clean[e] != ";":
                e = match[e] + 1 if clean[e] in "({[" else e + 1
            ranges.append((k, e + 1, other))

site_lines = {}
for m in re.finditer(r"\.w64\b", clean):
    label = "shared"
    best = None
    for s, e, lab in ranges:
        if s <= m.start() < e and (best is None or s >= best[0]):
            best = (s, lab)
    if best:
        label = best[1]
    site_lines.setdefault(line_of[m.start()], []).append(label)

rows = [r.rstrip("\n").split("\t") for r in open(sys.argv[2], encoding="utf-8")]
seen = {}
diffs = 0
for line, fn, helper, c, code in rows:
    l = int(line)
    k = seen.get(l, 0)
    seen[l] = k + 1
    mine = site_lines.get(l, ["(none)"])[k] if k < len(site_lines.get(l, [])) else "(none)"
    theirs = c if not c.startswith("fn:") else "fn"
    if mine != theirs and not (theirs == "fn"):
        diffs += 1
        print(f"{l}\t{fn}\tscript={c}\tbrace={mine}")
    if theirs == "fn" and mine != "shared":
        print(f"{l}\t{fn}\tscript={c}\tbrace={mine} (named fn)")
extra = sum(len(v) for v in site_lines.values()) - len(rows)
print(f"differences: {diffs}; brace sites minus script sites: {extra}")
