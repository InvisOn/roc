# Draft: `zig build minici` needs tools the docs do not mention

> **FILED as roc-lang/roc#12202** on 2026-10-11: filed by the owner as "No prerequisite list mentions MiniCI's `run-test-repl-wasm` needs Node.js (a recent one)"; open.

> **Upstream or ours:** Upstream. The defect is in upstream's code and does not depend on our arm32 work.

> **Relevance to our arm32 work:** We lost time to missing tools the first times we ran minici. The reference documents them.

Filed as roc-lang/roc#12202 on 2026-10-11.

| | |
|---|---|
| Still an issue? | Yes, corrected again 2026-10-11 (upstream `c1464a1dc0`): only Node.js is undocumented. Rust and the wasm32 target ARE documented, in `CONTRIBUTING/README.md` "Test prerequisites" (an earlier version of this draft missed that by checking only `BUILDING_FROM_SOURCE.md`). qemu is ours; kcov runs only on Linux arm64. Node.js is mentioned nowhere, the Nix dev shell (`src/flake.nix`) does not provide it, and CI relies on the runner's preinstalled Node (no `setup-node`). Ubuntu 24.04's Node 18 fails the test (see below). |
| Already upstream? | **Filed as #12202** (2026-10-11). Before filing: None found (searched issues and PRs, 2026-10-02). |
| Fix on our reference branch | `2def52effc` (adds the list to the docs). |
| Before filing | Nothing. |

Checked 2026-10-02 at `d16a6598e4`; corrected 2026-10-11 at `c1464a1dc0`.

---

**Title:** MiniCI's `run-test-repl-wasm` needs Node.js (a recent one), which no prerequisite list mentions

**What happens**

`run-test-repl-wasm` runs `node --test test/repl-wasm-test/cells.test.mjs` (`build.zig`, `run_repl_cells_test`). Node.js is not listed in `CONTRIBUTING/README.md` "Test prerequisites" (which does list the Rust wasm32 target for the glue tests), nor in `BUILDING_FROM_SOURCE.md`, and the Nix dev shell does not provide it. CI passes because the GitHub runner image ships a recent Node; there is no `setup-node` step or version pin.

- Without Node: `failed to spawn and capture stdio from node: FileNotFound`.
- With Ubuntu 24.04's `nodejs` (Node 18.19.1): the test file fails to import, because `src/repl_wasm/www/cells.js` uses `export` but has a `.js` extension and no `package.json` declares `"type": "module"`, so Node 18 loads it as CommonJS:

  ```
  SyntaxError: Named export 'activeCell' not found. The requested module '../../src/repl_wasm/www/cells.js' is a CommonJS module, which may not support all module.exports as named exports.
  ```

  Newer Node versions detect the module syntax by default, so the test passes there.

**Where**

- `build.zig:3369-3371` (upstream `c1464a1dc0`): `b.addSystemCommand(&.{ "node", "--test" })` with `test/repl-wasm-test/cells.test.mjs`, attached to the `run-test-repl-wasm` step (`build.zig:1717`). Added on 2026-08-07 in `16dc8a2338` ("Add notebook UI and generic REPL effects").
- `src/build/minici.zig:274`: `.{ .name = "run-test-repl-wasm", .placement = .primary_host }`, which has run the step in every MiniCI on the primary host since `0d8167db21` (2026-10-09, "Fail a MiniCI run that compiles after build-ci"). Before that the Node test only ran when someone asked for the step.
- `src/repl_wasm/www/cells.js`: the ES module (`export function findCells`, line 9) that Node 18 loads as CommonJS.

**How to reproduce**

From the root of a roc-lang/roc checkout. Neither part depends on what Node, if any, is installed.

1. No Node on PATH (hides any installed `node` for one command):

```sh
mkdir -p /tmp/roc-nonode && ln -sf "$(command -v zig)" /tmp/roc-nonode/zig
env PATH=/tmp/roc-nonode /tmp/roc-nonode/zig build run-test-repl-wasm
# error: failed to spawn and capture stdio from node: FileNotFound
```

2. An older Node (official prebuilt binaries, unpacked into /tmp, nothing installed):

```sh
cd /tmp && for v in v18.20.8 v22.20.0; do curl -fsSLO https://nodejs.org/dist/$v/node-$v-linux-x64.tar.xz && tar xJf node-$v-linux-x64.tar.xz; done; cd -
/tmp/node-v18.20.8-linux-x64/bin/node --test test/repl-wasm-test/cells.test.mjs
# SyntaxError: Named export 'activeCell' not found ... is a CommonJS module   (pass 0, fail 1)
/tmp/node-v22.20.0-linux-x64/bin/node --test test/repl-wasm-test/cells.test.mjs
# pass 7, fail 0
```

And the docs:

```sh
grep -n -i 'node' CONTRIBUTING/README.md BUILDING_FROM_SOURCE.md   # no prerequisite entry
```

**Expected**

"Test prerequisites" lists Node.js and its minimum version, or `cells.js` is made an explicit ES module (a `.mjs` name, or a `package.json` with `"type": "module"` beside it) so any Node with ES modules runs the test. A Node entry in the Nix dev shell would cover Nix users too.

**Environment**

- OS: Pop!_OS 24.04 LTS, x86_64
- Roc: upstream `c1464a1dc0`; Node.js 18.19.1 (Ubuntu package), 18.20.8 and 22.20.0 (nodejs.org builds)
