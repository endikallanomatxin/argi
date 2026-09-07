const std = @import("std");
const syn = @import("../3_syntax/syntax_tree.zig");
const file_bindings = @import("file_bindings.zig");

pub const FileDeclId = enum(u32) { _ };
pub const StringRange = struct { start: u32, len: u32 };

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

    pub fn deinit(self: *FileSemanticGraph, allocator: std.mem.Allocator) void {
        self.declarations.deinit(allocator);
        self.strings.deinit(allocator);
        self.lexical.deinit(allocator);
        self.* = .{};
    }

    pub fn declaration(self: *const FileSemanticGraph, id: FileDeclId) Declaration {
        return self.declarations.items[@intFromEnum(id)];
    }

    pub fn text(self: *const FileSemanticGraph, range: StringRange) []const u8 {
        return self.strings.items[range.start..][0..range.len];
    }

    pub fn storageBytes(self: *const FileSemanticGraph) usize {
        return self.declarations.items.len * @sizeOf(Declaration) + self.strings.items.len + self.lexical.storageBytes();
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
        if (name.len > std.math.maxInt(u32) or graph.strings.items.len > std.math.maxInt(u32) - name.len or graph.declarations.items.len >= std.math.maxInt(u32))
            return error.FileSemanticGraphTooLarge;
        const range: StringRange = .{ .start = @intCast(graph.strings.items.len), .len = @intCast(name.len) };
        try graph.strings.appendSlice(allocator, name);
        try graph.declarations.append(allocator, .{
            .kind = kind,
            .name = range,
            .source_offset = tree.location(node).offset,
            .syntax_node = node,
        });
    }
    graph.lexical = try file_bindings.build(allocator, tree, source);
    return graph;
}
