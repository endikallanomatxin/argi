const std = @import("std");
const g = @import("graph.zig");

// A lexical path can cross constant reference aliases and literal records, but
// never mutable reference slots, calls, indices or choices. This proves static
// identity; each backend still evaluates the original address expression.
const Step = union(enum) { field: u32, root: g.GlobalBindingId };
const Path = struct {
    graph: *const g.GlobalSemanticGraph,
    current: g.GlobalNodeId,
    pointer: bool = false,
    remaining: usize,

    fn next(self: *Path) ?Step {
        while (self.remaining != 0) {
            self.remaining -= 1;
            const node = self.graph.node(self.current).content;
            if (self.pointer) {
                switch (node) {
                    .address_of => |value| {
                        self.current = value;
                        self.pointer = false;
                    },
                    .binding_use, .struct_field_access => {
                        self.current = immutableValue(self.graph, self.current, &self.remaining) orelse return null;
                    },
                    else => return null,
                }
            } else switch (node) {
                .binding_use => |binding| {
                    self.remaining = 0;
                    return .{ .root = binding };
                },
                .struct_field_access => |field| {
                    self.current = field.value;
                    return .{ .field = field.field_index };
                },
                .dereference => |value| {
                    self.current = value.pointer;
                    self.pointer = true;
                },
                else => return null,
            }
        }
        return null;
    }
};

fn immutableInitializer(graph: *const g.GlobalSemanticGraph, id: g.GlobalBindingId) ?g.GlobalNodeId {
    const binding = graph.binding(id);
    if (binding.mutability != .constant or binding.deferred_initialization) return null;
    const value = binding.initialization orelse return null;
    // An input's initializer is a default recipe. A caller can supply another
    // reference, so that recipe never proves the parameter's actual target.
    for (graph.functions.items) |function| {
        for (graph.binding_refs.items[function.input_bindings.start..][0..function.input_bindings.len]) |input|
            if (input == id) return null;
    }
    return value;
}

// Resolve values, not storage: projecting a reference field selects its actual
// immutable initializer, never the record slot's cleanup flag. Share a budget
// across projections and aliases so malformed cycles terminate.
fn immutableValue(graph: *const g.GlobalSemanticGraph, value: g.GlobalNodeId, remaining: *usize) ?g.GlobalNodeId {
    var current = value;
    while (remaining.* != 0) {
        remaining.* -= 1;
        switch (graph.node(current).content) {
            .binding_use => |id| current = immutableInitializer(graph, id) orelse return null,
            .struct_field_access => |field| {
                const base = immutableValue(graph, field.value, remaining) orelse return null;
                const literal = graph.node(base).content;
                if (literal != .struct_value_literal) return null;
                const fields = literal.struct_value_literal.fields;
                current = for (graph.value_fields.items[fields.start..][0..fields.len]) |candidate| {
                    if (std.mem.eql(u8, graph.text(candidate.name), graph.text(field.field_name)))
                        break candidate.value;
                } else return null;
            },
            .address_of, .struct_value_literal => return current,
            else => return null,
        }
    }
    return null;
}

// Backend cleanup targets contain only direct lexical field projections.
pub fn root(graph: *const g.GlobalSemanticGraph, target: g.GlobalNodeId) ?g.GlobalBindingId {
    var current = target;
    for (0..graph.nodes.items.len) |_| switch (graph.node(current).content) {
        .binding_use => |binding| return binding,
        .struct_field_access => |field| current = field.value,
        else => return null,
    };
    return null;
}

pub fn addressedTarget(graph: *const g.GlobalSemanticGraph, pointer: g.GlobalNodeId) ?g.GlobalNodeId {
    var remaining = graph.nodes.items.len;
    const current = immutableValue(graph, pointer, &remaining) orelse return null;
    switch (graph.node(current).content) {
        .address_of => |target| {
            var path = Path{ .graph = graph, .current = target, .remaining = graph.nodes.items.len };
            while (path.next()) |step| if (step == .root) return target;
            return null;
        },
        else => return null,
    }
}

