# Part 5: ELF32 objects, ARM relocations and 32-bit DWARF

- **Status:** Accepted
- **Scope:** Branch
- **Plan row:** 5, ELF32 objects, ARM relocations, 32-bit DWARF
- **Branch:** `arm32/elf32-objects` (not cut yet)
- **Fork PR:** not yet
- **Parent:** none
- **Base:** `arm32/encoder` (`dbc497d6a8`), on `isa-register-seams`
  (`f72be15da9`), on `isa-word-size` (upstream PR 12983), on upstream
  `22e3718d45`. Opened upstream only after the parts below it merge.
- **Head:** none yet

## Abstract

Part 5 teaches the dev backend's object writer to write 32-bit ARM
relocatable objects: ELF32 headers, sections and symbols, `.ARM.attributes`,
the `$a` mapping symbol, `SHT_REL` relocations for `R_ARM_CALL`,
`R_ARM_ABS32`, `R_ARM_MOVW_PREL_NC` and `R_ARM_MOVT_PREL`, and DWARF with
four-byte addresses. Six decisions: where in-memory arm32 relocation
patching goes (D1: in part 5, with the arm32 relocation kinds; upstream's
explicit relocation kinds make an `Isa` argument unnecessary); how the link smoke test is written now that part 4
brought no ELF reader (D2, a Zig build step that links but does not run);
whether ELF32 is a second writer or a class parameter of the one writer
(D3, one writer); what `.ARM.attributes` says (D4, a fixed block matching
part 4's CPU floor); REL or RELA (D5, REL); and how the writer learns the
pointer width (D6, from the target). 64-bit output must not change: the
relative oracle runs on each commit, and a byte comparison of x86_64 and
aarch64 objects before and after guards D3.

## Problem

Part 6's code generator produces A32 code with relocations, and part 8
links it into programs. Between them, the code has to become an object
file a linker accepts. Today's writer (`src/backend/dev/object/elf.zig`)
writes only ELF64 for x86_64 and aarch64: `Elf64_*` structures, `SHT_RELA`,
and machine numbers 62 and 183. `Relocation.zig` has no arm32 kinds, and
`Dwarf.zig` writes every address as eight bytes.

Without part 5, part 6 has nowhere to put its output, and the first time
the ELF32 layout, the relocation types or the REL addends are checked is
when part 8 links a whole program, where a wrong field shows up as a
linker error or a crash with many possible causes.

### Breakages you can run

Nothing reaches the object writer for arm32 yet: `isaOfOrNull(.arm32musl)`
returns null, so a build stops in the dev backend before any object is
written (part 4's RFC shows the command and output). The writer's own
gap shows in its type:

    src/backend/dev/object/elf.zig:128
    pub const Architecture = enum { x86_64, aarch64, ... }

What part 5 makes runnable, on the branch once the commits exist:

    cd .workspaces/arm32-elf32-objects
    zig build test
    zig build run-check-arm32-link-smoke

The first runs the writer's unit tests, which read the ELF32 output back
with `std.elf`; the second builds a small arm32 object with part 4's
encoder and this writer and links it with `zig cc` (D2).

## What this enables

- **Follows directly:** part 6 writes its code and relocations through
  this writer; part 8 links them into programs.
- **Follows directly:** debuggers and `addr2line` read 32-bit line
  tables, because DWARF addresses match the target width.
- **Possible later, not planned:** other 32-bit ELF targets (for example
  a 32-bit x86 dev backend) reuse the class parameter (D3).

## Background

- **ELF32 versus ELF64:** the same sections and meaning, with smaller
  header, section, symbol and relocation records (`Elf32_Ehdr` is 52 bytes,
  `Elf64_Ehdr` 64) and a different field order in symbols.
- **REL versus RELA:** a RELA record carries its addend; a REL record
  does not, and the addend is read from the bytes being relocated. The ARM
  ELF ABI (AAELF32) uses REL, and part 4's encoder already writes REL
  addends: `bl(0)` encodes −8, and `pcRelAddress` puts −16 and −12 in its
  `movw` and `movt` (part 4's RFC, commit 5).
- **`.ARM.attributes`:** a section that states the CPU architecture, FPU
  and calling-convention details. Linkers compare it between objects and
  reject or warn on a hard-float/soft-float mix, and LLD picks the kind of
  stub it inserts for long branches and ARM-to-Thumb calls from its CPU
  architecture tag (v7 allows `blx` and `movw`/`movt` stubs). Debian-style
  armhf C libraries are Thumb-2, so a `bl puts` from our A32 code crosses
  into Thumb.
- **Mapping symbols:** `$a` marks the start of A32 code in a section (and
  `$d` data, `$t` Thumb). AAELF32 requires them; disassemblers use them.
- **Reference:** `claude/arm32-dev-backend-reference` at `d0846f6eb6`.
  Files and sizes against its base `73df27a5bb`:

  | File | Lines (+/−) |
  |---|---|
  | `object/elf.zig` | +554 |
  | `Relocation.zig` | +175 / −20 |
  | `Dwarf.zig` | +59 / −14 |
  | `arm32_link_smoke.zig` | +100 |
  | `ci/arm32_link_smoke.py` | +137 |
  | `ci/elf32_reader.py` | +248 (part 4's D4, now dropped) |

- **The reference's smoke test:** builds an object whose function uses all
  four relocation types and calls `puts`, checks its header and attributes
  with `elf32_reader.py`, links it with `zig cc` and a C `main`, and runs it
  under `qemu-arm-static -cpu cortex-a9` or on a device over SSH.
- **Part 4's D4 outcome:** the oracle tool is Zig and reads its objects
  itself; no Python reader exists, and minici's Windows lane has no
  `python3`.

## Discussion

- **Acceptable upstream:** judged as if a maintainer wrote it. One writer
  rather than two copies (D3); every later reference fix included
  (`d0846f6eb6` changed `elf.zig` and `macho.zig` after the snapshot).
- **AGENTS.md:** no heuristics. The reference's base patched by looking
  at the bytes, and the reference added an `isa` argument to fix that.
  Upstream has since fixed it another way (`69b0808e11`, in our base):
  every relocation carries an explicit kind set by the code generator, and
  the bytes are only debug asserts. Part 5's arm32 kinds follow that
  pattern (D1).
- **Output unchanged:** x86_64 and aarch64 objects must be byte-identical.
  The relative oracle covers program behaviour; D3's byte comparison
  covers the object bytes themselves.
- **Plan order:** part 5 comes before part 6, which adds `.arm32` to `Isa`.
  Anything in part 5 that switches on `Isa` cannot name `.arm32` yet.
- **Not in part 5:** `ObjectFileCompiler.supportsTarget` and the
  word-sized descriptor writes (the reference's other `ObjectFileCompiler`
  changes) gate whether the dev backend serves arm32; they belong with
  part 6 or 8, where arm32 is first compiled.

### Alternatives considered

- **Write ELF32 through Zig's linker or `std.elf` writers.** Rejected
  because upstream's dev backend writes its own objects for all targets.
- **Leave DWARF at eight-byte addresses for arm32.** Rejected because
  `DW_FORM_addr` must match the unit's `address_size`, and four is what
  debuggers expect on a 32-bit target.

## Decisions

### D1. Where in-memory arm32 relocation patching goes

- **Status:** Accepted
- **Context:** `applyRelocationsWithContext` patches code in memory for
  `HostSplice` (part 9's host) and `machine_code_shim`. The reference adds a
  `comptime isa: Isa` argument and an arm32 prong, but `Isa.arm32` comes in
  part 6.
- **Alternatives:**
  1. Part 5 covers the object path only (writer, relocation kinds,
     DWARF); in-memory patching for arm32, with its `Isa` argument, comes
     with part 9, the first part that runs arm32 code in-process.
     Implications: about 120 fewer lines here; part 5 does not touch
     upstream's patcher.
  2. Part 5 adds the `isa` argument now for x86_64 and aarch64, replacing
     the byte-guessing; part 9 adds the arm32 prong. Implications: a fix
     upstream may like on its own (AGENTS.md's no-heuristics rule), but
     it is not about objects and grows this PR's review.
  3. Move part 5 after part 6. Implications: part 6 then has no object
     writer for its tests.
- **Recommendation:** Alternative 1, and offer alternative 2's fix to
  upstream separately when part 9 nears.
- **Outcome:** first alternative 2, then alternative 4 (below), because
  alternative 2 was already upstream. `69b0808e11` gave every function
  relocation an explicit `FunctionRelocationKind`, and data relocations
  already had `DataRelocationKind`; the patcher switches on the kind and
  checks the bytes only in debug asserts. The context above described the
  reference's older base. With explicit kinds no `Isa` is needed, so the
  problem alternatives 1 to 3 solve is gone. Two new alternatives:
  4. Part 5 adds the arm32 kinds with their in-memory patch functions and
     unit tests. Implications: about 120 lines nothing calls in-process
     until part 9; each kind is complete in one place.
  5. Part 5 adds the kinds, and the patcher's arm32 prongs are
     `unreachable` until part 9. Implications: about 120 lines smaller,
     but a placeholder reachable as soon as an arm32 relocation is
     patched in-process.
  Accepted: alternative 4.
- **Consequences:** `FunctionRelocationKind` gains `arm32_call` and
  `DataRelocationKind` gains `arm32_movw_prel` and `arm32_movt_prel`;
  `patchLinkedFunctionRelocation` and `patchLinkedDataRelocation` gain
  their prongs (`patchArm32Call`, `patchArm32MovPrel`), tested against
  part 4's encoder output. No `abs32` kind and no `patchAbsolute32Operand`
  (E-10): no arm32 code puts an address word in its code, and the
  reference's one use, a `local_data` pointer patched in memory, is
  already covered by `patchAbsolutePointerOperand`, which writes the host
  pointer's width. Each kind fixes its addend (−8, −16, −12); the encoder
  writes it into the instruction, and the ELF writer and the patcher
  debug-assert it there rather than write it again (X-7). The ELF, Mach-O
  and COFF writers and `RunImage` gain prongs for the kinds: Mach-O and
  COFF as invariants, since arm32 objects are only ELF, and `RunImage`
  returning `error.UnsupportedDevRunRelocation`, as it does for
  `local_data`. `HostSplice` and `machine_code_shim` do not change; part
  9 starts feeding them arm32 code.

### D2. How the link smoke test is written

- **Status:** Accepted
- **Context:** the reference uses Python and the dropped `elf32_reader.py`,
  and runs the program under qemu. Upstream CI has no qemu until part 8's
  lane.
- **Alternatives:**
  1. A Zig build step `run-check-arm32-link-smoke`: a small Zig program
     builds the object with `Emit` and `ElfWriter`, checks the header,
     flags and attributes with `std.elf`, and links it with `zig cc -target
     arm-linux-musleabihf` and a C `main`. No run; part 8's qemu lane runs
     it. A minici job in the source lane. Implications: no Python; linking
     already proves the relocation types and REL addends are accepted.
  2. Port the reference's Python script, as a `primary_host` job (Linux
     only, so Windows' missing `python3` does not matter). Implications:
     about 385 lines with a reader; upstream does use Python in CI, but the
     check would not run on every host.
  3. Unit tests only: write an object and read it back with `std.elf`.
     Implications: smallest, but nothing links, so a relocation type the
     linker rejects lands unnoticed.
- **Recommendation:** Alternative 1, with alternative 3's unit tests as
  well.
- **Outcome:** Alternative 1, with the unit tests.
- **Consequences:** the smoke program's run (does it print and return
  42?) waits for part 8; the step's placement must be checked like part
  4's (it needs only Zig and the source tree). After linking, the step
  also reads the executable with `std.elf` and checks the `bl` lands on
  its callee and the `movw`/`movt` pair on its data symbol (X-8), so a
  wrong addend or relocation type shows without qemu.

### D3. One writer with a class parameter, or a second writer

- **Status:** Accepted
- **Context:** the reference adds `write32` (about 450 lines) beside the
  existing writer, renamed `write64`; both lay out the same sections.
- **Alternatives:**
  1. One writer, generic over the ELF class at comptime (record types,
     relocation section type and entry size, alignment).
     Implications: no duplicated layout code; the 64-bit path is
     rewritten, so its output needs the byte comparison.
  2. A second writer, as the reference does. Implications: the 64-bit path
     is untouched; about 450 lines that repeat it, which a maintainer is
     likely to ask to merge.
- **Recommendation:** Alternative 1.
- **Outcome:** Alternative 1.
- **Consequences:** a test (or a one-off comparison recorded here) that
  x86_64 and aarch64 objects are byte-identical before and after; the
  arm32-only pieces (`.ARM.attributes`, `$a`) are switch prongs on the
  architecture.

### D4. What `.ARM.attributes` states

- **Status:** Accepted
- **Context:** the reference writes a fixed block: ARMv7-A, A32 and
  Thumb-2 permitted, VFPv3-D32, NEONv1, 8-byte alignment and hard-float
  arguments.
- **Alternatives:**
  1. A fixed block matching part 4's CPU floor, built from named tag
     constants, with a unit test against what `zig cc` writes for the same
     CPU. Implications: simple; must change if the floor moves.
  2. Derive it from the target's Zig CPU features. Implications: follows a
     floor change automatically, but needs a feature-to-tag mapping.
  3. Omit the section. Implications: smallest; LLD then cannot catch a
     hard-float/soft-float mix with the C runtime.
- **Recommendation:** Alternative 1; review whether `Tag_THUMB_ISA_use`
  should be "Thumb-2 permitted" when the backend emits no Thumb.
- **Outcome:** Alternative 1, with `Tag_THUMB_ISA_use` = 2. The block has
  the reference's 11 tags. Clang writes 2 for ARM-mode code too (it means
  the target allows Thumb-2, not that the file contains it), and LLD
  chooses stubs from `Tag_CPU_arch`, not this tag. `zig cc` writes 27 tags
  for cortex-a7, so the unit test checks that each of our 11 has
  `zig cc`'s value, with `Tag_FP_arch` and `Tag_Advanced_SIMD_arch` pinned
  to our floor (VFPv3-D32 and NEONv1; `zig cc` writes VFPv4 and NEON with
  FMA for cortex-a7).
- **Consequences:** part 4's comptime CPU-floor check and this block name
  the same floor; a comment on each points at the other.

### D5. REL or RELA

- **Status:** Accepted
- **Context:** upstream writes `SHT_RELA` for both 64-bit targets.
- **Alternatives:**
  1. `SHT_REL`, as AAELF32 specifies; addends live in the instruction or
     data word. Implications: what GNU and LLVM tools emit for ARM; part
     4's placeholders already carry the addends.
  2. `SHT_RELA`. Implications: no addends in the code, but unusual for ARM
     and less widely accepted by tools.
- **Recommendation:** Alternative 1.
- **Outcome:** Alternative 1.
- **Consequences:** the writer must not write an addend for arm32; a data
  relocation (`R_ARM_ABS32` in `.rodata`) needs its addend in the word.
  The same holds for DWARF (X-5): `Dwarf.build` writes 0 in each relocated
  field and keeps the addend in the relocation (a subprogram's `low_pc`
  carries its `code_start`). RELA and Mach-O are fine with that; the ELF32
  writer must copy each debug relocation's addend into its field, as the
  Mach-O writer does, or every subprogram on arm32 would point at the
  start of `.text`. A test reads a subprogram's `low_pc` field back and
  checks it equals `code_start`.

### D6. How the writer learns the pointer width

- **Status:** Accepted
- **Context:** DWARF needs the address width, and the writer the ELF
  class. The reference passes `.four` or `.eight` from
  `target.ptrBitWidth()` in `ObjectFileCompiler`.
- **Alternatives:**
  1. From the target, as the reference does, through upstream's existing
     `DebugRelocWidth`. Implications: one source of truth; no guessing.
  2. From the architecture enum (`.arm` means 32-bit). Implications:
     breaks for a future ILP32 target on a 64-bit architecture.
- **Recommendation:** Alternative 1.
- **Outcome:** Alternative 1.
- **Consequences:** `Dwarf.build` gains an `address_width` argument; the
  x86_64 and aarch64 callers pass `.eight`.

## Risks

### R1. The 64-bit writer changes by accident (D3)

- **Likelihood:** Medium
- **Impact:** High
- **How we'd notice:** the byte comparison; the relative oracle.
- **Mitigation:** the comparison runs on every commit that touches
  `elf.zig`.
- **If it happens:** fix before the commit lands.

### R2. The objects link but run wrong

- **Likelihood:** Medium
- **Impact:** Medium
- **How we'd notice:** part 8's qemu lane runs the smoke program; before
  that, the smoke step's check of the linked `bl` and `movw`/`movt`
  targets (D2) catches wrong relocations, but not wrong code.
- **Mitigation:** run the smoke program by hand under qemu on each
  commit (not in CI).
- **If it happens:** fix in part 5's branch if it is still open,
  otherwise in part 8.

### R3. Upstream moves the writer first

- **Likelihood:** Medium (`d0846f6eb6` already brought upstream changes
  to `elf.zig` and `macho.zig`)
- **Impact:** Low
- **How we'd notice:** the rebase before cutting.
- **Mitigation:** cut from the current upstream state, not the reference.
- **If it happens:** adapt.

## Testing

From `.workspaces/arm32-elf32-objects`, on each commit:

    zig build test
    zig build run-check-arm32-link-smoke

Expected: the patcher's arm32 tests pass (D1); the writer's tests pass (ELF32 header, sections, symbols, REL
records and attributes read back with `std.elf`); the smoke step links, and
the linked `bl` and `movw`/`movt` reach their targets.

64-bit objects unchanged, on each commit that touches `elf.zig` (D3): the
same x86_64 and aarch64 objects written before and after, compared with
`cmp`. Expected: identical.

By hand, not in CI: run the smoke program under qemu.

    qemu-arm-static -cpu cortex-a9 <linked smoke program>

Expected: it prints the smoke message and returns 42.

Plus the relative oracle and the part 4 check list on each commit, and
`zig build minici -- --minici-shard source`.

## Recommendation

Accepted 2026-11-21: D1 4, D2 1, D3 1, D4 1, D5 1, D6 1. Commits, each
building and passing on its own:

1. `Dwarf.zig`: the `address_width` argument; callers pass `.eight`.
2. `elf.zig`: the writer generic over the ELF class, 64-bit output
   byte-identical.
3. `elf.zig`: the arm32 architecture (ELF32, `EM_ARM`, `e_flags`, `$a`,
   `.ARM.attributes`, `SHT_REL` with addends in place, debug relocations
   included) and its unit tests.
4. `Relocation.zig`: the arm32 kinds and their in-memory patching, with
   their ELF types and the other writers' and `RunImage`'s prongs, and
   tests.
5. The link smoke step, its check of the linked targets, and its minici job.
