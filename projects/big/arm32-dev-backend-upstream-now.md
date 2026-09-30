# ARM32 Dev Backend: What Upstream Can Use Now

The arm32 work found defects, fixed some, and learned things that help
upstream Roc today, whether or not the arm32 backend lands. This note collects
them in one place, ordered by how directly upstream can act on them. The
details live in the notes each entry links; this is the index for proposing
them.

Each entry was checked against upstream `main` at `b2b9541c42` (2026-09-28)
unless it says otherwise. Commit hashes are on `32-bit-backend`.

Contents:

1. Fixes ready on the branch that help upstream today
2. Open defects in upstream code, not fixed
3. CI, build and tooling findings
4. Proposals and lessons
5. Suggested order
6. How to verify each item yourself

## 1. Fixes ready on the branch that help upstream today

Each is its own commit and applies without the arm32 backend. Proposing them
as small pull requests first costs upstream little review and shrinks the
arm32 pull requests.

| Fix | Commit | Who it helps today |
|---|---|---|
| **Default-platform glibc builds with `--opt=dev` crashed at startup.** A headerless program built for `x64glibc`/`arm64glibc` with the dev backend asked for the glibc loader but had no dynamic section, so it crashed before `main`. The LLVM path already linked statically; the rule is now shared (`buildLinkAbi`), with a new CLI case that builds and runs x64glibc `--opt=dev`. Still present upstream (only `llvmBuildLinkAbi` exists). | `16d1ab893c` | Every x86_64 and aarch64 glibc user of the dev backend |
| **The snapshot tool recorded every dev compile error as `NOT_IMPLEMENTED`.** `processDevObjectSnapshot` turned any error into the not-implemented hash (`else \|_\|`), so a real code-generation failure looked like an unsupported target. Still present upstream. | `d910f7aa39` | Anyone relying on `dev_object` snapshots |
| **The instruction cache was not flushed before JIT memory ran.** `ExecutableMemory` relied on the kernel's maintenance at `mprotect`; the flush now runs explicitly (shared with the machine-code shim). Mandatory on ARMv7; on aarch64 it makes the ordering explicit instead of relying on kernel behaviour. Still absent upstream. | `49bf1449b9` (+ `6eeba018af`, the CI path fix) | aarch64 JIT (interpreter shim, eval) |
| **A backend unit test wrote to stderr, which fails `zig build`** although every test passed. The merge now records the conflict in `WasmModule.merge_type_conflict`. Still present upstream. | `1138ce4c33` | Anyone running `run-test-zig-module-backend` |
| **Relocations were patched by guessing the ISA from the bytes** (an `E8` before the operand meant x86_64). Now the caller passes the ISA. Forbidden by AGENTS.md's no-heuristics rule regardless of arm32. | `e865de0a8a` (mixed with arm32's rules; would need splitting) | Code health; AGENTS.md compliance |
| **minici's prerequisites were undocumented** (qemu, Rust targets, kcov...). | `2def52effc` | New contributors |
| Target data sized by the host's `usize`; erased-callable layouts taken from the host; `LargeBlockAllocator` shift that only compiles for 64-bit `usize`; the wasm test ULEB reader; wasm eval backend reported available on 32-bit hosts. | `f4af9e372d`, `d69fb5eb7f`, `f2fb602f74`, `e610fb5353`, `1344ce3159` | No 64-bit behaviour change; they make the compiler build and cross-compile correctly for any 32-bit target, so they can land early as "32-bit readiness" |

Details for every entry: `arm32-dev-backend-existing-code-changes.md`,
"Fixes to existing defects".

## 2. Open defects in upstream code, not fixed

Found by the arm32 work, verified in the tree, left alone because they are
outside its scope. Details and fix directions:
`arm32-dev-backend-issues.md`, section 1.1.

