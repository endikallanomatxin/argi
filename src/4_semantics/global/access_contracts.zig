//! Resolve declared access paths into the same coordinates used by summaries.
const std = @import("std");
const graph_mod = @import("graph.zig");
const types = @import("types.zig");
const schema = @import("../primitives/schema.zig");
const Resolver = @import("contracts.zig").Resolver;
const Bound = schema.MethodSafetyContract.AccessBound;

pub const Resolution = union(enum) { bound: Bound, failure: []const u8 };
pub const Context = struct { participant: graph_mod.GlobalTypeId, domains: []const schema.StringRange };

pub fn resolve(self: *Resolver, module_index: usize, inputs: graph_mod.FieldRange, bound: Bound, context: Context) anyerror!Resolution {
    if (bound.input_index >= inputs.len) return .{ .failure = "access bound names an unknown input" };
    var ty = self.graph.fields.items[inputs.start + bound.input_index].ty;
    if (bound.fields.len == 1) for (context.domains, 0..) |domain, index| {
        if (!std.mem.eql(u8, self.modules[module_index].text(domain), self.modules[module_index].text(bound.fields[0]))) continue;
        const input = self.graph.semanticType(ty);
        if (input != .pointer or !types.equal(self.graph, input.pointer.child, context.participant)) continue;
        var result = bound;
        result.fields = &.{};
        result.domain_index = @intCast(index);
        return .{ .bound = result };
    };
    var mutable = false;
    var external = false;
    if (self.graph.semanticType(ty) == .pointer) {
        const pointer = self.graph.semanticType(ty).pointer;
        external = true;
        mutable = pointer.mutability == .read_write;
        if (bound.fields.len != 0) ty = pointer.child;
    }
    if (bound.fields.len == 0) {
        if (!external) return .{ .failure = "reads and writes require a reference input" };
        if (bound.write and !mutable) return .{ .failure = "writes requires a mutable reference input" };
        return .{ .bound = bound };
    }
    const a = try self.graph.safetyAllocator(self.allocator);
    var projections: std.ArrayList(schema.MethodSafetyContract.AccessProjection) = .empty;
    defer projections.deinit(a);
    for (bound.fields) |name| {
        var depth: usize = 0;
        while (self.graph.semanticType(ty) == .pointer) {
            if (depth == 128) return .{ .failure = "access bound reference path is too deep" };
            depth += 1;
            const pointer = self.graph.semanticType(ty).pointer;
            external = true;
            mutable = pointer.mutability == .read_write;
            try projections.append(a, .dereference);
            ty = pointer.child;
        }
        const text = self.modules[module_index].text(name);
        if (text.len != 0 and text[0] == '_') {
            if (types.nominalTypeOwner(self.graph, ty)) |owner| {
                if (!self.graph.sameModuleNamespace(owner, @enumFromInt(module_index)) and
                    !(self.modules[module_index].is_bundled_core and self.graph.modules.items[@intFromEnum(owner)].is_bundled_core))
                    return .{ .failure = "access bounds cannot select private fields of another module" };
            }
        }
        const fields = types.fields(self.graph, ty) orelse return .{ .failure = "access bound field paths require a known record type; erased regions are not yet expressible" };
        var selected: ?graph_mod.GlobalTypeId = null;
        for (self.graph.fields.items[fields.start..][0..fields.len], 0..) |field, index| {
            if (!std.mem.eql(u8, self.graph.text(field.name), text)) continue;
            try projections.append(a, .{ .field = @intCast(index) });
            selected = field.ty;
            break;
        }
        ty = selected orelse return .{ .failure = "access bound selects an unknown field" };
    }
    if (self.graph.semanticType(ty) == .pointer) {
        const pointer = self.graph.semanticType(ty).pointer;
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
