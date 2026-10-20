# Draft: The snapshot tool records every dev-backend compile error as `NOT_IMPLEMENTED`

> **Upstream or ours:** Upstream. The bug is in upstream's code and has nothing to do with our arm32 work.

> **Relevance to our arm32 work:** While arm32 code generation was unfinished, real arm32 compile errors were recorded as `NOT_IMPLEMENTED`. They looked like "not supported yet" instead of failures. Our reference branch fixes this.

Not filed. For roc-lang/roc.

| | |
|---|---|
| Still an issue? | Yes (2026-10-20, upstream `main` at `5fc587cf51`, by reading the code). |
| Already upstream? | No issue or PR found (searched 2026-10-20). |
| Fixed on our reference branch? | Yes, in `d910f7aa39`. |
| Before filing | Nothing. Reading the code is enough. |

---

**Title:** The snapshot tool records every dev-backend compile error as `NOT_IMPLEMENTED`

**What happens**

A `type=dev_object` snapshot compiles a program to an object file for each target and stores a hash of the result. If compiling fails for any reason, the snapshot tool stores `NOT_IMPLEMENTED` instead of failing. That is the same value it stores for targets the dev backend does not support.

So when a supported target fails to compile, the snapshot looks like the target is simply not supported, and the snapshot passes.

**Where** (upstream `main` at `5fc587cf51`)

- `src/snapshot_tool/main.zig:4009-4012`, in `processDevObjectSnapshot` (line 3870). The `else |_|` branch catches every compile error and sets `hash_results[i].supported = false`.
- `src/snapshot_tool/main.zig:4073` writes `NOT_IMPLEMENTED` for every result marked unsupported.

**Why it matters**

`dev_object` snapshots exist to catch changes in generated code. Suppose a change makes a supported target fail to compile. Its hash turns into `NOT_IMPLEMENTED`, which reads as "this target is not supported". `--update-expected` then accepts it. The test cannot catch the very failure it is there for.

The function already skips unsupported targets before it compiles anything, so any error that reaches this branch is a real failure.

**How to reproduce**

We don't know of a program that makes a supported target fail to compile today, so this comes from reading the code:

```sh
grep -n 'else |_|' src/snapshot_tool/main.zig
```

The match at line 4009 is in the loop that hashes `result.object_bytes`. It marks every error as unsupported, and line 4073 writes those as `NOT_IMPLEMENTED`.

**Environment**

- OS: Pop!_OS 24.04 LTS, x86_64
- Roc compiler version `release-fast-a932c654`
