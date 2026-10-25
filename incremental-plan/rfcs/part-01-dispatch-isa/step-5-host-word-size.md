# Fold step 2, step 5 of 9: draft 07, host word size

Branch `dispatch/isa`, six commits on top of step 4. The hashes are the ones
at the time of writing.

| Commit | Source | Subject |
|---|---|---|
| `9c6a25e452` | reference `cede2ab5b7` | Size target data by the target's word in the dev backend driver |
| `772baf1e39` | reference `2aecaa5529` | Lay out erased-callable payloads by the target's word |
| `7e4b27d5ff` | new | Check the hot-reload capture prefix against the target's layout |
| `6f2b3a4efc` | new | Size new erased-callable payloads by the target's layout |
| `8ea2423294` | reference `be8a417829` | Report the wasm eval backend unavailable on 32-bit hosts |
| `e65824d17e` | new | Skip CLI tests that instantiate wasm32 output on 32-bit hosts |

The three reference commits keep their original author dates.

## Terms

- **Host:** the machine running the compiler. **Target:** the machine the
  compiled program runs on.
- **Word size:** the size of a memory address: 8 bytes on 64-bit machines,
  4 on 32-bit ARM and wasm32.
- **Erased callable:** Roc's runtime form of a function value. It lives in a
  heap block: a pointer to the code, a pointer to a cleanup function, the
  captured values, then a trailer of compiler metadata.
- **bytebox:** the WebAssembly interpreter the tests use to run wasm output.

## Why

The dev backend generates code that reads and writes memory on the target,
but in several places it measured that memory with the host's word size.
Today every host that runs the dev backend is 64-bit, and the driver still requires an 8-byte
target word (`LirCodeGen.zig:503`), so the two always agree and nothing
changes in the output. Once a 64-bit compiler builds for 32-bit ARM, they
differ, and the compiler would write fields where the arm32 runtime doesn't
look. These commits make those places use the target's sizes, so the arm32
steps start from correct offsets.

The last two commits are about running the compiler's tests on a 32-bit
machine (the Pi 3, part 11 `arm32/host`). bytebox reserves 4 GiB for a wasm
module with no memory maximum, which a 32-bit process cannot hold, so every
wasm test would fail there for a reason unrelated to the code under test.

## What changed

- **`9c6a25e452`:** six sites in `LirCodeGen.zig` use `target_ptr_size`
  instead of `@sizeOf(usize)` or `@alignOf(usize)`: the Debug RocStr
  alignment checks, the erased-call descriptor array, and the drop-pointer
  offset.
- **`772baf1e39`:** new `erased_layout` helper in `LirCodeGen`. It scales
  the `builtins.erased_callable` structs by the target word, with a
  compile-time check that every field is pointer-sized. The payload writes,
  the capture offset and the startup registration of frozen procedures use
  it.
- **`7e4b27d5ff`:** the Debug check on the hot-reload capture prefix
  compares against `erased_layout`'s value.
- **`6f2b3a4efc`:** the allocation size for a new erased callable comes from
  `erased_layout` instead of `builtins.erased_callable.compilerPayloadSize`.
- **`8ea2423294`:** `backendAvailable(.wasm)` is false for a 32-bit process
  outside freestanding builds, and the eval runner asks it instead of
  assuming wasm works.
- **`e65824d17e`:** three CLI tests and the wasm32 glue runtime cases,
  which instantiate wasm32 output under bytebox, report themselves skipped
  on 32-bit hosts.

## How the reference commits were adapted

- Upstream renamed emit calls since the reference commits
  (`emitAndRegs` → `emitAnd`, `self.codegen.emitStore` → `self.emitStore`).
  Upstream's names were kept.
- The reference's `word_size` doesn't exist upstream. Upstream already has
  the same value as `target_ptr_size`, so that name is used.
- `2aecaa5529` also edited two `projects/big/` notes files. They were left
  out.
- Upstream now passes the hot-reload prefix in as data
  (`self.erased_capture_prefix`, from LIR) where the reference used
  `enable_hot_reload` plus a constant. Upstream's design was kept.
