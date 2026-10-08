//! ELF object file writer for the dev backend.
//!
//! This module writes ELF (Executable and Linkable Format) object files
//! from generated machine code and relocations. It produces relocatable
//! object files (.o) that can be linked with other objects to create
//! executables or shared libraries.
//!
//! Reference: https://refspecs.linuxfoundation.org/elf/elf.pdf

const std = @import("std");
const Allocator = std.mem.Allocator;
const DataRelocationKind = @import("../Relocation.zig").DataRelocationKind;
const object = @import("mod.zig");
const DebugReloc = object.DebugReloc;

/// ELF file header constants
const ELF = struct {
    // ELF identification
    const MAGIC = "\x7fELF".*;
    const CLASS_32 = 1;
    const CLASS_64 = 2;
    const DATA_LSB = 1; // Little endian
    const VERSION_CURRENT = 1;

    // ELF type
    const ET_REL = 1; // Relocatable file

    // Machine types
    const EM_X86_64 = 62;
    const EM_AARCH64 = 183;
    const EM_ARM = 40;

    // Section header types
    const SHT_PROGBITS = 1;
    const SHT_SYMTAB = 2;
    const SHT_STRTAB = 3;
    const SHT_RELA = 4;
    const SHT_NOBITS = 8;
    const SHT_REL = 9;
    const SHT_ARM_ATTRIBUTES = 0x70000003;

    // Section flags
    const SHF_WRITE = 0x1;
    const SHF_ALLOC = 0x2;
    const SHF_EXECINSTR = 0x4;
    const SHF_INFO_LINK = 0x40;

    // Symbol binding
    const STB_LOCAL = 0;
    const STB_GLOBAL = 1;

    // Symbol type
    const STT_NOTYPE = 0;
    const STT_OBJECT = 1;
    const STT_FUNC = 2;
    const STT_SECTION = 3;

    // Symbol visibility
    const STV_DEFAULT = 0;
    const STV_HIDDEN = 2;

    // Special section indices
    const SHN_UNDEF = 0;

    // x86_64 relocation types
    const R_X86_64_64 = 1;
    const R_X86_64_PC32 = 2;
    const R_X86_64_PLT32 = 4;
    const R_X86_64_32 = 10;

    // aarch64 relocation types
    const R_AARCH64_ABS64 = 257;
    const R_AARCH64_ABS32 = 258;
    const R_AARCH64_ADR_PREL_PG_HI21 = 275;
    const R_AARCH64_ADD_ABS_LO12_NC = 277;
    const R_AARCH64_CALL26 = 283;

    // arm32 relocation types (AAELF32)
    const R_ARM_ABS32 = 2;
    const R_ARM_CALL = 28;
    const R_ARM_MOVW_PREL_NC = 45;
    const R_ARM_MOVT_PREL = 46;

    // arm32 e_flags: EABI version 5, hard-float procedure call standard
    const EF_ARM_EABI_VER5 = 0x05000000;
    const EF_ARM_ABI_FLOAT_HARD = 0x00000400;
};

/// ELF64 file header (64 bytes)
const Elf64_Ehdr = extern struct {
    e_ident: [16]u8,
    e_type: u16,
    e_machine: u16,
    e_version: u32,
    e_entry: u64,
    e_phoff: u64,
    e_shoff: u64,
    e_flags: u32,
    e_ehsize: u16,
    e_phentsize: u16,
    e_phnum: u16,
    e_shentsize: u16,
    e_shnum: u16,
    e_shstrndx: u16,
};

/// ELF64 section header (64 bytes)
const Elf64_Shdr = extern struct {
    sh_name: u32,
    sh_type: u32,
    sh_flags: u64 = 0,
    sh_addr: u64 = 0,
    sh_offset: u64,
    sh_size: u64,
    sh_link: u32 = 0,
    sh_info: u32 = 0,
    sh_addralign: u64,
    sh_entsize: u64 = 0,
};

/// ELF64 symbol table entry (24 bytes)
const Elf64_Sym = extern struct {
    st_name: u32,
    st_info: u8,
    st_other: u8,
    st_shndx: u16,
    st_value: u64,
    st_size: u64,
};

/// ELF64 relocation entry with addend (24 bytes)
const Elf64_Rela = extern struct {
    r_offset: u64,
    r_info: u64,
    r_addend: i64,
};

/// ELF32 file header (52 bytes)
const Elf32_Ehdr = extern struct {
    e_ident: [16]u8,
    e_type: u16,
    e_machine: u16,
    e_version: u32,
    e_entry: u32,
    e_phoff: u32,
    e_shoff: u32,
    e_flags: u32,
    e_ehsize: u16,
    e_phentsize: u16,
    e_phnum: u16,
    e_shentsize: u16,
    e_shnum: u16,
    e_shstrndx: u16,
};

/// ELF32 section header (40 bytes)
const Elf32_Shdr = extern struct {
    sh_name: u32,
    sh_type: u32,
    sh_flags: u32,
    sh_addr: u32,
    sh_offset: u32,
    sh_size: u32,
    sh_link: u32,
    sh_info: u32,
    sh_addralign: u32,
    sh_entsize: u32,
};

/// ELF32 symbol table entry (16 bytes)
const Elf32_Sym = extern struct {
    st_name: u32,
    st_value: u32,
    st_size: u32,
    st_info: u8,
    st_other: u8,
    st_shndx: u16,
};

/// ELF32 relocation entry without addend (8 bytes). The addend lives in the
/// relocated field itself (REL form), as AAELF32 prescribes for ARM.
const Elf32_Rel = extern struct {
    r_offset: u32,
    r_info: u32,
};

/// Target architecture for ELF generation
pub const Architecture = enum {
    x86_64,
    aarch64,
    /// 32-bit ARM (A32, AAPCS32 hard-float): written as ELF32 with REL
    /// relocations.
    arm,

    fn machine(self: Architecture) u16 {
        return switch (self) {
            .x86_64 => ELF.EM_X86_64,
            .aarch64 => ELF.EM_AARCH64,
            .arm => ELF.EM_ARM,
        };
    }
};

/// Symbol definition for the object file
pub const Symbol = struct {
    name: []const u8,
    section: Section,
    offset: u64,
    size: u64,
    is_global: bool,
    is_function: bool,
    is_hidden: bool = false,
};

/// Section types
pub const Section = enum {
    text,
    data,
    rodata,
    bss,
    undef, // External symbol
};

/// The `EI_OSABI` byte an object declares.
///
/// A linker reads this from its input objects to decide which OS-specific
/// program headers the output needs: `ld.lld` emits OpenBSD's `PT_OPENBSD_*`
/// headers only when it infers that OSABI from an input, and it takes the value
/// from the first input that declares anything other than `none`. These values
/// match what LLVM writes for the same triples, so the two backends' objects
/// agree when they meet in one link.
pub const Osabi = enum(u8) {
    none = 0,
    freebsd = 9,
    openbsd = 12,
};