| Defect | Where | Severity | Upstream `main` |
|---|---|---|---|
| **wasm32 narrows `U64` sublist indices to 32 bits.** At our base, `List.sublist([1, 2, 3], { start: 4294967296, len: 1 })` gave `[1.0]` on wasm and `[]` elsewhere (confirmed with an eval case). | `WasmCodeGen.zig`, `.list_sublist` | Miscompile | Partly changed: the main path now passes `i64`; the zero-sized-element path still uses `i32_wrap_i64`. Re-verify with the eval case. |
| **The snapshot tool hashes programs that failed to type-check** (the definition becomes `<runtime_error>`), so a new snapshot can lock in a broken program silently. | `snapshot_tool/main.zig` | Test hole | Present |
| **LIR images drop the layout store's recursive-graph keys**, so any consumer handing an image to the object-file path panics on the first recursive type. | `lir/lir_image.zig` (built with an empty map) | Latent panic | Present |
| **Procedure symbol names change with every compiler build** (the git revision is folded into every checked-artifact key), so any byte-pinning test of real code breaks on the next commit. The A0 oracles work around it with `ProcIdentity.canonicalizeSymbolNames`. | `check/checked_artifact.zig` | Reproducibility; design question | Present |
| **`abs64` relocation patching is sized by the host**: four bytes when the compiler runs on a 32-bit host. | `Relocation.zig`, `patchAbsolutePointerOperand` | Latent (32-bit hosts) | Present |
| **A string result stored from one register** for non-stack locations (length and capacity left unwritten); commented "Fallback". | `LirCodeGen.zig`, `storeResultToSavedPtr` `.str` | Either dead or corrupting; a forbidden fallback | Present |
| **`list_get_unsafe` silently truncates an i128/Dec index** instead of reporting the producer bug. | `LirCodeGen.zig` | Forbidden best-effort recovery | Present |
| **A `U64` discriminant loaded as eight bytes** on the 64-bit targets, masking only discriminants under four bytes; unverified whether the padding is always zero. | `LirCodeGen.zig`, `generateDiscriminantAccess` | Possible wrong tag | Not rechecked |
| **The glibc stub emits `ret` for `aarch64_be`, `wasm32`, `other`**, not an instruction on most of them. | `build/glibc_stub.zig` | Unreached today | Present |
| **git-lints pads a file name with NUL bytes** in "src/ file never imported". | `tidy --git-lints` | Cosmetic | Not rechecked |
| **The compiler at our base panics type-checking basic-cli 0.22.2** ("trying to add var at rank 5, but current rank is 4"); the nightly checks it cleanly. | type checker | Crash | Probably fixed; recheck after the merge |
| Redundant narrowing shifts before byte stores. | `LirCodeGen.zig` | Dead work | Not rechecked |
| **The x86_64 SysV classifier asserts on a zero-sized aggregate member.** `test/fx/parallel_fusion.roc` and `test/fx/inspect_dict_set.roc` panic (`assert(size > 0)`) when built with `--target=x64musl` and the default LLVM backend, so `roc-cross-compile (ubuntu-24.04, x64musl)` fails. Found 2026-10-01. | `layout/abi/x86_64.zig`, `classifySystemV` via `classifyMemberSysV` | Compiler crash | Present at `00cab95af8` |

## 3. CI, build and tooling findings

- **A plain `zig build` deletes the user's whole Roc cache.** The install
  step (and the steps that build the test platforms) depend on
  `ClearRocCacheStep`, which deletes `~/.cache/roc` (or
  `$XDG_CACHE_HOME/roc`), downloaded packages included, and `ROC_CACHE_DIR` does not move packages.
  A contributor's basic-cli download vanished during `run-test-cli`. Present
  upstream. Fix: clear only the host entries the step means to invalidate.
- **The full `ci_zig.yml` run cannot finish on hosted Linux runners.** On
  2026-09-29 and 2026-09-30 every `zig-cross-compile` target, the two Linux
  `zig-tests`, valgrind and the arm64 nix build were killed together (exit
  143) 12-35 minutes into building `roc` with LLVM. Upstream's own nightly
  loses the same jobs. Any step after `cross compile with llvm` is therefore
  never tested on GitHub.
