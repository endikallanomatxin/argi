const std = @import("std");
const syn = @import("../3_syntax/syntax_tree.zig");
const file_bindings = @import("file_bindings.zig");
const lexical_tables = @import("global_lexical.zig");
const semantic_strings = @import("semantic_strings.zig");

pub const ModuleDeclId = enum(u32) { _ };
/// Module-local identity of an unresolved lookup.
pub const ModuleTypeRefId = enum(u32) { _ };
pub const ModuleTypeId = enum(u32) { _ };
pub const ModuleFunctionId = enum(u32) { _ };
pub const StringRange = semantic_strings.StringRange;
pub const DeclarationRange = struct { start: u32, len: u32 };

/// The spelling of an import is file-local; locating its module is global work.
pub const ImportReference = struct {
    path: StringRange,
    source_offset: u32,
    syntax_node: syn.NodeIndex,
};

/// A type lookup requirement, not a selected declaration or canonical type.
/// Even a name declared in this file may participate in global resolution.
pub const TypeReference = struct {
    name: StringRange,
    qualifier: ?StringRange,
    source_offset: u32,
    syntax_node: syn.NodeIndex,
    resolution: TypeReferenceResolution = .external,
    resolved_type: ?ModuleTypeId = null,
};

pub const TypeReferenceResolution = union(enum) {
    builtin: BuiltinType,
    module: ModuleDeclId,
    external,
};

pub const BuiltinType = enum { Int8, Int16, Int32, Int64, UIntNative, UInt8, UInt16, UInt32, UInt64, Float16, Float32, Float64, Char, Bool, Void, Type, Any };
pub const ModuleType = union(enum) {
    builtin: BuiltinType,
    declared: ModuleDeclId,
    pointer: struct { child: ModuleTypeId, mutability: syn.PointerMutability },
    array: struct { length: u64, element: ModuleTypeId },
};

pub const FieldRange = struct { start: u32, len: u32 };
pub const Field = struct { name: StringRange, ty: ModuleTypeId, source_offset: u32, has_default: bool };
pub const FunctionInterface = struct { declaration: ModuleDeclId, input: FieldRange, output: FieldRange };

pub const DeclarationKind = enum {
    binding,
    import_alias,
    abstract_type,
    type,
    choice_option,
    function,
    test_function,
};

pub const Declaration = struct {
    kind: DeclarationKind,
    name: StringRange,
    source_offset: u32,
    module_file_index: u32,
    // Temporary syntax provenance bridge while expression lowering is migrated.
    syntax_node: syn.NodeIndex,
    type_id: ?ModuleTypeId = null,
    function_id: ?ModuleFunctionId = null,
    struct_fields: ?FieldRange = null,
};

pub const FileOffsets = struct {
    source_file_index: u32,
    declaration_base: u32,
    declaration_count: u32,
    type_reference_base: u32,
    type_reference_count: u32,
    import_reference_base: u32,
    import_reference_count: u32,
};

pub const Symbol = struct {
    name: StringRange,
    declarations: DeclarationRange,
};

