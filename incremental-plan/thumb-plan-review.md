# Review: Thumb (T32) in the Incremental Plan

Written 2026-10-27. A skeptical second opinion on option A2 (Thumb as parts
10 and 11, after the A32 parts), as of notes commit `3b497a0791`. Checked
against the reference snapshot `e0fa273ebf` and upstream `26436de489`.
Nothing was run on the ARM devices.

## Summary

Recommendation: take Thumb out of the committed plan. A2's "parts 4 to 9
taken from the reference, designed for Thumb" contradicts the reference
code. How a target selects Thumb is deferred to part 11, but it shapes part
1's `Isa` enum now. And putting Thumb at parts 10 and 11 delays the first
CI-tested arm32 program by two large PRs.

## Findings, most severe first

### 1. "Taken from the reference" and "encoding choices out of the shared code" can't both be true (high)

- **Where:** `README.md:94-95` and `:270-272`.
- **What:** the reference's shared driver calls A32-only encoder features
  directly. It has 29 uses of `arm32.ModImm` (A32's rotated-immediate type),
  for example `e0fa273ebf:src/backend/dev/LirCodeGen.zig:8746` and
  `:10055`. It also has predicated moves (`movRegRegCond` at `:1966`) and
  94 `isa == .arm32` / `.arm32 =>` sites.
- In the reference's `arm32/CodeGen.zig`, patches write raw little-endian
  `u32` words (`:355-361`) and hard-code A32's PC bias of +8 (`:343`, the
  "+16"). Thumb-2 stores 32-bit instructions as two halfwords, high half
  first, and its PC bias is +4.
- Upstream's own driver also calls encoders directly, 449 times
  (`26436de489:src/backend/dev/LirCodeGen.zig`). So moving encoding
  choices out of the shared code would go against upstream's style, which
  `README.md:40` says wins.
- **Why it matters:** either parts 6, 8 and 9 are rewritten (they are then
  no longer the reference's tested code), or the A32 assumptions land and
  part 11 rewrites them (the rework A2 was meant to avoid).
- **Change:** name the real boundary. Only the arm32 `CodeGen` may write
  or patch instruction bytes, or know the PC bias and branch ranges. The
  driver keeps calling the encoder, as upstream does. List the `ModImm`
  and predicated sites as the known part 11 cost.

### 2. How a target selects Thumb is deferred to part 11, but it decides the shape of parts 1 and 4 to 9 (high)

- **Where:** `README.md:303-304`. Part 1's `src/backend/dev/isa.zig` (on
  `dispatch/isa`) is the affected enum.
- **What:** if Thumb is a new `Isa` member, all 94 arm32 sites need an
  answer, and the exhaustive switches force that. If it is a mode inside
  `.arm32`, the encoder type, the cache key (`PackFile.zig` and
  `ProcArtifact.zig` store veneer offsets) and the relocation patchers all
  need a mode parameter.
- Upstream already has a mechanism worth considering: CPU levels and
  "baseline twin" targets (`26436de489:src/target/mod.zig:584`, `:647`).
  Zig also has a separate `.thumb` CPU arch, which upstream classifies as
  "other" (`:67`).
- **Change:** decide it in part 4's RFC at the latest. Ideally record it
  before #9 goes upstream, because #9 introduces `Isa`.

### 3. The order delays the first working, CI-guarded arm32 program (high)

- **Where:** `README.md:76-80` and
  `rfcs/part-01-dispatch-isa/step-6-word-size.md:221-225`.
- **What:** part 6 lifts the 8-byte assert. The tests guarding it only run
  in CI from part 12, so Thumb adds two big PRs (an estimated 4,500 to
  7,600 lines) to that gap.
- The reference's eval-corpus lane runs a compiler built for arm32 under
  qemu, and that compiler runs the generated code in its own process
  (`e0fa273ebf:src/backend/dev/arm32/TOOLS.md:153-161`). That is part 13's
  host path. So part 12's "eval corpus as A32 and as Thumb" depends on
  part 13.
- `README.md:272` says programs build "from here" (parts 6 and 7).
  Upstream already has the `arm32musl` target
  (`26436de489:src/target/mod.zig:465`), but linking needs part 12's
  runtime files and platform entries.
- If the maintainers balk at Thumb, parts 12 to 14 are stuck behind it.

### 4. Thumb gives little to a Cortex-A dev backend (high, judgement)

- **Where:** `README.md:100-102` and `HANDOFF.md:253-263`.
- **What:** the plan's case is smaller code and Cortex-M.
  - Code size is not what a dev backend is for. `--opt=dev` is for fast
    compiles, and release builds go through LLVM, which can already emit
    Thumb.
  - Every ARMv7-A core, and every ARMv8-A core that runs 32-bit code, runs
    A32.
  - For Cortex-M, the HANDOFF itself lists the bigger work: no OS, no JIT
    memory, soft-float, no NEON, and ARMv6-M's subset. Thumb-2 alone
    doesn't get there.
- Upstream would carry a second encoder, a second oracle and a doubled CI
  lane for a mode with no users.
- `rfcs/part-01-dispatch-isa/step-8-pr9-description.md:18` already
  promises upstream "The backend will generate both". The plan table at
  `:116-118` shows parts 10 to 12 with Thumb.

### 5. Part 11 is missing work that the reference shows is needed (medium)

- **Branch islands:** the driver says "Only aarch64's short conditional
  branches need islands"
  (`e0fa273ebf:src/backend/dev/LirCodeGen.zig:22626`). Thumb conditional
  branches reach only ±1 MB (32-bit form) or ±256 bytes (16-bit form), so
  arm32 needs islands too. That is shared-driver work the pipeline map
  (`README.md:120-123`) doesn't show for 11.
