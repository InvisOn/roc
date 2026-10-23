# Upstream issue drafts

Drafts of issues for roc-lang/roc, one per problem found during the arm32 work.

**Filed:** 01 (#11995), 04 (#12200), 05 (#12479), 06 (#12202), 08 (#12198), 09 (#12199), 17 (#12201), 29 (#12176), 30 (#12197), 31 (#12179), 32 (#12207), 10 (#12480), 13 (#12481), 19 (#12483), 11 (#12499), 33 (#12500), 35 (#12520), 36 (#12531) and 14 (#12532). Upstream fixed 21, 22, 28 and 34 before we filed them. Once a draft is filed or fixed, it is removed from this folder. Older versions are in this branch's history.

**Last checked:** 2026-10-20, against upstream `main` at `5fc587cf51`. All drafts were checked by reading the code, plus upstream's Nightly Gate run of 2026-10-19 for the CI drafts. All of upstream's issues and PRs were searched. "By reading the code" means nobody ran anything, unless a draft says a test was run. Earlier checks: 2026-10-17 at `43b87451c5`, 2026-10-10 at `faecf66d88`, and first on 2026-10-02 at `d16a6598e4`.

## Preferred filing order

Proven bugs with a test come first, then bugs that only matter on 32-bit, then CI problems. Each line says why it sits where it does. The fork PR is the fix, tested on InvisOn/roc, which can be offered with the issue.

1. **26**, stale line-number exclusions. A check that passes or fails for the wrong reason, with a script in the draft that proves the four stale entries. Fix: fork PR #5.
2. **02**, the snapshot tool records real compile errors as "not implemented". It hides failures from the snapshot test. Fix: fork PR #7.
3. **03**, no instruction cache flush before JIT code runs. Upstream gets away with it today mostly by luck. Fix: fork PR #8, not yet tested on aarch64, so test it there before filing.
4. **07**, 32-bit host readiness. Matters only for a 32-bit target or host, and it is the biggest draft, so file it once the smaller ones have landed.
5. **12**, abs64 relocation sized by the host. Matters only for a compiler running on a 32-bit machine. Fix: fork PR #3.
6. **27**, minici artifact download fails now and then. Minor, a rerun passes.
7. **23**, full-CI Linux jobs get killed. Upstream's own Nightly Gate shows it every night, so an issue adds little.

Don't file these yet:

- **16**, glibc stub writes `ret` for arm. Upstream PR #12513 (open) fixes it. File the issue only if that PR is closed without a fix.
- **15**, U64 discriminant load. Probably not a bug, see the draft. Confirm it with a test first, or drop it.
- **20**, **24** and **25**. Probably fixed (20, 24) or unknown (25). Rerun them on current `main` first, and drop the ones that pass.

Before filing any of them, follow "Before filing" in the draft itself and check it on current `main`.

| File | Why it matters to our arm32 work | Reported? | Still an issue? (2026-10-20, upstream `main` `5fc587cf51`, code reading) | Already upstream? (all issues and PRs searched 2026-10-20) | Fixed on our reference? (`d65fdf3ac1`) |
|---|---|---|---|---|---|
| `02-snapshot-tool-errors-as-not-implemented.md` | While arm32 code generation was unfinished, real arm32 compile errors were recorded as "not implemented" instead of failing. Our reference fixes it. | no | yes: `src/snapshot_tool/main.zig:4011`, `else \|_\|` still sets `supported = false` | none. #12199 (our 09) is a different snapshot-tool bug | yes, `d910f7aa39`: `processDevObjectSnapshot` already skips unsupported targets before compiling, so any compile error left is real; it now logs the error and fails the snapshot instead of recording `NOT_IMPLEMENTED` |
| `03-icache-not-flushed-before-jit.md` | Needed for arm32. Without the flush, newly written code doesn't run reliably on 32-bit ARM. Our reference adds it. | no | yes: `ExecutableMemory.zig:404-408` calls `mprotect`, no flush | none for `ExecutableMemory`. #11193 and #11452 (merged) gave only the machine-code shim its flush | yes, `49bf1449b9`: the shim's flush moved from `src/machine_code_shim/instruction_cache.zig` to `src/backend/dev/instruction_cache.zig` so both share it, and `protectExecutable` calls it before `mprotect` (`ExecutableMemory.zig:409`), which flushes with the `cacheflush` syscall on 32-bit ARM; every error set listing `ExecutableMemory`'s errors gains `FlushInstructionCacheFailed` |
| `07-32-bit-host-readiness.md` | A 64-bit machine compiling for arm32 is exactly where the two word sizes differ. Our reference fixes these places. | no | yes: `LirCodeGen.zig:8223, 8236, 14093, 14100, 14562, 14587`; `eval/mod.zig:18`; `compile_time_host.zig:39` stamp (could be added) | none. #9436 (closed) was the same habit in the LIR interpreter | yes: `f4af9e372d` uses the target's `word_size` for the Debug string alignment check, the erased-call descriptor array and the drop-pointer offset; `d69fb5eb7f` derives erased-callable payload offsets from the builtins structs scaled by the target word (`erased_layout`), with a compile-time check that every field is pointer-sized; `1344ce3159` makes `backendAvailable(.wasm)` false on 32-bit hosts |
| `12-abs64-relocation-sized-by-host.md` | Matters only for a compiler running on arm32. Our reference doesn't change it. | no | yes: `Relocation.zig:329-337` branches on `@sizeOf(usize)` | none | no (`Relocation.zig:403-404`); matters to us only for a compiler running on arm32 |
| `15-u64-discriminant-load.md` | None in particular. Noticed while reading the backend. | no | probably not: the 8-byte load happens only for a `U64` target, and upstream always reads discriminants into `U32` locals; the refcount helper masks | none | no (`LirCodeGen.zig:13898`); unconfirmed |
| `16-glibc-stub-ret-for-other-arches.md` | `arm32linux` uses the glibc stub, and `ret` is not a 32-bit ARM instruction. Our reference gives arm its own stub. | no | yes: `glibc_stub.zig:24, 93, 100` write `ret` for `.aarch64_be, .arm, .wasm32, .other` | none | yes, `627b4b7248`: `.arm` gets its own stub body, `mov r0, #0` / `bx lr` (`glibc_stub.zig:24, 103`); `.aarch64_be, .wasm32, .other` still write `ret` |
| `20-llvm-range-iteration-abort.md` | It failed a job in our CI. arm32 doesn't use the LLVM backend, so it's unrelated to our code. | no | **probably fixed**: upstream's Nightly Gate 2026-10-19, `eval-llvm (macos-15)`: 17 failures, all `LlvmBackendUnavailable` (wide UTF decoding, a Fluxsort case), none of the range cases. Not rerun on the Pi 5 | none | not ours (upstream CI) |
| `23-full-ci-linux-jobs-killed.md` | The arm32 eval steps come after the job that gets killed, so they never run on GitHub. We run them in a separate, smaller job. | no | yes, on upstream's own Nightly Gate (fails every night 2026-10-16..19; 2026-10-19 `zig-cross-compile (arm-linux-musleabihf)` exit 143, runner shutdown); visible to upstream, low value to file | none filed; upstream's own Nightly Gate shows it every night | not ours (upstream CI) |
| `24-releasefast-test-failures.md` | They failed our CI. We had to trace them to upstream before we could trust our own results. | no | **probably fixed**; not rerun | none | not ours (upstream tests) |
| `25-macos-15-intel-glue-failures.md` | It fails in our CI. Unrelated to our code. | no | unknown: `zig-tests (macos-15-intel)` was cancelled after 6 h on 2026-10-19; the `LlvmBackendUnavailable` part now shows in `eval-llvm (macos-15)` | none | not ours (upstream CI) |
| `26-stale-line-number-exclusions.md` | Our changes move lines in the checked files, so the skipped lines land on the wrong code and the check passes or fails for the wrong reason. | no | yes, four stale entries (checked by a script in the draft): `cir_to_lir.zig` no longer exists; `inspected.zig` 2474 is a `}` and 3264-3275 is past its 3255 lines; `inspected_run.zig` 109 is blank | none | no; same stale ranges, shifted by one (`check_runner.zig:211-217`) |
| `27-minici-artifact-download.md` | It sometimes fails our PR's CI run before any test runs. A rerun passes. | no | yes (2026-10-02); minor | none | not ours (upstream CI) |
| 01: Default-platform glibc programs built with `--opt=dev` crash at startup (removed) | Found bringing up `arm32linux`, where the dev backend is the only backend. Our reference fixes it for every target. | yes, #11995 (closed) | — | — | — |
| 04: A passing backend unit test prints a WASM merge message that zig build shows as a failed command (removed) | It made our backend test runs report failure with every test passing. Our reference fixes it. | yes, #12200 (closed) | — | — | — |
| 05: Relocation patching guesses the instruction set from the code bytes (removed) | A byte test can't tell a third instruction set apart, so arm32 needed the caller to pass it. Our reference does that. | yes, #12479 (open) | — | — | — |
| 06: No prerequisite list mentions MiniCI's `run-test-repl-wasm` needs Node.js (removed) | We lost time to missing tools the first times we ran minici. | yes, #12202 (closed) | — | — | — |
| 08: wasm miscompile `List.sublist` narrows a `U64` start index to 32 bits (removed) | Doesn't affect arm32. Found while studying how the other 32-bit target (wasm) handles 64-bit values. | yes, #12198 (closed) | — | — | — |
| 09: The snapshot tool hashes `dev_object` programs that failed to type-check (removed) | We made this mistake ourselves: a snapshot we added had a type error and was hashed anyway. | yes, #12199 (closed) | — | — | — |
| 10: A loaded LIR image has no recursive-graph keys in its layout store (removed) | We hit it building the oracle that hashes every eval case's machine code. We took another route. | yes, #12480 (open) | — | — | — |
| 11: Procedure symbol names change with every change to the compiler's source (removed) | Our 64-bit oracle compares machine code byte for byte, but the names differ between any two compilers. We rename symbols before comparing. | yes, #12499 (open) | — | — | — |
| 13: Fallback in dev backend (a string result stored from one register) (removed) | None in particular. Found while reading the backend for word-size assumptions. | yes, #12481 (open) | — | — | — |
| 17: `run-check-git-lints` pads a file name with NUL bytes (removed) | Seen in the lint output on our branch. Cosmetic. | yes, #12201 (closed) | — | — | — |
| 19: Dev backend: extra shifts before storing a single byte (removed) | None in particular. Noticed while reading the backend. | yes, #12483 (open) | — | — | — |
| 29: LSP integration test depends on the contents of `/tmp` (removed) | None to arm32. It failed a minici phase during one of our syncs. | yes, #12176 (closed) | — | — | — |
| 30: Segfault in `fuzz-build` (removed) | It blocks AFL++ fuzzing of the dev backend. Our arm32 `setjmp` is written the same way and would break the same way. | yes, #12197 (closed) | — | — | — |
| 31: A syntax error in an app file makes `roc check` check a nearby `main.roc` instead (removed) | None to arm32. Found while confirming draft 29. | yes, #12179 (closed) | — | — | — |
| 32: `apt install afl++` in the fuzzing guide no longer works since Zig 0.17 (removed) | It blocks AFL++ fuzzing of the dev backend before draft 30's crash is even reached. | yes, #12207 (closed) | — | — | — |
| 33: The deep "curried lambdas" eval test now needs three times the memory (removed) | It blocks our sync. The test now needs more memory than a 32-bit process can have, so it fails on arm32. | yes, #12500 (open) | — | — | — |
| 35: The nested procedure path pool grows with the square of nesting depth (removed) | It blocks our sync. Since `55a9d652c1` the deep "closures nested as call arguments" test runs out of memory on arm32. | yes, #12520 (open) | — | — | — |
| 36: `dev_object` snapshot hashes depend on the compiler build (removed) | It blocks our sync. Three of our `dev_object` snapshots fail minici after every merge since `16a3cb76e5`. | yes, #12531 (open) | — | — | — |
| 14: `list_get_unsafe` quietly cuts an i128 or Dec index down to 64 bits (removed) | None in particular. Found while reading the backend for word-size assumptions. Fix offered as fork PR #6. | yes, #12532 (open) | — | — | — |

Every draft is about upstream's code or CI. None is a bug in our reference branch; those were fixed there and are listed in the verification note's findings table.

Some drafts can't fail upstream today:

- 07 and 12 matter only for a 32-bit machine or target.
- 03, 10, 11 and 16 are in upstream code that nothing upstream currently reaches, or reaches only by luck.

Each draft's first lines say which case it is.

**Deleted 2026-10-02:** 18, the type checker panic on basic-cli 0.22.2. Someone else reported it as #11640, and #11671 fixed it. It no longer happens on the nightly with basic-cli 0.22.2 or 0.23.0.

**Not drafted:**

- Deleting part of `.zig-cache/o` breaks Zig's cache. That is how Zig behaves, not a Roc bug.
- Suggestions rather than bugs: stop committing prebuilt binaries, report peak memory per test, and the byte-for-byte comparison oracle. See `projects/big/arm32-dev-backend-upstream-now.md`.
