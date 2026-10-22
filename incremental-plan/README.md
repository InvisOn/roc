# Incremental Plan: landing the arm32 dev backend upstream

Written 2026-10-22. This is how the arm32 work goes to roc-lang/roc: as a
series of small pull requests the maintainers can review and merge one at
a time, not as one 25,000-line branch.

Stepwise Rebuild (`stepwise-rebuild/`) stays as it is. It is how I learn
the backend by building it. This plan is how the work lands upstream. The
two fit together: a Stepwise Rebuild step can be the work behind one of
these pull requests.

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
  against are built from the pinned Zig, not committed (see part 12). If
  the maintainers want them committed, they must be byte-reproducible and
  checked in CI. The Zig ABI workaround is named where it appears.
- **One PR open at a time**, so review effort goes to one thing and nothing
  waits on a stack of unmerged work.
- Commits: signed, no Co-Authored-By or Claude-Session line, no upstream
  `#NNNN` or roc-lang links in commit messages or files.

## The sequence

Sizes are hand-written lines from the verified reference diff
(`git diff 73df27a5bb 2f5d8e3685`), without our `projects/` notes, which
stay out of upstream. They will change as upstream moves.

| # | Pull request | Size | Changes 64-bit output? |
|---|---|---|---|
| 0 | Proposal to the maintainers (no code) | none | no |
| 1 | Upstream bug fixes from our drafts, one PR each, only those the maintainers want | small each | no |
| 2 | Architecture dispatch (`isa.zig`, `binaryIs`) | about 50 | no |
| 3 | Driver word size, part 1: sizes through `word` | about 2,000 | no |
| 4 | Driver word size, part 2: emit helpers move onto each code generator | about 3,000 | no |
| 5 | Driver word size, part 3: the rest of `LirCodeGen.zig`'s 64-bit assumptions | about 2,000 | no |
| 6 | A32/NEON encoder and its assembler oracle | about 3,800 | no |
| 7 | ELF32 objects, ARM relocations, 32-bit DWARF | about 1,300 | no |
| 8 | arm32 code generator, frames, register roles | about 2,000 | no |
| 9 | AAPCS32 calling convention | about 1,200 | no |
| 10 | 64-bit and 128-bit values on 32-bit registers | in 3 to 5 | no |
| 11 | NEON SIMD | in 3 to 5 | no |
| 12 | arm32 targets, platforms, runtime files, CI lane | about 500 | no |
| 13 | arm32 as a host (running code in-process) | about 550 | no |
| 14 | Docs, and turning the CI lane from optional to required | about 1,400 | no |

Parts 3 to 5 together are the biggest change to upstream's own code, about
5,400 added and 2,800 removed lines in `LirCodeGen.zig`, plus about 1,000
in the x86_64 and aarch64 code generators. That is why it is split in
three, each proven byte-identical.

## Where each part fits in the compiler pipeline

```
source -> parse -> canonicalize -> type check          (front end, unchanged)
       -> post-check: monotype, lambda sets, Boxy plan  (unchanged)
       -> LIR, with the target's word size              (unchanged, already 32-bit ready)
       -> dev backend:
            LirCodeGen.zig, the shared driver            [3, 4, 5, 10, 11]
              -> per-architecture CodeGen               [2, 8]
                   -> instruction encoder               [6]
              -> calls: C ABI and frames                [9]
       -> output, one of:
            object file (ELF32, relocations, DWARF)      [7]
              -> link with the platform and C runtime   [12]
              -> executable
            code in memory, run by the compiler itself   [13]
```

Everything up to and including LIR already works for a 32-bit target: LIR
takes its word size from the target and already produces 32-bit layouts for
wasm32. All the arm32 work is after LIR, in the dev backend and what follows
it.

- **0 and 1** touch no pipeline stage of ours. Draft fixes land wherever
  each bug is (the snapshot tool, the backend, the build scripts).
- **2, architecture dispatch:** inside the dev backend. It is how the shared
  driver chooses the architecture's code, before any code is generated.
- **3 to 5, word size:** the shared driver, `LirCodeGen.zig`. It turns each
  LIR statement into calls on the architecture's code generator. These
  parts remove its fixed 8-byte assumptions.
- **6, encoder:** the last step of code generation. It turns one
  instruction into its four bytes.
- **7, objects:** after code generation. It packs the machine code into an
  ELF32 object with relocations and debug info, for the linker.
- **8, code generator:** between the driver and the encoder. It turns the
  driver's requests (load, add, branch, frame) into arm32 instructions.
- **9, calling convention:** in code generation, wherever a call is made or
  received. It decides which registers and stack slots hold arguments and
  results, so Roc code and C code (the platform, builtins) agree.
- **10 and 11, wide values and SIMD:** in the shared driver, where LIR
  operations on 64-bit, 128-bit and vector values are lowered. On arm32
  they need word pairs, four words and NEON registers.