/// ELF object file writer
pub const ElfWriter = struct {
    const Self = @This();

    allocator: Allocator,
    arch: Architecture,
    osabi: Osabi,

    // Borrowed section contents, valid until write completes
    text: []const u8,
    rodata: []const u8,
    /// Size of `.bss`, which the file declares without storing bytes.
    zero_fill_size: u64,

    // Symbol table
    symbols: std.ArrayList(Symbol),

    // Relocations for .text section
    text_relocs: std.ArrayList(TextReloc),
    rodata_relocs: std.ArrayList(TextReloc),

    /// DWARF debug sections plus their explicit cross-section relocations.
    debug: object.DebugSections = .{},

    // String tables
    shstrtab: std.ArrayList(u8),

    const TextReloc = struct {
        offset: u64, // Offset in .text where relocation applies
        symbol_idx: u32, // Index into symbol table
        reloc_type: u32, // Architecture-specific relocation type
        addend: i64,
    };

    const TextDataReloc = struct {
        kind: u32,
        addend: i64,
    };

    pub fn init(allocator: Allocator, arch: Architecture, osabi: Osabi) Allocator.Error!Self {
        var self = Self{
            .allocator = allocator,
            .arch = arch,
            .osabi = osabi,
            .text = &.{},
            .rodata = &.{},
            .zero_fill_size = 0,
            .symbols = .empty,
            .text_relocs = .empty,
            .rodata_relocs = .empty,
            .shstrtab = .empty,
        };

        errdefer self.deinit();

        // Initialize string tables with null byte
        try self.shstrtab.append(allocator, 0);

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.symbols.deinit(self.allocator);
        self.text_relocs.deinit(self.allocator);
        self.rodata_relocs.deinit(self.allocator);
        self.shstrtab.deinit(self.allocator);
    }

    /// Borrow the code section contents until write completes
    pub fn setCode(self: *Self, code: []const u8) void {
        self.text = code;
    }

    /// Borrow read-only data section contents until write completes.
    pub fn setZeroFill(self: *Self, size: u64) void {
        self.zero_fill_size = size;
    }

    pub fn setRodata(self: *Self, rodata: []const u8) void {
        self.rodata = rodata;
    }

    /// Add a symbol to the object file
    pub fn addSymbol(self: *Self, symbol: Symbol) Allocator.Error!u32 {
        const idx: u32 = @intCast(self.symbols.items.len);
        try self.symbols.append(self.allocator, symbol);
        return idx;
    }

    /// Add an external symbol reference
    pub fn addExternalSymbol(self: *Self, name: []const u8) Allocator.Error!u32 {
        return self.addSymbol(.{
            .name = name,
            .section = .undef,
            .offset = 0,
            .size = 0,
            .is_global = true,
            .is_function = true,
        });
    }

    /// Add an absolute pointer relocation to the rodata section.
    pub fn addRodataRelocation(self: *Self, offset: u64, symbol_idx: u32, addend: i64) Allocator.Error!void {
        const reloc_type: u32 = switch (self.arch) {
            .x86_64 => ELF.R_X86_64_64,
            .aarch64 => ELF.R_AARCH64_ABS64,
            .arm => ELF.R_ARM_ABS32,
        };

        try self.rodata_relocs.append(self.allocator, .{
            .offset = offset,
            .symbol_idx = symbol_idx,
            .reloc_type = reloc_type,
            .addend = addend,
        });
    }

    /// Add a relocation to the text section
    pub fn addTextRelocation(self: *Self, offset: u64, symbol_idx: u32, addend: i64) Allocator.Error!void {
        const reloc_type: u32 = switch (self.arch) {
            .x86_64 => ELF.R_X86_64_PLT32,
            .aarch64 => ELF.R_AARCH64_CALL26,
            // BL through R_ARM_CALL lets the linker turn it into BLX or add
            // an interworking veneer when the callee is Thumb.
            .arm => ELF.R_ARM_CALL,
        };

        try self.text_relocs.append(self.allocator, .{
            .offset = offset,
            .symbol_idx = symbol_idx,
            .reloc_type = reloc_type,
            .addend = addend,
        });
    }

    /// Add a data-address relocation to the text section.
    pub fn addTextDataRelocation(self: *Self, offset: u64, symbol_idx: u32, kind: DataRelocationKind) Allocator.Error!void {
        const reloc: TextDataReloc = switch (kind) {
            .abs64 => .{
                .kind = switch (self.arch) {
                    .x86_64 => ELF.R_X86_64_64,
                    .aarch64 => ELF.R_AARCH64_ABS64,
                    .arm => unreachable,
                },
                .addend = @as(i64, 0),
            },
            .rel32 => .{
                .kind = switch (self.arch) {
                    .x86_64 => ELF.R_X86_64_PC32,
                    .aarch64, .arm => unreachable,
                },
                .addend = @as(i64, -4),
            },
            .page21 => .{
                .kind = switch (self.arch) {
                    .x86_64, .arm => unreachable,
                    .aarch64 => ELF.R_AARCH64_ADR_PREL_PG_HI21,
                },
                .addend = @as(i64, 0),
            },
            .pageoff12 => .{
                .kind = switch (self.arch) {
                    .x86_64, .arm => unreachable,
                    .aarch64 => ELF.R_AARCH64_ADD_ABS_LO12_NC,
                },
                .addend = @as(i64, 0),
            },
            .abs32 => .{
                .kind = switch (self.arch) {
                    .x86_64, .aarch64 => unreachable,
                    .arm => ELF.R_ARM_ABS32,
                },
                .addend = @as(i64, 0),
            },
            .arm_movw_prel => .{
                .kind = switch (self.arch) {
                    .x86_64, .aarch64 => unreachable,
                    .arm => ELF.R_ARM_MOVW_PREL_NC,
                },
                .addend = kind.armMovAddend(),
            },
            .arm_movt_prel => .{
                .kind = switch (self.arch) {
                    .x86_64, .aarch64 => unreachable,
                    .arm => ELF.R_ARM_MOVT_PREL,
                },
                .addend = kind.armMovAddend(),
            },
        };

        try self.text_relocs.append(self.allocator, .{
            .offset = offset,
            .symbol_idx = symbol_idx,
            .reloc_type = reloc.kind,
            .addend = reloc.addend,
        });
    }

    /// Add a string to the string table, return its offset
    fn addString(self: *Self, table: *std.ArrayList(u8), str: []const u8) Allocator.Error!u32 {
        const offset: u32 = @intCast(table.items.len);
        try table.appendSlice(self.allocator, str);
        try table.append(self.allocator, 0); // Null terminator
        return offset;
    }

    /// Write the ELF object file to a buffer: ELF64 with RELA relocations for
    /// the 64-bit architectures, ELF32 with REL relocations for arm32.
    pub fn write(self: *Self, output: *std.ArrayList(u8)) Allocator.Error!void {
        switch (self.arch) {
            .x86_64, .aarch64 => try self.write64(output),
            .arm => try self.write32(output),
        }
    }

    fn write64(self: *Self, output: *std.ArrayList(u8)) Allocator.Error!void {
        // Section indices
        const SHIDX_TEXT = 1;
        const SHIDX_RODATA = 2;
        const SHIDX_SYMTAB = 5;
        const SHIDX_STRTAB = 6;
        const SHIDX_SHSTRTAB = 7;
        const SHIDX_DEBUG_LINE = 8;
        const SHIDX_DEBUG_ABBREV = 9;
        const SHIDX_DEBUG_INFO = 10;
        const SHIDX_BSS = 13;
        const NUM_SECTIONS = 14;

        // Add section names to shstrtab
        const shname_text = try self.addString(&self.shstrtab, ".text");
        const shname_rodata = try self.addString(&self.shstrtab, ".rodata");
        const shname_rela_text = try self.addString(&self.shstrtab, ".rela.text");
        const shname_rela_rodata = try self.addString(&self.shstrtab, ".rela.rodata");
        const shname_symtab = try self.addString(&self.shstrtab, ".symtab");
        const shname_strtab = try self.addString(&self.shstrtab, ".strtab");
        const shname_shstrtab = try self.addString(&self.shstrtab, ".shstrtab");
        const shname_debug_line = try self.addString(&self.shstrtab, ".debug_line");
        const shname_debug_abbrev = try self.addString(&self.shstrtab, ".debug_abbrev");
        const shname_debug_info = try self.addString(&self.shstrtab, ".debug_info");
        const shname_rela_debug_line = try self.addString(&self.shstrtab, ".rela.debug_line");
        const shname_rela_debug_info = try self.addString(&self.shstrtab, ".rela.debug_info");
        const shname_bss = try self.addString(&self.shstrtab, ".bss");

        const debug_target_sections = [_]u16{ SHIDX_TEXT, SHIDX_DEBUG_LINE, SHIDX_DEBUG_ABBREV };
        const WRITER_SYMBOL_OFFSET: u32 = 1 + debug_target_sections.len;
        var num_locals: u32 = WRITER_SYMBOL_OFFSET;
        const symtab_size = (self.symbols.items.len + WRITER_SYMBOL_OFFSET) * @sizeOf(Elf64_Sym);
        var string_bytes: usize = 1; // The string table starts with a null byte.
        for (self.symbols.items) |symbol| string_bytes += symbol.name.len + 1;
        const rela_text_size = self.text_relocs.items.len * @sizeOf(Elf64_Rela);
        const rela_rodata_size = self.rodata_relocs.items.len * @sizeOf(Elf64_Rela);
        const rela_debug_line_size = self.debug.line_relocs.len * @sizeOf(Elf64_Rela);
        const rela_debug_info_size = self.debug.info_relocs.len * @sizeOf(Elf64_Rela);

        // Calculate offsets
        const ehdr_size: u64 = @sizeOf(Elf64_Ehdr);

        // Section data starts after headers
        var offset: u64 = ehdr_size;

        // Align sections
        const text_offset = alignUp(offset, 16);
        offset = text_offset + self.text.len;

        const rodata_offset = alignUp(offset, 16);
        offset = rodata_offset + self.rodata.len;

        const rela_text_offset = alignUp(offset, 8);
        offset = rela_text_offset + rela_text_size;

        const rela_rodata_offset = alignUp(offset, 8);
        offset = rela_rodata_offset + rela_rodata_size;

        const symtab_offset = alignUp(offset, 8);
        offset = symtab_offset + symtab_size;

        const strtab_offset = offset;
        offset = strtab_offset + string_bytes;

        const shstrtab_offset = offset;
        offset = shstrtab_offset + self.shstrtab.items.len;

        const debug_line_offset = offset;
        offset = debug_line_offset + self.debug.line.len;
        const debug_abbrev_offset = offset;
        offset = debug_abbrev_offset + self.debug.abbrev.len;
        const debug_info_offset = offset;
        offset = debug_info_offset + self.debug.info.len;
        const rela_debug_line_offset = alignUp(offset, 8);
        offset = rela_debug_line_offset + rela_debug_line_size;
        const rela_debug_info_offset = alignUp(offset, 8);
        offset = rela_debug_info_offset + rela_debug_info_size;

        const shdr_offset = alignUp(offset, 8);

        std.debug.assert(output.items.len == 0);
        const object_size: usize = @intCast(shdr_offset + NUM_SECTIONS * @sizeOf(Elf64_Shdr));
        try output.ensureTotalCapacityPrecise(self.allocator, object_size);

        // Write ELF header
        var ehdr = Elf64_Ehdr{
            .e_ident = undefined,
            .e_type = ELF.ET_REL,
            .e_machine = self.arch.machine(),
            .e_version = ELF.VERSION_CURRENT,
            .e_entry = 0,
            .e_phoff = 0,
            .e_shoff = shdr_offset,
            .e_flags = 0,
            .e_ehsize = @sizeOf(Elf64_Ehdr),
            .e_phentsize = 0,
            .e_phnum = 0,
            .e_shentsize = @sizeOf(Elf64_Shdr),
            .e_shnum = NUM_SECTIONS,
            .e_shstrndx = SHIDX_SHSTRTAB,
        };

        // Set e_ident
        @memcpy(ehdr.e_ident[0..4], &ELF.MAGIC);
        ehdr.e_ident[4] = ELF.CLASS_64;
        ehdr.e_ident[5] = ELF.DATA_LSB;
        ehdr.e_ident[6] = ELF.VERSION_CURRENT;
        ehdr.e_ident[7] = @backingInt(self.osabi);
        @memset(ehdr.e_ident[8..16], 0);

        output.appendSliceAssumeCapacity(std.mem.asBytes(&ehdr));

        // Pad to text section
        padTo(output, text_offset);
        output.appendSliceAssumeCapacity(self.text);

        padTo(output, rodata_offset);
        output.appendSliceAssumeCapacity(self.rodata);

        // Pad to rela sections
        padTo(output, rela_text_offset);
        for (self.text_relocs.items) |rel| {
            const r_info: u64 = (@as(u64, rel.symbol_idx + WRITER_SYMBOL_OFFSET) << 32) | rel.reloc_type;

            const elf_rela = Elf64_Rela{
                .r_offset = rel.offset,
                .r_info = r_info,
                .r_addend = rel.addend,
            };

            output.appendSliceAssumeCapacity(std.mem.asBytes(&elf_rela));
        }

        padTo(output, rela_rodata_offset);
        for (self.rodata_relocs.items) |rel| {
            const r_info: u64 = (@as(u64, rel.symbol_idx + WRITER_SYMBOL_OFFSET) << 32) | rel.reloc_type;

            const elf_rela = Elf64_Rela{
                .r_offset = rel.offset,
                .r_info = r_info,
                .r_addend = rel.addend,
            };

            output.appendSliceAssumeCapacity(std.mem.asBytes(&elf_rela));
        }

        // Pad to symtab
        padTo(output, symtab_offset);
        // First symbol is always null
        output.appendSliceAssumeCapacity(&std.mem.zeroes([24]u8));

        // Section symbols used by DWARF cross-section relocations.
        for (debug_target_sections) |section_index| {
            const section_sym = Elf64_Sym{
                .st_name = 0,
                .st_info = (ELF.STB_LOCAL << 4) | ELF.STT_SECTION,
                .st_other = 0,
                .st_shndx = section_index,
                .st_value = 0,
                .st_size = 0,
            };
            output.appendSliceAssumeCapacity(std.mem.asBytes(&section_sym));
        }

        // Count local symbols (for sh_info)

        // Add symbols
        var name_offset: u32 = 1;
        for (self.symbols.items) |sym| {
            const st_info: u8 = blk: {
                const bind: u8 = if (sym.is_global) ELF.STB_GLOBAL else ELF.STB_LOCAL;
                const sym_type: u8 = if (sym.is_function) ELF.STT_FUNC else if (sym.section == .rodata or sym.section == .bss) ELF.STT_OBJECT else ELF.STT_NOTYPE;
                break :blk (bind << 4) | sym_type;
            };

            const st_shndx: u16 = switch (sym.section) {
                .text => SHIDX_TEXT,
                .data => 0, // Would be data section index
                .rodata => SHIDX_RODATA,
                .bss => SHIDX_BSS,
                .undef => ELF.SHN_UNDEF,
            };

            const elf_sym = Elf64_Sym{
                .st_name = name_offset,
                .st_info = st_info,
                .st_other = if (sym.is_hidden) ELF.STV_HIDDEN else ELF.STV_DEFAULT,
                .st_shndx = st_shndx,
                .st_value = sym.offset,
                .st_size = sym.size,
            };

            output.appendSliceAssumeCapacity(std.mem.asBytes(&elf_sym));
            name_offset += @intCast(sym.name.len + 1);

            if (!sym.is_global) {
                num_locals += 1;
            }
        }

        // strtab (no padding needed)
        output.appendAssumeCapacity(0);
        for (self.symbols.items) |sym| {
            output.appendSliceAssumeCapacity(sym.name);
            output.appendAssumeCapacity(0);
        }

        // shstrtab
        output.appendSliceAssumeCapacity(self.shstrtab.items);

        // Debug sections
        output.appendSliceAssumeCapacity(self.debug.line);
        output.appendSliceAssumeCapacity(self.debug.abbrev);
        output.appendSliceAssumeCapacity(self.debug.info);
        padTo(output, rela_debug_line_offset);
        appendDebugRelocations(self.arch, self.debug.line_relocs, output);
        padTo(output, rela_debug_info_offset);
        appendDebugRelocations(self.arch, self.debug.info_relocs, output);

        // Pad to section headers
        padTo(output, shdr_offset);

        // Write section headers
        // 0: NULL section
        output.appendSliceAssumeCapacity(&std.mem.zeroes([64]u8));

        // 1: .text
        appendShdr(output, .{ .sh_name = shname_text, .sh_type = ELF.SHT_PROGBITS, .sh_flags = ELF.SHF_ALLOC | ELF.SHF_EXECINSTR, .sh_offset = text_offset, .sh_size = self.text.len, .sh_addralign = 16 });

        // 2: .rodata
        appendShdr(output, .{ .sh_name = shname_rodata, .sh_type = ELF.SHT_PROGBITS, .sh_flags = ELF.SHF_ALLOC, .sh_offset = rodata_offset, .sh_size = self.rodata.len, .sh_addralign = 16 });

        // 3: .rela.text
        appendShdr(output, .{ .sh_name = shname_rela_text, .sh_type = ELF.SHT_RELA, .sh_flags = ELF.SHF_INFO_LINK, .sh_offset = rela_text_offset, .sh_size = rela_text_size, .sh_link = SHIDX_SYMTAB, .sh_info = SHIDX_TEXT, .sh_addralign = 8, .sh_entsize = @sizeOf(Elf64_Rela) });

        // 4: .rela.rodata
        appendShdr(output, .{ .sh_name = shname_rela_rodata, .sh_type = ELF.SHT_RELA, .sh_flags = ELF.SHF_INFO_LINK, .sh_offset = rela_rodata_offset, .sh_size = rela_rodata_size, .sh_link = SHIDX_SYMTAB, .sh_info = SHIDX_RODATA, .sh_addralign = 8, .sh_entsize = @sizeOf(Elf64_Rela) });

        // 5: .symtab
        appendShdr(output, .{ .sh_name = shname_symtab, .sh_type = ELF.SHT_SYMTAB, .sh_offset = symtab_offset, .sh_size = symtab_size, .sh_link = SHIDX_STRTAB, .sh_info = num_locals, .sh_addralign = 8, .sh_entsize = @sizeOf(Elf64_Sym) });

        // 6: .strtab
        appendShdr(output, .{ .sh_name = shname_strtab, .sh_type = ELF.SHT_STRTAB, .sh_offset = strtab_offset, .sh_size = string_bytes, .sh_addralign = 1 });

        // 7: .shstrtab
        appendShdr(output, .{ .sh_name = shname_shstrtab, .sh_type = ELF.SHT_STRTAB, .sh_offset = shstrtab_offset, .sh_size = self.shstrtab.items.len, .sh_addralign = 1 });

        // 8: .debug_line
        appendShdr(output, .{ .sh_name = shname_debug_line, .sh_type = ELF.SHT_PROGBITS, .sh_offset = debug_line_offset, .sh_size = self.debug.line.len, .sh_addralign = 1 });

        // 9: .debug_abbrev
        appendShdr(output, .{ .sh_name = shname_debug_abbrev, .sh_type = ELF.SHT_PROGBITS, .sh_offset = debug_abbrev_offset, .sh_size = self.debug.abbrev.len, .sh_addralign = 1 });

        // 10: .debug_info
        appendShdr(output, .{ .sh_name = shname_debug_info, .sh_type = ELF.SHT_PROGBITS, .sh_offset = debug_info_offset, .sh_size = self.debug.info.len, .sh_addralign = 1 });

        // 11: .rela.debug_line
        appendShdr(output, .{ .sh_name = shname_rela_debug_line, .sh_type = ELF.SHT_RELA, .sh_flags = ELF.SHF_INFO_LINK, .sh_offset = rela_debug_line_offset, .sh_size = rela_debug_line_size, .sh_link = SHIDX_SYMTAB, .sh_info = SHIDX_DEBUG_LINE, .sh_addralign = 8, .sh_entsize = @sizeOf(Elf64_Rela) });

        // 12: .rela.debug_info
        appendShdr(output, .{ .sh_name = shname_rela_debug_info, .sh_type = ELF.SHT_RELA, .sh_flags = ELF.SHF_INFO_LINK, .sh_offset = rela_debug_info_offset, .sh_size = rela_debug_info_size, .sh_link = SHIDX_SYMTAB, .sh_info = SHIDX_DEBUG_INFO, .sh_addralign = 8, .sh_entsize = @sizeOf(Elf64_Rela) });

        // 13: .bss, declared by size alone; SHT_NOBITS stores no bytes, so
        // its file offset only has to be inside the file.
        appendShdr(output, .{ .sh_name = shname_bss, .sh_type = ELF.SHT_NOBITS, .sh_flags = ELF.SHF_ALLOC | ELF.SHF_WRITE, .sh_offset = shdr_offset, .sh_size = self.zero_fill_size, .sh_addralign = 16 });
        std.debug.assert(output.items.len == object_size);
    }

    fn appendShdr(output: *std.ArrayList(u8), shdr: Elf64_Shdr) void {
        output.appendSliceAssumeCapacity(std.mem.asBytes(&shdr));
    }

    /// ELF32 with REL relocations (arm32). Section indices 1-12 match
    /// write64; section 13 is `.ARM.attributes` and 14 is `.bss` (write64's
    /// 13), so arm32's indices stay where they were before `.bss` existed.
    /// REL records carry no addend
    /// field, so each relocation's explicit addend is stored into the
    /// relocated field of the output copy, encoded as its type requires.
    fn write32(self: *Self, output: *std.ArrayList(u8)) Allocator.Error!void {
        std.debug.assert(self.arch == .arm);
        const SHIDX_TEXT = 1;
        const SHIDX_RODATA = 2;
        const SHIDX_SYMTAB = 5;
        const SHIDX_STRTAB = 6;
        const SHIDX_SHSTRTAB = 7;
        const SHIDX_DEBUG_LINE = 8;
        const SHIDX_DEBUG_ABBREV = 9;
        const SHIDX_DEBUG_INFO = 10;
        const SHIDX_BSS = 14;
        const NUM_SECTIONS = 15;

        const shname_text = try self.addString(&self.shstrtab, ".text");
        const shname_rodata = try self.addString(&self.shstrtab, ".rodata");
        const shname_rel_text = try self.addString(&self.shstrtab, ".rel.text");
        const shname_rel_rodata = try self.addString(&self.shstrtab, ".rel.rodata");
        const shname_symtab = try self.addString(&self.shstrtab, ".symtab");
        const shname_strtab = try self.addString(&self.shstrtab, ".strtab");
        const shname_shstrtab = try self.addString(&self.shstrtab, ".shstrtab");
        const shname_debug_line = try self.addString(&self.shstrtab, ".debug_line");
        const shname_debug_abbrev = try self.addString(&self.shstrtab, ".debug_abbrev");
        const shname_debug_info = try self.addString(&self.shstrtab, ".debug_info");
        const shname_rel_debug_line = try self.addString(&self.shstrtab, ".rel.debug_line");
        const shname_rel_debug_info = try self.addString(&self.shstrtab, ".rel.debug_info");
        const shname_attributes = try self.addString(&self.shstrtab, ".ARM.attributes");
        const shname_bss = try self.addString(&self.shstrtab, ".bss");

        // Symbols: null, the section symbols DWARF relocations target, the
        // `$a` mapping symbol marking .text as A32, then the writer's symbols.
        const debug_target_sections = [_]u16{ SHIDX_TEXT, SHIDX_DEBUG_LINE, SHIDX_DEBUG_ABBREV };
        const mapping_symbol_name = "$a";
        const WRITER_SYMBOL_OFFSET: u32 = 1 + debug_target_sections.len + 1;
        var num_locals: u32 = WRITER_SYMBOL_OFFSET;
        const symtab_size = (self.symbols.items.len + WRITER_SYMBOL_OFFSET) * @sizeOf(Elf32_Sym);
        var string_bytes: usize = 1 + mapping_symbol_name.len + 1;
        for (self.symbols.items) |symbol| string_bytes += symbol.name.len + 1;
        const rel_text_size = self.text_relocs.items.len * @sizeOf(Elf32_Rel);
        const rel_rodata_size = self.rodata_relocs.items.len * @sizeOf(Elf32_Rel);
        const rel_debug_line_size = self.debug.line_relocs.len * @sizeOf(Elf32_Rel);
        const rel_debug_info_size = self.debug.info_relocs.len * @sizeOf(Elf32_Rel);
        const attributes = arm_attributes;

        var offset: u64 = @sizeOf(Elf32_Ehdr);
        const text_offset = alignUp(offset, 16);
        offset = text_offset + self.text.len;
        const rodata_offset = alignUp(offset, 16);
        offset = rodata_offset + self.rodata.len;
        const rel_text_offset = alignUp(offset, 4);
        offset = rel_text_offset + rel_text_size;
        const rel_rodata_offset = alignUp(offset, 4);
        offset = rel_rodata_offset + rel_rodata_size;
        const symtab_offset = alignUp(offset, 4);
        offset = symtab_offset + symtab_size;
        const strtab_offset = offset;
        offset = strtab_offset + string_bytes;
        const shstrtab_offset = offset;
        offset = shstrtab_offset + self.shstrtab.items.len;
        const debug_line_offset = offset;
        offset = debug_line_offset + self.debug.line.len;
        const debug_abbrev_offset = offset;
        offset = debug_abbrev_offset + self.debug.abbrev.len;
        const debug_info_offset = offset;
        offset = debug_info_offset + self.debug.info.len;
        const rel_debug_line_offset = alignUp(offset, 4);
        offset = rel_debug_line_offset + rel_debug_line_size;
        const rel_debug_info_offset = alignUp(offset, 4);
        offset = rel_debug_info_offset + rel_debug_info_size;
        const attributes_offset = offset;
        offset = attributes_offset + attributes.len;
        const shdr_offset = alignUp(offset, 4);

        std.debug.assert(output.items.len == 0);
        const object_size: usize = @intCast(shdr_offset + NUM_SECTIONS * @sizeOf(Elf32_Shdr));
        try output.ensureTotalCapacityPrecise(self.allocator, object_size);

        var ehdr = Elf32_Ehdr{
            .e_ident = undefined,
            .e_type = ELF.ET_REL,
            .e_machine = self.arch.machine(),
            .e_version = ELF.VERSION_CURRENT,
            .e_entry = 0,
            .e_phoff = 0,
            .e_shoff = @intCast(shdr_offset),
            .e_flags = ELF.EF_ARM_EABI_VER5 | ELF.EF_ARM_ABI_FLOAT_HARD,
            .e_ehsize = @sizeOf(Elf32_Ehdr),
            .e_phentsize = 0,
            .e_phnum = 0,
            .e_shentsize = @sizeOf(Elf32_Shdr),
            .e_shnum = NUM_SECTIONS,
            .e_shstrndx = SHIDX_SHSTRTAB,
        };
        @memcpy(ehdr.e_ident[0..4], &ELF.MAGIC);
        ehdr.e_ident[4] = ELF.CLASS_32;
        ehdr.e_ident[5] = ELF.DATA_LSB;
        ehdr.e_ident[6] = ELF.VERSION_CURRENT;
        ehdr.e_ident[7] = @backingInt(self.osabi);
        @memset(ehdr.e_ident[8..16], 0);
        output.appendSliceAssumeCapacity(std.mem.asBytes(&ehdr));

        padTo(output, text_offset);
        output.appendSliceAssumeCapacity(self.text);
        for (self.text_relocs.items) |rel| storeRelAddend(output.items[@intCast(text_offset + rel.offset)..], rel.reloc_type, rel.addend);

        padTo(output, rodata_offset);
        output.appendSliceAssumeCapacity(self.rodata);
        for (self.rodata_relocs.items) |rel| storeRelAddend(output.items[@intCast(rodata_offset + rel.offset)..], rel.reloc_type, rel.addend);

        padTo(output, rel_text_offset);
        for (self.text_relocs.items) |rel| appendRel32(output, rel.offset, rel.symbol_idx + WRITER_SYMBOL_OFFSET, rel.reloc_type);
        padTo(output, rel_rodata_offset);
        for (self.rodata_relocs.items) |rel| appendRel32(output, rel.offset, rel.symbol_idx + WRITER_SYMBOL_OFFSET, rel.reloc_type);

        padTo(output, symtab_offset);
        output.appendSliceAssumeCapacity(&std.mem.zeroes([@sizeOf(Elf32_Sym)]u8));
        for (debug_target_sections) |section_index| {
            const section_sym = Elf32_Sym{
                .st_name = 0,
                .st_value = 0,
                .st_size = 0,
                .st_info = (ELF.STB_LOCAL << 4) | ELF.STT_SECTION,
                .st_other = 0,
                .st_shndx = section_index,
            };
            output.appendSliceAssumeCapacity(std.mem.asBytes(&section_sym));
        }
        const mapping_sym = Elf32_Sym{
            .st_name = 1,
            .st_value = 0,
            .st_size = 0,
            .st_info = (ELF.STB_LOCAL << 4) | ELF.STT_NOTYPE,
            .st_other = 0,
            .st_shndx = SHIDX_TEXT,
        };
        output.appendSliceAssumeCapacity(std.mem.asBytes(&mapping_sym));

        var name_offset: u32 = 1 + mapping_symbol_name.len + 1;
        for (self.symbols.items) |sym| {
            const bind: u8 = if (sym.is_global) ELF.STB_GLOBAL else ELF.STB_LOCAL;
            const sym_type: u8 = if (sym.is_function) ELF.STT_FUNC else if (sym.section == .rodata or sym.section == .bss) ELF.STT_OBJECT else ELF.STT_NOTYPE;
            const elf_sym = Elf32_Sym{
                .st_name = name_offset,
                .st_value = @intCast(sym.offset),
                .st_size = @intCast(sym.size),
                .st_info = (bind << 4) | sym_type,
                .st_other = if (sym.is_hidden) ELF.STV_HIDDEN else ELF.STV_DEFAULT,
                .st_shndx = switch (sym.section) {
                    .text => SHIDX_TEXT,
                    .data => 0,
                    .rodata => SHIDX_RODATA,
                    .bss => SHIDX_BSS,
                    .undef => ELF.SHN_UNDEF,
                },
            };
            output.appendSliceAssumeCapacity(std.mem.asBytes(&elf_sym));
            name_offset += @intCast(sym.name.len + 1);
            if (!sym.is_global) num_locals += 1;
        }

        output.appendAssumeCapacity(0);
        output.appendSliceAssumeCapacity(mapping_symbol_name);
        output.appendAssumeCapacity(0);
        for (self.symbols.items) |sym| {
            output.appendSliceAssumeCapacity(sym.name);
            output.appendAssumeCapacity(0);
        }

        output.appendSliceAssumeCapacity(self.shstrtab.items);

        output.appendSliceAssumeCapacity(self.debug.line);
        for (self.debug.line_relocs) |rel| storeRelAddend(output.items[@intCast(debug_line_offset + rel.section_offset)..], debugRelType32(rel), @intCast(rel.addend));
        output.appendSliceAssumeCapacity(self.debug.abbrev);
        output.appendSliceAssumeCapacity(self.debug.info);
        for (self.debug.info_relocs) |rel| storeRelAddend(output.items[@intCast(debug_info_offset + rel.section_offset)..], debugRelType32(rel), @intCast(rel.addend));

        padTo(output, rel_debug_line_offset);
        for (self.debug.line_relocs) |rel| appendRel32(output, rel.section_offset, debugTargetSymbol(rel), debugRelType32(rel));
        padTo(output, rel_debug_info_offset);
        for (self.debug.info_relocs) |rel| appendRel32(output, rel.section_offset, debugTargetSymbol(rel), debugRelType32(rel));

        output.appendSliceAssumeCapacity(attributes);

        padTo(output, shdr_offset);
        output.appendSliceAssumeCapacity(&std.mem.zeroes([@sizeOf(Elf32_Shdr)]u8));
        const headers = [_]Elf32_Shdr{
            section32(shname_text, ELF.SHT_PROGBITS, ELF.SHF_ALLOC | ELF.SHF_EXECINSTR, text_offset, self.text.len, 0, 0, 16, 0),
            section32(shname_rodata, ELF.SHT_PROGBITS, ELF.SHF_ALLOC, rodata_offset, self.rodata.len, 0, 0, 16, 0),
            section32(shname_rel_text, ELF.SHT_REL, ELF.SHF_INFO_LINK, rel_text_offset, rel_text_size, SHIDX_SYMTAB, SHIDX_TEXT, 4, @sizeOf(Elf32_Rel)),
            section32(shname_rel_rodata, ELF.SHT_REL, ELF.SHF_INFO_LINK, rel_rodata_offset, rel_rodata_size, SHIDX_SYMTAB, SHIDX_RODATA, 4, @sizeOf(Elf32_Rel)),
            section32(shname_symtab, ELF.SHT_SYMTAB, 0, symtab_offset, symtab_size, SHIDX_STRTAB, num_locals, 4, @sizeOf(Elf32_Sym)),
            section32(shname_strtab, ELF.SHT_STRTAB, 0, strtab_offset, string_bytes, 0, 0, 1, 0),
            section32(shname_shstrtab, ELF.SHT_STRTAB, 0, shstrtab_offset, self.shstrtab.items.len, 0, 0, 1, 0),
            section32(shname_debug_line, ELF.SHT_PROGBITS, 0, debug_line_offset, self.debug.line.len, 0, 0, 1, 0),
            section32(shname_debug_abbrev, ELF.SHT_PROGBITS, 0, debug_abbrev_offset, self.debug.abbrev.len, 0, 0, 1, 0),
            section32(shname_debug_info, ELF.SHT_PROGBITS, 0, debug_info_offset, self.debug.info.len, 0, 0, 1, 0),
            section32(shname_rel_debug_line, ELF.SHT_REL, ELF.SHF_INFO_LINK, rel_debug_line_offset, rel_debug_line_size, SHIDX_SYMTAB, SHIDX_DEBUG_LINE, 4, @sizeOf(Elf32_Rel)),
            section32(shname_rel_debug_info, ELF.SHT_REL, ELF.SHF_INFO_LINK, rel_debug_info_offset, rel_debug_info_size, SHIDX_SYMTAB, SHIDX_DEBUG_INFO, 4, @sizeOf(Elf32_Rel)),
            section32(shname_attributes, ELF.SHT_ARM_ATTRIBUTES, 0, attributes_offset, attributes.len, 0, 0, 1, 0),
            // Declared by size alone; SHT_NOBITS stores no bytes, so its file
            // offset only has to be inside the file.
            section32(shname_bss, ELF.SHT_NOBITS, ELF.SHF_ALLOC | ELF.SHF_WRITE, shdr_offset, self.zero_fill_size, 0, 0, 16, 0),
        };
        for (headers) |header| output.appendSliceAssumeCapacity(std.mem.asBytes(&header));
        std.debug.assert(output.items.len == object_size);
    }

    fn padTo(output: *std.ArrayList(u8), target: u64) void {
        const current: u64 = @intCast(output.items.len);
        if (current < target) {
            const padding: usize = @intCast(target - current);
            output.appendNTimesAssumeCapacity(0, padding);
        }
    }
};