/// Compact semantic storage owned by one module directory. Source-file indices
/// and syntax nodes are provenance only; all semantic table identities are
/// allocated in this module-wide storage.
pub const ModuleSemanticGraph = struct {
    module_dir: []const u8 = "",
    declarations: std.ArrayList(Declaration) = .empty,
    symbols: std.ArrayList(Symbol) = .empty,
    symbol_declarations: std.ArrayList(ModuleDeclId) = .empty,
    types: std.ArrayList(ModuleType) = .empty,
    functions: std.ArrayList(FunctionInterface) = .empty,
    fields: std.ArrayList(Field) = .empty,
    strings: std.ArrayList(u8) = .empty,
    lexical: lexical_tables.LexicalTables = .{},
    type_references: std.ArrayList(TypeReference) = .empty,
    import_references: std.ArrayList(ImportReference) = .empty,
    file_offsets: std.ArrayList(FileOffsets) = .empty,

    pub fn deinit(self: *ModuleSemanticGraph, allocator: std.mem.Allocator) void {
        allocator.free(self.module_dir);
        self.declarations.deinit(allocator);
        self.symbols.deinit(allocator);
        self.symbol_declarations.deinit(allocator);
        self.types.deinit(allocator);
        self.functions.deinit(allocator);
        self.fields.deinit(allocator);
        self.strings.deinit(allocator);
        self.lexical.deinit(allocator);
        self.type_references.deinit(allocator);
        self.import_references.deinit(allocator);
        self.file_offsets.deinit(allocator);
        self.* = .{};
    }

    pub fn declaration(self: *const ModuleSemanticGraph, id: ModuleDeclId) Declaration {
        return self.declarations.items[@intFromEnum(id)];
    }

    pub fn text(self: *const ModuleSemanticGraph, range: StringRange) []const u8 {
        return self.strings.items[range.start..][0..range.len];
    }

    pub fn declarationsNamed(self: *const ModuleSemanticGraph, name: []const u8) []const ModuleDeclId {
        var start: usize = 0;
        var end = self.symbols.items.len;
        while (start < end) {
            const middle = start + (end - start) / 2;
            const symbol = self.symbols.items[middle];
            switch (std.mem.order(u8, self.text(symbol.name), name)) {
                .lt => start = middle + 1,
                .gt => end = middle,
                .eq => return self.symbol_declarations.items[symbol.declarations.start..][0..symbol.declarations.len],
            }
        }
        return &.{};
    }

    pub fn storageBytes(self: *const ModuleSemanticGraph) usize {
        var lexical_bytes: usize = 0;
        lexical_bytes = self.lexical.storageBytes();
        return self.module_dir.len + self.declarations.items.len * @sizeOf(Declaration) +
            self.symbols.items.len * @sizeOf(Symbol) + self.symbol_declarations.items.len * @sizeOf(ModuleDeclId) +
            self.types.items.len * @sizeOf(ModuleType) + self.functions.items.len * @sizeOf(FunctionInterface) +
            self.fields.items.len * @sizeOf(Field) +
            self.strings.items.len + lexical_bytes +
            self.type_references.items.len * @sizeOf(TypeReference) +
            self.import_references.items.len * @sizeOf(ImportReference) +
            self.file_offsets.items.len * @sizeOf(FileOffsets);
    }

    fn addString(self: *ModuleSemanticGraph, allocator: std.mem.Allocator, value: []const u8) !StringRange {
        return semantic_strings.append(&self.strings, allocator, value);
    }
};

pub const FileInput = struct {
    file_index: u32,
    tree: *const syn.FileSyntaxTree,
    source: []const u8,
};

pub const ModuleSemanticGraphBuilder = struct {
    allocator: std.mem.Allocator,
    graph: ModuleSemanticGraph,

    pub fn init(allocator: std.mem.Allocator, module_dir: []const u8) !ModuleSemanticGraphBuilder {
        return .{ .allocator = allocator, .graph = .{ .module_dir = try allocator.dupe(u8, module_dir) } };
    }

    pub fn deinit(self: *ModuleSemanticGraphBuilder) void {
        self.graph.deinit(self.allocator);
    }

    pub fn build(self: *ModuleSemanticGraphBuilder, files: []const FileInput) !ModuleSemanticGraph {
        try self.graph.file_offsets.ensureTotalCapacity(self.allocator, files.len);
        for (files, 0..) |file, module_file_index| {
            const declaration_base: u32 = @intCast(self.graph.declarations.items.len);
            const type_reference_base: u32 = @intCast(self.graph.type_references.items.len);
            const import_reference_base: u32 = @intCast(self.graph.import_references.items.len);
            try discoverFile(self.allocator, &self.graph, file, @intCast(module_file_index));
            self.graph.file_offsets.appendAssumeCapacity(.{
                .source_file_index = file.file_index,
                .declaration_base = declaration_base,
                .declaration_count = @intCast(self.graph.declarations.items.len - declaration_base),
                .type_reference_base = type_reference_base,
                .type_reference_count = @intCast(self.graph.type_references.items.len - type_reference_base),
                .import_reference_base = import_reference_base,
                .import_reference_count = @intCast(self.graph.import_references.items.len - import_reference_base),
            });
        }
        try buildSymbolIndex(self.allocator, &self.graph);
        try predeclareTypes(self.allocator, &self.graph);
        resolveModuleTypeReferences(&self.graph);
        try buildStructDefinitions(self.allocator, &self.graph, files);
        try buildFunctionInterfaces(self.allocator, &self.graph, files);
        const result = self.graph;
        self.graph = .{};
        return result;
    }
};

/// Starts semantic construction at the language's module boundary. The helper
/// performs discovery file by file, but writes every durable result directly
/// into module-owned tables; there is no intermediate file semantic artifact.
pub fn build(allocator: std.mem.Allocator, module_dir: []const u8, files: []const FileInput) !ModuleSemanticGraph {
    var builder = try ModuleSemanticGraphBuilder.init(allocator, module_dir);
    errdefer builder.deinit();
    return builder.build(files);
}

