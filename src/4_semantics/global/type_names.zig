const std = @import("std");
const global_sg = @import("graph.zig");
const global_types = @import("types.zig");

pub fn appendTypeName(buffer: *std.array_list.Managed(u8), graph: *const global_sg.GlobalSemanticGraph, ty: global_sg.GlobalTypeId) anyerror!void {
    // Candidate signatures may still contain unresolved slots while reporting
    // a failed call. Their poison payload is not a declaration to inspect.
    if (graph.isTypeUnresolved(ty)) {
        try buffer.appendSlice("<unresolved>");
        return;
    }
    if (global_types.arrayLength(graph, ty)) |length| {
        const element = global_types.arrayElement(graph, ty) orelse return error.InvalidArrayType;
        try buffer.append('[');
        var storage: [32]u8 = undefined;
        try buffer.appendSlice(try std.fmt.bufPrint(&storage, "{d}", .{length}));
        try buffer.append(']');
        try appendTypeName(buffer, graph, element);
        return;
    }
    switch (graph.semanticType(ty)) {
        .builtin => |builtin| try buffer.appendSlice(@tagName(builtin)),
        .nominal => |definition| try buffer.appendSlice(graph.typeDefinitionName(definition)),
        .generic => |generic| {
            const base_name = graph.familyDefinitionName(generic.base);
            if (std.mem.eql(u8, base_name, "Nullable")) {
                for (graph.generic_arguments.items[generic.arguments.start..][0..generic.arguments.len]) |argument| switch (argument.value) {
                    .type => |value| {
                        try buffer.append('?');
                        try appendTypeName(buffer, graph, value);
                        return;
                    },
                    else => {},
                };
            }
            try buffer.appendSlice(base_name);
            try buffer.appendSlice("#(");
            for (graph.generic_arguments.items[generic.arguments.start..][0..generic.arguments.len], 0..) |argument, index| {
                if (index != 0) try buffer.appendSlice(", ");
                const name = graph.text(argument.name);
                if (name.len != 0) {
                    try buffer.append('.');
                    try buffer.appendSlice(name);
                }
                switch (argument.value) {
                    .type => |value| {
                        if (name.len != 0) try buffer.appendSlice(": ");
                        try appendTypeName(buffer, graph, value);
                    },
                    .definition => |value| {
                        if (name.len != 0) try buffer.appendSlice(": ");
                        try buffer.appendSlice(graph.familyDefinitionName(value.origin));
                    },
                    .comptime_int => |value| {
                        if (name.len != 0) try buffer.appendSlice(" = ");
                        var storage: [32]u8 = undefined;
                        try buffer.appendSlice(try std.fmt.bufPrint(&storage, "{d}", .{value}));
                    },
                }
            }
            try buffer.append(')');
        },
        .pointer => |pointer| {
            try buffer.appendSlice(if (pointer.mutability == .read_write) "$&" else "&");
            try appendTypeName(buffer, graph, pointer.child);
        },
        .nullable => |child| {
            try buffer.append('?');
            try appendTypeName(buffer, graph, child);
        },
        .structural_choice => |choice| try appendChoiceTypeName(buffer, graph, choice.variants),
        .inferred_choice => |choice| try appendChoiceTypeName(buffer, graph, choice.variants),
        .array => unreachable,
        .structural => try buffer.appendSlice("{...}"),
        else => try buffer.appendSlice("<type>"),
    }
}

fn appendChoiceTypeName(
    buffer: *std.array_list.Managed(u8),
    graph: *const global_sg.GlobalSemanticGraph,
    variants: global_sg.VariantRange,
) anyerror!void {
    try buffer.append('(');
    for (graph.variants.items[variants.start..][0..variants.len], 0..) |variant, index| {
        if (index != 0) try buffer.appendSlice(", ");
        try buffer.appendSlice("..");
        try buffer.appendSlice(graph.text(variant.name));
        if (variant.payload_type) |payload| {
            try buffer.appendSlice(": ");
            try appendTypeName(buffer, graph, payload);
        }
    }
    try buffer.append(')');
}
