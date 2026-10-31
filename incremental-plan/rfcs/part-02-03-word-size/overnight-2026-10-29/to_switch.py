#!/usr/bin/env python3
"""Rewrite the dev backend's two-way instruction-set tests as exhaustive
`switch (isa)` statements and expressions, for a whole source tree.

usage: to_switch.py <repo-root>

Input: a tree in its `binaryIs` form (`isa.binaryIs(.x)` tests, and the
cached `is_x86_64` / `is_aarch64` flags in `FrameBuilder` and
`CallingConvention`). Output, in place: the same tree with every such test a
`switch (isa)`, `binaryIs` deleted from `isa.zig`, and `zig fmt` applied.

Steps:
  1. delete the cached-flag definitions, then convert the flags and the
     `binaryIs` atoms (the `if`/`else` forms become switches);
  2. `zig fmt`;
  3. polish: fold each condition that combines the instruction set with
     something else into a switch that names each backend's answer;
  4. `zig fmt`, and strip `binaryIs` from `isa.zig`;
  5. assert nothing is left: no `binaryIs`, no cached flag, and no switch
     whose arms are only `true` / `false`.

Any shape the script does not know stops it with an error; nothing is
skipped. Prints a census per file to stderr.
"""
import os
import re
import subprocess
import sys

ISAS = ("x86_64", "aarch64")
DEV = "src/backend/dev"
CONVERTED = ("LirCodeGen.zig", "FrameBuilder.zig", "CallingConvention.zig")
FLAG_FILES = ("FrameBuilder.zig", "CallingConvention.zig")


class Unhandled(Exception):
    pass


def other(x):
    return ISAS[1] if x == ISAS[0] else ISAS[0]


def scan(s, i, stops):
    """From i, walk at bracket depth 0 and return (index, token) of the first
    stop. stops: set of chars ',', ';', ')', ']', '}' (closing ones only when
    they would go below depth 0) and the word 'else'."""
    depth = 0
    n = len(s)
    while i < n:
        c = s[i]
        if c == '/' and s.startswith('//', i):
            i = s.index('\n', i)
            continue
        if c == '\\' and s.startswith('\\\\', i):
            i = s.index('\n', i)
            continue
        if c == '"':
            i += 1
            while s[i] != '"':
                i += 2 if s[i] == '\\' else 1
            i += 1
            continue
        if c == "'":
            i += 1
            while s[i] != "'":
                i += 2 if s[i] == '\\' else 1
            i += 1
            continue
        if c in '([{':
            depth += 1
        elif c in ')]}':
            if depth == 0:
                if c in stops:
                    return i, c
                raise ValueError("unbalanced at %d" % i)
            depth -= 1
        elif depth == 0:
            if c in stops and c in ',;':
                return i, c
            if 'else' in stops and s.startswith('else', i) and not (s[i - 1].isalnum() or s[i - 1] == '_') and not (s[i + 4].isalnum() or s[i + 4] == '_'):
                return i, 'else'
        i += 1
    raise ValueError("ran off end")


def match_block(s, i):
    """s[i] == '{'; return index just past the matching '}'."""
    assert s[i] == '{', s[i:i + 40]
    j, _ = scan(s, i + 1, {'}'})
    return j + 1


def ws(s, i):
    while s[i] in ' \t\n':
        i += 1
    return i


def is_word_at(s, i, word):
    n = len(word)
    return s.startswith(word, i) and not (s[i + n].isalnum() or s[i + n] == '_')


def is_statement(s, i):
    j = i - 1
    while s[j] in ' \t\n':
        j -= 1
    return s[j] in '{};'


def where(s, i):
    return "line %d: %s" % (s.count('\n', 0, i) + 1, s[i:i + 80].split('\n')[0])


def single_statement(block):
    """`{ stmt; }` -> `stmt`, for a block holding one expression statement."""
    inner = block[1:-1].strip()
    if not inner.endswith(';'):
        raise Unhandled("block is not one statement: " + inner[:80])
    body = inner[:-1]
    e, tok = scan(body + ';', 0, {';'})
    if e != len(body) or '//' in body or re.match(r"(const|var)\b", body):
        raise Unhandled("block is not one expression statement: " + inner[:80])
    return body


