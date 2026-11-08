const std = @import("std");
const g = @import("graph.zig");
const ir = @import("../module/parameterized/ir.zig");
const p = @import("../primitives/schema.zig");
const Generics = @import("generics.zig").Resolver;
const types = @import("types.zig");

// Self-contained value descriptions carry no graph identities or runtime references.
// They participate in ordinary generic identity and survive module relocation.
pub fn encode(r: *Generics, module: usize, expression: ir.ParameterizedNodeId, bindings: *Generics.Bindings) !p.StringRange {
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(r.allocator);
    try encodeNode(r, module, expression, bindings, &bytes, 0);
    return r.graph.addString(r.allocator, bytes.items);
}

fn text(a: std.mem.Allocator, bytes: *std.ArrayList(u8), value: []const u8) !void {
    try bytes.appendSlice(a, std.mem.asBytes(&@as(u32, @intCast(value.len))));
    try bytes.appendSlice(a, value);
}

pub fn integer(r: *Generics, value: i128) !p.StringRange {
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(r.allocator);
    try bytes.append(r.allocator, 'i');
    try bytes.appendSlice(r.allocator, std.mem.asBytes(&value));
    return r.graph.addString(r.allocator, bytes.items);
}

pub fn integerValue(graph: *const g.GlobalSemanticGraph, encoded: p.StringRange) !i64 {
    const bytes = graph.text(encoded);
    if (bytes.len != 1 + @sizeOf(i128) or bytes[0] != 'i') return error.GenericArgumentKindMismatch;
    return std.math.cast(i64, std.mem.bytesToValue(i128, bytes[1..])) orelse error.ComptimeIntegerOverflow;
}

fn encodeNode(r: *Generics, module: usize, id: ir.ParameterizedNodeId, bindings: *Generics.Bindings, bytes: *std.ArrayList(u8), depth: usize) anyerror!void {
    if (depth > 128) return error.ComptimeValueTooDeep;
    const m = &r.modules[module];
    const storage = &m.semantic.parameterized_storage.ir;
    const node = storage.nodes.items[@intFromEnum(id)];
    const a = r.allocator;
    switch (node) {
        .pending => |pending_id| {
            const pending = storage.pending.items[@intFromEnum(pending_id)];
            if (pending == .resolve_expression) {
                const e = pending.resolve_expression;
                if (e.detail == .comptime_parameter) {
                    const raw = @intFromEnum(e.detail.comptime_parameter);
                    if (bindings.ints[raw]) |number| {
                        const widened: i128 = number;
                        try bytes.append(a, 'i');
                        return bytes.appendSlice(a, std.mem.asBytes(&widened));
                    }
                    const value = bindings.values[raw] orelse return error.UnboundComptimeParameter;
                    return bytes.appendSlice(a, r.graph.text(value));
                }
                if (e.kind == .list_value) {
                    try bytes.append(a, 'a');
                    try bytes.appendSlice(a, std.mem.asBytes(&e.operands.len));
                    for (storage.node_refs.items[e.operands.start..][0..e.operands.len]) |item| try encodeNode(r, module, item, bindings, bytes, depth + 1);
                    return;
                }
                if (e.kind == .choice_literal) {
                    try bytes.append(a, 'c');
                    try text(a, bytes, m.text(e.name.?));
                    try bytes.append(a, if (e.operands.len == 0) 0 else 1);
                    if (e.operands.len != 0) try encodeNode(r, module, storage.node_refs.items[e.operands.start], bindings, bytes, depth + 1);
                    return;
                }
            }
            r.comptime_failure = .{ .source = valueSource(r, module, if (pending == .resolve_expression) pending.resolve_expression.source else .{ .file_index = 0, .offset = 0 }), .reason = "compile-time value parameters require immutable literal values or forwarded value parameters" };
            return error.InvalidComptimeValue;
        },
        .resolved => |value| switch (value.content) {
            .string_literal => |v| {
                try bytes.append(a, 's');
                try text(a, bytes, m.text(v));
            },
            .bool_literal => |v| try bytes.append(a, if (v) 't' else 'f'),
            .int_literal => |v| {
                try bytes.append(a, 'i');
                try bytes.appendSlice(a, std.mem.asBytes(&v));
            },
            .float_literal => |v| {
                try bytes.append(a, 'd');
                try bytes.appendSlice(a, std.mem.asBytes(&v));
            },
            .struct_value_literal => |v| {
                try bytes.append(a, 'r');
                try bytes.appendSlice(a, std.mem.asBytes(&v.fields.len));
                const fields = try a.dupe(ir.ValueField, storage.value_fields.items[v.fields.start..][0..v.fields.len]);
                defer a.free(fields);
                // Named record field order is not part of value identity.
                std.mem.sort(ir.ValueField, fields, m, struct {
                    fn less(mod: @TypeOf(m), x: ir.ValueField, y: ir.ValueField) bool {
                        return std.mem.lessThan(u8, mod.text(x.name), mod.text(y.name));
                    }
                }.less);
                for (fields) |field| {
                    try text(a, bytes, m.text(field.name));
                    try encodeNode(r, module, field.value, bindings, bytes, depth + 1);
                }
            },
            .list_literal => |v| {
                try bytes.append(a, 'a');
                try bytes.appendSlice(a, std.mem.asBytes(&v.elements.len));
                for (storage.node_refs.items[v.elements.start..][0..v.elements.len]) |item| try encodeNode(r, module, item, bindings, bytes, depth + 1);
            },
            else => {
                r.comptime_failure = .{ .source = valueSource(r, module, value.source), .reason = "compile-time value parameters require immutable literals; references and runtime storage are not supported" };
                return error.InvalidComptimeValue;
            },
        },
    }
}

