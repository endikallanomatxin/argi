const std = @import("std");
const diagnostic = @import("../1_base/diagnostic.zig");
const source_db = @import("../1_base/source_db.zig");
const source_files = @import("../1_base/source_files.zig");
const syn = @import("../3_syntax/syntax_tree.zig");
const syntaxer = @import("../3_syntax/syntaxer.zig");
const tokenizer = @import("../2_tokens/tokenizer.zig");
const module_graph = @import("module_semantic_graph.zig");
const global_builder = @import("global_semantic_graph_builder.zig");

fn parseSource(allocator: std.mem.Allocator, source: []const u8, file_id: source_db.FileId) !syn.FileSyntaxTree {
    const files = [_]source_files.SourceFile{ .{ .path = "a.rg", .code = source }, .{ .path = "b.rg", .code = source } };
    var diagnostics = diagnostic.Diagnostics.init(&allocator, &files);
    defer diagnostics.deinit();
    var tokenizer_context = tokenizer.Tokenizer.init(allocator, &diagnostics, source, file_id);
    defer tokenizer_context.deinit();
    _ = try tokenizer_context.tokenize();
    var context = syntaxer.Syntaxer.initFile(allocator, syn.FileSyntaxTree.initOwnedTokens(file_id, tokenizer_context.takeTokens()), source, &diagnostics);
    defer context.deinit();
    return try context.parse();
}

test "module semantic graph owns declarations from all direct files" {
    const allocator = std.testing.allocator;
    const first_source = "Point : Type = ()\n";
    const second_source = "distance(.point: Point) -> () := {}\n";
    var first = try parseSource(allocator, first_source, @enumFromInt(0));
    defer first.deinit(allocator);
    var second = try parseSource(allocator, second_source, @enumFromInt(1));
    defer second.deinit(allocator);
    var graph = try module_graph.build(allocator, "geometry", &.{
        .{ .file_index = 0, .tree = &first, .source = first_source },
        .{ .file_index = 1, .tree = &second, .source = second_source },
    });
    defer graph.deinit(allocator);

    try std.testing.expectEqualStrings("geometry", graph.module_dir);
    try std.testing.expectEqual(@as(usize, 2), graph.file_offsets.items.len);
    try std.testing.expectEqual(@as(usize, 2), graph.declarations.items.len);
    try std.testing.expectEqualStrings("Point", graph.text(graph.declarations.items[0].name));
    try std.testing.expectEqualStrings("distance", graph.text(graph.declarations.items[1].name));
    try std.testing.expectEqual(@as(u32, 0), graph.declarations.items[0].module_file_index);
    try std.testing.expectEqual(@as(u32, 1), graph.declarations.items[1].module_file_index);
    var found_point = false;
    for (graph.type_references.items) |reference| {
        if (std.mem.eql(u8, graph.text(reference.name), "Point")) found_point = true;
    }
    try std.testing.expect(found_point);
}

test "global builder consumes module graphs and preserves file provenance" {
    const allocator = std.testing.allocator;
    const source = "value := 1\n";
    var first = try parseSource(allocator, source, @enumFromInt(0));
    defer first.deinit(allocator);
    var second = try parseSource(allocator, source, @enumFromInt(1));
    defer second.deinit(allocator);
    var modules = [_]module_graph.ModuleSemanticGraph{
        try module_graph.build(allocator, "one", &.{.{ .file_index = 0, .tree = &first, .source = source }}),
        try module_graph.build(allocator, "two", &.{.{ .file_index = 1, .tree = &second, .source = source }}),
    };
    defer for (&modules) |*module| module.deinit(allocator);
    var merged = try global_builder.mergeModuleGraphs(allocator, &modules, 2);
    defer merged.deinit(allocator);

    const second_id = merged.globalDeclId(1, @enumFromInt(0));
    try std.testing.expectEqualStrings("value", merged.text(merged.declaration(second_id).name));
    try std.testing.expectEqual(@as(u32, 1), merged.declaration(second_id).file_index);
    try std.testing.expectEqual(@as(u32, 1), merged.file_offsets.items[1].declaration_base);
}