- **Test failures in upstream's ReleaseFast `-Dfuzz` test pass.** macOS-15's
  second `run-test-zig` pass (ReleaseFast, `-Dfuzz`) failed 11 tests; the
  Debug pass had none. Reproduced on Linux at our base `58508d582b`: the LIR
  proc-pass test "no-op workers do not append duplicate source bodies" and
  two staged SpecConstr tests (one expecting `error.OutOfMemory` and getting
  nothing). Four more fail at the base too (two interface-summary tests,
  range proving, and `lir_inline_test` "interface summaries relocate across
  bodies and executor lanes"). Three fx stack-overflow tests fail only on
  macOS. "snapshot validation" is still open (verification note, part 3). These look like ReleaseFast-only
  behaviour (removed safety checks, allocation-failure injection) in
  upstream's tests.
- **macOS-15-intel `zig-tests`**: RustGlue plugins fail to load and
  `--opt=speed` reports `LlvmBackendUnavailable`, in upstream's nightly too.
- **Line-number exclusions in `build.zig`'s pattern checks go stale.** Two
  `inspected.zig` ranges already point at unrelated lines. A marker comment on
  each allowed line would not move. (Issues note, 1.3.)
- **A test that writes to stderr fails `zig build`** even when every test
  passes: a trap worth a line in the contributor docs.
- **Partially deleting `.zig-cache/o` breaks Zig's cache for good**
  ("failed to check cache: FileNotFound"); only a whole-directory delete
  recovers. Cross-built compilers (250-400 MB each) fill a disk fast.
- **A PR minici shard can fail before running anything**: on 2026-09-30
  `macos-core` failed at "Download MiniCI build artifact" after a long wait
  in the queue, and ran no tests. Cause not investigated (the artifact is
  short-lived).

## 4. Proposals and lessons

- **Byte-identity oracles for backend refactors (A0).** Hash every eval
  case's x86_64 and aarch64 object (one line per case in
  `test/dev_code_hashes/eval.blake3`) and check it in minici, plus the
  `dev_object` snapshots. Any refactor of the dev backend can then prove it
  changed no output byte. It held at every one of the arm32 work's commits
  (checked commit by commit), which is what lets a 7,700-line driver change
  be reviewed with confidence.
  Cost: about four minutes on sixteen cores (46 on the Windows runner, so
  check on Linux only, `56029eddf9`). This is the arm32 plan's second pull
  request anyway.
- **The Zig 0.16 arm ABI bug (reported).** Zig passes a by-value
  `callconv(.c)` argument of nested `extern struct` type off-ABI on
  `arm-linux-musleabihf`. The fx test host works around it, with two
  tripwires that fail when Zig fixes it. Reported to Zig as
  https://codeberg.org/ziglang/zig/issues/37018 (2026-09-30).
  (Issues note, 1.2.)
