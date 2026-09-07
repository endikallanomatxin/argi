const std = @import("std");
const syn = @import("../3_syntax/syntax_tree.zig");
const file_bindings = @import("file_bindings.zig");
const lexical_tables = @import("global_lexical.zig");
const semantic_strings = @import("semantic_strings.zig");

pub const ModuleDeclId = enum(u32) { _ };
/// Module-local identity of an unresolved lookup.
pub const ModuleTypeRefId = enum(u32) { _ };
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
    resolved_declaration: ?ModuleDeclId = null,
};

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
        for (graph.declarationsNamed(graph.text(reference.name))) |declaration_id| {
            switch (graph.declaration(declaration_id).kind) {
                .type, .abstract_type => {
                    reference.resolved_declaration = declaration_id;
                    break;
                },
                else => {},
            }
        }
    }
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
