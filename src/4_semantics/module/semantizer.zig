const std = @import("std");
const module_sg = @import("graph.zig");
const body_lowerer = @import("body_lowerer.zig");
const initializer_lowerer = @import("initializer_lowerer.zig");
const module_alias_lowerer = @import("module_alias_lowerer.zig");
const global_roots_lowerer = @import("global_roots_lowerer.zig");
const parameterized_lowerer = @import("parameterized/lowerer.zig");
const function_identity_lowerer = @import("function_identity_lowerer.zig");
const contract_relation_lowerer = @import("contract_relation_lowerer.zig");
const generic_call_args_lowerer = @import("generic_call_args_lowerer.zig");
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
    contract_definitions: u32 = 0,
    contract_relations: u32 = 0,
    generic_calls: u32 = 0,
    local_semantics_complete: bool = false,
};

pub const BuildResult = struct {
    graph: module_sg.ModuleSemanticGraph,
    stats: BuildStats,
};

pub fn build(allocator: std.mem.Allocator, module_dir: []const u8, files: []const module_sg.FileInput) !BuildResult {
    return buildForTarget(allocator, module_dir, files, .{});
}

pub fn buildForTarget(allocator: std.mem.Allocator, module_dir: []const u8, files: []const module_sg.FileInput, target: @import("../../1_base/target.zig").Config) !BuildResult {
    var graph = try module_sg.buildForTarget(allocator, module_dir, files, target);
    errdefer graph.deinit(allocator);
    const stats = try finish(allocator, &graph, files, null);
    return .{ .graph = graph, .stats = stats };
}

/// Finish semantic lowering on a graph that has already completed module
/// discovery/interfaces. This lets the frontend discover all module headers
/// first, derive explicit semantic configuration such as the bundled prelude,
/// and still lower each durable ModuleSG only once.
pub fn finish(
    allocator: std.mem.Allocator,
    graph: *module_sg.ModuleSemanticGraph,
    files: []const module_sg.FileInput,
    diagnostics: ?*diagnostic.Diagnostics,
) !BuildStats {
    if (graph.semantic.local_semantics_complete) return error.ModuleSemanticGraphAlreadyComplete;

    // Discovery publishes names and forward type identities. Construct every
    // interface and body in the same canonical semantic pools.
    try function_identity_lowerer.validateOrdinaryIdentities(graph, files, diagnostics);
    const module_aliases = try module_alias_lowerer.lower(allocator, graph, files);
    const initializers = try initializer_lowerer.lower(allocator, graph, files, diagnostics);
    try lowerNominalLayouts(graph, files);

    const global_roots = try global_roots_lowerer.lower(allocator, graph);

    const parameterized_stats = try parameterized_lowerer.lowerDiagnosed(allocator, graph, files, diagnostics);
    try lowerModuleConditions(allocator, graph, files);
    // Templates register contract interfaces before ordinary body lowering, so
    // each contract body is materialized only after specialization.
    const bodies = try body_lowerer.lowerSourceFunctions(allocator, graph, files, diagnostics);
    try function_identity_lowerer.lower(graph, files, diagnostics);
    const relation_stats = try contract_relation_lowerer.lowerDiagnosed(allocator, graph, files, diagnostics);
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
        .contract_definitions = parameterized_stats.contract_definitions,
        .contract_relations = relation_stats.implementations,
        .generic_calls = generic_calls.generic_calls,
        .local_semantics_complete = true,
    };
}

fn lowerModuleConditions(allocator: std.mem.Allocator, graph: *module_sg.ModuleSemanticGraph, files: []const module_sg.FileInput) !void {
    var writer = @import("writer.zig").Writer.init(allocator, graph);
    for (files, 0..) |file, file_index| for (file.tree.roots) |root| {
        const statement = file.tree.ifStatement(root) orelse continue;
        if (!statement.comptime_selection) continue;
        const expression = try parameterized_lowerer.lowerConcreteExpression(graph, &writer, @intCast(file_index), file.tree, file.source, statement.condition);
        try graph.conditions.append(allocator, .{
            .source = .{ .file_index = @intCast(file_index), .offset = file.tree.location(root).offset },
            .expression = expression,
        });
    };
}

// Incomplete types and callback signatures have no structural fields. Layout
// metadata distinguishes an incomplete identity from a pointer-valued signature
// and from an ordinary record whose fields are still unresolved.
fn lowerNominalLayouts(graph: *module_sg.ModuleSemanticGraph, files: []const module_sg.FileInput) !void {
    for (graph.declarations.items, 0..) |declaration, raw| {
        if (declaration.kind != .type) continue;
        const file = files[declaration.module_file_index];
        const node = module_sg.declarationSyntaxNode(files, declaration) orelse continue;
        const tag = file.tree.tag(node);
        if (tag != .c_enum_declaration and tag != .c_union_declaration and tag != .c_struct_declaration and tag != .c_incomplete_declaration and tag != .c_function_pointer_declaration) continue;
        const identity = graph.definitionForDeclaration(@enumFromInt(@as(u32, @intCast(raw)))) orelse continue;
        const definition = &graph.semantic.type_definitions.items[@intFromEnum(identity)];
        definition.function_id = declaration.function_id;
        definition.choice_layout = if (tag == .c_enum_declaration) .c_enum else .regular;
        definition.struct_layout = if (tag == .c_function_pointer_declaration) .c_function_pointer else if (tag == .c_union_declaration) .c_union else if (tag == .c_struct_declaration) .c_struct else if (tag == .c_incomplete_declaration) .c_incomplete else .regular;
    }
}

test "finish completes an already discovered module graph" {
    const allocator = std.testing.allocator;
    var graph = try module_sg.build(allocator, "empty", &.{});
    defer graph.deinit(allocator);
    try std.testing.expect(!graph.semantic.local_semantics_complete);
    const stats = try finish(allocator, &graph, &.{}, null);
    try std.testing.expect(graph.semantic.local_semantics_complete);
    try std.testing.expect(stats.local_semantics_complete);
}

test "finish lowers explicit bundled contract bounds in one pass" {
    const allocator = std.testing.allocator;
    const source = "consume := #(.Value: Type: PreludeContract) (.value: Value) -> ()  {}\n";
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
    var graph = try module_sg.build(allocator, "app", &files);
    defer graph.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), graph.semantic.parameterized_storage.parameterized_functions.items.len);

    _ = try finish(
        allocator,
        &graph,
        &files,
        null,
    );
    try std.testing.expectEqual(@as(usize, 1), graph.semantic.parameterized_storage.parameterized_functions.items.len);
}

test "module semantizer completes syntax-independent local semantics" {
    const allocator = std.testing.allocator;
    var result = try build(allocator, "empty", &.{});
    defer result.graph.deinit(allocator);
    try std.testing.expect(result.graph.semantic.local_semantics_complete);
    try std.testing.expect(result.stats.local_semantics_complete);
}

test "qualified external signature lowers without a contract catalog" {
    const allocator = std.testing.allocator;
    const source =
        "dep := import(\"../dep\")\n" ++
        "consume_imported := #(.Value: Type: dep.Protocol) (.value: Value) -> (.result: Int32)  {\n" ++
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
    try std.testing.expectEqual(@as(usize, 1), result.graph.semantic.parameterized_storage.parameterized_functions.items.len);
}
