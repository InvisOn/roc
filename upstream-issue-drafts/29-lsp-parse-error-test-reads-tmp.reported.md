# Draft: LSP test "parse errors are reported as diagnostics" fails when /tmp holds a Roc file

> **FILED as roc-lang/roc#12176** on 2026-10-10: filed by the owner with the repro only; open.

> **Upstream or ours:** Upstream. Reproduced on clean upstream `130536d915` and `c50792641a`; our branch does not change `src/lsp`.

> **Relevance to our arm32 work:** None to arm32. It failed the `run-test-zig-module-lsp_integration` phase of minici during the sync of 2026-10-05, because `/tmp/main.roc` (written 2026-10-04 by hand, not by any tool of ours) holds a program with mutually recursive methods. With an empty private `/tmp` the phase passes on our branch and on upstream.

Filed as roc-lang/roc#12176 on 2026-10-10. The ticket holds the repro only; the explanation below was not included.

| | |
|---|---|
| Still an issue? | Yes, reproduced 2026-10-10 with the steps below (LSP code identical to upstream `faecf66d88`). The Oct 5 trigger (mutually recursive methods, "recursive dispatch") no longer errors on today's compiler, so the steps now use an undefined name. A syntax error in `/tmp/main.roc` does not fail the test: its message ("unclosed string") happens to contain the words the test looks for. |
| Already upstream? | **Filed as #12176** (2026-10-10). Before filing: None found (2026-10-10: searched issues and PRs, open and closed, for parse_error_test, test_parse_error, the test's name, and LSP with /tmp; read every LSP issue listed). The test still uses `file:///tmp/test_parse_error.roc` at upstream `faecf66d88`. |
| Fix on our reference branch | None (upstream test; not ours to fix). |
| Before filing | Done 2026-10-10: the cause is draft 31 (a syntax error makes the build switch to the nearest `main.roc`). File both together, or mention 31 here. |

---

**Title:** LSP integration test "parse errors are reported as diagnostics" depends on the contents of `/tmp`

**What happens**

`src/lsp/test/parse_error_test.zig` checks a document at the fixed URI `file:///tmp/test_parse_error.roc`. The checker also picks up other `.roc` files in `/tmp`. Because the test document has a syntax error, the checker treats it as a module of the nearest `main.roc` and builds that package (a separate issue, linked below). When `/tmp/main.roc` holds a program with an error that is reported before type checking, such as an undefined name, that file's diagnostics come first in the result. The test reads only `result[0]` without checking its URI, finds `main.roc`'s message instead of the parse error, and fails:

```
src/lsp/test/parse_error_test.zig:60:9: in parseErrorsAreReportedAsDiagnostics
        try std.testing.expect(mentions_parse_issue);
  FAIL     parse errors are reported as diagnostics
```

**Where**

`src/lsp/test/parse_error_test.zig` (the hardcoded `file:///tmp/...` URI). The other specs use a per-spec temporary directory under `.zig-cache/tmp` (`integration_env.zig`, `tmpDir`).

**Why it matters**

The test result depends on unrelated files on the machine running it, so it fails on a developer machine for reasons that have nothing to do with the change being tested. The cause is a compiler bug, filed separately: because the test document has a syntax error, the build treats it as a child module and builds the nearest `main.roc` (here `/tmp/main.roc`) instead, so that file's diagnostics come first. See the issue on syntax errors switching `roc check` to a nearby `main.roc`.

**How to reproduce**

From the root of a roc-lang/roc checkout. The first step writes `/tmp/main.roc`; if that file already exists, move it aside first and put it back at the end.

```sh
cat > /tmp/main.roc <<'EOF'
main! = |_args| {
	echo!(no_such_name)
	Ok({})
}
EOF
zig build run-test-zig-module-lsp_integration -- --test-filter "parse errors are reported as diagnostics"   # FAIL
rm /tmp/main.roc
zig build run-test-zig-module-lsp_integration -- --test-filter "parse errors are reported as diagnostics"   # passes
```

**Expected**

The spec uses its own temporary directory like the other LSP specs, so files elsewhere on the machine do not change its result.

**Environment**

- OS: Pop!_OS 24.04 LTS, x86_64
- Roc compiler: built from source at `130536d915`
