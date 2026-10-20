# Draft: The snapshot tool records every dev-backend compile error as `NOT_IMPLEMENTED`

> **Upstream or ours:** Upstream. The defect is in upstream's code and does not depend on our arm32 work.

> **Relevance to our arm32 work:** While arm32 code generation was incomplete, real arm32 compile failures were recorded as `NOT_IMPLEMENTED` and looked like "not supported yet". The reference fixes it.

Not filed. For roc-lang/roc.

| | |
|---|---|
| Still an issue? | Yes, by code reading: in `src/snapshot_tool/main.zig` the object-compile call still ends in `else |_| { ... supported = false }`. |
| Already upstream? | None found (searched issues and PRs, 2026-10-02). |
| Fix on our reference branch | `d910f7aa39`. |
| Before filing | Nothing; code reading is enough. |

Checked 2026-10-02 against upstream `main` at `d16a6598e4`.

---

**Title:** The snapshot tool records every dev-backend compile error as `NOT_IMPLEMENTED`

**What happens**

For `type=dev_object` snapshots, any error from compiling the object file is turned into the `NOT_IMPLEMENTED` hash. A real code-generation failure for a supported target therefore looks like an unsupported target, and the snapshot passes.

**Where** (upstream `main` at `5fc587cf51`)

- `src/snapshot_tool/main.zig:4009-4012`, in `processDevObjectSnapshot` (line 3870): the `else |_|` branch of the object-compile call sets `hash_results[i].supported = false` for every error.
- `src/snapshot_tool/main.zig:4073`: an unsupported target is written as `NOT_IMPLEMENTED`.

**Why it matters**

`dev_object` snapshots exist to catch changes in generated code. With this behaviour, a regression that makes a supported target fail to compile shows up as its hash turning into `NOT_IMPLEMENTED`, which reads as "this target is not supported", and `--update-expected` accepts it. The test cannot catch the failure it is there for.

**How to reproduce**

No program is known that makes a supported target fail to compile today, so this is seen by reading the code:

```sh
grep -n 'else |_|' src/snapshot_tool/main.zig
```

The match in the per-target loop that hashes `result.object_bytes` sets `supported = false` for every error; further down, an unsupported target is written as `NOT_IMPLEMENTED`.

**Environment**

- OS: Pop!_OS 24.04 LTS, x86_64
- Roc compiler version `release-fast-a932c654`
