# Incremental Plan: landing the arm32 dev backend upstream

Written 2026-10-22. This is how the arm32 work goes to roc-lang/roc: as a
series of small pull requests the maintainers can review and merge one at
a time, not as one 25,000-line branch.

Stepwise Rebuild (`stepwise-rebuild/`) stays as it is. It is how I learn
the backend by building it. This plan is how the work lands upstream. The
two fit together: a Stepwise Rebuild step can be the work behind one of
these pull requests.

Where things stand, what to do next and how to set up another machine:
`HANDOFF.md`. The tools it uses are in `tools/`. Each branch and step gets
a planning doc made from `templates/rfc.md`. Everything for one branch is
in its own directory, `rfcs/part-<NN>-<branch>/`: the branch doc
`<branch>-rfc.md` (the branch name with `/` written as `-`), its step docs,
and the write-ups of finished steps.

## Why incremental

- **Review size.** The reference adds about 23,000 lines (127 files). No
  maintainer can review that at once. Pieces of 300 to 2,000 lines can be.
- **Upstream moves fast.** 215 commits landed in two days this week. A big
  branch rots while it waits. A small PR is reviewed and merged before it
  conflicts.
- **Value early.** The first pull requests help upstream even if arm32
  never ships: bug fixes, a word-size-neutral driver, better tools.
- **Each step can be stopped.** If the maintainers say no to arm32 at some
  point, everything merged before that still stands on its own.

## Rules for every pull request

- **Proposed first, by me.** Nothing goes upstream without my say-so.
  Claude drafts, I decide and post.
- **Small and alone.** One topic per PR. It builds and passes minici on its
  own, on current upstream `main`.
- **64-bit output unchanged** unless the PR says otherwise. Every PR that
  touches the shared driver includes the relative oracle result: x86_64 and
  aarch64 object bytes identical before and after.
- **Upstream's style wins.** Where upstream does something one way, the PR
  does it that way. The rules in upstream's `AGENTS.md` and `design.md`
  apply, for example a same-line reason on every `unreachable`.
- **State the cost.** Each PR description says what it changes in shared
  code, what it adds to CI time, and what maintainers will have to keep
  working.
- **No unverifiable binaries.** The C runtime files arm32 programs link
  against are built from the pinned Zig, not committed (see part 10). If
  the maintainers want them committed, they must be byte-reproducible and
  checked in CI. The Zig ABI workaround is named where it appears.
- **Test commands in every PR.** Each description ends with a "How to
  test" section: copy-paste commands run from the repository root, and what
  their output should be.
- **One PR open at a time**, so review effort goes to one thing and nothing
  waits on a stack of unmerged work.
- Commits: signed, no Co-Authored-By or Claude-Session line, no upstream
  `#NNNN` or roc-lang links in commit messages or files.

## The sequence

Sizes are hand-written lines from the verified reference diff
(`git diff 73df27a5bb e0fa273ebf`), without our `projects/` notes, which
stay out of upstream. They will change as upstream moves.