fn buildSymbolIndex(allocator: std.mem.Allocator, graph: *ModuleSemanticGraph) !void {
    try graph.symbol_declarations.ensureTotalCapacity(allocator, graph.declarations.items.len);
    for (graph.declarations.items, 0..) |_, index| graph.symbol_declarations.appendAssumeCapacity(@enumFromInt(@as(u32, @intCast(index))));
    std.mem.sort(ModuleDeclId, graph.symbol_declarations.items, graph, struct {
        fn lessThan(g: *ModuleSemanticGraph, lhs: ModuleDeclId, rhs: ModuleDeclId) bool {
            const left = g.text(g.declaration(lhs).name);
            const right = g.text(g.declaration(rhs).name);
            const order = std.mem.order(u8, left, right);
            return order == .lt or (order == .eq and @intFromEnum(lhs) < @intFromEnum(rhs));
        }
    }.lessThan);
    try graph.symbols.ensureTotalCapacity(allocator, graph.declarations.items.len);
    var start: usize = 0;
    while (start < graph.symbol_declarations.items.len) {
        const name = graph.declaration(graph.symbol_declarations.items[start]).name;
        var end = start + 1;
        while (end < graph.symbol_declarations.items.len and std.mem.eql(u8, graph.text(name), graph.text(graph.declaration(graph.symbol_declarations.items[end]).name))) end += 1;
        graph.symbols.appendAssumeCapacity(.{ .name = name, .declarations = .{ .start = @intCast(start), .len = @intCast(end - start) } });
        start = end;
    }
}

fn resolveModuleTypeReferences(graph: *ModuleSemanticGraph) void {
    for (graph.type_references.items) |*reference| {
        if (reference.qualifier != null) continue;
        if (builtinFromName(graph.text(reference.name))) |builtin| {
            reference.resolution = .{ .builtin = builtin };
            continue;
        }
        for (graph.declarationsNamed(graph.text(reference.name))) |declaration_id| {
            switch (graph.declaration(declaration_id).kind) {
                .type, .abstract_type => {
                    reference.resolution = .{ .module = declaration_id };
                    reference.resolved_type = graph.declaration(declaration_id).type_id;
                    break;
                },
                else => {},
            }
        }
    }
}

fn predeclareTypes(allocator: std.mem.Allocator, graph: *ModuleSemanticGraph) !void {
    for (graph.declarations.items, 0..) |*declaration, index| switch (declaration.kind) {
        .type, .abstract_type => {
            if (graph.types.items.len >= std.math.maxInt(u32)) return error.ModuleSemanticGraphTooLarge;
            declaration.type_id = @enumFromInt(@as(u32, @intCast(graph.types.items.len)));
            try graph.types.append(allocator, .{ .declared = @enumFromInt(@as(u32, @intCast(index))) });
        },
        else => {},
    };
}

fn buildFunctionInterfaces(allocator: std.mem.Allocator, graph: *ModuleSemanticGraph, files: []const FileInput) !void {
    for (graph.declarations.items, 0..) |*declaration, declaration_index| {
        if (declaration.kind != .function and declaration.kind != .test_function) continue;
        const file_input = files[declaration.module_file_index];
        const function = if (declaration.kind == .test_function)
            file_input.tree.testDeclaration(declaration.syntax_node).?.function
        else
            file_input.tree.functionDeclaration(declaration.syntax_node).?;
        if (function.generic_params.len != 0 or function.generic_params_struct != null) continue;
        const field_start = graph.fields.items.len;
        if (!try appendFields(allocator, graph, file_input, function.input) or
            !try appendFields(allocator, graph, file_input, function.output))
        {
            graph.fields.shrinkRetainingCapacity(field_start);
            continue;
        }
        const input_len = file_input.tree.structTypeLiteral(function.input).?.fields.len;
        const output_len = file_input.tree.structTypeLiteral(function.output).?.fields.len;
        const function_id: ModuleFunctionId = @enumFromInt(@as(u32, @intCast(graph.functions.items.len)));
        try graph.functions.append(allocator, .{
            .declaration = @enumFromInt(@as(u32, @intCast(declaration_index))),
            .input = .{ .start = @intCast(field_start), .len = @intCast(input_len) },
            .output = .{ .start = @intCast(field_start + input_len), .len = @intCast(output_len) },
        });
        declaration.function_id = function_id;
    }
}

