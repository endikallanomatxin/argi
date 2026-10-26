const std = @import("std");
const diagnostic = @import("../1_base/diagnostic.zig");
const source_files = @import("../1_base/source_files.zig");
const tokenizer = @import("../2_tokens/tokenizer.zig");
const syntax_tree = @import("syntax_tree.zig");
const syntaxer = @import("syntaxer.zig");

fn parseTestFile(path: []const u8) !syntax_tree.FileSyntaxTree {
    const source = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, std.testing.allocator, .limited(4 * 1024 * 1024));
    defer std.testing.allocator.free(source);
    return parseTestSource(path, source);
}

fn parseTestSource(path: []const u8, source: []const u8) !syntax_tree.FileSyntaxTree {
    const files = [_]source_files.SourceFile{.{ .path = path, .code = source }};
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var diagnostics = diagnostic.Diagnostics.init(&allocator, &files);
    defer diagnostics.deinit();

    var error_offset: usize = 0;
    const selected = try @import("../1_base/target_selection.zig").selectSyntax(allocator, source, .{}, &error_offset);
    var tokenizer_context = tokenizer.Tokenizer.init(allocator, &diagnostics, selected, diagnostics.source_db.fileId(0));
    _ = try tokenizer_context.tokenize();
    const tokens = tokenizer_context.takeTokens();

    var compact = try syntaxer.Syntaxer.init(std.testing.allocator, .init(&tokens), source, &diagnostics);
    defer compact.deinit();
    const tree = try compact.parse();
    try std.testing.expect(!diagnostics.hasErrors());
    return tree;
}

test "compact syntaxing binds type and function definition values with their own parameters" {
    const source =
        \\Point := (.x: Float64, .y: Float64 = 0)
        \\Box := <.T: Type> (.value: T)
        \\identity := <.T: Type> (.value: T) -> (.result: T) { result = value }
        \\Alias := Box
    ;
    var tree = try parseTestSource("definitions.rg", source);
    defer tree.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 4), tree.roots.len);
    for (tree.roots) |root| try std.testing.expect(tree.symbolDeclaration(root) != null);
    const point = tree.definitionValue(tree.roots[0]).?;
    try std.testing.expect(tree.structTypeLiteral(point) != null);
    const box = tree.parameterizedDefinition(tree.definitionValue(tree.roots[1]).?).?;
    try std.testing.expectEqual(@as(usize, 1), box.parameters.len);
    try std.testing.expect(tree.parameterList(box.parameters_struct.?) != null);
    try std.testing.expect(tree.structTypeLiteral(box.parameters_struct.?) == null);
    try std.testing.expect(tree.structTypeLiteral(box.value) != null);
    const identity = tree.parameterizedDefinition(tree.definitionValue(tree.roots[2]).?).?;
    const function = tree.functionDefinition(identity.value).?;
    try std.testing.expect(function.body.unwrap() != null);
    try std.testing.expect(tree.functionDeclaration(tree.roots[2]) != null);
    try std.testing.expect(tree.functionDeclaration(identity.value) == null);
    const alias = tree.definitionValue(tree.roots[3]).?;
    try std.testing.expectEqual(syntax_tree.Node.Tag.identifier, tree.tag(alias));
}

test "compact syntaxing specializes values and calls with one angle-list representation" {
    const source =
        \\result := identity<Int32>(.value = 42)
        \\family := Box<Box<Int32>>
        \\qualified := utility.identity<.T: Int32>(.value = 42)
        \\operation := Compare<Int32, Int32>.compare(.left = a, .right = b)
        \\box: Box<Int32>=(.value = 42)
        \\converted := value | convert<.to: UIntNative>(_)
    ;
    var tree = try parseTestSource("specializations.rg", source);
    defer tree.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 6), tree.roots.len);
    const first = tree.functionCall(tree.symbolDeclaration(tree.roots[0]).?.value.?).?;
    try std.testing.expectEqual(syntax_tree.Node.Tag.specialization, tree.tag(first.callee));
    try std.testing.expect(first.specialization_arguments != null);
    try std.testing.expect(tree.specializationArguments(first.specialization_arguments.?) != null);
    try std.testing.expect(tree.structTypeLiteral(first.specialization_arguments.?) == null);
    const family = tree.definitionValue(tree.roots[1]).?;
    try std.testing.expectEqual(syntax_tree.Node.Tag.specialization, tree.tag(family));
    const field = tree.structTypeField(tree.specializationArguments(tree.data(family).node_and_node.second).?.fields[0]).?;
    try std.testing.expectEqual(syntax_tree.Node.Tag.specialization, tree.tag(field.type_node.?));
    const qualified = tree.functionCall(tree.definitionValue(tree.roots[2]).?).?;
    try std.testing.expectEqualStrings("utility", tree.tokenTextFromSource(source, qualified.module_qualifier.?));
    const operation = tree.functionCall(tree.definitionValue(tree.roots[3]).?).?;
    try std.testing.expect(operation.contract_type != null);
    try std.testing.expect(tree.symbolDeclaration(tree.roots[4]).?.value != null);
}

