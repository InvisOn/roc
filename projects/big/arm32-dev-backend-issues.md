# ARM32 Dev Backend: Issues Found

Issues found while carrying out `projects/big/arm32-dev-backend.md`, each
verified in the tree rather than inferred. Most are pre-existing and outside
arm32's scope; each says where it lives, why it matters, and its status. The
design and the reasoning behind the arm32 work are in
`src/backend/dev/arm32/DESIGN.md`.

## Open: pre-existing defects

### LIR images drop the layout store's recursive-graph keys

- **Where:** `src/lir/lir_image.zig` rebuilds the layout store with an empty
  `interned_recursive_graphs` map (around `:402` and `:815`).
- **Effect:** `src/layout/digest.zig` needs those keys to end its walk through a
  recursive layout. Any consumer that hands an image to the dev backend's
  object-file path panics on the first recursive type ("layout digest: cyclic
  layout N has no recursive-graph key"). Nothing does that today; the eval
  runner's hash oracle hit it and now compiles the live lowering instead.
- **Fix direction:** serialize the keys into the image. Making the digest
  tolerate their absence would be a fallback.

### In-process relocation patching guesses the encoding

- **Where:** `src/backend/dev/Relocation.zig`, `patchLinkedFunctionRelocation`.
- **Effect:** it picks x86 `call rel32` or AArch64 `BL` by decoding the bytes
  around the relocation (`0xE8` before the offset, or the `BL` opcode bits)
  instead of carrying an explicit relocation kind. That is recovering missing
  information in a compiler stage, which AGENTS.md forbids, and it cannot be
  extended to A32 `BL` without adding a third guess.
- **Fix direction:** give function relocations an explicit encoding kind, as
  `DataRelocationKind` does for data. Needed before J3a runs arm32 code
  in-process.

### `abs64` patching is sized by the host, not the relocation

- **Where:** `src/backend/dev/Relocation.zig`, `patchAbsolutePointerOperand`.
- **Effect:** an `abs64` relocation writes four bytes when the *compiler host*
  has a 32-bit `usize`. The relocation kind should decide the width; on an
  arm32 host (J3a) this would silently narrow 64-bit fields.
- **Fix direction:** arm32 code uses the explicit `abs32` kind (added in A3);
  `abs64` should always write eight bytes.

### The snapshot tool hashes programs that failed to type-check

- **Where:** `src/snapshot_tool/main.zig`, `type=dev_object` snapshots.
- **Effect:** a type error turns the definition into `<runtime_error>` in the
  MONO section and the tool still hashes the object, with no diagnostic. A
  new snapshot can lock in a broken program without anyone noticing.
- **Fix direction:** report problems for `dev_object` snapshots (as other
  snapshot types do) or refuse to hash a program with errors.

### Procedure symbol names change with every compiler build

- **Where:** `src/check/checked_artifact.zig` folds
  `build_options.compiler_artifact_hash` (from the git revision) into every
  checked-artifact key; `ProcIdentity` digests those keys and names each
  procedure symbol `roc__proc_<digest>`.
- **Effect:** every object containing a procedure changes bytes on every
  commit even when code generation is identical. The original ten
  `dev_object` snapshots never noticed because none compiles a procedure; any
  byte-pinning test of real code breaks on the next commit.
- **Status:** both A0 oracles hash with `ProcIdentity.canonicalizeSymbolNames`.
  Whether identities *should* depend on the compiler build is a design
  question for the identity owners, not for arm32.

### glibc stub still emits `ret` for non-x86/aarch64/arm architectures

- **Where:** `src/build/glibc_stub.zig`.
- **Effect:** arm now gets real A32 bodies, but `aarch64_be`, `wasm32` and
  `other` still emit `ret`, which is not an instruction on most of them. Only
  reached for glibc cross targets, none of which use those architectures.

### A backend unit test writes to stderr, failing `zig build`

- **Where:** `wasm.WasmModule` test "mergeModule rejects same-name imports with
  different signatures" prints "WASM merge: both modules import 'roc_crashed'".
- **Effect:** `zig build run-test-zig-module-backend` reports failure although
  the binary reports every test passed; failures in that step are therefore
  easy to dismiss.

## Open: risks for the remaining arm32 work

### The 64-bit register budget is nearly exhausted already

Over the eval corpus, instruction selection peaks at 12 of 13 allocatable
general registers on x86_64 (12 of 25 on aarch64), pinned registers included.
arm32 has 11, with 64-bit values taking two each. Existing sequences cannot be
reused on arm32 (D10), and x86_64 itself is one register from an invariant
panic.

### Width bugs in shared native code have never been exercised

wasm32 is the only 32-bit target today and it shares no code generation with
the dev backend. The first 32-bit native target will be the first to run the
shared native code (object writing, relocation widths, DWARF, the driver's
literal 8s) at 32-bit width.

### Test skip guards are keyed on the host architecture

`LirCodeGen.zig` tests skip unless `builtin.cpu.arch` is x86_64 or aarch64
instead of consulting `host_lir_codegen_available`. The plan's J3a rewrites
them.

## Resolved during the work

- **`*.s` was gitignored:** `ci/arm32_encoding_oracle.s` would never have
  reached CI. Whitelisted in `.gitignore`.
- **Plan docs failed tidy:** spaced em dashes and duplicate or missing titles
  in `projects/big/`. Fixed.
- **CLI tables handed arm32 the host's objects:** `BuiltinsObjects.forTarget`
  and `forTargetExtern` mapped `arm32linux`/`arm32musl` to `native`. Replaced
  by explicit arm32 rows.
- **`LirCodeGen.cc` would have panicked for arm32:** its initializer called
  `CallingConvention.forTarget`, which panics for `.arm`. The never-read field
  is gone.
- **Two-way arch tests would have mis-routed arm32:** about 250
  `arch == .x86_64` / `== .aarch64` tests in the driver, `FrameBuilder` and
  `CallingConvention` (some with no final `else`) now go through `Isa`, which
  refuses to compile for arm32.

## Tooling notes

- JIT code cannot be a golden oracle: it embeds absolute host addresses.
- `libc.a` from Zig's musl is not byte-reproducible (members are named by
  absolute cache paths), and Zig's cache holds two `crt1.o` builds per arm
  triple; `ci/vendor_musl_runtime.py` takes the one the link line names.
- The eval-corpus hash check costs about four minutes on sixteen cores, mostly
  re-checking the Builtin module for each case.
- The plan's claim that `roc build --help` names `dev` as the default `--opt`
  is stale: it names `speed`.
