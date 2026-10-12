# TODO (arm32 dev backend)

Personal list; not committed (listed in `.git/info/exclude`). Details live in
`projects/big/arm32-dev-backend-*.md`; this is only the overview.

Last updated 2026-10-01. Branch `32-bit-backend` is merged with upstream
`main` at `00cab95af8` and pushed (PR InvisOn/roc#1).

## Now: rebuild it by hand, to learn

- [ ] See `LEARNING_HOLES.md` (chosen: the reference with holes, on
      `arm32-holes`). Start: stage 0 (map of the compiler). `LEARNING.md` is
      the full by-hand rebuild, kept as the slower alternative.

## Upstream

- The reference branch (`32-bit-backend`) is **not** going upstream (decided
  2026-10-02; the old plan to split it into 8 PRs is dropped). What goes
  upstream is `dev-backend-aarch32`, when it is done.
- [ ] When that time comes: the PRs must note the committed binaries (xz)
      and the Zig ABI workaround (https://codeberg.org/ziglang/zig/issues/37018).
- [ ] On hold, but keep in mind: walkthroughs for the remaining phases of
      the reference (`arm32-dev-backend-walkthroughs.md`): A2/A3/Track C,
      J1, J2-J4, the upstream merges. Phase 1 is done. Claude reminds me.

## Decisions I owe

- [x] Driver facade: decided 2026-10-02, option (b): arm32's cases stay in the
      driver, matching the maintainers' style. `arm32-dev-backend-facade-decision.md`.
- [ ] Interpreter hosted-call trampoline fix for arm32 hosts (plans in the
      issues note, 1.2).
- [ ] Fuzzing: start stage 1 before or after the upstream PRs
      (`arm32-dev-backend-fuzzing.md`).
- [ ] File upstream issues: 26 drafts in `upstream-issue-drafts/` (see its
      `README.md` for which are still issues). Claude rechecks the ones that
      need a build before I file anything.

## Waiting on upstream

- [ ] roc-lang/roc#11885 (carries the #11909 SysV zero-size fix). When it
      lands: merge upstream again; the x64musl cross-compile jobs and
      `eval-llvm (ubuntu)` should go green.

## Open arm32 limitations (issues note, 1.2)

- wasm eval oracle cannot run in a 32-bit process
- the driver still names mnemonics and register literals (facade decision)
- interpreter trampoline assumes a 64-bit host
- a Debug arm32 eval runner does not link
- two eval tests need more than a 1 GB board's memory
- Zig 0.16 arm nested-struct ABI bug (worked around; Zig #37018)
- a `u64` builtin parameter passed as one register is not caught

## Annoyances, one commit each (issues note, 1.3)

- line-number exclusions in build.zig's pattern checks go stale
- minici stops at the first failing phase
- `zig build` wipes `~/.cache/roc` (upstream; work around with `XDG_CACHE_HOME`)
- arm32 debugging is slow (plan steps 2-3 open)
- `.zig-cache` fills the disk (clear finished worktrees' caches)
- the int app prints heap addresses
- probe apps that read stdin block without input

## Later projects (issues note, 1.4)

- Stop committing prebuilt binaries (security; its own upstream PR)
- Report peak memory per test in the eval runner

## Tools

- Verify tools live in `.git/verify-tools/`; the Roc versions and how to run them: `.git/verify-tools/roc/README.md`.
- Test machines: Pi 5 `aj@roc5.local` (aarch64), Pi 3 `aj@rocit.local`
  (armv7). The old laptop `roc@rocon.local` is off.
