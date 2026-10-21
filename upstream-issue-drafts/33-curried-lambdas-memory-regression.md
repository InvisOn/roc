# Draft: The deep "curried lambdas" eval test now needs three times the memory

> **Upstream or ours:** Upstream's code. It started with the merge of PR #12330 (`534956997e`).

> **Relevance to our arm32 work:** It blocks our sync. On arm32 the test needs more memory than a 32-bit process can have, so it fails with `OutOfMemory`. Before #12330 it passed on arm32 with 1.06 GB.

Not filed. For roc-lang/roc.

| | |
|---|---|
| Still an issue? | Yes (2026-10-21, upstream `main` at `534956997e`, measured). |
| Already upstream? | No open issue found (searched 2026-10-21). Closed issue #11997 ("Make compiling curried lambda chains linear in their depth", closed 2026-10-18) is about this same test. It found the cost quadratic in depth and placed it in Monotype lowering. This looks like part of that cost coming back. |
| Fixed on our reference branch? | No. Not ours to fix. |
| Before filing | Mention #11997. The cause is measured (see "Where the time and memory go"). The fixes below are suggestions and are not tried. |

---

**Title:** The deep "curried lambdas" eval test needs three times the memory and five times the time since #12330

**What happens**

The eval test `issue 11698: curried lambdas (specialize=no)` in `src/eval/test/eval_deep_nesting_tests.zig` builds a function with 5,000 nested lambdas. Since #12330 was merged, compiling it takes much more memory and time.

On x86_64, with the eval runner built `ReleaseSmall`:

| Upstream `main` | Result | Peak memory | Test time |
|---|---|---|---|
| `73df27a5bb` (before #12330) | pass | 1.2 GB | 1.8 s |
| `534956997e` (#12330 merged) | pass | 3.4 GB | 9.4 s |

The variant without `(specialize=no)` is not affected: 1.8 s both times.

The runner's phase times do not show the extra time. Parse, can, check, interp and dev add up to about 0.4 s in both builds. The extra time is in the Boxy plan, which the runner does not time on its own (see below).

On a 32-bit target the test now fails. A 32-bit process cannot get 3.4 GB, so the compiler stops with `OutOfMemory` before any backend runs. We saw this with the eval runner built for `arm-linux-musleabihf` and run under qemu-arm: peak memory above 2.5 GB, then `OutOfMemory` after 68 s. Before #12330 the same test passed there with 1.06 GB in 15 s.

**Where the time and memory go**

We added temporary counters and timers to `src/postcheck/boxy/plan.zig` and ran the test once (x86_64, `ReleaseFast`). Almost all of the extra cost is in one step, `chooseRowJoinRepresentatives`, which #12330 added:

| Step in `analyzeProgram` | Time | Process memory after it |
|---|---|---|
| start | | 1,185 MiB |
| `computeRowJoins`: seeding the work list | 0 ms | 1,187 MiB |
| `computeRowJoins`: joining type pairs (8,333 pairs, 61 merges) | 2 ms | 1,188 MiB |
| `chooseRowJoinRepresentatives` | 2,322 ms | 3,357 MiB |
| the rest of `analyzeProgram` | 0 ms | |

Inside `chooseRowJoinRepresentatives`:

- It calls `rowJoinIdentityIsGround` once for each of the 6,317 types that took part in a join.
- Each call walks the whole type with a new `seen` hash set. The type of a lambda at nesting level k contains every level below it. So the walks visit 12,510,265 nodes in total. That is about 5,000² / 2, so the cost grows with the square of the depth.
- The memory those `seen` sets use is not given back between calls. The process grows by 2.2 GB during this step and stays there.
- In the end no join set had two compatible ground members (`row_join_members` is empty). So for this program the whole step produces nothing, but costs 2.3 s and 2.2 GB.

The joining itself is cheap. Parent chains in `row_joins` never got longer than 1, and `computeWorkerScopeChains` took 0 ms.

**Possible fixes** (not tried)

1. **Check groundness only where it can matter.** `chooseRowJoinRepresentatives` checks every identity for groundness (line 9999) before it knows the identity's group size. Only groups with at least two members are used (line 10013). With 61 merges, at most about 122 of the 6,317 identities are in such a group. Grouping first and checking groundness only for members of groups with two or more members would skip almost all of the walks here.
2. **Remember groundness between calls.** A type is ground exactly when all its parts are ground. Keeping one map from identity to result for the whole step, and filling it as the walks go, would visit each type node once. That makes the step linear in the size of the types, whatever the nesting. A type reached again while it is still being walked (a recursive type) would need the same treatment the current `seen` set gives it.
3. **Reuse one `seen` set.** If the walk stays per call, one set cleared with `clearRetainingCapacity` between calls would stop the memory from growing with each call. This alone fixes the memory but not the time.

Fix 1 or 2 removes the square-of-the-depth cost. Fix 2 also covers programs where many large types do land in shared groups.

**Where** (upstream `main` at `534956997e`)

- `src/eval/test/eval_deep_nesting_tests.zig:15` sets `depth = 5000`. The test is at lines 271-277.
- `src/postcheck/boxy/plan.zig:9987`, `chooseRowJoinRepresentatives`. Line 9999 checks every identity for groundness. Line 10013 skips groups with fewer than two members.
- `plan.zig:9932`, `rowJoinIdentityIsGround`. Line 9935 makes a new `seen` set for each call.
- `plan.zig:9733`, `computeRowJoins`, called from `analyzeProgram` at line 3865.
- #11997 placed the earlier cost in Monotype lowering. This one is in a different place, in the Boxy plan that #12330 added to.
- The change came with the merge of #12330 (`534956997e`, "reject forwarded closed rows"). Not narrowed to one commit.

**How to reproduce**

```sh
git checkout 534956997e
zig build build-test-eval-runner -Doptimize=ReleaseSmall --prefix /tmp/after
/usr/bin/time -v /tmp/after/bin/eval-test-runner --timeout 300000 \
  --filter 'issue 11698: curried lambdas' 2>&1 | grep -E 'curried|passed|Maximum resident'

git checkout 73df27a5bb
zig build build-test-eval-runner -Doptimize=ReleaseSmall --prefix /tmp/before
/usr/bin/time -v /tmp/before/bin/eval-test-runner --timeout 300000 \
  --filter 'issue 11698: curried lambdas' 2>&1 | grep -E 'curried|passed|Maximum resident'
```

Output at `534956997e`:

```
    1. issue 11698: curried lambdas (specialize=no)  (9361.0ms)  [parse:5.2 can:8.3 check:79.0 interp:155.7 dev:146.3]
    2. issue 11698: curried lambdas  (1827.5ms)  [parse:5.0 can:8.4 check:80.4 interp:69.2 dev:64.4 wasm:71.3]
1 passed, 0 failed, 0 crashed, 1 skipped (2 total) in 11579ms using 1 process(es)
	Maximum resident set size (kbytes): 3432164
```

Output at `73df27a5bb`:

```
    1. issue 11698: curried lambdas  (1880.4ms)  [parse:5.3 can:8.4 check:85.5 interp:76.4 dev:73.6 wasm:81.3]
    2. issue 11698: curried lambdas (specialize=no)  (1762.3ms)  [parse:5.3 can:8.3 check:82.4 interp:64.6 dev:60.7]
1 passed, 0 failed, 0 crashed, 1 skipped (2 total) in 3868ms using 1 process(es)
	Maximum resident set size (kbytes): 1217456
```

**Environment**

- OS: Pop!_OS 24.04 LTS, x86_64 (Linux 7.2.6)
- Zig 0.17.0
- Eval runner built from upstream `main`, `-Doptimize=ReleaseSmall`
