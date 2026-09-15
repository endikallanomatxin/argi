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

pub const BuildStats = struct {
    lowered_functions: u32 = 0,
    fallback_functions: u32 = 0,
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

pub fn build(
    allocator: std.mem.Allocator,
    module_dir: []const u8,
    files: []const module_sg.FileInput,
) !BuildResult {
    return buildWithAbstractCatalog(allocator, module_dir, files, &.{});
}

pub fn buildWithAbstractCatalog(
    allocator: std.mem.Allocator,
    module_dir: []const u8,
    files: []const module_sg.FileInput,
    abstract_names: []const []const u8,
) !BuildResult {
    var graph = try module_sg.build(allocator, module_dir, files);
    errdefer graph.deinit(allocator);

    // Declaration discovery can leave interfaces whose imported/generic types
    // and default values still need source syntax. Finish that construction
    // work first; everything after canonicalization consumes one Module* ID
    // space and must not depend on the builder-era compatibility prefixes.
    const module_aliases = try module_alias_lowerer.lower(allocator, &graph, files);
    const initializers = try initializer_lowerer.lower(allocator, &graph, files);
    try lowerNominalLayouts(allocator, &graph, files);
    try canonicalize_storage.run(allocator, &graph);

    try lowerOperatorMetadata(allocator, &graph, files);
    const global_roots = try global_roots_lowerer.lower(allocator, &graph);

    const parameterized_stats = try parameterized_lowerer.lowerWithAbstractCatalog(allocator, &graph, files, abstract_names);
    // Templates claim abstract interfaces before ordinary body lowering, so
    // each contract body is materialized only after specialization.
    const bodies = try body_lowerer.lowerMissingFunctions(allocator, &graph, files);
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
        },
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

test "module semantizer completes syntax-independent local semantics" {
    const allocator = std.testing.allocator;
    var result = try build(allocator, "empty", &.{});
    defer result.graph.deinit(allocator);
    try std.testing.expect(result.graph.semantic.local_semantics_complete);
    try std.testing.expect(result.stats.local_semantics_complete);
    try std.testing.expectEqual(@as(u32, 0), result.stats.fallback_functions);
}
