# ARM32 Dev Backend: Issues and Notes

Issues found while carrying out `projects/big/arm32-dev-backend.md`, each
verified in the tree rather than inferred. Most are pre-existing and outside
arm32's scope; each says where it lives, why it matters, and its status. The
design and the reasoning behind the arm32 work are in
`src/backend/dev/arm32/DESIGN.md`; every change made to existing code, and why,
is in `projects/big/arm32-dev-backend-existing-code-changes.md`.

Nothing here is deleted when it stops being current: a resolved entry moves
to "Resolved" with the commit that resolved it, and background that no longer
describes the tree moves to "Background and history". The record of what was
found, and why things are the way they are, stays in one place.

Where a new note goes:

| Kind of note | Where |
|---|---|
| A defect or limitation found (open) | here, section 1.1 (outside arm32) or 1.2 (arm32 support), with Where / Effect / Fix direction and a status line |
| A small friction in the workflow | here, 1.3; fix each in its own commit, which removes the entry |
| An idea worth a separate project | here, 1.4 |
| A plan for fixing an open entry | inside that entry, as a "Plan" subsection |
| Something resolved | move its entry to section 2, with the resolving commit |
| A change to code that existed before the arm32 work | `arm32-dev-backend-existing-code-changes.md`, under its milestone, or under "Fixes to existing defects" if it has its own commit |
| How arm32 works and why (decisions, amendments, lessons) | `src/backend/dev/arm32/DESIGN.md` |
| How to work on arm32 (workflow) | `src/backend/dev/arm32/GUIDE.md` |
| A tool, script or command | `src/backend/dev/arm32/TOOLS.md` |
| The plan's units and their acceptance | `projects/big/arm32-dev-backend.md` (a plan change is recorded as an amendment in DESIGN.md) |
| Verification results, catching up with upstream | `projects/big/arm32-dev-backend-verification.md` |
| A design decision the work still owes, laid out for the owner | its own `projects/big/arm32-dev-backend-<topic>-decision.md`, linked from its issues entry |
| A follow-up project's plan (fuzzing, for example) | its own `projects/big/arm32-dev-backend-<topic>.md`, indexed in `projects/README.md` |
| A guided tour of a phase, for the owner | `projects/big/arm32-dev-backend-walkthroughs.md` |

Contents:

1. Open
   1. Pre-existing defects (outside arm32, found by this work)
   2. Limitations of arm32 support
   3. Annoyances to fix later
   4. Follow-up ideas
2. Resolved
3. Background and history

## 1. Open

### 1.1 Pre-existing defects

#### LIR images drop the layout store's recursive-graph keys

- **Where:** `src/lir/lir_image.zig` rebuilds the layout store with an empty
  `interned_recursive_graphs` map (around `:402` and `:815`).
