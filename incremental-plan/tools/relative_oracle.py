#!/usr/bin/env python3
"""Relative 64-bit oracle (part 5 of the arm32 verification plan).

After merging upstream `main` into the arm32 branch,
the committed 64-bit golden hashes describe the old base,
so the check becomes relative:
the merged tip must produce exactly the x86_64 and aarch64 output
that the merged upstream commit produces.

    python3 relative_oracle.py --upstream <upstream-commit> --merged <merge-commit> --work <dir>
    python3 relative_oracle.py --upstream <base> --merged <pr-head> --apply-a0-to-merged
    python3 relative_oracle.py --self-test

Needs Python 3.12 or newer (it uses the `type` statement).

For each side it makes a detached worktree,
builds the eval runner,
writes the per-case dev-code hashes (`--write-dev-code-hashes`)
and regenerates the `dev_object` snapshots.
The two sides build at the same time,
then hash one at a time, once no build is running (see BuildGate),
and each phase's time is printed.
Each side's result is saved under a key of every input that reaches it
(see side_key),
so a rerun on the same base reuses the upstream side;
--fresh builds both anyway.

Upstream has no hash mode,
so A0's oracle commit is applied to the upstream worktree without committing;
if it does not apply cleanly the tool stops and says so.
The patches in a0-patches/ are applied after it, in name order:
fixes to A0's own code that only the oracle uses.
Cases and snapshots present on only one side are listed, not compared
(either side may have added tests).

Functional core: parse_hashes, compare_hashes, snapshot_hash_lines,
compare_snapshots, render, cache_key.
Imperative shell: prepare, side_key, plan_side, hash_side, build_side, main.
"""
import argparse
import concurrent.futures
import dataclasses
import datetime
import glob
import hashlib
import json
import os
import re
import signal
import subprocess
import sys
import tempfile
import threading
import time
from collections.abc import Callable, Iterable, Mapping

# {case or snapshot file name: {target: hash}}
type Hashes = dict[str, dict[str, str]]


@dataclasses.dataclass(frozen=True)
class SideResult:
    """What one side produced."""
    hashes: Hashes  # eval cases
    snapshots: Hashes  # dev_object snapshots' 64-bit hash lines


@dataclasses.dataclass(frozen=True)
class SideOutcome:
    result: SideResult
    how: str  # "built (key ...)" or "reused from <date> (key ...)"


@dataclasses.dataclass(frozen=True)
class HashComparison:
    differ: tuple[str, ...]
    only_upstream: tuple[str, ...]
    only_merged: tuple[str, ...]


@dataclasses.dataclass(frozen=True)
class SnapshotDiff:
    file: str
    target: str
    upstream: str | None
    merged: str | None


@dataclasses.dataclass(frozen=True)
class SnapshotComparison:
    diffs: tuple[SnapshotDiff, ...]
    only_upstream: tuple[str, ...]
    only_merged: tuple[str, ...]


@dataclasses.dataclass(frozen=True)
class Follow:
    """An upstream rename A0's code must follow."""
    file: str
    old: str  # A0's text
    new: str  # upstream's text
    commit: str  # the upstream commit that renamed it


@dataclasses.dataclass(frozen=True)
class Decl:
    """A declaration A0's code needs that upstream's file does not have."""
    file: str
    decl: str
    after: str  # the line it goes after


# The checkout this is run from.
# Run it from the main checkout, not a worktree.
REPO: str = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True, check=True).stdout.strip()
TOOLS: str = os.path.dirname(os.path.abspath(__file__))
# "Add byte-identity oracles for the dev backend's 64-bit output (A0)"
# (5ee8a07527 before the 2026-10-17 rewrite).
A0_COMMIT: str = "ef81f19e4b"
# Fixes to A0's own code, applied after A0 and A0_FOLLOWS, in name order.
A0_PATCHES: list[str] = sorted(glob.glob(os.path.join(TOOLS, "a0-patches", "*.patch")))
SIXTY_FOUR_BIT: re.Pattern[str] = re.compile(r"^(x64|arm64)[a-z0-9]*=")


# ---- functional core -------------------------------------------------------

def parse_hashes(text: str) -> Hashes:
    """{case name: {target: hash}} from an eval.blake3 file."""
    cases: Hashes = {}
    for line in text.splitlines():
        if not line or line.startswith("#"):
            continue
        name, *fields = line.split("\t")
        cases[name] = dict(f.split("=", 1) for f in fields if "=" in f)
    return cases


