# ARM32 Dev Backend Tools

Reference for every tool added by the arm32 work. `GUIDE.md` shows where
each fits in testing. All Python tools need only the standard library and run
on every CI host; they find Zig as `zig` or through `$ZIG`.

## `ci/arm32_encoding_oracle.py` (with `ci/arm32_encoding_oracle.s`)

**Purpose:** proves each `arm32.Emit` emitter produces exactly LLVM's bytes,
and keeps that proof in ordinary Zig tests so `zig build test` needs no
external tool.

**Input format:** each non-comment line of `ci/arm32_encoding_oracle.s` is
`A32 assembly | Emit call`:

```
add r0, r1, r2                          | addRegRegReg(.r0, .r1, .r2)
movw r3, #0x5678; movt r3, #0x1234      | movRegImm32(.r3, 0x12345678)
movw r4, #0xfff0; movt r4, #0xfff4; add r4, pc, r4 | =pcRelAddress(.r4)
```

`;` separates the instructions of one entry, a leading `=` discards the call's
return value, and `@` starts a comment line. The Zig side is written as it
appears after `try e.`; `ModImm` and `GeneralReg` are in scope.

**Usage:**

```
python3 ci/arm32_encoding_oracle.py          # regenerate src/backend/dev/arm32/encoding_oracle_tests.zig
python3 ci/arm32_encoding_oracle.py --check  # fail if the generated file is stale
zig build run-check-arm32-encoding-oracle    # the --check mode as a build step (in minici)
```

**How it works:** assembles all entries in one file with `zig cc -target
arm-linux-musleabihf` (`.arch armv7-a`, `.fpu neon-vfpv3`, `.arm`), finds each
entry's bytes from the labels it inserts, and renders one
`expectEqualSlices` test per entry, formatted with `zig fmt`.

**Failures and what they mean:**
- "Emit methods without an oracle entry": every emitter taking `self: *Self`
  (except `init`/`deinit`) needs at least one entry.
- "an entry needs a relocation": the entry's bytes depend on the link. The
  one accepted relocation is LLVM's `R_ARM_CALL` on a `BL` to itself, whose
  in-place REL addend already equals the final bytes.
- "assembled to N bytes, expected M": an entry lists a different number of
  instructions than the assembler produced (for example an alias expanding).
- A test failing in `encoding_oracle_tests.zig`: the emitter is wrong.

## `ci/elf32_reader.py`

**Purpose:** reads little-endian ELF32 files without a cross toolchain, so
every CI host (including Windows and macOS) can inspect arm32 objects.

**Usage:**

```
python3 ci/elf32_reader.py --header FILE      # Class, Machine, Flags
python3 ci/elf32_reader.py --attributes FILE  # aeabi .ARM.attributes, one tag per line
python3 ci/elf32_reader.py --sections FILE
python3 ci/elf32_reader.py --symbols FILE
```