fn buildStructDefinitions(allocator: std.mem.Allocator, graph: *ModuleSemanticGraph, files: []const FileInput) !void {
    for (graph.declarations.items) |*declaration| {
        if (declaration.kind != .type) continue;
        const input = files[declaration.module_file_index];
        const type_declaration = switch (input.tree.tag(declaration.syntax_node)) {
            .type_declaration => input.tree.typeDeclaration(declaration.syntax_node).?,
            .c_union_declaration => blk: {
                const value = input.tree.cUnionDeclaration(declaration.syntax_node).?;
                break :blk syn.TypeDeclaration{ .name_token = value.name_token, .generic_params = value.generic_params, .generic_params_struct = value.generic_params_struct, .value = value.value };
            },
            else => continue,
        };
        if (type_declaration.generic_params.len != 0 or type_declaration.generic_params_struct != null or input.tree.tag(type_declaration.value) != .struct_type_literal) continue;
        const start = graph.fields.items.len;
        if (!try appendFields(allocator, graph, input, type_declaration.value)) {
            graph.fields.shrinkRetainingCapacity(start);
            continue;
        }
        declaration.struct_fields = .{ .start = @intCast(start), .len = @intCast(graph.fields.items.len - start) };
    }
}

fn appendFields(allocator: std.mem.Allocator, graph: *ModuleSemanticGraph, input: FileInput, struct_node: syn.NodeIndex) !bool {
    const literal = input.tree.structTypeLiteral(struct_node) orelse return false;
    for (literal.fields) |field_node| {
        const field = input.tree.structTypeField(field_node) orelse return false;
        const type_node = field.type_node orelse return false;
        const ty = try lowerType(allocator, graph, input.tree, input.source, input.file_index, type_node) orelse return false;
        const name = if (field.inferred_result) "result" else input.tree.tokenTextFromSource(input.source, field.name_token);
        try graph.fields.append(allocator, .{ .name = try graph.addString(allocator, name), .ty = ty, .source_offset = input.tree.tokenLocation(field.name_token).offset, .has_default = field.default_value != null });
    }
    return true;
}

fn lowerType(allocator: std.mem.Allocator, graph: *ModuleSemanticGraph, tree: *const syn.FileSyntaxTree, source: []const u8, source_file_index: u32, node: syn.NodeIndex) !?ModuleTypeId {
    const syntax_type = tree.syntaxType(node) orelse return null;
    return switch (syntax_type) {
        .name => |name| blk: {
            if (name.qualifier_token != null) break :blk null;
            const spelling = tree.tokenTextFromSource(source, name.name_token);
            if (builtinFromName(spelling)) |builtin| break :blk try appendType(allocator, graph, .{ .builtin = builtin });
            const reference = findTypeReferenceForSourceFile(graph, source_file_index, node) orelse break :blk null;
            break :blk switch (reference.resolution) {
                .builtin => |builtin| try appendType(allocator, graph, .{ .builtin = builtin }),
                .module => reference.resolved_type,
                .external => null,
            };
        },
        .pointer => |pointer| blk: {
            const child = try lowerType(allocator, graph, tree, source, source_file_index, pointer.child) orelse break :blk null;
            break :blk try appendType(allocator, graph, .{ .pointer = .{ .child = child, .mutability = pointer.mutability } });
        },
        .array => |array| blk: {
            const length = std.fmt.parseInt(u64, tree.tokenTextFromSource(source, array.length_token), 0) catch break :blk null;
            const element = try lowerType(allocator, graph, tree, source, source_file_index, array.element) orelse break :blk null;
            break :blk try appendType(allocator, graph, .{ .array = .{ .length = length, .element = element } });
        },
        else => null,
    };
}

fn appendType(allocator: std.mem.Allocator, graph: *ModuleSemanticGraph, ty: ModuleType) !ModuleTypeId {
    for (graph.types.items, 0..) |existing, index| {
        if (moduleTypesEqual(existing, ty)) return @enumFromInt(@as(u32, @intCast(index)));
    }
    if (graph.types.items.len >= std.math.maxInt(u32)) return error.ModuleSemanticGraphTooLarge;
    const id: ModuleTypeId = @enumFromInt(@as(u32, @intCast(graph.types.items.len)));
    try graph.types.append(allocator, ty);
    return id;
}

fn moduleTypesEqual(lhs: ModuleType, rhs: ModuleType) bool {
    if (std.meta.activeTag(lhs) != std.meta.activeTag(rhs)) return false;
    return switch (lhs) {
        .builtin => |value| value == rhs.builtin,
        .declared => |value| value == rhs.declared,
        .pointer => |value| value.child == rhs.pointer.child and value.mutability == rhs.pointer.mutability,
        .array => |value| value.length == rhs.array.length and value.element == rhs.array.element,
    };
}

