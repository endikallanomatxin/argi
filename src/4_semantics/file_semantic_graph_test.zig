const std = @import("std");
const diagnostic = @import("../1_base/diagnostic.zig");
const source_db = @import("../1_base/source_db.zig");
const source_files = @import("../1_base/source_files.zig");
const syn = @import("../3_syntax/syntax_tree.zig");
const syntaxer = @import("../3_syntax/syntaxer.zig");
const tokenizer = @import("../2_tokens/tokenizer.zig");
const graph_mod = @import("file_semantic_graph.zig");

fn parseSource(allocator: std.mem.Allocator, source: []const u8, file_id: source_db.FileId) !syn.FileSyntaxTree {
    const files = [_]source_files.SourceFile{
        .{ .path = "placeholder.rg", .code = "" },
        .{ .path = "source.rg", .code = source },
    };
    var diagnostics = diagnostic.Diagnostics.init(&allocator, &files);
    defer diagnostics.deinit();

    var tokenizer_context = tokenizer.Tokenizer.init(allocator, &diagnostics, source, file_id);
    _ = try tokenizer_context.tokenize();
    const owned_tokens = tokenizer_context.takeTokens();
    var compact = syntaxer.Syntaxer.initFile(
        allocator,
        syn.FileSyntaxTree.initOwnedTokens(file_id, owned_tokens),
        source,
        &diagnostics,
    );
    defer compact.deinit();
    const tree = try compact.parse();
    try std.testing.expect(!diagnostics.hasErrors());
    return tree;
}

test "file semantic graph classifies file declarations" {
    const source_text =
        "..out_of_memory\n" ++
        "dependency := #import(\"./dependency\")\n" ++
        "constant := 1\n" ++
        "variable :: Int32 = 2\n" ++
        "Record : Type = ()\n" ++
        "Capability : Abstract = ()\n" ++
        "compute() -> () := {}\n" ++
        "test check() -> !() := {}\n";
    const allocator = std.testing.allocator;
    const source = try allocator.dupe(u8, source_text);
    var tree = try parseSource(allocator, source, @enumFromInt(1));
    defer tree.deinit(allocator);

    var graph = try graph_mod.semantizeFile(allocator, &tree, source);
    defer graph.deinit(allocator);
    allocator.free(source);

    const expected = [_]struct { kind: graph_mod.DeclarationKind, name: []const u8 }{
        .{ .kind = .choice_option, .name = "out_of_memory" },
        .{ .kind = .import_alias, .name = "dependency" },
        .{ .kind = .binding, .name = "constant" },
        .{ .kind = .binding, .name = "variable" },
        .{ .kind = .type, .name = "Record" },
        .{ .kind = .abstract_type, .name = "Capability" },
        .{ .kind = .function, .name = "compute" },
        .{ .kind = .test_function, .name = "check" },
    };
    try std.testing.expectEqual(expected.len, graph.declarations.items.len);
    for (expected, 0..) |wanted, index| {
        const declaration = graph.declaration(@enumFromInt(index));
        try std.testing.expectEqual(wanted.kind, declaration.kind);
        try std.testing.expectEqualStrings(wanted.name, graph.text(declaration.name));
        try std.testing.expect(@intFromEnum(declaration.syntax_node) < tree.nodes.len);
    }
}

test "file semantic graph owns declaration names after source and syntax release" {
    const allocator = std.testing.allocator;
    const source = try allocator.dupe(u8, "kept_name := 42\nworker() -> () := {}\n");
    var tree = try parseSource(allocator, source, @enumFromInt(1));
    var graph = try graph_mod.semantizeFile(allocator, &tree, source);
    tree.deinit(allocator);
    allocator.free(source);
    defer graph.deinit(allocator);

    try std.testing.expectEqualStrings("kept_name", graph.text(graph.declaration(@enumFromInt(0)).name));
    try std.testing.expectEqualStrings("worker", graph.text(graph.declaration(@enumFromInt(1)).name));
}

test "file semantic graph does not depend on SourceDb file identity" {
    const allocator = std.testing.allocator;
    const source_text = "value := 1\nrun(.value: Int32) -> () := {}\n";
    const first_source = try allocator.dupe(u8, source_text);
    const second_source = try allocator.dupe(u8, source_text);
    var first_tree = try parseSource(allocator, first_source, @enumFromInt(0));
    var second_tree = try parseSource(allocator, second_source, @enumFromInt(1));
    defer first_tree.deinit(allocator);
    defer second_tree.deinit(allocator);

    var first = try graph_mod.semantizeFile(allocator, &first_tree, first_source);
    var second = try graph_mod.semantizeFile(allocator, &second_tree, second_source);
    defer first.deinit(allocator);
    defer second.deinit(allocator);
    allocator.free(first_source);
    allocator.free(second_source);

    try std.testing.expectEqual(first.declarations.items.len, second.declarations.items.len);
    try std.testing.expectEqualSlices(u8, first.strings.items, second.strings.items);
    try std.testing.expectEqualDeep(first.type_references.items, second.type_references.items);
    try std.testing.expectEqualDeep(first.lexical.bindings.items, second.lexical.bindings.items);
    try std.testing.expectEqualDeep(first.lexical.references.items, second.lexical.references.items);
    for (first.declarations.items, second.declarations.items) |left, right| {
        try std.testing.expectEqual(left.kind, right.kind);
        try std.testing.expectEqual(left.name, right.name);
        try std.testing.expectEqual(left.source_offset, right.source_offset);
        try std.testing.expectEqual(left.syntax_node, right.syntax_node);
    }
}

