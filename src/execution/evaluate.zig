const std = @import("std");
const g = @import("../4_semantics/global/graph.zig");
const types = @import("../4_semantics/global/types.zig");
const p = @import("../4_semantics/primitives/schema.zig");
const bytecode = @import("../5_codegen/bytecode/bytecode.zig");
const Lower = @import("../5_codegen/bytecode/lower.zig").Lower;
const Vm = @import("vm.zig").Vm;
const Limits = @import("vm.zig").Limits;

// Prove a closed dependency unit and evaluate it through the ordinary VM.
// Inputs are external constant values, not session handles or capabilities.
// No host effects or JIT are admitted by this evaluator's bytecode subset.
// The graph and its types retain their compiler identity; results are exported
// into compiler-owned constant nodes, never left pointing into executor storage.
pub fn evaluate(allocator: std.mem.Allocator, graph: *g.GlobalSemanticGraph, diagnostics: *@import("../1_base/diagnostic.zig").Diagnostics, entry: g.GlobalFunctionId, args: []const bytecode.Value, source: p.SourceRef, limits: Limits) ![]const g.GlobalNodeId {
    var budget = limits;
    return evaluateBudgeted(allocator, graph, diagnostics, entry, args, source, &budget);
}

// One explicit request can evaluate several closed argument calls. They share
// fuel and cumulative storage accounting rather than resetting quotas per call.
pub fn evaluateBudgeted(allocator: std.mem.Allocator, graph: *g.GlobalSemanticGraph, diagnostics: *@import("../1_base/diagnostic.zig").Diagnostics, entry: g.GlobalFunctionId, args: []const bytecode.Value, source: p.SourceRef, budget: *Limits) ![]const g.GlobalNodeId {
    if (@intFromEnum(entry) >= graph.functions.items.len) return error.InvalidEntry;
    var scratch = std.heap.ArenaAllocator.init(allocator);
    defer scratch.deinit();
    const temporary = scratch.allocator();
    // Checking can publish call cleanup annotations into the retained graph.
    // Those allocations must belong to its owner, not the evaluator arena.
    var checker = @import("../4_semantics/safety/checker.zig").SafetyChecker.init(allocator, diagnostics, graph);
    defer checker.deinit();
    try checker.analyzeUnit(&.{entry});
    var lower = try Lower.init(temporary, graph);
    const function = graph.function(entry);
    for (graph.fields.items[function.input.start..][0..function.input.len]) |field| {
        if (!freezable(graph, lower.cleanup_types, field.ty, 0)) return error.UnfreezableEvaluationInput;
    }
    for (graph.fields.items[function.output.start..][0..function.output.len]) |field| {
        if (!freezable(graph, lower.cleanup_types, field.ty, 0)) return error.UnfreezableEvaluationResult;
    }
    const program = try lower.compile(entry);
    var executor = try Vm.init(temporary, program, budget.*);
    defer executor.deinit();
    defer {
        budget.instructions -|= executor.steps;
        if (executor.state != .fresh) budget.value_cells -|= executor.storage.cells;
    }
    const values = try executor.run(entry, args);
    // Validate the entire result before publishing any compiler nodes.
    for (values, graph.fields.items[function.output.start..][0..function.output.len]) |value, field| {
        if (!bytecode.valueFits(graph, field.ty, value)) return error.UnfreezableEvaluationResult;
    }
    const node_start = graph.nodes.items.len;
    const field_start = graph.value_fields.items.len;
    const reference_start = graph.node_refs.items.len;
    errdefer {
        graph.nodes.items.len = node_start;
        graph.value_fields.items.len = field_start;
        graph.node_refs.items.len = reference_start;
    }
    const result = try allocator.alloc(g.GlobalNodeId, values.len);
    errdefer allocator.free(result);
    for (values, graph.fields.items[function.output.start..][0..function.output.len], result) |value, field, *out| {
        out.* = try freeze(allocator, graph, field.ty, value, source);
    }
    return result;
}

fn freezable(graph: *const g.GlobalSemanticGraph, owners: []const bool, ty: g.GlobalTypeId, depth: usize) bool {
    if (depth > 64 or owners[@intFromEnum(ty)]) return false;
    if (bytecode.integerBounds(graph, ty) != null) return true;
    const semantic = graph.semanticType(ty);
    if (semantic == .builtin) return semantic.builtin == .Bool or semantic.builtin == .Void;
    if (semantic == .pointer or semantic == .virtual) return false;
    if (types.arrayElement(graph, ty)) |element| return freezable(graph, owners, element, depth + 1);
    if (types.variants(graph, ty)) |variants| {
        for (graph.variants.items[variants.start..][0..variants.len]) |variant| {
            if (variant.payload_type) |payload| if (!freezable(graph, owners, payload, depth + 1)) return false;
        }
        return true;
    }
    const fields = types.fields(graph, ty) orelse return false;
    for (graph.fields.items[fields.start..][0..fields.len]) |field| {
        if (!freezable(graph, owners, field.ty, depth + 1)) return false;
    }
    return true;
}