- Zig 0.17 has no `@typeInfo(T).@"struct".fields`, so `erased_layout`'s
  field check loops over `field_names` and `field_types`.
- Upstream keeps wasm available in freestanding builds (the compiler built
  as WebAssembly), which never run bytebox. The reference's
  `.wasm => @sizeOf(usize) >= 8` would have turned wasm off there too; the
  resolution keeps freestanding available.

## Review findings and outcomes

Pick 1 (`cede2ab5b7`):

- **REVIEW, applied:** the offsets now use the target word, but the stores
  next to them still write `.w64`. The message no longer implies 32-bit
  layouts are now right: it says the store widths change when the driver
  learns a 4-byte word.
- **NIT, applied:** dropped `@intCast` around `target_ptr_size` in two
  `emitStore` calls.

Pick 2 (`2aecaa5529`):

- **REVIEW, applied as its own commit (`7e4b27d5ff`):** the Debug prefix
  check still compared against the host value.
- **REVIEW, applied in the pick:** the startup registration of frozen
  procedures, added upstream after the reference commit, used the host's
  metadata alignment.
- **REVIEW, applied as its own commit (`6f2b3a4efc`):** the allocation size
  for a new erased callable used the host's sizes. The reference branch
  still has this bug.
- **REVIEW, applied:** same `.w64` caveat as pick 1, in the message.
- **REVIEW, not fixed here:** `static_data.zig:1404` also uses the host
  `capture_offset`. Recorded as draft 38, which also covers the same habit
  in the wasm code generator.

Pick 3 (`be8a417829`):

- **REVIEW, applied as its own commit (`e65824d17e`):** the CLI tests also
  run bytebox. Only `setupGlueRuntimeWasm` instantiates modules; the two
  validators only decode, which reserves nothing.
- **NIT, applied:** the comment now says "the modules the eval runner
  builds declare no memory maximum", since a module linked with a platform
  host can get one.

This doc's own review:

- **REVIEW, applied:** the last commit's message said "four CLI tests". It
  was amended to name three tests plus the wasm32 glue runtime cases, which
  turned `038c933e87` into `e65824d17e`. The code is identical, so the test
  results below, run on `038c933e87`, hold for it.

## Tests

All run on this machine (x86_64, 16 cores, `-j14`).

- `9c6a25e452`, `772baf1e39`, `7e4b27d5ff`, `6f2b3a4efc`: each tested on
  its own with `run-test-zig-module-backend`, 513 passed, 2 skipped.
- `8ea2423294`: `run-test-zig-module-eval` and `run-test-zig-module-backend`,
  584 passed, 2 skipped. `run-test-eval`: 2593 passed, 0 failed, 0 crashed,
  47 skipped, in 19½ minutes.
- `e65824d17e`: only the CLI tests it touches; the full set below covered
  the rest. 10 passed. 5 RustGlue wasm32
  glue tests failed because this machine lacks the Rust
  `wasm32-unknown-unknown` target. 1 was skipped by an existing ZigGlue
  skip. The two LLVM tests (with `--include-llvm`) failed, and fail the same
  way at upstream `3bb8f2ec6c` and `414a19203e`: drafts 39 and 40.
- Full set on the finished branch (`e65824d17e`): all passed, in about 15
  minutes: `run-check-zig-format`, `run-check-unreachable-rationale`,
  `run-test-zig-module-backend`, `roc`, `run-test-zig-module-check`,
  `run-test-zig-module-compile`, `run-test-zig-module-eval`,
  `run-test-zig-lir-inline`, `run-test-zig-snapshot-tool`,
  `run-check-snapshots`.

## Final commit messages

### `9c6a25e452`

```
Size target data by the target's word in the dev backend driver

LirCodeGen describes memory on the target, but three places measured it
with the compiler host's word:
- the Debug RocStr validity check tested allocation and bytes-pointer
  alignment against @alignOf(usize) - 1;
- the erased-call descriptor array was sized and indexed by @sizeOf(usize);
- the erased-callable heap cell stored its drop pointer at offset
  @sizeOf(usize).

All three now take these offsets and sizes from target_ptr_size. The
stores into those slots still write 64 bits, and the driver still requires
an 8-byte target word, so generated code is unchanged. The store widths
change when the driver learns a 4-byte word.
```