- **Stop committing prebuilt binaries** (the owner's intention). About 100
  `crt1.o`, `libc.a`, glibc stub and `.lib` files are committed; a binary
  cannot be reviewed, which is how the xz-utils backdoor hid. Generate them
  at build time from Zig's sources, as `ci/vendor_musl_runtime.py` already
  does for arm32. (Issues note, 1.4.)
- **Report peak memory per test** in the eval runner: the child's
  `ru_maxrss` from `wait4` costs nothing and would have found two tests that
  need more than a 1 GB board has. (Issues note, 1.4.)
- **x86_64 is one register from an invariant panic.** Over the eval corpus
  instruction selection peaks at 12 of 13 allocatable general registers on
  x86_64. The D10 register-budget measurement from A1 makes that visible.
- **The driver's ISA-specific code** (592 raw emitter calls, 84% of them
  upstream's x86_64/aarch64 code): a per-ISA facade would make the driver
  ISA-neutral. A design question for the maintainers; see
  `arm32-dev-backend-facade-decision.md`.

## 5. Suggested order

1. Small independent fixes from section 1: `16d1ab893c` (a user-visible crash)
   first, then `d910f7aa39`, `1138ce4c33`, `49bf1449b9`, `2def52effc`.
2. The cache-wipe fix and the ReleaseFast test failures, as issues.
3. Done: the Zig ABI bug is filed (https://codeberg.org/ziglang/zig/issues/37018).
4. The section 2 defects as issues, with the wasm sublist miscompile first
   (it has a ready eval case).
5. The A0 oracles, which open the arm32 series.

## 6. How to verify each item yourself

Every check below runs against upstream, not against this branch, unless it
says so. The code-reading checks need nothing built; the others say what they
cost.

### Setup (once)

```sh
cd ~/repos/roc_32bit
git fetch upstream
git worktree add --detach ~/repos/roc-upstream upstream/main
cd ~/repos/roc-upstream
# A plain `zig build` deletes ~/.cache/roc (item 3.1); point it elsewhere:
export XDG_CACHE_HOME=/tmp/roc-probe-cache ZIG_GLOBAL_CACHE_DIR=~/.cache/zig
zig build roc                 # a few minutes; enough for most checks
```

Heavy commands (marked **heavy**) are best run one at a time, under a cap:
`systemd-run --user --scope -p MemoryMax=24G -p MemorySwapMax=4G <command>`.
Anything below that edits files is undone with `git checkout -- .` and
`git clean -fd` in the worktree. When done: `git worktree remove
~/repos/roc-upstream`.

### Section 1: fixes on the branch

**1.1 glibc `--opt=dev` crash.** Build and run a program with no platform
header:

```sh
printf 'main! = |_| {\n    echo!("Hello, World!")\n    Ok({})\n}\n' > /tmp/hello.roc
./zig-out/bin/roc build --opt=dev --no-cache --target=x64glibc --output=/tmp/hello_dev /tmp/hello.roc
/tmp/hello_dev                                    # upstream: crashes before printing
readelf -l /tmp/hello_dev | grep -E 'INTERP|DYNAMIC'  # an INTERP header but no DYNAMIC
./zig-out/bin/roc build --opt=speed --no-cache --target=x64glibc --output=/tmp/hello_speed /tmp/hello.roc
/tmp/hello_speed                                  # LLVM path: prints Hello, World!
```

The same commands with the branch's `roc` print `Hello, World!` for both.

**1.2 Snapshot errors recorded as `NOT_IMPLEMENTED`.** Code reading:
`git show upstream/main:src/snapshot_tool/main.zig | grep -n 'else |_|'`, then
read `processDevObjectSnapshot` around the match: every error from
`compileToObjectFile` becomes the `NOT_IMPLEMENTED` hash.

**1.3 Instruction cache not flushed.** Code reading:
`git show upstream/main:src/backend/dev/ExecutableMemory.zig | grep -n 'mprotect\|flush'`
shows the `mprotect` and no flush. A failure is timing-dependent on aarch64,
so there is no reliable reproduction; on ARMv7 it is required by the
architecture (the branch's arm32 runs depend on it).

**1.4 A test writing to stderr fails `zig build`.**

```sh
zig build run-test-zig-module-backend 2>&1 | grep -E 'WASM merge|passed|failed command'
```

It prints "WASM merge: both modules import ...", every test passes, and the
step still reports a failed command.

**1.5 Relocations patched by guessing the ISA.** Code reading:
`git show upstream/main:src/backend/dev/Relocation.zig | grep -n -i '0xe8'`
shows the byte test that decides x86_64 versus aarch64.

**1.6 minici prerequisites undocumented.**
`git show upstream/main:BUILDING_FROM_SOURCE.md | grep -ciE 'qemu|kcov'`
prints 0; on the branch it does not.

**1.7 32-bit readiness.** **Heavy** (about 8 GB, 10 minutes):

```sh
zig build build-test-eval-runner -Dtarget=arm-linux-musleabihf -Doptimize=ReleaseSmall --prefix /tmp/arm32-probe
```

Upstream fails to compile `src/base/LargeBlockAllocator.zig` (a `usize`
shifted by a `u6`). The host-word sizing is code reading:
`git grep -n '@sizeOf(usize)\|@alignOf(usize)' upstream/main -- src/backend/dev/LirCodeGen.zig`.

### Section 2: open defects

**2.1 wasm sublist indices.** Add two temporary eval cases to the list in
`src/eval/test/eval_low_level_tests.zig`:

```zig
    .{
        .name = "probe - sublist start at 2^32",
        .source = "List.sublist([1, 2, 3], { start: 4294967296, len: 1 })",
        .expected = .{ .inspect_str = "[]" },
    },
    .{
        .name = "probe - zero-sized sublist start at 2^32",
        .source =
        \\{
        \\x : List({})
        \\x = [{}, {}, {}]
        \\List.len(List.sublist(x, { start: 4294967296, len: 1 }))
        \\}
        ,
        .expected = .{ .inspect_str = "0" },
    },
```

Then `zig build run-test-eval -- --test-filter "probe - "` (**heavy**, builds
the eval runner). A failure on the wasm backend only confirms the bug; at our
base the first case gave `[1.0]` on wasm. Undo with `git checkout -- src`.

**2.2 The snapshot tool hashes programs with type errors.**

```sh
cp test/snapshots/dev_object_arithmetic.md test/snapshots/dev_object_probe.md
sed -i 's/add(3, 4)/add("x", 4)/' test/snapshots/dev_object_probe.md
zig build build-snapshot-tool
./zig-out/bin/snapshot --update-expected test/snapshots/dev_object_probe.md; echo "exit $?"
grep -nE 'runtime_error|^x64|^arm64|PROBLEMS' test/snapshots/dev_object_probe.md
rm test/snapshots/dev_object_probe.md
```

The MONO section shows `<runtime_error>`, hash lines are written, no problem
is reported and the tool exits 0.

**2.3 LIR images drop recursive-graph keys.** Code reading:
`git show upstream/main:src/lir/lir_image.zig | grep -n interned_recursive_graphs`
shows the map created empty when an image is loaded, and
`git grep -n 'has no recursive-graph key' upstream/main -- src/layout` shows the
panic the digest raises without it.

**2.4 Symbol names change with every build.** Two builds of `roc` at
different commits name the same procedure differently. **Heavy** (`zig
build` builds the test platforms):

```sh
zig build
./zig-out/bin/roc build --opt=dev --no-cache --keep-temp --output=/tmp/int1 test/int/app.roc
nm <kept directory it prints>/roc_app_*.o | grep roc__proc_ | head -3
git commit --allow-empty -m probe && zig build roc
./zig-out/bin/roc build --opt=dev --no-cache --keep-temp --output=/tmp/int2 test/int/app.roc
nm <new kept directory>/roc_app_*.o | grep roc__proc_ | head -3   # different digests
git reset --hard HEAD~1                                          # drop the probe commit
```

The cause is code reading:
`git grep -n compiler_artifact_hash upstream/main -- src/check/checked_artifact.zig`.

**2.5 `abs64` sized by the host.** Code reading:
`git show upstream/main:src/backend/dev/Relocation.zig | grep -n -A12 'fn patchAbsolutePointerOperand'`:
the width comes from `@sizeOf(usize)`, the compiler's own word, not from the
relocation kind.

**2.6 to 2.8, 2.12 (driver fallbacks, the discriminant load, byte-store
narrowing).** Code reading in `src/backend/dev/LirCodeGen.zig` on upstream:

```sh
F=src/backend/dev/LirCodeGen.zig
git show upstream/main:$F | grep -n 'Fallback for non-stack string location'   # 2.6
git show upstream/main:$F | grep -n 'just load the low'                        # 2.7
git show upstream/main:$F | grep -n 'fn loadAndMaskDiscriminant'              # 2.8
git show upstream/main:$F | grep -n 'fn storeResultToSavedPtr'                # 2.12: the .u8/.i8 arms
```

Whether 2.8 misbehaves in practice needs a tag union whose four-byte
discriminant is followed by non-zero padding; nobody has built one yet.

**2.9 glibc stub `ret`.**
`git show upstream/main:src/build/glibc_stub.zig | grep -n 'ret'` shows `ret`
emitted for `.aarch64_be, .wasm32, .other`.

**2.10 git-lints NUL padding.**

```sh
echo 'pub const x = 1;' > src/zz_probe.zig && git add src/zz_probe.zig
zig build run-check-git-lints 2>&1 | cat -v | grep zz_probe   # ^@^@... after the name
git rm -q --cached src/zz_probe.zig && rm src/zz_probe.zig
```

**2.11 basic-cli panic.** With a `roc` built at our base (`git -C
~/repos/roc-upstream checkout --detach 58508d582b && zig build roc`):
`./zig-out/bin/roc check <any app using basic-cli 0.22.2>`, for example
`~/repos/roc_32bit/.git/verify-tools/sitrep-roc/sitrep.roc`. It panics with
"trying to add var at rank 5, but current rank is 4". Repeat at
`upstream/main` to see whether it is fixed there.

**2.13 x86_64 SysV zero-sized member.** **Heavy** (builds the test
platforms):

```sh
zig build run-test-cli -- --suite platforms --filter test/fx/parallel_fusion.roc \
  --filter test/fx/inspect_dict_set.roc --cross-target=x64musl
```

Both crash in the build phase with `assert(size > 0)` in
`src/layout/abi/x86_64.zig`.

### Section 3: CI, build and tooling

**3.1 `zig build` deletes the Roc cache.** Safely, with a stand-in cache:

```sh
export XDG_CACHE_HOME=/tmp/roc-probe-cache
mkdir -p $XDG_CACHE_HOME/roc/packages && touch $XDG_CACHE_HOME/roc/packages/marker
zig build 2>&1 | grep 'Cleared roc cache'
ls $XDG_CACHE_HOME/roc      # gone
```

Without `XDG_CACHE_HOME` it deletes your real `~/.cache/roc`.

**3.2 Full CI runs lose their Linux build jobs.** In GitHub, open run
36666186906 on InvisOn/roc, or:

```sh
gh run view 36666186906 -R InvisOn/roc --json jobs \
  --jq '.jobs[] | select(.conclusion=="cancelled") | "\(.name) \(.startedAt) \(.completedAt)"'
```

Each cancelled job's log ends in "Process completed with exit code 143".
Upstream's own runs: `gh run list -R roc-lang/roc --workflow ci_zig.yml`.

**3.3 ReleaseFast `-Dfuzz` test failures.** **Heavy** (about an hour and up
to 24 GB even filtered), at our base:

```sh
git checkout --detach 58508d582b
systemd-run --user --scope -p MemoryMax=24G -p MemorySwapMax=4G \
  zig build -j2 run-test-zig -Doptimize=ReleaseFast -Dfuzz -Dsystem-afl=false -- \
  --test-filter "no-op workers do not append duplicate source bodies" \
  --test-filter "staged SpecConstr discovery admits source order" \
  --test-filter "staged SpecConstr submission failure drains accepted tasks"
```

All three tests fail; with `-Doptimize=Debug` (the default) they pass. The other
test names are in the verification note, part 3.

**3.4 macOS-15-intel glue failures.** CI only:
`gh run view 36615593810 -R InvisOn/roc --log-failed | grep 'run failed'`.

**3.5 Stale line-number exclusions.** Code reading:
`grep -n excluded_ranges build.zig`, then view the `inspected.zig` lines it
names, for example
`git show upstream/main:src/eval/inspected.zig | sed -n '2475p;3265,3276p'`,
and compare with what the exclusion's comment says it allows.

**3.6 Partial `.zig-cache` deletion.** Destructive to the build cache, so
only in the throwaway worktree: after a build, delete one directory under
`.zig-cache/o` that holds a built binary, then rebuild; Zig fails with
"failed to check cache: FileNotFound" until `.zig-cache` is deleted whole.

**3.7 minici shard without its artifact.**
`gh run view 36666185179 -R InvisOn/roc --json jobs --jq '.jobs[] | select(.name=="zig-minici (macos-core)") | .steps[] | "\(.name) \(.conclusion)"'`.

### Section 4: proposals

- **A0 oracles** (on the branch): `zig build run-check-dev-code-hashes`
  passes. Change any x86_64 code generation (for example swap two
  independent instructions in an emitter) and rerun: it names the eval cases
  whose bytes changed.
- **Zig arm ABI bug:**
  `zig test -target arm-linux-musleabihf --test-cmd qemu-arm-static --test-cmd-bin test/fx/platform/zig_arm_nested_struct_abi_probe.zig`
  (on the branch; needs `qemu-user-static`). Passing means the bug is still
  in Zig.
- **Committed binaries:**
  `git ls-tree -r --name-only upstream/main | grep -cE '\.(o|a|lib)$'`
  (80 at `b2b9541c42`; the glibc stub `.so` files come on top).
- **x86_64 register budget:** no one-command check; the measurement and its
  method are in `src/backend/dev/arm32/DESIGN.md`, "register budget".
- **Facade numbers:** `python3 ~/repos/roc_32bit/.git/verify-tools/facade_stats.py`.
