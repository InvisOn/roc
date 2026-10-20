# Learning the arm32 dev backend: the reference with holes

A faster route to the same learning as
`LEARNING.md` (the full rebuild by hand, kept as it was). Chosen 2026-10-01.

The goal is unchanged: how the Roc compiler works, how to get a feel for a
large codebase I did not write, and how to approach new codebases. The
implementation matters less than that.

## Handoff: where things stand (2026-10-18)

For a new conversation, on my second PC (two monitors). The order I chose:
these holes first, to learn the ropes and the workflow; then the clean
branch (`NICE_BRANCH.md`).

- **The reference** is `claude/arm32-dev-backend-reference` on the fork
  InvisOn/roc (PR InvisOn/roc#2; it was `32-bit-backend` and PR #1 until
  2026-10-17). It is the finished arm32 dev backend (about 26K lines,
  written by Claude). Claude keeps it merged with upstream by itself, in a
  separate long-running conversation on the first PC
  (`.git/verify-tools/UPSTREAM_SYNC.md` there); do not do that work here.
- **The holes branch** is `arm32-holes` on the fork, cut from the tag
  `arm32-reference` (also on the fork). Stage 1's holes are built (see
  "Progress"); later stages' holes are built when I reach them. It stays on
  its commit and does not follow upstream.
- **Getting it on this PC:**
  ```sh
  git clone git@github.com:InvisOn/roc.git roc && cd roc   # or fetch in an existing clone
  git fetch origin --tags
  git worktree add ../roc-by-hand arm32-holes
  git worktree add ../roc-notes notes    # this file and the other notes
  ```
  The notes live on the orphan branch `notes`. The first PC pushes them
  there; pull it before starting, and push my own changes to it (commit
  them there only, never on a code branch: the fork is public, and notes
  are never committed next to code).
- Heavy jobs (a full build, the eval tests, qemu) one at a time per
  machine, under a memory limit; the first PC's runs do not touch this one.
- `TODO.md`, `LEARNING.md` and this file live on the `notes` branch, never
  on a code branch.

**First thing in a new conversation:** read this file, check "Progress",
then start me on stage 0, or on stage 1 (its holes are ready).

## The idea

Typing 26,000 lines is not where the learning is. Most of the reference is
repetition: 165 encoder functions follow a handful of patterns; the driver
lowers dozens of operations in a few families. The learning is in the first
instance of each pattern and in the decisions.

So: a branch that is the reference with chosen functions removed. Each hole
is a stub that fails, with the tests that cover it left in place. I write
those functions; everything around a hole is real code I have to read to
fill it.

- I write roughly 2,000 to 3,000 lines instead of 26,000 (an estimate).
- The implementation always exists: the reference minus the holes I have not
  filled.
- The checks already exist: the assembler oracle, the eval corpus under
  qemu, the Pis.

## Four kinds of exercise

1. **Holes.** Fill a stubbed function until its tests pass. Then compare
   with the reference (`git diff arm32-reference -- <file>`) and ask why it
   differs.
2. **Review.** The reference splits into 8 PRs
   (`.git/verify-tools/roc/pr_split.roc`). For one PR: predict what it must
   contain, read its diff, write review comments and questions. Claude
   answers and says what I missed.
3. **Bug hunts.** Claude plants one defect on a scratch branch (a wrong
   offset, a swapped register, a missing relocation). I find it with the
   tests and tools.
4. **Explain it back.** I write the walkthrough for the stage. Claude checks
   it against the code. What I cannot explain is what to dig into.

## Ground rules

- **I fill the holes.** Claude builds the holes and bug-hunt branches from
  the reference (mechanical), points at what to read, gives hints in three
  steps (a nudge, then the idea, then the reference), reviews, and runs the
  tools. It does not show the reference's version of a hole unless I ask.
- **Predict, then look.** Before filling a hole or reading a PR, write down
  what I expect.
- **Keep my own map.** One page per stage in my own words.
- **One piece from a blank page.** Before touching stage 1's holes, write a
  tiny encoder of my own without looking at the reference (below). It is
  the one place I keep the experience of designing from nothing.

