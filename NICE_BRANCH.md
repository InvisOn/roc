# The clean arm32 branch: first cut

Personal note; not committed. Written 2026-10-02. This is a first cut from
what was already known; each item gets checked properly when we reach it.

The reference branch `32-bit-backend` adds 26,348 lines to upstream. That is
too much to review. We build a new branch from upstream, commit by commit,
with better code and less of it.

## Handoff: where things stand (2026-10-02)

For a new conversation.

- **The clean branch** is `dev-backend-aarch32`, in the worktree
  `~/repos/roc-dev-backend-aarch32`, created from upstream
  `e79b7f856b` (the commit the reference is verified against). It has no
  commits of ours yet. Work there.
- **The notes** are symlinked into that worktree at their usual paths
  (`projects/big/arm32-*.md`, `src/backend/dev/arm32/*.md`, `TODO.md`,
  `LEARNING*.md`, this file, `COMPILER_CHARTS.md`). The real files live in
  `~/repos/roc_32bit`. They show as untracked; **never commit them**
  (no `git add -A` or `git add .`; add files by name).
- **The reference** is `32-bit-backend` in `~/repos/roc_32bit`
  (PR InvisOn/roc#1): working, verified, 26K lines. Claude keeps it merged
  with upstream every night from a separate long-running conversation
  (`.git/verify-tools/UPSTREAM_SYNC.md`). Do not sync it from here. Before
  any heavy build, check `.git/verify-tools/upstream-sync/state.txt` in
  `roc_32bit`: only one heavy job at a time.
- **Decided:** I write commits, Claude proposes and reviews; match the
  maintainers' style; the facade is closed with option (b); `ci/` scripts
  stay Python; we sync this branch with upstream together.
- **Not decided:** the 8-week target needs me to write only the first of
  each pattern and Claude the rest (Claude proposed it; I have not said
  yes). Until I do, the rule is that I write every commit.
- **Claude owes:** see `CLAUDE_OWES.md`. Delivered 2026-10-02 (the two
  sections at the end of this file): the breakdown of the driver's changed
  lines, the `Isa` recommendation, and the encoder proposal (E1 to E6).
  Waiting for my answers to them.

**This branch is what goes upstream, when it is done.** The reference
branch does not (decided 2026-10-02).

## How we work

1. Claude proposes a commit: what it contains, what to cut and why, its size.
2. I decide.
3. **I write it.** Claude helps only when I ask.
4. We review it together.
5. It is verified.
6. I commit.

- The new branch gets its own worktree. The notes stay in `roc_32bit`.
- We sync the new branch with upstream together, as part of the learning.
  Claude keeps syncing the reference branch by itself every night.
- Goal: better code quality. A smaller diff is welcome, never at the cost of
  quality.
- **Weigh every decision's effect on upstream** (decided 2026-10-03): what
  it shows on roc-lang/roc's pages now (no `#NNNN` in commit messages, no
  mentions, nothing filed without me), and what it would cost the
  maintainers when this branch is proposed (their code changed, review
  size, CI time). Each proposal states that cost next to its benefit.
- **Match the maintainers' style as much as possible** (decided 2026-10-02).
  Where upstream already has a way of doing something, the clean branch does
  it that way, even where the reference did it differently.
- The `ci/` scripts we added stay in Python.
- Heavy builds and tests by Claude only between 00:00 and 17:00.

## Where the 26,348 added lines are

Measured against upstream `e79b7f856b` at reference tip `f1fc227423`.

| What | Lines added | Hand-written code? |
|---|---|---|
| Plan notes in `projects/` | 4,513 | no |
| Generated: encoder oracle tests, eval hash file | 4,725 | no |
| arm32 docs (`DESIGN`, `GUIDE`, `TOOLS`) | 1,322 | no |
| Snapshots | 376 | no |
| CI scripts and workflows | 1,353 | partly |
| Shared driver `LirCodeGen.zig` | 5,631 (and 3,358 removed) | yes |
| arm32 backend directory | 3,656 (2,225 code, 361 tests, the rest comments and blanks) | yes |
| Other dev backend (ELF32, object writer, calling convention) | 2,728 | yes |
| `layout/abi` | 553 | yes |
| Other source (CLI, eval, builtins, build) | 978 | yes |
| Test platforms and programs | 435 | yes |

