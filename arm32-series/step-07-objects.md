# Step 7: ELF32 objects and linking

## Goal

`roc build --opt=dev --target=arm32musl` produces an executable that runs.
The dev backend writes an ELF32 object with REL relocations and DWARF, and
LLD links it with the platform and the vendored C runtime.

## Files from the reference snapshot

- `src/backend/dev/object/elf.zig`: `write32`, `section32`, `appendRel32`,
  `storeRelAddend`, `debugRelType32`, and the arm32 prongs of
  `addTextRelocation`, `addTextDataRelocation`, `addRodataRelocation`.
- `src/backend/dev/Relocation.zig`: `R_ARM_CALL` and `R_ARM_JUMP24`
  branches (`patchArm32BranchInstruction`), and the PC-relative movw and
  movt pair (`patchArmMovPrel`, `armMovAddend`).
- `src/backend/dev/Dwarf.zig`: four-byte addresses.
- `src/backend/dev/ObjectFileCompiler.zig`, `ObjectWriter.zig`,
  `object/coff.zig`, `object/macho.zig`: the plumbing.
- `src/backend/dev/arm32/CodeGen.zig`: `emitLoadDataAddress`,
  `codeRefVeneer`, `normalizeArtifactCode`.
- `src/default_platform/linux_runtime.zig`, `src/sljmp/`: what an arm32
  executable needs at run time.
- Snapshots: the `dev_object_*` files that change.
- Docs: `GUIDE.md`, "Objects: elf.zig, Relocation.zig, Dwarf.zig" and
  "The CLI end to end".

## Mirrors

The ELF64 writer `write64` in the same file. What differs: 32-bit headers
and symbols, REL records with the addend stored in the instruction instead
of RELA, and ARM attributes (`Tag_CPU_arch`, `Tag_ABI_VFP_args`).

## Holes

| Hole | Function | The concept |
|---|---|---|
| 7.1 | `write32`, the relocation section | REL versus RELA, and where the addend goes |
| 7.2 | `patchArmMovPrel` | an address built PC-relatively in two halves |
| 7.3 | `patchArm32BranchInstruction` | a 24-bit word offset, and its range |

## Check

```sh
python3 ci/arm32_link_smoke.py
zig build roc
./zig-out/bin/roc build --opt=dev --target=arm32musl --output=hello test/fx/hello_world.roc
qemu-arm-static ./hello
python3 ci/elf32_reader.py --header --attributes --sections --symbols <object>
zig build run-test-cli -- --suite platforms --filter test/fx/ --cross-target=arm32musl --cross-opt=dev --cross-run --cross-runner=qemu-arm-static
```

Test counts: to be measured (fx under qemu).

## Done when

- The link smoke test passes.
- `hello` prints under qemu.
- The measured fx count is reached, including `abi_call_shapes`.

## Prompt

> Read `arm32-series/README.md` and `arm32-series/step-07-objects.md` on
> the `notes` branch. Build step 7 on top of step 6 with its holes. Plant
> one bug hunt in the relocation code after I finish.

## Progress

- Not started.
