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
const invariant = @import("base").invariant;
const FunctionRelocationKind = @import("../Relocation.zig").FunctionRelocationKind;
const DataRelocationKind = @import("../Relocation.zig").DataRelocationKind;
const object = @import("mod.zig");
const DebugReloc = object.DebugReloc;
const UnitImage = @import("../UnitImage.zig");

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
    const SHT_REL = 9;
    const SHT_ARM_ATTRIBUTES = 0x70000003;
    const SHT_NOBITS = 8;

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

    // arm32 header flags: EABI version 5, hard-float procedure call standard
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
    sh_addr: u32 = 0,
    sh_offset: u32,
    sh_size: u32,
    sh_link: u32,
    sh_info: u32,
    sh_addralign: u32,
    sh_entsize: u32,
};

/// ELF32 symbol table entry (16 bytes); the fields are in a different order
/// from ELF64's.
const Elf32_Sym = extern struct {
    st_name: u32,
    st_value: u32,
    st_size: u32,
    st_info: u8,
    st_other: u8,
    st_shndx: u16,
};

/// ELF32 relocation entry without addend (8 bytes)
const Elf32_Rel = extern struct {
    r_offset: u32,
    r_info: u32,
};

/// A section header in the writer's own widths. Each class narrows it to its
/// record with `shdr`.
const SectionHeader = struct {
    name: u32,
    type: u32,
    flags: u64 = 0,
    offset: u64,
    size: u64,
    link: u32 = 0,
    info: u32 = 0,
    addralign: u64,
    entsize: u64 = 0,
};

/// A symbol table entry in the writer's own widths. Each class narrows it to
/// its record with `sym`.
const SymbolEntry = struct {
    name: u32,
    info: u8,
    other: u8,
    shndx: u16,
    value: u64,
    size: u64,
};

/// The record types, relocation form and table alignment of the 64-bit ELF
/// class, which x86_64 and aarch64 objects use. `ElfWriter.writeClass`
/// lays out an object from these alone, so a class differs from another
/// only here.
const Elf64 = struct {
    const ident_class = ELF.CLASS_64;
    const Ehdr = Elf64_Ehdr;
    const Shdr = Elf64_Shdr;
    const Sym = Elf64_Sym;
    /// One relocation record; 64-bit objects carry the addend in it.
    const Reloc = Elf64_Rela;
    const addend_in_record = true;
    const reloc_section_type = ELF.SHT_RELA;
    /// The name prefix of a relocation section (`.rela.text`).
    const reloc_section_prefix = ".rela";
    /// The alignment of the symbol table and the relocation sections.
    const table_align = 8;

    fn reloc(offset: u64, symbol: u32, reloc_type: u32, addend: i64) Reloc {
        return .{
            .r_offset = offset,
            .r_info = (@as(u64, symbol) << 32) | reloc_type,
            .r_addend = addend,
        };
    }

    fn shdr(h: SectionHeader) Shdr {
        return .{
            .sh_name = h.name,
            .sh_type = h.type,
            .sh_flags = h.flags,
            .sh_offset = h.offset,
            .sh_size = h.size,
            .sh_link = h.link,
            .sh_info = h.info,
            .sh_addralign = h.addralign,
            .sh_entsize = h.entsize,
        };
    }

    fn sym(e: SymbolEntry) Sym {
        return .{
            .st_name = e.name,
            .st_info = e.info,
            .st_other = e.other,
            .st_shndx = e.shndx,
            .st_value = e.value,
            .st_size = e.size,
        };
    }
};

/// The 32-bit ELF class, which arm32 objects use. Its relocation records have
/// no addend field (REL), so `ElfWriter.writeClass` stores each addend in
/// the field it relocates, as AAELF32 specifies.
const Elf32 = struct {
    const ident_class = ELF.CLASS_32;
    const Ehdr = Elf32_Ehdr;
    const Shdr = Elf32_Shdr;
    const Sym = Elf32_Sym;
    /// One relocation record, without the addend.
    const Reloc = Elf32_Rel;
    const addend_in_record = false;
    const reloc_section_type = ELF.SHT_REL;
    /// The name prefix of a relocation section (`.rel.text`).
    const reloc_section_prefix = ".rel";
    /// The alignment of the symbol table and the relocation sections.
    const table_align = 4;

    /// The record for one relocation. The addend has no field here;
    /// `writeClass` has stored it in the relocated field.
    fn reloc(offset: u64, symbol: u32, reloc_type: u32, _: i64) Reloc {
        return .{
            .r_offset = @intCast(offset),
            .r_info = (@as(u32, @as(u24, @intCast(symbol))) << 8) | @as(u8, @intCast(reloc_type)),
        };
    }

    fn shdr(h: SectionHeader) Shdr {
        return .{
            .sh_name = h.name,
            .sh_type = h.type,
            .sh_flags = @intCast(h.flags),
            .sh_offset = @intCast(h.offset),
            .sh_size = @intCast(h.size),
            .sh_link = h.link,
            .sh_info = h.info,
            .sh_addralign = @intCast(h.addralign),
            .sh_entsize = @intCast(h.entsize),
        };
    }

    fn sym(e: SymbolEntry) Sym {
        return .{
            .st_name = e.name,
            .st_value = @intCast(e.value),
            .st_size = @intCast(e.size),
            .st_info = e.info,
            .st_other = e.other,
            .st_shndx = e.shndx,
        };
    }
};