test "compact syntaxing separates comparison syntax from angle specialization without names" {
    const cases = [_]struct { source: []const u8, tag: syntax_tree.Node.Tag }{
        .{ .source = "answer := a < b", .tag = .compare_less },
        .{ .source = "answer := a > b", .tag = .compare_greater },
        .{ .source = "answer := a < b > c", .tag = .compare_greater },
        .{ .source = "answer := a < b + c >= d", .tag = .compare_greater_equal },
        .{ .source = "answer := family<.Flag = [a < b or c >= d]>", .tag = .specialization },
        .{ .source = "answer := a <= b", .tag = .compare_less_equal },
        .{ .source = "answer := a >= b", .tag = .compare_greater_equal },
        .{ .source = "answer := exponent < -4 or exponent >= 16", .tag = .logical_or },
        .{ .source = "answer := a < b > (c)", .tag = .function_call },
        .{ .source = "answer := [a < b] > c", .tag = .compare_greater },
        .{ .source = "answer := family < Int32 >", .tag = .specialization },
        .{ .source = "answer := family<Int32>", .tag = .specialization },
        .{ .source = "answer := family<\nInt32,\nBox<Int32>\n>", .tag = .specialization },
    };
    for (cases) |case| {
        var tree = try parseTestSource("angles.rg", case.source);
        defer tree.deinit(std.testing.allocator);
        const value = tree.symbolDeclaration(tree.roots[0]).?.value.?;
        try std.testing.expectEqual(case.tag, tree.tag(value));
    }
    var sequence = try parseTestSource("comparisons.rg", "a < b\nc < d\ne < f");
    defer sequence.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 3), sequence.roots.len);
}

test "compact syntaxing permits ordinary named input and output types on function values" {
    var tree = try parseTestSource("signatures.rg", "f := Args -> Results { result = x }\ng := <.T: Type> Args -> Results { result = x }\nh := schema.Args -> schema.Results { result = x }\ni := schema.Args<Bool> -> schema.Results<Bool> { result = x }");
    defer tree.deinit(std.testing.allocator);
    for (tree.roots) |root| {
        const value = tree.definitionBody(tree.definitionValue(root).?);
        const definition = tree.functionDefinition(value).?;
        try std.testing.expect(tree.typeReference(definition.input) != null);
        try std.testing.expect(tree.typeReference(definition.output) != null);
    }
}

test "compact syntaxing permits parameterized values in explicit type declarations" {
    var tree = try parseTestSource("families.rg", "Forward: Type = <.T: Type> Original<T>");
    defer tree.deinit(std.testing.allocator);
    try std.testing.expectEqual(syntax_tree.Node.Tag.symbol_declaration_constant, tree.tag(tree.roots[0]));
    const declaration = tree.typeDeclaration(tree.roots[0]).?;
    try std.testing.expectEqual(@as(usize, 1), declaration.generic_params.len);
    try std.testing.expect(tree.typeReference(declaration.value) != null);
}

test "compact syntaxing reports missing angle delimiters and positional separators" {
    try std.testing.expectError(error.ExpectedRightAngle, parseTestSource("missing.rg", "value: Box<Int32 = zeroed()"));
    try std.testing.expectError(error.ExpectedComma, parseTestSource("separator.rg", "value: Pair<Int32 Int64>"));
    try std.testing.expectError(error.ExpectedRightAngle, parseTestSource("missing-named.rg", "value := family<.T: Int32"));
}

test "compact syntaxing rolls back losing specialization syntax under allocation failure" {
    const source = "comparison := a < b + c >= d\nbox: Box<Box<Int32>>=(.value = 42)";
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const base = arena.allocator();
    const files = [_]source_files.SourceFile{.{ .path = "speculation.rg", .code = source }};
    var diagnostics = diagnostic.Diagnostics.init(&base, &files);
    defer diagnostics.deinit();
    var lex = tokenizer.Tokenizer.init(base, &diagnostics, source, diagnostics.source_db.fileId(0));
    _ = try lex.tokenize();
    try std.testing.checkAllAllocationFailures(std.testing.allocator, struct {
        fn run(allocator: std.mem.Allocator, text: []const u8, view: @import("../2_tokens/token.zig").View, owner: *const diagnostic.Diagnostics) !void {
            var messages = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer messages.deinit();
            const temporary = messages.allocator();
            var local = diagnostic.Diagnostics.initBorrowed(&temporary, owner);
            defer local.deinit();
            var parser = try syntaxer.Syntaxer.init(allocator, view, text, &local);
            defer parser.deinit();
            var tree = try parser.parse();
            defer tree.deinit(allocator);
            try std.testing.expectEqual(@as(usize, 2), tree.roots.len);
            try std.testing.expectEqual(@as(usize, 0), local.list.items.len);
            const value = tree.definitionValue(tree.roots[0]).?;
            try std.testing.expectEqual(syntax_tree.Node.Tag.compare_greater_equal, tree.tag(value));
        }
    }.run, .{ source, @import("../2_tokens/token.zig").View.init(&lex.tokens), &diagnostics });
}