| # | Pull request | Where it sits | Size | Changes 64-bit output? | Fork PR | Branch |
|---|---|---|---|---|---|---|
| 0 | Proposal to the maintainers (no code) | none | none | no | none | none |
| 1 | Architecture dispatch (`isa.zig`, `binaryIs`) and driver word size (1 of 3): sizes through `word`. With the glibc stub's arm32 body (draft 16), the instruction cache flush (draft 03) and the host word-size fixes (drafts 07 and 12) | dev backend: architecture choice and shared driver, plus glibc stub, code in memory, relocations | about 2,150 | no | [#9](https://github.com/InvisOn/roc/pull/9), folding in [#8](https://github.com/InvisOn/roc/pull/8), [#3](https://github.com/InvisOn/roc/pull/3) and closed [#4](https://github.com/InvisOn/roc/pull/4) | `dispatch/isa` |
| 2 | Driver word size (2 of 3): emit helpers move onto each code generator | dev backend: shared driver | about 3,000 | no | not yet | `word-size/emit-helpers` |
| 3 | Driver word size (3 of 3): the rest of `LirCodeGen.zig`'s 64-bit assumptions | dev backend: shared driver | about 2,000 | no | not yet | `word-size/driver-rest` |
| 4 | A32/NEON encoder and its assembler oracle | dev backend: instruction encoder | about 3,800 | no | not yet | `arm32/encoder` |
| 5 | ELF32 objects, ARM relocations, 32-bit DWARF | output: object file | about 1,300 | no | not yet | `arm32/elf32-objects` |
| 6 | arm32 code generator, frames, register roles | dev backend: per-architecture code generator | about 2,000 | no | not yet | `arm32/codegen` |
| 7 | AAPCS32 calling convention | dev backend: calls (C ABI, frames) | about 1,200 | no | not yet | `arm32/aapcs32` |
| 8 | 64-bit and 128-bit values on 32-bit registers | dev backend: shared driver | in 1, 2 and 3 | no | not yet | (in 1, 2 and 3) |
| 9 | NEON SIMD | dev backend: shared driver | in 1, 2 and 3 | no | not yet | (in 1, 2 and 3) |
| 10 | arm32 targets, platforms, runtime files, CI lane | CLI target (start) and linking (end) | about 500 | no | not yet | `arm32/targets` |
| 11 | arm32 as a host (running code in-process) | output: code in memory | about 550 | no | not yet | `arm32/host` |
| 12 | Docs, and turning the CI lane from optional to required | none | about 1,400 | no | not yet | `arm32/docs` |

The parts were renumbered 0 to 12 on 2026-10-25 (see Progress for the old
numbers). Two earlier parts folded into part 1 on 2026-10-24. One was a row
of separate upstream bug fixes: the drafts that matter to arm32 are now in
part 1, so the maintainers review them together with the change that needs
them, and the other drafts are not part of this plan. The other was the
first word-size part, which joined the architecture dispatch, so the
dispatch arrives together with the first change that needs it.

Parts 1, 2 and 3 together are the biggest change to upstream's own code, about
5,400 added and 2,800 removed lines in `LirCodeGen.zig`, plus about 1,000
in the x86_64 and aarch64 code generators. That is why it is split in
three, each proven byte-identical.

## Where each part fits in the compiler pipeline

```
source -> parse -> canonicalize -> type check          (front end, unchanged)
       -> post-check: monotype, lambda sets, Boxy plan  (unchanged)
       -> LIR, with the target's word size              (unchanged, already 32-bit ready)
       -> dev backend:
            LirCodeGen.zig, the shared driver            [1, 2, 3, 8, 9]
              -> per-architecture CodeGen               [1, 6]
                   -> instruction encoder               [4]
              -> calls: C ABI and frames                [7]
       -> output, one of:
            object file (ELF32, relocations, DWARF)      [5]
              -> link with the platform and C runtime   [10]
              -> executable
            code in memory, run by the compiler itself   [11]
```

Everything up to and including LIR already works for a 32-bit target: LIR
takes its word size from the target and already produces 32-bit layouts for
wasm32. All the arm32 work is after LIR, in the dev backend and what follows
it.

- **0** touches no pipeline stage.
- **1, architecture dispatch:** inside the dev backend. It is how the shared
  driver chooses the architecture's code, before any code is generated.
- **1, 2 and 3, word size:** the shared driver, `LirCodeGen.zig`. It turns each
  LIR statement into calls on the architecture's code generator. These
  parts remove its fixed 8-byte assumptions.
- **4, encoder:** the last step of code generation. It turns one
  instruction into its four bytes.
- **5, objects:** after code generation. It packs the machine code into an
  ELF32 object with relocations and debug info, for the linker.
- **6, code generator:** between the driver and the encoder. It turns the
  driver's requests (load, add, branch, frame) into arm32 instructions.
