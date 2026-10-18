# Upstream issue drafts

Personal notes; not committed. One draft per finding from the arm32 work,
for roc-lang/roc. Filed so far (these drafts, and the fixed 21, 22 and 28, deleted 2026-10-17; copies stay on the `notes` branch): 01 (#11995), 04 (#12200), 06 (#12202), 08 (#12198), 09 (#12199), 17 (#12201), 29 (#12176), 30 (#12197) 31 (#12179) and 32 (#12207). Status rechecked 2026-10-17 against upstream `main` at `43b87451c5` (02, 03, 05, 10, 12, 13, 14, 16, 26 by code reading; searched for new reports since 2026-10-10: none); before that 2026-10-10 against upstream
`main` at `faecf66d88` (02-27, by code reading and a search for new reports since 2026-10-01; first checked 2026-10-02 at `d16a6598e4`); "code reading" means the code was read, not run.

| File | Still an issue? | Already upstream? |
|---|---|---|
| `02-snapshot-tool-errors-as-not-implemented.md` | yes (code, `faecf66d88`): `else |_|` still sets `supported = false` | none found (rechecked 2026-10-10) |
| `03-icache-not-flushed-before-jit.md` | yes (code): `ExecutableMemory.zig` still has no cache flush | none found (rechecked 2026-10-10) |
| `05-relocation-isa-guessed-from-bytes.md` | yes (code): `0xE8` test still in `Relocation.zig` | none found (rechecked 2026-10-10) |
| `07-32-bit-host-readiness.md` | not rechecked 2026-10-10 (unobservable upstream) | none found (rechecked 2026-10-10) |
| `10-lir-image-drops-recursive-graph-keys.md` | yes (code): map still created empty; the digest check is now `base.invariant` (unreachable in release) | none found (rechecked 2026-10-10) |
| `11-proc-symbol-names-change-every-build.md` | yes (code); design question | none found (rechecked 2026-10-10) |
| `12-abs64-relocation-sized-by-host.md` | yes (code): `@sizeOf(usize)` still in `Relocation.zig` | none found (rechecked 2026-10-10) |
| `13-string-result-stored-from-one-register.md` | yes (code): the non-stack string fallback is still there | none found (rechecked 2026-10-10) |
| `14-list-get-unsafe-truncates-i128-index.md` | yes (code): still loads the low 64 bits of an i128/Dec index | none found (rechecked 2026-10-10) |
| `15-u64-discriminant-load.md` | unconfirmed (`loadAndMaskDiscriminant` still there) | none found (rechecked 2026-10-10) |
| `16-glibc-stub-ret-for-other-arches.md` | yes (code): still emits `ret` for `.aarch64_be, .arm, .wasm32, .other` | none found (rechecked 2026-10-10) |
| `19-redundant-narrowing-shifts.md` | not rechecked; minor | none found (rechecked 2026-10-10) |
| `20-llvm-range-iteration-abort.md` | not rechecked (needs an aarch64 LLVM eval run) | none found (rechecked 2026-10-10) |
| `23-full-ci-linux-jobs-killed.md` | upstream's own Nightly Gate fails or is cancelled every night 2026-10-05..09 with many Linux jobs cancelled; visible to upstream, low value to file now | none found (rechecked 2026-10-10) |
| `24-releasefast-test-failures.md` | **probably fixed**; not rerun | none found (rechecked 2026-10-10) |
| `25-macos-15-intel-glue-failures.md` | upstream's Nightly Gate has macOS-15-intel jobs failing or cancelled (2026-10-09); visible to upstream, low value to file now | none found (rechecked 2026-10-10) |
| `26-stale-line-number-exclusions.md` | yes (2026-10-17): ranges in `src/build/check_runner.zig`; `inspected.zig` is now 3207 lines, so 3264-3275 points past its end | none found (rechecked 2026-10-10) |
| `27-minici-artifact-download.md` | yes (2026-10-02); minor | none found (rechecked 2026-10-10) |

Every draft is about upstream's code or CI; none is a defect of our reference
branch (those were fixed there and are in the verification note's findings
table). Each file's first line says whether upstream is affected today or
only a 32-bit host or target would hit it (07, 12; and 03, 10, 11, 16 are
latent or unreached upstream).

Deleted 2026-10-02: 18, the type checker panic on basic-cli 0.22.2. It was
reported upstream as #11640 and fixed by #11671; it no longer reproduces on
the nightly with basic-cli 0.22.2 or 0.23.0.

Not drafted: partially deleting `.zig-cache/o` breaks Zig's cache (that is
Zig's behaviour, not Roc's), and the proposals (stop committing prebuilt
binaries; report peak memory per test; the byte-identity oracle), which are
suggestions, not defects. See `projects/big/arm32-dev-backend-upstream-now.md`.
