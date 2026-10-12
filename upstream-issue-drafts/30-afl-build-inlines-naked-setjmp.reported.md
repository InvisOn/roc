# Draft: The AFL++ build of the fuzzers crashes: clang inlines the naked `setjmp`

> **FILED as roc-lang/roc#12197** on 2026-10-11: filed by the owner with the repro only; open; on Zig 0.17 the build stops earlier at draft 32, worth a comment on the issue.
> **No longer reproduces on current upstream (2026-10-11):** at `c1464a1dc0` (Zig 0.17) with AFL++ 5.03c built on LLVM 22, `fuzz-build` is produced, 21 random inputs exit 0, and gdb shows `setjmpImpl` called as a real function (its own return address), not inlined. The crash needed Zig 0.16 with an LLVM 17 `afl-cc`. The naked function still relies on not being inlined (hardening: mark it never-inline). Worth a comment on #12197.


> **Upstream or ours:** Upstream. Reproduced on clean upstream `233bb124dc` (2026-10-08). The x86_64 `setjmp` in `src/sljmp/linux.zig` is upstream's; our branch adds an arm32 implementation with the same shape.

> **Relevance to our arm32 work:** It blocks AFL++ fuzzing of the dev backend (fuzzing stage 1): every input crashes before the program reaches code generation. Our arm32 `setjmpImpl` is written the same way, so an AFL++-style rebuild for arm32 would break it the same way.

**Files and where to find them** (local, not in upstream)

- The input used: `/home/aj/repos/roc_32bit/.git/verify-tools/fuzz/smoke/in4` (any input crashes; the ticket below makes its own).
- The upstream build that crashed: `/home/aj/repos/roc_32bit/.git/verify-tools/relative-oracle/upstream/zig-out/bin/fuzz-build` (until the next relative-oracle run resets that worktree).

Filed as roc-lang/roc#12197 on 2026-10-11. The ticket holds the repro only; the explanation below was not included.

| | |
|---|---|
| Still an issue? | Yes by code (`setjmpImpl` unchanged at `faecf66d88`), but not reproducible on current upstream with Ubuntu's AFL++: since Zig 0.17 the fuzz build fails earlier, `afl-cc` (LLVM 17) cannot read Zig's bitcode (draft 32). Last reproduced 2026-10-08 at `233bb124dc` (Zig 0.16). To reproduce now needs an AFL++ built on a newer LLVM. Reproduced again 2026-10-11 by the owner with the Oct 8 Zig 0.16 `fuzz-build` of our branch (exit 134 without, 139 with `AFL_IGNORE_PROBLEMS=1`; gdb shows `setjmpImpl` .. `devRootWorker` as frames inlined at one address). When filing: file 32 first and say the Zig 0.17 build stops at 32. |
| Already upstream? | **Filed as #12197** (2026-10-11). Before filing: None found (searched issues and PRs for setjmp, AFL, segfault, 2026-10-08; again for setjmp, afl, fuzz crash, naked, AFL_IGNORE_PROBLEMS, fuzz-build, 2026-10-10). `src/sljmp/linux.zig` is unchanged at upstream `faecf66d88`. |
| Fix on our reference branch | None (upstream code; not ours to fix). |
| Before filing | Nothing. |

---

**Title:** The AFL++ fuzz binaries crash at once: clang inlines the naked `setjmpImpl`

**What happens**

`zig build -Dfuzz build-fuzz-build` links the fuzz object through `afl-cc -O3`, which optimizes Zig's LLVM output again. That pass inlines `X86_64.setjmpImpl`, a naked function called through a function pointer, into `compile_time_finalization.devRootWorker`. The naked body ends in `ret`, so it now returns from the middle of `devRootWorker`, and the binary crashes on the first input:

```
SIGSEGV in linux.X86_64.setjmpImpl () at src/sljmp/linux.zig:33
  linux.X86_64.setjmp () at src/sljmp/linux.zig:71
  compile_time_host.CrashBoundary.set () at src/eval/compile_time_host.zig:182
  compile_time_finalization.devRootWorker (...)
```

In the disassembly, `devRootWorker` holds the `setjmp` stores (`mov %rbx,0x0(%rdi)` ... `xor %eax,%eax`) followed directly by `ret`. The same program built through Zig's own pipeline (`zig build build-repro-build`, `zig-out/bin/repro-build`) does not crash.