- **7, calling convention:** in code generation, wherever a call is made or
  received. It decides which registers and stack slots hold arguments and
  results, so Roc code and C code (the platform, builtins) agree.
- **8 and 9, wide values and SIMD:** in the shared driver, where LIR
  operations on 64-bit, 128-bit and vector values are lowered. On arm32
  they need word pairs, four words and NEON registers.
- **10, targets and platforms:** at both ends. The CLI accepts the target at
  the start, and linking at the end needs the platform and C runtime files.
- **11, host:** a second output path. Instead of an object file, the compiler
  writes the code into executable memory and runs it itself, which the
  eval tests and compile-time evaluation use.
- **12, docs:** none.

## Each pull request

### 0. The proposal

A message to the maintainers (their usual channel, Claude drafts it):

- what exists: a working arm32 dev backend, verified under qemu and on two
  Raspberry Pis, kept merged with upstream daily
- what we propose: landing it in the order above, one PR at a time
- the cost to them: review time, the shared-code changes in parts 1, 2 and 3,
  one extra CI lane
- what we ask: yes or no to arm32 as a dev backend target, and their
  preferences (CI lane, how big a PR may be)
- the runtime files: we propose building them instead of committing them
  (part 10), and offer the same for the 32 runtime binaries upstream already
  commits for x64 and arm64

Nothing else starts until they answer. If they want a different order or
size, this plan changes to match.

### Folded drafts

Since 2026-10-24 the arm32 drafts are part of the PRs that need them, not
separate fixes. Each fork PR below is folded into its part when that part is
cut, and is then closed.