- **Effect:** `src/layout/digest.zig` needs those keys to end its walk through a
  recursive layout. Any consumer that hands an image to the dev backend's
  object-file path panics on the first recursive type ("layout digest: cyclic
  layout N has no recursive-graph key"). Nothing does that today; the eval
  runner's hash oracle hit it and now compiles the live lowering instead.
- **Fix direction:** serialize the keys into the image. Making the digest
  tolerate their absence would be a fallback.

#### `abs64` patching is sized by the host, not the relocation

**Status: open.** Unchanged; arm32 code does not reach it because it uses the
explicit `abs32` kind.

- **Where:** `src/backend/dev/Relocation.zig`, `patchAbsolutePointerOperand`.
- **Effect:** an `abs64` relocation writes four bytes when the *compiler host*
  has a 32-bit `usize`. The relocation kind should decide the width; on an
  arm32 host (J3a) this would silently narrow 64-bit fields.
- **Fix direction:** arm32 code uses the explicit `abs32` kind (added in A3);
  `abs64` should always write eight bytes.

#### The snapshot tool hashes programs that failed to type-check

- **Where:** `src/snapshot_tool/main.zig`, `type=dev_object` snapshots.
- **Effect:** a type error turns the definition into `<runtime_error>` in the
  MONO section and the tool still hashes the object, with no diagnostic. A
  new snapshot can lock in a broken program without anyone noticing.
- **Fix direction:** report problems for `dev_object` snapshots (as other
  snapshot types do) or refuse to hash a program with errors.

#### Procedure symbol names change with every compiler build

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

#### glibc stub still emits `ret` for non-x86/aarch64/arm architectures

- **Where:** `src/build/glibc_stub.zig`.
- **Effect:** arm now gets real A32 bodies, but `aarch64_be`, `wasm32` and
  `other` still emit `ret`, which is not an instruction on most of them. Only
  reached for glibc cross targets, none of which use those architectures.

#### wasm32 wraps `U64` sublist indices to 32 bits (confirmed miscompile)

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

#### `list_get_unsafe` accepts an index in an i128 location

- **Where:** `src/backend/dev/LirCodeGen.zig`, the `.list_get_unsafe` handler's
  index materialization (`.stack_i128` and `.immediate_i128` arms, commented
  "Dec/i128 index - just load the low" part).
- **Effect:** a list index is `U64` in LIR, so an i128/Dec location there is a
  producer bug; the handler silently truncates it instead of reporting the
  invariant violation. That is best-effort recovery in a compiler stage.
- **Fix direction:** make those arms invariant failures.

#### A U64 discriminant loaded as eight bytes

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

#### A string result stored from one register

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

#### Redundant narrowing before byte stores

- **Where:** `src/backend/dev/LirCodeGen.zig`, `storeResultToSavedPtr`'s `.u8`
  and `.i8` arms.
- **Effect:** each shifts the register left and right by `word_bits - 8`
  before `emitStoreScalarToPtr(..., 1)`, which stores only the low byte, so
  the two shifts are dead work. Harmless; left in place because Track A
  changes must be byte-identical. A cleanup can drop them with a regenerated
  hash file.

#### The branch compiler panics type-checking basic-cli 0.22.2

**Status: open, found 2026-09-29; very likely fixed upstream already.**

- **Symptom:** `roc check` of any app using basic-cli 0.22.2 panics in the
  type checker: "trying to add var at rank 5, but current rank is 4". The
  nightly compiler (`release-fast-9927ba85`) checks the same app cleanly.
- **Where:** the type checker, which the arm32 work does not touch, so the
  bug belongs to the upstream base the branch sits on (`58508d582b`), not to
  arm32.
- **Next:** recheck after catching up with upstream (part 4 of the
  verification plan); if it still panics there, reduce it and report it
  upstream.

#### git-lints pads a file name with NUL bytes

**Status: open (cosmetic), found 2026-09-29.**

- **Where:** the "src/ file never imported" message of
  `zig build run-check-git-lints` (`tidy --git-lints`).
- **Effect:** the file name is followed by NUL bytes up to a fixed width
  instead of spaces, so the output is binary to `grep` and shows as a gap in
  terminals. Probably a fixed-size, zero-filled buffer printed whole.
- **Fix direction:** print only the used part of the buffer, or pad with
  spaces.

### 1.2 Limitations of arm32 support

#### The wasm eval oracle cannot run in a 32-bit process

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

#### The driver still names mnemonics and register literals

**Status: open, found by the acceptance checks (2026-09-29); needs a
decision, recorded here rather than silently counted as met.**

- **The criteria:** A1 (and the plan's correctness ideal) require
  `rg 'codegen\.emit\.' src/backend/dev/LirCodeGen.zig` and A1's
  register-literal search to return nothing: the driver would call only
  facade methods and name no ISA register.
- **What happened:** A1's amendment kept the lowering *strategies* (i128,
  SIMD, checked multiply, entry wrappers) out of the facade and deferred their
  signatures "to A2 and the NEON batch". Neither added them. J1 instead gave
  those sites `.arm32 =>` arms with raw `self.codegen.emit.` calls in
  exhaustive switches. So the raw calls grew from 502 at A1 to 611 at J1,
  and 136 register literals remain. DESIGN.md's status table still says
  "deferred to A2 and the NEON batch".
- **What still holds:** the safety property the criteria were for. Every
  architecture decision is an exhaustive switch or a `binaryIs` test, so a
  missing arm32 path is a compile error, never a silent fall-through.
- **Why it matters:** maintainers reviewing `LirCodeGen.zig` will see
  three-way switches with ISA mnemonics in the shared driver, which the
  plan said would not be there.
- **Options:** (a) define facade signatures for the strategy families
  (i128 by pointer, `Wide64` pairs, NEON kernels) and move the arms into the
  per-ISA `CodeGen`s, a large but mechanical refactor that must keep both
  byte-identity oracles unchanged; or (b) amend the plan: the driver may
  contain per-ISA arms inside exhaustive switches, with the rationale above,
  recorded in DESIGN.md. Worth raising with the maintainers before choosing.
- **Trade-offs in detail:** `arm32-dev-backend-facade-decision.md`
  (measurements, four options, a comparison table and a recommendation).

#### The interpreter's hosted-call trampoline assumes a 64-bit host

**Status: open, and worse than first recorded (found by reading
`interpreter.zig`, not yet run).** On an arm32 host `host_trampoline.available`
is false (since `ecf471509f`, J1b), but the interpreter does not refuse the
call: it falls through to the "uniform" hosted ABI, calling the function as
`fn (args_buf, ret_buf)`. Only platforms written for that ABI (the echo
platform, for wasm32) register functions of that shape; an ordinary platform
registers C-ABI functions, so an interpreter running on arm32 calls them with
the wrong arguments. It is reached only by a compiler built for arm32 and run
there with the interpreter; `roc build --opt=interpreter` refuses non-native
targets, and the eval runners dispatch hosted calls through a callback, so
none of the J3 runs exercised it.

- **Where:** `src/eval/host_trampoline.zig`, the ABI target selection, and
  `src/eval/host_trampoline.S`.
- **Effect:** any host that is not aarch64 is treated as x86_64 SysV, so an
  interpreter running *on* arm32 (the Track D/J3a lane) would marshal hosted
  calls with the wrong ABI; the trampoline also carries 64-bit registers and
  has no A32 entry. The J3a baseline's 51 passing cases make no hosted call.
- **Fix direction:** an explicit arm32 selection (`layout.abi.Target.arm32`,
  which now exists) and an A32 trampoline, or an explicit refusal on hosts the
  trampoline does not implement, before J3 makes the lane required.

**Plan, step 1: refuse instead of calling the wrong way (do now).**

The uniform `(args_buf, ret_buf)` ABI is a wasm32 contract: the echo platform
chooses its shape by `is_wasm`, not by `host_trampoline.available`, so every
platform registers C-ABI functions on every other architecture. Restricting
the uniform path to wasm32 therefore breaks nothing that works today.

1. In `interpreter.zig`'s hosted-call dispatch, keep the three existing
   branches (the `hosted_call_handler` callback, the trampoline when
   `host_trampoline.available`, the uniform call) but take the uniform branch
   only when the compiler runs on wasm32 (`builtin.cpu.arch == .wasm32`, the
   same condition as the echo platform's `is_wasm`; better, one shared
   constant both use).
2. Add a fourth branch for every other architecture without a trampoline
   (today: arm32 and 32-bit x86): an explicit error that names the
   architecture and says the interpreter cannot call hosted functions there,
   through the interpreter's existing error reporting, not a panic. Decide
   while writing it whether this is a user-facing error (a compiler built for
   that host is a supported configuration) or an invariant failure; the
   former is right if arm32-hosted compilers are shipped.
3. Update the comments at the uniform branch and at `echoLineHostedFn` so
   both state the same rule.
4. Tests: a unit test that the dispatch selects the refusal on a
   non-wasm, non-trampoline architecture (a comptime selection function
   that takes the architecture, so it can be tested for arm on an x86_64
   host). End to end: a compiler built for arm32
   (`zig build roc -Dtarget=arm-linux-musleabihf`), run under qemu and on the
   Raspberry Pi 5, prints the error for `roc --opt=interpreter
   test/fx/hello_world.roc` instead of misbehaving.
5. One commit, a fix to existing code: an entry under "Fixes to existing
   defects" in the existing-code-changes note, and this entry's status
   updated to "refuses cleanly; A32 trampoline open".

**Plan, step 2: an A32 trampoline (only if the maintainers want the compiler
to run on 32-bit ARM).**

Scope question first: the arm32 plan made arm32 a *target*; the compiler ran
on arm32 only for the test runners. Raise it with the maintainers together
with the rest of the arm32 work. If they want it:

1. **Control block.** `Call` today fixes 64-bit registers (`gp: [8]u64`,
   `sse: [8]u128`) and the assembly hardcodes 8-byte field offsets. Make the
   register images per-architecture (arm32: four `u32` core registers, eight
   `f64` VFP double registers, the stack area, `sret`, results r0-r3 and
   d0-d3), and derive the assembly's offsets from `@offsetOf` with comptime
   assertions next to the struct, so the Zig and assembly layouts cannot
   drift.
2. **Classification.** Reuse `layout.abi.Target.arm32` (J1b's AAPCS32
   classifier, including C.5 splits between r3 and the stack and VFP
   back-filling) through `abi.lower`, as x86_64 and aarch64 do. The
   scatter code maps each placement to the arm32 images (a `u64` in an even
   register pair, an `f32` into an S register view of a D image).
3. **Assembly (`host_trampoline.S`, an `__arm__` section).** `push {r4, r5,
   fp, lr}`; keep the control block in r4; if there are stack arguments,
   reserve them keeping SP 8-byte aligned and copy the bytes; `vldmia` d0-d7;
   `ldmia` r0-r3; `blx` the target; store r0-r3 and `vstmia` d0-d3 into the
   result images; restore and return. A32, hard-float, no NEON needed.
4. **Results.** AAPCS32 returns up to four bytes of a composite in r0, a
   64-bit integer in r0:r1, a homogeneous float aggregate of up to four
   members in d0-d3 / s0-s3, and anything else through a hidden pointer in
   r0. The gather code follows the classifier, as for the other ISAs.
5. **Tests.** There is no execution test of the trampoline today (only a
   text check of the assembly and a layout test). Add one that calls Zig
   `callconv(.c)` functions through `host_trampoline.call` for each
   J3 call shape (`test/fx/abi_call_shapes.roc`'s list: an i64 after an i32,
   an i64 on the stack, a 12-byte record split by C.5, an f32 back-fill, nine
   f64s, a hidden result pointer, an F64 -> I64 -> F64 round trip), on every
   architecture with a trampoline, so x86_64 and aarch64 gain coverage too.
   Put it in a small test module if the eval module's test binary is too
   large to link or run for arm32. End to end: the fx suite with
   `--opt=interpreter` from a compiler built for arm32, under qemu and on the
   Pi 5.
6. **Commits.** The control-block generalization (byte-identical behaviour on
   x86_64/aarch64) first, with the execution tests; then the A32 stub and
   `available` turned on for arm. Remove step 1's refusal for arm in the
   second commit.

Risks: the eval module's arm32 test binary may be too large (see "A Debug
arm32 eval runner does not link"); VFP register images must be saved as
doubles and addressed as singles for f32 arguments; and the stub has no
unwind information, so a crash inside a hosted function shows no frames
through the trampoline (true for the existing ISAs too).

#### Building the arm32 eval runners needs 18 GB, more than CI runners have

**Status: fix prepared (2026-09-30), to be confirmed by a CI run of the
lane.** The CI step now builds the runners in ReleaseSmall (results below).
Before: **open, confirmed in CI.** In the first full run on the public fork
(run 36494296904, 2026-09-29) the lane's runner died: "The hosted runner lost
communication with the server… starves it for CPU/Memory". Upstream's own
nightly loses its `arm-linux-musleabihf` job the same way.

- **Where:** `.github/workflows/ci_zig.yml`, step "Build the eval runner for
  arm32" (`zig build build-test-eval-runner build-test-eval-host-effects-runner
  -Dtarget=arm-linux-musleabihf -Doptimize=ReleaseFast`), on GitHub-hosted
  `ubuntu-24.04`.
- **Measured** (`--summary all`, 2026-09-27, x86_64 desktop): compiling
  `eval-test-runner` for arm32 peaks at **18 GB** resident (14 minutes),
  `eval-host-effects-runner` at **11 GB** (8 minutes); every other step
  stays under 1 GB. The two build in parallel by default, so the step needs
  about 29 GB at peak.
- **Effect:** GitHub's standard hosted Linux runners have 16 GB on public
  repositories (and less for private ones), so the lane J3a made required
  will very likely fail from lack of memory on its first CI run. A Raspberry Pi 5
  (8 GB) rebooted trying the same build with four jobs, and cannot build it
  even one step at a time.
- **Fix directions, to investigate in this order:**
  1. The cheap check first: build the two runners one at a time (`-j1`) and
     see whether the larger one (18 GB) fits in the hosted runner's 16 GB
     plus its swap. If it does, this alone may fix the lane.
  2. Find what takes 18 GB (the LLVM-backend oracle linked into the runner,
     or Zig's own ReleaseFast code generation of one huge compilation unit)
     and whether a build option that leaves out the LLVM backend, or
     `-Doptimize=ReleaseSmall`, cuts it below the runner's memory.
  3. Build them on a larger GitHub-hosted runner (which costs money even on
     a public repository) and pass the binaries to the job that runs them
     under qemu. Not on the owner's own machines: no CI runners there.
  Whatever the fix, confirm it with `--summary all` (MaxRSS per step) before
  relying on CI.

**Analysis (2026-09-29, from `build.zig`, no builds yet).**

- `eval-test-runner` is one ReleaseFast compilation of the whole compiler
  (`roc_modules`), the test harness, bytebox and the SIMD corpus, plus
  LLVM: `addLlvmSupportToStep` links LLVM's static libraries and C++ glue and
  adds the `llvm_codegen`/`llvm_compile` modules whenever prebuilt LLVM exists
  for the target, which it does for arm32. There is no option to leave it out.
- **The runner never uses LLVM in this lane.** Its LLVM eval backend is
  opt-in (`--include-llvm`, off by default; `parallel_runner.zig`), and the
  arm32 lane does not pass it. So every arm32 build compiles and links all
  of LLVM for nothing.
- Leaving LLVM out is not only a build switch: the `eval` module imports
  `llvm_compile`, so the evaluator would need to compile without it (a
  comptime-known "LLVM linked" option, with the LLVM backend reporting
  unavailable, as the wasm backend does on 32-bit hosts).
- The 18 GB is the peak of one `compile exe` step, which includes Zig's own
  code generation and optimization through LLVM and the in-process link.
  Which of the two dominates is not known yet.

**Plan.** Every experiment runs inside a simulated hosted runner on the
desktop (`systemd-run --user --scope -p MemoryMax=16G -p MemorySwapMax=4G`;
the desktop delegates the memory controller), so an overrun kills the build,
not the machine. Each records peak memory with `--summary all`. Run when the
per-commit sweep is not using the desktop, or on the owner's larger Linux
machine.

1. **Sequential (`-j1`):** does the 18 GB build fit in 16 GB plus 4 GB swap
   when built alone? If yes, changing the CI step to build the two runners
   one at a time may be enough, at the cost of a slower lane.
2. **Where the memory goes:** the same build with `-femit-llvm-ir` off and
   a Zig time report, and the arm32 `roc` executable alone (the compiler
   plus LLVM, without the test runner). If `roc` alone is close to 18 GB,
   the test code is not the problem; if it is far below, the runner's extra
   modules are.
3. **Optimize mode:** the same build in ReleaseSmall and ReleaseSafe. The
   lane needs the runner to run the corpus in reasonable time, not maximum
   speed, so ReleaseSmall is acceptable if it fits.
4. **Without LLVM:** a build option that keeps LLVM out of the eval runners
   for the arm32 lane (the change described above). Likely the largest
   saving, but a real code change to existing modules, so only if 1-3 do not
   suffice.

The fix is chosen from the smallest change that fits with margin, confirmed
by a CI run of the lane.

**Results (2026-09-30, desktop, inside `systemd-run -p MemoryMax=16G -p
MemorySwapMax=4G`, fresh cache, peak memory from `--summary all`):**

| Experiment | `eval-test-runner` | `eval-host-effects-runner` | Build time | Verdict |
|---|---|---|---|---|
| ReleaseFast, both at once (before) | 18 GB | 11 GB | (29 GB together) | does not fit |
| 1: ReleaseFast, `-j1` | 17 GB | 12 GB | 22 min | fits only by swapping; too thin |
| 3: ReleaseSmall, `-j1` | 8 GB | 5 GB | 10 min | fits with a wide margin, even both at once (13 GB) |

The ReleaseSmall runners pass the whole corpus under qemu `cortex-a9`:
2171/2171 in 19.9 minutes (ReleaseFast: 15.6 minutes, both with six
threads) and host effects 86/86. So the fix is one flag in the CI step
(`-Doptimize=ReleaseSmall`); experiments 2 and 4 were not needed.
Experiment 4 (leaving LLVM out of the arm32 eval runners) stays a possible
improvement: the lane never uses LLVM.

#### A Debug arm32 eval runner does not link

`zig build build-test-eval-runner -Dtarget=arm-linux-musleabihf` in Debug
fails in LLD: "InputSection too large for range extension thunk". The runner
links LLVM, and a Debug A32 image is larger than a B/BL range extension
thunk can span. The plan's J3a acceptance measures D10 in "the Debug runner
build"; J3a used ReleaseFast (as the CI lane does) and ReleaseSafe instead.
That still checks D10: exhausting a register pool is a `std.debug.panic` in
every build mode, not an assertion that Release builds drop.

#### Two eval tests need more memory than a 1 GB board has

**Status: open for 1 GB boards only.** On a Raspberry Pi 5 (8 GB, 64-bit
kernel) both tests pass: the full corpus runs 2171/2171 there
(2026-09-27, at `e3457476ca`).

"inspect: inclusive numeric ranges all iterate" and "inspect: exclusive
numeric ranges all iterate" compile ten `Iter.fold` range pipelines, one per
integer width. Compiling them peaks at about 1.25 GB resident on x86_64 and
870 MB in an arm32 build (under qemu). On the Raspberry Pi 3 (920 MB RAM plus
zram swap) they fail with OutOfMemory during compilation, even with one
worker; every other test passes there. This is the compiler front end's
memory use, not arm32 code generation.

Follow-up idea: see "Report peak memory per test" under follow-up ideas.

#### Zig 0.16 passes nested `extern struct` arguments off-ABI on arm

**Status: open (a Zig bug), worked around in the fx test host.**

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

#### A `u64` builtin parameter passed as one register is not caught

**Status: open (a standing rule).** Nothing checks it mechanically yet.

On arm32 a builtin's `u64` parameter takes an aligned register pair. A call
site that passes one with `addImmArg` or `addRegArg` builds a single-register
argument; for an immediate that fits 32 bits nothing fails at build time
(`CallBuilder` rejects only immediates wider than a word). J2 audited every
wrapper with 64-bit parameters (`dev_wrappers.zig`, `boxy_abi.zig`) and moved
their call sites to `addU64SlotArg`, `addImm64Arg` or `addMem64Arg`; a new
builtin with a `u64` parameter needs the same.

### 1.3 Annoyances to fix later

Small frictions met while working, none blocking. Each says where it belongs.
Fix each one in its own commit, and remove its entry in that commit.

- **Line-number exclusions in build.zig's pattern checks go stale.** The
  type-checker pattern check (`excluded_ranges` in `build.zig`, two tables)
  excludes lines of `inspected.zig`, `Check.zig`, `store.zig`,
  `cir_to_lir.zig` and `utils.zig` by number, so any edit above an excluded
  line breaks CI (J3a shifted `inspected.zig` by one line). Two of the
  `inspected.zig` ranges (2475 and 3265-3276) already point at unrelated
  lines, so whatever they meant to allow is no longer allowed or needed.
  Fix: replace the tables with a marker comment on each allowed line (for
  example `// pattern-check: allow cross-module name match`) that the
  scanner looks for. The reason then sits next to the code, and edits
  elsewhere cannot move it. Audit each current range while converting it,
  and drop the stale ones.
- **minici stops at the first failing phase and rebuilds everything first.**
  A full run spends about 15 minutes in `build-ci` before the first check,
  so each quick lint failure costs a full cycle. Run the `run-check-*`
  phases directly first, and resume with `--minici-after <phase>`.
- **Building the test platforms deletes the user's whole Roc cache.**
  `ClearRocCacheStep` in `build.zig` (upstream code, run before the test
  platforms are rebuilt) calls `deleteTree` on `~/.cache/roc` (or
  `$XDG_CACHE_HOME/roc`), which also holds downloaded packages such as
  basic-cli. The A1 `run-test-cli` run on 2026-09-30 wiped them, and the
  next `roc` run of the verify tools re-downloaded basic-cli.
  `ROC_CACHE_DIR` does not help: it moves only the build cache, not
  packages. Workaround until fixed: run repo builds with `XDG_CACHE_HOME`
  pointing at a scratch directory. Fix (upstream): clear only the build
  cache's host entries the step means to invalidate, never packages.
- **Debugging arm32 failures is slow** (plan for a fix below). Two separate
  problems:
  - *Unit-test binaries print no stack traces.* This is not an arm or qemu
    limitation: `src/build/unit_test_runner.zig` sets
    `allow_stack_tracing = build_options.debug_gpa_traces`, which defaults
    to off because capturing allocation traces dominates Debug test time.
    `-Ddebug-gpa-traces` turns panic and error-return traces back on for
    every target. The fx host sets `.allow_stack_tracing = false` too.
  - *The eval runner has no Debug arm32 build.* It fails to link ("InputSection
    too large for range extension thunk"; see "A Debug arm32 eval runner does
    not link"). ReleaseFast has no traces and no safety checks, so J3a
    debugging used a separate ReleaseSafe build (about 20 minutes).

  **Plan.** Take these in order and stop once debugging is fast enough.
  1. Done: `-Ddebug-gpa-traces` gives arm32 unit tests error-return traces
     with source lines under qemu (verified with a throwaway failing test),
     documented in `src/backend/dev/arm32/TOOLS.md`.
  2. Make the Debug arm32 eval runner link. A32 `BL` reaches ±32 MB, and LLD
     can only place range-extension thunks between input sections. The eval
     runner is one Zig compilation unit whose `.text` is a single input
     section larger than that. `roc` and several objects in `build.zig`
     already set `link_function_sections = true`. Setting it for the eval
     runners (at least for arm targets) splits `.text` per function, which
     should let LLD place thunks. If it works, the Debug runner gives safety
     checks and traces with no separate ReleaseSafe build, and J3a's
     acceptance ("the Debug runner build's D10 high-water mark") can be met
     as the plan wrote it. Risk: the build may still be slow or large; for
     x86_64 and aarch64 the setting only changes section layout, but it
     needs a check that it does not slow host builds noticeably.
  3. If 2 fails, add a build step (for example
     `build-test-eval-runner-arm32-safe`) that builds the ReleaseSafe runners
     into their own prefix, so nobody overwrites `zig-out/bin` with arm
     binaries by accident (which happened during J3a).

  **Alternatives considered.**
  - *gdb through qemu's gdb stub* (`qemu-arm-static -g <port>` with an
    arm-capable gdb). It gives full debugging, but the local gdb is
    x86_64-only (`gdb-multiarch` would be needed), and it steps one process,
    while the eval runner forks a child per test. Useful for one hard bug, not
    as the everyday path.
  - *Native gdb on the board.* The Pi has gdb, and the Pi 5 will be fast
    enough. It needs the program copied over and has the same fork problem.
    Good for hardware-only bugs.
  - *Symbolizing raw return addresses offline.* The panic handler would print
    addresses and `llvm-symbolizer` would resolve them against the unstripped
    binary. That only duplicates what `allow_stack_tracing` already does once
    it is on.
  - *Running arm32 tests only on the board.* It avoids qemu, but CI and most
    contributors have no board, so qemu stays the primary path.
- **`.zig-cache` fills the disk during cross builds** (above). A periodic
  full clear, or a separate `--cache-dir` for arm32 cross builds that can be
  deleted wholesale, would avoid it.
- **The int app prints heap addresses,** so comparing its stdout across
  targets needs masking. `test/int/platform/host.zig` prints
  `init returned Box: 0x{x}` and `update returned new Box: 0x{x}`, and the
  J3c lane in `ci_cross_compile.yml` masks `0x...` before diffing. Fix:
  print that the box is non-null (for example `init returned a Box`), and
  check the address in the host instead if it matters. Then remove the
  `sed` masking from the J3c step in the same commit.
- **The wasm eval oracle is off on 32-bit hosts** (see "The wasm eval oracle
  cannot run in a 32-bit process" above for the cause and the options). The
  fix belongs in bytebox's memory reservation; remove the gate in
  `eval.backendAvailable` in the same commit.
- **Probe apps that read stdin block without input.** Any ad-hoc
  build-and-run script must redirect stdin (`</dev/null`) and use a timeout.

### 1.4 Follow-up ideas

#### Report peak memory per test

Report
peak memory per test in the eval runner, next to its per-phase timing. The
runner already forks a child per test, and on POSIX `wait4` returns the
child's `ru_maxrss`, so a "largest memory" list like the "slowest tests" list
costs almost nothing and would have found these two tests before a 1 GB
board did. Open questions for that project: report only or enforce limits
(limits are flaky across allocators and hosts), attributing compile vs run
memory (needs measuring inside the child), and Windows (a different query).

#### Stop committing prebuilt binaries (owner's intention, security)

**Status: planned for after the arm32 work lands; until then the arm32
work follows Roc's current practice.** Decided by the owner 2026-09-29.

- **What:** the repository commits prebuilt binaries that tests link: at
  the arm32 work's base about 100 files (`crt1.o` and `libc.a` per musl
  target in the fx, int and str test platforms, glibc stub files per glibc
  target, and 24 `.lib` import libraries per mingw target). The arm32 work
  adds five in the same pattern: `crt1.o` and `libc.a` for `arm32musl` in
  the fx and int platforms, and `Scrt1.o` for `arm32linux`.
- **Why change it:** a binary in the tree cannot be reviewed. The xz-utils
  backdoor (CVE-2024-3094) hid its payload in binary "test files" that
  reviewers could not read; a tampered `libc.a` or `crt1.o` here would be
  linked into every test program built for that target. Readable sources plus
  a build step leave nothing opaque in the history.
- **Direction:** generate the files at build time from Zig's own sources
  (`ci/vendor_musl_runtime.py` already does this for arm32; the other targets
  need the same), list them in `.gitignore`, and delete the committed copies.
  Points to settle:
  - Zig's `libc.a` is not byte-reproducible (members are named by absolute
    cache paths), so either normalize the archive when generating it or stop
    relying on byte comparisons of it.
  - Build time: generate once per target and cache.
  - The mingw `.lib` files come from a different source (import libraries),
    so they need their own generator.
  - Until then, a CI check that regenerates the committed files and compares
    them (after normalizing) would at least detect tampering.