fn freeze(allocator: std.mem.Allocator, graph: *g.GlobalSemanticGraph, ty: g.GlobalTypeId, value: bytecode.Value, source: p.SourceRef) anyerror!g.GlobalNodeId {
    const content: @TypeOf(@as(g.Node, undefined).content) = switch (value) {
        .integer => |integer| .{ .int_literal = integer },
        .boolean => |boolean| .{ .bool_literal = boolean },
        .unit => .{ .struct_value_literal = .{ .fields = .{ .start = 0, .len = 0 } } },
        .reference => return error.UnfreezableEvaluationResult,
        .array => |values| blk: {
            const element = types.arrayElement(graph, ty).?;
            const nodes = try allocator.alloc(g.GlobalNodeId, values.len);
            defer allocator.free(nodes);
            for (values, nodes) |item, *node| node.* = try freeze(allocator, graph, element, item, source);
            const start: u32 = @intCast(graph.node_refs.items.len);
            try graph.node_refs.appendSlice(allocator, nodes);
            break :blk .{ .array_literal = .{ .elements = .{ .start = start, .len = @intCast(values.len) }, .element_type = element, .length = @intCast(values.len) } };
        },
        .record => |values| blk: {
            const fields = types.fields(graph, ty).?;
            const entries = try allocator.alloc(g.ValueField, values.len);
            defer allocator.free(entries);
            for (values, graph.fields.items[fields.start..][0..fields.len], entries) |item, field, *out| {
                out.* = .{ .name = field.name, .value = try freeze(allocator, graph, field.ty, item, source) };
            }
            const start: u32 = @intCast(graph.value_fields.items.len);
            try graph.value_fields.appendSlice(allocator, entries);
            break :blk .{ .struct_value_literal = .{ .fields = .{ .start = start, .len = @intCast(entries.len) } } };
        },
        .choice => |choice| blk: {
            const variant: g.GlobalVariantId = @enumFromInt(choice.variant);
            const selected = try bytecode.choiceVariant(graph, ty, variant);
            break :blk .{ .choice_literal = .{ .choice_type = ty, .variant = variant, .payload = if (choice.payload) |payload| try freeze(allocator, graph, selected.payload_type.?, payload.*, source) else null } };
        },
    };
    const result: g.GlobalNodeId = @enumFromInt(graph.nodes.items.len);
    try graph.nodes.append(allocator, .{ .source = source, .ty = ty, .content = content });
    return result;
}

// Execute an already-selected expression with constant operands. It uses
// the normal expression lowerer, verifier and VM, without synthesizing language
// functions or duplicating primitive semantics in the constant resolver.
pub fn evaluateExpression(allocator: std.mem.Allocator, graph: *g.GlobalSemanticGraph, root: g.GlobalNodeId, operands: []const g.GlobalNodeId, args: []const bytecode.Value, budget: *Limits) !g.GlobalNodeId {
    const node = graph.node(root);
    switch (node.content) {
        .binary_operation, .comparison, .struct_field_access, .array_index => {},
        else => return error.UnsupportedCompileTimeExpression,
    }
    var scratch = std.heap.ArenaAllocator.init(allocator);
    defer scratch.deinit();
    const temporary = scratch.allocator();
    var lower = try Lower.init(temporary, graph);
    const ty = node.ty orelse return error.UnfreezableEvaluationResult;
    if (!freezable(graph, lower.cleanup_types, ty, 0)) return error.UnfreezableEvaluationResult;
    for (operands) |operand| {
        const input = graph.node(operand).ty orelse return error.UnfreezableEvaluationInput;
        if (!freezable(graph, lower.cleanup_types, input, 0)) return error.UnfreezableEvaluationInput;
    }
    const program = try lower.compileExpression(root, operands);
    var executor = try Vm.init(temporary, program, budget.*);
    defer executor.deinit();
    defer {
        budget.instructions -|= executor.steps;
        if (executor.state != .fresh) budget.value_cells -|= executor.storage.cells;
    }
    const result = try executor.runExpression(args);
    if (result.len != 1 or !bytecode.valueFits(graph, ty, result[0])) return error.UnfreezableEvaluationResult;
    const node_start = graph.nodes.items.len;
    const field_start = graph.value_fields.items.len;
    const reference_start = graph.node_refs.items.len;
    errdefer {
        graph.nodes.items.len = node_start;
        graph.value_fields.items.len = field_start;
        graph.node_refs.items.len = reference_start;
    }
    return freeze(allocator, graph, ty, result[0], node.source);
}
