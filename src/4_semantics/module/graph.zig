const std = @import("std");
const syn = @import("../../3_syntax/syntax_tree.zig");
const file_bindings = @import("../lexical/file_bindings.zig");
const lexical_tables = @import("../lexical/global.zig");
const semantic_strings = @import("../primitives/strings.zig");
const primitives = @import("../primitives/schema.zig");
const module_entities = @import("entities.zig");
const module_storage = @import("storage.zig");

pub const ModuleDeclId = module_entities.ModuleDeclId;
/// Module-local identity of an unresolved lookup.
pub const ModuleTypeRefId = enum(u32) { _ };
pub const ModuleTypeId = module_entities.ModuleTypeId;
pub const ModuleFunctionId = module_entities.ModuleFunctionId;
pub const StringRange = semantic_strings.StringRange;
pub const DeclarationRange = struct { start: u32, len: u32 };

/// A type lookup requirement, not a selected declaration or canonical type.
/// Even a name declared in this file may participate in global resolution.
pub const TypeReference = struct {
    name: StringRange,
    qualifier: ?StringRange,
    source_offset: u32,
    resolution: TypeReferenceResolution = .external,
    resolved_type: ?ModuleTypeId = null,
};

pub const TypeReferenceResolution = union(enum) {
    builtin: BuiltinType,
    module: ModuleDeclId,
    external,
};

pub const BuiltinType = primitives.BuiltinType;
pub const ModuleType = union(enum) {
    builtin: BuiltinType,
    declared: ModuleDeclId,
    pointer: struct { child: ModuleTypeId, mutability: syn.PointerMutability },
    array: struct { length: u64, element: ModuleTypeId },
    nullable: ModuleTypeId,
    inferred_errable: ModuleTypeId,
    structural: FieldRange,
    structural_choice: FieldRange,
    generic: struct { base: ModuleDeclId, arguments: FieldRange },
};

pub const FieldRange = struct { start: u32, len: u32 };
pub const Field = struct {
    name: StringRange,
    ty: ModuleTypeId,
    source_offset: u32,
    has_default: bool,
    // Expression lowering has not moved into the module graph yet.
    default_value: ?syn.NodeIndex = null,
    module_file_index: u32 = 0,
};
pub const FunctionInterface = struct { declaration: ModuleDeclId, input: FieldRange, output: FieldRange };
pub const ChoiceVariant = struct { name: StringRange, qualifier: ?StringRange, payload_type: ?ModuleTypeId, source_offset: u32, module_file_index: u32 };
pub const GenericTypeArgument = struct { name: StringRange, ty: ModuleTypeId };

pub const DeclarationKind = primitives.DeclarationKind;

pub const Declaration = struct {
    kind: DeclarationKind,
    name: StringRange,
    source_offset: u32,
    module_file_index: u32,
    // Temporary syntax provenance bridge while expression lowering is migrated.
    type_id: ?ModuleTypeId = null,
    function_id: ?ModuleFunctionId = null,
    struct_fields: ?FieldRange = null,
    choice_variants: ?FieldRange = null,
    generic_parameter_count: ?u32 = null,
};

pub const FileOffsets = struct {
    path: StringRange,
    declaration_base: u32,
    declaration_count: u32,
    type_reference_base: u32,
    type_reference_count: u32,
};

pub const Symbol = struct {
    name: StringRange,
    declarations: DeclarationRange,
};

