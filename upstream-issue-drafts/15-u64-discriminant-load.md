# Draft: Dev backend: is the padding after a tag union's discriminant always zero?

> **Upstream or ours:** Upstream's code. Probably not a bug: see "What we found" below.

> **Relevance to our arm32 work:** None in particular. We noticed it while reading the backend.

Not filed. For roc-lang/roc.

| | |
|---|---|
| Still an issue? | Probably not (2026-10-20, upstream `main` at `5fc587cf51`, by reading the code). The 8-byte load is used only when a discriminant is read into a `U64` local, and upstream's lowering always reads discriminants into `U32` locals. |
| Already upstream? | No issue or PR found (searched 2026-10-20). |
| Fixed on our reference branch? | No. |
| Before filing | Probably don't file. At most, ask whether the backend should assert that a discriminant is never read into a `U64`. |

---

**Title:** Dev backend: is the padding after a tag union's discriminant always zero?

**What might happen**

`loadAndMaskDiscriminant` loads a tag union's discriminant as 4 or 8 bytes. It masks the loaded value only when the discriminant is smaller than 4 bytes. If it loads 8 bytes for a 4-byte discriminant, the upper 4 bytes come from the padding after it. If that padding is not zero, the comparison could see the wrong tag.

**What we found**

The load is 8 bytes only when the discriminant is read into a `U64` local. Every place in upstream's lowering that reads a discriminant uses a `U32` local, so the load is 4 bytes and no padding is read. A 4-byte discriminant also needs more than 65,536 variants.

The other place that loads a discriminant, the refcount helper for tag unions, loads 8 bytes but then masks to the discriminant's size, so it is safe too.

So the problem can't happen with LIR that upstream produces today. It could only happen with LIR that reads a 4-byte discriminant into a `U64` local.

**Where** (upstream `main` at `5fc587cf51`)

- `src/backend/dev/LirCodeGen.zig:11351-11424`, `loadAndMaskDiscriminant`. It loads 8 bytes (`.w64`) unless `disc_use_w32` is set (lines 11366-11389). It masks only when the discriminant is smaller than 4 bytes (lines 11410-11421).
- `LirCodeGen.zig:13362-13376`, `generateDiscriminantAccess`. It passes `disc_use_w32 = target_layout != .u64`, so it loads 4 bytes unless the target local is a `U64`.
- `src/postcheck/solved_lir_lower.zig:8387`, `10348`, `10888`, `11884`, `12019-12020`, `12066`, `13005` and `13338`. Each creates a discriminant local with layout `.u32`.
- `LirCodeGen.zig:12795-12818`, the tag-union refcount helper. It loads 8 bytes when there is room, then masks to the discriminant's size (lines 12813-12818).

**How to reproduce**

Not reproduced. Upstream's lowering doesn't produce the LIR that would trigger it.

```sh
grep -n -A30 'fn loadAndMaskDiscriminant' src/backend/dev/LirCodeGen.zig
grep -n 'disc.target_layout != .u64' src/backend/dev/LirCodeGen.zig
grep -n 'RefOp.discriminant' src/postcheck/solved_lir_lower.zig
```

**Environment**

- OS: Pop!_OS 24.04 LTS, x86_64
- Roc compiler version `release-fast-a932c654`
