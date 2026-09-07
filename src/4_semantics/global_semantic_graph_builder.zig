const std = @import("std");
const module_sema = @import("module_semantic_graph.zig");
const syn = @import("../3_syntax/syntax_tree.zig");
const source_db = @import("../1_base/source_db.zig");
const global_lexical = @import("global_lexical.zig");

pub const GlobalDeclId = enum(u32) { _ };
pub const GlobalTypeRefId = enum(u32) { _ };
pub const GlobalTypeId = enum(u32) { _ };
pub const GlobalFunctionId = enum(u32) { _ };

pub const FileOffsets = struct {
    declaration_base: u32 = 0,
    declaration_count: u32 = 0,
    type_reference_base: u32 = 0,
    type_reference_count: u32 = 0,
    import_reference_base: u32 = 0,
    import_reference_count: u32 = 0,
};

pub const ModuleOffsets = struct { declaration_base: u32, declaration_count: u32, string_base: u32, type_base: u32, function_base: u32, field_base: u32, structural_field_base: u32, choice_variant_base: u32 };

pub const GlobalType = union(enum) {
    builtin: module_sema.BuiltinType,
    declared: GlobalDeclId,
    pointer: struct { child: GlobalTypeId, mutability: syn.PointerMutability },
    array: struct { length: u64, element: GlobalTypeId },
    nullable: GlobalTypeId,
    inferred_errable: GlobalTypeId,
    structural: module_sema.FieldRange,
};
pub const Field = struct { name: module_sema.StringRange, ty: GlobalTypeId, source_offset: u32, has_default: bool };
pub const FunctionInterface = struct { declaration: GlobalDeclId, input: module_sema.FieldRange, output: module_sema.FieldRange };
pub const ChoiceVariant = struct { name: module_sema.StringRange, qualifier: ?module_sema.StringRange, payload_type: ?GlobalTypeId };

pub const Declaration = struct {
    kind: module_sema.DeclarationKind,
    name: module_sema.StringRange,
    source_offset: u32,
    file_index: u32,
    syntax_node: syn.NodeIndex,
    type_id: ?GlobalTypeId,
    function_id: ?GlobalFunctionId,
    struct_fields: ?module_sema.FieldRange,
    choice_variants: ?module_sema.FieldRange,
};

pub const TypeReference = struct {
    name: module_sema.StringRange,
    qualifier: ?module_sema.StringRange,
    source_offset: u32,
    syntax_node: syn.NodeIndex,
    resolution: TypeReferenceResolution,
};