/// Compact semantic storage owned by one module directory. Source-file indices
/// and syntax nodes in the compatibility tables are provenance only. Durable
/// bodies and semantic identities live in `semantic` using Module* IDs.
pub const ModuleSemanticGraph = struct {
    module_dir: []const u8 = "",
    is_bundled_core: bool = false,
    declarations: std.ArrayList(Declaration) = .empty,
    symbols: std.ArrayList(Symbol) = .empty,
    symbol_declarations: std.ArrayList(ModuleDeclId) = .empty,
    types: std.ArrayList(ModuleType) = .empty,
    functions: std.ArrayList(FunctionInterface) = .empty,
    fields: std.ArrayList(Field) = .empty,
    structural_fields: std.ArrayList(Field) = .empty,
    choice_variant_entries: std.ArrayList(ChoiceVariant) = .empty,
    structural_choice_variants: std.ArrayList(ChoiceVariant) = .empty,
    generic_type_arguments: std.ArrayList(GenericTypeArgument) = .empty,
    strings: std.ArrayList(u8) = .empty,
    lexical: lexical_tables.LexicalTables = .{},
    type_references: std.ArrayList(TypeReference) = .empty,
    file_offsets: std.ArrayList(FileOffsets) = .empty,
    semantic: module_storage.Storage = .{},

    pub fn deinit(self: *ModuleSemanticGraph, allocator: std.mem.Allocator) void {
        allocator.free(self.module_dir);
        self.declarations.deinit(allocator);
        self.symbols.deinit(allocator);
        self.symbol_declarations.deinit(allocator);
        self.types.deinit(allocator);
        self.functions.deinit(allocator);
        self.fields.deinit(allocator);
        self.structural_fields.deinit(allocator);
        self.choice_variant_entries.deinit(allocator);
        self.structural_choice_variants.deinit(allocator);
        self.generic_type_arguments.deinit(allocator);
        self.strings.deinit(allocator);
        self.lexical.deinit(allocator);
        self.type_references.deinit(allocator);
        self.file_offsets.deinit(allocator);
        self.semantic.deinit(allocator);
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
        const lexical_bytes = self.lexical.storageBytes();
        return self.module_dir.len + self.declarations.items.len * @sizeOf(Declaration) +
            self.symbols.items.len * @sizeOf(Symbol) + self.symbol_declarations.items.len * @sizeOf(ModuleDeclId) +
            self.types.items.len * @sizeOf(ModuleType) + self.functions.items.len * @sizeOf(FunctionInterface) +
            (self.fields.items.len + self.structural_fields.items.len) * @sizeOf(Field) +
            (self.choice_variant_entries.items.len + self.structural_choice_variants.items.len) * @sizeOf(ChoiceVariant) +
            self.generic_type_arguments.items.len * @sizeOf(GenericTypeArgument) +
            self.strings.items.len + lexical_bytes +
            self.type_references.items.len * @sizeOf(TypeReference) +
            self.file_offsets.items.len * @sizeOf(FileOffsets) +
            self.semantic.storageBytes();
    }

    fn addString(self: *ModuleSemanticGraph, allocator: std.mem.Allocator, value: []const u8) !StringRange {
        return semantic_strings.append(&self.strings, allocator, value);
    }
};

pub const FileInput = struct {
    path: []const u8,
    tree: *const syn.FileSyntaxTree,
    source: []const u8,
    is_bundled_core: bool = false,
};


