#!/usr/bin/env python3
"""Vendor the musl C runtime linker inputs used by the `*musl` test platforms.

Where these files come from
---------------------------
`crt1.o` (process startup) and `libc.a` are Zig's bundled musl, compiled by the
installed Zig toolchain (Zig 0.16.0) for the requested target. The script links
a trivial program with `zig build-exe -target <triple> -lc --verbose-link` and
copies the `crt1.o` and `libc.a` the program's link line names. (Zig first
partial-links the raw startup object into the `crt1.o` it links, so the cache
holds two; only the final link line identifies the one to vendor.)

Why they are checked in
-----------------------
A `*musl` target links ONLY what the platform declares in its `targets:` block
(see `src/cli/linker.zig`), so each test platform's `platform/targets/<target>/`
directory holds the runtime next to `libhost.a`. `test/fx` holds the canonical
checked-in copy and `build.zig` copies it into the other test platforms.

How to regenerate
-----------------
    zig version          # must print 0.16.0
    python3 ci/vendor_musl_runtime.py arm32musl

These are test fixtures: they only have to link. They are not byte-for-byte
reproducible (Zig names `libc.a`'s members by their absolute cache paths), so
there is no `--check` mode; regenerate only when the Zig version changes.

New files must be force-added (`git add -f`); `.gitignore` whitelists the fx
copies.
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REQUIRED_ZIG_VERSION = "0.16.0"

# Roc target name -> Zig target triple.
TARGETS = {
    "arm32musl": "arm-linux-musleabihf",
}

FILES = ("crt1.o", "libc.a")


def zig() -> str:
    return os.environ.get("ZIG", "zig")


def build_runtime(triple: str, work: Path) -> dict[str, Path]:
    """Link a trivial program for `triple` and return the runtime inputs the
    linker actually used, read from Zig's own `--verbose-link` command line."""
    main_c = work / "main.c"
    main_c.write_text("int main(void) { return 0; }\n")
    env = dict(os.environ, ZIG_GLOBAL_CACHE_DIR=str(work / "cache"), ZIG_LOCAL_CACHE_DIR=str(work / "local"))
    result = subprocess.run(
        [zig(), "build-exe", "-target", triple, "-lc", str(main_c), "-femit-bin=" + str(work / "a.out"), "--verbose-link"],
        check=True,
        env=env,
        capture_output=True,
        text=True,
    )
    # Zig first partial-links (`ld.lld -r`) the raw startup object into the
    # `crt1.o` it uses; only the executable's own link line names the final
    # runtime inputs.
    out_path = str(work / "a.out")
    exe_lines = [line for line in (result.stdout + result.stderr).splitlines() if " -r " not in line and out_path in line]
    if len(exe_lines) != 1:
        sys.exit("expected one link line producing the program, found %d" % len(exe_lines))
    link_args = exe_lines[0].split()
    found = {}
    for name in FILES:
        matches = sorted({arg for arg in link_args if Path(arg).name == name})
        if len(matches) != 1:
            sys.exit("expected the link line to name exactly one %s, found %d" % (name, len(matches)))
        found[name] = Path(matches[0])
    return found


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("target", choices=sorted(TARGETS))
    args = parser.parse_args()

    version = subprocess.run([zig(), "version"], capture_output=True, text=True, check=True).stdout.strip()
    if version != REQUIRED_ZIG_VERSION:
        sys.exit("zig version is %s; this script requires %s" % (version, REQUIRED_ZIG_VERSION))

    dest = ROOT / "test" / "fx" / "platform" / "targets" / args.target
    with tempfile.TemporaryDirectory() as tmp:
        built = build_runtime(TARGETS[args.target], Path(tmp))
        dest.mkdir(parents=True, exist_ok=True)
        for name, path in built.items():
            shutil.copyfile(path, dest / name)
            print("wrote %s" % (dest / name).relative_to(ROOT))
    return 0


if __name__ == "__main__":
    sys.exit(main())