test "compact syntaxing represents anonymous compile-time entries independently of calls" {
    const sources = [_][]const u8{
        "#run { calculate() }",
        "answer ::= #run () -> (.result: Int32) { result = calculate(42) }",
        "answer ::= #run (.system: System) -> (.result: Int32) { assume writer ::= $&system.terminal&.stdout\nresult = 42 }",
    };
    for (sources, 0..) |source, index| {
        var tree = try parseTestSource("entry.rg", source);
        defer tree.deinit(std.testing.allocator);
        const node = firstNodeWithTag(&tree, .comptime_entry);
        const entry = tree.comptimeEntry(node).?;
        try std.testing.expectEqual(syntax_tree.Node.Tag.code_block, tree.tag(entry.body));
        try std.testing.expectEqual(index != 0, entry.input != null);
        try std.testing.expectEqual(index != 0, entry.output != null);
        try std.testing.expect(tree.functionCall(node) == null);
        try std.testing.expect(tree.functionDeclaration(node) == null);
        try std.testing.expectEqualStrings("#", tree.tokenTextFromSource(source, tree.mainToken(node)));
        if (entry.input) |input| {
            const fields = tree.structTypeLiteral(input).?.fields;
            try std.testing.expectEqual(@as(usize, if (index == 2) 1 else 0), fields.len);
        }
        if (entry.output) |output|
            try std.testing.expectEqual(@as(usize, 1), tree.structTypeLiteral(output).?.fields.len);
    }
}

test "compact syntaxing rejects superseded compile-time call prefixes" {
    try std.testing.expectError(error.ExpectedLeftBrace, parseTestSource("entry.rg", "#run calculate()"));
    try std.testing.expectError(error.ExpectedLeftBrace, parseTestSource("entry.rg", "#run calculate#(.n = 42)()"));
}

