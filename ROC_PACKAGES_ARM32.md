# Roc packages on GitHub with tests, for arm32

Personal note; not committed. Surveyed 2026-10-20. Clones (shallow, read only)
in the session scratchpad `pkgs/`; baseline results there in `pkg-baseline.txt`.

## How a package's tests can run on arm32

- `roc test --opt=dev <file>` runs every top-level `expect` with the dev
  backend of the machine the compiler runs on. It has no `--target`.
- **On arm32 (the direct route):** build `roc` for arm32
  (`zig build roc -Dtarget=arm-linux-musleabihf -Doptimize=ReleaseSmall`;
  heavy, up to ~18 GB, run alone), copy it and the packages to the Pi 5 and
  Pi 3, and run `roc test --opt=dev`. Every `expect` is then compiled by our
  arm32 backend and run on the board. Compare the pass counts with the
  x86_64 baseline below; `--opt=interpreter` on the Pi is a second reference.
- **Cross-compiling:** `expect`s are not part of `roc build` output, so a
  package's tests cannot be cross-built as they are. Each package would need a
  small fx-platform app that calls it and prints results, built with
  `--target=arm32musl --opt=dev`. More work; not set up.
- Some test files and examples name packages or platforms by URL; the Pis need
  network access for those, or a copied package cache.

## Baseline: x86_64, our build at merge `d65fdf3ac1` (upstream `cf05860a7c`), `roc test --opt=dev`

All use the new syntax (`|x|` lambdas, no `\x ->`).

### Pass on x86_64: ready for arm32 (27 packages, 2,772 tests)