- **Scope:** a change to every target, so it is proposed to the maintainers
  as its own pull request, not bundled with the arm32 work.

## 2. Resolved

#### In-process relocation patching guesses the encoding

**Status: resolved in `e865de0a8a`** (J3a). Relocation patching takes the ISA
the code was generated for and patches each site by that ISA's rule; arm32
patches A32 `bl`/`b`.

- **Where:** `src/backend/dev/Relocation.zig`, `patchLinkedFunctionRelocation`.
- **Effect:** it picks x86 `call rel32` or AArch64 `BL` by decoding the bytes
  around the relocation (`0xE8` before the offset, or the `BL` opcode bits)
  instead of carrying an explicit relocation kind. That is recovering missing
  information in a compiler stage, which AGENTS.md forbids, and it cannot be
  extended to A32 `BL` without adding a third guess.
- **Fix direction:** give function relocations an explicit encoding kind, as
  `DataRelocationKind` does for data. Needed before J3a runs arm32 code
  in-process.

#### A backend unit test wrote to stderr, failing `zig build`

- **Where:** `wasm.WasmModule` test "mergeModule rejects same-name imports with
  different signatures" printed "WASM merge: both modules import 'roc_crashed'".
- **Effect:** `zig build run-test-zig-module-backend` reported failure although
  the binary reported every test passed.
