const std = @import("std");
const module_sg = @import("graph.zig");
const body_lowerer = @import("body_lowerer.zig");
const initializer_lowerer = @import("initializer_lowerer.zig");
const module_alias_lowerer = @import("module_alias_lowerer.zig");
const global_roots_lowerer = @import("global_roots_lowerer.zig");
const parameterized_lowerer = @import("parameterized/lowerer.zig");
const generic_operator_lowerer = @import("generic_operator_lowerer.zig");
const function_identity_lowerer = @import("function_identity_lowerer.zig");
const abstract_relation_lowerer = @import("abstract_relation_lowerer.zig");
const generic_call_args_lowerer = @import("generic_call_args_lowerer.zig");
const callable = @import("../primitives/callable.zig");
const canonicalize_storage = @import("canonicalize_storage.zig");
const complete_verify = @import("complete_verify.zig");
const diagnostic = @import("../../1_base/diagnostic.zig");
const source_files = @import("../../1_base/source_files.zig");
const tokenizer = @import("../../2_tokens/tokenizer.zig");
const syntaxer = @import("../../3_syntax/syntaxer.zig");

pub const BuildStats = struct {
    lowered_functions: u32 = 0,
    global_bindings: u32 = 0,
    module_aliases: u32 = 0,
    global_roots: u32 = 0,
    field_defaults: u32 = 0,
    generic_types: u32 = 0,
    generic_functions: u32 = 0,
    generic_operators: u32 = 0,
    deinit_functions: u32 = 0,
    generic_deinit_functions: u32 = 0,
    abstract_definitions: u32 = 0,
    abstract_relations: u32 = 0,
    generic_calls: u32 = 0,
    local_semantics_complete: bool = false,
};

pub const BuildResult = struct {
    graph: module_sg.ModuleSemanticGraph,
    stats: BuildStats,
};

pub const QualifiedAbstract = parameterized_lowerer.QualifiedAbstract;
pub const needsLinkedLowering = parameterized_lowerer.needsLinkedLowering;

pub fn build(
    allocator: std.mem.Allocator,
    module_dir: []const u8,
    files: []const module_sg.FileInput,
) !BuildResult {
    return buildLinked(allocator, module_dir, files, &.{});
}

pub fn buildLinked(
    allocator: std.mem.Allocator,
    module_dir: []const u8,
    files: []const module_sg.FileInput,
    abstract_types: []const QualifiedAbstract,
) !BuildResult {
    var graph = try module_sg.build(allocator, module_dir, files);
    errdefer graph.deinit(allocator);
    const stats = try finishLinked(allocator, &graph, files, abstract_types);
    return .{ .graph = graph, .stats = stats };
}

/// Finish semantic lowering on a graph that has already completed module
/// discovery/interfaces. This lets the frontend discover all module headers
/// first, derive explicit semantic configuration such as the bundled prelude,
/// and still lower each durable ModuleSG only once.
pub fn finishLinked(
    allocator: std.mem.Allocator,
    graph: *module_sg.ModuleSemanticGraph,
    files: []const module_sg.FileInput,
    abstract_types: []const QualifiedAbstract,
) !BuildStats {
    if (graph.semantic.local_semantics_complete) return error.ModuleSemanticGraphAlreadyComplete;

    // Declaration discovery can leave interfaces whose imported/generic types
    // and default values still need source syntax. Finish that construction
    // work first; everything after canonicalization consumes one Module* ID
    // space and must not depend on the discovery-time construction prefixes.
    const module_aliases = try module_alias_lowerer.lower(allocator, graph, files);
    const initializers = try initializer_lowerer.lower(allocator, graph, files);
    try lowerNominalLayouts(allocator, graph, files);
    try canonicalize_storage.run(allocator, graph);

    try lowerOperatorMetadata(allocator, graph, files);
    const global_roots = try global_roots_lowerer.lower(allocator, graph);

    const parameterized_stats = try parameterized_lowerer.lowerLinked(allocator, graph, files, abstract_types);
    // Templates claim abstract interfaces before ordinary body lowering, so
    // each contract body is materialized only after specialization.
    const bodies = try body_lowerer.lowerMissingFunctions(allocator, graph, files);
    const generic_operators = try generic_operator_lowerer.lower(graph, files);
    const identity_stats = function_identity_lowerer.lower(graph, files);
    const relation_stats = try abstract_relation_lowerer.lower(allocator, graph, files);
    const generic_calls = try generic_call_args_lowerer.lower(allocator, graph, files);

    graph.semantic.local_semantics_complete = true;
    try complete_verify.verifyModule(graph);

    return .{
        .lowered_functions = bodies.lowered_functions,
        .global_bindings = initializers.global_bindings,
        .module_aliases = module_aliases,
        .global_roots = global_roots,
        .field_defaults = initializers.field_defaults,
        .generic_types = parameterized_stats.generic_types,
        .generic_functions = parameterized_stats.generic_functions,
        .generic_operators = generic_operators,
        .deinit_functions = identity_stats.deinit_functions,
        .generic_deinit_functions = identity_stats.generic_deinit_functions,
        .abstract_definitions = parameterized_stats.abstract_definitions,
        .abstract_relations = relation_stats.implementations + relation_stats.implementation_parameterized_forms + relation_stats.defaults + relation_stats.default_parameterized_forms,
        .generic_calls = generic_calls.generic_calls,
        .local_semantics_complete = true,
    };
}