fn appendDebugRelocations(
    arch: Architecture,
    relocs: []const DebugReloc,
    output: *std.ArrayList(u8),
) void {
    for (relocs) |rel| {
        const target_symbol_index: u64 = switch (rel.target) {
            .text => 1,
            .debug_line => 2,
            .debug_abbrev => 3,
        };
        const reloc_type: u32 = switch (arch) {
            .x86_64 => switch (rel.width) {
                .four => ELF.R_X86_64_32,
                .eight => ELF.R_X86_64_64,
            },
            .aarch64 => switch (rel.width) {
                .four => ELF.R_AARCH64_ABS32,
                .eight => ELF.R_AARCH64_ABS64,
            },
            // arm32 objects are ELF32; write32 emits their REL records.
            .arm => unreachable,
        };
        const elf_rela = Elf64_Rela{
            .r_offset = rel.section_offset,
            .r_info = (target_symbol_index << 32) | reloc_type,
            .r_addend = @intCast(rel.addend),
        };
        output.appendSliceAssumeCapacity(std.mem.asBytes(&elf_rela));
    }
}

fn section32(name: u32, sh_type: u32, flags: u32, offset: u64, size: u64, link: u32, info: u32, alignment: u32, entsize: u32) Elf32_Shdr {
    return .{
        .sh_name = name,
        .sh_type = sh_type,
        .sh_flags = flags,
        .sh_addr = 0,
        .sh_offset = @intCast(offset),
        .sh_size = @intCast(size),
        .sh_link = link,
        .sh_info = info,
        .sh_addralign = alignment,
        .sh_entsize = entsize,
    };
}

