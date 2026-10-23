#!/usr/bin/env python3
"""Relative 64-bit oracle (part 5 of the arm32 verification plan).

After merging upstream `main` into the arm32 branch, the committed 64-bit
golden hashes describe the old base, so the check becomes relative: the
merged tip must produce exactly the x86_64 and aarch64 output that the
merged upstream commit produces.

    python3 relative_oracle.py --upstream <upstream-commit> --merged <merge-commit> --work <dir>
    python3 relative_oracle.py --upstream <base> --merged <pr-head> --apply-a0-to-merged
    python3 relative_oracle.py --self-test

For each side it makes a detached worktree, builds the eval runner, writes
the per-case dev-code hashes (`--write-dev-code-hashes`) and regenerates the
`dev_object` snapshots. Upstream has no hash mode, so A0's oracle commit is
applied to the upstream worktree without committing; if it does not apply
cleanly the tool stops and says so. Cases and snapshots present on only one
side are listed, not compared (either side may have added tests).

Functional core: parse_hashes, compare_hashes, snapshot_hash_lines,
compare_snapshots, render. Imperative shell: prepare/build/hash/main.
"""
import argparse
import glob
import os
import re
import subprocess
import sys

# The checkout this is run from. Run it from the main checkout, not a worktree.
REPO = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True, check=True).stdout.strip()
TOOLS = os.path.dirname(os.path.abspath(__file__))
A0_COMMIT = "ef81f19e4b"  # (5ee8a07527 before the 2026-10-17 rewrite) "Add byte-identity oracles for the dev backend's 64-bit output (A0)"
SIXTY_FOUR_BIT = re.compile(r"^(x64|arm64)[a-z0-9]*=")


# ---- functional core -------------------------------------------------------

def parse_hashes(text):
    """{case name: {target: hash}} from an eval.blake3 file."""
    cases = {}
    for line in text.splitlines():
        if not line or line.startswith("#"):
            continue
        name, *fields = line.split("\t")
        cases[name] = dict(f.split("=", 1) for f in fields if "=" in f)
    return cases


def compare_hashes(upstream, merged):
    """(differing case names, only-upstream names, only-merged names)."""
    common = upstream.keys() & merged.keys()
    differ = sorted(n for n in common if upstream[n] != merged[n])
    return differ, sorted(upstream.keys() - merged.keys()), sorted(merged.keys() - upstream.keys())


def snapshot_hash_lines(text):
    """The 64-bit target hash lines of one dev_object snapshot, as {target: value}."""
    out = {}
    for line in text.splitlines():
        if SIXTY_FOUR_BIT.match(line):
            key, value = line.split("=", 1)
            out[key] = value
    return out


def compare_snapshots(upstream, merged):
    """upstream/merged: {file name: {target: value}}. Returns (diffs, only-upstream, only-merged),
    diffs as (file, target, upstream value, merged value)."""
    diffs = []
    for name in sorted(upstream.keys() & merged.keys()):
        a, b = upstream[name], merged[name]
        for target in sorted(a.keys() | b.keys()):
            if a.get(target) != b.get(target):
                diffs.append((name, target, a.get(target), b.get(target)))
    return diffs, sorted(upstream.keys() - merged.keys()), sorted(merged.keys() - upstream.keys())


# Since upstream ee048d9adb the compiler identity is a content hash of the
# compiler's sources (it was the git revision, which git-shim pins). The two
# sides have different sources by construction, and the identity reaches every
# proc symbol and, in Debug builds, immediates in the generated code. Each
# worktree's build.zig is rewritten to use one fixed identity module instead.
IDENTITY_ANCHOR = (
    '    const output = run.addOutputFileArg("compiler_identity.zig");\n'
    '    return b.createModule(.{ .root_source_file = output });\n'
)
FIXED_IDENTITY = (
    "//! Fixed compiler identity for the relative oracle.\n\n"
    "pub const compiler_compatibility_hash: [32]u8 = @splat(0x5a);\n"
    'pub const compiler_compatibility_id = "' + "5a" * 32 + '";\n'
)


# Upstream renames that A0's code must follow on an upstream tree containing
# the renaming commit: (file, A0's text, upstream's text, the commit). Each
# old text must occur exactly once, so a stale entry fails loudly.
A0_FOLLOWS = [
    # 0833d310c2 removed parseInspectedProgramImpl; its (null, null) form was
    # parseAndCanonicalizeInspectedProgram, which upstream kept.
    ("src/eval/inspected.zig",
     "parseInspectedProgramImpl(allocator, source_kind, source, imports, null, null)",
     "parseAndCanonicalizeInspectedProgram(allocator, source_kind, source, imports)",
     "0833d310c2"),
    # 2766784b62 removed the Lambda Mono debug materializer and its option.
    ("src/eval/inspected.zig",
     "            .debug_materialized_out = options.debug_materialized_out,\n",
     "",
     "2766784b62"),
]