def if_chain_end(s, k):
    """s[k:] starts with `if (`; return the end of the whole if/else chain
    used as a statement."""
    assert s.startswith('if (', k)
    p, _ = scan(s, k + 4, {')'})
    i = ws(s, p + 1)
    if s[i] == '|':
        i = ws(s, s.index('|', i + 1) + 1)
    if s[i] == '{':
        e = match_block(s, i)
    else:
        e, tok = scan(s, i, {'else', ';'})
        if tok == ';':
            return e + 1
    j = ws(s, e)
    if is_word_at(s, j, 'else'):
        k2 = ws(s, j + 4)
        if s.startswith('if (', k2):
            return if_chain_end(s, k2)
        if s[k2] == '{':
            return match_block(s, k2)
        if s.startswith('switch (', k2):
            p2, _ = scan(s, k2 + 8, {')'})
            return match_block(s, ws(s, p2 + 1))
        e2, _ = scan(s, k2, {';'})
        return e2 + 1
    return e


def convert(s, mode, census):
    """Step 1: `if`/`else` on one instruction-set atom becomes a switch; an
    atom inside a larger condition becomes a bool-valued switch, which the
    polish step folds."""
    if mode == "binaryis":
        isa_expr = r"(?P<isa>isa|isaOf\((?:[^()]|\([^()]*\))*\))"
        atom = r"(?P<ct>comptime\s+)?(?P<neg>!)?" + isa_expr + r"\.binaryIs\(\.(?P<which>x86_64|aarch64)\)"
    else:
        atom = r"(?P<ct>comptime\s+)?(?P<neg>!)?(?P<isa>)is_(?P<which>x86_64|aarch64)\b"
    if_re = re.compile(r"\bif \(" + atom + r"\)")
    atom_re = re.compile(atom)

    def isa_operand(m):
        e = m.group("isa")
        if mode == "flags" or e == "isa" or e == "":
            return "isa"
        return "comptime " + e

    def side(m):
        w = m.group("which")
        return other(w) if m.group("neg") else w

    out = []
    pos = 0
    while True:
        m = if_re.search(s, pos)
        if not m:
            break
        line_start = s.rfind('\n', 0, m.start()) + 1
        if '//' in s[line_start:m.start()]:
            out.append(s[pos:m.end()])
            pos = m.end()
            continue
        which = side(m)
        op = isa_operand(m)
        i = ws(s, m.end())
        if s[i] == '{':
            then_end = match_block(s, i)
            then_txt = s[i:then_end]
            j = ws(s, then_end)
            if is_word_at(s, j, 'else'):
                k = ws(s, j + 4)
                if s[k] == '{':
                    else_end = match_block(s, k)
                    else_txt = s[k:else_end]
                    census["stmt_block"] += 1
                elif s.startswith('switch (', k):
                    # `if (atom) { .. } else switch (x) { .. }`
                    p2, _ = scan(s, k + 8, {')'})
                    else_end = match_block(s, ws(s, p2 + 1))
                    else_txt = s[k:else_end]
                    census["stmt_else_switch"] += 1
                elif s.startswith('if (', k):
                    m2 = if_re.match(s, k)
                    if m2:
                        if side(m2) != other(which):
                            raise Unhandled("else-if names the same instruction set, " + where(s, m.start()))
                        b = ws(s, m2.end())
                        b_end = match_block(s, b)
                        else_txt = s[b:b_end]
                        # drop a trailing `else { unreachable / compileError }`
                        e = ws(s, b_end)
                        if is_word_at(s, e, 'else'):
                            e2 = ws(s, e + 4)
                            e_end = match_block(s, e2) if s[e2] == '{' else scan(s, e2, {';'})[0] + 1
                            tail = s[e2:e_end]
                            if not ('unreachable' in tail or '@compileError' in tail):
                                raise Unhandled("third branch is not unreachable, " + where(s, m.start()))
                            else_end = e_end
                        else:
                            else_end = b_end
                        census["chain_flattened"] += 1
                    else:
                        else_end = if_chain_end(s, k)
                        else_txt = s[k:else_end]
                        census["chain_rest"] += 1
                else:
                    # `.tag => if (atom) { stmt; } else expr,`: an expression
                    # switch whose arms are the statement and the expression.
                    e, tok = scan(s, k, {';', ',', ')', ']', '}'})
                    if tok != ',':
                        raise Unhandled("block then, bare else not in a list, " + where(s, m.start()))
                    else_txt = s[k:e].rstrip()
                    repl = "switch (%s) { .%s => %s, .%s => %s }" % (op, which, single_statement(then_txt), other(which), else_txt)
                    census["expr_block_then"] += 1
                    out.append(s[pos:m.start()])
                    out.append(repl)
                    pos = k + len(else_txt)
                    continue
                end = else_end
            else:
                else_txt = "{}"
                end = then_end
                census["stmt_noelse"] += 1
            repl = "switch (%s) {\n.%s => %s,\n.%s => %s,\n}" % (op, which, then_txt, other(which), else_txt)
        else:
            j, tok = scan(s, i, {'else', ';', ',', ')', ']', '}'})
            then_txt = s[i:j].rstrip()
            if tok == ';':
                # statement without braces or else: `if (c) stmt;`
                repl = "switch (%s) {\n.%s => %s,\n.%s => {},\n}" % (op, which, then_txt, other(which))
                end = j + 1
                census["stmt_bare"] += 1
            elif tok == 'else':
                k = ws(s, j + 4)
                m2 = if_re.match(s, k) if s.startswith('if ', k) else None
                if m2:
                    if side(m2) != other(which):
                        raise Unhandled("else-if names the same instruction set, " + where(s, m.start()))
                    b = ws(s, m2.end())
                    e, _ = scan(s, b, {'else'})
                    y_txt = s[b:e].rstrip()
                    z = ws(s, e + 4)
                    e3, _ = scan(s, z, {';', ',', ')', ']', '}'})
                    if not ('unreachable' in s[z:e3] or '@compileError' in s[z:e3]):
                        raise Unhandled("third branch is not unreachable, " + where(s, m.start()))
                    repl = "switch (%s) { .%s => %s, .%s => %s }" % (op, which, then_txt, other(which), y_txt)
                    end = z + len(s[z:e3].rstrip())
                    census["expr_chain"] += 1
                    out.append(s[pos:m.start()])
                    out.append(repl)
                    pos = end
                    continue
                if s[k] == '{' and (then_txt.endswith('}') or then_txt.endswith(';')):
                    raise Unhandled("bare then with block else, " + where(s, m.start()))
                e, _ = scan(s, k, {';', ',', ')', ']', '}'})
                else_txt = s[k:e].rstrip()
                repl = "switch (%s) { .%s => %s, .%s => %s }" % (op, which, then_txt, other(which), else_txt)
                end = k + len(else_txt)
                if is_statement(s, m.start()) and s[end] == ';':
                    end += 1
                census["expr"] += 1
            else:
                raise Unhandled("bare then ending in '%s', %s" % (tok, where(s, m.start())))
        out.append(s[pos:m.start()])
        out.append(repl)
        pos = end
    out.append(s[pos:])
    s = "".join(out)

    # Atoms left inside larger conditions: bool-valued switches.
    def bool_sw(m):
        line_start = s.rfind('\n', 0, m.start()) + 1
        if '//' in s[line_start:m.start()]:
            return m.group(0)
        census["bool_atom"] += 1
        which = m.group("which")
        t, f = ("false", "true") if m.group("neg") else ("true", "false")
        ct = m.group("ct") or ""
        return "%s(switch (%s) { .%s => %s, .%s => %s })" % (ct, isa_operand(m), which, t, other(which), f)

    return atom_re.sub(bool_sw, s)


