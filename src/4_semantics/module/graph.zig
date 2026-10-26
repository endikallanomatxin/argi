const std = @import("std");
const syn = @import("../../3_syntax/syntax_tree.zig");
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
pub const FieldRange = struct { start: u32, len: u32 };
pub const FunctionInterface = struct { declaration: ModuleDeclId, input: FieldRange, output: FieldRange };
pub const DeclarationKind = primitives.DeclarationKind;

pub const Declaration = struct {
    kind: DeclarationKind,
    name: StringRange,
    source_offset: u32,
    module_file_index: u32,
    // Construction-time syntax provenance used while lowering declaration bodies.
    type_id: ?ModuleTypeId = null,
    underlying_type: ?ModuleTypeId = null,
    function_id: ?ModuleFunctionId = null,
    struct_fields: ?FieldRange = null,
    choice_variants: ?FieldRange = null,
    generic_parameter_count: ?u32 = null,
};

pub const FileOffsets = struct {
    path: StringRange,
    content_hash: ?u64 = null,
    declaration_base: u32,
    declaration_count: u32,
    type_reference_base: u32,
    type_reference_count: u32,
};

pub const Symbol = struct {
    name: StringRange,
    declarations: DeclarationRange,
};

/// Closed condition recipe retained independently of FileSyntaxTree. Source
/// offsets identify its directive in the loader's immutable selection plan.
pub const ModuleCondition = struct {
    source: primitives.SourceRef,
    expression: @import("parameterized/ir.zig").ParameterizedNodeId,
};

/// Compact semantic storage owned by one module directory. Source-file indices
/// and source offsets in construction tables are provenance only. Durable
/// bodies and semantic identities live in `semantic` using Module* IDs.
pub const ModuleSemanticGraph = struct {
    target: @import("../../1_base/target.zig").Config = .{},
    module_dir: []const u8 = "",
    is_bundled_core: bool = false,
    declarations: std.ArrayList(Declaration) = .empty,
    /// Compiler-generated declarations form a trailing partition, outside the
    /// source-file partitions and public symbol index. Each retains source
    /// provenance in its ordinary declaration record.
    generated_declaration_count: u32 = 0,
    symbols: std.ArrayList(Symbol) = .empty,
    symbol_declarations: std.ArrayList(ModuleDeclId) = .empty,
    functions: std.ArrayList(FunctionInterface) = .empty,
    strings: std.ArrayList(u8) = .empty,
    type_references: std.ArrayList(TypeReference) = .empty,
    file_offsets: std.ArrayList(FileOffsets) = .empty,
    semantic: module_storage.Storage = .{},
    conditions: std.ArrayList(ModuleCondition) = .empty,

    pub fn deinit(self: *ModuleSemanticGraph, allocator: std.mem.Allocator) void {
        allocator.free(self.module_dir);
        self.declarations.deinit(allocator);
        self.symbols.deinit(allocator);
        self.symbol_declarations.deinit(allocator);
        self.functions.deinit(allocator);
        self.strings.deinit(allocator);
        self.type_references.deinit(allocator);
        self.file_offsets.deinit(allocator);
        self.semantic.deinit(allocator);
        self.conditions.deinit(allocator);
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
        return self.module_dir.len + self.declarations.items.len * @sizeOf(Declaration) +
            self.symbols.items.len * @sizeOf(Symbol) + self.symbol_declarations.items.len * @sizeOf(ModuleDeclId) +
            self.functions.items.len * @sizeOf(FunctionInterface) +
            self.strings.items.len +
            self.type_references.items.len * @sizeOf(TypeReference) +
            self.file_offsets.items.len * @sizeOf(FileOffsets) +
            self.conditions.items.len * @sizeOf(ModuleCondition) + self.semantic.storageBytes();
    }

    fn addString(self: *ModuleSemanticGraph, allocator: std.mem.Allocator, value: []const u8) !StringRange {
        return semantic_strings.append(&self.strings, allocator, value);
    }
};

