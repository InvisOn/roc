# ARM32 Dev Backend: Issues Found

Issues found while carrying out `projects/big/arm32-dev-backend.md`, each
verified in the tree rather than inferred. Most are pre-existing and outside
arm32's scope; each says where it lives, why it matters, and its status. The
design and the reasoning behind the arm32 work are in
`src/backend/dev/arm32/DESIGN.md`; every change made to existing code, and why,
is in `projects/big/arm32-dev-backend-existing-code-changes.md`.

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

### wasm32 wraps `U64` sublist indices to 32 bits (confirmed miscompile)

- **Where:** `src/backend/wasm/WasmCodeGen.zig`, the `.list_sublist` /
  `.list_sublist_borrowed` lowering, which loads the record's `U64` `start`
  and `len` and narrows each with `i32_wrap_i64` before the call.
- **Effect:** `List.sublist([1, 2, 3], { start: 4294967296, len: 1 })`
  evaluates to `[1.0]` on the wasm backend and to `[]` on the interpreter and
  the dev backend (checked with a temporary eval case). Any index at or above
  2^32 wraps to a small in-range one. `List.get` with the same index is
  correct on all three.
- **Fix direction:** pass the full `U64` to a builtin that saturates it, as
  the native builtins do (`start: u64`), or saturate instead of wrap. Worth an
  eval case that runs on every backend.
- **Relevance to arm32:** the dev backend's list and string builtins take
  `u64` counts and indices and narrow them themselves, so the arm32 driver
  must pass genuine 64-bit values (register pairs) there and must not narrow
  them; only `usize` results typed `U64` (`List.len`) and in-bounds indices
  used for address arithmetic cross the word/`U64` boundary in the driver.

### `list_get_unsafe` accepts an index in an i128 location

- **Where:** `src/backend/dev/LirCodeGen.zig`, the `.list_get_unsafe` handler's
  index materialization (`.stack_i128` and `.immediate_i128` arms, commented
  "Dec/i128 index - just load the low" part).
- **Effect:** a list index is `U64` in LIR, so an i128/Dec location there is a
  producer bug; the handler silently truncates it instead of reporting the
  invariant violation. That is best-effort recovery in a compiler stage.
- **Fix direction:** make those arms invariant failures.

### A string result stored from one register

- **Where:** `src/backend/dev/LirCodeGen.zig`, `storeResultToSavedPtr`'s
  `.str` arm, the catch-all over non-stack locations (commented "Fallback for
  non-stack string location").
- **Effect:** a RocStr is three words; for any location that is not
  `.stack`/`.stack_str` this loads one register (the bytes pointer, via
  `ensureInGeneralReg`) and stores only that word, leaving the length and
  capacity unwritten. Either such locations never reach it (then the arm
  should be an invariant failure) or they do and the result is corrupt. It is
  a fallback in a compiler stage, which AGENTS.md forbids.
- **Fix direction:** make the arm an invariant failure and fix any producer
  that reaches it.

### Redundant narrowing before byte stores

- **Where:** `src/backend/dev/LirCodeGen.zig`, `storeResultToSavedPtr`'s `.u8`
  and `.i8` arms.
- **Effect:** each shifts the register left and right by `word_bits - 8`
  before `emitStoreScalarToPtr(..., 1)`, which stores only the low byte, so
  the two shifts are dead work. Harmless; left in place because Track A
  changes must be byte-identical. A cleanup can drop them with a regenerated
  hash file.

## Open: risks for the remaining arm32 work

### The interpreter's hosted-call trampoline assumes a 64-bit host

- **Where:** `src/eval/host_trampoline.zig`, the ABI target selection, and
  `src/eval/host_trampoline.S`.
- **Effect:** any host that is not aarch64 is treated as x86_64 SysV, so an
  interpreter running *on* arm32 (the Track D/J3a lane) would marshal hosted
  calls with the wrong ABI; the trampoline also carries 64-bit registers and
  has no A32 entry. The J3a baseline's 51 passing cases make no hosted call.
- **Fix direction:** an explicit arm32 selection (`layout.abi.Target.arm32`,
  which now exists) and an A32 trampoline, or an explicit refusal on hosts the
  trampoline does not implement, before J3 makes the lane required.

### Baseline of the arm32 eval lane before J1

`zig build build-test-eval-runner -Dtarget=arm-linux-musleabihf
-Doptimize=ReleaseFast`, run with `qemu-arm-static -cpu cortex-a9 ...
--timeout 300000` (2026-09-25): 51 passed, 2120 failed, 0 crashed. Every
failure is `UnsupportedPlatform` (the dev backend has no arm32 code
generator), so the compiler's front end and interpreter already run on a
32-bit host; J1-J3 turn the failures into passes.

### Target data laid out with the host's word

Code generation sometimes sizes *target* data with the *host's* `usize`, which
is right only while host and target share a word size (every target before
arm32). Fixed (`654087283b`): `@alignOf(usize)` in the Debug RocStr validity
check and `@sizeOf(usize)` in the erased-call descriptor array and the
erased-callable drop-pointer slot; and every use of
`builtins.erased_callable`'s host layouts (`Payload`, `capture_offset`,
`HotReloadCaptureHeader`, `CompilerMetadata`), now derived for the target word
by `erased_layout` in `LirCodeGen`.

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

### A checked I64 multiply takes 10 of arm32's 11 temporaries

`emitWide64MulChecked` holds both operand pairs, the result pair and four
partial-product registers at once. It runs between statements, where the
pool is otherwise free, but any caller that keeps a register live across it
would exhaust the pool (an invariant panic, not a miscompile). Reloading an
operand word from its slot would free two registers if that ever happens.

### Shim execution does not resolve `__aeabi_*` yet

`callAeabiHelper` emits a relocation to the helper's name in shim mode, like
every other runtime symbol. Shim mode only runs for the compiler's host, so
this matters only for a compiler running on arm32; its shim would have to
resolve those names against compiler-rt.

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
