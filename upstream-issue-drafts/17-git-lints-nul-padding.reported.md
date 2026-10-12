# Draft: git-lints pads a file name with NUL bytes in "src/ file never imported"

> **FILED as roc-lang/roc#12201** on 2026-10-11: filed by the owner; open.

> **Upstream or ours:** Upstream. The defect is in upstream's code and does not depend on our arm32 work.

> **Relevance to our arm32 work:** Seen in the lint output on our branch. Cosmetic.

Filed as roc-lang/roc#12201 on 2026-10-11.

| | |
|---|---|
| Still an issue? | Yes, reproduced 2026-10-11 on clean upstream `c1464a1dc0`: `zz_probe.zig^@^@^@...: error: src/ file never imported in src/ or test/`. |
| Already upstream? | **Filed as #12201** (2026-10-11). Before filing: None found (searched issues and PRs, 2026-10-02). |
| Fix on our reference branch | Not fixed by us. |
| Before filing | Nothing (reproduced on clean upstream 2026-10-11). |

Checked 2026-10-02 against upstream `main` at `d16a6598e4`.

---

**Title:** git-lints pads a file name with NUL bytes in "src/ file never imported"

**What happens**

The "src/ file never imported in src/ or test/" message prints the file name followed by NUL bytes.

**How to reproduce**

```sh
echo 'pub const x = 1;' > src/zz_probe.zig && git add src/zz_probe.zig
zig build run-check-git-lints 2>&1 | cat -v | grep zz_probe   # ^@^@... after the name
git rm -q --cached src/zz_probe.zig && rm src/zz_probe.zig
```

Cosmetic.

**Environment**

- OS: Pop!_OS 24.04 LTS, x86_64
- Roc compiler version `release-fast-a932c654`
