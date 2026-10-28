# ARM32 Dev Backend: Walkthroughs

Guided tours of the arm32 work, one phase at a time (the phases are the cut
points in `arm32-dev-backend-verification.md`). Each explains what changed,
why the plan needed it, how it works, and what the checks prove, with places
in the code to read. Written for the owner, who will present the work to the
Roc maintainers.

## Phase 1: a safety net, then making the driver arm32-aware

Commits #1-#11: the plan, the first encoder batch (Track B), A0 and A1.

### The problem phase 1 solves

Roc's dev backend compiles LIR (the compiler's low-level intermediate
representation) straight to machine code, without LLVM. Most of it is one
large ISA-neutral **driver**, `src/backend/dev/LirCodeGen.zig`, which walks
LIR and asks a per-ISA code generator for instructions. Before this work the
driver knew two ISAs, x86_64 and aarch64, and its decisions were written as
two-way tests: `if (arch == .x86_64) ... else ...`. Adding a third ISA to a
file full of two-way tests has two dangers:

1. **Silent misrouting:** an `else` branch written for aarch64 would quietly
   run for arm32 too, producing wrong code without any error.
2. **Collateral damage:** rewriting the driver to make room for arm32 could
   change what it generates for x86_64 and aarch64, which real users run.

Phase 1 answers danger 2 with a safety net (A0) before touching the driver,
and danger 1 by making every architecture decision explicit (A1).

### Track B, first batch: an encoder that cannot lie (#3)

`src/backend/dev/arm32/Emit.zig` turns "add r0, r1, #4" into the four bytes
the CPU executes. Encoders are easy to get subtly wrong, so it is checked
against a real assembler: `ci/arm32_encoding_oracle.s` lists instructions in
assembly syntax next to the Zig call that should produce them;
`ci/arm32_encoding_oracle.py` assembles the file with `zig cc` (LLVM's
assembler) and generates one byte-exact test per line into
`encoding_oracle_tests.zig`. If the encoder and the assembler disagree, a test
fails; if someone adds an encoder function without an oracle line, the
`run-check-arm32-encoding-oracle` check fails.

One design choice worth knowing: A32 can only encode certain immediates (an
8-bit value rotated by an even amount). The encoder takes them as a `ModImm`
type, so an unencodable immediate is a compile-time or checked error at the
call site, never something the encoder quietly works around. That follows
AGENTS.md's rule against fallbacks in the compiler.

Read: `arm32/Emit.zig` (the `ModImm` section and any data-processing
function), and a few entries of `ci/arm32_encoding_oracle.s`.

### A0: byte-identity oracles, the safety net (#4)

Idea: if every x86_64 and aarch64 object the compiler produces is
byte-for-byte the same before and after a change, the change cannot have
altered 64-bit behaviour. A0 records those bytes.

- **Six new `dev_object` snapshots** (`test/snapshots/dev_object_*.md`)
  compile small programs aimed at the code Track A would touch (floats,
  Dec/I128, lists with closures, recursion, many arguments, strings) and
  store a hash of the object for every target.
- **`--write-dev-code-hashes` / `--check-dev-code-hashes`** in the eval
  runner compile every eval test case (1961) for x64musl and arm64musl
  through the object-file path and store each object's Blake3 hash in
  `test/dev_code_hashes/eval.blake3`. `run-check-dev-code-hashes` checks it in
  minici.

Three lessons from building it (recorded in DESIGN.md, "Learnings"):

- **JIT code cannot be a golden reference.** The plan first asked to hash
  code as generated for in-process execution, but that embeds absolute host
  addresses, which change every run. Object files use relocations instead,
  so their bytes are stable, and one file covers both ISAs on any host. (The
  same fact caused a CI failure later: a test that asked for in-process
  arm32 code on a 64-bit host got a host address too large for 32 bits.)
- **Procedure names change with every compiler build.** Symbol names digest
  a hash of the compiler itself, so every commit would change every hash.
  A0 rewrites them to first-appearance numbers
  (`ProcIdentity.canonicalizeSymbolNames`) before hashing, and was checked
  by rebuilding with a different compiler version: all hashes still matched.
- **LIR images drop some data** the object path needs (the recursive-layout
  keys), so the hashes come from the live lowering instead (an open defect in
  the issues note).

What it proves: the per-commit sweep checked every commit from A0 on against
these files and found no change, so no step of the arm32 work altered
x86_64 or aarch64 output.

Read: `src/eval/test/parallel_runner.zig` (search `DevCodeHashMode`) and one
of the new snapshot files.

### A1: every architecture decision made explicit (#5-#11)

**Dispatch (#5).** New `src/backend/dev/isa.zig` defines
`Isa = { x86_64, aarch64, arm32 }`. Every place the driver chooses by
architecture now either:

- switches exhaustively on `Isa`, so adding `arm32` forces an arm32 answer
  (Zig refuses a switch that misses a case), or
- goes through `Isa.binaryIs`, which is a **compile error** when the target
  is arm32.

So a missing arm32 path cannot run silently; it stops the build with a list
of exactly the places to handle. That list was J1's to-do list. About 250
two-way tests were converted mechanically, with byte-identical output.

**Register budget, D10 (#7).** The driver takes temporary registers from a
bounded pool and never spills (moves values to memory to free registers);
running out is an invariant violation. The pools moved into each ISA's
`CodeGen`, which now records a **high-water mark**. Measuring it over the
eval corpus showed x86_64 already peaks at 12 of its 13 registers; arm32 has
11. So the 64-bit instruction sequences could not simply be reused for
arm32. That measurement is why J1 wrote leaner arm32 sequences, and why
J3a's eval runs found two register-exhaustion bugs.

**The CC seam (#8).** The driver used to name registers directly
(`if x86_64 .RBP else .FP`). Now it asks the ISA's calling-convention
namespace (`CC.BASE_PTR`, `CC.ROC_RET_REGS`, ...), so arm32 plugs in its own
by defining its `CC`.

**The facade (#9, #10, #11).** 55 small helpers whose bodies were an
x86_64/aarch64 choice (loads and stores by width, compares, jumps, register
arithmetic) moved into each ISA's `CodeGen` with one shared signature. The
driver calls `self.codegen.helper(...)`, and arm32 supplies its own version.
Raw instruction calls in the driver went from 585 to 502. #11 records that
the bigger lowering *strategies* (i128, SIMD, overflow checks, entry
wrappers) were deferred. They were never given facade signatures, which is
the open decision in `arm32-dev-backend-facade-decision.md`.

What the checks prove: the dev_object snapshots and eval hashes are
unchanged at every A1 commit (the sweep), the A1 acceptance searches pass
(the arch tests left are host-side test guards; the arm32 compile-error
gates are in place), and the one A1 criterion not met is the register-name
search, part of that same open decision.

Read: `src/backend/dev/isa.zig` (short), then search `LirCodeGen.zig` for
`binaryIs(` and for `switch (isa)`, and look at one facade helper in all
three `CodeGen.zig` files (for example `emitLoadStack`).

### Questions to check your understanding

1. Why is a compile error on arm32 (`binaryIs`) safer than an `else` branch?
2. Why can object-file bytes be a golden reference when JIT bytes cannot?
3. What would the eval hash file show if an A2 commit had changed how
   x86_64 stores a 16-bit value?
4. Why did measuring x86_64's register high-water mark matter for arm32?
