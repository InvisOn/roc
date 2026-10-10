#!/usr/bin/env python3
"""Generate the byte-exact arm32 encoder tests from the assembler.

Each entry of ci/arm32_encoding_oracle.s pairs A32 assembly with the arm32
`Emit` call that must produce the same bytes:

    add r0, r1, r2                      | addRegRegReg(.r0, .r1, .r2)
    movw r0, #0x5678; movt r0, #0x1234  | movRegImm32(.r0, 0x12345678)
    movw r4, #0xfff0; ...               | pcRelAddress(.r4)

`;` separates instructions of one entry. The call's arguments follow it as
written, so a struct or union argument names its type (`Operand2{ ... }`).
Lines starting with `@` are comments.

The entries are assembled with `zig cc -target arm-linux-musleabihf` (LLVM's
assembler) and the expected bytes are written to
src/backend/dev/arm32/encoding_oracle_tests.zig as one Zig test per entry, so
`zig build test` needs no external tool.

    python3 ci/arm32_encoding_oracle.py           # regenerate
    python3 ci/arm32_encoding_oracle.py --check   # fail if out of date

Both modes also fail when an emitter of arm32 `Emit` has no entry.
"""

import argparse
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.dont_write_bytecode = True
sys.path.insert(0, HERE)
import elf32_reader  # noqa: E402

ROOT = os.path.dirname(HERE)
SOURCE = os.path.join(ROOT, "ci", "arm32_encoding_oracle.s")
OUTPUT = os.path.join(ROOT, "src", "backend", "dev", "arm32", "encoding_oracle_tests.zig")
EMIT = os.path.join(ROOT, "src", "backend", "dev", "arm32", "Emit.zig")

ASM_PRELUDE = """\
.syntax unified
.arch armv7-a
.fpu neon-vfpv3
.arm
.text
"""

R_ARM_CALL = 28

# Emitter methods that emit nothing.
NON_EMITTING = {"init", "deinit"}


class Entry:
    def __init__(self, lineno, asm, zig):
        self.lineno = lineno
        self.asm = asm
        self.zig = zig
        self.bytes = None


def parse_source(path):
    entries = []
    with open(path) as f:
        for lineno, raw in enumerate(f, 1):
            line = raw.strip()
            if not line or line.startswith("@"):
                continue
            if "|" not in line:
                sys.exit("%s:%d: expected `asm | zig call`" % (path, lineno))
            asm, zig = (part.strip() for part in line.split("|", 1))
            instructions = [i.strip() for i in asm.split(";") if i.strip()]
            if not instructions or not zig:
                sys.exit("%s:%d: empty assembly or Zig call" % (path, lineno))
            entries.append(Entry(lineno, instructions, zig))
    return entries