pub const FileInput = struct {
    diagnostics: ?*@import("../../1_base/diagnostic.zig").Diagnostics = null,
    path: []const u8,
    tree: *const syn.FileSyntaxTree,
    source: []const u8,
    is_bundled_core: bool = false,
    is_entry: bool = false,
};

/// Construction-only lookup from durable source provenance back into syntax.
/// Completed ModuleSG declarations keep source identity, not AST identity.
pub fn declarationSyntaxNode(files: []const FileInput, declaration: Declaration) ?syn.NodeIndex {
    if (declaration.module_file_index >= files.len) return null;
    const tree = files[declaration.module_file_index].tree;
    for (tree.roots) |node| {
        if (tree.location(node).offset == declaration.source_offset) return node;
    }
    for (tree.roots) |root| {
        const conformance = tree.contractConformance(root) orelse continue;
        const members = conformance.implementation_members;
        for (tree.structTypeLiteral(members).?.fields) |field| {
            const value = tree.structTypeField(field).?.default_value orelse continue;
            if (tree.functionDeclaration(value) != null and tree.location(value).offset == declaration.source_offset) return value;
        }
    }
    return null;
}

pub fn pointerMutabilityFromSyntax(value: syn.PointerMutability) primitives.PointerMutability {
    return switch (value) {
        .read_only => .read_only,
        .read_write => .read_write,
    };
}

pub fn mutabilityFromSyntax(value: syn.Mutability) primitives.Mutability {
    return switch (value) {
        .constant => .constant,
        .variable => .variable,
    };
}

pub fn forModeFromSyntax(value: syn.ForMode) primitives.ForMode {
    return switch (value) {
        .move => .move,
        .value => .value,
        .borrow => .borrow,
        .mut_borrow => .mut_borrow,
    };
}

pub fn matchCaseModeFromSyntax(value: syn.MatchCaseMode) primitives.MatchCaseMode {
    return switch (value) {
        .value => .value,
        .borrow => .borrow,
        .mut_borrow => .mut_borrow,
        .move => .move,
    };
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
                // Selected source fragments retain the original buffer's version.
                .content_hash = if (file.diagnostics) |diagnostics| blk: {
                    if (@intFromEnum(file.tree.file_id) < diagnostics.source_db.files.len) {
                        const original = diagnostics.source_db.get(file.tree.file_id);
                        if (std.mem.eql(u8, original.path, file.path)) break :blk original.content_hash;
                    }
                    break :blk @import("../../1_base/source_db.zig").contentHash(file.source);
                } else @import("../../1_base/source_db.zig").contentHash(file.source),
                .declaration_base = declaration_base,
                .declaration_count = @intCast(self.graph.declarations.items.len - declaration_base),
                .type_reference_base = type_reference_base,
                .type_reference_count = @intCast(self.graph.type_references.items.len - type_reference_base),
            });
        }
        try buildSymbolIndex(self.allocator, &self.graph);
        try predeclareTypes(self.allocator, &self.graph);
        resolveModuleTypeReferences(&self.graph);
        const result = self.graph;
        self.graph = .{};
        return result;
    }
};

/// Starts semantic construction at the language's module boundary. The helper
/// performs discovery file by file, but writes every durable result directly
/// into module-owned tables; there is no intermediate file semantic artifact.
pub fn build(allocator: std.mem.Allocator, module_dir: []const u8, files: []const FileInput) !ModuleSemanticGraph {
    return buildForTarget(allocator, module_dir, files, .{});
}

