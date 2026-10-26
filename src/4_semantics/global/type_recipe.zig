const std = @import("std");
const g = @import("graph.zig");
const p = @import("../primitives/schema.zig");
const Generics = @import("generics.zig").Resolver;

const Ids = struct {
    pub const TypeId = enum(u32) { _ };
    pub const TypeDefinitionId = g.GlobalTypeDefinitionId;
    pub const FieldId = enum(u32) { _ };
    pub const VariantId = enum(u32) { _ };
    pub const GenericArgId = enum(u32) { _ };
    pub const DeclId = g.GlobalDeclId;
    pub const NodeId = enum(u32) { _ };
};
const Node = union(enum) { stable: g.GlobalTypeId, shape: p.SemanticType(Ids) };
const DefaultBinding = struct { ty: ?Ids.TypeId, integer: ?i64 };
const DefaultField = struct { name: p.StringRange, value: Ids.NodeId };
const PendingDefault = struct {
    module_index: usize,
    expression: @import("../module/parameterized/ir.zig").ParameterizedNodeId,
    bindings: p.Range(u32),
};
const Default = union(enum) {
    stable: g.GlobalNodeId,
    literal: struct {
        source: p.SourceRef,
        ty: ?Ids.TypeId,
        value: union(enum) {
            int: i128,
            float: f64,
            char: u32,
            boolean: bool,
            string: p.StringRange,
            type: Ids.TypeId,
            pending: PendingDefault,
            choice: struct { choice_type: Ids.TypeId, ordinal: u32, payload: ?Ids.NodeId },
            record: struct { fields: p.Range(u32), positional: u32 },
            array: struct { elements: p.Range(u32), element_type: Ids.TypeId, length: u32 },
        },
    },
};