def compare_hashes(upstream: Hashes, merged: Hashes) -> HashComparison:
    common = upstream.keys() & merged.keys()
    return HashComparison(
        differ=tuple(sorted(n for n in common if upstream[n] != merged[n])),
        only_upstream=tuple(sorted(upstream.keys() - merged.keys())),
        only_merged=tuple(sorted(merged.keys() - upstream.keys())))


def snapshot_hash_lines(text: str) -> dict[str, str]:
    """The 64-bit target hash lines of one dev_object snapshot, as {target: value}."""
    out: dict[str, str] = {}
    for line in text.splitlines():
        if SIXTY_FOUR_BIT.match(line):
            key, value = line.split("=", 1)
            out[key] = value
    return out


def compare_snapshots(upstream: Hashes, merged: Hashes) -> SnapshotComparison:
    """upstream/merged: {file name: {target: value}}."""
    diffs: list[SnapshotDiff] = []
    for name in sorted(upstream.keys() & merged.keys()):
        a, b = upstream[name], merged[name]
        for target in sorted(a.keys() | b.keys()):
            if a.get(target) != b.get(target):
                diffs.append(SnapshotDiff(name, target, a.get(target), b.get(target)))
    return SnapshotComparison(
        diffs=tuple(diffs),
        only_upstream=tuple(sorted(upstream.keys() - merged.keys())),
        only_merged=tuple(sorted(merged.keys() - upstream.keys())))


# Since upstream ee048d9adb the compiler identity is a content hash of the compiler's sources
# (it was the git revision, which git-shim pins).
# The two sides have different sources by construction,
# and the identity reaches every proc symbol
# and, in Debug builds, immediates in the generated code.
# Each worktree's build.zig is rewritten to use one fixed identity module instead.
IDENTITY_ANCHOR: str = (
    '    const output = run.addOutputFileArg("compiler_identity.zig");\n'
    '    return b.createModule(.{ .root_source_file = output });\n'
)
FIXED_IDENTITY: str = (
    "//! Fixed compiler identity for the relative oracle.\n\n"
    "pub const compiler_compatibility_hash: [32]u8 = @splat(0x5a);\n"
    'pub const compiler_compatibility_id = "' + "5a" * 32 + '";\n'
)


# Upstream renames that A0's code must follow
# on an upstream tree containing the renaming commit.
# Each old text must occur exactly once,
# so a stale entry fails loudly.
A0_FOLLOWS: tuple[Follow, ...] = (
    # 0833d310c2 removed parseInspectedProgramImpl;
    # its (null, null) form was parseAndCanonicalizeInspectedProgram,
    # which upstream kept.
    Follow("src/eval/inspected.zig",
           "parseInspectedProgramImpl(allocator, source_kind, source, imports, null, null)",
           "parseAndCanonicalizeInspectedProgram(allocator, source_kind, source, imports)",
           "0833d310c2"),
    # 2766784b62 removed the Lambda Mono debug materializer and its option.
    Follow("src/eval/inspected.zig",
           "            .debug_materialized_out = options.debug_materialized_out,\n",
           "",
           "2766784b62"),
    # 3b7831cbd9 made inspected lowering choose the specialization strategy
    # (Boxy lowers through CompileTimeFinalization);
    # A0's hash-mode helper must lower the same way.
    # Applies after the entry above.
    Follow("src/eval/inspected.zig",
           "    return lir.CheckedPipeline.lowerCheckedModulesToLir(\n"
           "        allocator,\n"
           "        .{\n"
           "            .root = check.CheckedArtifact.loweringView(root_module),\n"
           "            .imports = import_views,\n"
           "        },\n"
           "        .{ .requests = root_module.root_requests.runtime_requests },\n"
           "        .{\n"
           "            .target_usize = target_usize,\n"
           "            .specialization_strategy = options.specialization_strategy,\n"
           "            .inline_mode = options.inline_mode,\n"
           "            .list_in_place_map = options.list_in_place_map,\n"
           "            .inline_expects = options.inline_expects,\n"
           "            .tag_reachability = options.tag_reachability,\n"
           "            .prove_ranges = options.prove_ranges,\n"
           "        },\n"
           "    );\n",
           "    const modules: lir.CheckedPipeline.CheckedModuleSet = .{\n"
           "        .root = check.CheckedArtifact.loweringView(root_module),\n"
           "        .imports = import_views,\n"
           "    };\n"
           "    const roots: lir.CheckedPipeline.RootRequestSet = .{ .requests = root_module.root_requests.runtime_requests };\n"
           "    const target = lowerToLirTarget(target_usize, options);\n"
           "    return switch (target.specialization_strategy) {\n"
           "        .lss => try lir.CheckedPipeline.lowerCheckedModulesToLir(allocator, modules, roots, target),\n"
           "        .boxy => try CompileTimeFinalization.lowerBoxyRuntime(allocator, modules, roots, target),\n"
           "    };\n",
           "3b7831cbd9"),
)