test "file semantic graph cleans up when declaration storage allocation fails" {
    const allocator = std.testing.allocator;
    const source = "value := 1\nread(.x: Int32) -> (.result: Int32) := {\n y := x\n return y\n}\n";
    var tree = try parseSource(allocator, source, @enumFromInt(1));
    defer tree.deinit(allocator);
    try std.testing.checkAllAllocationFailures(allocator, lowerWithAllocator, .{ &tree, source });
}

fn lowerWithAllocator(allocator: std.mem.Allocator, tree: *const syn.FileSyntaxTree, source: []const u8) !void {
    var graph = try graph_mod.semantizeFile(allocator, tree, source);
    defer graph.deinit(allocator);
}

test "file semantic graph preserves normalized operator names" {
    const allocator = std.testing.allocator;
    const source =
        "operator +(.left: Int32, .right: Int32) -> (.sum: Int32) := {}\n" ++
        "operator ==(.left: Int32, .right: Int32) -> (.same: Bool) := {}\n" ++
        "operator get[](.self: &Int32, .index: Int32) -> (.value: Int32) := {}\n";
    var tree = try parseSource(allocator, source, @enumFromInt(1));
    defer tree.deinit(allocator);
    var graph = try graph_mod.semantizeFile(allocator, &tree, source);
    defer graph.deinit(allocator);

    const expected = [_][]const u8{ "operator +", "operator ==", "operator get[]" };
    try std.testing.expectEqual(expected.len, graph.declarations.items.len);
    for (expected, 0..) |name, index| {
        try std.testing.expectEqual(.function, graph.declaration(@enumFromInt(index)).kind);
        try std.testing.expectEqualStrings(name, graph.text(graph.declaration(@enumFromInt(index)).name));
    }
}

test "file semantic graph resolves lexical values but defers module-shaped access" {
    const allocator = std.testing.allocator;
    const source = "read(.x: Int32) -> (.result: Int32) := {\n y := x\n return y\n}\n" ++
        "field(.x: Int32) -> (.result: Int32) := {\n return x.member\n}\n";
    var tree = try parseSource(allocator, source, @enumFromInt(1));
    defer tree.deinit(allocator);
    var graph = try graph_mod.semantizeFile(allocator, &tree, source);
    defer graph.deinit(allocator);
    const lexical = &graph.lexical;
    try std.testing.expectEqual(@as(usize, 2), lexical.references.items.len);
    try std.testing.expectEqualStrings("x", lexical.text(lexical.references.items[0].name));
    try std.testing.expectEqualStrings("y", lexical.text(lexical.references.items[1].name));
    try std.testing.expectEqualStrings("x", lexical.text(lexical.bindings.items[@intFromEnum(lexical.references.items[0].binding)].name));
    try std.testing.expectEqualStrings("y", lexical.text(lexical.bindings.items[@intFromEnum(lexical.references.items[1].binding)].name));
    var pending_field = false;
    for (lexical.deferred_nodes.items) |node| {
        if (tree.tag(node) == .struct_field_access) pending_field = true;
    }
    try std.testing.expect(pending_field);
}

test "file semantic graph owns unresolved qualified type references" {
    const allocator = std.testing.allocator;
    const source = try allocator.dupe(u8, "read(.point: geometry.Point) -> (.result: Int32) := {}\n");
    var tree = try parseSource(allocator, source, @enumFromInt(1));
    var graph = try graph_mod.semantizeFile(allocator, &tree, source);
    defer graph.deinit(allocator);
    tree.deinit(allocator);
    allocator.free(source);
    try std.testing.expectEqual(@as(usize, 2), graph.type_references.items.len);
    const point = graph.type_references.items[0];
    try std.testing.expectEqualStrings("Point", graph.text(point.name));
    try std.testing.expectEqualStrings("geometry", graph.text(point.qualifier.?));
    const result = graph.type_references.items[1];
    try std.testing.expectEqualStrings("Int32", graph.text(result.name));
    try std.testing.expectEqual(null, result.qualifier);
}