/// Construction-only lookup from durable source provenance back into syntax.
/// Completed ModuleSG declarations keep source identity, not AST identity.
pub fn declarationSyntaxNode(files: []const FileInput, declaration: Declaration) ?syn.NodeIndex {
    if (declaration.module_file_index >= files.len) return null;
    const tree = files[declaration.module_file_index].tree;
    for (tree.roots) |node| {
        if (tree.location(node).offset == declaration.source_offset) return node;
    }
    return null;
}

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
        self.graph.is_bundled_core = files.len != 0 and files[0].is_bundled_core;
        for (files) |file| if (file.is_bundled_core != self.graph.is_bundled_core) return error.MixedModuleOrigins;
        try self.graph.file_offsets.ensureTotalCapacity(self.allocator, files.len);
        for (files, 0..) |file, module_file_index| {
            const declaration_base: u32 = @intCast(self.graph.declarations.items.len);
            const type_reference_base: u32 = @intCast(self.graph.type_references.items.len);
            try discoverFile(self.allocator, &self.graph, file, @intCast(module_file_index));
            self.graph.file_offsets.appendAssumeCapacity(.{
                .path = try self.graph.addString(self.allocator, std.fs.path.basename(file.path)),
                .declaration_base = declaration_base,
                .declaration_count = @intCast(self.graph.declarations.items.len - declaration_base),
                .type_reference_base = type_reference_base,
                .type_reference_count = @intCast(self.graph.type_references.items.len - type_reference_base),
            });
        }
        try buildSymbolIndex(self.allocator, &self.graph);
        try predeclareTypes(self.allocator, &self.graph);
        resolveModuleTypeReferences(&self.graph);
        try buildStructDefinitions(self.allocator, &self.graph, files);
        try buildChoiceDefinitions(self.allocator, &self.graph, files);
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
        const declaration_node = declarationSyntaxNode(files, declaration.*) orelse continue;
        const function = if (declaration.kind == .test_function)
            file_input.tree.testDeclaration(declaration_node).?.function
        else
            file_input.tree.functionDeclaration(declaration_node).?;
        if (function.generic_params.len != 0 or function.generic_params_struct != null) continue;
        const field_start = graph.fields.items.len;
        if (!try appendFields(allocator, graph, file_input, @intCast(declaration.module_file_index), function.input) or
            !try appendFields(allocator, graph, file_input, @intCast(declaration.module_file_index), function.output))
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
        const declaration_node = declarationSyntaxNode(files, declaration.*) orelse continue;
        const type_declaration = switch (input.tree.tag(declaration_node)) {
            .type_declaration => input.tree.typeDeclaration(declaration_node).?,
            .c_union_declaration => blk: {
                const value = input.tree.cUnionDeclaration(declaration_node).?;
                break :blk syn.TypeDeclaration{ .name_token = value.name_token, .generic_params = value.generic_params, .generic_params_struct = value.generic_params_struct, .value = value.value };
            },
            else => continue,
        };
        if (type_declaration.generic_params.len != 0 or type_declaration.generic_params_struct != null or input.tree.tag(type_declaration.value) != .struct_type_literal) continue;
        const start = graph.fields.items.len;
        if (!try appendFields(allocator, graph, input, declaration.module_file_index, type_declaration.value)) {
            graph.fields.shrinkRetainingCapacity(start);
            continue;
        }
        declaration.struct_fields = .{ .start = @intCast(start), .len = @intCast(graph.fields.items.len - start) };
    }
}

fn buildChoiceDefinitions(allocator: std.mem.Allocator, graph: *ModuleSemanticGraph, files: []const FileInput) !void {
    for (graph.declarations.items) |*declaration| {
        if (declaration.kind != .type) continue;
        const input = files[declaration.module_file_index];
        const declaration_node = declarationSyntaxNode(files, declaration.*) orelse continue;
        const generic_params, const generic_params_struct, const value = switch (input.tree.tag(declaration_node)) {
            .type_declaration => blk: {
                const item = input.tree.typeDeclaration(declaration_node).?;
                break :blk .{ item.generic_params, item.generic_params_struct, item.value };
            },
            .c_enum_declaration => blk: {
                const item = input.tree.cEnumDeclaration(declaration_node).?;
                break :blk .{ item.generic_params, item.generic_params_struct, item.value };
            },
            else => continue,
        };
        if (generic_params.len != 0 or generic_params_struct != null) continue;
        const literal = input.tree.choiceTypeLiteral(value) orelse continue;
        const start = graph.choice_variant_entries.items.len;
        var complete = true;
        for (literal.variants) |variant_node| {
            const variant = input.tree.choiceTypeVariant(variant_node) orelse {
                complete = false;
                break;
            };
            const payload_type = if (variant.payload_type) |payload|
                try lowerType(allocator, graph, input.tree, input.source, declaration.module_file_index, payload) orelse {
                    complete = false;
                    break;
                }
            else
                null;
            try graph.choice_variant_entries.append(allocator, .{
                .name = try graph.addString(allocator, input.tree.tokenTextFromSource(input.source, variant.name_token)),
                .qualifier = if (variant.module_qualifier) |qualifier| try graph.addString(allocator, input.tree.tokenTextFromSource(input.source, qualifier)) else null,
                .payload_type = payload_type,
                .source_offset = input.tree.tokenLocation(variant.name_token).offset,
                .module_file_index = declaration.module_file_index,
            });
        }
        if (!complete) {
            graph.choice_variant_entries.shrinkRetainingCapacity(start);
            continue;
        }
        declaration.choice_variants = .{ .start = @intCast(start), .len = @intCast(literal.variants.len) };
    }
}