## How to read a codebase this size

1. **Follow one input through.** A `type=dev_object` snapshot in
   `test/snapshots/` shows SOURCE, MONO (after type-checking and
   specialization) and DEV OUTPUT for a tiny program.
2. **Find the seams before the details:** which module hands which data
   structure to which. Name five or six hand-offs first.
3. **Read tests before code.**
4. **Change something and watch what breaks.**
5. **Use history:** `git log -p --follow <file>` and the commit messages.
6. **Only then read a function closely,** and only those on the path of the
   input I am following.

## Stages

| # | Stage | Holes (I write) | Also | Check |
|---|---|---|---|---|
| 0 | Map of the compiler | none | my one-page map | I can say what each stage hands the next |
| 1 | A32 encoder | 13 functions in `arm32/Emit.zig` | blank-page mini encoder first; review PR 4 | the real assembler agrees byte for byte |
| 2 | ELF32 object writer | relocation and symbol writing in `write32` | bug hunt | `ci/elf32_reader.py`; LLD links it; runs under qemu |
| 3 | arm32 calling convention | argument placement in `layout/abi/arm32.zig` | explain it back | unit tests |
| 4 | The driver, reading | none | map of `LirCodeGen.zig`; review PR 3 | I can trace `x + 1` from LIR to bytes |
| 5 | arm32 code generation | one operation per family (below) | review PR 5; bug hunts | eval corpus under qemu, by family |
| 6 | Targets and linking | none, or one target-table entry | review PR 6 | `roc build --target=arm32musl` runs on a Pi |

Skipped (little to learn about the compiler): the CI lanes, the vendored
runtime objects, snapshot regeneration, arm32 as a host.

Holes for stages 2 to 6 are chosen when I get there; Claude proposes, I
agree. Stage 5's families, as a first cut: a 32-bit integer add; a 64-bit
add on 32-bit registers; a float operation; a call into a builtin; an i128
operation; one string or list operation; one SIMD operation.

### Stage 0: a map of the compiler (reading only, no build)

- `design.md`: "Core Principles", then skim from "Runtime Lowering Strategy"
  (line 9528): Monotype IR, Lambda Solved IR, Direct LIR Lowering, ARC
  Borrow Inference, Internal Calling Convention, Dev Backend Register
  Lifetimes, Build Outputs And The Targets Header. Skip the checker.
- `test/snapshots/dev_object_float_math.md`: SOURCE and MONO side by side.
- Answer in my map:
  1. The stages between source text and machine code, in order.
  2. What LIR is, and what is already decided when code reaches it (types?
     layouts? reference counting? calling convention?).
  3. What the dev backend and the LLVM backend both start from.
  4. Who links the object file, and what is linked with it.
- Then compare with `src/backend/dev/arm32/DESIGN.md`, "Where arm32 sits in
  the pipeline".

### Stage 1: the A32 encoder

**Blank page first (no reference, a few evenings).** In a scratch file,
write functions that return the four bytes of: `mov r0, r1`;
`add r0, r1, #4`; `ldr r0, [r1, #8]`; `bl <offset>`; `bx lr`. Source of
truth: the ARMv7-A manual. Check each against the real assembler
(`ci/arm32_encoding_oracle.py`; usage in `src/backend/dev/arm32/TOOLS.md`).
Predict first: how does a 32-bit constant get into a register when an
instruction has 12 bits for an immediate?

**Then the holes** in `src/backend/dev/arm32/Emit.zig` on `arm32-holes`
(165 public functions; these thirteen are the layouts the rest are built
on). Each stub panics with its number. Suggested order:

