#!/usr/bin/env python3
"""Rewrite two-way ISA tests in the dev backend's shared driver as exhaustive
`switch (isa)` statements/expressions. Experiment only.

usage: to_switch.py <file> <mode>
  mode "binaryis": atoms are `[comptime] [!]isa.binaryIs(.X)` and
                   `[comptime] [!]isaOf(...).binaryIs(.X)`
  mode "flags":    atoms are `[comptime] [!]is_x86_64` / `is_aarch64`
Prints a census to stderr; rewrites the file in place.
"""
import re
import sys

ISAS = ("x86_64", "aarch64")


def other(x):
    return ISAS[1] if x == ISAS[0] else ISAS[0]


def skip_trivia(s, i):
    """Index of the next char that is not inside a string/char/comment."""
    return i


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


def is_statement(s, i):
    j = i - 1
    while s[j] in ' \t\n':
        j -= 1
    return s[j] in '{};'


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
    if s.startswith('else', j) and not (s[j + 4].isalnum() or s[j + 4] == '_'):
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


def main():
    path, mode = sys.argv[1], sys.argv[2]
    s = open(path).read()
    if mode == "binaryis":
        isa_expr = r"(?P<isa>isa|isaOf\((?:[^()]|\([^()]*\))*\))"
        atom = r"(?P<ct>comptime\s+)?(?P<neg>!)?" + isa_expr + r"\.binaryIs\(\.(?P<which>x86_64|aarch64)\)"
    else:
        atom = r"(?P<ct>comptime\s+)?(?P<neg>!)?(?P<isa>)is_(?P<which>x86_64|aarch64)\b"
    if_re = re.compile(r"\bif \(" + atom + r"\)")
    atom_re = re.compile(atom)
    census = {"stmt_block": 0, "stmt_noelse": 0, "stmt_bare": 0, "expr": 0, "chain_flattened": 0, "bool_atom": 0, "skipped": 0}

    def isa_operand(m):
        e = m.group("isa")
        if mode == "flags" or e == "isa" or e == "":
            return "isa"
        return "comptime " + e

    out = []
    pos = 0
    while True:
        m = if_re.search(s, pos)
        if not m:
            break
        # skip occurrences inside comments
        line_start = s.rfind('\n', 0, m.start()) + 1
        if '//' in s[line_start:m.start()]:
            out.append(s[pos:m.end()])
            pos = m.end()
            continue
        which = m.group("which")
        if m.group("neg"):
            which = other(which)
        op = isa_operand(m)
        i = ws(s, m.end())
        then_start = i
        if s[i] == '{':
            then_end = match_block(s, i)
            then_txt = s[then_start:then_end]
            j = ws(s, then_end)
            if s.startswith('else', j) and not (s[j + 4].isalnum() or s[j + 4] == '_'):
                k = ws(s, j + 4)
                if s[k] == '{':
                    else_end = match_block(s, k)
                    else_txt = s[k:else_end]
                    census["stmt_block"] += 1
                elif s.startswith('if (', k):
                    m2 = if_re.match(s, k)
                    if m2:
                        w2 = m2.group("which")
                        if m2.group("neg"):
                            w2 = other(w2)
                        if w2 != other(which):
                            census["skipped"] += 1
                            out.append(s[pos:m.end()])
                            pos = m.end()
                            continue
                        b = ws(s, m2.end())
                        b_end = match_block(s, b)
                        else_txt = s[b:b_end]
                        # drop a trailing `else { unreachable / compileError }`
                        e = ws(s, b_end)
                        if s.startswith('else', e):
                            e2 = ws(s, e + 4)
                            e_end = match_block(s, e2) if s[e2] == '{' else scan(s, e2, {';'})[0] + 1
                            tail = s[e2:e_end]
                            assert 'unreachable' in tail or '@compileError' in tail, tail
                            else_end = e_end
                        else:
                            else_end = b_end
                        census["chain_flattened"] += 1
                    else:
                        else_end = if_chain_end(s, k)
                        else_txt = s[k:else_end]
                        census["chain_rest"] = census.get("chain_rest", 0) + 1
                else:
                    census["skipped"] += 1
                    out.append(s[pos:m.end()])
                    pos = m.end()
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
                    w2 = m2.group("which")
                    if m2.group("neg"):
                        w2 = other(w2)
                    assert w2 == other(which)
                    b = ws(s, m2.end())
                    e, _ = scan(s, b, {'else'})
                    y_txt = s[b:e].rstrip()
                    z = ws(s, e + 4)
                    e3, _ = scan(s, z, {';', ',', ')', ']', '}'})
                    assert 'unreachable' in s[z:e3] or '@compileError' in s[z:e3], s[z:e3]
                    repl = "switch (%s) { .%s => %s, .%s => %s }" % (op, which, then_txt, other(which), y_txt)
                    end = z + len(s[z:e3].rstrip())
                    census["expr_chain"] = census.get("expr_chain", 0) + 1
                    out.append(s[pos:m.start()]); out.append(repl); pos = end
                    continue
                if s[k] == '{' and (then_txt.endswith('}') or then_txt.endswith(';')):
                    census["skipped"] += 1
                    out.append(s[pos:m.end()])
                    pos = m.end()
                    continue
                e, _ = scan(s, k, {';', ',', ')', ']', '}'})
                else_txt = s[k:e].rstrip()
                repl = "switch (%s) { .%s => %s, .%s => %s }" % (op, which, then_txt, other(which), else_txt)
                end = k + len(s[k:e].rstrip())
                if is_statement(s, m.start()) and s[end] == ';':
                    end += 1
                census["expr"] += 1
            else:
                census["skipped"] += 1
                out.append(s[pos:m.end()])
                pos = m.end()
                continue
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

    s = atom_re.sub(bool_sw, s)
    open(path, "w").write(s)
    print(census, file=sys.stderr)


if __name__ == "__main__":
    main()