# Declarations A0's code needs that upstream's file does not have: (file,
# declaration, the line it goes after). Added only when absent.
A0_DECLS = [
    ("src/eval/inspected.zig", "const GuardedList = lir.LirStore.GuardedList;\n",
     "const LirImage = lir.LirImage;\n"),
]


def follow_upstream_renames(path):
    for rel, decl, after in A0_DECLS:
        f = os.path.join(path, rel)
        text = open(f).read()
        if decl in text:
            continue
        if text.count(after) != 1:
            sys.exit(f"A0_DECLS: {after!r} occurs {text.count(after)} times in {rel}; update relative_oracle.py")
        open(f, "w").write(text.replace(after, after + decl))
        run(["git", "add", "--", rel], path)
    for rel, old, new, commit in A0_FOLLOWS:
        if run(["git", "merge-base", "--is-ancestor", commit, "HEAD"], path, check=False).returncode != 0:
            continue
        f = os.path.join(path, rel)
        text = open(f).read()
        if old not in text and new in text:
            continue  # already followed
        if text.count(old) != 1:
            sys.exit(f"A0_FOLLOWS: {old!r} occurs {text.count(old)} times in {rel}; update relative_oracle.py")
        open(f, "w").write(text.replace(old, new))
        run(["git", "add", "--", rel], path)


def pin_identity(build_zig):
    """build.zig text with compilerIdentityModule returning FIXED_IDENTITY.
    Raises ValueError unless the anchor occurs exactly once."""
    if build_zig.count(IDENTITY_ANCHOR) != 1:
        raise ValueError("compilerIdentityModule's return does not match the oracle's anchor")
    fixed = FIXED_IDENTITY.replace("\\", "\\\\").replace("\n", "\\n").replace('"', '\\"')
    return build_zig.replace(IDENTITY_ANCHOR, (
        '    _ = run.addOutputFileArg("compiler_identity.zig");\n'
        '    const pinned = b.addWriteFiles().add("compiler_identity.zig", "' + fixed + '");\n'
        '    return b.createModule(.{ .root_source_file = pinned });\n'))


def render(hash_result, snap_result):
    differ, only_u, only_m = hash_result
    sdiffs, sonly_u, sonly_m = snap_result
    ok = not differ and not sdiffs
    lines = ["relative 64-bit oracle: " + ("PASS" if ok else "FAIL"),
             f"  eval cases: {len(differ)} differ; {len(only_u)} only upstream; {len(only_m)} only merged"]
    lines += [f"    differs: {n}" for n in differ[:40]]
    lines += [f"  dev_object snapshots: {len(sdiffs)} 64-bit lines differ; "
              f"{len(sonly_u)} files only upstream; {len(sonly_m)} only merged"]
    lines += [f"    {f}: {t} upstream={u} merged={m}" for f, t, u, m in sdiffs[:40]]
    return "\n".join(lines), ok


def self_test():
    h = "# c\nA\tx64musl=1\tarm64musl=2\nB\tx64musl=3\tarm64musl=4\n"
    h2 = "A\tx64musl=1\tarm64musl=2\nB\tx64musl=3\tarm64musl=5\nC\tx64musl=9\tarm64musl=9\n"
    assert compare_hashes(parse_hashes(h), parse_hashes(h2)) == (["B"], [], ["C"])
    s = "x64musl=aa\narm32musl=zz\narm64mac=bb\nnot a hash line\n"
    assert snapshot_hash_lines(s) == {"x64musl": "aa", "arm64mac": "bb"}
    d = compare_snapshots({"f.md": {"x64musl": "aa"}}, {"f.md": {"x64musl": "ab"}, "g.md": {}})
    assert d == ([("f.md", "x64musl", "aa", "ab")], [], ["g.md"])
    text, ok = render(([], [], []), ([], [], []))
    assert ok and text.startswith("relative 64-bit oracle: PASS")
    b = "fn f() void {\n" + IDENTITY_ANCHOR + "}\n"
    pinned = pin_identity(b)
    assert IDENTITY_ANCHOR not in pinned and "root_source_file = pinned" in pinned
    try:
        pin_identity("no anchor")
        raise AssertionError("pin_identity accepted a build.zig without the anchor")
    except ValueError:
        pass
    print("self-test passed")


# ---- imperative shell ------------------------------------------------------

def run(argv, cwd, env=None, check=True):
    p = subprocess.run(argv, cwd=cwd, capture_output=True, text=True, env=env)
    if check and p.returncode != 0:
        sys.exit(f"failed: {' '.join(argv)} (in {cwd})\n{p.stdout[-2000:]}{p.stderr[-2000:]}")
    return p