| Package | Test entry | Tests |
|---|---|---|
| [jaredramirez/roc-redis](https://github.com/jaredramirez/roc-redis) | `package/main.roc` | 941 |
| [Karakatiza666/roc-semver](https://github.com/Karakatiza666/roc-semver) | `tests/semver.roc`, `tests/version_req.roc` | 249 |
| [grodaus/kdl-roc](https://github.com/grodaus/kdl-roc) | `lib/main.roc` | 250 |
| [niclas-ahden/roc-xml](https://github.com/niclas-ahden/roc-xml) | `package/main.roc` | 199 |
| [Karakatiza666/roc-app-header](https://github.com/Karakatiza666/roc-app-header) | `tests/*.roc` (5 files) | 166 |
| [ricardo-valero/roc-ps1-emu](https://github.com/ricardo-valero/roc-ps1-emu) | `package/main.roc` | 85 |
| [Karakatiza666/roc-base58](https://github.com/Karakatiza666/roc-base58) | `tests/*.roc` (3 files) | 89 |
| [Karakatiza666/roc-cbor](https://github.com/Karakatiza666/roc-cbor) | `src/main.roc` | 78 |
| [niclas-ahden/roc-scram](https://github.com/niclas-ahden/roc-scram) | `package/main.roc` | 74 |
| [niclas-ahden/roc-maybe](https://github.com/niclas-ahden/roc-maybe) | `package/main.roc` | 73 |
| [niclas-ahden/roc-xlsx](https://github.com/niclas-ahden/roc-xlsx) | `package/main.roc` | 72 |
| [roc-lang/path](https://github.com/roc-lang/path) | `package/main.roc` | 71 |
| [niclas-ahden/roc-md5](https://github.com/niclas-ahden/roc-md5) | `package/main.roc` | 65 |
| [kili-ilo/roc-random](https://github.com/kili-ilo/roc-random) | `package/main.roc` | 61 |
| [lukewilliamboswell/roc-ansi](https://github.com/lukewilliamboswell/roc-ansi) | `package/main.roc` | 60 |
| [niclas-ahden/roc-zip](https://github.com/niclas-ahden/roc-zip) | `package/main.roc` | 53 |
| [niclas-ahden/roc-database-url](https://github.com/niclas-ahden/roc-database-url) | `package/main.roc` | 44 |
| [niclas-ahden/roc-prng](https://github.com/niclas-ahden/roc-prng) | `package/main.roc` | 31 |
| [InvisOn/roc_sort](https://github.com/InvisOn/roc_sort) (yours) | `src/package.roc` | 30 |
| [niclas-ahden/roc-hmac](https://github.com/niclas-ahden/roc-hmac) | `package/main.roc` | 25 |
| [JRI98/RocPBT](https://github.com/JRI98/RocPBT) | `main.roc` | 20 |
| [niclas-ahden/roc-deflate](https://github.com/niclas-ahden/roc-deflate) | `package/main.roc` | 16 |
| [OldIronHorse/tabulate](https://github.com/OldIronHorse/tabulate) | `package/main.roc` | 13 |
| [OldIronHorse/sfmt](https://github.com/OldIronHorse/sfmt) | `package/main.roc` | 5 |
| [lukewilliamboswell/roc-pandoc](https://github.com/lukewilliamboswell/roc-pandoc) | `package/main.roc` | 2 |
| [grayrest/roc-regex](https://github.com/grayrest/roc-regex) | `package/main.roc` | 0 (compiles; no `expect`s) |
| [roc-lang/unicode](https://github.com/roc-lang/unicode) | `package/main.roc` | 0 (its 55 `expect`s are in `examples/`; entry to find) |

Good first picks: roc-redis (941 tests, binary protocol), roc-md5/roc-hmac/
roc-scram (bit twiddling on U32/U64: exercises our 64-bit-on-32-bit paths),
roc-deflate and roc-zip (byte lists), roc-ps1-emu (a CPU emulator: U32
arithmetic, shifts), roc-random/roc-prng (U64 multiplies).

### Compiler crashes on x86_64 too (3)

| Package | Panic |
|---|---|
| [Karakatiza666/roc-toml](https://github.com/Karakatiza666/roc-toml) (1,196 `expect`s) | `postcheck invariant violated: retained body draft content referenced suppressed owned content` |
| [lukewilliamboswell/roc-time](https://github.com/lukewilliamboswell/roc-time) | `ARC: ... released struct representation is missing exact residual-shell metadata` |
| [lukewilliamboswell/roc-pdf](https://github.com/lukewilliamboswell/roc-pdf) | `ARC: ... use of dead refcounted local ... (walking body of join ...)` |

These are in the shared front end (postcheck, ARC), not the dev backend, so
probably upstream's. Not confirmed: the only pure-upstream `roc` at hand was
built 2026-10-09; with it roc-time panics the same way and roc-toml passes
(110 tests in `tests/values.roc`). To confirm: build upstream `cf05860a7c`'s
`roc` and rerun; if upstream, draft issues.

### Do not compile with the current compiler (6)

| Package | Result |
|---|---|
| [smores56/weaver](https://github.com/smores56/weaver) | 6,453 errors (older syntax generation) |
| [smores56/roc-semver](https://github.com/smores56/roc-semver) | 2,443 errors |
| [lukewilliamboswell/roc-graph-layout](https://github.com/lukewilliamboswell/roc-graph-layout) | 39 errors |
| [grayrest/roc-markdown](https://github.com/grayrest/roc-markdown) | 9 errors |
| [lukewilliamboswell/roc-parser](https://github.com/lukewilliamboswell/roc-parser), [Hasnep/roc-ascii](https://github.com/Hasnep/roc-ascii) | 1 error each |

### Not run yet

- [exercism/roc](https://github.com/exercism/roc): 2,132 `expect`s over many
  exercises; each exercise is its own test file. Large, worth a script.
- [radekm/chrono-roc](https://github.com/radekm/chrono-roc): no result line
  (to look at).

## Next steps

1. After the current sync chain: build `roc` for arm32 (alone, under the
   memory limit).
2. Copy it and the 27 passing packages to the Pi 5; run `roc test --opt=dev`
   on each; compare counts with the table. Then the Pi 3.
3. Any difference from x86_64 is a candidate arm32 bug: reduce it to a
   small `expect`, then an eval or fx case.