fn lowerNominalLayouts(allocator: std.mem.Allocator, graph: *module_sg.ModuleSemanticGraph, files: []const module_sg.FileInput) !void {
    for (graph.declarations.items, 0..) |declaration, raw| {
        if (declaration.kind != .type) continue;
        const file = files[declaration.module_file_index];
        const node = module_sg.declarationSyntaxNode(files, declaration) orelse continue;
        const tag = file.tree.tag(node);
        if (tag != .c_enum_declaration and tag != .c_union_declaration) continue;
        try graph.semantic.declaration_semantics.append(allocator, .{
            .declaration = @enumFromInt(@as(u32, @intCast(raw))),
            .choice_layout = if (tag == .c_enum_declaration) .c_enum else .regular,
            .struct_layout = if (tag == .c_union_declaration) .c_union else .regular,
        });
    }
}

fn lowerOperatorMetadata(
    allocator: std.mem.Allocator,
    graph: *module_sg.ModuleSemanticGraph,
    files: []const module_sg.FileInput,
) !void {
    graph.semantic.function_operators.clearRetainingCapacity();
    try graph.semantic.function_operators.ensureTotalCapacity(allocator, graph.functions.items.len);
    for (graph.functions.items) |function| {
        const declaration = graph.declarations.items[@intFromEnum(function.declaration)];
        const file = files[declaration.module_file_index];
        const declaration_node = module_sg.declarationSyntaxNode(files, declaration) orelse {
            graph.semantic.function_operators.appendAssumeCapacity(null);
            continue;
        };
        const operator: ?callable.OperatorKind = if (file.tree.functionNameFromSource(file.source, declaration_node)) |name|
            switch (name) {
                .operator => |value| module_sg.operatorKindFromSyntax(value),
                .identifier => null,
            }
        else
            null;
        graph.semantic.function_operators.appendAssumeCapacity(operator);
    }
}

test "finishLinked completes an already discovered module graph" {
    const allocator = std.testing.allocator;
    var graph = try module_sg.build(allocator, "empty", &.{});
    defer graph.deinit(allocator);
    try std.testing.expect(!graph.semantic.local_semantics_complete);
    const stats = try finishLinked(allocator, &graph, &.{}, &.{});
    try std.testing.expect(graph.semantic.local_semantics_complete);
    try std.testing.expect(stats.local_semantics_complete);
}

test "module semantizer completes syntax-independent local semantics" {
    const allocator = std.testing.allocator;
    var result = try build(allocator, "empty", &.{});
    defer result.graph.deinit(allocator);
    try std.testing.expect(result.graph.semantic.local_semantics_complete);
    try std.testing.expect(result.stats.local_semantics_complete);
}

