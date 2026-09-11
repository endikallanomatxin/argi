const std = @import("std");
const graph_mod = @import("graph.zig");
const entities = @import("entities.zig");
const writer_mod = @import("writer.zig");

/// Consume import syntax at the ModuleSema boundary and retain only the
/// semantic alias relation plus source provenance. GlobalSema never needs to
/// recover an alias by comparing syntax-node/source-offset windows again.
pub fn lower(
    allocator: std.mem.Allocator,
    graph: *graph_mod.ModuleSemanticGraph,
    files: []const graph_mod.FileInput,
) !u32 {
    var writer = writer_mod.Writer.init(allocator, graph);
    var count: u32 = 0;
    for (graph.declarations.items, 0..) |declaration, raw| {
        if (declaration.kind != .import_alias) continue;
        if (declaration.module_file_index >= files.len) return error.InvalidModuleFileIndex;
        const file = files[declaration.module_file_index];
        const declaration_node = graph_mod.declarationSyntaxNode(files, declaration) orelse return error.InvalidImportAlias;
        const symbol = file.tree.symbolDeclaration(declaration_node) orelse return error.InvalidImportAlias;
        const value_node = symbol.value orelse return error.InvalidImportAlias;
        const import_statement = file.tree.importStatement(value_node) orelse return error.InvalidImportAlias;
        const path_text = file.tree.tokenTextFromSource(file.source, import_statement.path_token);
        try graph.semantic.module_aliases.append(allocator, .{
            .declaration = @enumFromInt(@as(u32, @intCast(raw))),
            .path = try writer.addString(path_text),
            .source = .{
                .file_index = declaration.module_file_index,
                .offset = file.tree.tokenLocation(import_statement.path_token).offset,
            },
        });
        count += 1;
    }
    return count;
}

test "module alias relation is an indexed semantic entity" {
    try std.testing.expect(@sizeOf(entities.ModuleAlias) <= 20);
}
