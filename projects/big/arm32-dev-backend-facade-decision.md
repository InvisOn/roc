# ARM32 Dev Backend: ISA-Specific Code in the Shared Driver

A decision the arm32 work still owes: the plan promised a shared driver
(`src/backend/dev/LirCodeGen.zig`) without ISA mnemonics or register names,
and the work did not deliver it. This note lays out what happened, what the
promise was for, and the options, so the owner can decide, ideally with the
maintainers. The open entry in `arm32-dev-backend-issues.md` ("The driver still
names mnemonics and register literals") points here.

## What the plan promised

A1 and the plan's correctness ideal: `rg 'codegen\.emit\.'
src/backend/dev/LirCodeGen.zig` and a search for register names
(`.RAX`, `.X0`, `.IP0`, ...) both return nothing. Every instruction the driver
needs would come from a per-ISA `CodeGen` method with a shared signature
(the "facade"), and every architecture decision would be an exhaustive switch
or a compile-time refusal.

The promise served three purposes:

1. **Safety:** a lowering with no arm32 path must fail to compile, not fall
   through to x86_64 or aarch64 code.
2. **Separation:** each ISA's instruction selection lives in its own
   directory, so the driver reads as ISA-neutral lowering.
3. **Extensibility:** a fourth ISA would be a new directory, not a new arm in
   every switch.

## What happened

- A1 moved 55 ISA-neutral helpers (loads and stores by width, stack
  addressing, compares, register arithmetic) into the facade, and deferred
  the lowering *strategies* (i128 and Dec arithmetic, 64-bit values on a
  32-bit target, SIMD kernels, checked multiplication, entry wrappers) "to A2
  and the NEON batch", because their x86_64/aarch64 shapes (one 64-bit
  register per value) did not fit arm32 (register pairs and memory-resident
  i128, NEON).
- A2 and the NEON batch did not add those signatures. J1 gave the strategy
  sites `.arm32 =>` arms with raw emitter calls instead.
- So purpose 1 holds: every decision is an exhaustive `switch (isa)` or a
  `binaryIs` test that refuses to compile for arm32. Purposes 2 and 3 do not.

## Measurements (at the tip, 2026-09-29, production code only)

| Measure | Value |
|---|---|
| Raw emitter calls in the driver | 592 (587 before the arm32 work; 502 after A1; 611 after J1) |
| … instruction defined only for x86_64 | 180 |
| … only for aarch64 | 145 |
| … only for arm32 | 97 |
| … name shared by several ISAs | 135 |
| … not an instruction (buffer access and the like) | 37 |
| `switch (isa)` sites, each with an `.arm32` arm | 43 |
| `binaryIs` two-way tests | 32 |
| Lines naming an ISA register | 142 |
| arm32-only functions in the driver (found by their guards) | at least 4, 346 lines: the `Wide64` family and `emitI128MulWrapWords` |
| Where raw calls cluster | SIMD 136, i128/Dec 79, float 58, `Wide64` 50, other 195 |
| The arm32 work's change to the driver | +5672 / −3394 lines |
| Per-ISA `CodeGen` facades | x86_64 125, aarch64 144, arm32 123 public functions |

**The key fact:** about 16% of the ISA-specific code in the driver is
arm32's. The rest is upstream's existing x86_64 and aarch64 code, which was
there before the arm32 work. Emptying the driver of mnemonics is mostly a
refactor of upstream's code, not of the arm32 work.

## Options

### (a) The full facade refactor

Define facade signatures for every strategy family and move all ISA arms,
x86_64 and aarch64 included, into the per-ISA `CodeGen`s.

- **For:**
  - It delivers the plan as written: a mnemonic-free driver.
  - A future ISA (RISC-V, say) becomes a new directory.
  - It is safe to do: the byte-identity oracles (the eval hash file and the
    `dev_object` snapshots) must stay unchanged, so any behaviour change in
    the move is caught mechanically.
- **Against:**
  - It is large: ~560 call sites, several thousand lines moved, and
    signatures to design for families whose shapes genuinely differ across
    ISAs (i128 in two registers versus in memory).
  - It rewrites upstream's own code in the most active file of the backend.
    Upstream changed this file in 17 conflicting places in the 465 commits
    of the first trial merge; a wholesale move would conflict with nearly
    every change upstream makes while it is under review.
  - A huge diff is hard to review, and it is not what the arm32 feature
    needs to work.
  - Facade signatures designed by the arm32 work alone may not be what the
    maintainers want for their own ISAs.

### (b) Amend the plan: per-ISA arms in exhaustive switches are the design

Keep the code as it is, and record in DESIGN.md that the driver may hold
per-ISA arms inside exhaustive switches and `binaryIs` tests, with the reason
(the strategies' shapes differ by ISA).

- **For:**
  - No code changes; nothing to re-verify.
  - It matches how upstream's driver is already written for x86_64 and
    aarch64, so reviewers see a familiar pattern.
  - The smallest diff in the most conflict-prone file.
  - The safety property (purpose 1) already holds.
- **Against:**
  - The driver keeps growing with every ISA: each new target adds an arm to
    43 switches and new functions.
  - arm32's code is spread through a ~30,000-line file instead of living
    in its own directory, which makes it harder to review as a unit.
  - The plan's promise is dropped, not delivered; the amendment has to be
    explained.

### (c) Middle: move only arm32's code out of the driver

Leave upstream's x86_64/aarch64 code alone. Move the arm32-only lowering (the
97 arm32-only calls, the arm32-only functions, the NEON kernels, the
word-by-word i128 lowering) into an arm32 module (for example
`src/backend/dev/arm32/Lowering.zig`), and make each `.arm32 =>` arm a single
call into it.

- **For:**
  - The arm32 work adds almost no mnemonics to the shared driver: its
    footprint there shrinks to 43 one-line arms plus the call plumbing.
  - arm32 can be reviewed as one directory.
  - Upstream's code is untouched, so conflicts with upstream stay where
    they are now.
  - It is verifiable the same way: the 64-bit oracles unchanged, and the
    arm32 suites (qemu, Raspberry Pis) pass.
- **Against:**
  - The moved code needs the driver's internals (register allocation,
    stack slots, value locations), so the arm32 module takes the driver
    (`*Self`, generic over the target) as an argument. That couples it to
    the driver's internals and blurs the layering the facade was meant to
    give.
  - The driver still has three-way switches (purpose 3 stays unmet).
  - A medium-sized change (roughly the 346+ lines of arm32-only functions
    plus the NEON and word-lowering kernels) to verify again, after the
    verification already done.

### (d) Land as (b) now; propose (a) upstream-wide later

Take (b) for the arm32 pull requests, and propose the full facade as its own
project for all ISAs once arm32 has landed, designed with the maintainers.

- **For:** keeps the arm32 work small and landable; puts the large refactor
  where it belongs (it is mostly upstream's code), with the maintainers
  choosing the signatures.
- **Against:** the driver stays mixed until someone does the follow-up; the
  follow-up may never happen.

## How to choose

| Criterion | (a) full | (b) amend | (c) arm32 out | (d) (b) then (a) |
|---|---|---|---|---|
| Delivers the plan's promise | yes | no | partly | later |
| Diff in the hottest file | very large | none | medium | none now |
| Merge-conflict exposure while in review | high | low | medium | low |
| Touches upstream's own code | yes | no | no | later, with them |
| arm32 reviewable as a unit | yes | no | yes | no |
| Re-verification needed | large | none | medium | none now |
| Effort | weeks | a DESIGN.md amendment | days | an amendment now |

The deciding factor is what the maintainers want, which only they can say:
(a) is the cleanest end state but mostly edits their code; (b) and (d) are
the least disruptive; (c) is the best arm32-only compromise.

**Recommendation:** raise it with the maintainers as part of proposing the
arm32 work, and prepare (d): write the DESIGN.md amendment for (b) now, so
the arm32 pull requests explain the choice rather than silently missing the
criterion, and offer (c) if they want arm32's code isolated before it lands.

## Reproducing the numbers

The measurements come from two read-only scripts in `.git/verify-tools/`
(`facade_stats.py`, `facade_isa_split.py`) that parse `LirCodeGen.zig` and
the three `Emit.zig` files at `HEAD`.