Flags combine. `--attributes` prints tags by name where known
(`Tag_CPU_arch: 10`, `Tag_ABI_VFP_args: 1`, ...) and `Tag_<n>` otherwise;
string-valued tags (for example LLVM's `Tag_CPU_name`) print as text. As a
library it exposes `read(path)`, `Elf32.sections`, `.symbols()`,
`.rel_entries(section)` and `.arm_attributes()`; the oracle and the link smoke
test import it.

## `ci/arm32_link_smoke.py` (with `src/backend/dev/arm32_link_smoke.zig`)

**Purpose:** the end-to-end check below code generation: the encoder, the
ELF32 writer and every arm32 relocation kind, linked by LLD and executed.

**Usage:**

```
python3 ci/arm32_link_smoke.py            # build, check, link, run under qemu
python3 ci/arm32_link_smoke.py --no-run   # stop after linking
python3 ci/arm32_link_smoke.py --keep DIR # also copy the .o and executable to DIR
```

**Steps it reports:** builds the object with `zig run` on
`arm32_link_smoke.zig`; checks ELF32, EM_ARM, `e_flags 0x5000400`,
`Tag_ABI_VFP_args 1`; links with `zig cc -target arm-linux-musleabihf` and a C
`main`; runs under `qemu-arm-static -cpu cortex-a9` (or `$QEMU_ARM`) and
requires the smoke message and "roc_link_smoke returned 42". Needs
`qemu-user-static` for the run step (`sudo apt-get install qemu-user-static`);
without it the tool fails unless `--no-run` is given, and `--no-run` prints
"NOT RUN" rather than passing silently.

## `ci/vendor_musl_runtime.py`

**Purpose:** produces the musl `crt1.o` and `libc.a` that a `*musl` test
platform links, from the pinned Zig (0.16.0), so they are not copied from an
arbitrary cache.

**Usage:**

```
python3 ci/vendor_musl_runtime.py arm32musl   # writes test/fx/platform/targets/arm32musl/{crt1.o,libc.a}
```

Then copy them to `test/int/platform/targets/arm32musl/` and `git add -f` both
copies (`*.o`/`*.a` are ignored; the fx copies are whitelisted in
`.gitignore`). The script takes the files named on the program's own link line
(`zig build-exe --verbose-link`), because Zig's cache holds two `crt1.o` builds
per arm triple (the raw startup object and the partially linked one it
actually uses). The outputs are not byte-reproducible (musl's archive members
are named by absolute cache paths), so there is no check mode; regenerate when
the Zig version changes.

## `eval-test-runner --write-dev-code-hashes` / `--check-dev-code-hashes`

**Purpose:** the golden byte-identity oracle for Track A: every eval case that
returns an inspected value (1961 today), compiled through the dev backend's
object-file path for `x64musl` and `arm64musl`, one Blake3 per object.

**Usage:**

```
zig build build-test-eval-runner
./zig-out/bin/eval-test-runner --check-dev-code-hashes test/dev_code_hashes/eval.blake3
./zig-out/bin/eval-test-runner --write-dev-code-hashes test/dev_code_hashes/eval.blake3
zig build run-check-dev-code-hashes         # the check as a build step (in minici)
```

`--filter` selects a subset (the file then only contains that subset, so write
to a scratch path when filtering) and `--threads N` caps the shards. The file
has one line per case: the case name, then `x64musl=<hash>` and
`arm64musl=<hash>` (or `error.<Name>` if compiling failed). A check failure
prints the first differing lines.

**How it works:** cases are split into contiguous shards computed by forked
children and concatenated in order, so the output is identical to a sequential
run (about four minutes on sixteen cores). Each case is lowered live (not
through a LIR image, which drops recursive-graph keys) for a 64-bit word and
compiled with `ObjectFileCompiler` for both targets. Object bytes are hashed
after `ProcIdentity.canonicalizeSymbolNames`.

## `ProcIdentity.canonicalizeSymbolNames` (`src/lir/LIR.zig`)

**Purpose:** makes object bytes comparable across compiler builds. Procedure
symbols are `roc__proc_<digest>`, and the digest includes the compiler build's
hash, so every commit changes them. This rewrites each such name, in place, to
`roc__proc_<first-appearance ordinal>` (same length, so no offset moves). Both
byte-identity oracles (the `dev_object` snapshot hashes and the eval-corpus
hashes) hash canonicalized bytes.

## `Isa.binaryIs` and `isaOf` (`src/backend/dev/isa.zig`)

Not a command-line tool, but the mechanism that produces J1's checklist:
`binaryIs(.x86_64)` / `binaryIs(.aarch64)` answers a two-way question on the
64-bit ISAs and refuses to compile on arm32. `grep -c binaryIs
src/backend/dev/LirCodeGen.zig` counts the sites J1 must still decide for
arm32.

## Build steps added

| Step | Runs | In minici |
|---|---|---|
| `run-check-arm32-encoding-oracle` | `ci/arm32_encoding_oracle.py --check` | yes |
| `run-check-dev-code-hashes` | `eval-test-runner --check-dev-code-hashes test/dev_code_hashes/eval.blake3` | yes |