test "linked lowering trigger ignores abstracts outside function inputs" {
    const allocator = std.testing.allocator;
    const source =
        "dep := #import(\"../dep\")\n" ++
        "consume(.value: Int32) -> (.result: dep.Abstract) := {}\n";
    const input_sources = [_]source_files.SourceFile{.{ .path = "app/use.rg", .code = source }};
    var diagnostics = diagnostic.Diagnostics.init(&allocator, &input_sources);
    defer diagnostics.deinit();
    var tokenizer_context = tokenizer.Tokenizer.init(allocator, &diagnostics, source, diagnostics.source_db.fileId(0));
    _ = try tokenizer_context.tokenize();
    var tokens = tokenizer_context.takeTokens();
    defer tokens.deinit(allocator);
    var compact = try syntaxer.Syntaxer.init(allocator, .init(&tokens), source, &diagnostics);
    defer compact.deinit();
    var tree = try compact.parse();
    defer tree.deinit(allocator);
    try std.testing.expect(!diagnostics.hasErrors());
    const files = [_]module_sg.FileInput{.{ .path = "app/use.rg", .tree = &tree, .source = source }};
    var result = try build(allocator, "app", &files);
    defer result.graph.deinit(allocator);
    try std.testing.expect(!needsLinkedLowering(&result.graph, &files, &.{.{ .qualifier = "dep", .name = "Abstract" }}));
}

test "linked lowering trigger detects imported abstract function inputs" {
    const allocator = std.testing.allocator;
    const source =
        "dep := #import(\"../dep\")\n" ++
        "consume(.value: dep.Abstract) -> () := {}\n";
    const input_sources = [_]source_files.SourceFile{.{ .path = "app/use.rg", .code = source }};
    var diagnostics = diagnostic.Diagnostics.init(&allocator, &input_sources);
    defer diagnostics.deinit();
    var tokenizer_context = tokenizer.Tokenizer.init(allocator, &diagnostics, source, diagnostics.source_db.fileId(0));
    _ = try tokenizer_context.tokenize();
    var tokens = tokenizer_context.takeTokens();
    defer tokens.deinit(allocator);
    var compact = try syntaxer.Syntaxer.init(allocator, .init(&tokens), source, &diagnostics);
    defer compact.deinit();
    var tree = try compact.parse();
    defer tree.deinit(allocator);
    try std.testing.expect(!diagnostics.hasErrors());
    const files = [_]module_sg.FileInput{.{ .path = "app/use.rg", .tree = &tree, .source = source }};
    var result = try build(allocator, "app", &files);
    defer result.graph.deinit(allocator);
    try std.testing.expect(needsLinkedLowering(&result.graph, &files, &.{.{ .qualifier = "dep", .name = "Abstract" }}));
}

test "qualified external signature lowers without an abstract catalog" {
    const allocator = std.testing.allocator;
    const source =
        "dep := #import(\"../dep\")\n" ++
        "consume_imported(.value: dep.Abstract) -> (.result: Int32) := {\n" ++
        "    result = score(.value = value).result\n" ++
        "}\n";
    const input_sources = [_]source_files.SourceFile{.{ .path = "app/use.rg", .code = source }};
    var diagnostics = diagnostic.Diagnostics.init(&allocator, &input_sources);
    defer diagnostics.deinit();
    var tokenizer_context = tokenizer.Tokenizer.init(allocator, &diagnostics, source, diagnostics.source_db.fileId(0));
    _ = try tokenizer_context.tokenize();
    var tokens = tokenizer_context.takeTokens();
    defer tokens.deinit(allocator);
    var compact = try syntaxer.Syntaxer.init(allocator, .init(&tokens), source, &diagnostics);
    defer compact.deinit();
    var tree = try compact.parse();
    defer tree.deinit(allocator);
    try std.testing.expect(!diagnostics.hasErrors());
    const files = [_]module_sg.FileInput{.{ .path = "app/use.rg", .tree = &tree, .source = source }};
    var result = try build(allocator, "app", &files);
    defer result.graph.deinit(allocator);
    try std.testing.expect(result.graph.semantic.local_semantics_complete);
    try std.testing.expectEqual(@as(usize, 0), result.graph.semantic.parameterized_storage.parameterized_functions.items.len);
    var linked = try buildLinked(allocator, "app", &files, &.{.{ .qualifier = "dep", .name = "Abstract" }});
    defer linked.graph.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), linked.graph.semantic.parameterized_storage.parameterized_functions.items.len);
    try std.testing.expectEqual(
        @import("parameterized/storage.zig").GenericDispatchKind.abstract_contract,
        linked.graph.semantic.parameterized_storage.parameterized_functions.items[0].dispatch_kind,
    );
}