### `772baf1e39`

```
Lay out erased-callable payloads by the target's word

LirCodeGen laid out erased-callable payloads with builtins.erased_callable's
constants and @offsetOf/@sizeOf of its structs. Those describe the compiler
host, but the builtins that read the payload run on the target. Every such
struct holds only pointer-sized fields, so on a 32-bit target
HotReloadCaptureHeader.original_on_drop moves from 8 to 4 and
CompilerMetadata shrinks from 8 bytes to 4.

erased_layout derives these layouts from the builtins structs scaled by
target_ptr_size, with a compile-time check that every field is
pointer-sized, so a future non-pointer field fails to compile instead of
being scaled wrongly. capture_alignment (16) is the same on every target.
The metadata offset registered for frozen erased procedures uses it too.

The stores into the payload still write 64 bits, and the driver still
requires an 8-byte target word, so generated code is unchanged.
```

### `7e4b27d5ff`

```
Check the hot-reload capture prefix against the target's layout

LirCodeGen's Debug check accepted an erased capture prefix only if it was
zero or builtins.erased_callable.hot_reload_capture_prefix_size, the
compiler host's value. The prefix lies in target memory, so the check now
compares against erased_layout's target-scaled value. Both are 16 on every
target today, because the header rounds up to the 16-byte capture
alignment.
```

### `6f2b3a4efc`

```
Size new erased-callable payloads by the target's layout

The allocation for a newly packed erased callable was sized with
builtins.erased_callable.compilerPayloadSize, which adds the host's
capture_offset and the host's @sizeOf(CompilerMetadata). It is now
erased_layout.capture_offset + metadata_offset +
erased_layout.compiler_metadata_size, the layout the stores into the
payload already use. Generated code is unchanged: the two agree whenever
the target word is 8 bytes, which the driver still requires.
```

### `8ea2423294`

```
Report the wasm eval backend unavailable on 32-bit hosts

The eval runner assumed the wasm backend always works. Outside
freestanding builds, wasm programs run under bytebox, which reserves a
module's whole linear memory up front. The modules the eval runner builds
declare no memory maximum, so the reservation is wasm32's full 4 GiB,
which a 32-bit process cannot hold, and every wasm test fails there.

backendAvailable(.wasm) is now false for a 32-bit process outside
freestanding builds, and the runner asks it instead of assuming.
Freestanding builds keep wasm available: they never run bytebox.
```

### `e65824d17e`

```
Skip CLI tests that instantiate wasm32 output on 32-bit hosts

Three CLI tests and the wasm32 glue runtime cases instantiate the wasm32
modules they build under bytebox, which reserves a module's whole linear
memory at instantiation. The test platforms declare no memory maximum, so
the reservation is wasm32's full 4 GiB, which a 32-bit process cannot
hold. These tests now report themselves skipped on such hosts, as the
runner does for other host-specific tests. Tests that only decode wasm
output reserve nothing and still run everywhere.
```

## Open

- The skip branches in `8ea2423294` and `e65824d17e` only run on a 32-bit
  machine and have never been compiled. Part 11 builds them on the Pi 3.
- The `.w64` store widths next to the new target offsets change with the
  word-size steps.
- Draft 38: static data and the wasm code generator use the host's
  erased-callable constants.
- Drafts 39 and 40: two upstream CLI tests fail with `--include-llvm`, and
  upstream CI never runs them.
- The 5 RustGlue wasm32 tests need `rustup target add wasm32-unknown-unknown`
  on this machine.
- The reference branch's `backendAvailable(.wasm)` turns wasm off in
  freestanding builds. Worth fixing there.
- Index weirdness seen once during pick 1: the staged pick vanished from the
  index between a test run and the review, with the working tree intact.
  Cause unknown. Staging is now checked right before every commit.
