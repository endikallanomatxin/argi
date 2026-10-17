const std = @import("std");
const g = @import("../4_semantics/global/graph.zig");
const types = @import("../4_semantics/global/types.zig");
const p = @import("../4_semantics/primitives/schema.zig");
const bytecode = @import("../5_codegen/bytecode/bytecode.zig");
const Lower = @import("../5_codegen/bytecode/lower.zig").Lower;
const Vm = @import("vm.zig").Vm;
const Limits = @import("vm.zig").Limits;

// Evaluate a closed, safety-checked dependency unit through the ordinary VM.
// Inputs are external constant values, not session handles or capabilities.
// No host effects or JIT are admitted by this evaluator's bytecode subset.
// The graph and its types retain their compiler identity; results are exported
// into compiler-owned constant nodes, never left pointing into executor storage.
pub fn evaluate(allocator: std.mem.Allocator, graph: *g.GlobalSemanticGraph, entry: g.GlobalFunctionId, args: []const bytecode.Value, source: p.SourceRef, limits: Limits) ![]const g.GlobalNodeId {
    if (@intFromEnum(entry) >= graph.functions.items.len) return error.InvalidEntry;
    var scratch = std.heap.ArenaAllocator.init(allocator);
    defer scratch.deinit();
    const temporary = scratch.allocator();
    var lower = try Lower.init(temporary, graph);
    const function = graph.function(entry);
    for (graph.fields.items[function.input.start..][0..function.input.len]) |field| {
        if (!freezable(graph, lower.cleanup_types, field.ty, 0)) return error.UnfreezableEvaluationInput;
    }
    for (graph.fields.items[function.output.start..][0..function.output.len]) |field| {
        if (!freezable(graph, lower.cleanup_types, field.ty, 0)) return error.UnfreezableEvaluationResult;
    }
    const program = try lower.compile(entry);
    var executor = try Vm.init(temporary, program, limits);
    defer executor.deinit();
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