test "compact syntaxing requires a complete compile-time entry signature" {
    try std.testing.expectError(error.ExpectedArrow, parseTestSource("entry.rg", "#run () {}"));
    try std.testing.expectError(error.ExpectedLeftBrace, parseTestSource("entry.rg", "#run () -> () calculate()"));
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

fn firstNodeWithTag(tree: *const syntax_tree.FileSyntaxTree, tag: syntax_tree.Node.Tag) syntax_tree.NodeIndex {
    const index = std.mem.indexOfScalar(syntax_tree.Node.Tag, tree.nodes.items(.tag), tag).?;
    return @enumFromInt(@as(u32, @intCast(index)));
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

test "compact syntaxing preserves generic parameter indices across extra data growth" {
    var tree = try parseTestFile("tests/feature_tests/functions/10_pipe_generic_explicit/main.rg");
    defer tree.deinit(std.testing.allocator);

    const declaration = tree.functionDeclaration(tree.roots[0]).?;
    const generic_struct = tree.parameterList(declaration.generic_params_struct.?).?;
    try std.testing.expectEqual(@as(usize, 1), declaration.generic_params.len);
    try std.testing.expectEqualSlices(syntax_tree.NodeIndex, generic_struct.fields, declaration.generic_params);

    const parameter = tree.structTypeField(declaration.generic_params[0]).?;
    try std.testing.expectEqual(syntax_tree.Node.Tag.type_name, tree.tag(parameter.type_node.?));
}

test "compact syntaxing accepts positive feature programs" {
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
    try expectTags("tests/feature_tests/collections/07_array_index_uint_native/main.rg", &.{
        .index_access,
        .index_assignment,
    });
    try expectTags("tests/feature_tests/functions/10_pipe_generic_explicit/main.rg", &.{
        .function_call,
        .pipe_expression,
    });
    try expectTags("tests/feature_tests/types/17_generic_type_initializer_from_init/main.rg", &.{.specialization});
    try expectTags("tests/feature_tests/functions/13_mixed_function_call/main.rg", &.{
        .struct_value_literal,
        .positional_value_field,
        .struct_value_field,
    });
    try expectTags("tests/feature_tests/io/02_reached_output_stream/main.rg", &.{
        .reach_directive,
        .reach_alternative,
    });
    try expectTags("tests/feature_tests/control_flow/17_for_moving/main.rg", &.{.for_move});
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

test "compact syntax views preserve semantic distinctions" {
    const MatchExpectation = struct { path: []const u8, tag: syntax_tree.Node.Tag, mode: syntax_tree.MatchCaseMode };
    const match_expectations = [_]MatchExpectation{
        .{ .path = "tests/feature_tests/types/07_choice_match_payload_binding/main.rg", .tag = .match_case_value, .mode = .value },
        .{ .path = "tests/feature_tests/types/29_match_borrowed_payload/main.rg", .tag = .match_case_borrow, .mode = .borrow },
        .{ .path = "tests/feature_tests/types/30_match_mut_borrowed_payload/main.rg", .tag = .match_case_mut_borrow, .mode = .mut_borrow },
        .{ .path = "tests/feature_tests/types/31_match_move_payload/main.rg", .tag = .match_case_move, .mode = .move },
    };
    for (match_expectations) |expected| {
        var tree = try parseTestFile(expected.path);
        defer tree.deinit(std.testing.allocator);
        const node = firstNodeWithTag(&tree, expected.tag);
        try std.testing.expectEqual(expected.mode, tree.matchCase(node).?.mode);
    }

    var accesses = try parseTestFile("tests/feature_tests/types/03_choice_payloads/main.rg");
    defer accesses.deinit(std.testing.allocator);
    const payload_access = firstNodeWithTag(&accesses, .choice_payload_access);
    const field_access = firstNodeWithTag(&accesses, .struct_field_access);
    try std.testing.expect(accesses.choicePayloadAccess(payload_access) != null);
    try std.testing.expect(accesses.structFieldAccess(payload_access) == null);
    try std.testing.expect(accesses.structFieldAccess(field_access) != null);
    try std.testing.expect(accesses.choicePayloadAccess(field_access) == null);

    var returns = try parseTestFile("tests/feature_tests/control_flow/02_loops/main.rg");
    defer returns.deinit(std.testing.allocator);
    const return_node = firstNodeWithTag(&returns, .return_statement);
    try std.testing.expect(returns.returnStatement(return_node).?.value == null);
}

test "generic type applications retain positional arguments" {
    try expectTags("tests/feature_tests/types/280_positional_type_arguments/main.rg", &.{ .specialization, .positional_type_field });
}

test "modern and legacy test declarations share function payloads" {
    var tree = try parseTestFile("tests/feature_tests/testing/21_modern_test_syntax/main.rg");
    defer tree.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 3), tree.roots.len);
    for (tree.roots) |root| {
        const declaration = tree.testDeclaration(root).?;
        try std.testing.expect(declaration.function.body != null);
        try std.testing.expectEqual(@as(usize, 1), tree.structTypeLiteral(declaration.function.input).?.fields.len);
        try std.testing.expectEqual(syntax_tree.Node.Tag.test_declaration, tree.tag(root));
    }
}

test "compact syntaxing keeps contract and operation specialization arguments distinct" {
    const source = "value := Protocol<Owner>.apply<.Value: Bool>(.value = true)";
    var tree = try parseTestSource("operation.rg", source);
    defer tree.deinit(std.testing.allocator);
    const call = tree.functionCall(tree.definitionValue(tree.roots[0]).?).?;
    try std.testing.expect(call.contract_type != null);
    try std.testing.expect(call.specialization_arguments != null);
    try std.testing.expectEqual(syntax_tree.Node.Tag.specialization, tree.tag(call.contract_type.?));
    const parameters = tree.specializationArguments(call.specialization_arguments.?).?;
    try std.testing.expectEqual(@as(usize, 1), parameters.fields.len);
    const field = tree.structTypeField(parameters.fields[0]).?;
    try std.testing.expectEqualStrings("Value", tree.tokenTextFromSource(source, field.name_token));
}

test "compact syntaxing specializes an associated type family in a type annotation" {
    var tree = try parseTestSource("associated_family.rg", "value: Factory<Owner>.Args<Bool> = (.value = true)\n");
    defer tree.deinit(std.testing.allocator);
    const declaration = tree.symbolDeclaration(tree.roots[0]).?;
    const specialization = tree.syntaxType(declaration.type_node.?).?;
    try std.testing.expect(specialization == .generic);
    const projection = tree.syntaxType(specialization.generic.base).?;
    try std.testing.expect(projection == .projection);
    try std.testing.expect(tree.syntaxType(projection.projection.base).? == .generic);
}