# A bool-valued switch as step 1 writes it, after zig fmt.
BOOL_SW = (r"\(switch \(isa\) \{\n[ \t]*\.(?P<a>x86_64|aarch64) => (?P<av>true|false),\n"
           r"[ \t]*\.(?P<b>x86_64|aarch64) => (?P<bv>true|false),\n[ \t]*\}\)")
# Any switch, on anything, whose two arms are bool literals.
LEFTOVER_BOOL_SW = re.compile(r"switch \([^)\n]*\) \{\n[ \t]*\.\w+ => (true|false),\n[ \t]*\.\w+ => (true|false),\n[ \t]*\}")


def true_side(m):
    if m.group("av") == m.group("bv"):
        raise Unhandled("both arms are " + m.group("av"))
    return (m.group("a"), m.group("b")) if m.group("av") == "true" else (m.group("b"), m.group("a"))


def no_top_level_or(c):
    if re.search(r"\bor\b", c):
        raise Unhandled("condition has an `or`: " + c)
    return c


def switch2(arms):
    return "switch (isa) {\n" + "".join(".%s => %s,\n" % a for a in arms) + "}"


def polish(s, census):
    """Step 3: fold each bool-valued switch into the condition around it, so
    every switch names each backend's own answer."""

    # `const n = comptime (SW);` then `if (n or c) {`: c moves into the false
    # arm (n is used nowhere else).
    r = re.compile(r"const (?P<n>\w+) = comptime " + BOOL_SW + r";\n(?P<ind>[ \t]*)if \((?P=n) or (?P<c>[^\n]+?)\) \{\n")
    while True:
        m = r.search(s)
        if not m:
            break
        t, f = true_side(m)
        c = no_top_level_or(m.group("c"))
        val = {t: "true", f: c}
        repl = "const %s = %s;\n%sif (%s) {\n" % (m.group("n"), switch2([(m.group("a"), val[m.group("a")]), (m.group("b"), val[m.group("b")])]), m.group("ind"), m.group("n"))
        block_end, _ = scan(s, m.start(), {'}'})
        uses = len(re.findall(r"\b%s\b" % m.group("n"), s[m.start():block_end]))
        if uses != 2:
            raise Unhandled("%s is used %d times in its block" % (m.group("n"), uses))
        s = s[:m.start()] + repl + s[m.end():]
        census["fold_or_into_false_arm"] += 1

    # `if (c and comptime (SW)) {\n stmt;\n}` with no else: c guards the
    # statement inside the true arm; the other arm does nothing.
    r = re.compile(r"if \((?P<c>[^\n]+?) and comptime " + BOOL_SW + r"\) \{\n[ \t]*(?P<stmt>[^\n]+);\n[ \t]*\}")
    while True:
        m = r.search(s)
        if not m:
            break
        if is_word_at(s, ws(s, m.end()), 'else'):
            raise Unhandled("guarded statement has an else, " + where(s, m.start()))
        t, f = true_side(m)
        c = no_top_level_or(m.group("c"))
        stmt = single_statement("{" + m.group("stmt") + ";}")
        s = s[:m.start()] + switch2([(t, "if (%s) %s" % (c, stmt)), (f, "{}")]) + s[m.end():]
        census["fold_guarded_statement"] += 1

    # `const n = c and comptime (SW);`: c becomes the true arm's value.
    r = re.compile(r"(?P<lead>(?:const|var) \w+ = )(?P<c>[^;\n]+?) and comptime " + BOOL_SW + r";")
    while True:
        m = r.search(s)
        if not m:
            break
        t, _ = true_side(m)
        c = no_top_level_or(m.group("c"))
        val = {m.group("a"): "false", m.group("b"): "false"}
        val[t] = c
        s = s[:m.start()] + m.group("lead") + switch2([(m.group("a"), val[m.group("a")]), (m.group("b"), val[m.group("b")])]) + ";" + s[m.end():]
        census["fold_and_before"] += 1

    # `[comptime ](SW) and c`: c becomes the true arm's value.
    r = re.compile(r"(?P<ct>comptime )?" + BOOL_SW + r" and ")
    while True:
        m = r.search(s)
        if not m:
            break
        e, _ = scan(s, m.end(), {')', ';', ','})
        c = no_top_level_or(s[m.end():e].strip())
        t, _ = true_side(m)
        val = {m.group("a"): "false", m.group("b"): "false"}
        val[t] = c
        s = s[:m.start()] + (m.group("ct") or "") + switch2([(m.group("a"), val[m.group("a")]), (m.group("b"), val[m.group("b")])]) + s[e:]
        census["fold_and_after"] += 1

    return s


