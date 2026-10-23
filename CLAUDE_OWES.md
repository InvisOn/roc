# What Claude owes me

Written 2026-10-02. Claude updates this when
something is delivered or newly promised.

## For the clean branch (`dev-backend-aarch32`)

- [x] **Breakdown of the word-size changes in the driver.** Delivered
      2026-10-02, in `NICE_BRANCH.md` ("The driver's 9,000 changed lines, by
      kind"). The biggest single cause is the helper move to `CodeGen`, not
      word size. Scripts: `.git/verify-tools/driver-breakdown/`.
- [x] **Weigh the `Isa` enum against upstream's style.** Delivered
      2026-10-02, same place. About 150 diff lines; recommendation: keep
      it, as its own early commit.
- [x] **First proposal: the encoder commits.** Delivered 2026-10-02, in
      `NICE_BRANCH.md` ("Proposal 1: the encoder"), E1 to E6.
- [ ] **Try the oracle as a `zig build` step** (assemble the `.s` file,
      compare in a Zig test; no generated file, no Python). Needed before
      E2. Not started; it is a build, so in the compute window.
- [ ] **Try leaving the 55 helpers in the driver** with an arm32 arm each,
      and measure the driver diff again. Promised as an estimate only.
- [ ] **How small the first working slice of the driver stage can be.** The
      driver is one generic type per architecture, so arm32 may not compile
      until most of the preparation is done. To measure before that stage.
- [ ] **Generated files: a proposal.** Commit the encoder's oracle tests and
      the eval hash file, or generate them during the test run.
      2026-10-03: the eval hash file half is settled by upstream 11885: a
      committed file cannot work any more (`NICE_BRANCH.md`, last section).
      The encoder's oracle tests are still open.
- [ ] **Check each "useful to the wider Roc project" item properly** when we
      reach it. The table in `NICE_BRANCH.md` is a first cut.
- [ ] **The 8-week schedule in `NICE_BRANCH.md`**, once I say yes to writing
      only the first of each pattern.

## Asked 2026-10-03 for tonight: test coverage to 100%, and fuzzing

On the reference (`32-bit-backend`), in this conversation, starting Sunday
2026-10-04 at 00:17 (weekend window, 00:00 to 06:30).

- [ ] **Measure first.** Line coverage, with kcov (upstream's coverage
      tooling already uses it), of the arm32 code: `src/backend/dev/arm32/`,
      ELF32 (`write32` in `object/elf.zig`), `layout/abi/arm32.zig`, and the
      arm32-only functions and `.arm32` cases in `LirCodeGen.zig` and
      `CallingConvention.zig`. Sources of execution: the backend tests, and
      the arm32 cross-compile paths (fx and int programs built for
      arm32musl, the eval corpus compiled for arm32).
      Prepared 2026-10-03 (reading only): upstream's kcov steps run only on
      Linux arm64 (and macOS); on Linux x86_64 kcov could not read Zig's
      DWARF (`build.zig`, `CoverageSummaryStep`). The desktop is x86_64, kcov
      is not packaged for Pop!_OS. kcov 43 is installed on the Raspberry
      Pi 5 (apt, 2026-10-03), but a probe showed it counts 0 lines for a
      Zig 0.16 aarch64 test binary (self-hosted or LLVM, musl or glibc,
      with debug info present). Upstream builds its own kcov from
      roc-lang/zig-kcov (a fork that also skips `unreachable` and `@panic`
      lines, which suits the agreed definition of 100%), through
      `zig build build-coverage-tests` for an arm64 target. So tonight:
      build that kcov and the test binaries for `aarch64-linux-musl` on the
      desktop, check it counts lines on the same probe, then measure on the
      Pi 5. If it does not count lines either, stop and tell me.
      **Result 2026-10-04 03:30: blocked; needs my decision.** On the Pi 5,
      apt's kcov 43 covers C programs (dynamic, static, DWARF 5) but counts
      0 lines for any Zig 0.16 binary, so the problem is specific to Zig's
      output. Upstream's kcov fork cannot be built from the desktop: roc's
      `build.zig` only declares it when the host itself is arm64, and the
      fork links the system's curl, zlib, libelf and libdw, so it has to be
      built on the Pi 5 itself. That needs, on the Pi: Zig 0.16, and
      `sudo apt install libcurl4-openssl-dev zlib1g-dev libelf-dev libdw-dev`.
      Nobody has shown that the fork counts Zig lines on arm64 with Zig
      0.16 either (upstream's own comment says it was not re-measured).
      Options: (a) install those on the Pi and try the fork; (b) measure
      coverage another way (Zig's sanitizer-coverage instrumentation, which
      kcov's `--clang` mode reads, or a small tool of our own); (c) count
      coverage per function instead of per line, from the tests' calls.
      The arm32 code generator runs on any host, so measuring it on an
      aarch64 host is fine.
      **Research 2026-10-06 (reading and probes only, no choice made):**
      (b) can run on the desktop, without kcov and without installing
      anything. Zig 0.16 emits SanitizerCoverage `trace-pc-guard`
      instrumentation (roc's `build.zig` already turns it on for the fuzz
      objects). A small runtime of our own would record the hit addresses,
      and Homebrew's `llvm-addr2line` maps them to lines: it resolved an
      address in the x86_64 `eval-test-runner` to
      `src/backend/dev/arm32/Emit.zig:373`, where the system `addr2line`
      and `eu-addr2line` fail on Zig's DWARF. Still unproven: listing every
      instrumented line (the denominator, from the guard or PC table), and
      leaving out `unreachable` and `@panic` lines.
      **Decision 2026-10-06 (mine): (b).** First a small proof on
      `src/backend/dev/arm32/Emit.zig` with the encoder tests (instrumented
      build, hit addresses, `llvm-addr2line`, a list of every instrumented
      line, `unreachable` and `@panic` lines left out). If the proof fails,
      Claude stops and tells me before going further. The tool lives in
      `.git/verify-tools/`; nothing in the compiler changes.
      **Proof result 2026-10-06 01:55: it works.** `arm32/Emit.zig` with the
      encoder tests: 719/719 lines (100%), 3 `unreachable` lines left out,
      test blocks not counted. Control: only the 13 `ldr` tests gives
      74/717 (10.3%) and lists the 643 lines that did not run. How
      (`.git/verify-tools/cov/`: `cov_build.sh`, `cov_rt.c`,
      `cov_report.py`, `roots/`):
      - Zig's own `-fsanitize-coverage-trace-pc-guard` lets LLVM prune
        blocks whose execution is implied by a neighbour, and Zig cannot pass
        `-mllvm`. So Zig emits LLVM bitcode, and Zig's own clang (same LLVM
        21) instruments it with pruning off. Homebrew's LLVM 22 miscompiles
        Zig's bitcode (tried: the test runner panics).
      - Zig compiles only referenced functions, so a test binary's own line
        count hides every function its tests never name (seen: 100% from
        only the `ldr` tests). A coverage root references every declaration
        of the module, recursively, for both arm32 targets; it is copied
        next to the module for the build and removed afterwards.
      - Limit: a function with `comptime` parameters counts only once
        something instantiates it (2 lines in `Emit.zig`); in the full
        measurement the whole compiler instantiates them.
      **Measured 2026-10-06 09:40** (unit tests of the backend module, plus
      the instrumented `roc` building every `test/fx` app and the int app for
      arm32musl and arm32linux; merged per line):
      `Emit.zig` 719/719, `Registers.zig` 30/30, `Call.zig` 4/4,
      `CodeGen.zig` 344/404 (85.1%), `layout/abi/arm32.zig` 72/78 (92.3%):
      1169/1235 (94.7%). The shared driver as instantiated for arm32,
      fx programs only: `LirCodeGen.zig` 5752/11552 (49.8%),
      `CallingConvention.zig` 252/299 (84.3%). Not yet a source: the eval
      corpus (it compiles for arm32 only in the runner under qemu; an
      instrumented arm32 runner is being built). Open for me to decide
      later: whether "the arm32 implementation" means the arm32 files and
      the arm32-only branches of the driver, or every line of the driver
      as instantiated for arm32 (much of it shared with the other ISAs).
      Some uncovered `CodeGen.zig` functions may be dead code for arm32
      (`reset`, `getStackSize`, the width-taking `emitAdd`/`emitSub`).
      **With the eval corpus, 2026-10-06 13:45** (instrumented arm32 eval
      runner under qemu, ReleaseSmall with debug info, as an extra source of
      covered lines; the run took 2 h 22 min against 46 min plain; all
      2539 cases passed). Merged over all three sources:
      arm32 files 1192/1235 (96.5%): `Emit.zig`, `Registers.zig`,
      `Call.zig` 100%, `CodeGen.zig` 367/404 (90.8%),
      `layout/abi/arm32.zig` 72/78 (92.3%). Driver as instantiated for
      arm32: `LirCodeGen.zig` 7897/11558 (68.3%), `CallingConvention.zig`
      275/299 (92.0%), together 8172/11857 (68.9%); the largest gaps are
      `generateLowLevel` (395 lines), structural equality (344), the Boxy
      (`--specialize=no`) helpers, list split operations and the NEON SIMD
      paths, mostly shared logic rather than arm32 code.
      The 37 uncovered `CodeGen.zig` lines: dead code with no caller
      anywhere (`getStackSize`, `emitLoadStackByte`,
      `emitLoadStackHalfword`); the rest is called from the driver but no
      test reaches it (F64 divide and negate, F32 arithmetic, signed and
      float `<=`, storing a float through a pointer, 16-byte vector stack
      moves), probably because the eval programs use constants that Roc
      folds at compile time; closing those needs eval cases whose inputs
      are only known at run time.
      **Decided 2026-10-07 (mine):** scope (i), our code: the arm32 files plus the driver lines our branch added or changed (by `git diff` against upstream) that the arm32 build compiles; gaps in upstream's shared code are listed, not chased. The three dead functions deleted (our code), 38bf6d9771. Eval cases: question asked, see the conversation.
      **Scope (i), 2026-10-07 13:25:** 3875/4459 lines (86.9%), 584 left.
      `Emit.zig`, `Registers.zig`, `Call.zig` 100%, `CodeGen.zig` 96.2%,
      `layout/abi/arm32.zig` 92.3%, our driver lines 82.2%
      (`LirCodeGen.zig`) and 90.6% (`CallingConvention.zig`). Sources now
      also include upstream's SIMD differential corpus and the `test/cli`,
      `test/echo` and `test/alloc-count` programs built for arm32. First new
      test: `test/fx/runtime_float_arith_widths.roc` (`05db6f15d3`). Found:
      `generateStructuralEquality` (79 of the 584) cannot be reached; the
      lowering expands equality into scalar compares (details in
      `.git/verify-tools/cov/scope_i_notes.md`). Gap list:
      `.git/verify-tools/cov/scope_i_gaps.txt` (`cov_scope_i.py`).
      **Was waiting for my decisions:** the scope of "100%" ((i) the arm32 files
      plus the arm32-only branches of the driver, or (ii) every line of the
      driver as instantiated for arm32); whether to delete the three dead
      functions on the reference (our code) or list them; whether new eval
      cases may go into the shared eval test files.
      Next: the other arm32 files (`Registers.zig`, `Call.zig`,
      `CodeGen.zig`, `layout/abi/arm32.zig`, ELF32 `write32`), then the
      arm32 paths in `LirCodeGen.zig` and `CallingConvention.zig`, where the
      sources of execution are the backend tests and the eval corpus
      compiled for arm32.
- [ ] **Then close the gaps** with tests, starting with the largest
      uncovered families.
- [ ] **Fuzzing:** stage 1 of `projects/big/arm32-dev-backend-fuzzing.md`
      (the dev backend's object compilation added to `fuzz-build`, which
      already selects arm32 among its targets; AFL++ on the desktop).
      Generators must compose small typed constructs (AGENTS.md).

Assumptions, confirmed by me on 2026-10-03:
- "100%" means every line that can run is run by a test; lines that cannot
  run (invariant panics, `unreachable`) are listed with the reason, not
  forced.
- Fuzzing runs only inside the compute window, so the plan's "24-hour AFL++
  run" becomes several nights.
- Upstream impact: none tonight. Everything stays on the fork; nothing is
  pushed without my yes. Fuzzing stages 1 and 2 could later be offered
  upstream on their own; that is my decision, not tonight's.
- Order tonight: the upstream sync first (about four hours with margin),
  then coverage measurement; whatever does not fit by 06:30 continues the
  next window (Sunday night, then the weekday window from Monday).

## Running in the other conversation

- [ ] **Upstream sync of the reference** (`claude/arm32-dev-backend-reference`,
      `32-bit-backend` until 2026-10-17): continuous since 2026-10-13; state in
      `.git/verify-tools/upstream-sync/state.txt` on the first PC.
- [x] **Push the notes commits** (the facade decision, the basic-cli panic): pushed 2026-10-03
- [x] **Re-create the sync schedule**: no longer needed; the sync runs continuously (2026-10-13)
- [x] **Watch upstream 11885** (the 120,000-line consolidation): merged into the reference 2026-10-03

## Decided 2026-10-02

- The charts page works.
- `arm32-holes` and `LEARNING_HOLES.md` stay, as practice. Claude builds the
  holes for stages 2 to 6 when I reach them.
- The reference branch does not go upstream. `dev-backend-aarch32` does,
  when it is done.

## Reminders Claude keeps giving me

- [ ] **The remaining walkthroughs are on hold**, not dropped: A2/A3/Track
      C, J1, J2-J4, the upstream merges. Claude brings them up in sitreps
      and when a stage of the clean branch reaches the matching part.

## The upstream issue drafts (`upstream-issue-drafts/`)

- [x] One draft per finding, 26 files (18, the basic-cli panic, deleted:
      fixed upstream), with status as of 2026-10-02
      (code reading and a search of upstream's issues and PRs).
- [ ] **Rechecks that need a build or a run** (compute window), on a clean
      checkout of current upstream `main`:
  - 01 glibc `--opt=dev` crash: reproduce.
  - 04 backend test writing to stderr: rerun the test step.
  - 07 host-sized target data: verified by reading the code 2026-10-02 (two of five parts fixed upstream, draft rewritten). Still to do: build upstream's eval runner for `arm-linux-musleabihf` to confirm it compiles.
  - 08 wasm sublist index: the two probe eval cases.
  - 09 snapshot tool hashing type errors: reproduced 2026-10-02 with the reference build (draft rewritten with a self-contained probe); rerun on clean upstream.
  - 17 git-lints NUL padding: the probe file.
  - 20 LLVM range-iteration abort: on the Pi 5, no local patch, and cut
    the case down to the line that triggers it.
  - 24 ReleaseFast test failures: the three tests (about an hour).
- [ ] 23 and 25 (CI jobs killed, macOS-15-intel): look at upstream's own
      recent nightly runs.
- [ ] Update the README table in the drafts directory after each recheck.
- [ ] basic-cli 0.23.0 is out (2026-09-27). Our Roc verify tools use 0.22.2, which gives 75 warnings with the nightly; an empty app on 0.23.0 gives none. Try moving the tools to 0.23.0.
