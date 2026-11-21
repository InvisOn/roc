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
    const CLASS_64 = 2;
    const DATA_LSB = 1; // Little endian
    const VERSION_CURRENT = 1;

    // ELF type
    const ET_REL = 1; // Relocatable file

    // Machine types
    const EM_X86_64 = 62;
    const EM_AARCH64 = 183;

    // Section header types
    const SHT_PROGBITS = 1;
    const SHT_SYMTAB = 2;
    const SHT_STRTAB = 3;
    const SHT_RELA = 4;
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

/// Target architecture for ELF generation
pub const Architecture = enum {
    x86_64,
    aarch64,

    fn machine(self: Architecture) u16 {
        return switch (self) {
            .x86_64 => ELF.EM_X86_64,
            .aarch64 => ELF.EM_AARCH64,
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
                },
                .addend = @as(i64, 0),
            },
            .rel32 => .{
                .kind = switch (self.arch) {
                    .x86_64 => ELF.R_X86_64_PC32,
                    .aarch64 => invariant("ELF invariant violated: rel32 data relocation in aarch64 code, which emits page21 and pageoff12", .{}),
                },
                .addend = @as(i64, -4),
            },
            .page21 => .{
                .kind = switch (self.arch) {
                    .x86_64 => invariant("ELF invariant violated: page21 data relocation in x86_64 code, which emits rel32", .{}),
                    .aarch64 => ELF.R_AARCH64_ADR_PREL_PG_HI21,
                },
                .addend = @as(i64, 0),
            },
            .pageoff12 => .{
                .kind = switch (self.arch) {
                    .x86_64 => invariant("ELF invariant violated: pageoff12 data relocation in x86_64 code, which emits rel32", .{}),
                    .aarch64 => ELF.R_AARCH64_ADD_ABS_LO12_NC,
                },
                .addend = @as(i64, 0),
            },
            // The field's own bytes hold the addend.
            .abs32_field => .{
                .kind = switch (self.arch) {
                    .x86_64 => ELF.R_X86_64_32,
                    .aarch64 => invariant("ELF invariant violated: abs32_field data relocation in aarch64 code, which only an x86_64 test unit emits", .{}),
                },
                .addend = std.mem.readInt(u32, self.text[@intCast(offset)..][0..4], .little),
            },
            .abs64_field => .{
                .kind = switch (self.arch) {
                    .x86_64 => invariant("ELF invariant violated: abs64_field data relocation in x86_64 code, which only an arm64 test unit emits", .{}),
                    .aarch64 => ELF.R_AARCH64_ABS64,
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
        const NUM_SECTIONS = 14;

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

        const debug_target_sections = [_]u16{ SHIDX_TEXT, SHIDX_DEBUG_LINE, SHIDX_DEBUG_ABBREV };
        const WRITER_SYMBOL_OFFSET: u32 = 1 + debug_target_sections.len;
        var num_locals: u32 = WRITER_SYMBOL_OFFSET;
        const symtab_size = (self.symbols.items.len + WRITER_SYMBOL_OFFSET) * @sizeOf(C.Sym);
        var string_bytes: usize = 1; // The string table starts with a null byte.
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

        const shdr_offset = alignUp(offset, C.table_align);

        std.debug.assert(output.items.len == 0);
        const object_size: usize = @intCast(shdr_offset + NUM_SECTIONS * @sizeOf(C.Shdr));
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
            .e_flags = 0,
            .e_ehsize = @sizeOf(C.Ehdr),
            .e_phentsize = 0,
            .e_phnum = 0,
            .e_shentsize = @sizeOf(C.Shdr),
            .e_shnum = NUM_SECTIONS,
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

        padTo(output, rodata_offset);
        self.rodata.appendAssumeCapacity(output);

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
        padTo(output, reloc_debug_line_offset);
        appendDebugRelocations(C, self.arch, self.debug.line_relocs, output);
        padTo(output, reloc_debug_info_offset);
        appendDebugRelocations(C, self.arch, self.debug.info_relocs, output);

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
        std.debug.assert(output.items.len == object_size);
    }

    /// The object `write` encodes, in the form a unit image is built from:
    /// exactly what `UnitImage` reads back from the encoded bytes
    /// (`UnitImage.Object`), with `keep_debug` deciding whether the debug
    /// sections are kept as `UnitImage.BuildOptions` does. Section contents
    /// stay borrowed from the writer.
    pub fn imageObject(self: *const Self, arena: Allocator, keep_debug: bool) (Allocator.Error || UnitImage.BuildError)!UnitImage.Object {
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
        const reloc_type: u32 = switch (arch) {
            .x86_64 => switch (rel.width) {
                .four => ELF.R_X86_64_32,
                .eight => ELF.R_X86_64_64,
            },
            .aarch64 => switch (rel.width) {
                .four => ELF.R_AARCH64_ABS32,
                .eight => ELF.R_AARCH64_ABS64,
            },
        };
        const elf_reloc = C.reloc(rel.section_offset, target_symbol_index, reloc_type, @intCast(rel.addend));
        output.appendSliceAssumeCapacity(std.mem.asBytes(&elf_reloc));
    }
}

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