Separately, before any input is read, the binary aborts with "forkserver is already up, but an instrumented dlopen() library loaded afterwards" unless `AFL_IGNORE_PROBLEMS=1` is set.

**Where**

`src/sljmp/linux.zig`: `setjmpImpl` is `callconv(.naked)` and reached through `setjmpFn`, a `*const fn` built with `@ptrCast(&setjmpImpl)`. Nothing marks it as not inlinable, and once the call is a direct call, LLVM's inliner treats the naked body as ordinary code. The aarch64 implementation is built the same way.

**Why it matters**

It makes the AFL++ fuzz targets that reach compile-time evaluation unusable: every input crashes, so AFL finds nothing but this.

**How to reproduce**

On x86_64 Linux with AFL++ installed (`apt install afl++`; tried with 4.09c), from the root of a roc-lang/roc checkout:

```sh
zig build -Dfuzz build-fuzz-build                       # writes zig-out/bin/fuzz-build (about an hour)
head -c 400 /dev/urandom > /tmp/fuzz-in
./zig-out/bin/fuzz-build < /tmp/fuzz-in; echo "exit $?"  # aborts: instrumented dlopen() library
AFL_IGNORE_PROBLEMS=1 AFL_IGNORE_PROBLEMS_COVERAGE=1 ./zig-out/bin/fuzz-build < /tmp/fuzz-in; echo "exit $?"   # 139
AFL_IGNORE_PROBLEMS=1 AFL_IGNORE_PROBLEMS_COVERAGE=1 gdb -batch -ex run -ex bt ./zig-out/bin/fuzz-build < /tmp/fuzz-in
```

The build writes only into the checkout's `.zig-cache/` and `zig-out/`; `/tmp/fuzz-in` can be deleted afterwards.

**Environment**

- OS: Pop!_OS 24.04 LTS, x86_64
- Roc compiler: built from source at `233bb124dc`
- AFL++ 4.09c (Ubuntu package)

---

## Follow-up after #12197 was closed (2026-10-11)

rtfeldman closed #12197: "Doesn't reproduce using that command. For future fuzz failures, a backtrace would be helpful; this could very well be happening because of an AFL thing and not a roc thing, but without a trace, there's no way to tell!"