fn findTypeReferenceForSourceFile(graph: *const ModuleSemanticGraph, source_file_index: u32, node: syn.NodeIndex) ?TypeReference {
    for (graph.file_offsets.items) |file| {
        if (file.source_file_index != source_file_index) continue;
        for (graph.type_references.items[file.type_reference_base..][0..file.type_reference_count]) |reference| if (reference.syntax_node == node) return reference;
    }
    return null;
}

fn builtinFromName(name: []const u8) ?BuiltinType {
    inline for (@typeInfo(BuiltinType).@"enum".fields) |field| if (std.mem.eql(u8, name, field.name)) return @enumFromInt(field.value);
    return null;
}

fn discoverFile(allocator: std.mem.Allocator, graph: *ModuleSemanticGraph, input: FileInput, module_file_index: u32) !void {
    const tree = input.tree;
    const source = input.source;
    for (tree.roots) |node| {
        const kind: DeclarationKind = switch (tree.tag(node)) {
            .symbol_declaration_constant, .symbol_declaration_variable => blk: {
                const value = tree.symbolDeclaration(node).?.value;
                break :blk if (value != null and tree.tag(value.?) == .import_statement) .import_alias else .binding;
            },
            .abstract_declaration => .abstract_type,
            .type_declaration, .c_enum_declaration, .c_union_declaration => .type,
            .choice_option_declaration => .choice_option,
            .function_declaration, .function_declaration_once => .function,
            .test_declaration => .test_function,
            else => continue,
        };
        const name_token = switch (kind) {
            .function => tree.functionDeclaration(node).?.name_token,
            .test_function => tree.testDeclaration(node).?.function.name_token,
            .choice_option => tree.choiceOptionDeclaration(node).?.name_token,
            else => tree.mainToken(node),
        };
        const name = if (kind == .function or kind == .test_function)
            switch (tree.functionNameFromSource(source, node) orelse continue) {
                .identifier => tree.tokenTextFromSource(source, name_token),
                .operator => |operator| switch (operator) {
                    .add => "operator +",
                    .equal => "operator ==",
                    .not_equal => "operator !=",
                    .get => "operator get[]",
                    .set => "operator set[]",
                    .get_ro_pointer => "operator get_ro_pointer[]",
                    .get_rw_pointer => "operator get_rw_pointer[]",
                },
            }
        else
            tree.tokenTextFromSource(source, name_token);
        if (graph.declarations.items.len >= std.math.maxInt(u32))
            return error.ModuleSemanticGraphTooLarge;
        const range = try graph.addString(allocator, name);
        try graph.declarations.append(allocator, .{
            .kind = kind,
            .name = range,
            .source_offset = tree.location(node).offset,
            .module_file_index = module_file_index,
            .syntax_node = node,
        });
    }
    // Syntax-node order permits binary lookup during the global consumer
    // migration without retaining a dense map for every expression node.
    for (tree.nodes.items(.tag), 0..) |tag, index| {
        if (tag == .import_statement) {
            const node: syn.NodeIndex = @enumFromInt(@as(u32, @intCast(index)));
            const path_token = tree.importStatement(node).?.path_token;
            const path = try graph.addString(allocator, tree.tokenTextFromSource(source, path_token));
            try graph.import_references.append(allocator, .{
                .path = path,
                .source_offset = tree.tokenLocation(path_token).offset,
                .syntax_node = node,
            });
        }
        if (tag != .type_name) continue;
        const node: syn.NodeIndex = @enumFromInt(@as(u32, @intCast(index)));
        const name = tree.syntaxType(node).?.name;
        const spelling = try graph.addString(allocator, tree.tokenTextFromSource(source, name.name_token));
        const qualifier = if (name.qualifier_token) |token|
            try graph.addString(allocator, tree.tokenTextFromSource(source, token))
        else
            null;
        try graph.type_references.append(allocator, .{
            .name = spelling,
            .qualifier = qualifier,
            .source_offset = tree.tokenLocation(name.qualifier_token orelse name.name_token).offset,
            .syntax_node = node,
        });
    }
    var lexical = try file_bindings.build(allocator, tree, source, &graph.strings);
    defer lexical.deinit(allocator);
    try graph.lexical.appendFileBindings(allocator, graph.strings.items, &lexical, module_file_index);
}
