# Draft: The snapshot tool hashes `dev_object` programs that failed to type-check

> **FILED as roc-lang/roc#12199** on 2026-10-11: filed by the owner; open.

> **Upstream or ours:** Upstream. The defect is in upstream's code and does not depend on our arm32 work.

> **Relevance to our arm32 work:** We made this mistake ourselves: a snapshot we added had a type error and was hashed anyway. We now check new snapshots for `<runtime_error>` by hand.

Filed as roc-lang/roc#12199 on 2026-10-11.

| | |
|---|---|
| Still an issue? | Yes, reproduced 2026-10-11 on a clean upstream `c1464a1dc0` build: `snapshot` exits 0, the MONO section has `main = |a, b| a - <runtime_error> + b`, a hash line is written (`x64musl=2ae3a38d...`), and there is no PROBLEMS section. |
| Already upstream? | **Filed as #12199** (2026-10-11). Before filing: None found (searched issues and PRs, 2026-10-02). |
| Fix on our reference branch | Not fixed by us. |
| Before filing | Nothing (reproduced on clean upstream 2026-10-11). |

---

**Title:** The snapshot tool hashes `dev_object` programs that failed to type-check

**What happens**

For a `type=dev_object` snapshot whose entry point is a function, a type error in the program is not reported. The ill-typed expression becomes `<runtime_error>` in the MONO section, object code is generated for it, and `snapshot --update-expected` writes hash lines, prints nothing and exits 0. There is no PROBLEMS section.

**Why it matters**

A snapshot is supposed to pin the code generated for a working program. Here a program that does not type-check is accepted and its hashes are stored, so the snapshot pins the output of a broken program and nobody is told. The only sign is `<runtime_error>` in the MONO section, which a reviewer has to notice by reading it.

**How to reproduce**

Save this as `test/snapshots/dev_object_probe.md`. The program subtracts a string from an `I64`.

```markdown
# META
~~~ini
description=Probe: a dev_object snapshot whose program has a type error
type=dev_object
~~~
# SOURCE
## app.roc
~~~roc
app [main] { pf: platform "./platform.roc" }

main : I64, I64 -> I64
main = |a, b| a - "x" + b
~~~
## platform.roc
~~~roc
platform ""
    requires {} { main : I64, I64 -> I64 }
    exposes []
    packages {}
    provides { "roc_main": main_for_host }
    targets: {
        inputs_dir: "targets/",
        x64glibc: { inputs: [app] },
    }

main_for_host : I64, I64 -> I64
main_for_host = main
~~~
```

Then:

```sh
zig build build-snapshot-tool
./zig-out/bin/snapshot --update-expected test/snapshots/dev_object_probe.md; echo "exit $?"
grep -n 'runtime_error\|PROBLEMS\|^x64musl' test/snapshots/dev_object_probe.md
rm test/snapshots/dev_object_probe.md
```

Result: `exit 0`, no output from the tool, a line `main = |a, b| a - <runtime_error> + b` in the MONO section, a hash line for every target, and no PROBLEMS section.

**Expected**

The tool reports the type error and fails the snapshot, as it does for other snapshot types.

**Note: a different failure when the entry point is a value**

If the provided `main` is a value and not a function (as in `test/snapshots/dev_object_arithmetic.md`, changing `add(3, 4)` to `add("x", 4)`), the tool does not hash anything: it aborts with `panic: static data invariant violated: crash in initializer 0 is not construction LIR` (`src/static_data.zig`). That is a crash where a diagnostic is expected, and probably the same missing check.

**Environment**

- OS: Pop!_OS 24.04 LTS, x86_64
- Roc compiler version `release-fast-a932c654`

---

## Follow-up after #12199 was closed (2026-10-11)

rtfeldman closed it as intended: "This is how it's supposed to work. You pass `--check-expected` to have errors fail the snapshot (unless they are recorded in the EXPECTED section)."

Our ticket showed only `--update-expected`, the mode that writes whatever comes out, so it read as a misuse. Checked again on a clean upstream `c1464a1dc0` snapshot tool:

- `snapshot --check-expected` on the probe: exit 0, no output. After `--update-expected` records it, `--check-expected` again exits 0.
- The recorded file has META, SOURCE, MONO (with `main = |a, b| a - <runtime_error> + b`) and DEV OUTPUT, and no PROBLEMS or EXPECTED section.
- `processDevObjectSnapshot` (`src/snapshot_tool/main.zig`, from line 3917) never collects reports and writes no PROBLEMS/EXPECTED section; in `--check-expected` it compares only the DEV OUTPUT hashes.

So the rule in his reply holds for the other snapshot types but not for `dev_object`: a type error passes in both modes.

**Possible reply on #12199** (owner's call):

> Thanks. I should have shown `--check-expected`: it passes too. With the probe recorded, `snapshot --check-expected test/snapshots/dev_object_probe.md` exits 0 with no output. For `dev_object` snapshots there is no EXPECTED or PROBLEMS section to record errors in: `processDevObjectSnapshot` writes only META, SOURCE, MONO and DEV OUTPUT, and `--check-expected` compares only the DEV OUTPUT hashes. So a type error in a `dev_object` program is never reported in either mode. If that's intended for `dev_object`, fine to leave closed.