def prepare(work, name, rev, with_a0):
    path = os.path.join(work, name)
    if not os.path.exists(path):
        run(["git", "worktree", "add", "--detach", path, rev], REPO)
    else:
        run(["git", "cherry-pick", "--abort"], path, check=False)
        run(["git", "reset", "--quiet", "--hard"], path)
        run(["git", "checkout", "--quiet", "--detach", rev], path)
    if with_a0:
        # A0's code and snapshots, not its edits to the plan documents under
        # projects/ (which upstream does not have).
        diff = run(["git", "diff", f"{A0_COMMIT}^", A0_COMMIT, "--", ".", ":!projects"], REPO).stdout
        p = subprocess.run(["git", "apply", "--3way", "--index"], cwd=path, input=diff,
                           capture_output=True, text=True)
        if p.returncode != 0:
            conflicts = run(["git", "diff", "--name-only", "--diff-filter=U"], path, check=False).stdout
            # rerere may already have resolved them (the same hunk conflicted
            # in the merge). Accept that only when no conflict marker is left.
            files = conflicts.split()
            unresolved = [f for f in files if "<<<<<<< " in open(os.path.join(path, f)).read()]
            if not files or unresolved:
                sys.exit("A0's oracle changes do not apply cleanly to upstream; resolve in "
                         f"{path} and rerun. Conflicting files:\n{conflicts}{p.stderr[-1500:]}")
            run(["git", "add", "--"] + files, path)
            print(f"A0 applied with conflicts that rerere resolved: {', '.join(files)}")
        follow_upstream_renames(path)
    build_zig = os.path.join(path, "build.zig")
    try:
        pinned = pin_identity(open(build_zig).read())
    except ValueError as e:
        sys.exit(f"{name}: {e}; update IDENTITY_ANCHOR in relative_oracle.py")
    open(build_zig, "w").write(pinned)
    return path


def hash_side(path, env):
    # Build both sides as the same compiler version. The build reads `git
    # rev-parse --short=8 HEAD` into the checked-artifact hash, which reaches
    # every proc identity, and since upstream 842120f79f the Debug checks put
    # that identity into the generated code as immediates. Two different
    # commits would then never produce the same bytes. The shim answers that
    # one git query with a fixed string.
    build_env = dict(env if env is not None else os.environ)
    build_env["PATH"] = os.path.join(TOOLS, "git-shim") + os.pathsep + build_env.get("PATH", "")
    run(["zig", "build", "build-test-eval-runner", "build-snapshot-tool"], path, build_env)
    out = os.path.join(path, "relative-oracle-hashes.blake3")
    # The work tree is reused and the file is untracked, so remove the last
    # run's copy. A runner without the hash mode takes the flag as a test
    # filter and writes nothing; without this the old file would be compared.
    if os.path.exists(out):
        os.remove(out)
    run([os.path.join(path, "zig-out/bin/eval-test-runner"), "--write-dev-code-hashes", out], path, env)
    if not os.path.exists(out):
        sys.exit(f"{path}: the eval runner wrote no hashes. It has no hash mode; "
                 "for a branch without A0 pass --apply-a0-to-merged.")
    snaps = sorted(glob.glob(os.path.join(path, "test/snapshots/dev_object_*.md")))
    run([os.path.join(path, "zig-out/bin/snapshot"), "--update-expected", *snaps], path, env, check=False)
    return (parse_hashes(open(out).read()),
            {os.path.basename(p): snapshot_hash_lines(open(p).read()) for p in snaps})


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--upstream")
    ap.add_argument("--merged")
    ap.add_argument("--work", default=os.path.join(REPO, ".workspaces/relative-oracle"))
    ap.add_argument("--apply-a0-to-merged", action="store_true",
                    help="apply A0's hash mode to --merged too (for a PR branch cut onto upstream)")
    ap.add_argument("--self-test", action="store_true")
    args = ap.parse_args()
    if args.self_test:
        return self_test()
    if not (args.upstream and args.merged):
        ap.error("--upstream and --merged are required")
    os.makedirs(args.work, exist_ok=True)
    env = dict(os.environ, TMPDIR=os.path.join(args.work, "tmp"))
    os.makedirs(env["TMPDIR"], exist_ok=True)
    upstream = hash_side(prepare(args.work, "upstream", args.upstream, True), env)
    merged = hash_side(prepare(args.work, "merged", args.merged, args.apply_a0_to_merged), env)
    text, ok = render(compare_hashes(upstream[0], merged[0]), compare_snapshots(upstream[1], merged[1]))
    print(text)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