- **12, targets and platforms:** at both ends. The CLI accepts the target at
  the start, and linking at the end needs the platform and C runtime files.
- **13, host:** a second output path. Instead of an object file, the compiler
  writes the code into executable memory and runs it itself, which the
  eval tests and compile-time evaluation use.
- **14, docs:** none.

## Each pull request

### 0. The proposal

A message to the maintainers (their usual channel, Claude drafts it):

- what exists: a working arm32 dev backend, verified under qemu and on two
  Raspberry Pis, kept merged with upstream daily
- what we propose: landing it in the order above, one PR at a time
- the cost to them: review time, the shared-code changes in parts 3 to 5,
  one extra CI lane
- what we ask: yes or no to arm32 as a dev backend target, and their
  preferences (CI lane, how big a PR may be)
- the runtime files: we propose building them instead of committing them
  (part 12), and offer the same for the 32 runtime binaries upstream already
  commits for x64 and arm64

Nothing else starts until they answer. If they want a different order or
size, this plan changes to match.

### 1. Bug fixes

The drafts in `upstream-issue-drafts/` that are upstream bugs. File the
issue first. Offer a PR only if they want one. Draft 14 is first (ready
now), then 02 and 03.

### 2. Architecture dispatch

`src/backend/dev/isa.zig`: `isaOf` and `Isa.binaryIs`. It replaces
scattered `target.toCpuArch() == .x86_64` checks with one switch. Useful
alone: it makes every two-way arch assumption visible.

### 3 to 5. The driver for any word size

From `LirCodeGen.zig` and the x86_64 and aarch64 code generators. Each part
compiles and runs only the 64-bit targets, and includes the oracle proof.
Splitting by area:
- **3:** sizes, offsets and loops go through `word`, `word_size` and
  `word_bits` instead of a fixed 8.
- **4:** the emit helpers move from the driver onto `self.codegen`, so each
  architecture supplies its own.
- **5:** what is left: the width vocabulary (`wide64_reg_width`,
  `wide64_store_width`), i128 by-pointer paths, and the `isa` switches.
No arm32 code yet. Upstream gains a driver whose word-size assumptions are
explicit.

### 6. The encoder

`src/backend/dev/arm32/Emit.zig` and `Registers.zig`, the encoding oracle
(`ci/arm32_encoding_oracle.py`, `.s`, the generated tests) and its build
step `run-check-arm32-encoding-oracle`. Self-contained: nothing calls it
yet. The oracle checks it against the GNU assembler byte for byte.

### 7. Objects

`object/elf.zig` (`write32`), `Relocation.zig` (ARM branches and movw/movt),
`Dwarf.zig` (four-byte addresses), `ci/elf32_reader.py`,
`ci/arm32_link_smoke.py`. Checked by the link smoke test.

### 8 and 9. Code generation and the calling convention

`arm32/CodeGen.zig`, `arm32/Call.zig`, the arm32 parts of
`FrameBuilder.zig` and `CallingConvention.zig`, and
`src/layout/abi/arm32.zig`. From here `roc build --target=arm32musl
--opt=dev` produces programs. The ABI shape tests (`test/fx/abi_call_shapes.roc`
and the nested struct probe) come with 9.

### 10 and 11. Wide values and SIMD

The Wide64 lowering, i128 as four words, and the NEON block, each in a few
PRs by operation family. Each one makes a known set of eval cases pass
under qemu.

### 12. Targets, platforms and CI

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

### 13. arm32 as a host

`HostSplice.zig`, `ExecutableMemory.zig`, the instruction cache flush, and
the eval glue, so the compiler can run arm32 code it just generated. It
adds the instruction cache flush that draft 03 is about. Whether that also
covers aarch64 hosts is to be checked when this PR is cut.

### 14. Docs and the required lane

`src/backend/dev/arm32/DESIGN.md`, `GUIDE.md`, `TOOLS.md`, trimmed to what
upstream wants to keep, and the CI lane made required.

## How each PR is made

1. Cut the topic from the reference's final state, onto current upstream
   `main`, in a fresh branch.
2. Make it match upstream's current style and rules.
3. Run the full check: fast checks, the relative oracle, minici, and for
   arm32 parts qemu and the Pis.
4. Claude drafts the description. I review, edit and post it.
5. Keep it rebased on `main` daily until it merges. Then cut the next one.

## Timing

If the maintainers review one PR a week, the 15 items take about 4 months.
Two a week, about 2 months. The order puts the parts most useful to
upstream first, so stopping early still leaves something of value.

## Progress

- 2026-10-22: plan written. Next: draft the proposal (part 0) and file
  draft 14 (part 1).
- 2026-10-22: part 12 changed: the C runtime files are built, not
  committed (security). Committed only if reproducible and checked in CI.
- 2026-10-22: added where each part fits in the compiler pipeline.