fn appendRel32(output: *std.ArrayList(u8), offset: u64, symbol_index: u32, reloc_type: u32) void {
    const rel = Elf32_Rel{
        .r_offset = @intCast(offset),
        .r_info = (symbol_index << 8) | reloc_type,
    };
    output.appendSliceAssumeCapacity(std.mem.asBytes(&rel));
}

fn debugTargetSymbol(rel: DebugReloc) u32 {
    return switch (rel.target) {
        .text => 1,
        .debug_line => 2,
        .debug_abbrev => 3,
    };
}

fn debugRelType32(rel: DebugReloc) u32 {
    return switch (rel.width) {
        .four => ELF.R_ARM_ABS32,
        // ELF32 DWARF addresses and offsets are four bytes.
        .eight => unreachable,
    };
}

/// The arm32 relocation types the writer emits.
const ArmReloc = enum(u32) {
    abs32 = ELF.R_ARM_ABS32,
    call = ELF.R_ARM_CALL,
    movw_prel_nc = ELF.R_ARM_MOVW_PREL_NC,
    movt_prel = ELF.R_ARM_MOVT_PREL,
};

/// Store a REL relocation's addend in the field it relocates, as AAELF32
/// defines the addend of each relocation type.
fn storeRelAddend(field: []u8, reloc_type: u32, addend: i64) void {
    const a: i32 = @intCast(addend);
    const reloc = std.enums.fromInt(ArmReloc, reloc_type) orelse {
        std.debug.panic("ELF32 invariant violated: relocation type {d} is not an arm32 type the writer emits", .{reloc_type});
    };
    switch (reloc) {
        .abs32 => std.mem.writeInt(i32, field[0..4], a, .little),
        .call => {
            // imm24 holds the addend in words.
            std.debug.assert(@mod(a, 4) == 0);
            const inst = std.mem.readInt(u32, field[0..4], .little);
            const imm24: u32 = @as(u24, @bitCast(@as(i24, @intCast(a >> 2))));
            std.mem.writeInt(u32, field[0..4], (inst & 0xFF000000) | imm24, .little);
        },
        .movw_prel_nc, .movt_prel => {
            // imm4:imm12 holds the addend as a signed 16-bit value.
            const imm16: u32 = @as(u16, @bitCast(@as(i16, @intCast(a))));
            const inst = std.mem.readInt(u32, field[0..4], .little);
            std.mem.writeInt(u32, field[0..4], (inst & 0xFFF0F000) | ((imm16 >> 12) << 16) | (imm16 & 0xFFF), .little);
        },
    }
}

