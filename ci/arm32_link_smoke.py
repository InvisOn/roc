#!/usr/bin/env python3
"""End-to-end smoke test of the arm32 encoder, ELF32 writer and relocations.

Steps:
  1. `zig run src/backend/dev/arm32_link_smoke.zig` builds a relocatable arm32
     object with `arm32.Emit` and `ElfWriter`; its function `roc_link_smoke`
     uses R_ARM_MOVW_PREL_NC/R_ARM_MOVT_PREL, R_ARM_ABS32 and R_ARM_CALL.
  2. `ci/elf32_reader.py` checks the object is ELF32, EM_ARM, hard-float
     (e_flags 0x5000400) and carries Tag_ABI_VFP_args: 1.
  3. `zig cc -target arm-linux-musleabihf` links it with a C `main` through
     LLD against musl.
  4. `qemu-arm-static -cpu cortex-a9` (the dev backend's CPU floor: ARMv7-A,
     NEON, no hardware divide) runs it, or, with `--ssh HOST`, a real 32-bit
     ARM Linux device does; the program must print the smoke message and
     report that the function returned 42.

    python3 ci/arm32_link_smoke.py              # all four steps
    python3 ci/arm32_link_smoke.py --no-run     # steps 1-3 (no qemu needed)
    python3 ci/arm32_link_smoke.py --keep DIR   # keep the object and executable
    python3 ci/arm32_link_smoke.py --ssh aj@rocit.local  # run on a device

Needs Zig 0.16.0 (as `zig` or `$ZIG`) and, for step 4, `qemu-arm-static` or
`qemu-arm` on PATH (`$QEMU_ARM` overrides).
"""

import argparse
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.dont_write_bytecode = True
sys.path.insert(0, HERE)
import elf32_reader  # noqa: E402

ROOT = os.path.dirname(HERE)
SMOKE_SOURCE = os.path.join(ROOT, "src", "backend", "dev", "arm32_link_smoke.zig")
TARGET_MODULE = os.path.join(ROOT, "src", "target", "mod.zig")
MESSAGE = "arm32 link smoke: encoder, ELF32 writer and relocations work"
MAIN_C = r"""
#include <stdio.h>
extern int roc_link_smoke(void);
int main(void) {
    int result = roc_link_smoke();
    printf("roc_link_smoke returned %d\n", result);
    return result == 42 ? 0 : 1;
}
"""


def fail(message):
    print("FAIL: " + message, file=sys.stderr)
    sys.exit(1)


def run(cmd, **kwargs):
    result = subprocess.run(cmd, capture_output=True, text=True, **kwargs)
    if result.returncode != 0:
        fail("%s exited %d\n%s%s" % (" ".join(cmd), result.returncode, result.stdout, result.stderr))
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--no-run", action="store_true", help="stop after linking; do not run under qemu")
    parser.add_argument("--keep", metavar="DIR", help="copy the object and executable into DIR")
    parser.add_argument("--ssh", metavar="HOST", help="run on a 32-bit ARM Linux device over ssh instead of qemu")
    args = parser.parse_args()
    if args.ssh and args.no_run:
        fail("--ssh and --no-run contradict each other")
    zig = os.environ.get("ZIG", "zig")

    qemu = None
    if not args.no_run and not args.ssh:
        qemu = os.environ.get("QEMU_ARM") or shutil.which("qemu-arm-static") or shutil.which("qemu-arm")
        if qemu is None:
            fail("no qemu-arm-static or qemu-arm on PATH; install qemu-user-static or pass --no-run")

    with tempfile.TemporaryDirectory() as work:
        obj = os.path.join(work, "arm32_link_smoke.o")
        exe = os.path.join(work, "arm32_link_smoke")
        main_c = os.path.join(work, "main.c")

        # 1. Build the object with the dev backend's arm32 encoder and ELF writer.
        run([zig, "run", "--dep", "roc_target", "-Mroot=" + SMOKE_SOURCE, "-Mroc_target=" + TARGET_MODULE, "--", obj], cwd=ROOT)
        print("ok   built %s with arm32.Emit and ElfWriter" % os.path.basename(obj))

        # 2. Check the container.
        elf = elf32_reader.read(obj)
        if elf.e_machine != 40:
            fail("e_machine is %d, expected 40 (ARM)" % elf.e_machine)
        if elf.e_flags != 0x05000400:
            fail("e_flags is 0x%x, expected 0x5000400" % elf.e_flags)
        attributes = dict(elf.arm_attributes() or [])
        if attributes.get(28) != 1:
            fail("Tag_ABI_VFP_args is %r, expected 1" % attributes.get(28))
        print("ok   ELF32, EM_ARM, e_flags 0x5000400, Tag_ABI_VFP_args 1")

        # 3. Link with LLD against musl.
        with open(main_c, "w") as f:
            f.write(MAIN_C)
        run([zig, "cc", "-target", "arm-linux-musleabihf", main_c, obj, "-o", exe])
        print("ok   linked with zig cc -target arm-linux-musleabihf")

        if args.keep:
            os.makedirs(args.keep, exist_ok=True)
            shutil.copy(obj, args.keep)
            shutil.copy(exe, args.keep)
            print("ok   kept the object and executable in %s" % args.keep)

        if args.no_run:
            print("NOT RUN: --no-run given; the executable was not executed")
            return 0

        # 4. Run on the dev backend's CPU floor, or on a device.
        if args.ssh:
            remote = "/tmp/arm32_link_smoke.%d" % os.getpid()
            run(["scp", "-q", "-o", "BatchMode=yes", exe, "%s:%s" % (args.ssh, remote)])
            result = subprocess.run(["ssh", "-o", "BatchMode=yes", args.ssh, "%s; status=$?; rm -f %s; exit $status" % (remote, remote)], capture_output=True, text=True)
            where = "ssh " + args.ssh
        else:
            result = subprocess.run([qemu, "-cpu", "cortex-a9", exe], capture_output=True, text=True)
            where = "%s -cpu cortex-a9" % os.path.basename(qemu)
        if result.returncode != 0:
            fail("the executable exited %d\n%s%s" % (result.returncode, result.stdout, result.stderr))
        if MESSAGE not in result.stdout or "roc_link_smoke returned 42" not in result.stdout:
            fail("unexpected output:\n" + result.stdout)
        print("ok   ran on %s:" % where)
        for line in result.stdout.splitlines():
            print("       " + line)
    return 0


if __name__ == "__main__":
    sys.exit(main())