- **Resolved in `1138ce4c33`:** the merge records the conflicting function in
  `WasmModule.merge_type_conflict` instead of printing it, and the test
  asserts the recorded conflict. The step passes, on the host and for arm32
  under `-fqemu`.

#### A checked I64 multiply took 10 of arm32's 11 temporaries

**Status: resolved in `c36fd3b6ea`** (J2).

`emitWide64MulChecked` held both operand pairs, the result pair and four
partial-product registers at once, and J2's D10 measurement saw the general
pool reach 11 / 11 there. It now leaves the operands in their memory slots and
loads one word at a time into two scratch registers, so it holds 8 registers
at most. Over everything J2 builds, the arm32 general peak is now 9 / 11 (see
the register budget section of `src/backend/dev/arm32/DESIGN.md`).

#### Shim execution did not resolve `__aeabi_*`

**Status: resolved in `c68e88c823`** (J3a).

`callAeabiHelper` emits a relocation to the helper's name in shim mode, like
every other runtime symbol. `native_runtime_libcalls.resolve` now binds those
names to the compiler's own compiler-rt when the compiler runs on arm32, so
in-process linking (HostSplice, the machine-code shim) resolves them.

#### Test skip guards are keyed on the host architecture

**Status: resolved in `894650cd4e`** (J3a): the tests skip on
`host_lir_codegen_available`, and all of them run and pass on an arm32 host
under qemu.