/// The `.ARM.attributes` section of every arm32 object (D9 of
/// projects/big/arm32-dev-backend.md): format version 'A', one "aeabi"
/// subsection holding one file-scope attribute set. The procedure-call
/// attributes let the linker reject a soft-float partner; the architecture
/// attributes record the ARMv7-A + NEON floor.
const arm_attributes = blk: {
    const attrs = [_]u8{
        6, 10, // Tag_CPU_arch: ARMv7
        7, 'A', // Tag_CPU_arch_profile: application
        8, 1, // Tag_ARM_ISA_use: A32 permitted
        9, 2, // Tag_THUMB_ISA_use: Thumb-2 (interworking)
        10, 3, // Tag_FP_arch: VFPv3 (D32)
        12, 1, // Tag_Advanced_SIMD_arch: NEONv1
        14, 0, // Tag_ABI_PCS_R9_use: V6 (ordinary register)
        23, 3, // Tag_ABI_FP_number_model: IEEE 754
        24, 1, // Tag_ABI_align_needed: 8-byte
        25, 1, // Tag_ABI_align_preserved: 8-byte
        28, 1, // Tag_ABI_VFP_args: VFP registers (hard-float)
    };
    const vendor = "aeabi";
    const file_size = 1 + 4 + attrs.len; // Tag_File, size, attributes
    const subsection_size = 4 + vendor.len + 1 + file_size;
    var bytes: [1 + subsection_size]u8 = undefined;
    bytes[0] = 'A';
    std.mem.writeInt(u32, bytes[1..5], subsection_size, .little);
    @memcpy(bytes[5..][0..vendor.len], vendor);
    bytes[5 + vendor.len] = 0;
    const file_at = 5 + vendor.len + 1;
    bytes[file_at] = 1; // Tag_File
    std.mem.writeInt(u32, bytes[file_at + 1 ..][0..4], file_size, .little);
    @memcpy(bytes[file_at + 5 ..][0..attrs.len], &attrs);
    const final = bytes;
    break :blk &final;
};