# Added only when absent.
A0_DECLS: tuple[Decl, ...] = (
    Decl("src/eval/inspected.zig", "const GuardedList = lir.LirStore.GuardedList;\n",
         "const LirImage = lir.LirImage;\n"),
)


def follow_upstream_renames(path: str) -> None:
    for d in A0_DECLS:
        f = os.path.join(path, d.file)
        text = open(f).read()
        if d.decl in text:
            continue
        if text.count(d.after) != 1:
            sys.exit(f"A0_DECLS: {d.after!r} occurs {text.count(d.after)} times in {d.file}; "
                     "update relative_oracle.py")
        open(f, "w").write(text.replace(d.after, d.after + d.decl))
        run(["git", "add", "--", d.file], path)
    for r in A0_FOLLOWS:
        if run(["git", "merge-base", "--is-ancestor", r.commit, "HEAD"], path, check=False).returncode != 0:
            continue
        f = os.path.join(path, r.file)
        text = open(f).read()
        if r.old not in text and r.new in text:
            continue  # already followed
        if text.count(r.old) != 1:
            sys.exit(f"A0_FOLLOWS: {r.old!r} occurs {text.count(r.old)} times in {r.file}; "
                     "update relative_oracle.py")
        open(f, "w").write(text.replace(r.old, r.new))
        run(["git", "add", "--", r.file], path)


def pin_identity(build_zig: str) -> str:
    """build.zig text with compilerIdentityModule returning FIXED_IDENTITY.
    Raises ValueError unless the anchor occurs exactly once."""
    if build_zig.count(IDENTITY_ANCHOR) != 1:
        raise ValueError("compilerIdentityModule's return does not match the oracle's anchor")
    fixed = FIXED_IDENTITY.replace("\\", "\\\\").replace("\n", "\\n").replace('"', '\\"')
    return build_zig.replace(IDENTITY_ANCHOR, (
        '    _ = run.addOutputFileArg("compiler_identity.zig");\n'
        '    const pinned = b.addWriteFiles().add("compiler_identity.zig", "' + fixed + '");\n'
        '    return b.createModule(.{ .root_source_file = pinned });\n'))


def cache_key(parts: Iterable[tuple[str, str]]) -> str:
    """A hex digest of (name, value) pairs.
    Order-independent; every value is a string."""
    h = hashlib.sha256()
    for name, value in sorted(parts):
        h.update(f"{name}\0{value}\0".encode())
    return h.hexdigest()


def render(hash_result: HashComparison, snap_result: SnapshotComparison,
           sources: Mapping[str, str]) -> tuple[str, bool]:
    """sources: {side: how its result was obtained (SideOutcome.how)}."""
    h, sn = hash_result, snap_result
    ok = not h.differ and not sn.diffs
    lines = ["relative 64-bit oracle: " + ("PASS" if ok else "FAIL")]
    lines += [f"  {side}: {how}" for side, how in sorted(sources.items())]
    lines += [f"  eval cases: {len(h.differ)} differ; {len(h.only_upstream)} only upstream; "
              f"{len(h.only_merged)} only merged"]
    lines += [f"    differs: {n}" for n in h.differ[:40]]
    lines += [f"  dev_object snapshots: {len(sn.diffs)} 64-bit lines differ; "
              f"{len(sn.only_upstream)} files only upstream; {len(sn.only_merged)} only merged"]
    lines += [f"    {d.file}: {d.target} upstream={d.upstream} merged={d.merged}" for d in sn.diffs[:40]]
    return "\n".join(lines), ok


