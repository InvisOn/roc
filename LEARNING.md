# Rebuilding the arm32 dev backend by hand

Personal plan; not committed. The goal is learning: how the Roc compiler
works, and how to find my way in a large codebase I did not write. The
finished branch `32-bit-backend` is the reference, not the thing to copy.

## Handoff: where things stand (2026-10-01)

For a new conversation. Everything below this section is the plan itself.

**What exists**

- Repo `~/repos/roc_32bit`, branch `32-bit-backend` at `cd28ff621a`,
  pushed; PR InvisOn/roc#1 against `arm32/base`. This is the finished arm32
  dev backend, written by Claude: about 26K lines over 145 commits. It is now
  the **reference**. Claude keeps it in step with upstream `main` (merge,
  fix, verify); otherwise it changes only to fix a defect in it.
- It is merged with upstream `main` at `00cab95af8` and verified: minici
  79/79, the arm32 eval corpus 2381/2381 under qemu, `test/fx` 122/122 under
  qemu and on the Pi 5, the int app on the Pi 3. Every failure in the last
  full CI run is traced to upstream, a runner, or macOS (verification note).
- PR minici run 36824390785 on `cd28ff621a` was still running when this was
  written (12 jobs passed, 2 to go, none failed). Check it once.
- `TODO.md` and `LEARNING.md` (repo root) are personal and never committed.

**Not done yet**

- The setup below (the `arm32-reference` tag and the `roc-by-hand` worktree)
  has not been run. Nothing of the rebuild exists.
- Stage 0 has not started.

**Open decisions (mine)**

- Upstream PRs (part 6 in `TODO.md`): hold all of them during the rebuild, or
  still send PR 1's independent fixes.
- Checking tools: the plan assumes I use the reference's tools (assembler
  oracle, ELF reader, hash oracle) as they are and rewrite only the backend.
- Older ones, unchanged: the driver facade, the interpreter trampoline fix,
  fuzzing, filing the aarch64 LLVM range abort upstream (all in `TODO.md`).

**How Claude works with me here**

- Tutor and reviewer, not author: see "Ground rules". Running tools, builds
  and tests, and checking my work, are Claude's job.
- Only one memory-heavy build or test at a time, under a memory cap
  (`systemd-run --user --scope -p MemoryMax=24G`); the machine kills
  overlapping ones.
- Set `XDG_CACHE_HOME=$PWD/.git/verify-tools/xdg-cache` for `zig build`, or
  it wipes `~/.cache/roc`.
- Fix only what our branch introduced; upstream bugs are traced and
  recorded, not fixed.
- Test machines: Pi 5 `<user>@<aarch64-device>` (aarch64), Pi 3 `<user>@<arm32-device>`
  (armv7). Tools and their README: `.git/verify-tools/roc/`.

**First thing to do in the new conversation**

1. Run the setup.
2. Stage 0: I read, then write my one-page map; Claude asks the stage 0
   questions and checks my answers against the code.

## Ground rules

- **I write the code.** Claude points at what to read, asks what I expect
  before I look, gives hints in three steps (a nudge, then the idea, then the
  reference commit), reviews what I wrote, and runs the tools.
- **Predict, then look.** Before opening the reference for a piece, write
  down how I think it works. The gap between the guess and the reference is
  where the learning is.
- **One stage at a time, each with a check I can run.** A stage is done when
  its check passes and I can explain it without notes.
- **Keep my own map.** One page per stage in my own words (`notes/` or
  wherever). Reading someone else's summary does not build the picture;
  writing one does.

## Setup (once)

```sh
git tag arm32-reference 32-bit-backend          # a stable name for the reference
git worktree add ../roc-by-hand -b arm32-by-hand 00cab95af8   # upstream, no arm32
```

Two directories side by side: `roc_32bit` (reference, read-only from now on)
and `roc-by-hand` (mine). A worktree's build cache grows to tens of GB; clear
`.zig-cache` when the disk fills.

## How to read a codebase this size

The driver alone is 31,000 lines; nobody reads that top to bottom.

1. **Follow one input through.** Take the smallest program that does
   something and watch it at every stage. Here that is cheap: a
   `type=dev_object` snapshot in `test/snapshots/` shows SOURCE, then MONO
   (the program after type-checking and specialization), then DEV OUTPUT.
2. **Find the seams before the details.** Which module hands what data
   structure to which? Name the five or six hand-offs; ignore everything
   inside them at first.
3. **Read tests before code.** A test says what a function is for in ten
   lines.
4. **Change something and watch what breaks.** Make an encoder emit a wrong
   byte, delete a case from a switch. The failures show who depends on what.