fn appendFields(allocator: std.mem.Allocator, graph: *ModuleSemanticGraph, input: FileInput, module_file_index: u32, struct_node: syn.NodeIndex) !bool {
    const literal = input.tree.structTypeLiteral(struct_node) orelse return false;
    for (literal.fields) |field_node| {
        const field = input.tree.structTypeField(field_node) orelse return false;
        const type_node = field.type_node orelse return false;
        const ty = try lowerType(allocator, graph, input.tree, input.source, module_file_index, type_node) orelse return false;
        const name = if (field.inferred_result) "result" else input.tree.tokenTextFromSource(input.source, field.name_token);
        try graph.fields.append(allocator, .{
            .name = try graph.addString(allocator, name),
            .ty = ty,
            .source_offset = input.tree.tokenLocation(field.name_token).offset,
            .has_default = field.default_value != null,
            .default_value = field.default_value,
            .module_file_index = module_file_index,
        });
    }
    return true;
}

fn lowerType(allocator: std.mem.Allocator, graph: *ModuleSemanticGraph, tree: *const syn.FileSyntaxTree, source: []const u8, module_file_index: u32, node: syn.NodeIndex) semantic_strings.Error!?ModuleTypeId {
    const syntax_type = tree.syntaxType(node) orelse return null;
    return switch (syntax_type) {
        .name => |name| blk: {
            if (name.qualifier_token != null) break :blk null;
            const spelling = tree.tokenTextFromSource(source, name.name_token);
            if (builtinFromName(spelling)) |builtin| break :blk try appendType(allocator, graph, .{ .builtin = builtin });
            const reference = findTypeReference(graph, module_file_index, tree.tokenLocation(name.name_token).offset) orelse break :blk null;
            break :blk switch (reference.resolution) {
                .builtin => |builtin| try appendType(allocator, graph, .{ .builtin = builtin }),
                .module => reference.resolved_type,
                .external => null,
            };
        },
        .pointer => |pointer| blk: {
            const child = try lowerType(allocator, graph, tree, source, module_file_index, pointer.child) orelse break :blk null;
            break :blk try appendType(allocator, graph, .{ .pointer = .{ .child = child, .mutability = pointer.mutability } });
        },
        .array => |array| blk: {
            const length = std.fmt.parseInt(u64, tree.tokenTextFromSource(source, array.length_token), 0) catch break :blk null;
            const element = try lowerType(allocator, graph, tree, source, module_file_index, array.element) orelse break :blk null;
            break :blk try appendType(allocator, graph, .{ .array = .{ .length = length, .element = element } });
        },
        .nullable => |child_node| blk: {
            const child = try lowerType(allocator, graph, tree, source, module_file_index, child_node) orelse break :blk null;
            break :blk try appendType(allocator, graph, .{ .nullable = child });
        },
        .inferred_errable => |child_node| blk: {
            const child = try lowerType(allocator, graph, tree, source, module_file_index, child_node) orelse break :blk null;
            break :blk try appendType(allocator, graph, .{ .inferred_errable = child });
        },
        .struct_literal => |literal| try lowerStructuralType(allocator, graph, tree, source, module_file_index, literal),
        .choice_literal => |literal| try lowerStructuralChoiceType(allocator, graph, tree, source, module_file_index, literal),
        .generic => |generic| try lowerGenericType(allocator, graph, tree, source, module_file_index, generic),
    };
}

