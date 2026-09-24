#!/usr/bin/env python3
"""Minimal little-endian ELF32 reader.

Used by the arm32 encoding oracle (ci/arm32_encoding_oracle.py) and as a
cross-disassembler-free way to inspect arm32 objects on every CI host, in the
spirit of ci/count_aarch64_pmull.py.

    python3 ci/elf32_reader.py --header FILE
    python3 ci/elf32_reader.py --sections FILE
    python3 ci/elf32_reader.py --symbols FILE
"""

import argparse
import struct
import sys

ELFCLASS32 = 1
ELFDATA2LSB = 1

MACHINES = {3: "Intel 80386", 40: "ARM", 62: "Advanced Micro Devices X86-64", 183: "AArch64"}

SECTION_TYPES = {
    0: "NULL",
    1: "PROGBITS",
    2: "SYMTAB",
    3: "STRTAB",
    4: "RELA",
    8: "NOBITS",
    9: "REL",
    0x70000003: "ARM_ATTRIBUTES",
}


class Elf32Error(Exception):
    pass


class Section:
    def __init__(self, name, sh_type, flags, addr, offset, size, link, info, addralign, entsize, data):
        self.name = name
        self.type = sh_type
        self.flags = flags
        self.addr = addr
        self.offset = offset
        self.size = size
        self.link = link
        self.info = info
        self.addralign = addralign
        self.entsize = entsize
        self.data = data


class Symbol:
    def __init__(self, name, value, size, info, other, shndx):
        self.name = name
        self.value = value
        self.size = size
        self.bind = info >> 4
        self.type = info & 0xF
        self.other = other
        self.shndx = shndx


class Elf32:
    def __init__(self, data):
        if len(data) < 52 or data[:4] != b"\x7fELF":
            raise Elf32Error("not an ELF file")
        if data[4] != ELFCLASS32:
            raise Elf32Error("not ELFCLASS32 (EI_CLASS=%d)" % data[4])
        if data[5] != ELFDATA2LSB:
            raise Elf32Error("not little-endian (EI_DATA=%d)" % data[5])
        self.data = data
        (
            self.e_type,
            self.e_machine,
            self.e_version,
            self.e_entry,
            self.e_phoff,
            self.e_shoff,
            self.e_flags,
            self.e_ehsize,
            self.e_phentsize,
            self.e_phnum,
            self.e_shentsize,
            self.e_shnum,
            self.e_shstrndx,
        ) = struct.unpack_from("<HHIIIIIHHHHHH", data, 16)
        self.sections = self._read_sections()

    def _read_sections(self):
        raw = []
        for i in range(self.e_shnum):
            off = self.e_shoff + i * self.e_shentsize
            raw.append(struct.unpack_from("<IIIIIIIIII", self.data, off))
        shstr = raw[self.e_shstrndx] if raw else None
        sections = []
        for name_off, sh_type, flags, addr, offset, size, link, info, align, entsize in raw:
            name = _cstr(self.data, shstr[4] + name_off) if shstr else ""
            body = b"" if sh_type == 8 else self.data[offset : offset + size]
            sections.append(Section(name, sh_type, flags, addr, offset, size, link, info, align, entsize, body))
        return sections

    def section(self, name):
        for s in self.sections:
            if s.name == name:
                return s
        return None

    def symbols(self):
        symtab = next((s for s in self.sections if s.type == 2), None)
        if symtab is None:
            return []
        strtab = self.sections[symtab.link]
        out = []
        for off in range(0, symtab.size, 16):
            name_off, value, size, info, other, shndx = struct.unpack_from("<IIIBBH", symtab.data, off)
            out.append(Symbol(_cstr(strtab.data, name_off), value, size, info, other, shndx))
        return out


    def rel_entries(self, section):
        """(r_offset, symbol, type) for each record of a SHT_REL section."""
        assert section.type == 9
        syms = self.symbols()
        out = []
        for off in range(0, section.size, 8):
            r_offset, r_info = struct.unpack_from("<II", section.data, off)
            out.append((r_offset, syms[r_info >> 8], r_info & 0xFF))
        return out


def _cstr(data, off):
    end = data.index(b"\x00", off)
    return data[off:end].decode("utf-8")


def read(path):
    with open(path, "rb") as f:
        return Elf32(f.read())


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--header", action="store_true")
    parser.add_argument("--sections", action="store_true")
    parser.add_argument("--symbols", action="store_true")
    parser.add_argument("file")
    args = parser.parse_args()

    try:
        elf = read(args.file)
    except (OSError, Elf32Error) as e:
        print("error: %s: %s" % (args.file, e), file=sys.stderr)
        return 1

    if args.header:
        print("Class: ELF32")
        print("Machine: %s" % MACHINES.get(elf.e_machine, "unknown (%d)" % elf.e_machine))
        print("Flags: 0x%x" % elf.e_flags)
    if args.sections:
        for s in elf.sections:
            print("%-24s %-14s size=%d entsize=%d" % (s.name, SECTION_TYPES.get(s.type, hex(s.type)), s.size, s.entsize))
    if args.symbols:
        for sym in elf.symbols():
            print("%08x %6d bind=%d type=%d shndx=%d %s" % (sym.value, sym.size, sym.bind, sym.type, sym.shndx, sym.name))
    return 0


if __name__ == "__main__":
    sys.exit(main())