5. **Use history.** `git log -p --follow` on a file and the commit messages
   say why code looks the way it does.
6. **Only then read a function closely,** and only the ones on the path of
   the input I am following.

## Stages

Order is for learning, not the order the reference was built in. The
reference started by refactoring the 31,000-line driver; that is the worst
place to begin. This starts with the small, closed pieces at the bottom and
works up.

| # | Stage | I write | Size in the reference | Check |
|---|---|---|---|---|
| 0 | Map of the compiler | nothing; my own one-page map | - | I can say what each stage hands the next |
| 1 | A32 instruction encoder | `arm32/Registers.zig`, `arm32/Emit.zig` | about 1,500 code lines, 163 functions | the real assembler agrees, byte for byte |
| 2 | ELF32 object writer | `write32` in `object/elf.zig` | about 300 lines | `ci/elf32_reader.py`; LLD links it; it runs under qemu |
| 3 | arm32 calling convention | `layout/abi/arm32.zig` | about 300 lines | its unit tests; a hand-built call into C |
| 4 | Read the driver | nothing; a map of `LirCodeGen.zig` | - | I can trace `x + 1` from LIR to bytes on x86_64 |
| 5 | Driver prep: word size and ISA made explicit | changes across `LirCodeGen.zig` | +4,200 / -3,500 lines | x86_64 and aarch64 output unchanged, byte for byte |
| 6 | arm32 code generation | `arm32/CodeGen.zig`, arm32 paths in the driver | about 6,000 lines | eval corpus under qemu, one family at a time |
| 7 | Targets, linking, platforms | target tables, runtime objects, CLI | about 1,100 lines | `roc build --target=arm32musl` runs on a Pi |
| 8 | arm32 as a host | runner and interpreter fixes | about 250 lines | the test runners themselves run on arm32 |

Stages 1 to 3 need nothing from the rest of the compiler: they are closed
problems with an outside source of truth (the ARM manual, the ELF spec, the
AAPCS). They are also where I learn Zig and the house style. Stages 5 and 6
are the bulk and the hard part.

Not yet measured: how small the first working slice of stages 5 and 6 can be
(the driver is one generic type per ISA, so arm32 may not compile at all
until most of stage 5 is done). Measure before starting stage 5.

### Stage 0: a map of the compiler (read only)

- Read `design.md`: "Core Principles", then skim from "Runtime Lowering
  Strategy" (line 9528) on: Monotype IR, Lambda Solved IR, Direct LIR
  Lowering, ARC Borrow Inference, Internal Calling Convention, Dev Backend
  Register Lifetimes, Build Outputs And The Targets Header. Skip the checker
  sections for now.
- Open `test/snapshots/dev_object_float_math.md`. Read SOURCE and MONO side
  by side.
- Questions to answer in my map:
  1. What are the stages between source text and machine code, in order?
  2. What is LIR, and what has already been decided by the time code reaches
     it (types? layouts? reference counting? calling convention?)
  3. The dev backend and the LLVM backend start from the same thing. What?
  4. Who links the object file, and what else is linked with it?
- Then compare with the reference's `src/backend/dev/arm32/DESIGN.md`,
  "Where arm32 sits in the pipeline".

### Stage 1: the A32 encoder

- Before reading the reference: read `src/backend/dev/aarch64/Emit.zig` and
  `Registers.zig` on upstream. What is an `Emit`? What does it own? What do
  callers pass in?
- Source of truth: the ARMv7-A manual's instruction encodings. Start with
  five: `mov` register, `add` immediate, `ldr`/`str` with an offset, `bl`,
  `bx lr`.
- Check: the reference's `ci/arm32_encoding_oracle.py` assembles each
  instruction with the real assembler and compares bytes (described in the
  reference's `src/backend/dev/arm32/TOOLS.md`). Use the tool as is; writing
  it is not the point.
- Things to predict first: how is a 32-bit constant loaded when an
  instruction has room for only 12 bits of immediate? What is a "modified
  immediate"? What does the condition field do?
- Then compare with the reference: walkthroughs note, "Track B, first batch".

Later stages get this level of detail when I reach them.

## Where the reference explains itself

- `projects/big/arm32-dev-backend-walkthroughs.md`: phase 1, with questions
- `src/backend/dev/arm32/DESIGN.md`: decisions and lessons
- `src/backend/dev/arm32/GUIDE.md`, `TOOLS.md`: what works, how to test it
- `projects/big/arm32-dev-backend.md`: the original plan (units A0 to J4)
- `projects/big/arm32-dev-backend-existing-code-changes.md`: every change to
  upstream code, with the reason
- `.git/verify-tools/roc/README.md`: the checking tools
