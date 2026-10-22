# Step 0: harness and stub backend

## Goal

Every way of running arm32 code exists and works, and every arm32 test
fails cleanly with "not implemented". That failure count is the starting
line for every later step.

## Files from the reference snapshot

Take these from `git diff 73df27a5bb 2f5d8e3685`:

- **Targets:** `src/target/mod.zig` (the `arm32musl` and `arm32linux`
  entries), `src/cli/main.zig` (accepting them with `--opt=dev`).
- **Test runners:** `src/cli/test/parallel_cli_runner.zig`,
  `src/cli/test/platform_config.zig`, `src/cli/test/fx_test_specs.zig`
  (`--cross-target`, `--cross-opt`, `--cross-run`, `--cross-runner`),
  `src/eval/test/parallel_runner.zig` (runs as an arm32 program).
- **Platforms:** `test/fx/platform/` and `test/int/platform/` target
  entries, and the vendored runtime files under their `targets/arm32*`
  folders. These are binaries. Regenerate them with
  `ci/vendor_musl_runtime.py` and `ci/vendor_glibc_crt.py` rather than
  copying, and note in the commit that they are committed binaries.
- **Tools:** `ci/arm32_encoding_oracle.py` and `.s`,
  `ci/elf32_reader.py`, `ci/arm32_link_smoke.py`,
  `src/backend/dev/arm32_link_smoke.zig`, `ci/ssh_cross_runner.sh`.
- **Build wiring:** `build.zig`, `src/build/check_runner.zig`,
  `src/build/test_harness.zig`, `src/build/glibc_stub.zig`,
  `src/build/minici.zig`, and the arm32 lanes in
  `.github/workflows/ci_zig.yml` and `ci_cross_compile.yml`.
- **The stub:** the dev backend recognises an arm32 target and returns a
  "not implemented" error before any code generation. It is not in the
  reference. Claude writes it for this step.
- **Docs:** `src/backend/dev/arm32/TOOLS.md`.

Not yet: anything under `src/backend/dev/arm32/` except the docs, and
anything in `LirCodeGen.zig`.

## The driver script

`.git/verify-tools/roc/hw_checks.roc` on the first PC runs every arm32
check under the memory cap and prints one summary. It hard-codes paths
from an old session. Claude turns it into a script in the stepwise-rebuild worktree
that takes the board names and output folder as arguments.

## Mirrors

Nothing. This is tooling.

## Holes

None. Read the tools instead, in this order: `TOOLS.md`, then the encoding
oracle (it is the one tool used in every later step).

## Check

```sh
zig build roc
./zig-out/bin/roc build --opt=dev --target=arm32musl --output=hello test/fx/hello_world.roc
# expected: a clean "not implemented" error, no crash
zig build build-test-eval-runner -Dtarget=arm-linux-musleabihf -Doptimize=ReleaseFast --prefix out-arm
qemu-arm-static -cpu cortex-a9 out-arm/bin/eval-test-runner --timeout 300000
python3 ci/arm32_encoding_oracle.py --check   # passes with an empty encoder
```

Then the x86_64 and aarch64 tests must still pass: `zig build minici`.

Test counts: to be measured (eval under qemu: 0 of about 2,580 pass).

## Done when

- The arm32 runs above fail cleanly, with nothing crashing.
- minici passes.
- The driver script runs end to end and prints its summary.

## Prompt

> Read `stepwise-rebuild/README.md` and `stepwise-rebuild/step-00-harness.md` on
> the `notes` branch of InvisOn/roc. Build step 0 on the stepwise-rebuild branch:
> cut its files from `git diff 73df27a5bb 2f5d8e3685`, write the stub, and
> tidy the hw_checks driver into a script. Propose each commit, I write
> it. Then measure the counts and update the step file.

## Progress

- Not started.
