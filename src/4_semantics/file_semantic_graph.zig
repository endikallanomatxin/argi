const std = @import("std");
const syn = @import("../3_syntax/syntax_tree.zig");
const file_bindings = @import("file_bindings.zig");
const file_strings = @import("file_strings.zig");

pub const FileDeclId = enum(u32) { _ };
/// File-local identity of an unresolved lookup, including names from this file.
pub const FileTypeRefId = enum(u32) { _ };
pub const StringRange = file_strings.StringRange;

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
    // Temporary bridge to GlobalSema while expression lowering is migrated.
    // This is local to the owning file, never a program SourceDb identity.
    syntax_node: syn.NodeIndex,
};

/// File-local declaration discovery. Records own their spelling and use only
/// dense local identities. No module visibility, overload choice, type identity
/// or import path resolution is decided here: all depend on the global world.
///
/// Expression bodies still use the syntax bridge during migration. Consequently
/// this initial representation is not yet a standalone persistent cache artifact.
pub const FileSemanticGraph = struct {
    declarations: std.ArrayList(Declaration) = .empty,
    strings: std.ArrayList(u8) = .empty,
    lexical: file_bindings.FileBindings = .{},
    type_references: std.ArrayList(TypeReference) = .empty,
    import_references: std.ArrayList(ImportReference) = .empty,

    pub fn deinit(self: *FileSemanticGraph, allocator: std.mem.Allocator) void {
        self.declarations.deinit(allocator);
        self.strings.deinit(allocator);
        self.lexical.deinit(allocator);
        self.type_references.deinit(allocator);
        self.import_references.deinit(allocator);
        self.* = .{};
    }

    pub fn declaration(self: *const FileSemanticGraph, id: FileDeclId) Declaration {
        return self.declarations.items[@intFromEnum(id)];
    }

    pub fn text(self: *const FileSemanticGraph, range: StringRange) []const u8 {
        return self.strings.items[range.start..][0..range.len];
    }

    pub fn storageBytes(self: *const FileSemanticGraph) usize {
        return self.declarations.items.len * @sizeOf(Declaration) + self.strings.items.len + self.lexical.storageBytes() +
            self.type_references.items.len * @sizeOf(TypeReference) +
            self.import_references.items.len * @sizeOf(ImportReference);
    }

    fn addString(self: *FileSemanticGraph, allocator: std.mem.Allocator, value: []const u8) !StringRange {
        return file_strings.append(&self.strings, allocator, value);
    }
};

/// This entrypoint deliberately has no source database, filesystem, global
/// scope, or other file graphs. Adding files cannot change its answers.
pub fn semantizeFile(allocator: std.mem.Allocator, tree: *const syn.FileSyntaxTree, source: []const u8) !FileSemanticGraph {
    var graph: FileSemanticGraph = .{};
    errdefer graph.deinit(allocator);
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
            return error.FileSemanticGraphTooLarge;
        const range = try graph.addString(allocator, name);
        try graph.declarations.append(allocator, .{
            .kind = kind,
            .name = range,
            .source_offset = tree.location(node).offset,
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
    graph.lexical = try file_bindings.build(allocator, tree, source, &graph.strings);
    return graph;
}