He is right that it does not reproduce on current `main` and that it is a toolchain ("AFL") interaction. The crash needs Zig 0.16 bitcode linked by an `afl-cc` built on LLVM 17 (Ubuntu's `afl++` 4.09c). On current `main` (Zig 0.17) that `afl-cc` cannot build at all (#12207), and an `afl-cc` on LLVM 22 does not inline the function, so nothing crashes.

**Reproduced again 2026-10-11** with the only binary left from that combination: `zig-out/bin/fuzz-build` of our branch, built 2026-10-08 (`strings`: zig 0.16.0, clang version 17.0.6). Files: `.git/verify-tools/draft30/repro-12197.txt`, `disasm-12197.txt`, `disasm-12197-llvm22.txt`, input `fuzz-in-12197`. Plain run: exit 134 (the `dlopen` abort); with `AFL_IGNORE_PROBLEMS=1 AFL_IGNORE_PROBLEMS_COVERAGE=1`: exit 139.

Backtrace (frames #1-#4 have no address of their own: inlined into #4):

```
Thread 1 "fuzz-build" received signal SIGSEGV, Segmentation fault.
#0  0x0000555558a6a475 in linux.X86_64.setjmpImpl () at /home/aj/repos/roc_32bit/src/sljmp/linux.zig:35
#1  linux.X86_64.setjmp () at /home/aj/repos/roc_32bit/src/sljmp/linux.zig:73
#2  linux.setjmp () at /home/aj/repos/roc_32bit/src/sljmp/linux.zig:20
#3  compile_time_host.CrashBoundary.set () at /home/aj/repos/roc_32bit/src/eval/compile_time_host.zig:182
#4  compile_time_finalization.devRootWorker (context=0x7ffffffd5240, item_id=<optimized out>) at /home/aj/repos/roc_32bit/src/eval/compile_time_finalization.zig:3864
#5  0x0000555558a42092 in compile_time_finalization.evalDevProgramRoots (module=0x7fffe0de2000, state=0x7fffda44d800, problem_store=0x7fffe5fe5410, coverage=0x7fffda44d890, owners=0x7ffffffd6240, lowered=0x7ffffffd7768, native=0x7ffffffe0bd0) at /home/aj/repos/roc_32bit/src/eval/compile_time_finalization.zig:3691
#6  0x0000555558a1eee1 in compile_time_finalization.evalProgramRoots__anon_549596 (allocator=..., module=0x3db013714b1e4, state=0x7fffda44d800, problem_store=0x7fffe5fe5410, coverage=0x7fffda44d890, owners=0x0, options=..., lowered=0x293) at /home/aj/repos/roc_32bit/src/eval/compile_time_finalization.zig:3589
#7  compile_time_finalization.finalizeLoweredProgram__anon_540561.Driver.evaluate (self=0x7ffffffd6710, ordinal=<optimized out>) at /home/aj/repos/roc_32bit/src/eval/compile_time_finalization.zig:971
#8  0x00005555589a9767 in compile_time_finalization.finalizeLoweredProgram__anon_540561 (lowered=0x7ffffffd7768, root_count=10, program=0x7ffffffe0bd0) at /home/aj/repos/roc_32bit/src/eval/compile_time_finalization.zig:1091
#9  0x000055555898117c in compile_time_finalization.evaluateLoweredRootsWithObservations__anon_540418 (host=0x7ffffffd7768, compile_time_root_count=10, options=...) at /home/aj/repos/roc_32bit/src/eval/compile_time_finalization.zig:855
#10 compile_time_finalization.evaluateLoweredRoots (host=0x7ffffffd7768, compile_time_root_count=10, options=...) at /home/aj/repos/roc_32bit/src/eval/compile_time_finalization.zig:832
#11 compile_time_finalization.finalizeProgram () at /home/aj/repos/roc_32bit/src/eval/compile_time_finalization.zig:699
#12 0x00005555597605d8 in coordinator.Coordinator.evaluatePreparedModules (self=0x7ffff75e0000, replay_cached_debug=true, extra_cached=<optimized out>, program_root=<optimized out>) at /home/aj/repos/roc_32bit/src/compile/coordinator.zig:3070
#13 0x00005555588ed841 in coordinator.Coordinator.finishCheckedProgram (self=0x7ffff75e0000, mode=<optimized out>) at /home/aj/repos/roc_32bit/src/compile/coordinator.zig:2339
#14 compile_build.BuildEnv.finishCheckedProgram (self=0x7fffffff7180) at /home/aj/repos/roc_32bit/src/compile/compile_build.zig:1203
#15 0x00005555588e7124 in compile_build.BuildEnv.compileDiscovered (self=0x7fffffff7180) at /home/aj/repos/roc_32bit/src/compile/compile_build.zig:1193
#16 0x0000555555709412 in BuildFuzzDriver.run (buf=<optimized out>, len=<optimized out>, debug=false, mode=well_typed) at BuildFuzzDriver.zig:91
#17 0x0000555555703c6c in main (argc=1, argv=0x7fffffffdd78) at /home/aj/repos/roc_32bit/zig-pkg/afl_kit-0.1.0-NdJ3csgfAABGuiQ4P99kFuaVSy4DHMilISiGF_VKX3xl/afl.c:96
rip            0x555558a6a475      0x555558a6a475 <compile_time_finalization.devRootWorker+1557>
```

The crash address is inside `devRootWorker`: `setjmpImpl`'s body was copied into it, ending in its own `ret`, with no `call` before it, so `(%rsp)` is not a return address:

```
0x555558a6a445 <compile_time_finalization.devRootWorker+1509>:	mov    %edi,-0x500d8(%rax)
0x555558a6a44b <compile_time_finalization.devRootWorker+1515>:	mov    %rbx,(%rdi)
0x555558a6a44e <compile_time_finalization.devRootWorker+1518>:	mov    %rbp,0x8(%rdi)
0x555558a6a452 <compile_time_finalization.devRootWorker+1522>:	mov    %r12,0x10(%rdi)
0x555558a6a456 <compile_time_finalization.devRootWorker+1526>:	mov    %r13,0x18(%rdi)
0x555558a6a45a <compile_time_finalization.devRootWorker+1530>:	mov    %r14,0x20(%rdi)
0x555558a6a45e <compile_time_finalization.devRootWorker+1534>:	mov    %r15,0x28(%rdi)
0x555558a6a462 <compile_time_finalization.devRootWorker+1538>:	lea    0x8(%rsp),%rdx
0x555558a6a467 <compile_time_finalization.devRootWorker+1543>:	mov    %rdx,0x30(%rdi)
0x555558a6a46b <compile_time_finalization.devRootWorker+1547>:	mov    (%rsp),%rdx
0x555558a6a46f <compile_time_finalization.devRootWorker+1551>:	mov    %rdx,0x38(%rdi)
0x555558a6a473 <compile_time_finalization.devRootWorker+1555>:	xor    %eax,%eax
=> 0x555558a6a475 <compile_time_finalization.devRootWorker+1557>:	ret
0x555558a6a476 <compile_time_finalization.devRootWorker+1558>:	ud2
0x555558a6a478 <compile_time_finalization.devRootWorker+1560>:	movslq 0x3a34711(%rip),%rcx        # 0x55555c49
0x555558a6a47f <compile_time_finalization.devRootWorker+1567>:	movzbl (%rax,%rcx,1),%edx
```

The same code in the Zig 0.17 build linked by AFL++ 5.03c on LLVM 22 (upstream `c1464a1dc0`): `setjmpImpl` is a separate function, entered by a call whose return address is `devRootWorker+1877`; 21 random inputs exit 0:

```
compile_time_finalization[devRootWorker] + 1877 in section .text of /home/aj/repos/roc_32bit/.git/verify-tools/drafts-ve
0x555556ec02d2 <compile_time_finalization.devRootWorker+1874>:	sbb    $0xc085fe84,%eax
0x555556ec02d7 <compile_time_finalization.devRootWorker+1879>:	je     0x555556ec031e <compile_time_finalization.devRootW
=> 0x555555702030 <linux.X86_64.setjmpImpl>:	mov    %rbx,(%rdi)
0x555555702033 <linux.X86_64.setjmpImpl+3>:	mov    %rbp,0x8(%rdi)
0x555555702037 <linux.X86_64.setjmpImpl+7>:	mov    %r12,0x10(%rdi)
0x55555570203b <linux.X86_64.setjmpImpl+11>:	mov    %r13,0x18(%rdi)
0x55555570203f <linux.X86_64.setjmpImpl+15>:	mov    %r14,0x20(%rdi)
0x555555702043 <linux.X86_64.setjmpImpl+19>:	mov    %r15,0x28(%rdi)
0x555555702047 <linux.X86_64.setjmpImpl+23>:	lea    0x8(%rsp),%rdx
0x55555570204c <linux.X86_64.setjmpImpl+28>:	mov    %rdx,0x30(%rdi)
0x555555702050 <linux.X86_64.setjmpImpl+32>:	mov    (%rsp),%rdx
0x555555702054 <linux.X86_64.setjmpImpl+36>:	mov    %rdx,0x38(%rdi)
0x555555702058 <linux.X86_64.setjmpImpl+40>:	xor    %eax,%eax
0x55555570205a <linux.X86_64.setjmpImpl+42>:	ret
0x55555570205b <linux.X86_64.setjmpImpl+43>:	ud2
0x55555570205d:	nopl   (%rax)
```

Conclusion: not a Roc logic bug. LLVM 17's optimizer (run again by `afl-cc -O3`) inlined a naked function, which must never be inlined. Roc's code relies on that implicitly; marking `setjmpImpl` never-inline would make it robust against such toolchains, but on current `main` with a working AFL++ there is nothing to fix.

**Possible reply on #12197** (owner's call):

> Thanks, agreed: it was an AFL toolchain interaction. With Zig 0.16 and Ubuntu's AFL++ 4.09c (LLVM 17), `afl-cc -O3` inlined the naked `X86_64.setjmpImpl` into `devRootWorker`, so its `ret` ran without a `call` (crash at `devRootWorker+1557`; backtrace and disassembly attached). On current main that AFL++ can't build the fuzzers at all (#12207), and with AFL++ built on LLVM 22 `setjmpImpl` is a real call and nothing crashes. So nothing to fix now; optionally `setjmpImpl` could be marked never-inline so a toolchain can't do this again.

