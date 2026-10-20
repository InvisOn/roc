# Upstream issue drafts

Upstream issue drafts from the arm32 work, for roc-lang/roc; one draft per finding.

Filed: 01 (#11995), 04 (#12200), 05 (#12479), 06 (#12202), 08 (#12198), 09 (#12199), 17 (#12201), 29 (#12176), 30 (#12197), 31 (#12179) and 32 (#12207). 21, 22 and 28 were fixed upstream before filing. Filed and fixed drafts are removed from this folder; earlier versions are in this branch's history.

Status rechecked 2026-10-20 against upstream `main` at `5fc587cf51` (all, by code reading and the 2026-10-19 Nightly Gate; all of upstream's issues and PRs searched); before that 2026-10-17 against upstream `main` at `43b87451c5` (02, 03, 05, 10, 12, 13, 14, 16, 26 by code reading; searched for new reports since 2026-10-10: none); before that 2026-10-10 against upstream
`main` at `faecf66d88` (02-27, by code reading and a search for new reports since 2026-10-01; first checked 2026-10-02 at `d16a6598e4`); "code reading" means the code was read, not run.

| File | Still an issue? (2026-10-20, upstream `main` `5fc587cf51`, code reading) | Already upstream? (all issues and PRs searched 2026-10-20) | Fixed on our reference? (`d65fdf3ac1`) |
|---|---|---|---|
| `02-snapshot-tool-errors-as-not-implemented.md` | yes: `src/snapshot_tool/main.zig:4011`, `else \|_\|` still sets `supported = false` | none. #12199 (our 09) is a different snapshot-tool bug | yes, `d910f7aa39`: `processDevObjectSnapshot` already skips unsupported targets before compiling, so any compile error left is real; it now logs the error and fails the snapshot instead of recording `NOT_IMPLEMENTED` |
| `03-icache-not-flushed-before-jit.md` | yes: `ExecutableMemory.zig:404-408` calls `mprotect`, no flush | none for `ExecutableMemory`. #11193 and #11452 (merged) gave only the machine-code shim its flush | yes, `49bf1449b9`: the shim's flush moved from `src/machine_code_shim/instruction_cache.zig` to `src/backend/dev/instruction_cache.zig` so both share it, and `protectExecutable` calls it before `mprotect` (`ExecutableMemory.zig:409`), which flushes with the `cacheflush` syscall on 32-bit ARM; every error set listing `ExecutableMemory`'s errors gains `FlushInstructionCacheFailed` |
| `07-32-bit-host-readiness.md` | yes: `LirCodeGen.zig:8223, 8236, 14093, 14100, 14562, 14587`; `eval/mod.zig:18`; `compile_time_host.zig:39` stamp (could be added) | none. #9436 (closed) was the same habit in the LIR interpreter | yes: `f4af9e372d` uses the target's `word_size` for the Debug string alignment check, the erased-call descriptor array and the drop-pointer offset; `d69fb5eb7f` derives erased-callable payload offsets from the builtins structs scaled by the target word (`erased_layout`), with a compile-time check that every field is pointer-sized; `1344ce3159` makes `backendAvailable(.wasm)` false on 32-bit hosts |
| `10-lir-image-drops-recursive-graph-keys.md` | yes: `lir_image.zig:388, 734` create the map empty; `layout/digest.zig:108` `base.invariant` | none | no; we avoid the path (`lir_image.zig:388, 734`) |
| `11-proc-symbol-names-change-every-build.md` | yes: `checked_artifact.zig:144-178` still hashes `compiler_artifact_hash`; design question | none. #11430 (closed) was a different reproducibility bug (the builtin bake); open PR #12463 changes the key's shape but keeps the compiler hash in it | no; our oracle renames symbols before comparing |
| `12-abs64-relocation-sized-by-host.md` | yes: `Relocation.zig:329-337` branches on `@sizeOf(usize)` | none | no (`Relocation.zig:403-404`); matters to us only for a compiler running on arm32 |
| `13-string-result-stored-from-one-register.md` | yes: `LirCodeGen.zig:16911` "Fallback for non-stack string location" | none | no (`LirCodeGen.zig:19603`) |
| `14-list-get-unsafe-truncates-i128-index.md` | yes: `LirCodeGen.zig:2229` "just load the low 64 bits" | none | no (`LirCodeGen.zig:2279`, now "the low word") |
| `15-u64-discriminant-load.md` | unconfirmed (`loadAndMaskDiscriminant` at `LirCodeGen.zig:11351`); needs a repro before filing | none | no (`LirCodeGen.zig:13898`); unconfirmed |
| `16-glibc-stub-ret-for-other-arches.md` | yes: `glibc_stub.zig:24, 93, 100` write `ret` for `.aarch64_be, .arm, .wasm32, .other` | none | yes, `627b4b7248`: `.arm` gets its own stub body, `mov r0, #0` / `bx lr` (`glibc_stub.zig:24, 103`); `.aarch64_be, .wasm32, .other` still write `ret` |
| `19-redundant-narrowing-shifts.md` | yes (reread): `storeResultToSavedPtr` (`LirCodeGen.zig:16769`) `.u8`/`.i8` shift by 56 twice, then store 1 byte; minor | none | no (`LirCodeGen.zig:19472-19473`, now shifts by `word_bits - 8`) |
| `20-llvm-range-iteration-abort.md` | **probably fixed**: upstream's Nightly Gate 2026-10-19, `eval-llvm (macos-15)`: 17 failures, all `LlvmBackendUnavailable` (wide UTF decoding, a Fluxsort case), none of the range cases. Not rerun on the Pi 5 | none | not ours (upstream CI) |
| `23-full-ci-linux-jobs-killed.md` | yes, on upstream's own Nightly Gate (fails every night 2026-10-16..19; 2026-10-19 `zig-cross-compile (arm-linux-musleabihf)` exit 143, runner shutdown); visible to upstream, low value to file | none filed; upstream's own Nightly Gate shows it every night | not ours (upstream CI) |
| `24-releasefast-test-failures.md` | **probably fixed**; not rerun | none | not ours (upstream tests) |
| `25-macos-15-intel-glue-failures.md` | unknown: `zig-tests (macos-15-intel)` was cancelled after 6 h on 2026-10-19; the `LlvmBackendUnavailable` part now shows in `eval-llvm (macos-15)` | none | not ours (upstream CI) |
| `26-stale-line-number-exclusions.md` | yes: ranges now in `src/build/check_runner.zig:190-225`; `inspected.zig` is 3255 lines, so 3264-3275 is past its end; 2474 is a `}` | none | no; same stale ranges, shifted by one (`check_runner.zig:211-217`) |
| `27-minici-artifact-download.md` | yes (2026-10-02); minor | none | not ours (upstream CI) |

Every draft is about upstream's code or CI; none is a defect of our reference
branch (those were fixed there and are in the verification note's findings
table). Each file's first line says whether upstream is affected today or
only a 32-bit host or target would hit it (07, 12; and 03, 10, 11, 16 are
latent or unreached upstream).

Deleted 2026-10-02: 18, the type checker panic on basic-cli 0.22.2. It was
reported upstream as #11640 and fixed by #11671; it no longer reproduces on
the nightly with basic-cli 0.22.2 or 0.23.0.

Not drafted: partially deleting `.zig-cache/o` breaks Zig's cache (that is
Zig's behaviour, not Roc's), and the proposals (stop committing prebuilt
binaries; report peak memory per test; the byte-identity oracle), which are
suggestions, not defects. See `projects/big/arm32-dev-backend-upstream-now.md`.
