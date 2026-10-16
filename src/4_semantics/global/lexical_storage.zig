const g = @import("graph.zig");

// A lexical path can cross constant reference aliases, but never mutable
// reference slots, calls, indices or choices. This is a static identity proof;
// the original address expression is still evaluated by each backend.
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
                    .binding_use => |id| {
                        self.current = immutableInitializer(self.graph, id) orelse return null;
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
    const initializer = graph.node(value).content;
    if (initializer != .address_of and initializer != .binding_use) return null;
    // An input's initializer is a default recipe. A caller can supply another
    // reference, so that recipe never proves the parameter's actual target.
    for (graph.functions.items) |function| {
        for (graph.binding_refs.items[function.input_bindings.start..][0..function.input_bindings.len]) |input|
            if (input == id) return null;
    }
    return value;
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
    var current = pointer;
    for (0..graph.nodes.items.len) |_| switch (graph.node(current).content) {
        .address_of => |target| {
            var path = Path{ .graph = graph, .current = target, .remaining = graph.nodes.items.len };
            while (path.next()) |step| if (step == .root) return target;
            return null;
        },
        .binding_use => |id| {
            current = immutableInitializer(graph, id) orelse return null;
        },
        else => return null,
    };
    return null;
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
