# Building the new Roc compiler from source

If you run into any problems getting Roc built from source, please ask for help in the `#beginners` channel on [Roc Zulip](https://roc.zulipchat.com) (the fastest way), or create an issue in this repo!

## Recommended way

[Download zig 0.16.0](https://ziglang.org/download/) and add it to your PATH.
[Search "Setting up PATH"](https://ziglang.org/learn/getting-started/) for more details.

Do a test run with
```
zig build roc
./zig-out/bin/roc version
```

## Running the CI checks locally

`zig build minici` runs the checks CI runs. A few of them need tools beyond
Zig:

- **Rust, with two targets** (`zig build run-check-glue-abi` compiles the
  generated Rust glue). Install Rust through [rustup](https://rustup.rs), then
  add the Rust target for your machine and the wasm target:

  | Host | Command |
  |---|---|
  | Linux x86-64 | `rustup target add x86_64-unknown-linux-musl wasm32-unknown-unknown` |
  | Linux AArch64 | `rustup target add aarch64-unknown-linux-musl wasm32-unknown-unknown` |
  | macOS x86-64 | `rustup target add x86_64-apple-darwin wasm32-unknown-unknown` |
  | macOS Apple silicon | `rustup target add aarch64-apple-darwin wasm32-unknown-unknown` |
  | Windows x86-64 | `rustup target add x86_64-pc-windows-msvc wasm32-unknown-unknown` |

  Without the target the check fails with `can't find crate for 'std'`.
- **Optional, for the arm32 checks:** `qemu-arm-static` (Debian/Ubuntu
  package `qemu-user-static`) runs arm32 programs, and `llvm-objdump` lets
  `run-check-simd-codegen` confirm the arm32 binary uses NEON. Without them
  those parts are skipped, and CI still runs them.

## Using Nix

If you're familiar with nix and like using it, you can build the compiler like this:
```
nix develop ./src
buildcmd
./zig-out/bin/roc version
```

## CPU requirements

Builds target the baseline instruction set for their architecture, so the `roc`
binary you build runs on any CPU of that architecture: baseline x86-64 (2003) or
armv8.0-a. You do not need to pick a build for your specific CPU.

To trade that portability for speed on a machine you know, pass `-Dcpu`:

```
zig build build-release -Dcpu=x86_64_v3   # AVX2, BMI2, FMA: Haswell (2013) and later, any AMD Zen
zig build build-release -Dcpu=native      # this exact machine; the result may not run elsewhere
```

`zig build -Dcpu=...` works the same way for non-release builds. `zig build --help`
lists the CPU names Zig accepts.

A binary built for a CPU level above the one it runs on dies with `Illegal
instruction` (SIGILL) at startup, before printing anything.

This is the CPU level of the `roc` binary itself. The CPU level that compiled
Roc *programs* target is a separate setting with its own floor.

## Windows Notes

Due to a [Zig bug](https://github.com/ziglang/zig/issues/17652) related to extracting dependencies from tarball files containing symlinks (which is not allowed by default on Windows), you might encounter permission denial issues. The workaround is to enable the `Developer Mode` option on Windows, which could be found under `Settings > System > Advanced`. If that does not work, please review the aforementioned bug for any additional clues.