ISA_DOC_BINARYIS = """/// The instruction set a dev-backend component is instantiated for. Every
/// instruction-set decision in the shared driver (`LirCodeGen`,
/// `FrameBuilder`, `CallingConvention`) is either an exhaustive `switch` on
/// this or a `binaryIs` test.
"""
ISA_DOC_SWITCH = """/// The instruction set a dev-backend component is instantiated for. Every
/// instruction-set choice in the shared driver (`LirCodeGen`, `FrameBuilder`,
/// `CallingConvention`) is an exhaustive `switch` on this, never `isa == .x`:
/// adding an instruction set then makes each choice a compile error until it
/// has an answer for the new one.
"""


def replace_once(s, pattern, repl, what, flags=0):
    s2, n = re.subn(pattern, repl, s, flags=flags)
    if n != 1:
        raise Unhandled("isa.zig: %s found %d times" % (what, n))
    return s2


def strip_isa(s):
    s = replace_once(s, re.escape(ISA_DOC_BINARYIS), ISA_DOC_SWITCH.replace('\\', r'\\'), "binaryIs doc comment")
    s = replace_once(s, r"\n\n    /// A two-way x86_64/aarch64 decision[\s\S]*?\n    pub inline fn binaryIs\([\s\S]*?\n    \}\n", "\n", "binaryIs function")
    s = replace_once(s, r"\n\ntest \"binaryIs [^\"\n]*\" \{\n[\s\S]*?\n\}\n", "\n", "binaryIs test")
    return s


