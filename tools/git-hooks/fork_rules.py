#!/usr/bin/env python3
"""Check the fork's commit rules before a commit or a push.

The rules:
- No upstream references: `#NNNN` (4 to 6 digits), `roc-lang/roc#N`,
  `roc-lang#N`, or github.com/roc-lang/roc issue and PR links. This applies
  to commit messages and to the lines a commit adds. An ARM immediate right
  after a register (`r11, #4080`, `[sp, #4095]`) is not a reference.
- No Co-Authored-By or Claude-Session lines, and no claude.ai session links.
- Not the words "personal" and "note" side by side.
- Every commit we push is signed.

Text that comes from upstream is never checked: commits that upstream
already has, and lines a merge takes unchanged from the merged branch.

Usage, from the hooks:
  fork_rules.py staged          pre-commit: the staged lines
  fork_rules.py msg <file>      commit-msg: the message
  fork_rules.py push            pre-push: the commits being pushed (stdin)
"""

import os
import re
import subprocess
import sys

ZERO = "0" * 40

ASM_REG = r"(?:r\d{1,2}|sp|lr|pc|fp|ip|[sdqxw]\d{1,2})"
HASH_NUM = re.compile(r"(" + ASM_REG + r"\]?,\s*)?#(\d{4,6})\b")
UPSTREAM_LINK = re.compile(
    r"roc-lang(?:/roc)?#\d+|github\.com/roc-lang/roc/(?:issues|pull)/\d+", re.I
)
TRAILER = re.compile(r"^\s*(?:Co-Authored-By|Claude-Session)\s*:", re.I | re.M)
SESSION_LINK = re.compile(r"claude\.ai/code/session", re.I)
PERSONAL_NOTE = re.compile(r"personal\s+note", re.I)


def git(*args, check=True):
    out = subprocess.run(["git", *args], capture_output=True, check=False)
    if check and out.returncode != 0:
        sys.stderr.write(out.stderr.decode(errors="replace"))
        sys.exit(2)
    return out.stdout.decode(errors="replace")


def line_problems(text):
    """Problems in one line of a file or a message."""
    found = []
    for m in HASH_NUM.finditer(text):
        if m.group(1) is None:
            found.append(f"upstream reference #{m.group(2)}")
    for m in UPSTREAM_LINK.finditer(text):
        found.append(f"upstream reference {m.group(0)}")
    if SESSION_LINK.search(text):
        found.append("Claude session link")
    if PERSONAL_NOTE.search(text):
        found.append("the words \"personal\" and \"note\" side by side")
    return found


def message_problems(msg, strip_comments=False):
    """strip_comments: git's own "#" help lines in a commit-msg file."""
    found = []
    lines = msg.splitlines()
    if strip_comments:
        lines = [l for l in lines if not l.startswith("#")]
    body = "\n".join(lines)
    if TRAILER.search(body):
        found.append("Co-Authored-By or Claude-Session line")
    for n, line in enumerate(lines, 1):
        for p in line_problems(line):
            found.append(f"message line {n}: {p}")
    return found


def added_lines(diff):
    """(path, line) for each added line in a unified diff."""
    path = None
    for line in diff.splitlines():
        if line.startswith("+++ "):
            path = line[6:] if line.startswith("+++ b/") else None
        elif line.startswith("+") and path is not None:
            yield path, line[1:]


def blob_lines(rev, path, cache):
    key = (rev, path)
    if key not in cache:
        out = subprocess.run(
            ["git", "show", f"{rev}:{path}"], capture_output=True, check=False
        )
        text = out.stdout.decode(errors="replace") if out.returncode == 0 else ""
        cache[key] = set(text.splitlines())
    return cache[key]


def diff_problems(diff, other_parents):
    """Problems in added lines. A line found in the same file on another
    parent of a merge came from that branch, so it is not ours."""
    found = []
    cache = {}
    for path, text in added_lines(diff):
        problems = line_problems(text)
        if not problems:
            continue
        if any(text in blob_lines(p, path, cache) for p in other_parents):
            continue
        for p in problems:
            found.append(f"{path}: {p}: {text.strip()[:100]}")
    return found


def is_signed(commit):
    raw = git("cat-file", "commit", commit)
    header = raw.split("\n\n", 1)[0]
    return any(l.startswith("gpgsig") for l in header.splitlines())


def check_staged():
    other = []
    merge_head = os.path.join(git("rev-parse", "--git-dir").strip(), "MERGE_HEAD")
    if os.path.exists(merge_head):
        other = open(merge_head).read().split()
    has_head = subprocess.run(
        ["git", "rev-parse", "--verify", "-q", "HEAD"], capture_output=True
    ).returncode == 0
    base = "HEAD" if has_head else git("hash-object", "-t", "tree", "/dev/null").strip()
    diff = git("diff", "--cached", "--no-color", "--no-ext-diff", "-U0", base)
    return diff_problems(diff, other)


def check_message(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        return message_problems(f.read(), strip_comments=True)


def check_commit(commit):
    found = []
    if not is_signed(commit):
        found.append("not signed")
    found += message_problems(git("log", "-1", "--format=%B", commit))
    parents = git("rev-list", "--parents", "-n", "1", commit).split()[1:]
    if parents:
        diff = git("diff", "--no-color", "--no-ext-diff", "-U0", parents[0], commit)
    else:
        diff = git("show", "--no-color", "--format=", "-U0", commit)
    found += diff_problems(diff, parents[1:])
    return found


def check_push(stdin):
    found = []
    for line in stdin.splitlines():
        parts = line.split()
        if len(parts) != 4:
            continue
        local_ref, local_sha, _remote_ref, remote_sha = parts
        if local_sha == ZERO:
            continue  # deleting a branch
        exclude = ["--remotes=upstream"]
        if remote_sha != ZERO:
            has = subprocess.run(
                ["git", "cat-file", "-e", remote_sha], capture_output=True
            ).returncode == 0
            if has:
                exclude.append(remote_sha)
        commits = git("rev-list", local_sha, "--not", *exclude).split()
        for c in commits:
            for p in check_commit(c):
                found.append(f"{c[:10]} ({local_ref}): {p}")
    return found


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    mode = sys.argv[1]
    if mode == "staged":
        found = check_staged()
    elif mode == "msg" and len(sys.argv) == 3:
        found = check_message(sys.argv[2])
    elif mode == "push":
        found = check_push(sys.stdin.read())
    else:
        print(__doc__)
        return 2
    if found:
        sys.stderr.write(f"fork rules ({mode}): {len(found)} problem(s)\n")
        for p in found:
            sys.stderr.write(f"  {p}\n")
        sys.stderr.write(
            "Write upstream numbers without # (or leave them out of commit "
            "messages), drop the trailer or session link, and sign with -S. "
            "The rules are at the top of fork_rules.py.\n"
        )
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
