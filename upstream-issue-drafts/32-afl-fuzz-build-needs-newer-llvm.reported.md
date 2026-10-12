# Draft: The documented AFL++ fuzz build fails on Zig 0.17: `afl-cc` cannot read Zig's bitcode

> **FILED as roc-lang/roc#12207** on 2026-10-11: filed by the owner; open.

> **Upstream or ours:** Upstream. Reproduced 2026-10-10 on a clean worktree of upstream `faecf66d88` (`.git/verify-tools/draft30/roc`), with Ubuntu's `afl++` 4.09c (LLVM 17.0.6).

> **Relevance to our arm32 work:** It blocks AFL++ fuzzing (fuzzing stage 1) before draft 30's crash can even be reached. Random fuzzing with `repro-build` still works.

**Files and where to find them** (local, not in upstream)

- Build log: `/home/aj/repos/roc_32bit/.git/verify-tools/draft30/build.log`.
- The clean upstream worktree: `/home/aj/repos/roc_32bit/.git/verify-tools/draft30/roc`.

Filed as roc-lang/roc#12207 on 2026-10-11.

| | |
|---|---|
| Still an issue? | Yes, reproduced again 2026-10-11 on a clean worktree of upstream `c1464a1dc0` (same error; log `.git/verify-tools/drafts-verify/32-build.log`); first seen 2026-10-10 at `faecf66d88`. |
| Already upstream? | **Filed as #12207** (2026-10-11). Before filing: None found (2026-10-10: searched all issues and PRs, any date, for afl, afl++, afl-cc, system-afl, fuzz build, fuzzing, bitcode, attribute kind, LLVM 17). Closest: #12082 (Zig 0.17 migration) fixed `-Dfuzz` options on a cold package cache and ran the parse fuzz harness, but does not mention the `apt` AFL++ (LLVM 17) failing; the maintainers likely fuzz through Nix or the `repro-*` executables. |
| Fix on our reference branch | None (upstream build and docs; not ours to fix). |
| Before filing | Nothing. Answered 2026-10-11: Zig 0.17.0 is built on LLVM 22 (`zig cc --version`: clang 22.1.8), so `afl-cc` must use LLVM 22 or newer; Ubuntu 24.04's `afl++` uses LLVM 17. |

---

**Title:** `CONTRIBUTING/fuzzing.md`'s `apt install afl++` no longer works: since Zig 0.17, AFL++ must be built on LLVM 22 or newer, and no Debian/Ubuntu release packages one

**What happens**

`CONTRIBUTING/fuzzing.md`'s prerequisite for Ubuntu/Debian is `sudo apt install afl++`, with no version requirement (last edited 2026-06-13, before the Zig 0.17 upgrade). Zig 0.17.0 is built on LLVM 22 (`zig cc --version` prints clang 22.1.8), and the last step of the fuzz build runs `afl-cc -O3` on Zig's bitcode. An AFL++ built on an older LLVM cannot read it, and the build fails:

```
+- run /usr/bin/afl-cc (build_obj) failure
error: Unknown attribute kind (91) (Producer: 'zig 0.17.0' Reader: 'LLVM 17.0.6')
1 error generated.
```

No `zig-out/bin/fuzz-*` binary is produced. Seen with Ubuntu 24.04's `afl++` 4.09c (LLVM 17). No Debian or Ubuntu release packages an AFL++ new enough (2026-10-11, from each release's `afl++` dependency): Debian bookworm clang-14, trixie clang-19, forky/sid clang-21; Ubuntu 24.04 clang-17, 25.10 clang-19, 26.04 clang-21, 26.10 (in development) clang-21. So the guide's Ubuntu/Debian line fails on every release today. CI does not notice: it builds the fuzz configuration with `-Dno-bin` and runs the `repro-*` executables, so it never runs `afl-cc`.

**How to reproduce**

With an AFL++ built on LLVM older than 22 (for example Ubuntu 24.04's `sudo apt install afl++`), from the root of a roc-lang/roc checkout:

```sh
zig build -Dfuzz build-fuzz-build
```

**Expected**

`CONTRIBUTING/fuzzing.md` says AFL++ must be built on LLVM 22 or newer (matching Zig 0.17) and how to get one, instead of `apt install afl++`; ideally `build.zig` checks `afl-cc`'s LLVM version and reports a clear error for an older one instead of the bitcode reader's "Unknown attribute kind".

**Where to get a working AFL++**

> **Tested end to end (2026-10-11):** on Pop!_OS 24.04, the script below installed AFL++ 5.03c on LLVM 22.1.8, and `zig build -Dfuzz build-fuzz-build` on upstream `c1464a1dc0` used `/usr/local/bin/afl-cc` and produced a working `fuzz-build`. A stale clone without `make clean` repeats the failure, hence `rm -rf` and `set -e`. Homebrew route untested.

- Homebrew (macOS and Linux): `brew install afl++` builds against Homebrew's `llvm` (23.1.3 as of 2026-10-11), new enough. The guide's macOS line should already work.
- Debian/Ubuntu: no packaged AFL++ is new enough, so build AFL++ yourself against LLVM 22. LLVM's own apt repository (apt.llvm.org) provides LLVM 22 for current Debian and Ubuntu releases, and AFL++'s `stable` branch supports LLVM 14 to 23:

  ```sh
  set -e
  sudo apt remove -y afl++
  wget https://apt.llvm.org/llvm.sh
  chmod +x llvm.sh
  sudo ./llvm.sh 22
  sudo apt install -y llvm-22-dev
  rm -rf AFLplusplus
  git clone --depth 1 -b stable https://github.com/AFLplusplus/AFLplusplus
  cd AFLplusplus
  make source-only LLVM_CONFIG=llvm-config-22 NO_PYTHON=1   # must print "[+] LLVM mode successfully built"
  sudo make install
  afl-cc --version                                          # clang version 22 or newer
  ```

  Remove the distribution's `afl++` package first (`sudo apt remove afl++`) so its older `afl-cc` is not found first on PATH.
  Without `NO_PYTHON=1`, a Python that the system loader cannot find (for example Homebrew's, when Homebrew is first on PATH) gets linked into `afl-showmap`; AFL++'s self-test then fails (`libpython3.14.so.1.0: cannot open shared object file`), LLVM mode is silently left out of `make install`, and `afl-cc` aborts with "Unable to find 'afl-compiler-rt.o'".
- Check any install with `afl-cc --version`: it must report clang/LLVM 22 or newer.

**Where**

`build.zig` (the `-Dfuzz` path with `system-afl`, the default) and `CONTRIBUTING/fuzzing.md` (install instructions).

**Environment**

- OS: Pop!_OS 24.04 LTS, x86_64
- Roc: upstream `faecf66d88`, Zig 0.17.0
- AFL++ 4.09c (Ubuntu package), LLVM 17.0.6