fn lowerGenericType(
    allocator: std.mem.Allocator,
    graph: *ModuleSemanticGraph,
    tree: *const syn.FileSyntaxTree,
    source: []const u8,
    module_file_index: u32,
    generic: syn.GenericType,
) semantic_strings.Error!?ModuleTypeId {
    const base = tree.syntaxType(generic.base) orelse return null;
    if (base != .name or base.name.qualifier_token != null) return null;
    const base_name = tree.tokenTextFromSource(source, base.name.name_token);
    const literal = tree.structTypeLiteral(generic.arguments) orelse return null;
    if (std.mem.eql(u8, base_name, "Array")) return lowerArrayGeneric(allocator, graph, tree, source, module_file_index, literal);
    if (std.mem.eql(u8, base_name, "choice_union")) return lowerChoiceUnion(allocator, graph, tree, source, module_file_index, literal);
    if (std.mem.eql(u8, base_name, "Virtual")) return null;
    const reference = findTypeReference(graph, module_file_index, tree.tokenLocation(base.name.name_token).offset) orelse return null;
    const declaration_id = switch (reference.resolution) {
        .module => |id| id,
        else => return null,
    };
    const parameter_count = graph.declaration(declaration_id).generic_parameter_count orelse return null;
    if (literal.fields.len != parameter_count) return null;
    const argument_start = graph.generic_type_arguments.items.len;
    const type_start = graph.types.items.len;
    var arguments: std.ArrayList(GenericTypeArgument) = .empty;
    defer arguments.deinit(allocator);
    errdefer {
        graph.generic_type_arguments.shrinkRetainingCapacity(argument_start);
        graph.types.shrinkRetainingCapacity(type_start);
    }
    for (literal.fields) |field_node| {
        const field = tree.structTypeField(field_node) orelse break;
        if (field.default_value != null) break;
        const type_node = field.type_node orelse break;
        const ty = try lowerType(allocator, graph, tree, source, module_file_index, type_node) orelse break;
        try arguments.append(allocator, .{
            .name = try graph.addString(allocator, tree.tokenTextFromSource(source, field.name_token)),
            .ty = ty,
        });
    } else {
        const start = graph.generic_type_arguments.items.len;
        try graph.generic_type_arguments.appendSlice(allocator, arguments.items);
        const id: ModuleTypeId = @enumFromInt(@as(u32, @intCast(graph.types.items.len)));
        try graph.types.append(allocator, .{ .generic = .{
            .base = declaration_id,
            .arguments = .{ .start = @intCast(start), .len = @intCast(arguments.items.len) },
        } });
        return id;
    }
    graph.generic_type_arguments.shrinkRetainingCapacity(argument_start);
    graph.types.shrinkRetainingCapacity(type_start);
    return null;
}

fn lowerChoiceUnion(
    allocator: std.mem.Allocator,
    graph: *ModuleSemanticGraph,
    tree: *const syn.FileSyntaxTree,
    source: []const u8,
    module_file_index: u32,
    literal: syn.StructTypeLiteral,
) semantic_strings.Error!?ModuleTypeId {
    if (literal.fields.len != 2) return null;
    var left_node: ?syn.NodeIndex = null;
    var right_node: ?syn.NodeIndex = null;
    for (literal.fields) |field_node| {
        const field = tree.structTypeField(field_node) orelse return null;
        if (field.default_value != null) return null;
        const type_node = field.type_node orelse return null;
        const name = tree.tokenTextFromSource(source, field.name_token);
        if (std.mem.eql(u8, name, "a")) {
            if (left_node != null) return null;
            left_node = type_node;
        } else if (std.mem.eql(u8, name, "b")) {
            if (right_node != null) return null;
            right_node = type_node;
        } else return null;
    }
    const left = try lowerType(allocator, graph, tree, source, module_file_index, left_node orelse return null) orelse return null;
    const right = try lowerType(allocator, graph, tree, source, module_file_index, right_node orelse return null) orelse return null;
    var variants: std.ArrayList(ChoiceVariant) = .empty;
    defer variants.deinit(allocator);
    if (!try appendChoiceUnionVariants(allocator, graph, &variants, left)) return null;
    if (!try appendChoiceUnionVariants(allocator, graph, &variants, right)) return null;
    std.mem.sort(ChoiceVariant, variants.items, graph, struct {
        fn lessThan(context: *ModuleSemanticGraph, lhs: ChoiceVariant, rhs: ChoiceVariant) bool {
            return std.mem.order(u8, context.text(lhs.name), context.text(rhs.name)) == .lt;
        }
    }.lessThan);
    const start = graph.structural_choice_variants.items.len;
    try graph.structural_choice_variants.appendSlice(allocator, variants.items);
    const id: ModuleTypeId = @enumFromInt(@as(u32, @intCast(graph.types.items.len)));
    try graph.types.append(allocator, .{ .structural_choice = .{ .start = @intCast(start), .len = @intCast(variants.items.len) } });
    return id;
}

