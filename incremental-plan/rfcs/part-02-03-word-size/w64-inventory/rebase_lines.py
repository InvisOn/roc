"""Move the line numbers in the classify scripts to a new base commit.

Usage: python3 -I rebase_lines.py <repo> <old commit> <new commit> <file in repo> <script>...

Maps each line of <file> at <old commit> to its line at <new commit> using
`git diff -U0` (git is run with `-C <repo>`), and rewrites every number inside
the `lines(...)` calls of each script. A number whose line was changed or
deleted has no new line; the script then stops, lists those numbers, and
writes nothing. Run the classify scripts afterwards: lines new at <new
commit> show up as unclassified sites there.
"""
import re
import subprocess
import sys

repo, old, new, path = sys.argv[1:5]
scripts = sys.argv[5:]

diff = subprocess.run(["git", "-C", repo, "diff", "-U0", old, new, "--", path],
                      check=True, capture_output=True, text=True).stdout
hunks = []  # (old_start, old_count, new_start, new_count)
for m in re.finditer(r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@", diff, re.M):
    hunks.append((int(m.group(1)), int(m.group(2) or 1), int(m.group(3)), int(m.group(4) or 1)))

def new_line(n):
    shift = 0
    for os_, oc, ns, nc in hunks:
        old_end = os_ + oc - 1 if oc else os_
        if oc and os_ <= n <= old_end:
            return None  # changed or deleted
        if (oc and n > old_end) or (not oc and n > os_):
            shift = (ns + nc - 1 if nc else ns) - (old_end if oc else os_)
    return n + shift

lost = set()
outputs = {}

def move(n):
    moved = new_line(n)
    if moved is None:
        lost.add(n)
        return n
    return moved

for script in scripts:
    text = open(script, encoding="utf-8").read()
    out = []
    i = 0
    for m in re.finditer(r"\blines\(", text):
        if m.start() < i:
            continue
        out.append(text[i:m.end()])
        # Scan to the matching ")", skipping comments; move numbers outside
        # comments, after the kind argument.
        j = m.end()
        depth = 1
        seen_comma = False
        while depth:
            ch = text[j]
            if ch == "#":
                k = text.index("\n", j)
                out.append(text[j:k])
                j = k
                continue
            if ch == "(":
                depth += 1
            elif ch == ")":
                depth -= 1
                if depth == 0:
                    break
            elif ch == "," and depth == 1:
                seen_comma = True
            if ch.isdigit() and seen_comma and not text[j - 1].isalnum():
                k = j
                while text[k].isdigit():
                    k += 1
                out.append(str(move(int(text[j:k]))))
                j = k
                continue
            out.append(ch)
            j += 1
        out.append(")")
        i = j + 1
    out.append(text[i:])
    outputs[script] = "".join(out)
if lost:
    sys.exit(f"lines changed or deleted at {new}: {sorted(lost)}")
for script, text in outputs.items():
    open(script, "w", encoding="utf-8").write(text)
print(f"moved line numbers in {len(scripts)} scripts ({len(hunks)} hunks)")
