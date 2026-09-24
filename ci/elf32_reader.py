#!/usr/bin/env python3
"""Minimal little-endian ELF32 reader.

Used by the arm32 encoding oracle (ci/arm32_encoding_oracle.py) and as a
cross-disassembler-free way to inspect arm32 objects on every CI host, in the
spirit of ci/count_aarch64_pmull.py.

    python3 ci/elf32_reader.py --header FILE
    python3 ci/elf32_reader.py --sections FILE
    python3 ci/elf32_reader.py --symbols FILE
    python3 ci/elf32_reader.py --attributes FILE
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


    def arm_attributes(self):
        """(tag number, value) pairs of the "aeabi" file-scope attributes in
        `.ARM.attributes`, in section order. String-valued tags (4, 5, 32 and
        odd tags above 32) yield str; the rest yield int."""
        sec = next((s for s in self.sections if s.type == 0x70000003), None)
        if sec is None:
            return None
        d = sec.data
        if not d or d[0] != ord("A"):
            raise Elf32Error(".ARM.attributes has an unknown format version")
        out = []
        pos = 1
        while pos < len(d):
            sub_len = struct.unpack_from("<I", d, pos)[0]
            end = pos + sub_len
            vendor_end = d.index(b"\x00", pos + 4)
            vendor = d[pos + 4 : vendor_end].decode()
            p = vendor_end + 1
            while vendor == "aeabi" and p < end:
                tag, p = _uleb(d, p)
                size = struct.unpack_from("<I", d, p)[0]
                sub_end = p - 1 + size
                p += 4
                if tag != 1:  # only Tag_File is emitted by Roc
                    p = sub_end
                    continue
                while p < sub_end:
                    attr, p = _uleb(d, p)
                    if attr in (4, 5, 32) or (attr > 32 and attr % 2 == 1):
                        nul = d.index(b"\x00", p)
                        out.append((attr, d[p:nul].decode()))
                        p = nul + 1
                    else:
                        value, p = _uleb(d, p)
                        out.append((attr, value))
            pos = end
        return out


ARM_ATTRIBUTE_NAMES = {
    4: "Tag_CPU_raw_name",
    5: "Tag_CPU_name",
    6: "Tag_CPU_arch",
    7: "Tag_CPU_arch_profile",
    8: "Tag_ARM_ISA_use",
    9: "Tag_THUMB_ISA_use",
    10: "Tag_FP_arch",
    12: "Tag_Advanced_SIMD_arch",
    14: "Tag_ABI_PCS_R9_use",
    23: "Tag_ABI_FP_number_model",
    24: "Tag_ABI_align_needed",
    25: "Tag_ABI_align_preserved",
    28: "Tag_ABI_VFP_args",
}


def _uleb(data, pos):
    result = 0
    shift = 0
    while True:
        byte = data[pos]
        pos += 1
        result |= (byte & 0x7F) << shift
        if byte < 0x80:
            return result, pos
        shift += 7


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
    parser.add_argument("--attributes", action="store_true", help="print the aeabi .ARM.attributes")
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
    if args.attributes:
        attrs = elf.arm_attributes()
        if attrs is None:
            print("error: %s has no .ARM.attributes section" % args.file, file=sys.stderr)
            return 1
        for tag, value in attrs:
            name = ARM_ATTRIBUTE_NAMES.get(tag, "Tag_%d" % tag)
            print("%s: %s" % (name, chr(value) if tag == 7 else value))
    if args.symbols:
        for sym in elf.symbols():
            print("%08x %6d bind=%d type=%d shndx=%d %s" % (sym.value, sym.size, sym.bind, sym.type, sym.shndx, sym.name))
    return 0


if __name__ == "__main__":
    sys.exit(main())