pub fn buildForTarget(allocator: std.mem.Allocator, module_dir: []const u8, files: []const FileInput, target: @import("../../1_base/target.zig").Config) !ModuleSemanticGraph {
    var builder = try ModuleSemanticGraphBuilder.init(allocator, module_dir);
    errdefer builder.deinit();
    builder.graph.target = target;
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
        if (builtinFromName(graph, graph.text(reference.name))) |builtin| {
            reference.resolution = .{ .builtin = builtin };
            continue;
        }
        for (graph.declarationsNamed(graph.text(reference.name))) |declaration_id| {
            switch (graph.declaration(declaration_id).kind) {
                .type, .contract_type => {
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
        .type, .contract_type => {
            if (graph.semantic.types.items.len >= std.math.maxInt(u32)) return error.ModuleSemanticGraphTooLarge;
            declaration.type_id = @enumFromInt(@as(u32, @intCast(graph.semantic.types.items.len)));
            const id: ModuleDeclId = @enumFromInt(@as(u32, @intCast(index)));
            try graph.semantic.types.append(allocator, .{ .resolved = if (declaration.kind == .contract_type or declaration.generic_parameter_count != null)
                .{ .definition = id }
            else
                .{ .declared = id } });
        },
        else => {},
    };
}

fn builtinFromName(graph: *const ModuleSemanticGraph, name: []const u8) ?BuiltinType {
    return primitives.builtinTypeNamedForTarget(name, graph.target.stdTarget());
}

fn discoverFile(allocator: std.mem.Allocator, graph: *ModuleSemanticGraph, input: FileInput, module_file_index: u32) !void {
    const tree = input.tree;
    const source = input.source;
    for (tree.roots) |node| {
        const kind: DeclarationKind = switch (tree.tag(node)) {
            .symbol_declaration_constant, .symbol_declaration_variable => blk: {
                if (tree.functionDeclaration(node) != null) break :blk .function;
                if (tree.typeDeclaration(node) != null) break :blk .type;
                const value = tree.symbolDeclaration(node).?.value;
                break :blk if (value != null and tree.tag(value.?) == .import_statement) .import_alias else .binding;
            },
            .contract_declaration => .contract_type,
            .type_declaration, .c_struct_declaration, .c_incomplete_declaration, .c_enum_declaration, .c_union_declaration, .c_function_pointer_declaration => .type,
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
    for (tree.roots) |root| {
        const conformance = tree.contractConformance(root) orelse continue;
        const members = conformance.implementation_members;
        for (tree.structTypeLiteral(members).?.fields) |field| {
            const value = tree.structTypeField(field).?.default_value orelse continue;
            if (tree.functionDeclaration(value) == null) continue;
            // Implementation bodies have private declaration identities and
            // never enter a source-visible global operation family.
            const name = try std.fmt.allocPrint(allocator, "_implement${d}${d}${s}", .{ module_file_index, tree.location(root).offset, tree.tokenTextFromSource(source, tree.mainToken(value)) });
            defer allocator.free(name);
            try graph.declarations.append(allocator, .{
                .kind = .function,
                .name = try graph.addString(allocator, name),
                .source_offset = tree.location(value).offset,
                .module_file_index = module_file_index,
                .generic_parameter_count = genericParameterCount(tree, value),
            });
        }
    }
    // Syntax-node order permits binary lookup during ModuleSema construction
    // without retaining a dense map for every expression node.
    for (tree.nodes.items(.tag), 0..) |tag, index| {
        if (tag != .type_name) continue;
        const node: syn.NodeIndex = @enumFromInt(@as(u32, @intCast(index)));
        const name = tree.syntaxType(node).?.name;
        const spelling = try graph.addString(allocator, tree.tokenTextFromSource(source, name.name_token));
        const qualifier = if (name.qualifier_token) |token| blk: {
            const path = try @import("qualified_path.zig").symbolic(allocator, tree, source, token, name.name_token);
            defer allocator.free(path);
            break :blk try graph.addString(allocator, path);
        } else null;
        try graph.type_references.append(allocator, .{
            .name = spelling,
            .qualifier = qualifier,
            .source_offset = tree.tokenLocation(name.qualifier_token orelse name.name_token).offset,
        });
    }
}

fn genericParameterCount(tree: *const syn.FileSyntaxTree, node: syn.NodeIndex) ?u32 {
    const value = tree.definitionValue(node) orelse return null;
    const definition = tree.parameterizedDefinition(value) orelse return null;
    return @intCast(definition.parameters.len);
}
