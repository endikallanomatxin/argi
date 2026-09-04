const std = @import("std");
const diagnostic = @import("../1_base/diagnostic.zig");
const source_files = @import("../1_base/source_files.zig");
const tokenizer = @import("../2_tokens/tokenizer.zig");
const syntax_tree = @import("syntax_tree.zig");
const syntaxer = @import("syntaxer.zig");
const legacy_syntaxer = @import("syntaxer_legacy.zig");

fn parseTestFile(path: []const u8) !syntax_tree.SyntaxFile {
    const source = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, std.testing.allocator, .limited(4 * 1024 * 1024));
    defer std.testing.allocator.free(source);
    const files = [_]source_files.SourceFile{.{ .path = path, .code = source }};
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var diagnostics = diagnostic.Diagnostics.init(&allocator, &files);
    defer diagnostics.deinit();

    var tokenizer_context = tokenizer.Tokenizer.init(allocator, &diagnostics, source, diagnostics.source_db.fileId(0));
    _ = try tokenizer_context.tokenize();
    const tokens = try tokenizer_context.takeTokens();
    var legacy = legacy_syntaxer.Syntaxer.init(allocator, tokens, source, &diagnostics);
    const legacy_roots = try legacy.parse();

    var compact = try syntaxer.Syntaxer.init(std.testing.allocator, tokens, source, &diagnostics);
    defer compact.deinit();
    const tree = try compact.parse();
    try std.testing.expect(!diagnostics.hasErrors());
    try std.testing.expectEqual(legacy_roots.len, tree.roots.len);
    return tree;
}

fn expectTags(path: []const u8, expected: []const syntax_tree.Node.Tag) !void {
    var tree = try parseTestFile(path);
    defer tree.deinit(std.testing.allocator);
    const tags = tree.nodes.items(.tag);
    for (expected) |tag| {
        if (std.mem.indexOfScalar(syntax_tree.Node.Tag, tags, tag) == null) {
            std.debug.print("compact tree for {s} is missing {s}\n", .{ path, @tagName(tag) });
            return error.TestExpectedEqual;
        }
    }
}

test "compact syntaxing preserves representative structures" {
    var minimal = try parseTestFile("tests/feature_tests/basics/01_minimal_main/main.rg");
    defer minimal.deinit(std.testing.allocator);
    const function = minimal.functionDeclaration(minimal.roots[0]).?;
    try std.testing.expectEqual(@as(usize, 0), minimal.structTypeLiteral(function.input).?.fields.len);
    try std.testing.expectEqual(@as(usize, 1), minimal.structTypeLiteral(function.output).?.fields.len);
    try std.testing.expectEqual(@as(usize, 1), minimal.codeBlock(function.body.?).?.statements.len);

    var control_flow = try parseTestFile("tests/feature_tests/control_flow/14_for_mut_borrowed_dynamic_array/main.rg");
    defer control_flow.deinit(std.testing.allocator);
    try std.testing.expect(std.mem.indexOfScalar(syntax_tree.Node.Tag, control_flow.nodes.items(.tag), .for_mut_borrow) != null);
    try std.testing.expect(std.mem.indexOfScalar(syntax_tree.Node.Tag, control_flow.nodes.items(.tag), .if_statement) != null);

    var choices = try parseTestFile("tests/feature_tests/types/39_inferred_errable_direct_error/main.rg");
    defer choices.deinit(std.testing.allocator);
    try std.testing.expect(std.mem.indexOfScalar(syntax_tree.Node.Tag, choices.nodes.items(.tag), .match_statement) != null);
}

test "compact syntaxing matches legacy roots for positive feature programs" {
    var root = try std.Io.Dir.cwd().openDir(std.testing.io, ".", .{ .iterate = true });
    defer root.close(std.testing.io);
    var feature_root = try root.openDir(std.testing.io, "tests/feature_tests", .{ .iterate = true });
    defer feature_root.close(std.testing.io);

    var category_iterator = feature_root.iterate();
    while (try category_iterator.next(std.testing.io)) |category| {
        if (category.kind != .directory) continue;
        const category_path = try std.fmt.allocPrint(std.testing.allocator, "tests/feature_tests/{s}", .{category.name});
        defer std.testing.allocator.free(category_path);
        var category_dir = try root.openDir(std.testing.io, category_path, .{ .iterate = true });
        defer category_dir.close(std.testing.io);
        var case_iterator = category_dir.iterate();
        while (try case_iterator.next(std.testing.io)) |case_entry| {
            if (case_entry.kind != .directory or std.mem.indexOfScalar(u8, case_entry.name, 'X') != null) continue;
            const main_path = try std.fmt.allocPrint(std.testing.allocator, "{s}/{s}/main.rg", .{ category_path, case_entry.name });
            defer std.testing.allocator.free(main_path);
            root.access(std.testing.io, main_path, .{}) catch |err| switch (err) {
                error.FileNotFound => continue,
                else => return err,
            };
            var tree = parseTestFile(main_path) catch |err| {
                std.debug.print("compact syntaxing failed for {s}: {s}\n", .{ main_path, @errorName(err) });
                return err;
            };
            tree.deinit(std.testing.allocator);
        }
    }
}

test "compact syntaxing preserves adversarial grammar distinctions" {
    try expectTags("tests/feature_tests/basics/14_get_and_set_index_operators/main.rg", &.{
        .function_declaration,
        .index_access,
        .index_assignment,
    });
    try expectTags("tests/feature_tests/functions/10_pipe_generic_explicit/main.rg", &.{
        .function_call,
        .pipe_expression,
    });
    try expectTags("tests/feature_tests/types/17_generic_type_initializer_from_init/main.rg", &.{.generic_type_instantiation});
    try expectTags("tests/feature_tests/functions/13_mixed_function_call/main.rg", &.{
        .struct_value_literal,
        .positional_value_field,
        .struct_value_field,
    });
    try expectTags("tests/feature_tests/io/02_reached_output_stream/main.rg", &.{
        .reach_directive,
        .reach_alternative,
    });
    try expectTags("tests/feature_tests/control_flow/04_for_dynamic_array/main.rg", &.{.for_value});
    try expectTags("tests/feature_tests/control_flow/13_for_borrowed_array/main.rg", &.{.for_borrow});
    try expectTags("tests/feature_tests/control_flow/14_for_mut_borrowed_dynamic_array/main.rg", &.{.for_mut_borrow});
    try expectTags("tests/feature_tests/types/07_choice_match_payload_binding/main.rg", &.{
        .choice_type_literal,
        .choice_type_variant,
        .choice_literal,
        .match_statement,
        .match_case_value,
    });
    try expectTags("tests/feature_tests/types/29_match_borrowed_payload/main.rg", &.{.match_case_borrow});
    try expectTags("tests/feature_tests/types/30_match_mut_borrowed_payload/main.rg", &.{.match_case_mut_borrow});
    try expectTags("tests/feature_tests/types/31_match_move_payload/main.rg", &.{.match_case_move});
    try expectTags("tests/feature_tests/types/38_inferred_errable_from_propagation/main.rg", &.{
        .inferred_errable_type,
        .error_propagation,
    });
    try expectTags("tests/feature_tests/types/41_nullable_sugar/main.rg", &.{.nullable_type});
    try expectTags("tests/feature_tests/control_flow/15_logical_and_or/main.rg", &.{
        .pointer_type_mut,
        .address_of_mut,
        .dereference,
    });
}
