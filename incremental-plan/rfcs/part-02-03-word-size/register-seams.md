# Register seams: state and findings

The register seams of `word-size-2-3-plan.md` D1: each architecture's code
generator names the registers the shared driver uses, by role, instead of
the driver naming x86_64 and aarch64 registers. Decided 2026-11-18 to go
into part 6 (N-1 B), prototyped first on a local branch.

## State (2026-11-18)

- Branch `isa-register-seams` (worktree `.workspaces/isa-register-seams`),
  local only, on `isa-word-size` (`896ca8b108`). Each commit was checked
  with the relative oracle (x86_64 and aarch64 output byte-identical).
  - `ad32b1ec5a` role registers: frame, stack, scratch,
    caller-stack-argument base, tail-call target and delta, Roc return
    registers and the incoming stack-argument offset come from
    `Emit(target).CC`.
  - `f484b7e684` entry-code save registers: `RESULT_PTR_SAVE_REG` and
    `ROC_OPS_SAVE_REG` in `CC`; the entry code,
    `reserveArgumentRegisters` and the RocOps pinning in lambda
    compilation read them.
- The commits use no width names (`word_width` and the others), so they
  can be cherry-picked onto `main` without upstream PR 12983. The same
  diff of the first commit applied cleanly on plain `main`.
- Next piece, not started: the temporary registers (reference
  `cc1c5fa33d`), such as the 16-register lists in the driver.

## Findings, not yet moved

Found in the review of `f484b7e684`. The RocOps register (R12, X20) and
the result-pointer register (RBX, X19) are still written directly in:

- the code generators' starting register masks (`x86_64/CodeGen.zig`
  near line 59, `aarch64/CodeGen.zig` near line 61);
- the frame layouts in `FrameBuilder.zig` (near lines 551 to 578, and the
  masks near 666, 718 and 756);
- the Windows R12 save and restore in `CallingConvention.zig` (near lines
  200 and 1022);
- the entry wrappers in `LirCodeGen.zig` (near lines 22666 and 22749).
  These are left on purpose: there the roles differ from the `CC` names
  (the aarch64 wrapper holds the result pointer in X20).

All of these sit in one architecture's own file or function, so an arm32
backend writes its own versions; moving them to `CC` would be a further
seams step, not needed for arm32 to work. If `CC.ROC_OPS_SAVE_REG` ever
changes, these places must change with it.

Also: `LirCodeGen.zig` near line 697 has a stale upstream comment,
"Register where RocOps pointer is saved", above a field that no longer
exists.

Other open review points in these commits:

- x86_64 defines `TAIL_CALL_DELTA_REG` (R10) although its tail calls do
  not use it, because the driver declares the constant for every
  architecture.
- `callee_saved_used` is a `u16` on x86_64 and a `u32` on aarch64; the
  driver writes `|= @intCast(...)` of a `u32` bit mask.