/// Immutable type descriptions owned independently of a speculative graph tail.
/// Only identities preceding the resolution pass can remain graph references.
/// Pools retain sharing within the captured type DAG, without copying the graph.
pub const Recipe = struct {
    pub const Boundary = struct { types: usize, declarations: usize, nodes: usize, type_definitions: usize = 0 };
    nodes: std.ArrayList(Node) = .empty,
    defaults: std.ArrayList(Default) = .empty,
    default_bindings: std.ArrayList(DefaultBinding) = .empty,
    default_fields: std.ArrayList(DefaultField) = .empty,
    default_elements: std.ArrayList(Ids.NodeId) = .empty,
    fields: std.ArrayList(p.Field(Ids)) = .empty,
    variants: std.ArrayList(p.ChoiceVariant(Ids)) = .empty,
    arguments: std.ArrayList(p.GenericArgument(Ids)) = .empty,
    strings: std.ArrayList(u8) = .empty,
    roots: []?Ids.TypeId = &.{},

    pub fn deinit(self: *Recipe, a: std.mem.Allocator) void {
        self.nodes.deinit(a);
        self.defaults.deinit(a);
        self.default_bindings.deinit(a);
        self.default_fields.deinit(a);
        self.default_elements.deinit(a);
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
        inline for (.{ "nodes", "defaults", "default_bindings", "default_fields", "default_elements", "fields", "variants", "arguments", "strings" }) |name|
            try @field(result, name).appendSlice(a, @field(self, name).items);
        result.roots = try a.dupe(?Ids.TypeId, self.roots);
        return result;
    }

    pub fn capture(a: std.mem.Allocator, graph: *const g.GlobalSemanticGraph, boundary: Boundary, roots: []const ?g.GlobalTypeId) !Recipe {
        var result: Recipe = .{};
        errdefer result.deinit(a);
        var context = Capture{ .a = a, .graph = graph, .boundary = boundary, .recipe = &result };
        defer context.seen.deinit(a);
        defer context.seen_defaults.deinit(a);
        result.roots = try a.alloc(?Ids.TypeId, roots.len);
        for (roots, result.roots) |root, *out| out.* = if (root) |ty| try context.typeId(ty, 0) else null;
        return result;
    }

    /// Rebuild into the coordinator's construction graph, never a losing probe.
    /// The caller publishes the complete type set atomically before resuming IR.
    pub fn publish(self: *const Recipe, a: std.mem.Allocator, generics: *Generics, roots: []?g.GlobalTypeId) !void {
        var context = Publish{ .a = a, .generics = generics, .recipe = self, .mapped = try a.alloc(?g.GlobalTypeId, self.nodes.items.len) };
        defer a.free(context.mapped);
        context.defaults = try a.alloc(?g.GlobalNodeId, self.defaults.items.len);
        defer a.free(context.defaults);
        @memset(context.defaults, null);
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

        fn defaultValue(self: *Match, saved: ?Ids.NodeId, current: ?g.GlobalNodeId) anyerror!bool {
            if (saved == null or current == null) return saved == null and current == null;
            if (@intFromEnum(current.?) >= self.graph.nodes.items.len) return false;
            const value = self.recipe.defaults.items[@intFromEnum(saved.?)];
            if (value == .stable) return value.stable == current.?;
            const literal = value.literal;
            const actual = self.graph.node(current.?);
            // Source identity distinguishes otherwise equal defaults from
            // different declarations, while values reject recycled node IDs.
            if (!std.meta.eql(literal.source, actual.source)) return false;
            if (literal.ty == null or actual.ty == null) {
                if ((literal.ty == null) != (actual.ty == null)) return false;
            } else if (!try self.typeId(literal.ty.?, actual.ty.?)) return false;
            return switch (literal.value) {
                .int => |v| actual.content == .int_literal and actual.content.int_literal == v,
                .float => |v| actual.content == .float_literal and @as(u64, @bitCast(actual.content.float_literal)) == @as(u64, @bitCast(v)),
                .char => |v| actual.content == .char_literal and actual.content.char_literal == v,
                .boolean => |v| actual.content == .bool_literal and actual.content.bool_literal == v,
                .string => |v| actual.content == .string_literal and std.mem.eql(u8, self.recipe.text(v), self.graph.text(actual.content.string_literal)),
                .type => |v| actual.content == .type_literal and try self.typeId(v, actual.content.type_literal),
                .choice => |v| choice: {
                    if (actual.content != .choice_literal) break :choice false;
                    const selected = actual.content.choice_literal;
                    if (!try self.typeId(v.choice_type, selected.choice_type)) break :choice false;
                    const variants = @import("types.zig").variants(self.graph, selected.choice_type) orelse break :choice false;
                    if (v.ordinal >= variants.len or @intFromEnum(selected.variant) != variants.start + v.ordinal) break :choice false;
                    break :choice try self.defaultValue(v.payload, selected.payload);
                },
                .array => |v| array: {
                    if (actual.content != .array_literal) break :array false;
                    const literal_array = actual.content.array_literal;
                    if (literal_array.length != v.length or literal_array.elements.len != v.elements.len or !try self.typeId(v.element_type, literal_array.element_type)) break :array false;
                    for (self.recipe.default_elements.items[v.elements.start..][0..v.elements.len], self.graph.node_refs.items[literal_array.elements.start..][0..v.elements.len]) |left, right|
                        if (!try self.defaultValue(left, right)) break :array false;
                    break :array true;
                },
                .record => |v| record: {
                    if (actual.content != .struct_value_literal) break :record false;
                    const literal_record = actual.content.struct_value_literal;
                    if (literal_record.assumed_fields.len != 0 or literal_record.dispatch_prefix_positional_count != v.positional or literal_record.fields.len != v.fields.len) break :record false;
                    for (self.recipe.default_fields.items[v.fields.start..][0..v.fields.len], self.graph.value_fields.items[literal_record.fields.start..][0..v.fields.len]) |left, right| {
                        if (!std.mem.eql(u8, self.recipe.text(left.name), self.graph.text(right.name)) or !try self.defaultValue(left.value, right.value)) break :record false;
                    }
                    break :record true;
                },
                .pending => |v| pending: {
                    if (actual.content != .argument_default) break :pending false;
                    const expression = self.graph.argument_defaults.items[actual.content.argument_default];
                    if (expression.module_index != v.module_index or expression.expression != v.expression or expression.bindings.len != v.bindings.len) break :pending false;
                    for (self.recipe.default_bindings.items[v.bindings.start..][0..v.bindings.len], self.graph.argument_default_bindings.items[expression.bindings.start..][0..expression.bindings.len]) |saved_binding, current_binding| {
                        if (saved_binding.integer != current_binding.integer) break :pending false;
                        if (saved_binding.ty == null or current_binding.ty == null) {
                            if ((saved_binding.ty == null) != (current_binding.ty == null)) break :pending false;
                        } else if (!try self.typeId(saved_binding.ty.?, current_binding.ty.?)) break :pending false;
                    }
                    break :pending true;
                },
            };
        }

        fn compare(self: *Match, saved: Ids.TypeId, current: g.GlobalTypeId) anyerror!bool {
            const graph = self.graph;
            const node = self.recipe.nodes.items[@intFromEnum(saved)];
            if (node == .stable) return node.stable == current or @import("types.zig").identityEqual(graph, node.stable, current);
            const shape = node.shape;
            const actual = graph.types.items[@intFromEnum(current)];
            if (@intFromEnum(std.meta.activeTag(shape)) != @intFromEnum(std.meta.activeTag(actual))) return false;
            return switch (shape) {
                .builtin => |value| value == actual.builtin,
                .nominal => |value| value == actual.nominal,
                .definition => |value| value == actual.definition,
                .pointer => |value| value.mutability == actual.pointer.mutability and try self.typeId(value.child, actual.pointer.child),
                .array => |value| value.length == actual.array.length and try self.typeId(value.element, actual.array.element),
                .nullable => |value| try self.typeId(value, actual.nullable),
                .inferred_errable => |value| try self.typeId(value, actual.inferred_errable),
                .inferred_choice => unreachable,
                .virtual => |value| try self.typeId(value, actual.virtual),
                .structural => |value| blk: {
                    if (value.layout != actual.structural.layout or value.fields.len != actual.structural.fields.len) break :blk false;
                    for (self.recipe.fields.items[value.fields.start..][0..value.fields.len], graph.fields.items[actual.structural.fields.start..][0..value.fields.len]) |left, right| {
                        if (!std.mem.eql(u8, self.recipe.text(left.name), graph.text(right.name)) or !try self.defaultValue(left.default_value, right.default_value) or !try self.typeId(left.ty, right.ty)) break :blk false;
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
        seen_defaults: std.AutoHashMapUnmanaged(g.GlobalNodeId, Ids.NodeId) = .empty,

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
                    .nominal => |v| .{ .nominal = if (@intFromEnum(v) < self.boundary.type_definitions) v else return error.ComptimeTypeRecipePending },
                    .definition => |v| .{ .definition = try self.declaration(v) },
                    .pointer => |v| .{ .pointer = .{ .child = try self.typeId(v.child, depth + 1), .mutability = v.mutability } },
                    .array => |v| .{ .array = .{ .element = try self.typeId(v.element, depth + 1), .length = v.length } },
                    .nullable => |v| .{ .nullable = try self.typeId(v, depth + 1) },
                    // This wrapper has no independent inferred identity. Keep
                    // its pending state and reconstruct its value type normally.
                    .inferred_errable => |v| .{ .inferred_errable = try self.typeId(v, depth + 1) },
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
        fn defaultValue(self: *Capture, id: g.GlobalNodeId, depth: usize) !Ids.NodeId {
            if (depth > 256) return error.CompileTimeTypeDepthLimit;
            if (self.seen_defaults.get(id)) |previous| return previous;
            const value: Default = if (@intFromEnum(id) < self.boundary.nodes)
                .{ .stable = id }
            else value: {
                const node = self.graph.node(id);
                const literal: @FieldType(@FieldType(Default, "literal"), "value") = switch (node.content) {
                    .int_literal => |v| .{ .int = v },
                    .float_literal => |v| .{ .float = v },
                    .char_literal => |v| .{ .char = v },
                    .bool_literal => |v| .{ .boolean = v },
                    .string_literal => |v| .{ .string = try self.string(v) },
                    .type_literal => |v| .{ .type = try self.typeId(v, depth) },
                    .choice_literal => |v| choice: {
                        const variants = @import("types.zig").variants(self.graph, v.choice_type) orelse return error.ComptimeTypeRecipePending;
                        const variant = @intFromEnum(v.variant);
                        if (variant < variants.start or variant - variants.start >= variants.len) return error.ComptimeTypeRecipePending;
                        break :choice .{ .choice = .{
                            .choice_type = try self.typeId(v.choice_type, depth + 1),
                            .ordinal = variant - variants.start,
                            .payload = if (v.payload) |payload| try self.defaultValue(payload, depth + 1) else null,
                        } };
                    },
                    .array_literal => |v| array: {
                        const elements = try self.a.alloc(Ids.NodeId, v.elements.len);
                        defer self.a.free(elements);
                        for (self.graph.node_refs.items[v.elements.start..][0..v.elements.len], elements) |element, *out| out.* = try self.defaultValue(element, depth + 1);
                        const element_type = try self.typeId(v.element_type, depth + 1);
                        const start = std.math.cast(u32, self.recipe.default_elements.items.len) orelse return error.SemanticGraphTooLarge;
                        try self.recipe.default_elements.appendSlice(self.a, elements);
                        break :array .{ .array = .{ .elements = .{ .start = start, .len = v.elements.len }, .element_type = element_type, .length = v.length } };
                    },
                    .struct_value_literal => |v| record: {
                        if (v.assumed_fields.len != 0) return error.ComptimeTypeRecipePending;
                        const fields = try self.a.alloc(DefaultField, v.fields.len);
                        defer self.a.free(fields);
                        for (self.graph.value_fields.items[v.fields.start..][0..v.fields.len], fields) |field, *out|
                            out.* = .{ .name = try self.string(field.name), .value = try self.defaultValue(field.value, depth + 1) };
                        const start = std.math.cast(u32, self.recipe.default_fields.items.len) orelse return error.SemanticGraphTooLarge;
                        try self.recipe.default_fields.appendSlice(self.a, fields);
                        break :record .{ .record = .{ .fields = .{ .start = start, .len = v.fields.len }, .positional = v.dispatch_prefix_positional_count } };
                    },
                    .argument_default => |v| pending: {
                        if (v >= self.graph.argument_defaults.items.len) return error.ComptimeTypeRecipePending;
                        const expression = self.graph.argument_defaults.items[v];
                        const bindings = try self.a.alloc(DefaultBinding, expression.bindings.len);
                        defer self.a.free(bindings);
                        for (self.graph.argument_default_bindings.items[expression.bindings.start..][0..expression.bindings.len], bindings) |binding, *out| {
                            out.* = .{ .ty = if (binding.ty) |ty| try self.typeId(ty, depth + 1) else null, .integer = binding.integer };
                        }
                        const start = std.math.cast(u32, self.recipe.default_bindings.items.len) orelse return error.SemanticGraphTooLarge;
                        try self.recipe.default_bindings.appendSlice(self.a, bindings);
                        break :pending .{ .pending = .{ .module_index = expression.module_index, .expression = expression.expression, .bindings = .{ .start = start, .len = expression.bindings.len } } };
                    },
                    else => return error.ComptimeTypeRecipePending,
                };
                break :value .{ .literal = .{ .source = node.source, .ty = if (node.ty) |ty| try self.typeId(ty, depth) else null, .value = literal } };
            };
            const result: Ids.NodeId = @enumFromInt(std.math.cast(u32, self.recipe.defaults.items.len) orelse return error.SemanticGraphTooLarge);
            try self.recipe.defaults.append(self.a, value);
            try self.seen_defaults.put(self.a, id, result);
            return result;
        }

        fn captureFields(self: *Capture, range: g.FieldRange, depth: usize) !p.Range(Ids.FieldId) {
            const fields = try self.a.alloc(p.Field(Ids), range.len);
            defer self.a.free(fields);
            for (self.graph.fields.items[range.start..][0..range.len], fields) |field, *out| {
                out.* = .{ .name = try self.string(field.name), .ty = try self.typeId(field.ty, depth), .source = field.source, .default_value = if (field.default_value) |id| try self.defaultValue(id, depth) else null };
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
        defaults: []?g.GlobalNodeId = &.{},

        fn string(self: *Publish, range: p.StringRange) !p.StringRange {
            return self.generics.graph.addString(self.a, self.recipe.text(range));
        }
        fn typeId(self: *Publish, id: Ids.TypeId) anyerror!g.GlobalTypeId {
            const index = @intFromEnum(id);
            if (self.mapped[index]) |previous| return previous;
            const node = self.recipe.nodes.items[index];
            const result = if (node == .stable) node.stable else try self.generics.internType(switch (node.shape) {
                .builtin => |v| .{ .builtin = v },
                .nominal => |v| .{ .nominal = v },
                .definition => |v| .{ .definition = v },
                .pointer => |v| .{ .pointer = .{ .child = try self.typeId(v.child), .mutability = v.mutability } },
                .array => |v| .{ .array = .{ .element = try self.typeId(v.element), .length = v.length } },
                .nullable => |v| .{ .nullable = try self.typeId(v) },
                .inferred_errable => |v| .{ .inferred_errable = try self.typeId(v) },
                .inferred_choice => unreachable,
                .virtual => |v| .{ .virtual = try self.typeId(v) },
                .structural => |v| .{ .structural = .{ .fields = try self.publishFields(v.fields), .layout = v.layout } },
                .structural_choice => |v| .{ .structural_choice = .{ .variants = try self.publishVariants(v.variants), .layout = v.layout } },
                .generic => |v| .{ .generic = .{ .base = v.base, .arguments = try self.publishArguments(v.arguments) } },
            });
            self.mapped[index] = result;
            return result;
        }
        fn defaultValue(self: *Publish, id: Ids.NodeId) !g.GlobalNodeId {
            const index = @intFromEnum(id);
            if (self.defaults[index]) |previous| return previous;
            const value = self.recipe.defaults.items[index];
            const result = if (value == .stable) value.stable else result: {
                const literal = value.literal;
                const node: g.Node = .{
                    .source = literal.source,
                    .ty = if (literal.ty) |ty| try self.typeId(ty) else null,
                    .content = switch (literal.value) {
                        .int => |v| .{ .int_literal = v },
                        .float => |v| .{ .float_literal = v },
                        .char => |v| .{ .char_literal = v },
                        .boolean => |v| .{ .bool_literal = v },
                        .string => |v| .{ .string_literal = try self.string(v) },
                        .type => |v| .{ .type_literal = try self.typeId(v) },
                        .choice => |v| choice: {
                            const choice_type = try self.typeId(v.choice_type);
                            _ = try self.generics.ensureGenericInstance(choice_type);
                            const variants = @import("types.zig").variants(self.generics.graph, choice_type) orelse return error.ComptimeTypeRecipePending;
                            if (v.ordinal >= variants.len) return error.ComptimeTypeRecipePending;
                            break :choice .{ .choice_literal = .{
                                .choice_type = choice_type,
                                .variant = @enumFromInt(variants.start + v.ordinal),
                                .payload = if (v.payload) |payload| try self.defaultValue(payload) else null,
                            } };
                        },
                        .array => |v| array: {
                            const elements = try self.a.alloc(g.GlobalNodeId, v.elements.len);
                            defer self.a.free(elements);
                            for (self.recipe.default_elements.items[v.elements.start..][0..v.elements.len], elements) |element, *out| out.* = try self.defaultValue(element);
                            const element_type = try self.typeId(v.element_type);
                            const start = std.math.cast(u32, self.generics.graph.node_refs.items.len) orelse return error.SemanticGraphTooLarge;
                            try self.generics.graph.node_refs.appendSlice(self.a, elements);
                            break :array .{ .array_literal = .{ .elements = .{ .start = start, .len = v.elements.len }, .element_type = element_type, .length = v.length } };
                        },
                        .record => |v| record: {
                            const fields = try self.a.alloc(g.ValueField, v.fields.len);
                            defer self.a.free(fields);
                            for (self.recipe.default_fields.items[v.fields.start..][0..v.fields.len], fields) |field, *out|
                                out.* = .{ .name = try self.string(field.name), .value = try self.defaultValue(field.value) };
                            const start = std.math.cast(u32, self.generics.graph.value_fields.items.len) orelse return error.SemanticGraphTooLarge;
                            try self.generics.graph.value_fields.appendSlice(self.a, fields);
                            break :record .{ .struct_value_literal = .{ .fields = .{ .start = start, .len = v.fields.len }, .dispatch_prefix_positional_count = v.positional } };
                        },
                        .pending => |v| pending: {
                            const bindings = try self.a.alloc(g.ArgumentDefaultBinding, v.bindings.len);
                            defer self.a.free(bindings);
                            for (self.recipe.default_bindings.items[v.bindings.start..][0..v.bindings.len], bindings) |binding, *out| {
                                out.* = .{ .ty = if (binding.ty) |ty| try self.typeId(ty) else null, .integer = binding.integer };
                            }
                            const graph = self.generics.graph;
                            const start = std.math.cast(u32, graph.argument_default_bindings.items.len) orelse return error.SemanticGraphTooLarge;
                            try graph.argument_default_bindings.appendSlice(self.a, bindings);
                            const recipe = std.math.cast(u32, graph.argument_defaults.items.len) orelse return error.SemanticGraphTooLarge;
                            try graph.argument_defaults.append(self.a, .{ .module_index = v.module_index, .expression = v.expression, .bindings = .{ .start = start, .len = v.bindings.len } });
                            break :pending .{ .argument_default = recipe };
                        },
                    },
                };
                const published: g.GlobalNodeId = @enumFromInt(std.math.cast(u32, self.generics.graph.nodes.items.len) orelse return error.SemanticGraphTooLarge);
                try self.generics.graph.nodes.append(self.a, node);
                break :result published;
            };
            self.defaults[index] = result;
            return result;
        }

        fn publishFields(self: *Publish, range: p.Range(Ids.FieldId)) !g.FieldRange {
            const values = try self.a.alloc(g.Field, range.len);
            defer self.a.free(values);
            for (self.recipe.fields.items[range.start..][0..range.len], values) |v, *out| out.* = .{ .name = try self.string(v.name), .ty = try self.typeId(v.ty), .source = v.source, .default_value = if (v.default_value) |id| try self.defaultValue(id) else null };
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
    graph.rollback(a, checkpoint);
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
    try graph.types.append(a, .{ .inferred_errable = @enumFromInt(2) });
    const roots = [_]?g.GlobalTypeId{@enumFromInt(3)};
    var recipe = try Recipe.capture(a, &graph, .{ .types = 1, .declarations = 0, .nodes = 0 }, &roots);
    defer recipe.deinit(a);
    var cloned = try recipe.clone(a);
    defer cloned.deinit(a);
    try std.testing.expect(try cloned.matches(a, &graph, &roots));
}

test "type recipes release failed capture cloning and comparison" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, captureAndCloneFailures, .{});
}

fn aggregateDefaultFailures(a: std.mem.Allocator, array: bool) !void {
    const owner = a;
    var graph: g.GlobalSemanticGraph = .{};
    defer graph.deinit(owner);
    try graph.types.append(owner, .{ .builtin = .Int32 });
    const checkpoint = graph.checkpoint();
    const source = p.SourceRef{ .file_index = 0, .offset = 12 };
    for ([_][]const u8{ "first", "second" }) |name|
        try graph.fields.append(owner, .{ .name = try graph.addString(owner, name), .source = source, .ty = @enumFromInt(0) });
    try graph.types.append(owner, .{ .structural = .{ .fields = .{ .start = 0, .len = 2 } } });
    try graph.nodes.append(owner, .{ .source = source, .ty = @enumFromInt(0), .content = .{ .int_literal = 42 } });
    for (graph.fields.items[0..2]) |field| try graph.value_fields.append(owner, .{ .name = field.name, .value = @enumFromInt(0) });
    try graph.nodes.append(owner, .{ .source = source, .ty = @enumFromInt(1), .content = .{ .struct_value_literal = .{ .fields = .{ .start = 0, .len = 2 } } } });
    try graph.fields.append(owner, .{ .name = try graph.addString(owner, "options"), .source = source, .ty = @enumFromInt(1), .default_value = @enumFromInt(1) });
    try graph.types.append(owner, .{ .structural = .{ .fields = .{ .start = 2, .len = 1 } } });
    if (array) {
        graph.types.items[1] = .{ .array = .{ .element = @enumFromInt(0), .length = 2 } };
        try graph.node_refs.appendSlice(a, &.{ @enumFromInt(0), @enumFromInt(0) });
        graph.nodes.items[1].content = .{ .array_literal = .{ .elements = .{ .start = 0, .len = 2 }, .element_type = @enumFromInt(0), .length = 2 } };
    }
    const roots = [_]?g.GlobalTypeId{@enumFromInt(2)};
    var recipe = try Recipe.capture(a, &graph, .{ .types = 1, .declarations = 0, .nodes = 0 }, &roots);
    defer recipe.deinit(a);
    var retained = try recipe.clone(a);
    defer retained.deinit(a);
    try std.testing.expect(try retained.matches(a, &graph, &roots));
    graph.nodes.items[0].content.int_literal = 99;
    try std.testing.expect(!try retained.matches(a, &graph, &roots));
    graph.rollback(a, checkpoint);
    try graph.types.append(owner, .{ .builtin = .Bool });
    try graph.nodes.append(owner, .{ .source = source, .ty = @enumFromInt(0), .content = .{ .int_literal = 99 } });
    var core = @import("core.zig").Resolver{ .allocator = a, .graph = &graph, .modules = &.{}, .offsets = &.{} };
    defer core.deinitReachedCalls();
    var generics = Generics{ .allocator = a, .graph = &graph, .modules = &.{}, .offsets = &.{}, .core = &core };
    defer generics.deinit();
    var published: [1]?g.GlobalTypeId = undefined;
    try retained.publish(a, &generics, &published);
    try std.testing.expect(try retained.matches(a, &graph, &published));
    const outer = graph.types.items[@intFromEnum(published[0].?)].structural.fields;
    const default = graph.node(graph.fields.items[outer.start].default_value.?);
    if (array) {
        const elements = default.content.array_literal.elements;
        try std.testing.expectEqual(@as(u32, 2), elements.len);
        const first = graph.node_refs.items[elements.start];
        try std.testing.expectEqual(first, graph.node_refs.items[elements.start + 1]);
        try std.testing.expectEqual(@as(i128, 42), graph.node(first).content.int_literal);
        try std.testing.expectEqual(@as(u64, 2), graph.semanticType(default.ty.?).array.length);
        return;
    }
    const fields = default.content.struct_value_literal.fields;
    try std.testing.expectEqual(@as(u32, 2), fields.len);
    const first = graph.value_fields.items[fields.start];
    try std.testing.expectEqualStrings("first", graph.text(first.name));
    try std.testing.expectEqual(first.value, graph.value_fields.items[fields.start + 1].value);
    try std.testing.expectEqual(@as(i128, 42), graph.node(first.value).content.int_literal);
}

test "type recipes preserve record defaults across rollback and allocation failures" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, aggregateDefaultFailures, .{false});
}

test "type recipes preserve array defaults across rollback and allocation failures" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, aggregateDefaultFailures, .{true});
}

test "record default recipes do not transport lexical capability candidate pools" {
    const a = std.testing.allocator;
    var graph: g.GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    const source = p.SourceRef{ .file_index = 0, .offset = 0 };
    const name = try graph.addString(a, "options");
    try graph.types.appendSlice(a, &.{
        .{ .structural = .{ .fields = .{ .start = 0, .len = 0 } } },
        .{ .structural = .{ .fields = .{ .start = 0, .len = 1 } } },
    });
    try graph.nodes.append(a, .{ .source = source, .ty = @enumFromInt(0), .content = .{ .struct_value_literal = .{ .fields = .{ .start = 0, .len = 0 }, .assumed_fields = .{ .start = 0, .len = 1 } } } });
    try graph.value_fields.append(a, .{ .name = name, .value = @enumFromInt(0) });
    try graph.fields.append(a, .{ .name = name, .source = source, .ty = @enumFromInt(0), .default_value = @enumFromInt(0) });
    try std.testing.expectError(error.ComptimeTypeRecipePending, Recipe.capture(a, &graph, .{ .types = 1, .nodes = 0, .declarations = 0 }, &.{@enumFromInt(1)}));
}

test "type recipes defer unresolved defaults and open inferred identities" {
    const a = std.testing.allocator;
    var graph: g.GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    try graph.types.append(a, .{ .builtin = .Int32 });
    try graph.nodes.append(a, .{ .source = .{ .file_index = 0, .offset = 0 }, .ty = @enumFromInt(0), .content = .{ .argument_default = 0 } });
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

test "type recipes retain literal defaults and their origins across rollback" {
    const allocator = std.testing.allocator;
    var graph: g.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);
    try graph.types.append(allocator, .{ .builtin = .Int32 });
    const checkpoint = graph.checkpoint();
    const source = p.SourceRef{ .file_index = 0, .offset = 7 };
    try graph.nodes.append(allocator, .{ .source = source, .ty = @enumFromInt(0), .content = .{ .int_literal = 42 } });
    for ([_][]const u8{ "first", "second" }) |name| try graph.fields.append(allocator, .{ .name = try graph.addString(allocator, name), .ty = @enumFromInt(0), .source = source, .default_value = @enumFromInt(0) });
    try graph.types.append(allocator, .{ .structural = .{ .fields = .{ .start = 0, .len = 2 } } });
    const roots = [_]?g.GlobalTypeId{@enumFromInt(1)};
    var recipe = try Recipe.capture(allocator, &graph, .{ .types = 1, .declarations = 0, .nodes = 0 }, &roots);
    defer recipe.deinit(allocator);
    var retained = try recipe.clone(allocator);
    defer retained.deinit(allocator);
    try std.testing.expect(try retained.matches(allocator, &graph, &roots));
    graph.rollback(allocator, checkpoint);
    try graph.nodes.append(allocator, .{ .source = source, .ty = @enumFromInt(0), .content = .{ .int_literal = 99 } });
    for ([_][]const u8{ "first", "second" }) |name| try graph.fields.append(allocator, .{ .name = try graph.addString(allocator, name), .ty = @enumFromInt(0), .source = source, .default_value = @enumFromInt(0) });
    try graph.types.append(allocator, .{ .structural = .{ .fields = .{ .start = 0, .len = 2 } } });
    try std.testing.expect(!try retained.matches(allocator, &graph, &roots));
    graph.nodes.items[0].content = .{ .int_literal = 42 };
    graph.nodes.items[0].source.offset = 8;
    try std.testing.expect(!try retained.matches(allocator, &graph, &roots));
    var core = @import("core.zig").Resolver{ .allocator = allocator, .graph = &graph, .modules = &.{}, .offsets = &.{} };
    defer core.deinitReachedCalls();
    var generics = Generics{ .allocator = allocator, .graph = &graph, .modules = &.{}, .offsets = &.{}, .core = &core };
    defer generics.deinit();
    var published: [1]?g.GlobalTypeId = undefined;
    try retained.publish(allocator, &generics, &published);
    try std.testing.expect(try retained.matches(allocator, &graph, &published));
    const fields = graph.types.items[@intFromEnum(published[0].?)].structural.fields;
    const first = graph.fields.items[fields.start].default_value.?;
    try std.testing.expectEqual(first, graph.fields.items[fields.start + 1].default_value.?);
    try std.testing.expect(first != @as(g.GlobalNodeId, @enumFromInt(0)));
    try std.testing.expectEqual(@as(i128, 42), graph.node(first).content.int_literal);
    try std.testing.expectEqual(source, graph.node(first).source);
}

test "type recipes preserve literal precision and owned string bytes after rollback" {
    const a = std.testing.allocator;
    var graph: g.GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    try graph.types.appendSlice(a, &.{ .{ .builtin = .Float64 }, .{ .builtin = .Bool }, .{ .builtin = .UInt32 } });
    const checkpoint = graph.checkpoint();
    const source = p.SourceRef{ .file_index = 0, .offset = 9 };
    const nan: f64 = @bitCast(@as(u64, 0x7ff8000000000042));
    const string = try graph.addString(a, "retained text");
    try graph.nodes.appendSlice(a, &.{
        .{ .source = source, .ty = @enumFromInt(0), .content = .{ .float_literal = -0.0 } },
        .{ .source = source, .ty = @enumFromInt(0), .content = .{ .float_literal = nan } },
        .{ .source = source, .ty = @enumFromInt(1), .content = .{ .bool_literal = true } },
        .{ .source = source, .ty = @enumFromInt(2), .content = .{ .char_literal = 0x1f642 } },
        .{ .source = source, .ty = null, .content = .{ .string_literal = string } },
        .{ .source = source, .ty = null, .content = .{ .type_literal = @enumFromInt(0) } },
    });
    const names = [_][]const u8{ "zero", "nan", "boolean", "scalar", "text", "type" };
    for (names, 0..) |name, index| try graph.fields.append(a, .{
        .name = try graph.addString(a, name),
        .source = source,
        .ty = @enumFromInt(0),
        .default_value = @enumFromInt(index),
    });
    try graph.types.append(a, .{ .structural = .{ .fields = .{ .start = 0, .len = names.len } } });
    var recipe = try Recipe.capture(a, &graph, .{ .types = 3, .declarations = 0, .nodes = 0 }, &.{@enumFromInt(3)});
    defer recipe.deinit(a);
    try std.testing.expect(try recipe.matches(a, &graph, &.{@enumFromInt(3)}));
    graph.nodes.items[0].content = .{ .float_literal = 0.0 };
    try std.testing.expect(!try recipe.matches(a, &graph, &.{@enumFromInt(3)}));
    graph.rollback(a, checkpoint);
    _ = try graph.addString(a, "overwritten graph string storage");
    var core = @import("core.zig").Resolver{ .allocator = a, .graph = &graph, .modules = &.{}, .offsets = &.{} };
    defer core.deinitReachedCalls();
    var generics = Generics{ .allocator = a, .graph = &graph, .modules = &.{}, .offsets = &.{}, .core = &core };
    defer generics.deinit();
    var published: [1]?g.GlobalTypeId = undefined;
    try recipe.publish(a, &generics, &published);
    try std.testing.expect(try recipe.matches(a, &graph, &published));
    const fields = graph.types.items[@intFromEnum(published[0].?)].structural.fields;
    const zero = graph.node(graph.fields.items[fields.start].default_value.?).content.float_literal;
    const retained_nan = graph.node(graph.fields.items[fields.start + 1].default_value.?).content.float_literal;
    const text = graph.node(graph.fields.items[fields.start + 4].default_value.?).content.string_literal;
    try std.testing.expectEqual(@as(u64, 0x8000000000000000), @as(u64, @bitCast(zero)));
    try std.testing.expectEqual(@as(u64, @bitCast(nan)), @as(u64, @bitCast(retained_nan)));
    try std.testing.expectEqualStrings("retained text", graph.text(text));
}

fn pendingDefaultFailures(a: std.mem.Allocator) !void {
    var graph: g.GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    const source = p.SourceRef{ .file_index = 0, .offset = 5 };
    try graph.types.append(a, .{ .builtin = .Int32 });
    const checkpoint = graph.checkpoint();
    try graph.types.append(a, .{ .pointer = .{ .child = @enumFromInt(0), .mutability = .read_only } });
    try graph.argument_default_bindings.appendSlice(a, &.{ .{ .ty = @enumFromInt(1), .integer = null }, .{ .ty = null, .integer = 42 } });
    try graph.argument_defaults.append(a, .{ .module_index = 0, .expression = @enumFromInt(7), .bindings = .{ .start = 0, .len = 2 } });
    try graph.nodes.append(a, .{ .source = source, .ty = @enumFromInt(0), .content = .{ .argument_default = 0 } });
    const name = try graph.addString(a, "value");
    try graph.fields.append(a, .{ .name = name, .ty = @enumFromInt(0), .source = source, .default_value = @enumFromInt(0) });
    try graph.types.append(a, .{ .structural = .{ .fields = .{ .start = 0, .len = 1 } } });
    var recipe = try Recipe.capture(a, &graph, .{ .types = 1, .declarations = 0, .nodes = 0 }, &.{@enumFromInt(2)});
    defer recipe.deinit(a);
    var retained = try recipe.clone(a);
    defer retained.deinit(a);
    try std.testing.expect(try retained.matches(a, &graph, &.{@enumFromInt(2)}));
    graph.argument_default_bindings.items[1].integer = 43;
    try std.testing.expect(!try retained.matches(a, &graph, &.{@enumFromInt(2)}));
    graph.rollback(a, checkpoint);
    // Recycled graph pools cannot become part of the retained substitution.
    try graph.types.append(a, .{ .builtin = .Bool });
    try graph.argument_defaults.append(a, .{ .module_index = 0, .expression = @enumFromInt(99), .bindings = .{ .start = 0, .len = 0 } });
    var core = @import("core.zig").Resolver{ .allocator = a, .graph = &graph, .modules = &.{}, .offsets = &.{} };
    defer core.deinitReachedCalls();
    var generics = Generics{ .allocator = a, .graph = &graph, .modules = &.{}, .offsets = &.{}, .core = &core };
    defer generics.deinit();
    var published: [1]?g.GlobalTypeId = undefined;
    try retained.publish(a, &generics, &published);
    try std.testing.expect(try retained.matches(a, &graph, &published));
    const fields = graph.types.items[@intFromEnum(published[0].?)].structural.fields;
    const node = graph.node(graph.fields.items[fields.start].default_value.?);
    const expression = graph.argument_defaults.items[node.content.argument_default];
    try std.testing.expectEqual(@as(u32, 7), @intFromEnum(expression.expression));
    const bindings = graph.argument_default_bindings.items[expression.bindings.start..][0..expression.bindings.len];
    try std.testing.expectEqual(@as(?i64, 42), bindings[1].integer);
    try std.testing.expect(graph.semanticType(bindings[0].ty.?) == .pointer);
}

test "type recipes retain pending default substitutions through rollback and allocation failures" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, pendingDefaultFailures, .{});
}

