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

### A U64 discriminant loaded as eight bytes

- **Where:** `src/backend/dev/LirCodeGen.zig`, `generateDiscriminantAccess`
  (the boxed tag-union arm) and `loadAndMaskDiscriminant` with
  `disc_use_w32 == false`.
- **Effect:** when the discriminant's target layout is `U64`, the 64-bit
  targets load a full word from the discriminant offset and mask only
  discriminants narrower than four bytes. A four-byte discriminant followed
  by padding would read the padding into the high half. Unverified: it
  depends on whether that padding is always zero.
- **Fix direction:** load `discriminant_size` bytes and zero-extend, as the
  arm32 path (a word load, then `discriminantResult`) already does.

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

### A checked I64 multiply took 10 of arm32's 11 temporaries (resolved in J2)

`emitWide64MulChecked` held both operand pairs, the result pair and four
partial-product registers at once, and J2's D10 measurement saw the general
pool reach 11 / 11 there. It now leaves the operands in their memory slots and
loads one word at a time into two scratch registers, so it holds 8 registers
at most. Over everything J2 builds, the arm32 general peak is now 9 / 11 (see
the register budget section of `src/backend/dev/arm32/DESIGN.md`).

### Shim execution did not resolve `__aeabi_*` (resolved in J3a)

`callAeabiHelper` emits a relocation to the helper's name in shim mode, like
every other runtime symbol. `native_runtime_libcalls.resolve` now binds those
names to the compiler's own compiler-rt when the compiler runs on arm32, so
in-process linking (HostSplice, the machine-code shim) resolves them.

### Test skip guards are keyed on the host architecture

`LirCodeGen.zig` tests skip unless `builtin.cpu.arch` is x86_64 or aarch64
instead of consulting `host_lir_codegen_available`. The plan's J3a rewrites
them.

### Zig 0.16 passes nested `extern struct` arguments off-ABI on arm

- **Where:** Zig's own C-ABI lowering for `arm-linux-musleabihf` (and so the
  `test/fx` host, `test/fx/platform/host.zig`, which is Zig).
- **Effect:** a by-value `callconv(.c)` argument whose type is an `extern
  struct` *containing another struct* starts at an even core register, as
  if 8-byte aligned, although every field is a word: for
  `fn f(h: H) callconv(.c) R` with `H = extern struct { name: R }` and `R` a
  12-byte `{ ?[*]u8, usize, usize }`, Zig reads `h` from r2, r3 and the
  first stack word, leaving r1 unused. AAPCS32 (and clang, for the same C)
  puts it in r1-r3. The same struct passed flat, or a nested one after a
  core-register argument in r0, lands correctly only when no even-register
  rounding shifts it. Reproduction: compile the two declarations above with
  `zig build-obj -target arm-linux-musleabihf` and disassemble; clang on the
  equivalent C uses r1-r3.