- **Running code in memory (part 13):** `Relocation.zig:236-256` patches
  only A32 `BL` and rejects targets with bit 0 set. With no linker in that
  path, nothing adds interworking veneers. `README.md:97-98`'s "linker
  veneers" claim covers only object files.
  - Thumb would need its own `BL`/`BLX` patching.
  - The `HostSplice.zig:459-464` stub is A32. It interworks on the way
    out, but Thumb callers must reach it with `BLX`.
  - Entry pointers into Thumb code need bit 0 set.
- **Object file:** the writer emits one `$a` mapping symbol for all of
  `.text` (`object/elf.zig:761-763`). Mixed or Thumb code needs `$t` (and
  `$d` for literal words). `.ARM.attributes` needs updating.
- **DWARF:** the reference emits no `.debug_frame` (`Dwarf.zig:3`), so
  unwinding isn't a Thumb problem yet. `DW_AT_low_pc` versus the symbol's
  bit 0 is.
- **IT-block rules:** at most four instructions, and a branch only as the
  last one. Unverified recollection: ARMv8-A deprecates IT blocks holding
  more than one 16-bit instruction, and the OS can make them trap. That
  matters on ARMv8 chips running 32-bit code (such as the Pi 3); check
  before relying on it.
- **"Literal ranges"** (`README.md:298`) doesn't apply: the reference uses
  no literal pools; it builds constants with MOVW/MOVT, which Thumb-2 also
  has.

### 6. Thumb testing is weaker than A32 testing, and its CI cost isn't stated (medium)

- The oracle checks encodings, not which encoding is chosen or how IT
  blocks are grouped. `README.md:390-392` says parts 4 and 10 need no
  ultrareview because "the oracle checks every encoding". It only checks
  the cases listed in the `.s` file (373 lines for A32).
- Part 12 adds a second qemu lane with no stated time. That breaks the
  plan's own rule at `README.md:43-45`. The reference's qemu lane time
  isn't recorded anywhere found.
- Neither the device runs nor the step 6 coverage table include a Thumb
  pass.

### 7. Leftovers from the renumbering (low)

- These docs use the old 0 to 12 numbers without saying so:
  - `step-4-abs64.md:22` ("part 11 `arm32/host`", now 13)
  - `step-3-glibc-stub.md:17` ("part 10 (`arm32/targets`)", now 12)
  - `dispatch-isa-rfc.md:277` ("part 11", now 13)
  - `step-7-checks-plan.md:157-198` ("part 11", now 13)
- `README.md:441`'s blanket note covers them, but `step-5` and
  `step-7-checks` got inline notes. Pick one way.
- Pipeline map (`README.md:120-128`): 11 is missing from the shared driver
  and from code in memory.
- Timing (`README.md:400`): "15 items, about 4 months" is the same as for
  13 items. Parts 8 and 9 (and perhaps 2 and 3) are "several PRs" each,
  so the real count is higher.
- `HANDOFF.md:239` lists "Thumb-2" as a fix for the Debug runner link
  failure. That code is LLVM's output for the compiler itself, so parts 10
  and 11 don't help. Thumb `BL` also reaches less far (±16 MB against
  ±32 MB).

### 8. Proposal and upstream order (low)

- The part 0 text (`README.md:167-178`) doesn't mention Thumb.
  `README.md:180` says "Nothing else starts until they answer", but nothing
  in the notes records that the proposal was sent, while #9 is nearly
  ready.

## Sizes

- Part 4 checks out: `Emit.zig` 1,975 + `Registers.zig` 254 + oracle
  `.py` 247 + `.s` 373 + generated tests 996 = 3,845 lines.
- T32 at 3,000 to 4,500 is plausible (a guess). The low end only holds if
  the encoder always emits 32-bit forms.
- Part 11 at 1,500 to 3,100 looks low given finding 5 (a guess).

## Options

### A1, Thumb in every part

- **Cost:** part 4 roughly doubles, to about 7,000 lines or more, far over
  the 300 to 2,000 lines a PR should have (`README.md:22`). Half of the
  code has no reference. arm32 reaches upstream much later.
- **Benefit:** the interface is proven by two encoders from the start, so
  no rework.

### A2 as written

- **Cost:** findings 1 to 3. The plan is internally contradictory, and
  Thumb blocks targets, CI and the host path.
- **Benefit:** Thumb lands eventually, and the A32 parts stay close to the
  reference.

### A2 reordered: Thumb last and optional

- **Order:** 4 to 9, then targets and CI, host, docs and the required
  lane, then Thumb.
- **Cost:** one more renumbering, and Thumb comes later.
- **Benefit:** a working, CI-guarded arm32 program arrives two big PRs
  sooner. Thumb can be dropped without blocking anything.

### A32 only; Thumb as a separate later proposal, with the Cortex-M track

- **Cost:** no Thumb from this plan. The Cortex-M track starts without a
  T32 encoder.
- **Benefit:** the smallest ask to upstream, no promise in #9, and Thumb
  gets argued where it is needed (Cortex-M).

## Recommendation

A32 only, with Thumb as a later proposal. Keep three cheap, local hooks,
since they are good design anyway:

- Record the selection decision in part 4's RFC (finding 2).
- Keep byte patching, PC bias and branch ranges inside the arm32
  `CodeGen`.
- Don't move encoding out of the driver.

Before #9 is posted, remove the Thumb sentence and rows from
`step-8-pr9-description.md:18` and `:116-118`.

If Thumb stays, take the reordered A2 instead, decide finding 2 now, and
add finding 5's items to part 11 (and to part 13 for running in memory).