def zig_fmt(paths):
    subprocess.run(["zig", "fmt"] + list(paths), check=True, stdout=subprocess.DEVNULL)


def main():
    root = sys.argv[1]
    dev = os.path.join(root, DEV)
    paths = [os.path.join(dev, f) for f in CONVERTED]
    texts = {}
    for f, p in zip(CONVERTED, paths):
        census = {k: 0 for k in ("flag_defs", "stmt_block", "stmt_else_switch", "stmt_noelse", "stmt_bare", "expr",
                                  "expr_block_then", "expr_chain", "chain_flattened", "chain_rest", "bool_atom")}
        s = open(p).read()
        if f in FLAG_FILES:
            s, n = re.subn(r"(?m)^[ \t]*const is_(x86_64|aarch64) = isa\.binaryIs\(\.\1\);\n", "", s)
            if n != 2:
                raise Unhandled("%s: %d cached-flag definitions, expected 2" % (f, n))
            census["flag_defs"] = n
            s = convert(s, "flags", census)
        s = convert(s, "binaryis", census)
        open(p, "w").write(s)
        texts[f] = census
    zig_fmt(paths)
    for f, p in zip(CONVERTED, paths):
        census = {k: 0 for k in ("fold_or_into_false_arm", "fold_guarded_statement", "fold_and_before", "fold_and_after")}
        s = polish(open(p).read(), census)
        open(p, "w").write(s)
        texts[f].update(census)
    zig_fmt(paths)

    isa_path = os.path.join(dev, "isa.zig")
    s = strip_isa(open(isa_path).read())
    open(isa_path, "w").write(s)
    zig_fmt([isa_path])

    for f, p in zip(CONVERTED, paths):
        s = open(p).read()
        if "binaryIs" in s:
            raise Unhandled("%s: binaryIs left, %s" % (f, where(s, s.index("binaryIs"))))
        m = re.search(r"\bis_(x86_64|aarch64)\b", s)
        if m:
            raise Unhandled("%s: cached flag left, %s" % (f, where(s, m.start())))
        m = LEFTOVER_BOOL_SW.search(s)
        if m:
            raise Unhandled("%s: true/false switch left, %s" % (f, where(s, m.start())))
        print(f, {k: v for k, v in texts[f].items() if v}, file=sys.stderr)
    left = subprocess.run(["git", "-C", root, "grep", "-n", "binaryIs", "--", "src"], capture_output=True, text=True).stdout
    if left:
        raise Unhandled("binaryIs left in the tree:\n" + left)


if __name__ == "__main__":
    try:
        main()
    except Unhandled as e:
        sys.exit("to_switch.py: " + str(e))
