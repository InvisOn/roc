#!/usr/bin/env python3
"""Resolve cherry-pick conflicts between the switch conversion (HEAD) and a
word-size commit (theirs) by keeping HEAD's switch structure and replaying
the commit's line-level edits: `.w64` -> `word` and the `word` -> `instruction`
rename, at the same calls. Prints what it did; refuses anything else."""
import re, sys
p = sys.argv[1]
s = open(p).read()
pat = re.compile(r"<<<<<<< [^\n]*\n(.*?)=======\n(.*?)>>>>>>> [^\n]*\n", re.S)
def fix(m):
    head, theirs = m.group(1), m.group(2)
    out = head
    # width swaps: a call that is `word` in theirs and `.w64` in head
    for call in set(re.findall(r"(\w+)\(word,", theirs)):
        out = re.sub(r"\b" + call + r"\(\.w64,", call + "(word,", out)
    if "|instruction, i|" in theirs:
        out = out.replace("|word, i|", "|instruction, i|").replace("@bitCast(word)", "@bitCast(instruction)").replace(", word, .little", ", instruction, .little")
    if "const instruction = " in theirs:
        out = out.replace("const word = std.mem.readInt", "const instruction = std.mem.readInt").replace("word & 0xFC000000", "instruction & 0xFC000000")
    print("resolved hunk:", out.count("word"), "word mentions", file=sys.stderr)
    return out
s, n = pat.subn(fix, s)
open(p, "w").write(s)
print(n, "hunks", file=sys.stderr)
