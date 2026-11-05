//! Resolve declared access paths into the same coordinates used by summaries.
const std = @import("std");
const graph_mod = @import("graph.zig");
const types = @import("types.zig");
const schema = @import("../primitives/schema.zig");
const Resolver = @import("contracts.zig").Resolver;
const Bound = schema.MethodSafetyContract.AccessBound;

pub const Resolution = union(enum) { bound: Bound, failure: []const u8 };
pub const Context = struct { participant: ?graph_mod.GlobalTypeId = null, domains: []const @import("../module/parameterized/storage.zig").RegionRequirement = &.{} };

pub fn resolve(self: *Resolver, module_index: usize, inputs: graph_mod.FieldRange, bound: Bound, context: Context) anyerror!Resolution {
    return resolveNames(try self.graph.safetyAllocator(self.allocator), self.graph, module_index, self.modules[module_index].strings.items, inputs, bound, context);
}

pub fn resolveGlobal(a: std.mem.Allocator, graph: *const graph_mod.GlobalSemanticGraph, module_index: usize, inputs: graph_mod.FieldRange, bound: Bound) anyerror!Resolution {
    return resolveNames(a, graph, module_index, graph.strings.items, inputs, bound, .{});
}

fn nameText(names: []const u8, name: schema.StringRange) []const u8 {
    return names[name.start..][0..name.len];
}

fn resolveNames(a: std.mem.Allocator, graph: *const graph_mod.GlobalSemanticGraph, module_index: usize, names: []const u8, inputs: graph_mod.FieldRange, bound: Bound, context: Context) anyerror!Resolution {
    if (bound.input_index >= inputs.len) return .{ .failure = "access bound names an unknown input" };
    var ty = graph.fields.items[inputs.start + bound.input_index].ty;
    if (bound.fields.len == 1) for (context.domains, 0..) |domain, index| {
        if (!std.mem.eql(u8, nameText(names, domain.name), nameText(names, bound.fields[0]))) continue;
        const input = graph.semanticType(ty);
        if (input != .pointer or !types.equal(graph, input.pointer.child, context.participant orelse continue)) continue;
        var result = bound;
        result.fields = &.{};
        result.domain_index = @intCast(index);
        return .{ .bound = result };
    };
    var mutable = false;
    var external = false;
    if (graph.semanticType(ty) == .pointer) {
        const pointer = graph.semanticType(ty).pointer;
        external = true;
        mutable = pointer.mutability == .read_write;
        if (bound.fields.len != 0) ty = pointer.child;
    }
    if (bound.fields.len == 0) {
        if (!external) return .{ .failure = "reads and writes require a reference input" };
        if (bound.write and !mutable) return .{ .failure = "writes requires a mutable reference input" };
        return .{ .bound = bound };
    }

    var projections: std.ArrayList(schema.MethodSafetyContract.AccessProjection) = .empty;
    defer projections.deinit(a);
    for (bound.fields) |name| {
        var depth: usize = 0;
        while (graph.semanticType(ty) == .pointer) {
            if (depth == 128) return .{ .failure = "access bound reference path is too deep" };
            depth += 1;
            const pointer = graph.semanticType(ty).pointer;
            external = true;
            mutable = pointer.mutability == .read_write;
            try projections.append(a, .dereference);
            ty = pointer.child;
        }
        const text = nameText(names, name);
        if (text.len != 0 and text[0] == '_') {
            if (types.nominalTypeOwner(graph, ty)) |owner| {
                if (!graph.sameModuleNamespace(owner, @enumFromInt(module_index)) and
                    !(graph.modules.items[module_index].is_bundled_core and graph.modules.items[@intFromEnum(owner)].is_bundled_core))
                    return .{ .failure = "access bounds cannot select private fields of another module" };
            }
        }
        const fields = types.fields(graph, ty) orelse return .{ .failure = "access bound field paths require a known record type; erased regions are not yet expressible" };
        var selected: ?graph_mod.GlobalTypeId = null;
        for (graph.fields.items[fields.start..][0..fields.len], 0..) |field, index| {
            if (!std.mem.eql(u8, graph.text(field.name), text)) continue;
            try projections.append(a, .{ .field = @intCast(index) });
            selected = field.ty;
            break;
        }
        ty = selected orelse return .{ .failure = "access bound selects an unknown field" };
    }
    if (graph.semanticType(ty) == .pointer) {
        const pointer = graph.semanticType(ty).pointer;
        external = true;
        mutable = pointer.mutability == .read_write;
        try projections.append(a, .dereference);
    }
    if (!external) return .{ .failure = "access bound must reach storage through a reference" };
    if (bound.write and !mutable) return .{ .failure = "writes requires a mutable reference at the selected access path" };
    var result = bound;
    result.fields = &.{};
    result.projections = try projections.toOwnedSlice(a);
    return .{ .bound = result };
}