`LirCodeGen.zig` tests skip unless `builtin.cpu.arch` is x86_64 or aarch64
instead of consulting `host_lir_codegen_available`. The plan's J3a rewrites
them.

#### Target data laid out with the host's word

**Status: resolved in `f4af9e372d`.**

Code generation sometimes sizes *target* data with the *host's* `usize`, which
is right only while host and target share a word size (every target before
arm32). Fixed (`f4af9e372d`): `@alignOf(usize)` in the Debug RocStr validity
check and `@sizeOf(usize)` in the erased-call descriptor array and the
erased-callable drop-pointer slot; and every use of
`builtins.erased_callable`'s host layouts (`Payload`, `capture_offset`,
`HotReloadCaptureHeader`, `CompilerMetadata`), now derived for the target word
by `erased_layout` in `LirCodeGen`.

#### Smaller items resolved during the work

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
- **Two-way arch tests would have misrouted arm32:** about 250
  `arch == .x86_64` / `== .aarch64` tests in the driver, `FrameBuilder` and
  `CallingConvention` (some with no final `else`) now go through `Isa`, which
  refuses to compile for arm32.

## 3. Background and history

#### The 64-bit register budget is nearly exhausted already

**Status: background.** Still true for x86_64; arm32's measured peaks and the
lowerings that keep it within 11 are in DESIGN.md's register budget section.

