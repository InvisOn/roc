# Fold step 2, step 4 of 9: #3 abs64 relocation width

Branch `dispatch/isa`, commit `30ccea2335` "Write all eight bytes of an abs64
relocation on any host", from #3 (`9ee4d148e8`), keeping its original author
date. The hash is the one at the time of writing.

## Why

An `abs64` relocation fills an eight-byte address slot in generated x86_64
or aarch64 code. `patchAbsolutePointerOperand` took the width it wrote from
the word size of the machine running the compiler instead of from the slot:
eight bytes on a 64-bit host, four on a 32-bit host. The host's word size is
the wrong input. If that branch were ever reached, it would leave the upper
four bytes of the slot as they were, with no error. The new test shows this
on 32-bit x86.

In practice the branch is not reached today. Both callers patch code that
runs in the process that patches it: `HostSplice.zig:266` sets `image_base`
from `@intFromPtr(image.ptr)` and then makes the image executable, and the
machine-code shim runs code on its own machine. An `abs64` comes only from
x86_64 or aarch64 code, so it is only ever patched on a 64-bit host. On a
32-bit ARM host (the Pi 3, step 13 `arm32/host`) the code is arm32, which
the reference branch patches with its own `abs32` kind, chosen by ISA
(`Relocation.zig:198-200` there).

So the change is about meaning, not a live crash. After it, the slot width
comes only from the relocation kind: `abs64` is always eight bytes, and the
four-byte case arm32 needs gets its own explicit `abs32` kind in step 7
(`arm32/elf32-objects`) instead of hiding under the `abs64` name, with a
`BranchOutOfRange` check that was the wrong error for it.

## What changed

One file, `src/backend/dev/Relocation.zig`:

- `patchAbsolutePointerOperand` becomes `patchAbs64Operand`. It always does
  an eight-byte bounds check and an eight-byte write. The four-byte branch
  and its `BranchOutOfRange` check are gone.
- Its single caller, the `.abs64` case in `patchLinkedDataRelocation`, uses
  the new name.
- Test helper `readPointerFromCode` becomes `readAbs64Operand` and always
  reads a `u64`. One existing test casts the value back to `usize` for
  `@ptrFromInt`.
- New test "an abs64 data relocation writes all eight bytes of its operand":
  fills 16 bytes with `0xAA`, applies an abs64 relocation at offset 4 to a
  32-bit address, and checks all eight bytes.

## Review findings and outcomes

- **Nit 1, checked:** does the message's claim "fails on 32-bit x86 without
  this change" hold? Ran `Relocation.zig`'s tests as a 32-bit x86 Linux
  binary (`zig test -target x86-linux-musl` with the build's module wiring):

  | Code | 32-bit x86 | x86_64 |
  |---|---|---|
  | With the fix | passes (all 7 `Relocation` tests) | passes |
  | Old code, new test kept | fails: `code[8..12]` still holds `0xAA` | passes |

  The claim holds, so the message stayed as #3 wrote it.
- **Nit 2, applied:** the test comment "On a 32-bit machine only 4 bytes
  used to be written, leaving 0xAA in code[8..12]." described history. It
  now reads "The address fits in 32 bits, so the upper four bytes must be
  written as zeros, not left as 0xAA." Comment only.

## Tests

- Backend module tests: 513 passed, 2 skipped (one more than before: the
  new test).
- The 32-bit x86 run above.
- `zig fmt --check` passes after Nit 2.

## Final commit message

```
Write all eight bytes of an abs64 relocation on any host

patchAbsolutePointerOperand chose the width it wrote from the compiler's
own word size: eight bytes on a 64-bit host, four on a 32-bit host. An
abs64 operand is eight bytes in the generated code either way, so a
compiler running on a 32-bit machine left the upper four bytes of the
operand as they were.

The function, now patchAbs64Operand, always writes eight bytes. A new
test pins it, and fails on 32-bit x86 without this change.
```

## Open

- #3 is closed at step 8.
- The reference branch still has the old `patchAbsolutePointerOperand`
  with its four-byte branch (`Relocation.zig:310` there). The plan step
  that brings in its relocation work (step 7) must keep `patchAbs64Operand`
  and not bring the old branch back.
