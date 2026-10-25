const std = @import("std");
const g = @import("graph.zig");
const global_types = @import("types.zig");
const reachability = @import("reachability.zig");
const diag = @import("../../1_base/diagnostic.zig");

// Written record fields share positional/name matching with call inputs.
// Lexical assumptions are handled separately: they are not stored fields.
pub fn suppliedField(graph: *const g.GlobalSemanticGraph, literal: anytype, expected_offset: usize, expected_name: []const u8) ?g.GlobalNodeId {
    for (0..literal.fields.len) |supplied_offset| {
        const supplied = graph.value_fields.items[literal.fields.start + @as(u32, @intCast(supplied_offset))];
        if (supplied_offset < literal.dispatch_prefix_positional_count or graph.text(supplied.name).len == 0) {
            if (supplied_offset == expected_offset) return supplied.value;
        } else if (std.mem.eql(u8, graph.text(supplied.name), expected_name)) return supplied.value;
    }
    return null;
}

// An expected record type does not initialize omitted required fields. Validate the
// executable literal before regular Safety checking or backend emission.
// Vacant bindings initialized field by field have no complete-value literal.
pub fn checkRequiredFields(
    graph: *const g.GlobalSemanticGraph,
    reachable: ?*const reachability.FunctionSet,
    diagnostics: ?*diag.Diagnostics,
) !void {
    var missing: ?Missing = null;
    if (reachable) |unit| {
        // Closed evaluation units already own their node set. Do not rescan
        // unrelated retained submissions for each compile-time request.
        var nodes = unit.nodes.keyIterator();
        while (nodes.next()) |id| {
            if (missingField(graph, id.*)) |failure| {
                if (missing == null or @intFromEnum(failure.node) < @intFromEnum(missing.?.node)) missing = failure;
            }
        }
    } else {
        for (0..graph.nodes.items.len) |raw| {
            const id: g.GlobalNodeId = @enumFromInt(@as(u32, @intCast(raw)));
            if (missingField(graph, id)) |failure| {
                missing = failure;
                break;
            }
        }
    }
    if (missing) |failure| {
        const field = graph.fields.items[@intFromEnum(failure.field)];
        if (diagnostics) |sink| try sink.add(
            @import("source_location.zig").location(graph, sink, graph.node(failure.node).source),
            .semantic,
            "record initializer is missing required field '{s}'",
            .{graph.text(field.name)},
        );
        return if (diagnostics != null) error.Reported else error.IncompleteRecordLiteral;
    }
}

const Missing = struct { node: g.GlobalNodeId, field: g.GlobalFieldId };

pub fn hasRequiredFields(graph: *const g.GlobalSemanticGraph, id: g.GlobalNodeId, target: g.GlobalTypeId) bool {
    return missingInLiteral(graph, id, target, 0) == null;
}

fn missingField(graph: *const g.GlobalSemanticGraph, id: g.GlobalNodeId) ?Missing {
    return missingInLiteral(graph, id, graph.node(id).ty orelse return null, 0);
}

fn missingInLiteral(graph: *const g.GlobalSemanticGraph, id: g.GlobalNodeId, ty: g.GlobalTypeId, depth: usize) ?Missing {
    if (depth > 64) return null;
    const literal = switch (graph.node(id).content) {
        .struct_value_literal => |value| value,
        else => return null,
    };
    // Union fields are overlapping alternatives, not independent obligations.
    if (global_types.isCUnion(graph, ty)) return null;
    const fields = global_types.fields(graph, ty) orelse return null;
    for (graph.fields.items[fields.start..][0..fields.len], 0..) |field, index| {
        if (suppliedField(graph, literal, index, graph.text(field.name))) |child| {
            if (missingInLiteral(graph, child, field.ty, depth + 1)) |failure| return failure;
        } else if (field.default_value == null) {
            return .{ .node = id, .field = @enumFromInt(fields.start + @as(u32, @intCast(index))) };
        }
    }
    return null;
}