| Hole | Function | The concept |
|---|---|---|
| 1.1 | `ModImm.encode` | an 8-bit value rotated right by an even amount |
| 1.2 | `dataProc` | the one layout behind every `add`/`sub`/`and`/`cmp`/`mov` |
| 1.3a, 1.3b | `encodeMovwMovt`, `movRegImm32` | loading any 32-bit constant |
| 1.4 | `multiply` | `mul`, and a 64-bit product in two registers (`umull`) |
| 1.5 | `encodeBranch` | pc-relative offsets, and why 8 is subtracted |
| 1.6 | `loadStoreWordByte` | base plus offset addressing, the up/down bit |
| 1.7a, 1.7b | `push`, `pop` | register lists as bit masks |
| 1.8a, 1.8b | `vfpDataProc`, `vfpLoadStore` | the VFP encoding, how S and D register numbers split |
| 1.9 | `neonThreeSameFields` | one NEON family, to see how it differs |

How to work a hole:

```sh
cd ../roc-by-hand
git show arm32-holes --stat         # what was removed
zig build run-test-zig-module-backend --summary all 2>&1 | grep -E "HOLE|pass,"
```

- With every hole open: 669 tests pass, 2 skip, 198 crash, each crash
  naming its hole (`panic: HOLE 1.2 dataProc: ...`). Fill a hole and its
  crashes go. Done when it reads 867 pass, 2 skip. (Counts from
  2026-10-18; on 2026-10-02 they were 710/199 of 911.)
- Each stub discards its unused parameters (`_ = rd;`). Delete a discard
  when I start using that parameter, or Zig reports a pointless discard.
- The bit-layout comments above the holes were removed; the ARMv7-A manual
  is the source. Look up the instruction by name (for 1.2: "ADD (register,
  ARM)" and "ADD (immediate, ARM)").
- 1.1 is called at compile time across the backend, so a slow search over
  all 4096 encodings stands in there to keep the branch compiling. It
  still panics at run time until I write the direct version.
- The first build of the worktree takes a while and its cache grows; later
  builds are quick.
- After a hole: `git diff arm32-reference -- src/backend/dev/arm32/Emit.zig`
  shows where mine differs from the reference. Ask why.

**Review:** PR 4 (the encoder and ELF32 writer) from the split.
**Explain it back:** why the encoder is checked against the assembler
rather than by tests written by hand (walkthroughs note, "an encoder that
cannot lie").

## Setup (done 2026-10-02)

- Tag `arm32-reference` is on the verified reference tip `ee5664f6a5`
  (upstream `220b9b7941`, 2026-10-18). Until then it was `83be07cd49`
  (`22af835e08` before the 2026-10-17 history rewrite).
- Branch `arm32-holes` starts at that tag, in the worktree `../roc-by-hand`.
  It stays on that commit; it does not need to follow upstream. Both are
  pushed to the fork (2026-10-18).
- One commit per stage that makes the holes, so
  `git show <that commit>` lists exactly what I have to write.

## Progress

- 2026-10-01: plan written.
- 2026-10-02: stage 1 holes built: commit `381ecf805e` on `arm32-holes`,
  thirteen stubs in `arm32/Emit.zig`. Checked: the branch compiles, and the
  backend tests report 710 passed, 199 crashed, every crash naming a hole,
  all thirteen holes hit. Not started by me yet.
- 2026-10-18: the stage 1 commit is `dd330ea86a` (it was `381ecf805e`;
  recreated on the rewritten reference without the Claude trailers, same
  files). Branch and tag pushed to the fork; I start on the second PC.
- 2026-10-18: rebuilt on the current reference `ee5664f6a5` before I
  started: stage 1 commit `9e314c109a`. The same thirteen holes; three stubs
  sat where Zig renamed `@intFromEnum` to `@backingInt`. Checked: compiles;
  669 passed, 2 skipped, 198 crashed, every crash naming a hole, all
  thirteen hit.

## Where the reference explains itself

- `projects/big/arm32-dev-backend-walkthroughs.md`: phase 1, with questions
- `src/backend/dev/arm32/DESIGN.md`: decisions and lessons
- `src/backend/dev/arm32/GUIDE.md`, `TOOLS.md`: what works, how to test it
- `projects/big/arm32-dev-backend.md`: the original plan
- `projects/big/arm32-dev-backend-existing-code-changes.md`: every change to
  upstream code, with the reason
- `.git/verify-tools/roc/README.md`: the checking tools
