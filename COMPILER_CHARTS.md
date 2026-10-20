# Compiler charts

The Roc compiler's pipeline today, and with
the arm32 dev backend added. Written 2026-10-02 from `design.md`, the source
layout and `src/backend/dev/arm32/DESIGN.md`.

## Today (upstream, without our changes)

```mermaid
flowchart TD
  src["Roc source (.roc)"] -->|text| parse["parse"]
  parse -->|syntax tree| can["canonicalize"]
  can -->|CIR: names resolved| check["check: type solver"]
  check -->|checked module, cached| mono
  subgraph post["postcheck: specialize (strategy lss)"]
    mono["Monotype"] --> lifted["Monotype Lifted"] --> lsolved["Lambda Solved"] --> lmono["Lambda Mono"]
  end
  check -.->|strategy boxy: no specialization| lir
  lmono -->|lower, layouts chosen| lir["LIR and its passes<br/>ARC inserts incref and decref"]
  lir --> interp["LIR interpreter<br/>compile-time evaluation"]
  lir --> llvm["LLVM backend"]
  lir --> wasm["wasm backend"]
  lir --> driver
  subgraph dev["dev backend"]
    driver["LirCodeGen: shared driver<br/>written for 64-bit registers"]
    abi["CallingConvention, layout/abi<br/>x86_64 and aarch64 C ABIs"] -->|where arguments go| driver
    driver -->|if x86_64| x86["x86_64<br/>CodeGen, Emit, Registers"]
    driver -->|else| a64["aarch64<br/>CodeGen, Emit, Registers"]
    x86 -->|code and relocations| ow["ObjectWriter<br/>ELF64, Mach-O, COFF"]
    a64 -->|code and relocations| ow
  end
  ow -->|app object file| link["linker: ld.lld"]
  host["platform host and runtime objects<br/>builtins, compiler-rt, libc"] --> link
  link --> exe["executable"]
```

## With the arm32 changes

Green is new, amber is existing code we change. Everything above LIR is
untouched.

```mermaid
flowchart TD
  src["Roc source (.roc)"] -->|text| parse["parse"]
  parse -->|syntax tree| can["canonicalize"]
  can -->|CIR: names resolved| check["check: type solver"]
  check -->|checked module, cached| mono
  subgraph post["postcheck: specialize (strategy lss)"]
    mono["Monotype"] --> lifted["Monotype Lifted"] --> lsolved["Lambda Solved"] --> lmono["Lambda Mono"]
  end
  check -.->|strategy boxy: no specialization| lir
  lmono -->|lower, layouts chosen| lir["LIR and its passes<br/>ARC inserts incref and decref<br/>unchanged: already word-size generic"]
  lir --> interp["LIR interpreter<br/>compile-time evaluation"]
  lir --> llvm["LLVM backend"]
  lir --> wasm["wasm backend"]
  lir --> driver
  subgraph dev["dev backend"]
    driver["LirCodeGen: shared driver<br/>word size from the target: 4 or 8 bytes<br/>one exhaustive switch over the ISA"]:::changed
    abi["CallingConvention, layout/abi<br/>adds arm32: AAPCS, hard float"]:::changed -->|where arguments go| driver
    driver -->|x86_64| x86["x86_64<br/>CodeGen, Emit, Registers"]
    driver -->|aarch64| a64["aarch64<br/>CodeGen, Emit, Registers"]
    driver -->|arm32, open: how much 64-bit-on-32-bit<br/>lowering stays in the driver| a32["arm32<br/>CodeGen, Emit (A32, VFP, NEON), Registers"]:::new
    x86 -->|code and relocations| ow["ObjectWriter<br/>adds ELF32 with REL relocations"]:::changed
    a64 -->|code and relocations| ow
    a32 -->|code and relocations| ow
  end
  ow -->|app object file| link["linker: ld.lld"]
  host["platform host and runtime objects<br/>adds targets arm32musl, arm32linux"]:::changed --> link
  link --> exe["executable<br/>also for ARMv7 boards"]
  subgraph checks["checks we add"]
    asm["real assembler<br/>encoder bytes must match"]:::new
    oracle["64-bit oracle<br/>x86_64 and aarch64 output must not change"]:::new
    hw["qemu and Raspberry Pis<br/>run the tests on arm32"]:::new
  end
  asm -.->|checks| a32
  oracle -.->|checks| driver
  hw -.->|runs| exe
  classDef new fill:#1d6f63,stroke:#12493f,color:#ffffff
  classDef changed fill:#8a5a00,stroke:#5c3c00,color:#ffffff
```