pub const TypeReferenceResolution = union(enum) {
    builtin: module_sema.BuiltinType,
    module: GlobalDeclId,
    external,
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
    types: std.ArrayList(GlobalType) = .empty,
    functions: std.ArrayList(FunctionInterface) = .empty,
    fields: std.ArrayList(Field) = .empty,
    structural_fields: std.ArrayList(Field) = .empty,
    choice_variant_entries: std.ArrayList(ChoiceVariant) = .empty,
    import_references: std.ArrayList(module_sema.ImportReference) = .empty,
    lexical: global_lexical.LexicalTables = .{},

    pub fn deinit(self: *GlobalSemanticGraphBuilder, allocator: std.mem.Allocator) void {
        self.declarations.deinit(allocator);
        self.strings.deinit(allocator);
        self.module_offsets.deinit(allocator);
        self.file_offsets.deinit(allocator);
        self.type_references.deinit(allocator);
        self.types.deinit(allocator);
        self.functions.deinit(allocator);
        self.fields.deinit(allocator);
        self.structural_fields.deinit(allocator);
        self.choice_variant_entries.deinit(allocator);
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
            self.types.items.len * @sizeOf(GlobalType) + self.functions.items.len * @sizeOf(FunctionInterface) +
            (self.fields.items.len + self.structural_fields.items.len) * @sizeOf(Field) +
            self.choice_variant_entries.items.len * @sizeOf(ChoiceVariant) +
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

pub fn mergeModuleGraphs(allocator: std.mem.Allocator, modules: []const module_sema.ModuleSemanticGraph, sources: *const source_db.SourceDb) !GlobalSemanticGraphBuilder {
    const maximum = std.math.maxInt(u32);
    const file_count = sources.files.len;
    if (modules.len > maximum or file_count > maximum) return error.GlobalSemanticGraphBuilderTooLarge;
    var merged: GlobalSemanticGraphBuilder = .{};
    errdefer merged.deinit(allocator);
    try merged.module_offsets.ensureTotalCapacity(allocator, modules.len);
    try merged.file_offsets.resize(allocator, file_count);
    @memset(merged.file_offsets.items, .{});

    for (modules) |module| {
        var source_file_indices: std.ArrayList(u32) = .empty;
        defer source_file_indices.deinit(allocator);
        try source_file_indices.ensureTotalCapacity(allocator, module.file_offsets.items.len);
        for (module.file_offsets.items) |file| {
            const file_index = findSourceFile(sources, module.module_dir, module.text(file.path)) orelse return error.ModuleSourceFileNotFound;
            source_file_indices.appendAssumeCapacity(@intCast(file_index));
        }
        if (module.declarations.items.len > maximum - merged.declarations.items.len or module.strings.items.len > maximum - merged.strings.items.len)
            return error.GlobalSemanticGraphBuilderTooLarge;
        const string_base: u32 = @intCast(merged.strings.items.len);
        const declaration_base: u32 = @intCast(merged.declarations.items.len);
        const type_base: u32 = @intCast(merged.types.items.len);
        const function_base: u32 = @intCast(merged.functions.items.len);
        const field_base: u32 = @intCast(merged.fields.items.len);
        const structural_field_base: u32 = @intCast(merged.structural_fields.items.len);
        const choice_variant_base: u32 = @intCast(merged.choice_variant_entries.items.len);
        merged.module_offsets.appendAssumeCapacity(.{ .declaration_base = declaration_base, .declaration_count = @intCast(module.declarations.items.len), .string_base = string_base, .type_base = type_base, .function_base = function_base, .field_base = field_base, .structural_field_base = structural_field_base, .choice_variant_base = choice_variant_base });
        try merged.strings.appendSlice(allocator, module.strings.items);
        try merged.declarations.ensureUnusedCapacity(allocator, module.declarations.items.len);
        for (module.declarations.items) |declaration| merged.declarations.appendAssumeCapacity(.{
            .kind = declaration.kind,
            .name = try relocateName(module.strings.items, declaration.name, string_base),
            .source_offset = declaration.source_offset,
            .file_index = source_file_indices.items[declaration.module_file_index],
            .syntax_node = declaration.syntax_node,
            .type_id = if (declaration.type_id) |id| @enumFromInt(type_base + @intFromEnum(id)) else null,
            .function_id = if (declaration.function_id) |id| @enumFromInt(function_base + @intFromEnum(id)) else null,
            .struct_fields = if (declaration.struct_fields) |range| .{ .start = field_base + range.start, .len = range.len } else null,
            .choice_variants = if (declaration.choice_variants) |range| .{ .start = choice_variant_base + range.start, .len = range.len } else null,
        });
        for (module.types.items) |ty| try merged.types.append(allocator, switch (ty) {
            .builtin => |builtin| .{ .builtin = builtin },
            .declared => |id| .{ .declared = @enumFromInt(declaration_base + @intFromEnum(id)) },
            .pointer => |pointer| .{ .pointer = .{ .child = @enumFromInt(type_base + @intFromEnum(pointer.child)), .mutability = pointer.mutability } },
            .array => |array| .{ .array = .{ .length = array.length, .element = @enumFromInt(type_base + @intFromEnum(array.element)) } },
            .nullable => |child| .{ .nullable = @enumFromInt(type_base + @intFromEnum(child)) },
            .inferred_errable => |child| .{ .inferred_errable = @enumFromInt(type_base + @intFromEnum(child)) },
            .structural => |range| .{ .structural = .{ .start = structural_field_base + range.start, .len = range.len } },
        });
        for (module.fields.items) |field| try merged.fields.append(allocator, .{
            .name = try relocateName(module.strings.items, field.name, string_base),
            .ty = @enumFromInt(type_base + @intFromEnum(field.ty)),
            .source_offset = field.source_offset,
            .has_default = field.has_default,
        });
        for (module.structural_fields.items) |field| try merged.structural_fields.append(allocator, .{
            .name = try relocateName(module.strings.items, field.name, string_base),
            .ty = @enumFromInt(type_base + @intFromEnum(field.ty)),
            .source_offset = field.source_offset,
            .has_default = field.has_default,
        });
        for (module.functions.items) |function| try merged.functions.append(allocator, .{
            .declaration = @enumFromInt(declaration_base + @intFromEnum(function.declaration)),
            .input = .{ .start = field_base + function.input.start, .len = function.input.len },
            .output = .{ .start = field_base + function.output.start, .len = function.output.len },
        });
        for (module.choice_variant_entries.items) |variant| try merged.choice_variant_entries.append(allocator, .{
            .name = try relocateName(module.strings.items, variant.name, string_base),
            .qualifier = if (variant.qualifier) |qualifier| try relocateName(module.strings.items, qualifier, string_base) else null,
            .payload_type = if (variant.payload_type) |id| @enumFromInt(type_base + @intFromEnum(id)) else null,
        });

        for (module.file_offsets.items, 0..) |file, module_file_index| {
            const source_file_index = source_file_indices.items[module_file_index];
            const type_reference_base: u32 = @intCast(merged.type_references.items.len);
            const import_base: u32 = @intCast(merged.import_references.items.len);
            for (module.type_references.items[file.type_reference_base..][0..file.type_reference_count]) |reference| try merged.type_references.append(allocator, .{
                .name = try relocateName(module.strings.items, reference.name, string_base),
                .qualifier = if (reference.qualifier) |name| try relocateName(module.strings.items, name, string_base) else null,
                .source_offset = reference.source_offset,
                .syntax_node = reference.syntax_node,
                .resolution = switch (reference.resolution) {
                    .builtin => |builtin| .{ .builtin = builtin },
                    .module => |id| .{ .module = @enumFromInt(declaration_base + @intFromEnum(id)) },
                    .external => .external,
                },
            });
            for (module.import_references.items[file.import_reference_base..][0..file.import_reference_count]) |reference| try merged.import_references.append(allocator, .{
                .path = try relocateName(module.strings.items, reference.path, string_base),
                .source_offset = reference.source_offset,
                .syntax_node = reference.syntax_node,
            });
            merged.file_offsets.items[source_file_index] = .{
                .declaration_base = declaration_base + file.declaration_base,
                .declaration_count = file.declaration_count,
                .type_reference_base = type_reference_base,
                .type_reference_count = file.type_reference_count,
                .import_reference_base = import_base,
                .import_reference_count = file.import_reference_count,
            };
        }
        try merged.lexical.appendModule(allocator, module.strings.items, &module.lexical, source_file_indices.items, string_base);
    }
    return merged;
}

fn findSourceFile(sources: *const source_db.SourceDb, module_dir: []const u8, basename: []const u8) ?usize {
    for (sources.files, 0..) |file, index| {
        if (!std.mem.eql(u8, std.fs.path.dirname(file.path) orelse ".", module_dir)) continue;
        if (std.mem.eql(u8, std.fs.path.basename(file.path), basename)) return index;
    }
    return null;
}

fn relocateName(strings: []const u8, name: module_sema.StringRange, base: u32) !module_sema.StringRange {
    if (name.start > strings.len or name.len > strings.len - name.start) return error.InvalidModuleStringRange;
    return .{ .start = base + name.start, .len = name.len };
}
