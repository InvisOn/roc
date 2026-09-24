# ARM32 Dev Backend: Changes to Existing Code

Every change the arm32 work has made to code that existed before
`projects/big/arm32-dev-backend.md` was started, with the reason it was
needed and the commit that carries it. New files (the `arm32/` module, the
oracle scripts, the vendored runtime) are not listed. Fixes to defects in
existing code are committed separately from plan milestones; plan milestones
that necessarily edit existing code are listed under their milestone.

Every entry that touches code generation leaves x86_64 and aarch64 output
byte-identical, verified by the A0 oracles (`dev_object` snapshots and the
eval-corpus object hashes) unless the entry says otherwise.

## Fixes to existing defects (separate commits)

### Target data sized by the host's `usize` (`654087283b`)

`LirCodeGen` measured target memory with the compiler host's word in three
places: the Debug RocStr validity check's alignment mask (`@alignOf(usize) -
1`), the erased-call descriptor array (`@sizeOf(usize)` per entry) and the
erased-callable heap cell's drop-pointer slot. Needed because a 64-bit host
cross-compiling for a 32-bit target would validate 4-byte-aligned heap strings
against 8-byte alignment (a false Debug crash) and lay out 8-byte slots the
target reads as 4-byte ones. No effect on today's targets.

### Plan documents failed `run-check-tidy` (`12be3758d5`)

Spaced em dashes and missing or duplicate top-level titles in
`projects/big/arm32-dev-backend*.md` and `arm64-backend-reference.md` made the
tidy check fail on the branch before any code changed. Needed so the tidy
check could gate every later commit.

## Plan milestones that edit existing code

### Track B: encoder and oracle (`8ffd541b71`)

- `.gitignore`: whitelists `ci/arm32_encoding_oracle.s`. Needed because `*.s`
  is ignored repository-wide, so CI would never have received the oracle's
  input and `run-check-arm32-encoding-oracle` would fail there.
- `build.zig`, `src/build/minici.zig`: the `run-check-arm32-encoding-oracle`
  step and minici job, so a stale generated test file fails CI.
- `src/backend/dev/mod.zig`: exports `arm32`, which is how its tests reach
  the backend test binary.

### A0: byte-identity oracles (`61a6d470f2`)

- `src/eval/test/parallel_runner.zig`: `--write-dev-code-hashes` /
  `--check-dev-code-hashes`, sharded over forked children. Needed as the
  golden oracle for Track A's rewrite of the driver.
- `src/eval/inspected.zig`: the live-lowering step is factored out of
  `lowerCheckedRootWithViews` (`lowerCheckedRootLive`) and reused by the new
  `devObjectHashes`. Needed because the LIR image the eval runner normally
  uses drops the layout store's recursive-graph keys, which the object path
  requires.
- `src/build/test_harness.zig`: `writeWholeFile` / `readWholeFile`. Needed
  because tidy bans `std.Io.Dir.cwd()` in core source trees such as
  `src/eval/`, and the shared harness is where runner file I/O lives.
- `src/lir/LIR.zig`: `ProcIdentity.canonicalizeSymbolNames`;
  `src/snapshot_tool/main.zig` hashes canonicalized objects. Needed because
  procedure symbol names digest the compiler build, so without it every
  commit would change every hash of an object containing a procedure. The ten
  pre-existing `dev_object` hashes are unaffected (they contain no procedure).
- `build.zig`, `src/build/minici.zig`: the `run-check-dev-code-hashes` step.

### A1: dispatch, register budget, `CC` seam, facade

- `LirCodeGen.zig`, `FrameBuilder.zig`, `CallingConvention.zig`,
  `ObjectWriter.zig` (`a3ad2da0d6`): every two-way `arch == .x86_64` /
  `== .aarch64` test goes through `Isa` (`src/backend/dev/isa.zig`). Needed
  because a binary test silently routes arm32 into another ISA's code path,
  and several `CallBuilder` chains had no final `else` (arm32 would have
  emitted nothing). The never-read `LirCodeGen.cc` field is removed because
  its initializer, `CallingConvention.forTarget`, panics for `.arm`.
- `x86_64/CodeGen.zig`, `aarch64/CodeGen.zig`, `NativeProcCompiler.zig`
  (`42b80a5c56`): the CPU level and the bounded temporary allocators move from
  the driver into each ISA's `CodeGen`, which records the D10 high-water mark.
  Needed as the seam per-ISA instruction selection and arm32's register budget
  build on.
- `x86_64/Emit.zig`, `aarch64/Emit.zig`, `LirCodeGen.zig` (`939c17678e`): role
  registers (result-pointer and RocOps save registers, Roc return registers,
  caller stack-argument base) come from the ISA's `CC`. Needed so arm32
  supplies its register roles by defining its `CC` instead of adding a third
  literal at each site.
- `LirCodeGen.zig`, both `CodeGen.zig` (`f23924444c`, `37872af5d3`): 55
  ISA-neutral helpers move into per-ISA `CodeGen` methods with one signature.
  Needed so arm32 implements them in its own `CodeGen`.

### A3: containers (`301db39b9a`)

- `object/elf.zig`: ELF32/REL writer for `.arm` beside the untouched ELF64
  path. Needed because the writer was ELF64/RELA-only and an EM_ARM ELF64
  object is accepted by no linker.
- `Relocation.zig`: `abs32`, `arm_movw_prel`, `arm_movt_prel` kinds and their
  in-process patchers. Needed for arm32's position-independent data addresses
  (D8).
- `object/macho.zig`, `object/coff.zig`, `RunImage.zig`: explicit refusals of
  the arm32 kinds (`RunImage.relocationKindForData` now returns an error).
  Needed because those switches are exhaustive and none of those formats or
  the shim runs arm32 code.
- `Dwarf.zig`, `ObjectFileCompiler.zig`: DWARF takes the target's address
  width. Needed because DWARF addresses were hard-coded to eight bytes.
- `ObjectWriter.zig`: the call-relocation addend becomes an exhaustive switch
  (x86_64 -4, aarch64 0, arm -8). Needed because `if x86_64 -4 else 0` would
  have given arm32 the wrong PC bias.

### Track C: target artifacts (`75c55299d2`)

- `build.zig`: arm32musl/arm32glibc builtins, runtime and host-library
  targets. Needed for anything to link for arm32.
- `src/default_platform/linux_runtime.zig`: an A32 `_start` and an arm
  `ucontext` for crash backtraces. Needed because `.arm` was a
  `@compileError`.
- `src/build/glibc_stub.zig`: real A32 bodies. Needed because it emitted
  `ret`, which is not an A32 instruction.
- `src/cli/main.zig`: explicit arm32 rows in the five prebuilt-object tables.
  Needed because arm32 fell through to the host's `native` builtins objects
  (and `null` runtime objects).
- `src/cli/test/parallel_cli_runner.zig`: `--cross-target` selecting no cases
  now fails. Needed because it exited 0, so a lane that tested nothing read as
  passing.
- `src/target/mod.zig`: a test pinning Zig's arm baseline to the D2 floor.
- `test/fx`, `test/int` platform manifests: declare `arm32musl`.

### A2: width model

- `LirCodeGen.zig` (`1decf55b3f`): `target_ptr_size` derives from the target
  (it was the literal 8) and the word vocabulary is added; RocStr/RocList
  field accesses name their fields. The small-string literal path bit-cast a
  word's bytes to `u64`, which compiles only for 8-byte words. Needed because
  every 32-bit value of these was wrong or uncompilable.
- `LirCodeGen.zig` (`9896319673`, `dcb012efe4`): list element access, the
  general copier, `List.len`/`List.capacity`, and the string and refcount
  helpers use words; `word_sign_bit` and `small_str_len_shift` replace
  `minInt(i64)` and a literal 56. Needed because those are pointer-sized
  values whose 64-bit spelling is a compile error (or wrong) on arm32.
