#!/usr/bin/env python3
"""Vendor the glibc process-startup object used by a `*glibc`/`*linux` test platform.

Where the file comes from
-------------------------
`Scrt1.o` (position-independent process startup) is Zig's bundled glibc,
compiled by the installed Zig toolchain (Zig 0.16.0) for the requested target.
The script links a trivial position-independent C program with
`zig build-exe -target <triple> -lc -fPIE --verbose-link` and copies the
`Scrt1.o` the program's link line names. Zig 0.16 links glibc programs with
`Scrt1.o` alone (no `crti.o`/`crtn.o`); the C library itself comes from the
glibc stub `libc.so` that `build.zig` generates for every GNU target.

Why it is checked in
--------------------
A glibc target links ONLY what the platform declares in its `targets:` block
(see `src/cli/linker.zig`), so the platform's `targets/<target>/` directory
holds the startup object next to `libhost.a` and `libc.so`.

How to regenerate
-----------------
    zig version          # must print 0.16.0
    python3 ci/vendor_glibc_crt.py arm32linux

It is a test fixture: it only has to link. Regenerate when the Zig version
changes. New files must be force-added (`git add -f`).
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
    "arm32linux": "arm-linux-gnueabihf",
}

# Test platforms that declare the target.
PLATFORMS = ("int",)


def zig() -> str:
    return os.environ.get("ZIG", "zig")


def find_scrt1(triple: str, work: Path) -> Path:
    """Link a trivial PIE program for `triple` and return the `Scrt1.o` its
    link line names."""
    main_c = work / "main.c"
    main_c.write_text("int main(void) { return 0; }\n")
    env = dict(os.environ, ZIG_GLOBAL_CACHE_DIR=str(work / "cache"), ZIG_LOCAL_CACHE_DIR=str(work / "local"))
    out_path = work / "a.out"
    result = subprocess.run(
        [zig(), "build-exe", "-target", triple, "-lc", "-fPIE", str(main_c), "-femit-bin=" + str(out_path), "--verbose-link"],
        check=True,
        env=env,
        capture_output=True,
        text=True,
    )
    lines = [line for line in (result.stdout + result.stderr).splitlines() if str(out_path) in line and " -r " not in line]
    if len(lines) != 1:
        sys.exit("expected one link line producing the program, found %d" % len(lines))
    matches = sorted({arg for arg in lines[0].split() if Path(arg).name == "Scrt1.o"})
    if len(matches) != 1:
        sys.exit("expected the link line to name exactly one Scrt1.o, found %d" % len(matches))
    return Path(matches[0])


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("target", choices=sorted(TARGETS))
    args = parser.parse_args()

    version = subprocess.run([zig(), "version"], capture_output=True, text=True, check=True).stdout.strip()
    if version != REQUIRED_ZIG_VERSION:
        sys.exit("zig version is %s; this script requires %s" % (version, REQUIRED_ZIG_VERSION))

    with tempfile.TemporaryDirectory() as tmp:
        scrt1 = find_scrt1(TARGETS[args.target], Path(tmp))
        for platform in PLATFORMS:
            dest = ROOT / "test" / platform / "platform" / "targets" / args.target
            dest.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(scrt1, dest / "Scrt1.o")
            print("wrote %s" % (dest / "Scrt1.o").relative_to(ROOT))
    return 0


if __name__ == "__main__":
    sys.exit(main())