fn choiceDefaultFailures(a: std.mem.Allocator, with_payload: bool) !void {
    var graph: g.GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    try graph.types.append(a, .{ .builtin = .Int32 });
    const checkpoint = graph.checkpoint();
    const source = p.SourceRef{ .file_index = 0, .offset = 31 };
    const name = try graph.addString(a, "option");
    try graph.variants.appendSlice(a, &.{
        .{ .name = try graph.addString(a, "empty"), .source = source, .value = 0 },
        .{ .name = try graph.addString(a, "present"), .source = source, .value = 1, .payload_type = @enumFromInt(0) },
    });
    try graph.types.append(a, .{ .structural_choice = .{ .variants = .{ .start = 0, .len = 2 } } });
    try graph.nodes.appendSlice(a, &.{
        .{ .source = source, .ty = @enumFromInt(0), .content = .{ .int_literal = 42 } },
        .{ .source = source, .ty = @enumFromInt(1), .content = .{ .choice_literal = .{
            .choice_type = @enumFromInt(1),
            .variant = @enumFromInt(@intFromBool(with_payload)),
            .payload = if (with_payload) @enumFromInt(0) else null,
        } } },
    });
    for (0..2) |_| try graph.fields.append(a, .{ .name = name, .ty = @enumFromInt(1), .source = source, .default_value = @enumFromInt(1) });
    try graph.types.append(a, .{ .structural = .{ .fields = .{ .start = 0, .len = 2 } } });
    const roots = [_]?g.GlobalTypeId{@enumFromInt(2)};
    var recipe = try Recipe.capture(a, &graph, .{ .types = 1, .declarations = 0, .nodes = 0 }, &roots);
    defer recipe.deinit(a);
    var retained = try recipe.clone(a);
    defer retained.deinit(a);
    try std.testing.expect(try retained.matches(a, &graph, &roots));
    graph.nodes.items[1].content.choice_literal.variant = @enumFromInt(@intFromBool(!with_payload));
    try std.testing.expect(!try retained.matches(a, &graph, &roots));
    graph.nodes.items[1].content.choice_literal.variant = @enumFromInt(@intFromBool(with_payload));
    if (with_payload) {
        graph.nodes.items[0].content.int_literal = 99;
        try std.testing.expect(!try retained.matches(a, &graph, &roots));
    }
    graph.rollback(a, checkpoint);
    // Recycle both type and variant IDs before reconstructing the saved value.
    try graph.types.append(a, .{ .builtin = .Bool });
    try graph.variants.append(a, .{ .name = try graph.addString(a, "unrelated"), .source = source, .value = 0 });
    var core = @import("core.zig").Resolver{ .allocator = a, .graph = &graph, .modules = &.{}, .offsets = &.{} };
    defer core.deinitReachedCalls();
    var generics = Generics{ .allocator = a, .graph = &graph, .modules = &.{}, .offsets = &.{}, .core = &core };
    defer generics.deinit();
    var published: [1]?g.GlobalTypeId = undefined;
    try retained.publish(a, &generics, &published);
    try std.testing.expect(try retained.matches(a, &graph, &published));
    const fields = graph.semanticType(published[0].?).structural.fields;
    const first = graph.fields.items[fields.start].default_value.?;
    try std.testing.expectEqual(first, graph.fields.items[fields.start + 1].default_value.?);
    const selected = graph.node(first).content.choice_literal;
    const variants = @import("types.zig").variants(&graph, selected.choice_type).?;
    try std.testing.expectEqual(variants.start + @intFromBool(with_payload), @intFromEnum(selected.variant));
    if (with_payload) {
        try std.testing.expectEqual(@as(i128, 42), graph.node(selected.payload.?).content.int_literal);
    } else try std.testing.expect(selected.payload == null);
}

