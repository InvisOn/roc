# Draft: Default-platform glibc programs built with `--opt=dev` crash at startup

> **FILED as roc-lang/roc#11995** on 2026-10-02: fixed upstream by PR #12001 the next day.

> **Fixed upstream.** Filed as issue #11995 on 2026-10-02; upstream fixed it the next day in PR #12001 (`a4ff90d640`), the same way as our reference did, and added a regression test. Nothing left to do.

> **Upstream or ours:** Upstream. The defect is in upstream's code and does not depend on our arm32 work.

> **Relevance to our arm32 work:** Found while bringing up `arm32linux` (glibc), where the dev backend is the only backend, so there is no LLVM path to fall back on. The reference fixes it for every target.

Filed as roc-lang/roc#11995 on 2026-10-02.

| | |
|---|---|
| Still an issue? | Yes, by code reading: upstream still has only `llvmBuildLinkAbi` (`src/cli/main.zig`); the dev path has no equivalent rule. Not reproduced today (needs a build). |
| Already upstream? | **Filed as #11995** (2026-10-02). Before filing: None found (searched issues and PRs, 2026-10-02). |
| Fix on our reference branch | `16d1ab893c` (shares the rule as `buildLinkAbi`, adds a CLI test that builds and runs x64glibc `--opt=dev`). |
| Before filing | Reproduce on a clean upstream build. |

Checked 2026-10-02 against upstream `main` at `d16a6598e4`.

---

**Title:** Default-platform glibc programs built with `--opt=dev` crash at startup

**What happens**

A program with no platform header, built for `x64glibc` or `arm64glibc` with the dev backend, crashes before `main`. The executable asks for the glibc loader (it has an `INTERP` header) but has no dynamic section. The LLVM path (`--opt=speed`) links the same program statically and works.

**Why it matters**

Anyone who builds a program without a platform header for `x64glibc` or `arm64glibc` with the dev backend gets an executable that crashes before it prints anything. Nothing at build time warns about it.

**How to reproduce**

```sh
printf 'main! = |_| {\n    echo!("Hello, World!")\n    Ok({})\n}\n' > /tmp/hello.roc
roc build --opt=dev --no-cache --target=x64glibc --output=/tmp/hello_dev /tmp/hello.roc
/tmp/hello_dev                                        # crashes before printing
readelf -l /tmp/hello_dev | grep -E 'INTERP|DYNAMIC'  # INTERP, no DYNAMIC
roc build --opt=speed --no-cache --target=x64glibc --output=/tmp/hello_speed /tmp/hello.roc
/tmp/hello_speed                                      # prints Hello, World!
```

**Environment**

- OS: Pop!_OS 24.04 LTS, x86_64, glibc 2.39
- Roc compiler version `release-fast-a932c654`