About 11,000 lines (41%) are not code a reviewer reads. About 14,000 are
hand-written. The hard part is the driver: about 9,000 changed lines in one
file.

"Generated" means written by a program, not typed by a person:

- `src/backend/dev/arm32/encoding_oracle_tests.zig` (2,588 lines):
  `ci/arm32_encoding_oracle.py` runs the real assembler on each line of
  `ci/arm32_encoding_oracle.s` and writes a Zig test expecting our encoder
  to produce the same bytes.
- `test/dev_code_hashes/eval.blake3` (2,137 lines): the eval runner writes a
  hash of the x86_64 and aarch64 machine code of every eval case; a later
  run compares against it.

## What to cut, cheapest first

1. **Notes off the branch** (4,513). Settled: they stay in `roc_32bit`.
2. **Generated files** (4,725). Open: generate the encoder tests when the
   tests run instead of committing them; keep or drop the eval hash file.
3. **Docs** (1,322): trim to what a maintainer needs.
4. **The driver.** Where "nice" is decided. Depends on the facade decision:
   whether the shared driver keeps naming arm32 instructions directly. No
   number promised until we try it.

## Useful to the wider Roc project, or only to us

| Useful beyond arm32 | arm32 only | Only ours |
|---|---|---|
| The independent fixes (10 commits, about 370 lines), such as the glibc `--opt=dev` crash | The A32 encoder and arm32 `CodeGen` | Plan and verification notes |
| The byte-identity oracle for 64-bit output: it protects any refactor of the driver | The ELF32 object writer | The verify tools in `.git/verify-tools/` |
| Checking an encoder against the real assembler: it would work for x86_64 and aarch64 too | The arm32 calling convention | `TODO.md`, the learning files, this note |
| Making the driver word-size aware: any future 32-bit target needs it | Targets, vendored runtimes, CI lanes | |
| Running cross-built tests on real hardware over ssh | | |
| The upstream bugs we found (`projects/big/arm32-dev-backend-upstream-now.md`) | | |

## Order to build in

Bottom-up, the same order as the learning stages: encoder, ELF32 writer,
calling convention, driver preparation, code generation by family, targets.
Suggested limit: about 400 hand-written lines per commit.

The reference is the oracle. Where a commit only reshapes code, its arm32
output must match the reference byte for byte. Where we simplify on purpose,
the qemu and Pi tests decide.

## Open decisions

- ~~The facade.~~ Decided 2026-10-02: option (b). arm32's cases sit in the
  shared driver next to x86_64's and aarch64's, as upstream writes its own.
  No facade, no separate arm32 lowering module. Reasons: upstream's driver
  is written that way and is growing that way (583 direct instruction calls,
  no open PR moves toward a facade); the driver is already about 97%
  architecture-neutral (about 720 specific lines of 28,366), so a facade
  would gain little; and most of our 9,000-line driver change is word-size
  awareness, which no facade removes.
- Where the reference departs from upstream's style, and whether to follow
  upstream instead. Known so far: the reference replaced upstream's two-way
  `arch == .x86_64` tests with an `Isa` enum, exhaustive switches and
  `binaryIs`, so that arm32 cannot fall into another architecture's branch.
  That is safer than upstream's style but is not upstream's style.
  Weighed 2026-10-02 (see "The `Isa` enum against upstream's style"): it is
  about 150 diff lines, not a large part. Claude recommends keeping it. Not
  decided.
- Generated files: commit them or generate them during the test run.
- Whether the 64-bit oracle goes upstream or stays our tool.
- What happens to the `arm32-holes` branch and `LEARNING_HOLES.md` now that
  I write every commit myself.

## Next

I decide, from the two sections at the end of this file:

1. Leave the 55 helpers in the driver (no move to `CodeGen`)?
2. Keep `Isa` and `binaryIs`?
3. The three encoder decisions: cut uncalled emitters, the oracle built by
   `zig build`, NEON later.

Then E1.

See also: `COMPILER_CHARTS.md` (the pipeline before and after), `TODO.md`.

## The driver's 9,000 changed lines, by kind (measured 2026-10-02)

