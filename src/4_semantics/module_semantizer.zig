const std = @import("std");
const module_sg = @import("module_semantic_graph.zig");
const fallback_lowerer = @import("module_fallback_lowerer.zig");
const initializer_lowerer = @import("module_initializer_lowerer.zig");
const global_roots_lowerer = @import("module_global_roots_lowerer.zig");
const template_lowerer = @import("module_template_lowerer.zig");
const generic_operator_lowerer = @import("module_generic_operator_lowerer.zig");
const function_identity_lowerer = @import("module_function_identity_lowerer.zig");
const abstract_relation_lowerer = @import("module_abstract_relation_lowerer.zig");
const generic_call_args_lowerer = @import("module_generic_call_args_lowerer.zig");
const callable = @import("semantic_callable.zig");
const complete_verify = @import("module_semantic_complete_verify.zig");

pub const BuildStats = struct {
    lowered_functions: u32 = 0,
    fallback_functions: u32 = 0,
    global_bindings: u32 = 0,
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

pub fn build(
    allocator: std.mem.Allocator,
    module_dir: []const u8,
    files: []const module_sg.FileInput,
) !BuildResult {
    var graph = try module_sg.build(allocator, module_dir, files);
    errdefer graph.deinit(allocator);

    try lowerOperatorMetadata(allocator, &graph, files);
    const initializers = try initializer_lowerer.lower(allocator, &graph, files);
    const global_roots = try global_roots_lowerer.lower(allocator, &graph);

    // Body lowering must have one producer. The previous pipeline first ran the
    // precise lowerer, rolled every semantic table back when it hit an
    // unsupported construct, and then walked the same function again with the
    // fallback lowerer. Besides duplicating language rules, that made semantic
    // state depend on a hand-maintained rollback checkpoint. Until the precise
    // lowerer can represent unresolved constructs as pending operations in the
    // same traversal, use the pending-capable lowerer as the single authority.
    const bodies = try fallback_lowerer.lowerMissingFunctions(allocator, &graph, files);

    const template_stats = try template_lowerer.lower(allocator, &graph, files);
    const generic_operators = try generic_operator_lowerer.lower(&graph, files);
    const identity_stats = function_identity_lowerer.lower(&graph, files);
    const relation_stats = try abstract_relation_lowerer.lower(allocator, &graph, files);
    const generic_calls = try generic_call_args_lowerer.lower(allocator, &graph, files);

    graph.semantic.local_semantics_complete = true;
    try complete_verify.verifyModule(&graph);

    return .{
        .graph = graph,
        .stats = .{
            .lowered_functions = bodies.lowered_functions,
            .fallback_functions = 0,
            .global_bindings = initializers.global_bindings,
            .global_roots = global_roots,
            .field_defaults = initializers.field_defaults,
            .generic_types = template_stats.generic_types,
            .generic_functions = template_stats.generic_functions,
            .generic_operators = generic_operators,
            .deinit_functions = identity_stats.deinit_functions,
            .generic_deinit_functions = identity_stats.generic_deinit_functions,
            .abstract_definitions = template_stats.abstract_definitions,
            .abstract_relations = relation_stats.implementations + relation_stats.implementation_templates + relation_stats.defaults + relation_stats.default_templates,
            .generic_calls = generic_calls.generic_calls,
            .local_semantics_complete = true,
        },
    };
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
        const operator: ?callable.OperatorKind = if (file.tree.functionNameFromSource(file.source, declaration.syntax_node)) |name|
            switch (name) {
                .operator => |value| callable.fromSyntax(value),
                .identifier => null,
            }
        else
            null;
        graph.semantic.function_operators.appendAssumeCapacity(operator);
    }
}

test "module semantizer completes syntax-independent local semantics" {
    const allocator = std.testing.allocator;
    var result = try build(allocator, "empty", &.{});
    defer result.graph.deinit(allocator);
    try std.testing.expect(result.graph.semantic.local_semantics_complete);
    try std.testing.expect(result.stats.local_semantics_complete);
    try std.testing.expectEqual(@as(u32, 0), result.stats.fallback_functions);
}