fn appendChoiceUnionVariants(allocator: std.mem.Allocator, graph: *ModuleSemanticGraph, result: *std.ArrayList(ChoiceVariant), type_id: ModuleTypeId) semantic_strings.Error!bool {
    const source_variants = switch (graph.types.items[@intFromEnum(type_id)]) {
        .declared => |declaration_id| blk: {
            const range = graph.declaration(declaration_id).choice_variants orelse return false;
            break :blk graph.choice_variant_entries.items[range.start..][0..range.len];
        },
        .structural_choice => |range| graph.structural_choice_variants.items[range.start..][0..range.len],
        else => return false,
    };
    for (source_variants) |variant| {
        if (variant.qualifier != null) return false;
        var duplicate = false;
        for (result.items) |existing| {
            if (!std.mem.eql(u8, graph.text(existing.name), graph.text(variant.name))) continue;
            if (existing.payload_type != variant.payload_type) return false;
            duplicate = true;
            break;
        }
        if (!duplicate) try result.append(allocator, variant);
    }
    return true;
}

fn lowerArrayGeneric(
    allocator: std.mem.Allocator,
    graph: *ModuleSemanticGraph,
    tree: *const syn.FileSyntaxTree,
    source: []const u8,
    module_file_index: u32,
    literal: syn.StructTypeLiteral,
) semantic_strings.Error!?ModuleTypeId {
    if (literal.fields.len != 2) return null;
    var length: ?u64 = null;
    var element_node: ?syn.NodeIndex = null;
    for (literal.fields) |field_node| {
        const field = tree.structTypeField(field_node) orelse return null;
        const name = tree.tokenTextFromSource(source, field.name_token);
        if (std.mem.eql(u8, name, "n")) {
            if (length != null or field.type_node != null) return null;
            const value = field.default_value orelse return null;
            length = std.fmt.parseInt(u64, tree.tokenTextFromSource(source, tree.mainToken(value)), 0) catch return null;
        } else if (std.mem.eql(u8, name, "t")) {
            if (element_node != null or field.default_value != null) return null;
            element_node = field.type_node orelse return null;
        } else return null;
    }
    const element = try lowerType(allocator, graph, tree, source, module_file_index, element_node orelse return null) orelse return null;
    return try appendType(allocator, graph, .{ .array = .{ .length = length orelse return null, .element = element } });
}

fn lowerStructuralChoiceType(
    allocator: std.mem.Allocator,
    graph: *ModuleSemanticGraph,
    tree: *const syn.FileSyntaxTree,
    source: []const u8,
    module_file_index: u32,
    literal: syn.ChoiceTypeLiteral,
) semantic_strings.Error!?ModuleTypeId {
    const variant_start = graph.structural_choice_variants.items.len;
    const type_start = graph.types.items.len;
    var variants: std.ArrayList(ChoiceVariant) = .empty;
    defer variants.deinit(allocator);
    errdefer {
        graph.structural_choice_variants.shrinkRetainingCapacity(variant_start);
        graph.types.shrinkRetainingCapacity(type_start);
    }
    for (literal.variants) |variant_node| {
        const variant = tree.choiceTypeVariant(variant_node) orelse break;
        const payload_type = if (variant.payload_type) |payload|
            try lowerType(allocator, graph, tree, source, module_file_index, payload) orelse break
        else
            null;
        try variants.append(allocator, .{
            .name = try graph.addString(allocator, tree.tokenTextFromSource(source, variant.name_token)),
            .qualifier = if (variant.module_qualifier) |qualifier| try graph.addString(allocator, tree.tokenTextFromSource(source, qualifier)) else null,
            .payload_type = payload_type,
            .source_offset = tree.tokenLocation(variant.name_token).offset,
            .module_file_index = module_file_index,
        });
    } else {
        const shape_start = graph.structural_choice_variants.items.len;
        try graph.structural_choice_variants.appendSlice(allocator, variants.items);
        const id: ModuleTypeId = @enumFromInt(@as(u32, @intCast(graph.types.items.len)));
        try graph.types.append(allocator, .{ .structural_choice = .{ .start = @intCast(shape_start), .len = @intCast(variants.items.len) } });
        return id;
    }
    graph.structural_choice_variants.shrinkRetainingCapacity(variant_start);
    graph.types.shrinkRetainingCapacity(type_start);
    return null;
}