/// Target architecture for ELF generation
pub const Architecture = enum {
    x86_64,
    aarch64,
    /// 32-bit ARM (A32, AAPCS hard-float), written as ELF32 with REL
    /// relocations.
    arm32,

    fn machine(self: Architecture) u16 {
        return switch (self) {
            .x86_64 => ELF.EM_X86_64,
            .aarch64 => ELF.EM_AARCH64,
            .arm32 => ELF.EM_ARM,
        };
    }

    /// The header's `e_flags`.
    fn flags(self: Architecture) u32 {
        return switch (self) {
            .x86_64, .aarch64 => 0,
            .arm32 => ELF.EF_ARM_EABI_VER5 | ELF.EF_ARM_ABI_FLOAT_HARD,
        };
    }

    /// The mapping symbol marking the start of `.text` as code of this
    /// instruction set, which AAELF32 requires; none elsewhere.
    fn textMappingSymbol(self: Architecture) ?[]const u8 {
        return switch (self) {
            .x86_64, .aarch64 => null,
            .arm32 => "$a",
        };
    }

    /// The contents of the `.ARM.attributes` section; none elsewhere.
    fn armAttributes(self: Architecture) ?[]const u8 {
        return switch (self) {
            .x86_64, .aarch64 => null,
            .arm32 => arm_attributes,
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
    rodata: UnitImage.PiecedBytes,
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
            .rodata = .{},
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

    pub fn setRodata(self: *Self, rodata: UnitImage.PiecedBytes) void {
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
            .arm32 => ELF.R_ARM_ABS32,
        };

        try self.rodata_relocs.append(self.allocator, .{
            .offset = offset,
            .symbol_idx = symbol_idx,
            .reloc_type = reloc_type,
            .addend = addend,
        });
    }

    /// Add a relocation to the text section
    pub fn addTextRelocation(self: *Self, offset: u64, symbol_idx: u32, kind: FunctionRelocationKind) Allocator.Error!void {
        std.debug.assert(self.arch == switch (kind) {
            .x86_call_rel32 => Architecture.x86_64,
            .aarch64_call26 => Architecture.aarch64,
        });
        const reloc_type: u32 = switch (kind) {
            .x86_call_rel32 => ELF.R_X86_64_PLT32,
            .aarch64_call26 => ELF.R_AARCH64_CALL26,
        };
        const addend: i64 = switch (kind) {
            .x86_call_rel32 => -4,
            .aarch64_call26 => 0,
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
                    .arm32 => invariant("ELF invariant violated: {t} data relocation in arm32 code, which has no data relocation kinds yet", .{kind}),
                },
                .addend = @as(i64, 0),
            },
            .rel32 => .{
                .kind = switch (self.arch) {
                    .x86_64 => ELF.R_X86_64_PC32,
                    .aarch64 => invariant("ELF invariant violated: rel32 data relocation in aarch64 code, which emits page21 and pageoff12", .{}),
                    .arm32 => invariant("ELF invariant violated: {t} data relocation in arm32 code, which has no data relocation kinds yet", .{kind}),
                },
                .addend = @as(i64, -4),
            },
            .page21 => .{
                .kind = switch (self.arch) {
                    .x86_64 => invariant("ELF invariant violated: page21 data relocation in x86_64 code, which emits rel32", .{}),
                    .aarch64 => ELF.R_AARCH64_ADR_PREL_PG_HI21,
                    .arm32 => invariant("ELF invariant violated: {t} data relocation in arm32 code, which has no data relocation kinds yet", .{kind}),
                },
                .addend = @as(i64, 0),
            },
            .pageoff12 => .{
                .kind = switch (self.arch) {
                    .x86_64 => invariant("ELF invariant violated: pageoff12 data relocation in x86_64 code, which emits rel32", .{}),
                    .aarch64 => ELF.R_AARCH64_ADD_ABS_LO12_NC,
                    .arm32 => invariant("ELF invariant violated: {t} data relocation in arm32 code, which has no data relocation kinds yet", .{kind}),
                },
                .addend = @as(i64, 0),
            },
            // The field's own bytes hold the addend.
            .abs32_field => .{
                .kind = switch (self.arch) {
                    .x86_64 => ELF.R_X86_64_32,
                    .aarch64 => invariant("ELF invariant violated: abs32_field data relocation in aarch64 code, which only an x86_64 test unit emits", .{}),
                    .arm32 => invariant("ELF invariant violated: {t} data relocation in arm32 code, which has no data relocation kinds yet", .{kind}),
                },
                .addend = std.mem.readInt(u32, self.text[@intCast(offset)..][0..4], .little),
            },
            .abs64_field => .{
                .kind = switch (self.arch) {
                    .x86_64 => invariant("ELF invariant violated: abs64_field data relocation in x86_64 code, which only an arm64 test unit emits", .{}),
                    .aarch64 => ELF.R_AARCH64_ABS64,
                    .arm32 => invariant("ELF invariant violated: {t} data relocation in arm32 code, which has no data relocation kinds yet", .{kind}),
                },
                .addend = std.mem.readInt(i64, self.text[@intCast(offset)..][0..8], .little),
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

    /// Write the ELF object file to a buffer
    pub fn write(self: *Self, output: *std.ArrayList(u8)) Allocator.Error!void {
        return switch (self.arch) {
            .x86_64, .aarch64 => self.writeClass(Elf64, output),
            .arm32 => self.writeClass(Elf32, output),
        };
    }

    /// Write the object with the records of ELF class `C` (see `Elf64`).
    fn writeClass(self: *Self, comptime C: type, output: *std.ArrayList(u8)) Allocator.Error!void {
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
        // `.ARM.attributes` follows `.bss`, so the sections every
        // architecture has keep the same indices.
        const SHIDX_ARM_ATTRIBUTES = 14;
        const attributes = self.arch.armAttributes();
        const mapping_symbol = self.arch.textMappingSymbol();
        const num_sections: u16 = if (attributes == null) SHIDX_ARM_ATTRIBUTES else SHIDX_ARM_ATTRIBUTES + 1;

        // Add section names to shstrtab
        const shname_text = try self.addString(&self.shstrtab, ".text");
        // Read-only data holding absolute pointers is writable, as a
        // compiler's `.data.rel.ro` is, so a loader can relocate it in a
        // position-independent output without writing to code pages.
        const pointer_bearing = self.rodata_relocs.items.len != 0;
        const shname_rodata = try self.addString(&self.shstrtab, if (pointer_bearing) ".data.rel.ro" else ".rodata");
        const shname_reloc_text = try self.addString(&self.shstrtab, C.reloc_section_prefix ++ ".text");
        const shname_reloc_rodata = try self.addString(&self.shstrtab, if (pointer_bearing) C.reloc_section_prefix ++ ".data.rel.ro" else C.reloc_section_prefix ++ ".rodata");
        const shname_symtab = try self.addString(&self.shstrtab, ".symtab");
        const shname_strtab = try self.addString(&self.shstrtab, ".strtab");
        const shname_shstrtab = try self.addString(&self.shstrtab, ".shstrtab");
        const shname_debug_line = try self.addString(&self.shstrtab, ".debug_line");
        const shname_debug_abbrev = try self.addString(&self.shstrtab, ".debug_abbrev");
        const shname_debug_info = try self.addString(&self.shstrtab, ".debug_info");
        const shname_reloc_debug_line = try self.addString(&self.shstrtab, C.reloc_section_prefix ++ ".debug_line");
        const shname_reloc_debug_info = try self.addString(&self.shstrtab, C.reloc_section_prefix ++ ".debug_info");
        const shname_bss = try self.addString(&self.shstrtab, ".bss");
        const shname_arm_attributes = if (attributes == null) 0 else try self.addString(&self.shstrtab, ".ARM.attributes");

        const debug_target_sections = [_]u16{ SHIDX_TEXT, SHIDX_DEBUG_LINE, SHIDX_DEBUG_ABBREV };
        // The null symbol, the section symbols, the mapping symbol if any,
        // then the writer's symbols.
        const WRITER_SYMBOL_OFFSET: u32 = @as(u32, 1 + debug_target_sections.len) + @intFromBool(mapping_symbol != null);
        var num_locals: u32 = WRITER_SYMBOL_OFFSET;
        const symtab_size = (self.symbols.items.len + WRITER_SYMBOL_OFFSET) * @sizeOf(C.Sym);
        // The string table starts with a null byte, then the mapping
        // symbol's name if any.
        const writer_names_offset: u32 = if (mapping_symbol) |name| @intCast(1 + name.len + 1) else 1;
        var string_bytes: usize = writer_names_offset;
        for (self.symbols.items) |symbol| string_bytes += symbol.name.len + 1;
        const reloc_text_size = self.text_relocs.items.len * @sizeOf(C.Reloc);
        const reloc_rodata_size = self.rodata_relocs.items.len * @sizeOf(C.Reloc);
        const reloc_debug_line_size = self.debug.line_relocs.len * @sizeOf(C.Reloc);
        const reloc_debug_info_size = self.debug.info_relocs.len * @sizeOf(C.Reloc);

        // Calculate offsets
        const ehdr_size: u64 = @sizeOf(C.Ehdr);

        // Section data starts after headers
        var offset: u64 = ehdr_size;

        // Align sections
        const text_offset = alignUp(offset, 16);
        offset = text_offset + self.text.len;

        const rodata_offset = alignUp(offset, 16);
        offset = rodata_offset + self.rodata.len;

        const reloc_text_offset = alignUp(offset, C.table_align);
        offset = reloc_text_offset + reloc_text_size;

        const reloc_rodata_offset = alignUp(offset, C.table_align);
        offset = reloc_rodata_offset + reloc_rodata_size;

        const symtab_offset = alignUp(offset, C.table_align);
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
        const reloc_debug_line_offset = alignUp(offset, C.table_align);
        offset = reloc_debug_line_offset + reloc_debug_line_size;
        const reloc_debug_info_offset = alignUp(offset, C.table_align);
        offset = reloc_debug_info_offset + reloc_debug_info_size;
        const arm_attributes_offset = offset;
        if (attributes) |bytes| offset += bytes.len;

        const shdr_offset = alignUp(offset, C.table_align);

        std.debug.assert(output.items.len == 0);
        const object_size: usize = @intCast(shdr_offset + num_sections * @sizeOf(C.Shdr));
        try output.ensureTotalCapacityPrecise(self.allocator, object_size);

        // Write ELF header
        var ehdr = C.Ehdr{
            .e_ident = undefined,
            .e_type = ELF.ET_REL,
            .e_machine = self.arch.machine(),
            .e_version = ELF.VERSION_CURRENT,
            .e_entry = 0,
            .e_phoff = 0,
            .e_shoff = @intCast(shdr_offset),
            .e_flags = self.arch.flags(),
            .e_ehsize = @sizeOf(C.Ehdr),
            .e_phentsize = 0,
            .e_phnum = 0,
            .e_shentsize = @sizeOf(C.Shdr),
            .e_shnum = num_sections,
            .e_shstrndx = SHIDX_SHSTRTAB,
        };

        // Set e_ident
        @memcpy(ehdr.e_ident[0..4], &ELF.MAGIC);
        ehdr.e_ident[4] = C.ident_class;
        ehdr.e_ident[5] = ELF.DATA_LSB;
        ehdr.e_ident[6] = ELF.VERSION_CURRENT;
        ehdr.e_ident[7] = @backingInt(self.osabi);
        @memset(ehdr.e_ident[8..16], 0);

        output.appendSliceAssumeCapacity(std.mem.asBytes(&ehdr));

        // Pad to text section
        padTo(output, text_offset);
        output.appendSliceAssumeCapacity(self.text);
        if (!C.addend_in_record) self.storeAddends(output, text_offset, self.text_relocs.items);

        padTo(output, rodata_offset);
        self.rodata.appendAssumeCapacity(output);
        if (!C.addend_in_record) self.storeAddends(output, rodata_offset, self.rodata_relocs.items);

        // Pad to the relocation sections
        padTo(output, reloc_text_offset);
        for (self.text_relocs.items) |rel| {
            const elf_reloc = C.reloc(rel.offset, rel.symbol_idx + WRITER_SYMBOL_OFFSET, rel.reloc_type, rel.addend);
            output.appendSliceAssumeCapacity(std.mem.asBytes(&elf_reloc));
        }

        padTo(output, reloc_rodata_offset);
        for (self.rodata_relocs.items) |rel| {
            const elf_reloc = C.reloc(rel.offset, rel.symbol_idx + WRITER_SYMBOL_OFFSET, rel.reloc_type, rel.addend);
            output.appendSliceAssumeCapacity(std.mem.asBytes(&elf_reloc));
        }

        // Pad to symtab
        padTo(output, symtab_offset);
        // First symbol is always null
        output.appendSliceAssumeCapacity(&std.mem.zeroes([@sizeOf(C.Sym)]u8));

        // Section symbols used by DWARF cross-section relocations.
        for (debug_target_sections) |section_index| {
            const section_sym = C.sym(.{
                .name = 0,
                .info = (ELF.STB_LOCAL << 4) | ELF.STT_SECTION,
                .other = 0,
                .shndx = section_index,
                .value = 0,
                .size = 0,
            });
            output.appendSliceAssumeCapacity(std.mem.asBytes(&section_sym));
        }
        if (mapping_symbol != null) {
            const elf_sym = C.sym(.{
                .name = 1,
                .info = (ELF.STB_LOCAL << 4) | ELF.STT_NOTYPE,
                .other = 0,
                .shndx = SHIDX_TEXT,
                .value = 0,
                .size = 0,
            });
            output.appendSliceAssumeCapacity(std.mem.asBytes(&elf_sym));
        }

        // Count local symbols (for sh_info)

        // Add symbols
        var name_offset: u32 = writer_names_offset;
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

            const elf_sym = C.sym(.{
                .name = name_offset,
                .info = st_info,
                .other = if (sym.is_hidden) ELF.STV_HIDDEN else ELF.STV_DEFAULT,
                .shndx = st_shndx,
                .value = sym.offset,
                .size = sym.size,
            });

            output.appendSliceAssumeCapacity(std.mem.asBytes(&elf_sym));
            name_offset += @intCast(sym.name.len + 1);

            if (!sym.is_global) {
                num_locals += 1;
            }
        }

        // strtab (no padding needed)
        output.appendAssumeCapacity(0);
        if (mapping_symbol) |name| {
            output.appendSliceAssumeCapacity(name);
            output.appendAssumeCapacity(0);
        }
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
        if (!C.addend_in_record) {
            storeDebugAddends(self.arch, output.items[@intCast(debug_line_offset)..][0..self.debug.line.len], self.debug.line_relocs);
            storeDebugAddends(self.arch, output.items[@intCast(debug_info_offset)..][0..self.debug.info.len], self.debug.info_relocs);
        }
        padTo(output, reloc_debug_line_offset);
        appendDebugRelocations(C, self.arch, self.debug.line_relocs, output);
        padTo(output, reloc_debug_info_offset);
        appendDebugRelocations(C, self.arch, self.debug.info_relocs, output);
        if (attributes) |bytes| output.appendSliceAssumeCapacity(bytes);

        // Pad to section headers
        padTo(output, shdr_offset);

        // Write section headers
        // 0: NULL section
        output.appendSliceAssumeCapacity(&std.mem.zeroes([@sizeOf(C.Shdr)]u8));

        // 1: .text
        appendShdr(C, output, .{ .name = shname_text, .type = ELF.SHT_PROGBITS, .flags = ELF.SHF_ALLOC | ELF.SHF_EXECINSTR, .offset = text_offset, .size = self.text.len, .addralign = 16 });

        // 2: .rodata
        appendShdr(C, output, .{ .name = shname_rodata, .type = ELF.SHT_PROGBITS, .flags = if (pointer_bearing) ELF.SHF_ALLOC | ELF.SHF_WRITE else ELF.SHF_ALLOC, .offset = rodata_offset, .size = self.rodata.len, .addralign = 16 });

        // 3: relocations for .text
        appendShdr(C, output, .{ .name = shname_reloc_text, .type = C.reloc_section_type, .flags = ELF.SHF_INFO_LINK, .offset = reloc_text_offset, .size = reloc_text_size, .link = SHIDX_SYMTAB, .info = SHIDX_TEXT, .addralign = C.table_align, .entsize = @sizeOf(C.Reloc) });

        // 4: relocations for .rodata
        appendShdr(C, output, .{ .name = shname_reloc_rodata, .type = C.reloc_section_type, .flags = ELF.SHF_INFO_LINK, .offset = reloc_rodata_offset, .size = reloc_rodata_size, .link = SHIDX_SYMTAB, .info = SHIDX_RODATA, .addralign = C.table_align, .entsize = @sizeOf(C.Reloc) });

        // 5: .symtab
        appendShdr(C, output, .{ .name = shname_symtab, .type = ELF.SHT_SYMTAB, .offset = symtab_offset, .size = symtab_size, .link = SHIDX_STRTAB, .info = num_locals, .addralign = C.table_align, .entsize = @sizeOf(C.Sym) });

        // 6: .strtab
        appendShdr(C, output, .{ .name = shname_strtab, .type = ELF.SHT_STRTAB, .offset = strtab_offset, .size = string_bytes, .addralign = 1 });

        // 7: .shstrtab
        appendShdr(C, output, .{ .name = shname_shstrtab, .type = ELF.SHT_STRTAB, .offset = shstrtab_offset, .size = self.shstrtab.items.len, .addralign = 1 });

        // 8: .debug_line
        appendShdr(C, output, .{ .name = shname_debug_line, .type = ELF.SHT_PROGBITS, .offset = debug_line_offset, .size = self.debug.line.len, .addralign = 1 });

        // 9: .debug_abbrev
        appendShdr(C, output, .{ .name = shname_debug_abbrev, .type = ELF.SHT_PROGBITS, .offset = debug_abbrev_offset, .size = self.debug.abbrev.len, .addralign = 1 });

        // 10: .debug_info
        appendShdr(C, output, .{ .name = shname_debug_info, .type = ELF.SHT_PROGBITS, .offset = debug_info_offset, .size = self.debug.info.len, .addralign = 1 });

        // 11: relocations for .debug_line
        appendShdr(C, output, .{ .name = shname_reloc_debug_line, .type = C.reloc_section_type, .flags = ELF.SHF_INFO_LINK, .offset = reloc_debug_line_offset, .size = reloc_debug_line_size, .link = SHIDX_SYMTAB, .info = SHIDX_DEBUG_LINE, .addralign = C.table_align, .entsize = @sizeOf(C.Reloc) });

        // 12: relocations for .debug_info
        appendShdr(C, output, .{ .name = shname_reloc_debug_info, .type = C.reloc_section_type, .flags = ELF.SHF_INFO_LINK, .offset = reloc_debug_info_offset, .size = reloc_debug_info_size, .link = SHIDX_SYMTAB, .info = SHIDX_DEBUG_INFO, .addralign = C.table_align, .entsize = @sizeOf(C.Reloc) });

        // 13: .bss, declared by size alone; SHT_NOBITS stores no bytes, so
        // its file offset only has to be inside the file.
        appendShdr(C, output, .{ .name = shname_bss, .type = ELF.SHT_NOBITS, .flags = ELF.SHF_ALLOC | ELF.SHF_WRITE, .offset = shdr_offset, .size = self.zero_fill_size, .addralign = 16 });

        // 14: .ARM.attributes
        if (attributes) |bytes| appendShdr(C, output, .{ .name = shname_arm_attributes, .type = ELF.SHT_ARM_ATTRIBUTES, .offset = arm_attributes_offset, .size = bytes.len, .addralign = 1 });
        std.debug.assert(output.items.len == object_size);
    }

    /// The object `write` encodes, in the form a unit image is built from:
    /// exactly what `UnitImage` reads back from the encoded bytes
    /// (`UnitImage.Object`), with `keep_debug` deciding whether the debug
    /// sections are kept as `UnitImage.BuildOptions` does. Section contents
    /// stay borrowed from the writer.
    pub fn imageObject(self: *const Self, arena: Allocator, keep_debug: bool) (Allocator.Error || UnitImage.BuildError)!UnitImage.Object {
        // `UnitImage` reads ELF64 objects only, and rejects an ELF32 one.
        if (self.arch == .arm32) return error.InvalidObject;
        const pointer_bearing = self.rodata_relocs.items.len != 0;
        const debug_class = struct {
            fn of(keep: bool, class: UnitImage.SectionClass) UnitImage.SectionClass {
                return if (keep) class else .skip;
            }
        }.of;
        const skipped: UnitImage.Section = .{ .class = .skip, .bytes = &.{}, .size = 0, .addralign = 1 };
        const sections = try arena.alloc(UnitImage.Section, 14);
        sections[0] = skipped;
        sections[1] = .{ .class = .text, .bytes = self.text, .size = self.text.len, .addralign = 16 };
        sections[2] = .{ .class = if (pointer_bearing) .data else .rodata, .bytes = &.{}, .pieced = self.rodata, .size = self.rodata.len, .addralign = 16 };
        for (sections[3..8]) |*section| section.* = skipped;
        sections[8] = .{ .class = debug_class(keep_debug, .debug_line), .bytes = self.debug.line, .size = self.debug.line.len, .addralign = 1 };
        sections[9] = .{ .class = debug_class(keep_debug, .debug_abbrev), .bytes = self.debug.abbrev, .size = self.debug.abbrev.len, .addralign = 1 };
        sections[10] = .{ .class = debug_class(keep_debug, .debug_info), .bytes = self.debug.info, .size = self.debug.info.len, .addralign = 1 };
        sections[11] = skipped;
        sections[12] = skipped;
        sections[13] = .{ .class = .bss, .bytes = &.{}, .size = self.zero_fill_size, .addralign = 16 };

        // The null symbol, the section symbols DWARF relocations name, then
        // the writer's symbols in order.
        const writer_symbol_offset: u32 = 4;
        const symbols = try arena.alloc(UnitImage.ObjectSymbol, self.symbols.items.len + writer_symbol_offset);
        symbols[0] = .{ .name = "", .value = 0, .size = 0, .section = null, .bind = .local, .kind = .notype, .hidden = false, .skip = true };
        for (symbols[1..writer_symbol_offset], [_]u32{ 1, 8, 9 }) |*symbol, section| {
            symbol.* = .{ .name = "", .value = 0, .size = 0, .section = section, .bind = .local, .kind = .section, .hidden = false, .skip = false };
        }
        for (self.symbols.items, symbols[writer_symbol_offset..]) |sym, *symbol| symbol.* = .{
            .name = sym.name,
            .value = sym.offset,
            .size = sym.size,
            .section = switch (sym.section) {
                .text => 1,
                .rodata => 2,
                .bss => 13,
                .data, .undef => null,
            },
            .bind = if (sym.is_global) .global else .local,
            .kind = if (sym.is_function) .func else if (sym.section == .rodata or sym.section == .bss) .object else .notype,
            .hidden = sym.is_hidden,
            .skip = false,
        };

        const relocs = try arena.alloc(UnitImage.Reloc, self.text_relocs.items.len + self.rodata_relocs.items.len + self.debug.line_relocs.len + self.debug.info_relocs.len);
        var at: usize = 0;
        for ([_]struct { []const TextReloc, u32 }{ .{ self.text_relocs.items, 1 }, .{ self.rodata_relocs.items, 2 } }) |group| {
            for (group[0]) |rel| {
                relocs[at] = .{
                    .section = group[1],
                    .offset = rel.offset,
                    .kind = switch (self.arch) {
                        .x86_64 => try UnitImage.classifyX86_64Reloc(rel.reloc_type),
                        .aarch64 => try UnitImage.classifyAarch64Reloc(rel.reloc_type),
                        .arm32 => unreachable, // returned above
                    },
                    .symbol = rel.symbol_idx + writer_symbol_offset,
                    .addend = rel.addend,
                };
                at += 1;
            }
        }
        for ([_]struct { []const DebugReloc, u32 }{ .{ self.debug.line_relocs, 8 }, .{ self.debug.info_relocs, 10 } }) |group| {
            for (group[0]) |rel| {
                relocs[at] = .{
                    .section = group[1],
                    .offset = rel.section_offset,
                    .kind = switch (rel.width) {
                        .four => .abs32,
                        .eight => .abs64,
                    },
                    .symbol = switch (rel.target) {
                        .text => 1,
                        .debug_line => 2,
                        .debug_abbrev => 3,
                    },
                    .addend = @intCast(rel.addend),
                };
                at += 1;
            }
        }
        return .{ .sections = sections, .symbols = symbols, .relocs = relocs, .text_section = 1, .static_data_section = 2, .x86_64 = self.arch == .x86_64 };
    }

    /// Store each relocation's addend in the field it relocates, inside
    /// the section copy that starts at `section_offset` in `output`.
    fn storeAddends(self: *const Self, output: *std.ArrayList(u8), section_offset: u64, relocs: []const TextReloc) void {
        for (relocs) |rel| storeAddend(self.arch, output.items[@intCast(section_offset + rel.offset)..], rel.reloc_type, rel.addend);
    }

    fn appendShdr(comptime C: type, output: *std.ArrayList(u8), header: SectionHeader) void {
        const shdr = C.shdr(header);
        output.appendSliceAssumeCapacity(std.mem.asBytes(&shdr));
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
    comptime C: type,
    arch: Architecture,
    relocs: []const DebugReloc,
    output: *std.ArrayList(u8),
) void {
    for (relocs) |rel| {
        const target_symbol_index: u32 = switch (rel.target) {
            .text => 1,
            .debug_line => 2,
            .debug_abbrev => 3,
        };
        const elf_reloc = C.reloc(rel.section_offset, target_symbol_index, debugRelocType(arch, rel.width), @intCast(rel.addend));
        output.appendSliceAssumeCapacity(std.mem.asBytes(&elf_reloc));
    }
}

/// The relocation type of a DWARF address or offset field of `width` bytes.
fn debugRelocType(arch: Architecture, width: object.DebugRelocWidth) u32 {
    return switch (arch) {
        .x86_64 => switch (width) {
            .four => ELF.R_X86_64_32,
            .eight => ELF.R_X86_64_64,
        },
        .aarch64 => switch (width) {
            .four => ELF.R_AARCH64_ABS32,
            .eight => ELF.R_AARCH64_ABS64,
        },
        .arm32 => switch (width) {
            .four => ELF.R_ARM_ABS32,
            .eight => invariant("ELF invariant violated: eight-byte DWARF field in an arm32 object, whose DWARF has four-byte addresses", .{}),
        },
    };
}

/// Store each DWARF relocation's addend in the field it relocates, inside
/// `section`, the output's copy of the debug section.
fn storeDebugAddends(arch: Architecture, section: []u8, relocs: []const DebugReloc) void {
    for (relocs) |rel| storeAddend(arch, section[rel.section_offset..], debugRelocType(arch, rel.width), @intCast(rel.addend));
}

/// Store a REL relocation's addend in `field`, the bytes it relocates, as
/// AAELF32 defines the addend of each relocation type. The field holds zero
/// until then: the producer states the addend in the relocation only.
fn storeAddend(arch: Architecture, field: []u8, reloc_type: u32, addend: i64) void {
    switch (arch) {
        .x86_64, .aarch64 => invariant("ELF invariant violated: an addend stored in place for {t}, whose RELA records carry it", .{arch}),
        .arm32 => {
            if (reloc_type != ELF.R_ARM_ABS32) invariant("ELF invariant violated: arm32 relocation type {d} has no in-place addend form", .{reloc_type});
            std.debug.assert(std.mem.readInt(u32, field[0..4], .little) == 0);
            std.mem.writeInt(i32, field[0..4], @intCast(addend), .little);
        },
    }
}

/// ARM build attribute tags (the ABI addenda's `Tag_*` numbers).
const ArmTag = struct {
    const File = 1;
    const CPU_arch = 6;
    const CPU_arch_profile = 7;
    const ARM_ISA_use = 8;
    const THUMB_ISA_use = 9;
    const FP_arch = 10;
    const Advanced_SIMD_arch = 12;
    const ABI_PCS_R9_use = 14;
    const ABI_FP_number_model = 23;
    const ABI_align_needed = 24;
    const ABI_align_preserved = 25;
    const ABI_VFP_args = 28;
};

/// The attributes every arm32 object states, as tag and value pairs. They
/// name part 4's CPU floor, which is Zig's arm baseline (see the floor check
/// in `arm32/Emit.zig`), and the hard-float calling convention, so a linker
/// rejects a soft-float partner. Each value is what `zig cc` writes for that
/// baseline. Every value fits in one ULEB128 byte.
const arm_attribute_values = [_][2]u8{
    .{ ArmTag.CPU_arch, 10 }, // ARMv7
    .{ ArmTag.CPU_arch_profile, 'A' }, // application
    .{ ArmTag.ARM_ISA_use, 1 }, // A32 permitted
    .{ ArmTag.THUMB_ISA_use, 2 }, // Thumb-2 permitted (the target allows it; the code has none)
    .{ ArmTag.FP_arch, 3 }, // VFPv3 with 32 double registers
    .{ ArmTag.Advanced_SIMD_arch, 1 }, // NEONv1
    .{ ArmTag.ABI_PCS_R9_use, 0 }, // r9 is an ordinary register
    .{ ArmTag.ABI_FP_number_model, 3 }, // IEEE 754
    .{ ArmTag.ABI_align_needed, 1 }, // 8-byte alignment
    .{ ArmTag.ABI_align_preserved, 1 }, // 8-byte stack alignment, leaf functions excepted
    .{ ArmTag.ABI_VFP_args, 1 }, // arguments in VFP registers (hard-float)
};

/// The `.ARM.attributes` section of every arm32 object: format version 'A',
/// one "aeabi" subsection holding one file-scope attribute set.
const arm_attributes: []const u8 = blk: {
    const vendor = "aeabi";
    const attribute_bytes = 2 * arm_attribute_values.len;
    const file_size = 1 + 4 + attribute_bytes; // Tag_File, its size, the pairs
    const subsection_size = 4 + vendor.len + 1 + file_size;
    var bytes: [1 + subsection_size]u8 = undefined;
    bytes[0] = 'A';
    std.mem.writeInt(u32, bytes[1..5], subsection_size, .little);
    @memcpy(bytes[5..][0..vendor.len], vendor);
    bytes[5 + vendor.len] = 0;
    const file_at = 5 + vendor.len + 1;
    bytes[file_at] = ArmTag.File;
    std.mem.writeInt(u32, bytes[file_at + 1 ..][0..4], file_size, .little);
    for (arm_attribute_values, 0..) |pair, i| {
        std.debug.assert(pair[0] < 0x80 and pair[1] < 0x80);
        bytes[file_at + 5 + 2 * i ..][0..2].* = pair;
    }
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
    try writer.addTextRelocation(1, ext_idx, .x86_call_rel32);

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
    try output.ensureTotalCapacityPrecise(std.testing.allocator, relocs.len * @sizeOf(Elf64.Reloc));
    appendDebugRelocations(Elf64, .x86_64, &relocs, &output);

    try std.testing.expectEqual(@as(usize, 3 * @sizeOf(Elf64.Reloc)), output.items.len);
    const abbrev = std.mem.bytesToValue(Elf64.Reloc, output.items[0..@sizeOf(Elf64.Reloc)]);
    const text = std.mem.bytesToValue(Elf64.Reloc, output.items[@sizeOf(Elf64.Reloc)..][0..@sizeOf(Elf64.Reloc)]);
    const line = std.mem.bytesToValue(Elf64.Reloc, output.items[2 * @sizeOf(Elf64.Reloc) ..][0..@sizeOf(Elf64.Reloc)]);

    try std.testing.expectEqual(@as(u64, 6), abbrev.r_offset);
    try std.testing.expectEqual((@as(u64, 3) << 32) | ELF.R_X86_64_32, abbrev.r_info);
    try std.testing.expectEqual(@as(u64, 24), text.r_offset);
    try std.testing.expectEqual((@as(u64, 1) << 32) | ELF.R_X86_64_64, text.r_info);
    try std.testing.expectEqual(@as(i64, 32), text.r_addend);
    try std.testing.expectEqual(@as(u64, 40), line.r_offset);
    try std.testing.expectEqual((@as(u64, 2) << 32) | ELF.R_X86_64_32, line.r_info);
}

/// Write an object for `arch` holding a local and a global function, an
/// external symbol, a call to it (64-bit architectures; arm32 has no call
/// relocation yet), a pointer in read-only data, zero-fill data and DWARF
/// for two procedures, the second starting at 16.
fn writeSampleObject(arch: Architecture, output: *std.ArrayList(u8)) Allocator.Error!void {
    const gpa = std.testing.allocator;
    const Dwarf = @import("../Dwarf.zig");
    const base = @import("base");

    var writer = try ElfWriter.init(gpa, arch, .none);
    defer writer.deinit();
    var code: [32]u8 = @splat(0);
    if (arch == .x86_64) code[0] = 0xE8;
    if (arch == .aarch64) std.mem.writeInt(u32, code[0..4], 0x94000000, .little);
    writer.setCode(&code);
    const rodata: [16]u8 = @splat(0);
    const rodata_piece = [1]UnitImage.SectionPiece{.{ .offset = 0, .bytes = &rodata }};
    writer.setRodata(.whole(&rodata_piece));
    writer.setZeroFill(64);

    const local = try writer.addSymbol(.{ .name = "local_fn", .section = .text, .offset = 16, .size = 16, .is_global = false, .is_function = true });
    _ = try writer.addSymbol(.{ .name = "global_fn", .section = .text, .offset = 0, .size = 16, .is_global = true, .is_function = true });
    const external = try writer.addExternalSymbol("puts");
    switch (arch) {
        .x86_64 => try writer.addTextRelocation(1, external, .x86_call_rel32),
        .aarch64 => try writer.addTextRelocation(0, external, .aarch64_call26),
        .arm32 => {},
    }
    try writer.addRodataRelocation(8, local, 4);

    const files = [_][]const u8{"main"};
    const entries = [_]@import("../LirCodeGen.zig").LineEntry{
        .{ .offset = 0, .loc = .{ .file = .some(0), .line = 3, .column = 1 }, .region = base.Region.zero() },
    };
    const procs = [_]Dwarf.ProcEntry{
        .{ .name = "global_fn", .code_start = 0, .code_size = 16, .loc = .{ .file = .some(0), .line = 3, .column = 1 } },
        .{ .name = "local_fn", .code_start = 16, .code_size = 16, .loc = .{ .file = .some(0), .line = 4, .column = 1 } },
    };
    const width: Dwarf.AddressWidth = if (arch == .arm32) .four else .eight;
    var dwarf = try Dwarf.build(gpa, "roc test", width, &files, &entries, &procs, code.len);
    defer dwarf.deinit(gpa);
    writer.debug = .{
        .line = dwarf.debug_line,
        .abbrev = dwarf.debug_abbrev,
        .info = dwarf.debug_info,
        .line_relocs = dwarf.line_relocs,
        .info_relocs = dwarf.info_relocs,
    };
    try writer.write(output);
}

/// The sample object read back through `std.elf`'s records for its class.
fn SampleReader(comptime arch: Architecture) type {
    return struct {
        const E = if (arch == .arm32) std.elf.Elf32 else std.elf.Elf64;
        const Reloc = if (arch == .arm32) E.Rel else E.Rela;

        bytes: []const u8,
        ehdr: E.Ehdr,

        fn init(bytes: []const u8) @This() {
            return .{ .bytes = bytes, .ehdr = std.mem.bytesToValue(E.Ehdr, bytes[0..@sizeOf(E.Ehdr)]) };
        }
        fn shdr(self: @This(), index: usize) E.Shdr {
            const at: usize = @intCast(self.ehdr.shoff + index * @sizeOf(E.Shdr));
            return std.mem.bytesToValue(E.Shdr, self.bytes[at..][0..@sizeOf(E.Shdr)]);
        }
        fn contents(self: @This(), index: usize) []const u8 {
            const h = self.shdr(index);
            return self.bytes[@intCast(h.offset)..][0..@intCast(h.size)];
        }
        fn name(self: @This(), index: usize) []const u8 {
            const names = self.contents(self.ehdr.shstrndx);
            return std.mem.sliceTo(names[self.shdr(index).name..], 0);
        }
        fn sym(self: @This(), index: usize) E.Sym {
            return std.mem.bytesToValue(E.Sym, self.contents(5)[index * @sizeOf(E.Sym) ..][0..@sizeOf(E.Sym)]);
        }
        fn symName(self: @This(), index: usize) []const u8 {
            return std.mem.sliceTo(self.contents(6)[self.sym(index).name..], 0);
        }
        fn reloc(self: @This(), section: usize, index: usize) Reloc {
            return std.mem.bytesToValue(Reloc, self.contents(section)[index * @sizeOf(Reloc) ..][0..@sizeOf(Reloc)]);
        }
    };
}

/// Check the layout every architecture shares: header, section names,
/// types, bounds and alignment, relocation sections and symbol order.
fn expectSampleLayout(comptime arch: Architecture) (Allocator.Error || error{ TestExpectedEqual, TestUnexpectedResult })!void {
    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(std.testing.allocator);
    try writeSampleObject(arch, &output);
    const R = SampleReader(arch);
    const r = R.init(output.items);

    const is32 = arch == .arm32;
    try std.testing.expectEqualSlices(u8, "\x7fELF", &r.ehdr.ident.magic);
    try std.testing.expectEqual(if (is32) std.elf.CLASS.@"32" else std.elf.CLASS.@"64", r.ehdr.ident.class);
    try std.testing.expectEqual(std.elf.ET.REL, r.ehdr.type);
    try std.testing.expectEqual(switch (arch) {
        .x86_64 => std.elf.EM.X86_64,
        .aarch64 => std.elf.EM.AARCH64,
        .arm32 => std.elf.EM.ARM,
    }, r.ehdr.machine);
    try std.testing.expectEqual(@as(u16, @sizeOf(R.E.Ehdr)), r.ehdr.ehsize);
    try std.testing.expectEqual(@as(u16, @sizeOf(R.E.Shdr)), r.ehdr.shentsize);
    try std.testing.expectEqual(@as(usize, @intCast(r.ehdr.shoff + r.ehdr.shnum * @sizeOf(R.E.Shdr))), output.items.len);

    const rel = if (is32) ".rel" else ".rela";
    const names = [_][]const u8{ "", ".text", ".data.rel.ro", rel ++ ".text", rel ++ ".data.rel.ro", ".symtab", ".strtab", ".shstrtab", ".debug_line", ".debug_abbrev", ".debug_info", rel ++ ".debug_line", rel ++ ".debug_info", ".bss", ".ARM.attributes" };
    const count: usize = if (is32) 15 else 14;
    try std.testing.expectEqual(count, r.ehdr.shnum);
    for (names[0..count], 0..) |expected, index| {
        try std.testing.expectEqualStrings(expected, r.name(index));
        const h = r.shdr(index);
        if (index == 0) continue;
        try std.testing.expect(h.addralign != 0);
        // `.bss` stores no bytes, so its offset has no alignment or extent.
        if (h.type == .NOBITS) continue;
        try std.testing.expectEqual(0, h.offset % h.addralign);
        try std.testing.expect(h.offset + h.size <= output.items.len);
    }

    // Each relocation section names the symbol table and its target, and
    // holds whole records of its class.
    for ([_][2]u32{ .{ 3, 1 }, .{ 4, 2 }, .{ 11, 8 }, .{ 12, 10 } }) |pair| {
        const h = r.shdr(pair[0]);
        try std.testing.expectEqual(if (is32) std.elf.SHT.REL else std.elf.SHT.RELA, h.type);
        try std.testing.expectEqual(@as(u32, 5), h.link);
        try std.testing.expectEqual(pair[1], h.info);
        try std.testing.expectEqual(@sizeOf(R.Reloc), h.entsize);
        try std.testing.expectEqual(0, h.size % h.entsize);
    }
    const text_relocs: usize = if (is32) 0 else 1;
    try std.testing.expectEqual(text_relocs * @sizeOf(R.Reloc), r.shdr(3).size);
    try std.testing.expectEqual(@sizeOf(R.Reloc), r.shdr(4).size);

    // Locals come first, and sh_info is the first global's index.
    const symtab = r.shdr(5);
    try std.testing.expectEqual(std.elf.SHT.SYMTAB, symtab.type);
    try std.testing.expectEqual(@sizeOf(R.E.Sym), symtab.entsize);
    const symbols: usize = @intCast(symtab.size / symtab.entsize);
    for (0..symbols) |index| {
        const bind = r.sym(index).info.bind;
        try std.testing.expectEqual(if (index < symtab.info) std.elf.STB.LOCAL else std.elf.STB.GLOBAL, bind);
    }
    const first_writer: usize = if (is32) 5 else 4;
    try std.testing.expectEqual(first_writer + 3, symbols);
    try std.testing.expectEqual(first_writer + 1, symtab.info);
    try std.testing.expectEqualStrings("local_fn", r.symName(first_writer));
    try std.testing.expectEqualStrings("global_fn", r.symName(first_writer + 1));
    try std.testing.expectEqualStrings("puts", r.symName(first_writer + 2));
    try std.testing.expectEqual(@as(u64, 16), r.sym(first_writer).value);

    // The read-only data pointer names `local_fn` with addend 4: in the
    // record for RELA, in the pointer itself for REL.
    const pointer = r.reloc(4, 0);
    try std.testing.expectEqual(@as(u64, 8), pointer.offset);
    try std.testing.expectEqual(first_writer, pointer.info.sym);
    if (is32) {
        try std.testing.expectEqual(@as(u32, 4), std.mem.readInt(u32, r.contents(2)[8..12], .little));
    } else {
        try std.testing.expectEqual(@as(i64, 4), pointer.addend);
    }
}

test "ELF objects read back with the layout of their class" {
    try expectSampleLayout(.x86_64);
    try expectSampleLayout(.aarch64);
    try expectSampleLayout(.arm32);
}

test "arm32 object is EABI5 hard-float, marks .text as A32 and states its attributes" {
    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(std.testing.allocator);
    try writeSampleObject(.arm32, &output);
    const r = SampleReader(.arm32).init(output.items);

    try std.testing.expectEqual(@as(u32, 0x05000400), r.ehdr.flags.int);
    try std.testing.expectEqual(@as(u8, 2), r.reloc(4, 0).info.type); // R_ARM_ABS32

    const mapping = r.sym(4);
    try std.testing.expectEqualStrings("$a", r.symName(4));
    try std.testing.expectEqual(std.elf.STT.NOTYPE, mapping.info.type);
    try std.testing.expectEqual(std.elf.STB.LOCAL, mapping.info.bind);
    try std.testing.expectEqual(@as(u16, 1), mapping.shndx);
    try std.testing.expectEqual(@as(u32, 0), mapping.value);

    const attributes = r.shdr(14);
    try std.testing.expectEqual(@as(u32, 0x70000003), @backingInt(attributes.type)); // SHT_ARM_ATTRIBUTES
    try std.testing.expectEqualSlices(u8, arm_attributes, r.contents(14));
}

test "arm32 DWARF fields hold their addends, since REL records have none" {
    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(std.testing.allocator);
    try writeSampleObject(.arm32, &output);
    const r = SampleReader(.arm32).init(output.items);

    // .debug_info's relocations: the abbrev offset, the unit's low_pc, the
    // line table offset, then each subprogram's low_pc.
    const info = r.contents(10);
    const relocs: usize = @intCast(r.shdr(12).size / @sizeOf(std.elf.Elf32.Rel));
    try std.testing.expectEqual(@as(usize, 5), relocs);
    for (0..relocs) |index| {
        const rel = r.reloc(12, index);
        try std.testing.expectEqual(@as(u8, 2), rel.info.type); // R_ARM_ABS32
    }
    const second_low_pc = r.reloc(12, 4);
    try std.testing.expectEqual(@as(u24, 1), second_low_pc.info.sym); // .text's section symbol
    try std.testing.expectEqual(@as(u32, 16), std.mem.readInt(u32, info[second_low_pc.offset..][0..4], .little));
    const first_low_pc = r.reloc(12, 3);
    try std.testing.expectEqual(@as(u32, 0), std.mem.readInt(u32, info[first_low_pc.offset..][0..4], .little));
}

test "arm32 attributes match what zig cc writes for the arm baseline" {
    // `zig cc -target arm-linux-musleabihf -marm -c` (Zig 0.17.1) writes
    // these values for the tags we state, among the 20 it writes.
    const zig_cc = [_][2]u8{
        .{ 6, 10 }, .{ 7, 'A' }, .{ 8, 1 },  .{ 9, 2 },  .{ 10, 3 }, .{ 12, 1 },
        .{ 14, 0 }, .{ 23, 3 },  .{ 24, 1 }, .{ 25, 1 }, .{ 28, 1 },
    };
    try std.testing.expectEqual(zig_cc.len, arm_attribute_values.len);
    for (zig_cc, arm_attribute_values) |expected, actual| try std.testing.expectEqual(expected, actual);

    // Format version, subsection length, vendor, file-scope tag and length.
    try std.testing.expectEqual(@as(u8, 'A'), arm_attributes[0]);
    try std.testing.expectEqual(arm_attributes.len - 1, std.mem.readInt(u32, arm_attributes[1..5], .little));
    try std.testing.expectEqualStrings("aeabi\x00", arm_attributes[5..11]);
    try std.testing.expectEqual(@as(u8, 1), arm_attributes[11]);
    try std.testing.expectEqual(arm_attributes.len - 11, std.mem.readInt(u32, arm_attributes[12..16], .little));
}
