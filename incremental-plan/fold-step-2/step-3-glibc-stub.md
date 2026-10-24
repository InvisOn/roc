# Fold step 2, step 3 of 9: #4 glibc stub for 32-bit ARM

Branch `dispatch/isa`, commit `430427f287` "Use correct instructions for
32-bit ARM", from #4 (`4dffc5b3ea`), keeping its original author date. The
hash is the one at the time of writing.

## Why

`generateComprehensiveStub` wrote `ret` as the body of every stub function
for `.arm`, which it grouped with `.aarch64_be`, `.wasm32` and `.other`.
`ret` is not an A32 instruction, so the assembler rejects the whole stub
("invalid instruction").

On our base nothing generates the arm stub yet: `build.zig:72` lists only
`x64glibc` and `arm64glibc` as glibc cross targets. The bug fires once
`arm32linux` joins that list, as the reference branch does at
`build.zig:78`, in plan step 12 (`arm32/targets`). From then on `zig build`
assembles the arm stub for the prepared test hosts, and without this fix it
fails.

## What changed

One file, `src/build/glibc_stub.zig` (+7/−4). `.arm` gets its own bodies,
like x86_64 and aarch64 already have: return 0 with `mov r0, #0` and
`bx lr`, and exit(1) through the EABI syscall (`mov r7, #1`, `svc #0`) for
the exit stub.

The code is identical to upstream PR 12513 (same patch-id `0e72c2f05326`),
which is still open.

## Review findings and outcomes

- **Attention, fixed:** #4's message claimed a test, "the 32-bit ARM glibc
  stub uses A32 returns". That test exists only in draft notes
  (`70539562c3`). `glibc_stub.zig` is not run by any test step, and it
  imports `../target/mod.zig`, outside `src/build/`. The claim was dropped,
  and the message now states the check that was done instead.
- Message line wrapping fixed.
- Nit 4 kept: `__sysctl` uses `writeAll` instead of `print`.
- Nit 5 left: `ret` stays the body for `.wasm32` and `.other`.

This commit was first made before the user's review. It was soft reset,
reviewed, and recommitted after approval.

## Tests

- Generated the arm stub and assembled it with
  `zig cc -target arm-linux-gnueabihf`: it builds an ELF32 ARM object with
  44 `bx lr`, 1 `svc` and 0 `ret`.
- The step 2 full test run passed before this commit. This commit touches
  only `src/build/`.

## Final commit message

```
Use correct instructions for 32-bit ARM

generateComprehensiveStub wrote `ret` as the body of every stub function
for .arm, which it groups with .aarch64_be, .wasm32 and .other. `ret` is
not an A32 instruction, so the assembler rejects the stub for 32-bit ARM
("invalid instruction").

.arm now gets its own bodies, matching what x86_64 and aarch64 do: return
0 with `mov r0, #0` and `bx lr`, and exit(1) through the EABI syscall for
the exit stub. The whole generated stub assembles with
`zig cc -target arm-linux-gnueabihf`.
```

## Open

- Upstream PR 12513's message makes the same false test claim. That is for
  the user to fix there.
- #4 itself is not closed by this fold.