fn lowerStructuralType(
    allocator: std.mem.Allocator,
    graph: *ModuleSemanticGraph,
    tree: *const syn.FileSyntaxTree,
    source: []const u8,
    module_file_index: u32,
    literal: syn.StructTypeLiteral,
) semantic_strings.Error!?ModuleTypeId {
    const field_start = graph.structural_fields.items.len;
    const type_start = graph.types.items.len;
    var fields: std.ArrayList(Field) = .empty;
    defer fields.deinit(allocator);
    errdefer {
        graph.structural_fields.shrinkRetainingCapacity(field_start);
        graph.types.shrinkRetainingCapacity(type_start);
    }
    for (literal.fields) |field_node| {
        const field = tree.structTypeField(field_node) orelse break;
        const type_node = field.type_node orelse break;
        const ty = try lowerType(allocator, graph, tree, source, module_file_index, type_node) orelse break;
        const name = if (field.inferred_result) "result" else tree.tokenTextFromSource(source, field.name_token);
        try fields.append(allocator, .{
            .name = try graph.addString(allocator, name),
            .ty = ty,
            .source_offset = tree.tokenLocation(field.name_token).offset,
            .has_default = field.default_value != null,
            .default_value = field.default_value,
            .module_file_index = module_file_index,
        });
    } else {
        const shape_start = graph.structural_fields.items.len;
        try graph.structural_fields.appendSlice(allocator, fields.items);
        const id: ModuleTypeId = @enumFromInt(@as(u32, @intCast(graph.types.items.len)));
        try graph.types.append(allocator, .{ .structural = .{
            .start = @intCast(shape_start),
            .len = @intCast(fields.items.len),
        } });
        return id;
    }
    graph.structural_fields.shrinkRetainingCapacity(field_start);
    graph.types.shrinkRetainingCapacity(type_start);
    return null;
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
        .nullable => |value| value == rhs.nullable,
        .inferred_errable => |value| value == rhs.inferred_errable,
        // Structural shapes are stored as distinct ranges. Legacy structural
        // equality remains responsible for equating identical anonymous types.
        .structural => false,
        .structural_choice => false,
        .generic => false,
    };
}

fn findTypeReference(graph: *const ModuleSemanticGraph, module_file_index: u32, source_offset: u32) ?TypeReference {
    const file = graph.file_offsets.items[module_file_index];
    for (graph.type_references.items[file.type_reference_base..][0..file.type_reference_count]) |reference| if (reference.source_offset == source_offset) return reference;
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
            .generic_parameter_count = genericParameterCount(tree, node),
        });
    }
    // Syntax-node order permits binary lookup during the global consumer
    // migration without retaining a dense map for every expression node.
    for (tree.nodes.items(.tag), 0..) |tag, index| {
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
        });
    }
    var lexical = try file_bindings.build(allocator, tree, source, &graph.strings);
    defer lexical.deinit(allocator);
    try graph.lexical.appendFileBindings(allocator, graph.strings.items, &lexical, module_file_index);
}

fn genericParameterCount(tree: *const syn.FileSyntaxTree, node: syn.NodeIndex) ?u32 {
    const params, const params_struct = switch (tree.tag(node)) {
        .type_declaration => blk: {
            const declaration = tree.typeDeclaration(node).?;
            break :blk .{ declaration.generic_params, declaration.generic_params_struct };
        },
        .c_enum_declaration => blk: {
            const declaration = tree.cEnumDeclaration(node).?;
            break :blk .{ declaration.generic_params, declaration.generic_params_struct };
        },
        .c_union_declaration => blk: {
            const declaration = tree.cUnionDeclaration(node).?;
            break :blk .{ declaration.generic_params, declaration.generic_params_struct };
        },
        else => return null,
    };
    return @intCast(if (params_struct) |struct_node| tree.structTypeLiteral(struct_node).?.fields.len else params.len);
}