fn alignUp(value: u64, alignment: u64) u64 {
    return (value + alignment - 1) & ~(alignment - 1);
}

// Tests

test "create minimal elf object" {
    var writer = try ElfWriter.init(std.testing.allocator, .x86_64, .none);
    defer writer.deinit();

    // Add some test code (ret instruction)
    writer.setCode(&[_]u8{0xC3});

    // Add a symbol for the function
    _ = try writer.addSymbol(.{
        .name = "test_func",
        .section = .text,
        .offset = 0,
        .size = 1,
        .is_global = true,
        .is_function = true,
    });

    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(std.testing.allocator);

    try writer.write(&output);

    // Check ELF magic
    try std.testing.expectEqualSlices(u8, "\x7fELF", output.items[0..4]);

    // Check it's 64-bit
    try std.testing.expectEqual(@as(u8, 2), output.items[4]);

    // Check it's little endian
    try std.testing.expectEqual(@as(u8, 1), output.items[5]);
}

test "elf with external symbol" {
    var writer = try ElfWriter.init(std.testing.allocator, .x86_64, .none);
    defer writer.deinit();

    // Simple code: call to external function (placeholder)
    writer.setCode(&[_]u8{ 0xE8, 0x00, 0x00, 0x00, 0x00, 0xC3 });

    // Add external symbol
    const ext_idx = try writer.addExternalSymbol("external_func");

    // Add relocation for the call
    try writer.addTextRelocation(1, ext_idx, -4);

    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(std.testing.allocator);

    try writer.write(&output);

    // Should produce valid ELF
    try std.testing.expectEqualSlices(u8, "\x7fELF", output.items[0..4]);
}