- **Consequence:** the arm32 dev backend follows AAPCS32, so a Zig host
  receives the wrong words. `hostedHostGetGreeting(host: HostRecord)` in the
  fx host takes `HostRecord { name: RocStr }`, and 16 of the 19 failing
  `test/fx` programs call `Host.get_greeting!` (segfault in the host's
  `bufPrint`, fault address = the string's second word).
- **Not changed in the compiler:** matching Zig here would break AAPCS32
  callers and C hosts; the compiler follows AAPCS32.
- **Worked around in the fx test host (temporary):** in
  `test/fx/platform/host.zig`, `hostedHostGetGreeting` takes the inner
  `RocStr` directly on arm32 (`HostGreetingArg`), and `hostRecordFromArg`
  rebuilds the `HostRecord`. A struct with one struct field has the same C
  ABI as that field on every target, so the Roc side is unchanged. The switch
  is `work_around_zig_arm_nested_struct_bug` (true only on arm).
- **How we find out it is fixed:** two tripwires, so nobody has to reread
  this note. `test/fx/platform/zig_arm_nested_struct_abi_probe.zig` expects
  the bug and fails, saying to remove the workaround, once Zig passes nested
  structs correctly; the arm32 CI lane runs it under qemu. And `host.zig`
  refuses to compile for arm on any Zig other than the one the bug was
  confirmed on (`confirmed_on`, 0.16.0), with a message giving the probe
  command, so an upgrade forces the check.
- **When Zig is fixed:** set `work_around_zig_arm_nested_struct_bug` to
  `false` and rerun `zig build run-test-cli -- --suite platforms --filter
  test/fx/ --cross-target=arm32musl --cross-opt=dev --cross-run
  --cross-runner=qemu-arm-static`; if all pass, delete the switch,
  `HostGreetingArg` and `hostRecordFromArg`, and restore the plain signature
  `fn hostedHostGetGreeting(host: HostRecord) callconv(.c) RocStr`. Other Zig
  hosts that take a nested struct by value on arm32 need the same until then.

### `test/fx` on arm32 (J3b)

With `--cross-run --cross-runner=qemu-arm-static`, all 121 programs pass.
Before the host workaround above, these 16 failed, all calling
`Host.get_greeting!`:
`match_str_return`, `question_mark_operator`, `empty_list_get`,
`dict_pseudo_seed_repro`, `zst_nested_singleton_shapes`, `list_method_get`,
`dbg_corrupts_recursive_tag_union`, `hosted_effect_opaque_with_data`,
`early_return_rc`, `float_comparison`, the four `match_guard_*`,
`cross_module_recursive_nominal`, `test_no_dbg`. (Three others,
`issue_10038_comptime_dict_transitions`, `inspect_dict_set` and
`leak_list_str_ops`, were arm32 bugs: `list_sublist`'s record window passed
as single words, and the list incref RC helper reading the list at 64-bit
word offsets.)

### A `u64` builtin parameter passed as one register is not caught

On arm32 a builtin's `u64` parameter takes an aligned register pair. A call
site that passes one with `addImmArg` or `addRegArg` builds a single-register
argument; for an immediate that fits 32 bits nothing fails at build time
(`CallBuilder` rejects only immediates wider than a word). J2 audited every
wrapper with 64-bit parameters (`dev_wrappers.zig`, `boxy_abi.zig`) and moved
their call sites to `addU64SlotArg`, `addImm64Arg` or `addMem64Arg`; a new
builtin with a `u64` parameter needs the same.

## Resolved during the work

- **The vendored arm32 `libc.a` lacked `string.h`:** Zig 0.16 builds part
  of the C library from its own sources into a separate `libzigc.a`, and
  musl's `libc.a` omits those functions, so linking `test/fx` programs
  failed on `strcmp`. `ci/vendor_musl_runtime.py` now appends `libzigc.a`'s
  members to the vendored `libc.a`.
- **Cross builds ignored the backend's stderr expectations:** the runner's
  `--cross-opt` passed `--opt=` but still required optimized-build warnings
  (the `dbg` warning) from dev builds. It now filters them the way native
  runs do.
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

### The wasm eval oracle cannot run in a 32-bit process

- **Symptom:** in an eval runner built for arm32, every wasm evaluation failed
  with `WasmExecFailed`. The ReleaseSafe runner shows the cause:
  `wasm instantiate failed: Uninstantiable64BitLimitsOn32BitArch`.
- **Cause:** Roc's wasm modules declare linear memory without a maximum
  (`WasmModule.memory_max_pages = null`). bytebox then takes the wasm32 limit
  of 65536 pages (4 GiB) and reserves all of it up front (`MemoryInstance.init`,
  a `StableArray` of the maximum size). Its own check refuses a maximum above
  `maxInt(usize)`, and 4 GiB does not fit a 32-bit address space. Nothing
  about the program or the arm32 backend is involved: any 32-bit host fails
  the same way.
- **What J3a did:** `eval.backendAvailable(.wasm)` is `@sizeOf(usize) >= 8`,
  and the eval runner asks it (it hardcoded `true` before), so a 32-bit build
  reports wasm as `not_implemented` instead of failing. The comment at the
  gate in `src/eval/mod.zig` explains why.
- **What it costs:** on an arm32 (or any 32-bit) host the wasm backend is not
  cross-checked by the eval corpus, and J3a's "same pass count as the host
  x86_64 run" covers the interpreter and dev backends only. The REPL's wasm
  backend is likewise unavailable in a 32-bit compiler. The wasm backend
  itself is host-independent and stays fully tested on 64-bit hosts.
- **Ways to lift it, in order of preference:**
  1. bytebox grows linear memory on demand instead of reserving the maximum
     (a change upstream, or to the vendored copy, which would need its own
     decision).
  2. The eval runner supplies memory through bytebox's `WasmMemoryExternal`
     hooks. This does not work alone: `verifyLimitsAreInstantiable` rejects
     the limit before the hooks are used, so it needs (1) too.
  3. The wasm backend declares a memory maximum. This changes the emitted
     modules on every host and caps every program's memory, so it is a
     language/platform decision, not a test-harness fix.
  Whichever lands, remove the `@sizeOf(usize)` gate in the same commit and
  rerun the arm32 eval corpus under qemu to confirm wasm passes.

### A Debug arm32 eval runner does not link

`zig build build-test-eval-runner -Dtarget=arm-linux-musleabihf` in Debug
fails in LLD: "InputSection too large for range extension thunk". The runner
links LLVM, and a Debug A32 image is larger than a B/BL range extension
thunk can span. The plan's J3a acceptance measures D10 in "the Debug runner
build"; J3a used ReleaseFast (as the CI lane does) and ReleaseSafe instead.
That still checks D10: exhausting a register pool is a `std.debug.panic` in
every build mode, not an assertion that Release builds drop.

### Cross-built compilers fill `.zig-cache` quickly

Each arm32 build of the eval runner leaves a 250-400 MB LLVM-linked binary in
`.zig-cache/o`. During J3a the cache reached 229 GB and filled the disk.
Deleting part of `.zig-cache/o` leaves manifests pointing at missing files,
and Zig does not recover ("failed to check cache: FileNotFound"), so clear
the whole directory instead.

### Two eval tests need more memory than a 1 GB board has

"inspect: inclusive numeric ranges all iterate" and "inspect: exclusive
numeric ranges all iterate" compile ten `Iter.fold` range pipelines, one per
integer width. Compiling them peaks at about 1.25 GB resident on x86_64 and
870 MB in an arm32 build (under qemu). On the Raspberry Pi 3 (920 MB RAM plus
zram swap) they fail with OutOfMemory during compilation, even with one
worker; every other test passes there. This is the compiler front end's
memory use, not arm32 code generation.

## Annoyances to fix later

Small frictions met while working, none blocking. Each says where it belongs.
Fix each one in its own commit, and remove its entry in that commit.

- **The backend test step always reports failure.** One wasm test prints to
  stderr, so `zig build run-test-zig-module-backend` fails although every
  test passes (see "WASM merge" above). Fix in the test: capture or drop the
  debug print. Until then, run the test binary directly to read the totals.
- **Line-number exclusions in build.zig's pattern checks go stale.** The
  type-checker pattern check excludes lines of `inspected.zig`,
  `Check.zig`, `store.zig` and `cir_to_lir.zig` by number, so any edit above
  them breaks the check (J3a shifted `inspected.zig` by one line). Two of the
  `inspected.zig` ranges (2475 and 3265-3276) already point at unrelated
  lines. Fix by anchoring exclusions to a marker comment on the line instead
  of a number.
- **minici stops at the first failing phase and rebuilds everything first.**
  A full run spends about 15 minutes in `build-ci` before the first check,
  so each quick lint failure costs a full cycle. Run the `run-check-*`
  phases directly first, and resume with `--minici-after <phase>`.
- **`run-check-glue-abi` needs a Rust target that is not documented as a
  prerequisite:** `rustup target add x86_64-unknown-linux-musl`. Add it to the
  contributor setup notes.
- **Zig does not print stack traces in arm Debug test binaries under qemu**
  ("stack tracing is disabled"), so an arm32 test failure shows no location.
  ReleaseSafe runners do print traces; a Debug runner does not link at all
  (above). Worth a small helper step that builds a ReleaseSafe arm32 runner.
- **`.zig-cache` fills the disk during cross builds** (above). A periodic
  full clear, or a separate `--cache-dir` for arm32 cross builds that can be
  deleted wholesale, would avoid it.
- **The int app prints heap addresses,** so comparing its stdout across
  targets needs masking (the J3c lane masks `0x…`). Printing a stable token
  instead of the pointer would make the output directly comparable.
- **The wasm eval oracle is off on 32-bit hosts** (see "The wasm eval oracle
  cannot run in a 32-bit process" above for the cause and the options). The
  fix belongs in bytebox's memory reservation; remove the gate in
  `eval.backendAvailable` in the same commit.
- **Probe apps that read stdin block without input.** Any ad-hoc
  build-and-run script must redirect stdin (`</dev/null`) and use a timeout.
