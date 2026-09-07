const std = @import("std");
const module_sema = @import("module_semantic_graph.zig");
const syn = @import("../3_syntax/syntax_tree.zig");
const global_lexical = @import("global_lexical.zig");

pub const GlobalDeclId = enum(u32) { _ };
pub const GlobalTypeRefId = enum(u32) { _ };

pub const FileOffsets = struct {
    declaration_base: u32 = 0,
    declaration_count: u32 = 0,
    type_reference_base: u32 = 0,
    type_reference_count: u32 = 0,
    import_reference_base: u32 = 0,
    import_reference_count: u32 = 0,
};

pub const ModuleOffsets = struct { declaration_base: u32, declaration_count: u32, string_base: u32 };

pub const Declaration = struct {
    kind: module_sema.DeclarationKind,
    name: module_sema.StringRange,
    source_offset: u32,
    file_index: u32,
    syntax_node: syn.NodeIndex,
};

pub const TypeReference = struct {
    name: module_sema.StringRange,
    qualifier: ?module_sema.StringRange,
    source_offset: u32,
    syntax_node: syn.NodeIndex,
    resolved_declaration: ?GlobalDeclId,
};

/// Provisional globalization storage. Its input boundary is a module semantic
/// graph; file indices survive only as source/syntax provenance for consumers
/// that have not yet moved off the legacy pointer-heavy graph.
pub const GlobalSemanticGraphBuilder = struct {
    declarations: std.ArrayList(Declaration) = .empty,
    strings: std.ArrayList(u8) = .empty,
    module_offsets: std.ArrayList(ModuleOffsets) = .empty,
    file_offsets: std.ArrayList(FileOffsets) = .empty,
    type_references: std.ArrayList(TypeReference) = .empty,
    import_references: std.ArrayList(module_sema.ImportReference) = .empty,
    lexical: global_lexical.LexicalTables = .{},

    pub fn deinit(self: *GlobalSemanticGraphBuilder, allocator: std.mem.Allocator) void {
        self.declarations.deinit(allocator);
        self.strings.deinit(allocator);
        self.module_offsets.deinit(allocator);
        self.file_offsets.deinit(allocator);
        self.type_references.deinit(allocator);
        self.import_references.deinit(allocator);
        self.lexical.deinit(allocator);
        self.* = .{};
    }

    pub fn globalDeclId(self: *const GlobalSemanticGraphBuilder, module_index: usize, local_id: module_sema.ModuleDeclId) GlobalDeclId {
        const offsets = self.module_offsets.items[module_index];
        std.debug.assert(@intFromEnum(local_id) < offsets.declaration_count);
        return @enumFromInt(offsets.declaration_base + @intFromEnum(local_id));
    }

    pub fn declaration(self: *const GlobalSemanticGraphBuilder, id: GlobalDeclId) Declaration {
        return self.declarations.items[@intFromEnum(id)];
    }

    pub fn text(self: *const GlobalSemanticGraphBuilder, range: module_sema.StringRange) []const u8 {
        return self.strings.items[range.start..][0..range.len];
    }

    pub fn storageBytes(self: *const GlobalSemanticGraphBuilder) usize {
        return self.declarations.items.len * @sizeOf(Declaration) + self.strings.items.len +
            self.module_offsets.items.len * @sizeOf(ModuleOffsets) + self.file_offsets.items.len * @sizeOf(FileOffsets) +
            self.type_references.items.len * @sizeOf(TypeReference) +
            self.import_references.items.len * @sizeOf(module_sema.ImportReference) + self.lexical.storageBytes();
    }

    pub fn globalTypeRefId(self: *const GlobalSemanticGraphBuilder, file_index: usize, local_id: module_sema.ModuleTypeRefId) GlobalTypeRefId {
        const offsets = self.file_offsets.items[file_index];
        std.debug.assert(@intFromEnum(local_id) < offsets.type_reference_count);
        return @enumFromInt(offsets.type_reference_base + @intFromEnum(local_id));
    }

    pub fn findTypeReference(self: *const GlobalSemanticGraphBuilder, file_index: usize, node: syn.NodeIndex) ?TypeReference {
        const offsets = self.file_offsets.items[file_index];
        return findReference(TypeReference, self.type_references.items[offsets.type_reference_base..][0..offsets.type_reference_count], node);
    }

    pub fn findImportReference(self: *const GlobalSemanticGraphBuilder, file_index: usize, node: syn.NodeIndex) ?module_sema.ImportReference {
        const offsets = self.file_offsets.items[file_index];
        return findReference(module_sema.ImportReference, self.import_references.items[offsets.import_reference_base..][0..offsets.import_reference_count], node);
    }

    pub fn findDeclaration(self: *const GlobalSemanticGraphBuilder, file_index: usize, node: syn.NodeIndex) ?GlobalDeclId {
        const offsets = self.file_offsets.items[file_index];
        for (self.declarations.items[offsets.declaration_base..][0..offsets.declaration_count], offsets.declaration_base..) |candidate, index| {
            if (candidate.syntax_node == node) return @enumFromInt(@as(u32, @intCast(index)));
        }
        return null;
    }

    fn findReference(comptime T: type, references: []const T, node: syn.NodeIndex) ?T {
        var start: usize = 0;
        var end = references.len;
        while (start < end) {
            const middle = start + (end - start) / 2;
            const reference = references[middle];
            if (@intFromEnum(reference.syntax_node) < @intFromEnum(node)) start = middle + 1 else if (@intFromEnum(reference.syntax_node) > @intFromEnum(node)) end = middle else return reference;
        }
        return null;
    }
};

