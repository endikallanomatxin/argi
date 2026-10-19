const std = @import("std");
const g = @import("graph.zig");
const p = @import("../primitives/schema.zig");
const Generics = @import("generics.zig").Resolver;

const Ids = struct {
    pub const TypeId = enum(u32) { _ };
    pub const FieldId = enum(u32) { _ };
    pub const VariantId = enum(u32) { _ };
    pub const GenericArgId = enum(u32) { _ };
    pub const DeclId = g.GlobalDeclId;
    pub const NodeId = g.GlobalNodeId;
};
const Node = union(enum) { stable: g.GlobalTypeId, shape: p.SemanticType(Ids) };

/// Immutable type descriptions owned independently of a speculative graph tail.
/// Only identities preceding the resolution pass can remain graph references.
/// Pools retain sharing within the captured type DAG, without copying the graph.
pub const Recipe = struct {
    pub const Boundary = struct { types: usize, declarations: usize, nodes: usize };
    nodes: std.ArrayList(Node) = .empty,
    fields: std.ArrayList(p.Field(Ids)) = .empty,
    variants: std.ArrayList(p.ChoiceVariant(Ids)) = .empty,
    arguments: std.ArrayList(p.GenericArgument(Ids)) = .empty,
    strings: std.ArrayList(u8) = .empty,
    roots: []?Ids.TypeId = &.{},

    pub fn deinit(self: *Recipe, a: std.mem.Allocator) void {
        self.nodes.deinit(a);
        self.fields.deinit(a);
        self.variants.deinit(a);
        self.arguments.deinit(a);
        self.strings.deinit(a);
        a.free(self.roots);
        self.* = .{};
    }

    pub fn clone(self: *const Recipe, a: std.mem.Allocator) !Recipe {
        var result: Recipe = .{};
        errdefer result.deinit(a);
        inline for (.{ "nodes", "fields", "variants", "arguments", "strings" }) |name|
            try @field(result, name).appendSlice(a, @field(self, name).items);
        result.roots = try a.dupe(?Ids.TypeId, self.roots);
        return result;
    }

    pub fn capture(a: std.mem.Allocator, graph: *const g.GlobalSemanticGraph, boundary: Boundary, roots: []const ?g.GlobalTypeId) !Recipe {
        var result: Recipe = .{};
        errdefer result.deinit(a);
        var context = Capture{ .a = a, .graph = graph, .boundary = boundary, .recipe = &result };
        defer context.seen.deinit(a);
        result.roots = try a.alloc(?Ids.TypeId, roots.len);
        for (roots, result.roots) |root, *out| out.* = if (root) |ty| try context.typeId(ty, 0) else null;
        return result;
    }

    /// Rebuild into the coordinator's construction graph, never a losing probe.
    /// The caller publishes the complete type set atomically before resuming IR.
    pub fn publish(self: *const Recipe, a: std.mem.Allocator, generics: *Generics, roots: []?g.GlobalTypeId) !void {
        var context = Publish{ .a = a, .generics = generics, .recipe = self, .mapped = try a.alloc(?g.GlobalTypeId, self.nodes.items.len) };
        defer a.free(context.mapped);
        @memset(context.mapped, null);
        for (self.roots, roots) |root, *out| out.* = if (root) |ty| try context.typeId(ty) else null;
    }

    /// Compare a fresh candidate structurally; its temporary IDs may have been
    /// reused for entirely different types since this recipe was captured.
    pub fn matches(self: *const Recipe, a: std.mem.Allocator, graph: *const g.GlobalSemanticGraph, roots: []const ?g.GlobalTypeId) !bool {
        if (self.roots.len != roots.len) return false;
        var context = Match{ .a = a, .graph = graph, .recipe = self };
        defer context.seen.deinit(a);
        for (self.roots, roots) |saved, current| {
            if (saved == null or current == null) {
                if ((saved == null) != (current == null)) return false;
            } else if (!try context.typeId(saved.?, current.?)) return false;
        }
        return true;
    }

    fn text(self: *const Recipe, range: p.StringRange) []const u8 {
        return self.strings.items[range.start..][0..range.len];
    }
    const Match = struct {
        const Key = struct { saved: Ids.TypeId, current: g.GlobalTypeId };
        a: std.mem.Allocator,
        graph: *const g.GlobalSemanticGraph,
        recipe: *const Recipe,
        seen: std.AutoHashMapUnmanaged(Key, bool) = .empty,

        fn typeId(self: *Match, saved: Ids.TypeId, current: g.GlobalTypeId) anyerror!bool {
            const key = Key{ .saved = saved, .current = current };
            if (self.seen.get(key)) |previous| return previous;
            if (@intFromEnum(current) >= self.graph.types.items.len) return false;
            const result = try self.compare(saved, current);
            try self.seen.put(self.a, key, result);
            return result;
        }

        fn compare(self: *Match, saved: Ids.TypeId, current: g.GlobalTypeId) anyerror!bool {
            const graph = self.graph;
            const node = self.recipe.nodes.items[@intFromEnum(saved)];
            if (node == .stable) return node.stable == current or @import("types.zig").equal(graph, node.stable, current);
            const shape = node.shape;
            const actual = graph.types.items[@intFromEnum(current)];
            if (@intFromEnum(std.meta.activeTag(shape)) != @intFromEnum(std.meta.activeTag(actual))) return false;
            return switch (shape) {
                .builtin => |value| value == actual.builtin,
                .declared => |value| value == actual.declared,
                .pointer => |value| value.mutability == actual.pointer.mutability and try self.typeId(value.child, actual.pointer.child),
                .array => |value| value.length == actual.array.length and try self.typeId(value.element, actual.array.element),
                .nullable => |value| try self.typeId(value, actual.nullable),
                .inferred_errable, .inferred_choice => unreachable,
                .virtual => |value| try self.typeId(value, actual.virtual),
                .structural => |value| blk: {
                    if (value.layout != actual.structural.layout or value.fields.len != actual.structural.fields.len) break :blk false;
                    for (self.recipe.fields.items[value.fields.start..][0..value.fields.len], graph.fields.items[actual.structural.fields.start..][0..value.fields.len]) |left, right| {
                        if (!std.mem.eql(u8, self.recipe.text(left.name), graph.text(right.name)) or left.default_value != right.default_value or !try self.typeId(left.ty, right.ty)) break :blk false;
                    }
                    break :blk true;
                },
                .structural_choice => |value| blk: {
                    const left = value.variants;
                    const right = actual.structural_choice.variants;
                    if (value.layout != actual.structural_choice.layout) break :blk false;
                    if (left.len != right.len) break :blk false;
                    for (self.recipe.variants.items[left.start..][0..left.len], graph.variants.items[right.start..][0..right.len]) |x, y| {
                        if (!std.mem.eql(u8, self.recipe.text(x.name), graph.text(y.name)) or x.value != y.value or x.option_decl != y.option_decl) break :blk false;
                        if (x.qualifier == null or y.qualifier == null) {
                            if ((x.qualifier == null) != (y.qualifier == null)) break :blk false;
                        } else if (!std.mem.eql(u8, self.recipe.text(x.qualifier.?), graph.text(y.qualifier.?))) break :blk false;
                        if (x.payload_type == null or y.payload_type == null) {
                            if ((x.payload_type == null) != (y.payload_type == null)) break :blk false;
                        } else if (!try self.typeId(x.payload_type.?, y.payload_type.?)) break :blk false;
                    }
                    break :blk true;
                },
                .generic => |value| blk: {
                    if (value.base != actual.generic.base or value.arguments.len != actual.generic.arguments.len) break :blk false;
                    for (self.recipe.arguments.items[value.arguments.start..][0..value.arguments.len], graph.generic_arguments.items[actual.generic.arguments.start..][0..value.arguments.len]) |x, y| {
                        if (!std.mem.eql(u8, self.recipe.text(x.name), graph.text(y.name)) or @intFromEnum(std.meta.activeTag(x.value)) != @intFromEnum(std.meta.activeTag(y.value))) break :blk false;
                        switch (x.value) {
                            .type => |ty| if (!try self.typeId(ty, y.value.type)) break :blk false,
                            .comptime_int => |n| if (n != y.value.comptime_int) break :blk false,
                        }
                    }
                    break :blk true;
                },
            };
        }
    };

    const Capture = struct {
        a: std.mem.Allocator,
        graph: *const g.GlobalSemanticGraph,
        boundary: Boundary,
        recipe: *Recipe,
        seen: std.AutoHashMapUnmanaged(g.GlobalTypeId, ?Ids.TypeId) = .empty,

        fn string(self: *Capture, range: p.StringRange) !p.StringRange {
            const start = std.math.cast(u32, self.recipe.strings.items.len) orelse return error.SemanticGraphTooLarge;
            try self.recipe.strings.appendSlice(self.a, self.graph.text(range));
            return .{ .start = start, .len = range.len };
        }
        fn declaration(self: *Capture, id: g.GlobalDeclId) !g.GlobalDeclId {
            if (@intFromEnum(id) >= self.boundary.declarations) return error.ComptimeTypeRecipePending;
            return id;
        }
        fn typeId(self: *Capture, id: g.GlobalTypeId, depth: usize) anyerror!Ids.TypeId {
            if (depth > 256) return error.CompileTimeTypeDepthLimit;
            if (self.seen.get(id)) |previous| return previous orelse error.CyclicCompileTimeType;
            try self.seen.put(self.a, id, null);
            const value = if (@intFromEnum(id) < self.boundary.types)
                Node{ .stable = id }
            else blk: {
                const shape = self.graph.types.items[@intFromEnum(id)];
                const description: p.SemanticType(Ids) = switch (shape) {
                    .builtin => |v| .{ .builtin = v },
                    .declared => |v| .{ .declared = try self.declaration(v) },
                    .pointer => |v| .{ .pointer = .{ .child = try self.typeId(v.child, depth + 1), .mutability = v.mutability } },
                    .array => |v| .{ .array = .{ .element = try self.typeId(v.element, depth + 1), .length = v.length } },
                    .nullable => |v| .{ .nullable = try self.typeId(v, depth + 1) },
                    .inferred_errable => return error.ComptimeTypeRecipePending,
                    .virtual => |v| .{ .virtual = try self.typeId(v, depth + 1) },
                    .structural => |v| .{ .structural = .{ .fields = try self.captureFields(v.fields, depth + 1), .layout = v.layout } },
                    .structural_choice => |v| .{ .structural_choice = .{ .variants = try self.captureVariants(v.variants, depth + 1), .layout = v.layout } },
                    // Open choice identities may themselves name a speculative
                    // type slot. They need an origin recipe before transport.
                    .inferred_choice => return error.ComptimeTypeRecipePending,
                    .generic => |v| .{ .generic = .{ .base = try self.declaration(v.base), .arguments = try self.captureArguments(v.arguments, depth + 1) } },
                };
                break :blk Node{ .shape = description };
            };
            const result: Ids.TypeId = @enumFromInt(std.math.cast(u32, self.recipe.nodes.items.len) orelse return error.SemanticGraphTooLarge);
            try self.recipe.nodes.append(self.a, value);
            self.seen.getPtr(id).?.* = result;
            return result;
        }
        fn captureFields(self: *Capture, range: g.FieldRange, depth: usize) !p.Range(Ids.FieldId) {
            const fields = try self.a.alloc(p.Field(Ids), range.len);
            defer self.a.free(fields);
            for (self.graph.fields.items[range.start..][0..range.len], fields) |field, *out| {
                if (field.default_value) |node| if (@intFromEnum(node) >= self.boundary.nodes) return error.ComptimeTypeRecipePending;
                out.* = .{ .name = try self.string(field.name), .ty = try self.typeId(field.ty, depth), .source = field.source, .default_value = field.default_value };
            }
            const start = std.math.cast(u32, self.recipe.fields.items.len) orelse return error.SemanticGraphTooLarge;
            try self.recipe.fields.appendSlice(self.a, fields);
            return .{ .start = start, .len = range.len };
        }
        fn captureVariants(self: *Capture, range: g.VariantRange, depth: usize) !p.Range(Ids.VariantId) {
            const values = try self.a.alloc(p.ChoiceVariant(Ids), range.len);
            defer self.a.free(values);
            for (self.graph.variants.items[range.start..][0..range.len], values) |v, *out| out.* = .{ .name = try self.string(v.name), .qualifier = if (v.qualifier) |q| try self.string(q) else null, .payload_type = if (v.payload_type) |ty| try self.typeId(ty, depth) else null, .option_decl = if (v.option_decl) |decl| try self.declaration(decl) else null, .source = v.source, .value = v.value };
            const start = std.math.cast(u32, self.recipe.variants.items.len) orelse return error.SemanticGraphTooLarge;
            try self.recipe.variants.appendSlice(self.a, values);
            return .{ .start = start, .len = range.len };
        }
        fn captureArguments(self: *Capture, range: p.Range(g.GlobalGenericArgId), depth: usize) !p.Range(Ids.GenericArgId) {
            const values = try self.a.alloc(p.GenericArgument(Ids), range.len);
            defer self.a.free(values);
            for (self.graph.generic_arguments.items[range.start..][0..range.len], values) |v, *out| out.* = .{ .name = try self.string(v.name), .value = switch (v.value) {
                .type => |ty| .{ .type = try self.typeId(ty, depth) },
                .comptime_int => |n| .{ .comptime_int = n },
            } };
            const start = std.math.cast(u32, self.recipe.arguments.items.len) orelse return error.SemanticGraphTooLarge;
            try self.recipe.arguments.appendSlice(self.a, values);
            return .{ .start = start, .len = range.len };
        }
    };

    const Publish = struct {
        a: std.mem.Allocator,
        generics: *Generics,
        recipe: *const Recipe,
        mapped: []?g.GlobalTypeId,

        fn string(self: *Publish, range: p.StringRange) !p.StringRange {
            return self.generics.graph.addString(self.a, self.recipe.text(range));
        }
        fn typeId(self: *Publish, id: Ids.TypeId) anyerror!g.GlobalTypeId {
            const index = @intFromEnum(id);
            if (self.mapped[index]) |previous| return previous;
            const node = self.recipe.nodes.items[index];
            const result = if (node == .stable) node.stable else try self.generics.internType(switch (node.shape) {
                .builtin => |v| .{ .builtin = v },
                .declared => |v| .{ .declared = v },
                .pointer => |v| .{ .pointer = .{ .child = try self.typeId(v.child), .mutability = v.mutability } },
                .array => |v| .{ .array = .{ .element = try self.typeId(v.element), .length = v.length } },
                .nullable => |v| .{ .nullable = try self.typeId(v) },
                .inferred_errable, .inferred_choice => unreachable,
                .virtual => |v| .{ .virtual = try self.typeId(v) },
                .structural => |v| .{ .structural = .{ .fields = try self.publishFields(v.fields), .layout = v.layout } },
                .structural_choice => |v| .{ .structural_choice = .{ .variants = try self.publishVariants(v.variants), .layout = v.layout } },
                .generic => |v| .{ .generic = .{ .base = v.base, .arguments = try self.publishArguments(v.arguments) } },
            });
            self.mapped[index] = result;
            return result;
        }
        fn publishFields(self: *Publish, range: p.Range(Ids.FieldId)) !g.FieldRange {
            const values = try self.a.alloc(g.Field, range.len);
            defer self.a.free(values);
            for (self.recipe.fields.items[range.start..][0..range.len], values) |v, *out| out.* = .{ .name = try self.string(v.name), .ty = try self.typeId(v.ty), .source = v.source, .default_value = v.default_value };
            const start = std.math.cast(u32, self.generics.graph.fields.items.len) orelse return error.SemanticGraphTooLarge;
            try self.generics.graph.fields.appendSlice(self.a, values);
            return .{ .start = start, .len = range.len };
        }
        fn publishVariants(self: *Publish, range: p.Range(Ids.VariantId)) !g.VariantRange {
            const values = try self.a.alloc(g.ChoiceVariant, range.len);
            defer self.a.free(values);
            for (self.recipe.variants.items[range.start..][0..range.len], values) |v, *out| out.* = .{ .name = try self.string(v.name), .qualifier = if (v.qualifier) |q| try self.string(q) else null, .payload_type = if (v.payload_type) |ty| try self.typeId(ty) else null, .option_decl = v.option_decl, .source = v.source, .value = v.value };
            const start = std.math.cast(u32, self.generics.graph.variants.items.len) orelse return error.SemanticGraphTooLarge;
            try self.generics.graph.variants.appendSlice(self.a, values);
            return .{ .start = start, .len = range.len };
        }
        fn publishArguments(self: *Publish, range: p.Range(Ids.GenericArgId)) !p.Range(g.GlobalGenericArgId) {
            const values = try self.a.alloc(g.GenericArgument, range.len);
            defer self.a.free(values);
            for (self.recipe.arguments.items[range.start..][0..range.len], values) |v, *out| out.* = .{ .name = try self.string(v.name), .value = switch (v.value) {
                .type => |ty| .{ .type = try self.typeId(ty) },
                .comptime_int => |n| .{ .comptime_int = n },
            } };
            const start = std.math.cast(u32, self.generics.graph.generic_arguments.items.len) orelse return error.SemanticGraphTooLarge;
            try self.generics.graph.generic_arguments.appendSlice(self.a, values);
            return .{ .start = start, .len = range.len };
        }
    };
};

