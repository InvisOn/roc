# PR draft: Choose the dev backend's instruction set by exhaustive switch over Isa

Description of the PR containing only the `isa-switch` commit: InvisOn/roc#11 (fork only; not filed upstream).

The shared dev backend driver (`LirCodeGen`, `FrameBuilder`,
`CallingConvention`) chose between x86_64 and aarch64 in about 220 places,
each by comparing the target's architecture with one of the two and
taking the other branch otherwise. Every such `else` silently stands for
"the other architecture": a third instruction set would be routed into
whichever branch happened to be the `else`, with no error.

That had already happened to `aarch64_be`. 140 of the checks were
`target.toCpuArch() == .aarch64` without `.aarch64_be`, so a big-endian
aarch64 target took the x86_64 branch at each of them, while the checks
that did name it took the aarch64 one. No `RocTarget` is `aarch64_be`, so
nothing reached this, but the backend never served it.

`isa.zig` adds the `Isa` enum: the two instruction sets the dev backend
emits. It is a new enum rather than `roc_target`'s `CpuArchClass` because
`CpuArchClass` also has `aarch64_be`, `arm`, `wasm32` and `other`; a switch
over it would need an arm for each architecture the dev backend has no
code generator for, every one of them dead. `isaOfOrNull` maps a
`RocTarget` to its `Isa`, or to `null` for every other architecture,
`aarch64_be` included, since both emitters write little-endian code.
`isaOf` is its compile-time form for the code generators; a target
without an `Isa` is a compile error that names the target.

Every instruction-set choice in the driver is now an exhaustive
`switch (isa)` that names each instruction set's answer: never
`isa == .x86_64`, and never a test cached in a `bool`, so adding an
instruction set makes each choice a compile error until it has its own
answer. A condition that combines the instruction set with something
else is a switch that yields it, for example
`switch (isa) { .x86_64 => is_windows, .aarch64 => false }`.
`FrameBuilder`'s and `CallingConvention`'s cached `is_x86_64` /
`is_aarch64` flags are gone. A switch on the comptime `isa` compiles only
the arm it takes, as `if (comptime ...)` did. `design.md` states the rule
in a new section, "Dev Backend Instruction Sets".

The other lists of the dev backend's architectures now ask `isaOfOrNull`:
`ObjectFileCompiler`'s cross-compilation dispatch and
`host_lir_codegen_available` (both accepted `aarch64_be`, which no code
generator could build), and the CLI's hot-reload capture prefix
(`devCapturePrefix`). `LirCodeGen`'s tests skip on a host without a code
generator by `host_lir_codegen_available` instead of their own
architecture checks, and their two host-dependent stack offsets switch on
the host's `Isa`. `aarch64/CodeGen.zig` and `aarch64/Emit.zig` reject
`aarch64_be` like `isaOf`. The big-endian compile error in
`num_from_le_bytes_unchecked`, which `isaOf`'s rejection made unreachable,
becomes one compile-time little-endian assert at the top of `LirCodeGen`.

No change to generated code: x86_64 and aarch64 output is byte-identical
(0 of 2,394 eval cases differ against the parent commit, and no
`dev_object` snapshot changes, Windows and macOS targets included).

🤖 Generated with [Claude Code](https://claude.com/claude-code)