Reference tip `21fc34953a` against upstream `e79b7f856b`,
`src/backend/dev/LirCodeGen.zig` only. Counted by scripts in
`.git/verify-tools/driver-breakdown/` (`classify2.py`, `classify.py`,
`groups.py`, `vocab.py`). They pair each removed line with the added line
that replaced it, so the numbers are close, not exact (5,604 added and 3,331
removed by this count; git says 5,631 and 3,358).

**1,831 old lines were each replaced by one new line:**

| Kind of replacement | Lines | Example |
|---|---|---|
| Width name only | 300 | `.w64` becomes `word` or `wide64_reg_width` |
| Literal becomes a word constant | 275 | `+ 8` becomes `+ listFieldOffset("length")`, `8` becomes `word_size` |
| Helper moved to `CodeGen`, nothing else | 238 | `self.emitLoad(` becomes `self.codegen.emitLoad(` |
| Helper moved and width name | 308 | both of the above on one line |
| Helper moved, width name and literal | 65 | |
| ISA test respelled only | 76 | `arch == .x86_64` becomes `isa == .x86_64` |
| Indentation only | 47 | a line now inside a `switch` arm |
| Comment reworded | 64 | |
| A real edit | 458 | about 175 word-size logic, 85 a two-way test becoming a switch arm, 15 role registers, 185 other |

**3,773 added lines replace nothing:**

| What | Lines |
|---|---|
| 102 new functions | 2,009 code (2,299 with their comments and blanks) |
| … `Wide64`: a 64-bit value on a 32-bit target (30 functions) | 723 |
| … NEON SIMD (19) | 637 |
| … i128 word by word (29) | 563 |
| … word helpers (11; five are the old 64-bit ones renamed) | 241 |
| … other (13) | 135 |
| New code inside existing functions | 803 (about 130 ISA arms, 170 word or `Wide64`, the rest mixed) |
| Outside functions (the word vocabulary, `erased_layout`) | 249 |
| Comments | 556 |
| Blank lines | 156 |

**1,500 removed lines are replaced by nothing:** 55 deleted functions (400
code lines, 557 with comments), 714 code lines inside surviving functions,
178 outside functions, 125 comments, 83 blank. Of the 55 functions, 50 are
the helpers that moved to the per-ISA `CodeGen` and 5 were renamed
(`emitPopcount64` to `emitPopcountWord` and so on).

### What follows from it

1. **The biggest single cause is not word size. It is the helper move**
   (the reference's A1): 55 small helpers (`emitLoad`, `emitStore`,
   `emitAddRegs`, `condEqual`, ...) went from the driver into each ISA's
   `CodeGen`. That touches 611 call sites in the driver (238 of them for no
   other reason), deletes about 500 lines there, and adds 981 lines to
   upstream's `x86_64/CodeGen.zig` and `aarch64/CodeGen.zig`. It is the
   start of the facade, which decision (b) closed. Upstream keeps these
   helpers in the driver as two-way `if`s. **Proposal: do not move them.**
   Each helper gets an arm32 arm where it stands. Estimate: about 50 helpers
   at about 3 lines each, in place of about 1,000 changed driver lines and
   about 1,000 lines in the two existing `CodeGen` files. To be tried, not
   promised.
2. **Width names: `.w64` leaves 892 lines.** Needed: a pointer-sized value
   must say so. It cannot be fewer sites. It can be smaller in two ways:
   - `wide64_reg_width` (180 lines) marks a value that is 64 bits on every
     target and is a compile error on arm32. arm32's `RegisterWidth` has
     only `w32`, so upstream's `.w64` left as it is may give the same
     compile error with no diff at all. To check when we reach it.
   - `word_size` (299 uses) is the same number as upstream's own
     `target_ptr_size` (which the reference then uses 4 times). One name;
     upstream's.
   Every one of these lines produces the same bytes on 64-bit targets, so
   they can be small commits, each checked by the 64-bit hash oracle.