test "type recipes outlive rollback and distinguish reused type identities" {
    const a = std.testing.allocator;
    var graph: g.GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    try graph.types.appendSlice(a, &.{ .{ .builtin = .Int32 }, .{ .builtin = .Bool } });
    const checkpoint = graph.checkpoint();
    try graph.types.append(a, .{ .pointer = .{ .child = @enumFromInt(0), .mutability = .read_only } });
    const fields: g.FieldRange = .{ .start = 0, .len = 1 };
    try graph.fields.append(a, .{ .name = try graph.addString(a, "item"), .ty = @enumFromInt(2), .source = .{ .file_index = 0, .offset = 0 } });
    try graph.types.append(a, .{ .structural = .{ .fields = fields } });
    try graph.types.append(a, .{ .array = .{ .length = 3, .element = @enumFromInt(3) } });
    const roots = [_]?g.GlobalTypeId{@enumFromInt(4)};
    var recipe = try Recipe.capture(a, &graph, .{ .types = 2, .declarations = 0, .nodes = 0 }, &roots);
    defer recipe.deinit(a);
    var cloned = try recipe.clone(a);
    defer cloned.deinit(a);
    try std.testing.expect(try recipe.matches(a, &graph, &roots));
    graph.rollback(checkpoint);
    // The former pointer ID now names a pointer to Bool. Matching must use
    // the retained structure, not a recycled numerical identity.
    try graph.types.append(a, .{ .pointer = .{ .child = @enumFromInt(1), .mutability = .read_only } });
    try graph.fields.append(a, .{ .name = try graph.addString(a, "item"), .ty = @enumFromInt(2), .source = .{ .file_index = 0, .offset = 0 } });
    try graph.types.append(a, .{ .structural = .{ .fields = fields } });
    try graph.types.append(a, .{ .array = .{ .length = 3, .element = @enumFromInt(3) } });
    try std.testing.expect(!try cloned.matches(a, &graph, &roots));
    var core = @import("core.zig").Resolver{ .allocator = a, .graph = &graph, .modules = &.{}, .offsets = &.{} };
    defer core.deinitReachedCalls();
    var generics = Generics{ .allocator = a, .graph = &graph, .modules = &.{}, .offsets = &.{}, .core = &core };
    defer generics.deinit();
    var published: [1]?g.GlobalTypeId = undefined;
    try cloned.publish(a, &generics, &published);
    try std.testing.expect(try cloned.matches(a, &graph, &published));
    try std.testing.expect(published[0].? != roots[0].?);
}

