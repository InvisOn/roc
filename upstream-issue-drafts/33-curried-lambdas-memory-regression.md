# Draft: The deep "curried lambdas" eval test now needs three times the memory

> **Upstream or ours:** Upstream's code. It started with the merge of PR #12330 (`534956997e`).

> **Relevance to our arm32 work:** It blocks our sync. On arm32 the test needs more memory than a 32-bit process can have, so it fails with `OutOfMemory`. Before #12330 it passed on arm32 with 1.06 GB.

Not filed. For roc-lang/roc.

| | |
|---|---|
| Still an issue? | Yes (2026-10-21, upstream `main` at `534956997e`, measured). |
| Already upstream? | No open issue found (searched 2026-10-21). Closed issue #11997 ("Make compiling curried lambda chains linear in their depth", closed 2026-10-18) is about this same test. It found the cost quadratic in depth and placed it in Monotype lowering. This looks like part of that cost coming back. |
| Fixed on our reference branch? | No. Not ours to fix. |
| Before filing | Mention #11997. Find which phase uses the memory: the runner's phase times add up to about 0.4 s of the 9.4 s. |

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

The runner's phase times do not show the extra time. Parse, can, check, interp and dev add up to about 0.4 s in both builds. So the time goes into a step the runner does not time.

On a 32-bit target the test now fails. A 32-bit process cannot get 3.4 GB, so the compiler stops with `OutOfMemory` before any backend runs. We saw this with the eval runner built for `arm-linux-musleabihf` and run under qemu-arm: peak memory above 2.5 GB, then `OutOfMemory` after 68 s. Before #12330 the same test passed there with 1.06 GB in 15 s.

**Where** (upstream `main` at `534956997e`)

- `src/eval/test/eval_deep_nesting_tests.zig:15` sets `depth = 5000`. The test is at lines 271-277.
- #11997 says the earlier cost was in Monotype lowering: `nestedInstantiationContext` and `stepInstantiateCall`. That is the first place to look.
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