pub fn mergeModuleGraphs(allocator: std.mem.Allocator, modules: []const module_sema.ModuleSemanticGraph, file_count: usize) !GlobalSemanticGraphBuilder {
    const maximum = std.math.maxInt(u32);
    if (modules.len > maximum or file_count > maximum) return error.GlobalSemanticGraphBuilderTooLarge;
    var merged: GlobalSemanticGraphBuilder = .{};
    errdefer merged.deinit(allocator);
    try merged.module_offsets.ensureTotalCapacity(allocator, modules.len);
    try merged.file_offsets.resize(allocator, file_count);
    @memset(merged.file_offsets.items, .{});

    for (modules) |module| {
        if (module.declarations.items.len > maximum - merged.declarations.items.len or module.strings.items.len > maximum - merged.strings.items.len)
            return error.GlobalSemanticGraphBuilderTooLarge;
        const string_base: u32 = @intCast(merged.strings.items.len);
        const declaration_base: u32 = @intCast(merged.declarations.items.len);
        merged.module_offsets.appendAssumeCapacity(.{ .declaration_base = declaration_base, .declaration_count = @intCast(module.declarations.items.len), .string_base = string_base });
        try merged.strings.appendSlice(allocator, module.strings.items);
        try merged.declarations.ensureUnusedCapacity(allocator, module.declarations.items.len);
        for (module.declarations.items) |declaration| merged.declarations.appendAssumeCapacity(.{
            .kind = declaration.kind,
            .name = try relocateName(module.strings.items, declaration.name, string_base),
            .source_offset = declaration.source_offset,
            .file_index = module.file_offsets.items[declaration.module_file_index].source_file_index,
            .syntax_node = declaration.syntax_node,
        });

        for (module.file_offsets.items) |file| {
            if (file.source_file_index >= file_count) return error.InvalidModuleFileIndex;
            const type_base: u32 = @intCast(merged.type_references.items.len);
            const import_base: u32 = @intCast(merged.import_references.items.len);
            for (module.type_references.items[file.type_reference_base..][0..file.type_reference_count]) |reference| try merged.type_references.append(allocator, .{
                .name = try relocateName(module.strings.items, reference.name, string_base),
                .qualifier = if (reference.qualifier) |name| try relocateName(module.strings.items, name, string_base) else null,
                .source_offset = reference.source_offset,
                .syntax_node = reference.syntax_node,
                .resolved_declaration = if (reference.resolved_declaration) |id| @enumFromInt(declaration_base + @intFromEnum(id)) else null,
            });
            for (module.import_references.items[file.import_reference_base..][0..file.import_reference_count]) |reference| try merged.import_references.append(allocator, .{
                .path = try relocateName(module.strings.items, reference.path, string_base),
                .source_offset = reference.source_offset,
                .syntax_node = reference.syntax_node,
            });
            merged.file_offsets.items[file.source_file_index] = .{
                .declaration_base = declaration_base + file.declaration_base,
                .declaration_count = file.declaration_count,
                .type_reference_base = type_base,
                .type_reference_count = file.type_reference_count,
                .import_reference_base = import_base,
                .import_reference_count = file.import_reference_count,
            };
        }
        try merged.lexical.appendModule(allocator, module.strings.items, &module.lexical, module.file_offsets.items, string_base);
    }
    return merged;
}

fn relocateName(strings: []const u8, name: module_sema.StringRange, base: u32) !module_sema.StringRange {
    if (name.start > strings.len or name.len > strings.len - name.start) return error.InvalidModuleStringRange;
    return .{ .start = base + name.start, .len = name.len };
}