def self_test() -> None:
    h = "# c\nA\tx64musl=1\tarm64musl=2\nB\tx64musl=3\tarm64musl=4\n"
    h2 = "A\tx64musl=1\tarm64musl=2\nB\tx64musl=3\tarm64musl=5\nC\tx64musl=9\tarm64musl=9\n"
    assert compare_hashes(parse_hashes(h), parse_hashes(h2)) == HashComparison(("B",), (), ("C",))
    s = "x64musl=aa\narm32musl=zz\narm64mac=bb\nnot a hash line\n"
    assert snapshot_hash_lines(s) == {"x64musl": "aa", "arm64mac": "bb"}
    d = compare_snapshots({"f.md": {"x64musl": "aa"}}, {"f.md": {"x64musl": "ab"}, "g.md": {}})
    assert d == SnapshotComparison((SnapshotDiff("f.md", "x64musl", "aa", "ab"),), (), ("g.md",))
    text, ok = render(HashComparison((), (), ()), SnapshotComparison((), (), ()), {"upstream": "built"})
    assert ok and text.startswith("relative 64-bit oracle: PASS") and "  upstream: built" in text
    k = cache_key([("tree", "a"), ("zig", "1")])
    assert k == cache_key([("zig", "1"), ("tree", "a")])
    assert k != cache_key([("tree", "b"), ("zig", "1")])
    assert k != cache_key([("tree", "a"), ("zig", "1"), ("env ROC_LIR_DUMP", "1")])
    b = "fn f() void {\n" + IDENTITY_ANCHOR + "}\n"
    pinned = pin_identity(b)
    assert IDENTITY_ANCHOR not in pinned and "root_source_file = pinned" in pinned
    try:
        pin_identity("no anchor")
        raise AssertionError("pin_identity accepted a build.zig without the anchor")
    except ValueError:
        pass
    assert A0_PATCHES, "a0-patches/ has no patches"
    for patch in A0_PATCHES:
        # Whether it applies is checked by prepare on every run, on the tree it applies to;
        # here only that git can read it.
        run(["git", "apply", "--stat", patch], TOOLS)
    self_test_side_key_and_cache()
    print("self-test passed")


def self_test_side_key_and_cache() -> None:
    """side_key, plan_side, build_side and BuildGate, on a throwaway git repository."""
    with tempfile.TemporaryDirectory() as work:
        path = os.path.join(work, "side")
        os.makedirs(os.path.join(work, "tmp"))
        os.makedirs(path)
        git = ["git", "-c", "user.name=t", "-c", "user.email=t", "-c", "commit.gpgsign=false"]
        run(git + ["init", "--quiet"], path)
        open(os.path.join(path, "a.zig"), "w").write("a\n")
        run(git + ["add", "a.zig"], path)
        run(git + ["commit", "--quiet", "-m", "a"], path)
        index = os.path.join(path, ".git", "index")
        index_before = open(index, "rb").read()
        env: dict[str, str] = {}

        k = side_key(path, env, work)
        assert k == side_key(path, env, work), "the key is stable"
        assert k != side_key(path, {"ROC_LIR_DUMP": "1"}, work), "a ROC_* variable changes it"
        assert k == side_key(path, {"HOME": "/elsewhere"}, work), "other variables do not"
        open(os.path.join(path, "a.zig"), "w").write("b\n")
        k_edited = side_key(path, env, work)
        assert k_edited != k, "an unstaged edit changes it"
        open(os.path.join(path, "new.zig"), "w").write("c\n")
        assert side_key(path, env, work) != k_edited, "an untracked file changes it"
        assert open(index, "rb").read() == index_before, "the work tree's index is untouched"

        calls: list[str] = []
        result = SideResult(hashes={"case": {"x64musl": "1"}}, snapshots={"f.md": {"x64musl": "2"}})

        def compute(p: str, e: Mapping[str, str], g: BuildGate) -> SideResult:
            calls.append(p)
            g.build_done()
            return result

        def failing(p: str, e: Mapping[str, str], g: BuildGate) -> SideResult:
            g.build_done()
            sys.exit("failed")

        def side(fresh: bool, c: Callable[[str, Mapping[str, str], BuildGate], SideResult]) -> SideOutcome:
            plan = plan_side(path, env, work, fresh)
            return plan.reused or build_side(plan, env, work, BuildGate(1), c)

        first = side(False, compute)
        assert first.how.startswith("built") and first.result == result and len(calls) == 1
        again = side(False, compute)
        assert again.how.startswith("reused from") and again.result == result and len(calls) == 1
        fresh = side(True, compute)
        assert fresh.how.startswith("built") and len(calls) == 2, "--fresh builds anyway"
        saved = os.listdir(os.path.join(work, "cache"))
        entry = os.path.join(work, "cache", saved[0])
        os.utime(entry, (1000, 1000))
        side(False, compute)
        assert os.stat(entry).st_mtime > 1000, "reusing a result marks it used"
        open(os.path.join(path, "a.zig"), "w").write("d\n")
        try:
            side(False, failing)
            raise AssertionError("a failing side returned")
        except SystemExit:
            pass
        assert os.listdir(os.path.join(work, "cache")) == saved, "a failed side saves nothing"

        gate = BuildGate(2)
        assert not gate.wait_for_builds(0.01), "hashing waits while a build runs"
        gate.build_done()
        assert not gate.wait_for_builds(0.01), "and while the other build runs"
        gate.build_done()
        assert gate.wait_for_builds(0.01), "and goes once no build runs"
        assert BuildGate(0).wait_for_builds(0.01), "with no build at all, it does not wait"

        pruned = os.path.join(work, "pruned")
        os.makedirs(pruned)
        for i in range(5):
            name = os.path.join(pruned, f"{i}.json")
            open(name, "w").write("{}")
            os.utime(name, (1000 + i, 1000 + i))
        open(os.path.join(pruned, "x.json.tmp"), "w").write("")
        assert prune_cache(pruned, 3) == ["0.json", "1.json"], "the least recently used go first"
        assert sorted(os.listdir(pruned)) == ["2.json", "3.json", "4.json", "x.json.tmp"]
        assert prune_cache(pruned, 3) == [], "nothing beyond the limit"


