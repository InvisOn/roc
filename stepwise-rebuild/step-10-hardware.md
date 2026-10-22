# Step 10: real hardware

## Goal

Everything that passes under qemu also passes on real boards: the Pi 5
(64-bit kernel, 16 KB pages, runs arm32 programs) and the Pi 3 (32-bit
Raspberry Pi OS, armv7l with NEON).

## Files

Nothing new from the reference, unless a board finds a difference qemu
hides. The step adds:

- the int platform's `arm32linux` target (`test/int/platform/targets/arm32linux/`)
- the CI lanes (`ci_cross_compile.yml` and `ci_zig.yml`) switched from
  `continue-on-error` to required, if I want that
- `BUILDING_FROM_SOURCE.md`: the arm32 notes

## Holes

None. The exercise is to explain it back: write the walkthrough of one
program from Roc source to a running process on the Pi 3.

## Check

```sh
ROC_CROSS_SSH_HOST=<user>@<aarch64-device> zig build run-test-cli -- --suite platforms \
    --filter test/fx/ --cross-target=arm32musl --cross-opt=dev --cross-run \
    --cross-runner=ci/ssh_cross_runner.sh --threads 3
ROC_CROSS_SSH_HOST=<user>@<arm32-device> zig build run-test-cli -- --suite platforms \
    --filter test/fx/ --cross-target=arm32musl --cross-opt=dev --cross-run \
    --cross-runner=ci/ssh_cross_runner.sh --threads 3
```

Then the int platform on the Pi 3, and the driver script from step 0 with
every part.

Test counts: to be measured.

## Done when

- The driver script's summary shows every part passing on both boards.
- The series is ready to propose (see `NICE_BRANCH.md`).

## Prompt

> Read `stepwise-rebuild/README.md` and `stepwise-rebuild/step-10-hardware.md` on
> the `notes` branch. Run step 10 on top of step 9: the hardware checks on
> both Pis, then review my walkthrough.

## Progress

- Not started.