test "type recipes preserve payload defaults across rollback and allocation failures" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, choiceDefaultFailures, .{true});
}

test "type recipes preserve payloadless defaults across rollback and allocation failures" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, choiceDefaultFailures, .{false});
}

test "type recipes preserve pending errable wrappers without retaining speculative type IDs" {
    const a = std.testing.allocator;
    var graph: g.GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    try graph.types.appendSlice(a, &.{ .{ .builtin = .Int32 }, .{ .builtin = .Bool } });
    const checkpoint = graph.checkpoint();
    try graph.types.append(a, .{ .array = .{ .element = @enumFromInt(0), .length = 3 } });
    try graph.types.append(a, .{ .inferred_errable = @enumFromInt(2) });
    const roots = [_]?g.GlobalTypeId{@enumFromInt(3)};
    var recipe = try Recipe.capture(a, &graph, .{ .types = 2, .declarations = 0, .nodes = 0 }, &roots);
    defer recipe.deinit(a);
    var cloned = try recipe.clone(a);
    defer cloned.deinit(a);
    try std.testing.expect(try cloned.matches(a, &graph, &roots));
    graph.rollback(a, checkpoint);
    try graph.types.append(a, .{ .array = .{ .element = @enumFromInt(1), .length = 3 } });
    try graph.types.append(a, .{ .inferred_errable = @enumFromInt(2) });
    try std.testing.expect(!try cloned.matches(a, &graph, &roots));
    var core = @import("core.zig").Resolver{ .allocator = a, .graph = &graph, .modules = &.{}, .offsets = &.{} };
    defer core.deinitReachedCalls();
    var generics = Generics{ .allocator = a, .graph = &graph, .modules = &.{}, .offsets = &.{}, .core = &core };
    defer generics.deinit();
    var published: [1]?g.GlobalTypeId = undefined;
    try cloned.publish(a, &generics, &published);
    try std.testing.expect(try cloned.matches(a, &graph, &published));
    try std.testing.expect(published[0].? != roots[0].?);
    const wrapper = graph.types.items[@intFromEnum(published[0].?)];
    try std.testing.expect(wrapper == .inferred_errable);
    const child = graph.types.items[@intFromEnum(wrapper.inferred_errable)];
    try std.testing.expect(child == .array);
    try std.testing.expectEqual(@as(u64, 3), child.array.length);
    try std.testing.expectEqual(@as(g.GlobalTypeId, @enumFromInt(0)), child.array.element);
}