pub fn equal(graph: *const g.GlobalSemanticGraph, left: g.GlobalNodeId, right: g.GlobalNodeId) bool {
    var a = Path{ .graph = graph, .current = left, .remaining = graph.nodes.items.len };
    var b = Path{ .graph = graph, .current = right, .remaining = graph.nodes.items.len };
    while (a.next()) |lhs| {
        const rhs = b.next() orelse return false;
        switch (lhs) {
            .field => |index| if (rhs != .field or rhs.field != index) return false,
            .root => |binding| return rhs == .root and rhs.root == binding,
        }
    }
    return false;
}

test "record reference proofs follow immutable values and stop at mutable or cyclic aliases" {
    const allocator = std.testing.allocator;
    var graph: g.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);
    const source = @import("../primitives/schema.zig").SourceRef{ .file_index = 0, .offset = 0 };
    const name = try graph.addString(allocator, "target");
    const owner: g.GlobalBindingId = @enumFromInt(0);
    const args: g.GlobalBindingId = @enumFromInt(1);
    const cycle: g.GlobalBindingId = @enumFromInt(2);
    const target: g.GlobalNodeId = @enumFromInt(0);
    const address: g.GlobalNodeId = @enumFromInt(1);
    const literal: g.GlobalNodeId = @enumFromInt(2);
    const use: g.GlobalNodeId = @enumFromInt(3);
    const field: g.GlobalNodeId = @enumFromInt(4);
    const cycle_use: g.GlobalNodeId = @enumFromInt(5);
    try graph.bindings.appendSlice(allocator, &.{
        .{ .name = name, .source = source, .ty = @enumFromInt(0), .mutability = .variable },
        .{ .name = name, .source = source, .ty = @enumFromInt(0), .mutability = .constant, .initialization = literal },
        .{ .name = name, .source = source, .ty = @enumFromInt(0), .mutability = .constant, .initialization = cycle_use },
    });
    try graph.value_fields.append(allocator, .{ .name = name, .value = address });
    try graph.nodes.appendSlice(allocator, &.{
        .{ .source = source, .ty = null, .content = .{ .binding_use = owner } },
        .{ .source = source, .ty = null, .content = .{ .address_of = target } },
        .{ .source = source, .ty = null, .content = .{ .struct_value_literal = .{ .fields = .{ .start = 0, .len = 1 } } } },
        .{ .source = source, .ty = null, .content = .{ .binding_use = args } },
        .{ .source = source, .ty = null, .content = .{ .struct_field_access = .{ .value = use, .field_name = name, .field_index = 0 } } },
        .{ .source = source, .ty = null, .content = .{ .binding_use = cycle } },
    });
    try std.testing.expectEqual(target, addressedTarget(&graph, field).?);
    try std.testing.expectEqual(@as(?g.GlobalNodeId, null), addressedTarget(&graph, cycle_use));
    graph.bindings.items[@intFromEnum(args)].mutability = .variable;
    try std.testing.expectEqual(@as(?g.GlobalNodeId, null), addressedTarget(&graph, field));
    graph.bindings.items[@intFromEnum(args)].mutability = .constant;
    graph.bindings.items[@intFromEnum(args)].deferred_initialization = true;
    try std.testing.expectEqual(@as(?g.GlobalNodeId, null), addressedTarget(&graph, field));
    graph.bindings.items[@intFromEnum(args)].deferred_initialization = false;
    try graph.binding_refs.append(allocator, args);
    try graph.functions.append(allocator, .{
        .declaration = @enumFromInt(0),
        .input = .{ .start = 0, .len = 0 },
        .output = .{ .start = 0, .len = 0 },
        .input_bindings = .{ .start = 0, .len = 1 },
    });
    // A record-valued parameter default is also only a caller-overridable recipe.
    try std.testing.expectEqual(@as(?g.GlobalNodeId, null), addressedTarget(&graph, field));
}