| Draft | Folds into | Fork PR | State | Checked with | Branch |
|---|---|---|---|---|---|
| 16, glibc stub writes `ret` for 32-bit ARM | 1 | [#4](https://github.com/InvisOn/roc/pull/4) | closed, commit kept | the stub assembles | `fix/glibc-stub-arm-returns` |
| 03, no instruction cache flush before JIT code runs | 1 | [#8](https://github.com/InvisOn/roc/pull/8) | open | `build-ci` on x86_64 only, not yet on aarch64 | `fix/flush-jit-instruction-cache` |
| 07, 32-bit host readiness | 1 | none yet | | | none yet |
| 12, abs64 relocation sized by the host | 1 | [#3](https://github.com/InvisOn/roc/pull/3) | open | its unit test | `fix/abs64-relocation-width` |

Not part of the plan: 02, 14 (filed as 12532), 26 and the CI drafts. Their
fork PRs ([#5](https://github.com/InvisOn/roc/pull/5) for 26,
[#6](https://github.com/InvisOn/roc/pull/6) for 14,
[#7](https://github.com/InvisOn/roc/pull/7) for 02) stay open on their own.

If upstream merges the owner's glibc stub PR (12513) first, draft 16 drops
out of part 1.

### 1. Architecture dispatch and word size (1 of 3)

`src/backend/dev/isa.zig`: `isaOf` and `Isa.binaryIs`. It replaces
scattered `target.toCpuArch() == .x86_64` checks with one switch. Useful
alone: it makes every two-way arch assumption visible.

It also carries the two fixes where code gave one answer for "every other
architecture": the glibc stub, which wrote the AArch64 `ret` for 32-bit ARM
too (draft 16), and the instruction cache flush, which only x86 can skip
(draft 03).

### 1, 2 and 3. The driver for any word size

From `LirCodeGen.zig` and the x86_64 and aarch64 code generators. Each part
compiles and runs only the 64-bit targets, and includes the oracle proof.
Splitting by area:
- **1 (with the dispatch):** sizes, offsets and loops go through `word`, `word_size` and
  `word_bits` instead of a fixed 8. It also takes the host word-size fixes:
  the places that use the compiler's own word size where the target's is
  meant (draft 07), and the abs64 relocation that writes four bytes on a
  32-bit host (draft 12).
- **2:** the emit helpers move from the driver onto `self.codegen`, so each
  architecture supplies its own.
- **3:** what is left: the width vocabulary (`wide64_reg_width`,
  `wide64_store_width`), i128 by-pointer paths, and the `isa` switches.
No arm32 code yet. Upstream gains a driver whose word-size assumptions are
explicit.

### 4. The encoder

`src/backend/dev/arm32/Emit.zig` and `Registers.zig`, the encoding oracle
(`ci/arm32_encoding_oracle.py`, `.s`, the generated tests) and its build
step `run-check-arm32-encoding-oracle`. Self-contained: nothing calls it
yet. The oracle checks it against the GNU assembler byte for byte.

### 5. Objects

`object/elf.zig` (`write32`), `Relocation.zig` (ARM branches and movw/movt),
`Dwarf.zig` (four-byte addresses), `ci/elf32_reader.py`,
`ci/arm32_link_smoke.py`. Checked by the link smoke test.

### 6 and 7. Code generation and the calling convention

`arm32/CodeGen.zig`, `arm32/Call.zig`, the arm32 parts of
`FrameBuilder.zig` and `CallingConvention.zig`, and
`src/layout/abi/arm32.zig`. From here `roc build --target=arm32musl
--opt=dev` produces programs. The ABI shape tests (`test/fx/abi_call_shapes.roc`
and the nested struct probe) come with 7.

### 8 and 9. Wide values and SIMD

The Wide64 lowering, i128 as four words, and the NEON block, each in a few
PRs by operation family. Each one makes a known set of eval cases pass
under qemu.

### 10. Targets, platforms and CI

The `arm32musl` and `arm32linux` targets, the test runner options
(`--cross-target`, `--cross-run`), the `fx` and `int` platform entries, and
an optional qemu CI lane.

**The C runtime files.** Programs built for these targets link against the
musl `crt1.o` and `libc.a` and the glibc `Scrt1.o`. The reference commits
five such files (two `libc.a` of about 5.5 to 6 MB each). This PR does not
commit them, for security:

- Nobody can review a 6 MB `libc.a`. Reviewers would have to trust it. The
  xz backdoor hid its payload in exactly this kind of unreviewable test
  file.
- The reference's files cannot even be checked: `ci/vendor_musl_runtime.py`
  is not byte-reproducible, because musl's archive members are named by
  absolute cache paths.

So, in order of preference:

1. **Build them, don't commit them.** A build step produces the files from
   the pinned Zig, which already contains musl's source, and caches them.
   Nothing enters the repo, and nothing needs trusting beyond Zig itself.
   Cost: about a minute of build time the first time.
2. **If the maintainers want them committed:** make them byte-reproducible
   (fix the archive member names), and add a CI check that regenerates
   them and compares. Reviewers then trust a check, not a blob.
3. Committing them as they are, which is what upstream does for its 32
   x64 and arm64 runtime files today, is not offered. Nothing could
   verify them.

Upstream commits 32 such files for x64 and arm64. Option 1 could later
replace those too, as a separate proposal, if the maintainers want it.

### 11. arm32 as a host

`HostSplice.zig`, `ExecutableMemory.zig`, the instruction cache flush, and
the eval glue, so the compiler can run arm32 code it just generated. The
instruction cache flush itself lands earlier, in part 1.

### 12. Docs and the required lane

`src/backend/dev/arm32/DESIGN.md`, `GUIDE.md`, `TOOLS.md`, trimmed to what
upstream wants to keep, and the CI lane made required.

## How each PR is made

1. Write the branch's planning doc from `templates/rfc.md`, and settle its
   decisions, before cutting the topic. Required for every PR.
2. Bring the topic onto current upstream `main` in a fresh branch, by
   whatever method fits, and check it against the reference's final state.
3. Make it match upstream's current style and rules.
4. Run the full check: fast checks, the relative oracle, minici, and for
   arm32 parts qemu and the Pis.
5. Claude drafts the description, with its "How to test" commands. I
   review, edit and post it.
6. Keep it rebased on `main` daily until it merges. Then cut the next one.

## Ultrareviews

We have 3 free ultrareviews (`/code-review ultra`, a multi-agent review in
the cloud). Each one reviews the diff as it stands at that moment, so a run
spent on a PR that still changes is mostly wasted. Run each one on a PR
that is finished: its own nitpicky review is done and fixed, minici and the
relative oracle pass, and it is about to be filed upstream. Run it from the
PR's worktree (`/code-review ultra` reviews the local branch), or name the
fork PR (`/code-review ultra <number>`).

Spend them where a bug is subtle, our own tests are weak, and a mistake
costs the most:

1. **Step 1, architecture dispatch and word size (1 of 3).** It is the
   first code upstream sees, it changes the shared driver that x86_64 and
   aarch64 use, and steps 2 and 3 build on its patterns. The relative
   oracle proves 64-bit output did not change, but not that the new word
   vocabulary is right for 32 bits.
2. **Step 3, the rest of `LirCodeGen.zig`'s 64-bit assumptions.** Width
   mistakes here compile, pass every 64-bit test, and show up only as wrong
   values on arm32. The oracle checks only that 64-bit output is unchanged.
3. **Step 7, AAPCS32 calling convention.** ABI mistakes (argument
   registers, stack alignment, how 64-bit values are split across register
   pairs, returns by pointer) pass Roc-only tests and break only when Roc
   code calls a C host or a C host calls Roc.

Not worth a run: step 2 (a mechanical move that the oracle proves
byte-identical), step 4 (the assembler oracle checks every encoding), and
steps 10 to 12 (targets, docs and CI, which CI itself tests). If a step
listed above turns out small and well covered when it is cut, give its run
to step 6 (arm32 code generator) instead.

## Timing

If the maintainers review one PR a week, the 13 items take about 4 months.
Two a week, about 2 months. The order puts the parts most useful to
upstream first, so stopping early still leaves something of value.

## Progress

- 2026-10-22: plan written. Next: draft the proposal (part 0) and file
  draft 14 (part 1).
- 2026-10-22: part 12 changed: the C runtime files are built, not
  committed (security). Committed only if reproducible and checked in CI.
- 2026-10-22: added where each part fits in the compiler pipeline.
- 2026-10-24: part 1 removed. The arm32 drafts fold into parts 2 (16, 03)
  and 3 (07, 12). The other drafts are not part of the plan. Each plan PR's
  description carries the plan table (#, pull request, where it sits).
- 2026-10-24: part 3 folded into part 2. Part 2 is now the architecture
  dispatch plus the first word-size part, with drafts 16, 03, 07 and 12.
  The other part numbers stay as they were.
- 2026-10-24: `HANDOFF.md` written for work on the desktop PC. The fold
  into part 2 has not started. #9's earlier oracle pass did not cover the
  eval cases (see `pr-review.md`).
- 2026-10-25: parts renumbered 0 to 12, without gaps. Old to new: 0 to 0,
  2 to 1, 4 to 2, 5 to 3, 6 to 4, 7 to 5, 8 to 6, 9 to 7, 10 to 8, 11 to 9,
  12 to 10, 13 to 11, 14 to 12. The entries above use the old numbers.
- 2026-10-25: fold steps 1 to 5 done on `dispatch/isa` (not pushed), each
  with a step doc in `rfcs/part-01-dispatch-isa/`. Step 6 (word size 1 of 3) is next:
  option 1 chosen, so the "Classify ..." commits move to part 3.
- 2026-10-25: added `templates/rfc.md`, a planning doc shape based on
  Roc's RFCs, with ADR-style decision blocks. Every branch and step gets
  one. It is required before a PR's topic is cut.