test "DWARF relocations preserve target section and field width" {
    const relocs = [_]DebugReloc{
        .{
            .section_offset = 6,
            .target = .debug_abbrev,
            .width = .four,
            .addend = 0,
        },
        .{
            .section_offset = 24,
            .target = .text,
            .width = .eight,
            .addend = 32,
        },
        .{
            .section_offset = 40,
            .target = .debug_line,
            .width = .four,
            .addend = 0,
        },
    };

    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(std.testing.allocator);
    try output.ensureTotalCapacityPrecise(std.testing.allocator, relocs.len * @sizeOf(Elf64_Rela));
    appendDebugRelocations(.x86_64, &relocs, &output);

    try std.testing.expectEqual(@as(usize, 3 * @sizeOf(Elf64_Rela)), output.items.len);
    const abbrev = std.mem.bytesToValue(Elf64_Rela, output.items[0..@sizeOf(Elf64_Rela)]);
    const text = std.mem.bytesToValue(Elf64_Rela, output.items[@sizeOf(Elf64_Rela)..][0..@sizeOf(Elf64_Rela)]);
    const line = std.mem.bytesToValue(Elf64_Rela, output.items[2 * @sizeOf(Elf64_Rela) ..][0..@sizeOf(Elf64_Rela)]);

    try std.testing.expectEqual(@as(u64, 6), abbrev.r_offset);
    try std.testing.expectEqual((@as(u64, 3) << 32) | ELF.R_X86_64_32, abbrev.r_info);
    try std.testing.expectEqual(@as(u64, 24), text.r_offset);
    try std.testing.expectEqual((@as(u64, 1) << 32) | ELF.R_X86_64_64, text.r_info);
    try std.testing.expectEqual(@as(i64, 32), text.r_addend);
    try std.testing.expectEqual(@as(u64, 40), line.r_offset);
    try std.testing.expectEqual((@as(u64, 2) << 32) | ELF.R_X86_64_32, line.r_info);
}