3. **Literals to word constants: about 340 lines.** Needed (8, 16, 24, 56,
   63 are wrong on arm32). Upstream already names `target_ptr_size`,
   `roc_str_size` and `roc_list_size`, so named sizes are its style. The
   reference has more names than it needs (`wordOffset`, `listFieldOffset`,
   `strFieldOffset`, `word_bits`, `word_sign_bit`, `small_str_len_shift`,
   `word_value_size`, `erased_layout`); which to keep is decided per commit.
4. **The new arm32 lowering: about 2,000 code lines in new functions.**
   This is the feature. Restyling does not shrink it; each family is
   reviewed in the code-generation stage.
5. **Comments: 627 added, 196 removed.** The driver went from 2,117 to
   2,548 comment lines. 35 of them cite plan names (`D6`, `J1`, `A2`) or
   the notes file, which will not exist on the clean branch.

### The `Isa` enum against upstream's style

Measured, it is a small part of the diff, not a large one: 76 lines changed
only in spelling, plus the 46-line `isa.zig`. Upstream's driver has 289
lines with a two-way test; most of the rest sat in the 50 moved helpers or
became switch arms that arm32 needs anyway. The reference ends with 43
`switch (isa)`, 35 `binaryIs`, 87 direct tests against x86_64 or aarch64,
and 55 against arm32.

- **Keep as the reference has it (recommended).** A two-way `if ... else`
  gives a third ISA whatever the `else` holds. The reference found real
  cases (a call-relocation addend `if x86_64 -4 else 0`; `CallBuilder`
  chains with no final `else`). `AGENTS.md` forbids fallbacks, and with
  three ISAs a silent `else` is one. `Isa` is already built on upstream's
  own `classifyCpuArch`. Cost: about 150 diff lines and one small file.
  Make it its own early commit, no change for 64-bit, so the maintainers
  can refuse it cheaply.
- **If they refuse:** leave upstream's two-way tests as written and add an
  `.arm` arm only where arm32 needs its own answer, switching on upstream's
  `classifyCpuArch` class. Smallest diff; the compile-time guard is gone
  and only the arm32 tests catch a wrong `else`.

## Proposal 1: the encoder

Reference: `arm32/Emit.zig` 1,973 lines (1,384 code), `Registers.zig` 254,
`mod.zig` 50; generated `encoding_oracle_tests.zig` 2,588;
`ci/arm32_encoding_oracle.py` 231, `ci/elf32_reader.py` 248,
`ci/arm32_encoding_oracle.s` 373 (323 entries).

### Three decisions first

1. **Cut the emitters nothing calls.** At least 36 of the 157 emitters are
   never called outside the encoder's own tests (322 lines): `bicRegRegReg`,
   `tstRegReg`, `teqRegReg`, `rorRegReg*`, `mlsRegRegRegReg`, `smlal`,
   `revRegReg`, `rev16RegReg`, `sxtbRegReg`, `sxthRegReg`, `ubfx`, `sbfx`,
   `bkpt`, `ldrdRegMem`, `strdRegMem`, `vcmpe*`, `vcmpZero*`,
   `vcvt{S,U}32FromF{32,64}`, `vmovCorePairFromD`, `vpush`, `vpop`,
   `neonLogicD`, `neonTwoMiscD`, `vmovI64Q`, `vdupQFromLane`,
   `vmovLaneFromCore`, `addsRegRegModImm`, `orrRegRegModImm`,
   `bicRegRegModImm`, `tstRegModImm`. The count is a lower bound: a name
   that x86_64 or aarch64 also uses counted as called. Rule: the clean
   encoder has only what the reference's code generator calls.
2. **The oracle: no committed generated file, no Python in the build
   (recommended).** Upstream's `build.zig` runs no Python. `zig build`
   already has an assembler (`zig cc`), and every A32 instruction is 4
   bytes. So: `build.zig` assembles the `.s` file for arm and hands the
   bytes to a Zig test, which runs the emitter calls in the same order and
   compares instruction by instruction. That removes the 2,588 generated
   lines, both Python files (479 lines) and the stale-file CI step. It is
   not verified: how the backend test module gets the bytes, and what to do
   with the entries that carry a relocation (`bl`), are open. This also
   answers the "generated files" item for the encoder. If it does not work,
   the choice is the reference's way: the Python generator and the
   committed file.