fn captureAndCloneFailures(a: std.mem.Allocator) !void {
    var graph: g.GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    try graph.types.append(a, .{ .builtin = .Int32 });
    try graph.types.append(a, .{ .pointer = .{ .child = @enumFromInt(0), .mutability = .read_only } });
    try graph.fields.append(a, .{ .name = try graph.addString(a, "item"), .ty = @enumFromInt(1), .source = .{ .file_index = 0, .offset = 0 } });
    try graph.types.append(a, .{ .structural = .{ .fields = .{ .start = 0, .len = 1 } } });
    const roots = [_]?g.GlobalTypeId{@enumFromInt(2)};
    var recipe = try Recipe.capture(a, &graph, .{ .types = 1, .declarations = 0, .nodes = 0 }, &roots);
    defer recipe.deinit(a);
    var cloned = try recipe.clone(a);
    defer cloned.deinit(a);
    try std.testing.expect(try cloned.matches(a, &graph, &roots));
}

test "type recipes release failed capture cloning and comparison" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, captureAndCloneFailures, .{});
}

test "type recipes defer unstable defaults and open inferred identities" {
    const a = std.testing.allocator;
    var graph: g.GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    try graph.types.append(a, .{ .builtin = .Int32 });
    try graph.nodes.append(a, .{ .source = .{ .file_index = 0, .offset = 0 }, .ty = @enumFromInt(0), .content = .{ .int_literal = 42 } });
    try graph.fields.append(a, .{ .name = try graph.addString(a, "item"), .ty = @enumFromInt(0), .source = .{ .file_index = 0, .offset = 0 }, .default_value = @enumFromInt(0) });
    try graph.types.append(a, .{ .structural = .{ .fields = .{ .start = 0, .len = 1 } } });
    const roots = [_]?g.GlobalTypeId{@enumFromInt(1)};
    try std.testing.expectError(error.ComptimeTypeRecipePending, Recipe.capture(a, &graph, .{ .types = 1, .declarations = 0, .nodes = 0 }, &roots));
    var recipe = try Recipe.capture(a, &graph, .{ .types = 1, .declarations = 0, .nodes = 1 }, &roots);
    defer recipe.deinit(a);
    try std.testing.expect(try recipe.matches(a, &graph, &roots));
    graph.types.items[1] = .{ .inferred_choice = .{ .identity = 1, .kind = .reasons, .variants = .{ .start = 0, .len = 0 } } };
    try std.testing.expectError(error.ComptimeTypeRecipePending, Recipe.capture(a, &graph, .{ .types = 1, .declarations = 0, .nodes = 1 }, &roots));
}