# ---- imperative shell ------------------------------------------------------

# When one side fails, the other is stopped:
# STOP keeps run from starting anything new,
# and stop_all ends what is running.
# Each command runs in its own process group,
# so stopping `zig build` also stops the compilers it started.
STOP: threading.Event = threading.Event()
RUNNING: set[subprocess.Popen[str]] = set()
RUNNING_LOCK: threading.Lock = threading.Lock()


def stop_all() -> None:
    with RUNNING_LOCK:
        STOP.set()
        for p in RUNNING:
            try:
                os.killpg(p.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass  # it ended on its own


def stop_on_sigterm() -> None:
    """Make `kill <pid>` stop every running command too.
    The commands run in their own process groups, so the signal does not reach them."""
    def handler(signum: int, frame: object) -> None:
        stop_all()
        sys.exit(128 + signum)
    signal.signal(signal.SIGTERM, handler)


def run(argv: list[str], cwd: str, env: Mapping[str, str] | None = None,
        check: bool = True, input: str | None = None) -> subprocess.CompletedProcess[str]:
    with RUNNING_LOCK:
        if STOP.is_set():
            sys.exit("stopped: the other side failed")
        p = subprocess.Popen(argv, cwd=cwd, env=env, text=True, start_new_session=True,
                             stdin=subprocess.PIPE if input is not None else None,
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        RUNNING.add(p)
    try:
        out, err = p.communicate(input)
    finally:
        with RUNNING_LOCK:
            RUNNING.discard(p)
    if STOP.is_set():
        sys.exit("stopped: the other side failed")
    if check and p.returncode != 0:
        sys.exit(f"failed: {' '.join(argv)} (in {cwd})\n{out[-2000:]}{err[-2000:]}")
    return subprocess.CompletedProcess(argv, p.returncode, out, err)


def prepare(work: str, name: str, rev: str, with_a0: bool) -> str:
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
        p = run(["git", "apply", "--3way", "--index"], path, check=False, input=diff)
        if p.returncode != 0:
            conflicts = run(["git", "diff", "--name-only", "--diff-filter=U"], path, check=False).stdout
            # rerere may already have resolved them
            # (the same hunk conflicted in the merge).
            # Accept that only when no conflict marker is left.
            files = conflicts.split()
            unresolved = [f for f in files if "<<<<<<< " in open(os.path.join(path, f)).read()]
            if not files or unresolved:
                sys.exit("A0's oracle changes do not apply cleanly to upstream; resolve in "
                         f"{path} and rerun. Conflicting files:\n{conflicts}{p.stderr[-1500:]}")
            run(["git", "add", "--"] + files, path)
            print(f"A0 applied with conflicts that rerere resolved: {', '.join(files)}")
        follow_upstream_renames(path)
        for patch in A0_PATCHES:
            p = run(["git", "apply", "--index", patch], path, check=False)
            if p.returncode != 0:
                sys.exit(f"{os.path.basename(patch)} does not apply on top of A0 in {path}; "
                         f"update it in relative_oracle.py's a0-patches/.\n{p.stderr[-1500:]}")
    build_zig = os.path.join(path, "build.zig")
    try:
        pinned = pin_identity(open(build_zig).read())
    except ValueError as e:
        sys.exit(f"{name}: {e}; update IDENTITY_ANCHOR in relative_oracle.py")
    open(build_zig, "w").write(pinned)
    # The work tree is reused and the file is untracked,
    # so remove the last run's copy.
    # A runner without the hash mode takes the flag as a test filter and writes nothing;
    # without this the old file would be compared.
    out = os.path.join(path, "relative-oracle-hashes.blake3")
    if os.path.exists(out):
        os.remove(out)
    return path


def side_key(path: str, env: Mapping[str, str], work: str) -> str:
    """The cache key of one prepared side:
    every input that reaches its result.

    - the source tree exactly as it will be built
      (after A0, rerere's resolutions, A0_FOLLOWS and the pinned identity),
      untracked files included,
      from a throwaway index so the work tree's index is untouched;
    - this script (how the runner and snapshot tool are called);
    - the git shim and the Zig version;
    - every ROC_* environment variable.
      Debug builds read the developer diagnostics (base.dev_diagnostics),
      all named ROC_*;
      taking every ROC_* variable is a superset of them.
    """
    # The throwaway index starts from the commit, not a copy of the work tree's index:
    # its entries carry no file times, so `git add -A` compares every file by content.
    # A copied index would have a new modification time,
    # which turns off git's check for files changed in the same second as the index,
    # and a same-size edit right after checkout could keep the old content.
    tmp_index = os.path.join(work, "tmp", f"index-{os.path.basename(path)}")
    if os.path.exists(tmp_index):
        os.remove(tmp_index)
    git_env = dict(os.environ, GIT_INDEX_FILE=tmp_index)
    run(["git", "read-tree", "HEAD"], path, git_env)
    run(["git", "add", "-A"], path, git_env)
    tree = run(["git", "write-tree"], path, git_env).stdout.strip()
    os.remove(tmp_index)
    shim = os.path.join(TOOLS, "git-shim", "git")
    parts = [
        ("tree", tree),
        ("script", hashlib.sha256(open(os.path.abspath(__file__), "rb").read()).hexdigest()),
        ("git-shim", hashlib.sha256(open(shim, "rb").read()).hexdigest()),
        ("zig", run(["zig", "version"], path).stdout.strip()),
    ]
    parts += [(f"env {k}", v) for k, v in env.items() if k.startswith("ROC_")]
    return cache_key(parts)


# The two sides build at the same time
# (each build is one Zig process using about one core),
# but run the eval hashes and snapshots one at a time:
# those use every core and most of the memory limit.
# Memory, measured on 8e9e512e0f with a0-patches/0001:
# a side's hashing peaks at 13.8 GB, the eval runner's build at about 7 GB,
# against the usual 20 GB limit.
# So no side hashes while any build is still running (BuildGate),
# and only one side hashes at a time (RUN_ONE_AT_A_TIME).
RUN_ONE_AT_A_TIME: threading.Lock = threading.Lock()


class BuildGate:
    """Counts the builds still running; hashing waits until there are none.

    Every building side calls build_done exactly once, also when its build fails,
    so the other side never waits for a build that will not finish
    (it then stops at its next command, see STOP)."""

    def __init__(self, builds: int) -> None:
        self._pending = builds
        self._cond = threading.Condition()

    def build_done(self) -> None:
        with self._cond:
            self._pending -= 1
            self._cond.notify_all()

    def wait_for_builds(self, timeout: float | None = None) -> bool:
        """True once no build is running; False if `timeout` seconds passed first."""
        with self._cond:
            return self._cond.wait_for(lambda: self._pending == 0, timeout)


# Each failed side and its error, in the order they failed.
FAILURES: list[tuple[str, BaseException]] = []
FAILURES_LOCK: threading.Lock = threading.Lock()


# How many saved results to keep:
# the most recently used (saved or reused);
# the rest are removed after each save.
CACHE_KEEP: int = 30
# Both sides save and prune the same folder.
CACHE_LOCK: threading.Lock = threading.Lock()


def prune_cache(cache_dir: str, keep: int) -> list[str]:
    """Remove all but the `keep` most recently used saved results
    (a file's modification time is when it was last saved or reused).
    Returns the removed file names, least recently used first."""
    entries = sorted((e for e in os.scandir(cache_dir) if e.name.endswith(".json")),
                     key=lambda e: e.stat().st_mtime)
    removed = entries[:max(0, len(entries) - keep)]
    for e in removed:
        os.remove(e.path)
    return [e.name for e in removed]


def log(side: str, phase: str, start: float) -> None:
    print(f"[{side}] {phase}: {(time.monotonic() - start) / 60:.1f} min", flush=True)


def hash_side(path: str, env: Mapping[str, str], gate: BuildGate) -> SideResult:
    # Build both sides as the same compiler version.
    # The build reads `git rev-parse --short=8 HEAD` into the checked-artifact hash,
    # which reaches every proc identity,
    # and since upstream 842120f79f the Debug checks put that identity
    # into the generated code as immediates.
    # Two different commits would then never produce the same bytes.
    # The shim answers that one git query with a fixed string.
    build_env = dict(env)
    build_env["PATH"] = os.path.join(TOOLS, "git-shim") + os.pathsep + build_env.get("PATH", "")
    side = os.path.basename(path)
    t = time.monotonic()
    try:
        run(["zig", "build", "build-test-eval-runner", "build-snapshot-tool"], path, build_env)
    finally:
        gate.build_done()
    log(side, "build", t)
    out = os.path.join(path, "relative-oracle-hashes.blake3")
    snaps = sorted(glob.glob(os.path.join(path, "test/snapshots/dev_object_*.md")))
    t = time.monotonic()
    gate.wait_for_builds()
    log(side, "waited for the other build", t)
    t = time.monotonic()
    with RUN_ONE_AT_A_TIME:
        log(side, "waited for the other side's hashing", t)
        t = time.monotonic()
        run([os.path.join(path, "zig-out/bin/eval-test-runner"), "--write-dev-code-hashes", out], path, env)
        log(side, "eval hashes", t)
        if not os.path.exists(out):
            sys.exit(f"{path}: the eval runner wrote no hashes. It has no hash mode; "
                     "for a branch without A0 pass --apply-a0-to-merged.")
        t = time.monotonic()
        # The snapshot tool exits 1 only when a snapshot fails to process,
        # and a failed file keeps its committed hash lines,
        # so a failure must stop the run rather than compare stale values.
        run([os.path.join(path, "zig-out/bin/snapshot"), "--update-expected", *snaps], path, env)
        log(side, "snapshots", t)
    return SideResult(
        hashes=parse_hashes(open(out).read()),
        snapshots={os.path.basename(p): snapshot_hash_lines(open(p).read()) for p in snaps})


@dataclasses.dataclass(frozen=True)
class SidePlan:
    """Whether one side reuses a saved result or builds, decided before either side starts."""
    path: str
    key: str
    reused: SideOutcome | None  # None: this side builds


def plan_side(path: str, env: Mapping[str, str], work: str, fresh: bool) -> SidePlan:
    """Runs before the sides start, so nothing prunes the saved result
    between finding it and marking it used."""
    side = os.path.basename(path)
    key = side_key(path, env, work)
    entry = os.path.join(work, "cache", key + ".json")
    if fresh or not os.path.exists(entry):
        return SidePlan(path, key, None)
    saved = json.load(open(entry))
    os.utime(entry)  # mark it used, so pruning keeps it
    print(f"[{side}] reused the result saved {saved['created']} (key {key[:12]})", flush=True)
    return SidePlan(path, key, SideOutcome(SideResult(hashes=saved["hashes"], snapshots=saved["snapshots"]),
                                           f"reused from {saved['created']} (key {key[:12]})"))


def build_side(plan: SidePlan, env: Mapping[str, str], work: str, gate: BuildGate,
               compute: Callable[[str, Mapping[str, str], BuildGate], SideResult] = hash_side) -> SideOutcome:
    """Builds and hashes one side and saves its result.
    A result is saved only after its side finished,
    written to a temporary file and renamed,
    so a killed run leaves no partial entry."""
    side = os.path.basename(plan.path)
    entry = os.path.join(work, "cache", plan.key + ".json")
    t = time.monotonic()
    result = compute(plan.path, env, gate)
    log(side, "total", t)
    cache_dir = os.path.dirname(entry)
    os.makedirs(cache_dir, exist_ok=True)
    created = datetime.datetime.now().astimezone().isoformat(timespec="seconds")
    with open(entry + ".tmp", "w") as f:
        json.dump({"created": created, "hashes": result.hashes, "snapshots": result.snapshots}, f)
    with CACHE_LOCK:
        os.replace(entry + ".tmp", entry)
        removed = prune_cache(cache_dir, CACHE_KEEP)
    if removed:
        print(f"[{side}] removed {len(removed)} saved result(s) beyond the {CACHE_KEEP} most recently used",
              flush=True)
    return SideOutcome(result, f"built (key {plan.key[:12]})")


def run_side(side: str, plan: SidePlan, env: Mapping[str, str], work: str, gate: BuildGate) -> SideOutcome:
    """build_side, recording a failure in FAILURES."""
    try:
        return build_side(plan, env, work, gate)
    except BaseException as e:
        with FAILURES_LOCK:
            FAILURES.append((side, e))
        raise


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--upstream")
    ap.add_argument("--merged")
    ap.add_argument("--work", default=os.path.join(REPO, ".workspaces/relative-oracle"))
    ap.add_argument("--apply-a0-to-merged", action="store_true",
                    help="apply A0's hash mode to --merged too (for a PR branch cut onto upstream)")
    ap.add_argument("--fresh", action="store_true",
                    help="build both sides even when a saved result matches (use for the run before review)")
    ap.add_argument("--self-test", action="store_true")
    args = ap.parse_args()
    if args.self_test:
        return self_test()
    if not (args.upstream and args.merged):
        ap.error("--upstream and --merged are required")
    stop_on_sigterm()
    os.makedirs(args.work, exist_ok=True)
    env = dict(os.environ, TMPDIR=os.path.join(args.work, "tmp"))
    os.makedirs(env["TMPDIR"], exist_ok=True)
    # Prepared and planned one after the other
    # (both add worktrees to the same repository),
    # then the sides that build run at the same time (see BuildGate).
    paths = {"upstream": prepare(args.work, "upstream", args.upstream, True),
             "merged": prepare(args.work, "merged", args.merged, args.apply_a0_to_merged)}
    plans = {side: plan_side(p, env, args.work, args.fresh) for side, p in paths.items()}
    outcomes = {side: plan.reused for side, plan in plans.items() if plan.reused is not None}
    building = {side: plan for side, plan in plans.items() if plan.reused is None}
    gate = BuildGate(len(building))
    # The first side to fail stops the other one,
    # and so do Ctrl-C and `kill`
    # (the commands run in their own process groups, so neither reaches them).
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        futures = {side: pool.submit(run_side, side, plan, env, args.work, gate) for side, plan in building.items()}
        try:
            concurrent.futures.wait(futures.values(), return_when=concurrent.futures.FIRST_EXCEPTION)
        except BaseException:  # Ctrl-C, or `kill` (see stop_on_sigterm)
            stop_all()
            raise
        if FAILURES:
            stop_all()
    if FAILURES:
        # A side stopped because the other failed says so in its own error.
        for side, e in FAILURES:
            print(f"[{side}] {e}", file=sys.stderr, flush=True)
        sys.exit(1)
    outcomes |= {side: f.result() for side, f in futures.items()}
    upstream, merged = outcomes["upstream"], outcomes["merged"]
    text, ok = render(compare_hashes(upstream.result.hashes, merged.result.hashes),
                      compare_snapshots(upstream.result.snapshots, merged.result.snapshots),
                      {"upstream": upstream.how, "merged": merged.how})
    print(text)
    sys.exit(0 if ok else 1)

if __name__ == "__main__":
    main()