Over the eval corpus, instruction selection peaks at 12 of 13 allocatable
general registers on x86_64 (12 of 25 on aarch64), pinned registers included.
arm32 has 11, with 64-bit values taking two each. Existing sequences cannot be
reused on arm32 (D10), and x86_64 itself is one register from an invariant
panic.

#### Width bugs in shared native code have never been exercised

**Status: history.** J1-J3 exercised that code at 32-bit width; the bugs it
found are fixed and listed in `arm32-dev-backend-existing-code-changes.md`.

wasm32 is the only 32-bit target today and it shares no code generation with
the dev backend. The first 32-bit native target will be the first to run the
shared native code (object writing, relocation widths, DWARF, the driver's
literal 8s) at 32-bit width.

#### Baseline of the arm32 eval lane before J1

**Status: history.** J3a ended at 2171/2171 under qemu.

`zig build build-test-eval-runner -Dtarget=arm-linux-musleabihf
-Doptimize=ReleaseFast`, run with `qemu-arm-static -cpu cortex-a9 ...
--timeout 300000` (2026-09-25): 51 passed, 2120 failed, 0 crashed. Every
failure is `UnsupportedPlatform` (the dev backend has no arm32 code
generator), so the compiler's front end and interpreter already run on a
32-bit host; J1-J3 turn the failures into passes.

#### `test/fx` on arm32 (J3b)

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

#### Cross-built compilers fill `.zig-cache` quickly

Each arm32 build of the eval runner leaves a 250-400 MB LLVM-linked binary in
`.zig-cache/o`. During J3a the cache reached 229 GB and filled the disk.
Deleting part of `.zig-cache/o` leaves manifests pointing at missing files,
and Zig does not recover ("failed to check cache: FileNotFound"), so clear
the whole directory instead.

#### Tooling notes

- JIT code cannot be a golden oracle: it embeds absolute host addresses.
- `libc.a` from Zig's musl is not byte-reproducible (members are named by
  absolute cache paths), and Zig's cache holds two `crt1.o` builds per arm
  triple; `ci/vendor_musl_runtime.py` takes the one the link line names.
- The eval-corpus hash check costs about four minutes on sixteen cores, mostly
  re-checking the Builtin module for each case.
- The plan's claim that `roc build --help` names `dev` as the default `--opt`
  is stale: it names `speed`.