test "arm32 object is ELF32, EM_ARM, hard-float, with REL relocations and in-place addends" {
    var writer = try ElfWriter.init(std.testing.allocator, .arm, .none);
    defer writer.deinit();

    // bl ext; movw r0, #0; movt r0, #0; add r0, pc, r0; bx lr
    const code = [_]u8{
        0xFE, 0xFF, 0xFF, 0xEB,
        0x00, 0x00, 0x00, 0xE3,
        0x00, 0x00, 0x40, 0xE3,
        0x00, 0x00, 0x8F, 0xE0,
        0x1E, 0xFF, 0x2F, 0xE1,
    };
    writer.setCode(&code);
    const rodata: [8]u8 = @splat(0);
    writer.setRodata(&rodata);

    _ = try writer.addSymbol(.{ .name = "f", .section = .text, .offset = 0, .size = code.len, .is_global = true, .is_function = true });
    const data = try writer.addSymbol(.{ .name = "d", .section = .rodata, .offset = 0, .size = 4, .is_global = true, .is_function = false });
    const ext = try writer.addExternalSymbol("ext");
    try writer.addTextRelocation(0, ext, -8);
    try writer.addTextDataRelocation(4, data, .arm_movw_prel);
    try writer.addTextDataRelocation(8, data, .arm_movt_prel);
    try writer.addRodataRelocation(4, data, 3);

    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(std.testing.allocator);
    try writer.write(&output);
    const bytes = output.items;

    const ehdr = std.mem.bytesToValue(Elf32_Ehdr, bytes[0..@sizeOf(Elf32_Ehdr)]);
    try std.testing.expectEqual(@as(u8, 1), ehdr.e_ident[4]); // ELFCLASS32
    try std.testing.expectEqual(@as(u16, 40), ehdr.e_machine);
    try std.testing.expectEqual(@as(u32, 0x05000400), ehdr.e_flags);

    const shdrs = std.mem.bytesAsSlice(Elf32_Shdr, bytes[ehdr.e_shoff..][0 .. ehdr.e_shnum * @sizeOf(Elf32_Shdr)]);
    const shstr = shdrs[ehdr.e_shstrndx];
    const Section32 = struct {
        fn find(all: []align(1) const Elf32_Shdr, strtab: []const u8, name: []const u8) Elf32_Shdr {
            for (all) |h| {
                if (std.mem.eql(u8, std.mem.sliceTo(strtab[h.sh_name..], 0), name)) return h;
            }
            unreachable;
        }
    };
    const strtab = bytes[shstr.sh_offset..][0..shstr.sh_size];
    const rel_text = Section32.find(shdrs, strtab, ".rel.text");
    try std.testing.expectEqual(@as(u32, 9), rel_text.sh_type);
    try std.testing.expectEqual(@as(u32, 8), rel_text.sh_entsize);
    try std.testing.expectEqual(@as(u32, 0x70000003), Section32.find(shdrs, strtab, ".ARM.attributes").sh_type);

    const rels = std.mem.bytesAsSlice(Elf32_Rel, bytes[rel_text.sh_offset..][0..rel_text.sh_size]);
    try std.testing.expectEqual(@as(usize, 3), rels.len);
    try std.testing.expectEqual(@as(u32, 28), rels[0].r_info & 0xFF); // R_ARM_CALL
    try std.testing.expectEqual(@as(u32, 45), rels[1].r_info & 0xFF); // R_ARM_MOVW_PREL_NC
    try std.testing.expectEqual(@as(u32, 46), rels[2].r_info & 0xFF); // R_ARM_MOVT_PREL
    const rel_rodata = Section32.find(shdrs, strtab, ".rel.rodata");
    const rodata_rels = std.mem.bytesAsSlice(Elf32_Rel, bytes[rel_rodata.sh_offset..][0..rel_rodata.sh_size]);
    try std.testing.expectEqual(@as(u32, 2), rodata_rels[0].r_info & 0xFF); // R_ARM_ABS32

    // REL addends live in the relocated fields.
    const text = Section32.find(shdrs, strtab, ".text");
    const t = bytes[text.sh_offset..][0..text.sh_size];
    try std.testing.expectEqual(@as(u32, 0xEBFFFFFE), std.mem.readInt(u32, t[0..4], .little)); // BL, addend -8
    try std.testing.expectEqual(@as(u32, 0xE30F0FF0), std.mem.readInt(u32, t[4..8], .little)); // movw r0, #0xfff0
    try std.testing.expectEqual(@as(u32, 0xE34F0FF4), std.mem.readInt(u32, t[8..12], .little)); // movt r0, #0xfff4
    const ro = Section32.find(shdrs, strtab, ".rodata");
    try std.testing.expectEqual(@as(i32, 3), std.mem.readInt(i32, bytes[ro.sh_offset + 4 ..][0..4], .little));
}

test "arm32 object declares zero-fill data in .bss and points its symbols there" {
    var writer = try ElfWriter.init(std.testing.allocator, .arm, .none);
    defer writer.deinit();
    writer.setCode(&.{ 0x1E, 0xFF, 0x2F, 0xE1 }); // bx lr
    writer.setZeroFill(4096);
    _ = try writer.addSymbol(.{ .name = "table", .section = .bss, .offset = 8, .size = 4088, .is_global = true, .is_function = false });

    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(std.testing.allocator);
    try writer.write(&output);
    const bytes = output.items;

    const ehdr = std.mem.bytesToValue(Elf32_Ehdr, bytes[0..@sizeOf(Elf32_Ehdr)]);
    const shdrs = std.mem.bytesAsSlice(Elf32_Shdr, bytes[ehdr.e_shoff..][0 .. ehdr.e_shnum * @sizeOf(Elf32_Shdr)]);
    const shstr = shdrs[ehdr.e_shstrndx];
    const names = bytes[shstr.sh_offset..][0..shstr.sh_size];
    const bss_index = for (shdrs, 0..) |h, i| {
        if (std.mem.eql(u8, std.mem.sliceTo(names[h.sh_name..], 0), ".bss")) break i;
    } else return error.TestExpectedEqual;
    const bss = shdrs[bss_index];
    try std.testing.expectEqual(@as(u32, ELF.SHT_NOBITS), bss.sh_type);
    try std.testing.expectEqual(@as(u32, 4096), bss.sh_size);
    // The file stores none of it.
    try std.testing.expect(bytes.len < 4096);

    const symtab = for (shdrs) |h| {
        if (h.sh_type == ELF.SHT_SYMTAB) break h;
    } else return error.TestExpectedEqual;
    const strtab = shdrs[symtab.sh_link];
    const symbols = std.mem.bytesAsSlice(Elf32_Sym, bytes[symtab.sh_offset..][0..symtab.sh_size]);
    const table = for (symbols) |sym| {
        if (std.mem.eql(u8, std.mem.sliceTo(bytes[strtab.sh_offset + sym.st_name ..], 0), "table")) break sym;
    } else return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(u16, @intCast(bss_index)), table.st_shndx);
    try std.testing.expectEqual(@as(u32, 8), table.st_value);
    try std.testing.expectEqual(@as(u8, ELF.STT_OBJECT), table.st_info & 0xf);
}

test "aarch64 DWARF relocations use AArch64 absolute types" {
    const relocs = [_]DebugReloc{
        .{ .section_offset = 6, .target = .debug_abbrev, .width = .four, .addend = 0 },
        .{ .section_offset = 24, .target = .text, .width = .eight, .addend = 32 },
    };
    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(std.testing.allocator);
    try output.ensureTotalCapacityPrecise(std.testing.allocator, relocs.len * @sizeOf(Elf64_Rela));
    appendDebugRelocations(.aarch64, &relocs, &output);

    const abbrev = std.mem.bytesToValue(Elf64_Rela, output.items[0..@sizeOf(Elf64_Rela)]);
    const text = std.mem.bytesToValue(Elf64_Rela, output.items[@sizeOf(Elf64_Rela)..][0..@sizeOf(Elf64_Rela)]);
    try std.testing.expectEqual((@as(u64, 3) << 32) | ELF.R_AARCH64_ABS32, abbrev.r_info);
    try std.testing.expectEqual((@as(u64, 1) << 32) | ELF.R_AARCH64_ABS64, text.r_info);
    try std.testing.expectEqual(@as(i64, 32), text.r_addend);
}