def assemble(entries):
    zig = os.environ.get("ZIG", "zig")
    lines = [ASM_PRELUDE]
    for i, entry in enumerate(entries):
        lines.append("oracle_%d:" % i)
        lines.extend("    " + inst for inst in entry.asm)
    lines.append("oracle_end:")
    with tempfile.TemporaryDirectory() as tmp:
        src = os.path.join(tmp, "oracle.s")
        obj = os.path.join(tmp, "oracle.o")
        with open(src, "w") as f:
            f.write("\n".join(lines) + "\n")
        result = subprocess.run(
            [zig, "cc", "-target", "arm-linux-musleabihf", "-c", src, "-o", obj],
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            sys.exit("assembler failed:\n" + result.stderr)
        elf = elf32_reader.read(obj)

    if elf.e_machine != 40:
        sys.exit("assembler produced e_machine %d, expected 40 (ARM)" % elf.e_machine)
    if elf.section(".rela.text") is not None:
        sys.exit("assembler emitted RELA records; expected REL")
    text = elf.section(".text")
    text_index = elf.sections.index(text)
    rel_text = elf.section(".rel.text")
    if rel_text is not None:
        # LLVM keeps every BL relocatable (R_ARM_CALL) so the linker can
        # interwork, even for local targets. When the target symbol is the
        # instruction itself (S = P), the REL addend in the instruction already
        # equals the resolved displacement, so the bytes are final. Anything
        # else would make the bytes depend on the link.
        for r_offset, sym, r_type in elf.rel_entries(rel_text):
            if r_type != R_ARM_CALL or sym.shndx != text_index or sym.value != r_offset:
                sys.exit("an entry needs a relocation at .text+0x%x; oracle entries must be self-contained" % r_offset)
    offsets = {}
    for sym in elf.symbols():
        if sym.name.startswith("oracle_"):
            offsets[sym.name] = sym.value
    bounds = [offsets["oracle_%d" % i] for i in range(len(entries))] + [offsets["oracle_end"]]
    for i, entry in enumerate(entries):
        entry.bytes = text.data[bounds[i] : bounds[i + 1]]
        if len(entry.bytes) != 4 * len(entry.asm):
            sys.exit(
                "%s:%d: `%s` assembled to %d bytes, expected %d"
                % (SOURCE, entry.lineno, "; ".join(entry.asm), len(entry.bytes), 4 * len(entry.asm))
            )


def zig_string(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def split_call(entry):
    """`name(args)` of an entry's Zig call, as (name, args)."""
    m = re.match(r"(\w+)\((.*)\)\s*$", entry.zig)
    if not m:
        sys.exit("%s:%d: expected `method(args)`, got `%s`" % (SOURCE, entry.lineno, entry.zig))
    return m.group(1), m.group(2).strip()


def render(entries):
    out = [
        "//! Byte-exact A32 encoding tests for arm32 `Emit`.",
        "//!",
        "//! GENERATED by ci/arm32_encoding_oracle.py from ci/arm32_encoding_oracle.s;",
        "//! do not edit. The expected words are what `zig cc -target",
        "//! arm-linux-musleabihf` assembles each entry to. Regenerate with",
        "//! `python3 ci/arm32_encoding_oracle.py`; CI runs it with `--check`.",
        "",
        'const std = @import("std");',
        'const emit = @import("Emit.zig");',
        "const E = emit.Emit(.arm32musl);",
        "const ModImm = emit.ModImm;",
        "const GeneralReg = E.GeneralReg;",
        "const Operand2 = emit.Operand2;",
        "",
        "/// Call `method` with `args` on a fresh emitter and expect exactly the",
        "/// little-endian `words`.",
        "fn expectEncoding(comptime method: anytype, args: anytype, words: []const u32) !void {",
        "    var e = E.init(std.testing.allocator);",
        "    defer e.deinit();",
        "    _ = try @call(.auto, method, .{&e} ++ args);",
        "    try std.testing.expectEqual(words.len * 4, e.buf.items.len);",
        "    for (words, 0..) |word, i| {",
        "        const got = std.mem.readInt(u32, e.buf.items[i * 4 ..][0..4], .little);",
        "        if (got != word) {",
        '            std.debug.print("word {d}: expected 0x{x:0>8}, found 0x{x:0>8}\\n", .{ i, word, got });',
        "            return error.TestExpectedEqual;",
        "        }",
        "    }",
        "}",
        "",
    ]
    seen = {}
    for entry in entries:
        name = "arm32 encoding: " + "; ".join(entry.asm)
        count = seen.get(name, 0)
        seen[name] = count + 1
        if count:
            name += " (%d)" % (count + 1)
        words = [int.from_bytes(entry.bytes[i : i + 4], "little") for i in range(0, len(entry.bytes), 4)]
        method, args = split_call(entry)
        out.append(
            "test %s { try expectEncoding(E.%s, .{%s}, &.{ %s }); }"
            % (zig_string(name), method, " " + args + " " if args else "", ", ".join("0x%08x" % w for w in words))
        )
    return "\n".join(out) + "\n"


def zig_fmt(text):
    zig = os.environ.get("ZIG", "zig")
    result = subprocess.run([zig, "fmt", "--stdin"], input=text, capture_output=True, text=True)
    if result.returncode != 0:
        sys.exit("zig fmt failed on the generated tests:\n" + result.stderr)
    return result.stdout


def check_coverage(entries):
    with open(EMIT) as f:
        emit_src = f.read()
    emitters = set(re.findall(r"^\s*pub fn (\w+)\(self: \*Self", emit_src, re.MULTILINE)) - NON_EMITTING
    called = set()
    for entry in entries:
        m = re.match(r"(\w+)\(", entry.zig)
        if m:
            called.add(m.group(1))
    missing = sorted(emitters - called)
    if missing:
        sys.exit("arm32 Emit methods without an oracle entry: " + ", ".join(missing))
    unknown = sorted(called - emitters)
    if unknown:
        sys.exit("oracle entries call unknown Emit methods: " + ", ".join(unknown))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true", help="fail if the generated tests are out of date")
    args = parser.parse_args()

    entries = parse_source(SOURCE)
    check_coverage(entries)
    assemble(entries)
    generated = zig_fmt(render(entries))

    if args.check:
        try:
            with open(OUTPUT) as f:
                current = f.read()
        except FileNotFoundError:
            current = None
        if current != generated:
            sys.exit("%s is out of date; run python3 ci/arm32_encoding_oracle.py" % os.path.relpath(OUTPUT, ROOT))
        print("arm32 encoding oracle: %d entries up to date" % len(entries))
        return 0

    with open(OUTPUT, "w") as f:
        f.write(generated)
    print("wrote %s (%d entries)" % (os.path.relpath(OUTPUT, ROOT), len(entries)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