pub fn materialize(r: *Generics, encoded: p.StringRange, expected: g.GlobalTypeId, source: p.SourceRef) !g.GlobalNodeId {
    // Graph strings can grow while recursively decoding, so retain stable bytes.
    const bytes = try r.allocator.dupe(u8, r.graph.text(encoded));
    defer r.allocator.free(bytes);
    var decoder = Decoder{ .r = r, .bytes = bytes, .source = source };
    const result = decoder.value(expected, 0) catch |err| switch (err) {
        error.InvalidComptimeValueType => {
            r.comptime_failure = .{ .source = source, .reason = "compile-time value does not match its declared parameter type or contains unsupported storage" };
            return err;
        },
        else => return err,
    };
    if (decoder.index != bytes.len) return error.InvalidComptimeValueType;
    return result;
}

const Decoder = struct {
    r: *Generics,
    bytes: []const u8,
    index: usize = 0,
    source: p.SourceRef,

    fn take(d: *Decoder, n: usize) ![]const u8 {
        if (n > d.bytes.len - d.index) return error.InvalidComptimeValueType;
        defer d.index += n;
        return d.bytes[d.index..][0..n];
    }
    fn number(d: *Decoder, comptime T: type) !T {
        return std.mem.bytesToValue(T, try d.take(@sizeOf(T)));
    }
    fn string(d: *Decoder) ![]const u8 {
        return d.take(try d.number(u32));
    }
    fn append(d: *Decoder, ty: g.GlobalTypeId, content: g.Node.Content) !g.GlobalNodeId {
        return d.r.core.appendNode(d.source, ty, content);
    }
    fn value(d: *Decoder, expected: g.GlobalTypeId, depth: usize) anyerror!g.GlobalNodeId {
        if (depth > 128) return error.ComptimeValueTooDeep;
        _ = try d.r.ensureGenericInstance(expected);
        const graph = d.r.graph;
        const tag = (try d.take(1))[0];
        switch (tag) {
            's' => {
                const spelling = try d.string();
                const ty = d.r.core.defaultStringLiteralType() orelse return error.DeferredGenericFunction;
                if (!types.equal(graph, expected, ty)) return error.InvalidComptimeValueType;
                return d.append(expected, .{ .string_literal = try graph.addString(d.r.allocator, spelling) });
            },
            't', 'f' => {
                if (!types.isBuiltin(graph, expected, .Bool)) return error.InvalidComptimeValueType;
                return d.append(expected, .{ .bool_literal = tag == 't' });
            },
            'i' => {
                const n = try d.number(i128);
                const node = try d.append(try d.r.core.builtin(.Int32), .{ .int_literal = n });
                if (!d.r.core.contextualLiteralFits(node, expected) or !try d.r.core.coerceContextualValue(node, expected) or !types.equal(graph, graph.node(node).ty.?, expected)) return error.InvalidComptimeValueType;
                return node;
            },
            'd' => {
                const n = try d.number(f64);
                const node = try d.append(try d.r.core.builtin(.Float32), .{ .float_literal = n });
                if (!d.r.core.contextualLiteralFits(node, expected) or !try d.r.core.coerceContextualValue(node, expected) or !types.equal(graph, graph.node(node).ty.?, expected)) return error.InvalidComptimeValueType;
                return node;
            },
            'c' => {
                const name = try d.string();
                if (std.mem.startsWith(u8, name, "_")) return error.InvalidComptimeValueType;
                const variant = types.findVariant(graph, expected, name) orelse return error.InvalidComptimeValueType;
                const has_payload = (try d.take(1))[0] != 0;
                var payload: ?g.GlobalNodeId = null;
                if (has_payload) {
                    const ty = variant.variant.payload_type orelse return error.InvalidComptimeValueType;
                    if (d.index >= d.bytes.len) return error.InvalidComptimeValueType;
                    // Scalar choice syntax wraps its argument in (.value = ...).
                    if (types.fields(graph, ty) == null and d.bytes[d.index] == 'r') {
                        _ = try d.take(1);
                        if (try d.number(u32) != 1) return error.InvalidComptimeValueType;
                        const field = try d.string();
                        if (field.len != 0 and !std.mem.eql(u8, field, "value")) return error.InvalidComptimeValueType;
                    }
                    payload = try d.value(ty, depth + 1);
                } else if (variant.variant.payload_type != null) return error.InvalidComptimeValueType;
                return d.append(expected, .{ .choice_literal = .{ .choice_type = expected, .variant = variant.id, .payload = payload } });
            },
            'r' => {
                if (types.arrayLength(graph, expected) == 0) {
                    if (try d.number(u32) != 0) return error.InvalidComptimeValueType;
                    return d.append(expected, .{ .array_literal = .{ .element_type = types.arrayElement(graph, expected).?, .length = 0, .elements = .{ .start = 0, .len = 0 } } });
                }
                if (types.isCUnion(graph, types.representationType(graph, expected) orelse return error.DeferredGenericFunction)) return error.InvalidComptimeValueType;
                const range = types.fields(graph, expected) orelse return error.InvalidComptimeValueType;
                const fields = try d.r.allocator.dupe(g.Field, graph.fields.items[range.start..][0..range.len]);
                defer d.r.allocator.free(fields);
                if (try d.number(u32) != fields.len) return error.InvalidComptimeValueType;
                var values: std.ArrayList(g.ValueField) = .empty;
                defer values.deinit(d.r.allocator);
                for (0..fields.len) |_| {
                    const name = try d.string();
                    if (std.mem.startsWith(u8, name, "_")) return error.InvalidComptimeValueType;
                    const field = for (fields) |f| {
                        if (std.mem.eql(u8, graph.text(f.name), name)) break f;
                    } else return error.InvalidComptimeValueType;
                    for (values.items) |previous| if (std.mem.eql(u8, graph.text(previous.name), name)) return error.InvalidComptimeValueType;
                    try values.append(d.r.allocator, .{ .name = field.name, .value = try d.value(field.ty, depth + 1) });
                }
                const start: u32 = @intCast(graph.value_fields.items.len);
                try graph.value_fields.appendSlice(d.r.allocator, values.items);
                return d.append(expected, .{ .struct_value_literal = .{ .fields = .{ .start = start, .len = @intCast(values.items.len) } } });
            },
            'a' => {
                const n = try d.number(u32);
                const child = types.arrayElement(graph, expected) orelse return error.InvalidComptimeValueType;
                if (types.arrayLength(graph, expected) != n) return error.InvalidComptimeValueType;
                var elements: std.ArrayList(g.GlobalNodeId) = .empty;
                defer elements.deinit(d.r.allocator);
                for (0..n) |_| try elements.append(d.r.allocator, try d.value(child, depth + 1));
                const start: u32 = @intCast(graph.node_refs.items.len);
                try graph.node_refs.appendSlice(d.r.allocator, elements.items);
                return d.append(expected, .{ .array_literal = .{ .element_type = child, .length = n, .elements = .{ .start = start, .len = n } } });
            },
            else => return error.InvalidComptimeValueType,
        }
    }
};

fn valueSource(r: *Generics, module: usize, local: p.SourceRef) p.SourceRef {
    return .{ .file_index = r.offsets[module].file_base + local.file_index, .offset = local.offset };
}