3. **NEON waits for the SIMD family.** Nothing uses it before then. Its
   enums (302 lines) and emitters (337) come with the lowering that calls
   them, and so does the CPU-floor check. The `CC` block in `Emit` and
   `Call.zig` wait for the calling-convention stage for the same reason.

### The commits

Sizes are the reference's lines with comments, after the cuts. Each commit
adds its emitters and their oracle entries together, so each one proves
itself.

| # | Contents | Size | Cut |
|---|---|---|---|
| E1 | `arm32/Registers.zig` (core registers, the D view), a first `arm32/mod.zig`, the export from `dev/mod.zig` | about 230 | The S and Q views go to E5 and the NEON commits; check `name()` has a caller |
| E2 | `Emit.zig` begins: header, `Condition`, `ModImm`, `Operand2`, `DataOp`, the `Emit` type with `init`/`deinit`/`emit32`/`dataProc`, the moves (`movRegReg` to `movRegImm32`). The oracle harness and the first 18 entries | about 250, and the harness | The `CC` block; the comment citing `D2` |
| E3 | Arithmetic, logic, compare | about 180 | 5 uncalled emitters (37 lines) |
| E4 | Shifts, multiply, `clz`, `rbit`, `uxtb`, `uxth` | about 100 | 10 uncalled (114 lines), `bitfieldExtract` with them |
| E5 | Branches, `udf`, `nop`, `pcRelAddress`; `MemForm`, `fitsImmediate`; loads and stores; `push`, `pop` | about 215 | `bkpt`, `ldrd`, `strd` (22 lines) |
| E6 | VFP: arithmetic, compare, convert, core moves, loads and stores; the S view | about 290 | 9 uncalled (63 lines) |

About 1,270 hand-written lines in six commits. NEON (about 580 after its
cuts) comes later, in two or three commits with SIMD.

E2 sets the pattern for the rest, so it is the one to take slowly. The five
hand-written tests at the end of the reference's `Emit.zig` (`ModImm`,
condition inversion, offset ranges, the branch PC bias, stack alignment)
stay, each in the commit that adds what it tests.

Before E2 can be written, decision 2 needs an answer, and that needs a
short trial of the build step.

## Upstream #11885 landed (2026-10-03): what it changes for this plan

Added by the sync conversation. Upstream's consolidation PR (332 commits,
785 files) is merged into the reference as `da28d4ab0e`; details are in the
verification note and in `src/backend/dev/arm32/DESIGN.md`.

1. **A stored hash file cannot be the 64-bit oracle any more.** Upstream
   `842120f79f` puts each procedure's content identity into the machine
   code of its Debug checks, and that identity includes the compiler's git
   revision. The same program therefore compiles to different bytes at
   every compiler commit. The reference's `test/dev_code_hashes/eval.blake3`
   and its minici step are removed for that reason. This settles the open
   question "keep or drop the eval hash file": it cannot be kept.
   **What works instead:** build the base and the tip as the same compiler
   version and compare their hashes. `.git/verify-tools/relative_oracle.py`
   does it (a `git` shim answers the build's `git rev-parse --short=8 HEAD`
   with a fixed string); a run takes about 25 minutes for both sides. So
   "each commit checked by the 64-bit hash oracle" (point 2 above) means:
   that tool, base against tip, not a committed file.
2. **`dev-backend-aarch32` is now 332 commits behind upstream** (it sits at
   `d16a6598e4`). No work of ours is on it yet, so catching up is a
   fast-forward. We do it together.
3. **Interfaces our code builds on changed.** In `CallingConvention.zig`
   the stack-argument list is growable (`stack_args.items`, `u32` offsets,
   `addStackArg` can fail) and a call builder must be released
   (`defer builder.deinit()`). Tag discriminants are `u32`. The Debug
   invalid-local check takes a frame index and the two halves of the proc
   identity. The reference shows how arm32 follows each (the merge commit's
   message lists them).
4. **The measurements above predate #11885.** The driver breakdown and the
   line counts were taken against upstream `e79b7f856b`. Upstream's driver
   grew by about 290 lines; the categories still hold.
5. **Upstream issue #11909 is closed** (the SysV zero-size assertion), so
   the x64musl cross-compile and `eval-llvm` failures should be gone.