test "type recipes retain anonymous nominal definitions across speculative type rollback" {
    const a = std.testing.allocator;
    var graph: g.GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    try graph.types.append(a, .{ .builtin = .Int32 });
    try graph.type_definitions.append(a, .{ .source = .{ .file_index = 0, .offset = 17 }, .underlying_type = @enumFromInt(0) });
    const checkpoint = graph.checkpoint();
    try graph.types.append(a, .{ .nominal = @enumFromInt(0) });
    const input = [_]?g.GlobalTypeId{@enumFromInt(1)};
    var recipe = try Recipe.capture(a, &graph, .{ .types = 1, .declarations = 0, .nodes = 0, .type_definitions = 1 }, &input);
    defer recipe.deinit(a);
    graph.rollback(a, checkpoint);
    try graph.types.append(a, .{ .builtin = .Bool });
    try std.testing.expect(!try recipe.matches(a, &graph, &input));
    var core = @import("core.zig").Resolver{ .allocator = a, .graph = &graph, .modules = &.{}, .offsets = &.{} };
    defer core.deinitReachedCalls();
    var generics = Generics{ .allocator = a, .graph = &graph, .modules = &.{}, .offsets = &.{}, .core = &core };
    defer generics.deinit();
    var output: [1]?g.GlobalTypeId = .{null};
    try recipe.publish(a, &generics, &output);
    try std.testing.expectEqual(@as(g.GlobalTypeDefinitionId, @enumFromInt(0)), graph.semanticType(output[0].?).nominal);
    try std.testing.expectEqual(@as(usize, 0), graph.declarations.items.len);
    try std.testing.expectEqualStrings("<anonymous>", graph.typeDefinitionName(@enumFromInt(0)));
}
