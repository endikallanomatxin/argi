const std = @import("std");
const syn = @import("../3_syntax/syntax_tree.zig");
const tok = @import("../2_tokens/token.zig");
const sg = @import("semantic_graph.zig");
const Scope = @import("scope.zig").Scope;

const diagnostics = @import("../1_base/diagnostic.zig");
const err = @import("errors.zig");

pub const TypedExpr = struct {
    node: *sg.SGNode,
    ty: sg.Type,
};

pub const BuiltinTypeInfoKind = enum {
    size,
    alignment,
};

const OwnedText = struct {
    allocator: *const std.mem.Allocator,
    bytes: []u8,

    fn deinit(self: OwnedText) void {
        self.allocator.free(self.bytes);
    }
};

const TypePairText = struct {
    expected: OwnedText,
    actual: OwnedText,

    fn deinit(self: TypePairText) void {
        self.expected.deinit();
        self.actual.deinit();
    }
};

pub const pointer_size_bytes: u64 = @sizeOf(*usize);
pub const pointer_alignment_bytes: u64 = pointer_size_bytes;

pub fn typesStructurallyEqual(a: sg.Type, b: sg.Type) bool {
    return switch (a) {
        .builtin => |ab| switch (b) {
            .builtin => |bb| ab == bb,
            else => false,
        },
        .abstract_type => |aat| switch (b) {
            .abstract_type => |bat| std.mem.eql(u8, aat.name, bat.name),
            else => false,
        },

        .struct_type => |ast| switch (b) {
            .builtin => false,
            .abstract_type => false,

            .struct_type => |bst| blk: {
                // Keep for legacy: structural comparison of anonymous structs
                if (ast.fields.len != bst.fields.len) break :blk false;
                var i: usize = 0;
                while (i < ast.fields.len) : (i += 1) {
                    const fa = ast.fields[i];
                    const fb = bst.fields[i];
                    if (!std.mem.eql(u8, fa.name, fb.name)) break :blk false;
                    if (!typesStructurallyEqual(fa.ty, fb.ty)) break :blk false;
                }
                break :blk true;
            },

            .pointer_type => false,
            .array_type => false,
        },

        .pointer_type => |apt_ptr| switch (b) {
            .pointer_type => |bpt_ptr| blk: {
                const apt = apt_ptr.*;
                const bpt = bpt_ptr.*;

                if (apt.mutability != bpt.mutability)
                    break :blk false;

                const sub_a = apt.child.*;
                const sub_b = bpt.child.*;

                if (isAny(sub_a) or isAny(sub_b)) break :blk true;

                break :blk typesStructurallyEqual(sub_a, sub_b);
            },
            else => false,
        },

        .array_type => |aat_ptr| switch (b) {
            .array_type => |bat_ptr| blk_arr: {
                const aat = aat_ptr.*;
                const bat = bat_ptr.*;
                if (aat.length != bat.length) break :blk_arr false;
                break :blk_arr typesStructurallyEqual(aat.element_type.*, bat.element_type.*);
            },
            else => false,
        },
    };
}

// Strict type equality: no wildcards; pointer subtypes must match exactly.
pub fn typesExactlyEqual(a: sg.Type, b: sg.Type) bool {
    return switch (a) {
        .builtin => |ab| switch (b) {
            .builtin => |bb| ab == bb,
            else => false,
        },
        .abstract_type => |aat| switch (b) {
            .abstract_type => |bat| std.mem.eql(u8, aat.name, bat.name),
            else => false,
        },
        .struct_type => |ast| switch (b) {
            .struct_type => |bst| ast == bst, // nominal: same named type instance
            else => false,
        },
        .pointer_type => |apt_ptr| switch (b) {
            .pointer_type => |bpt_ptr| blk: {
                const apt = apt_ptr.*;
                const bpt = bpt_ptr.*;
                if (apt.mutability != bpt.mutability) break :blk false;
                break :blk typesExactlyEqual(apt.child.*, bpt.child.*);
            },
            else => false,
        },
        .array_type => |aat_ptr| switch (b) {
            .array_type => |bat_ptr| blk_arr: {
                const aat = aat_ptr.*;
                const bat = bat_ptr.*;
                if (aat.length != bat.length) break :blk_arr false;
                break :blk_arr typesExactlyEqual(aat.element_type.*, bat.element_type.*);
            },
            else => false,
        },
    };
}

pub fn isAny(t: sg.Type) bool {
    return switch (t) {
        .builtin => |bt| bt == .Any,
        else => false,
    };
}

pub fn isIntegerType(t: sg.Type) bool {
    return switch (t) {
        .builtin => |bt| switch (bt) {
            .Int8, .Int16, .Int32, .Int64, .UIntNative, .UInt8, .UInt16, .UInt32, .UInt64 => true,
            else => false,
        },
        else => false,
    };
}

pub fn pointerToAny(mutability: syn.PointerMutability, allocator: *const std.mem.Allocator) !sg.Type {
    const child = try allocator.create(sg.Type);
    child.* = .{ .builtin = .Any };

    const sem_ptr = try allocator.create(sg.PointerType);
    sem_ptr.* = .{
        .mutability = mutability,
        .child = child,
    };

    return .{ .pointer_type = sem_ptr };
}

pub fn pointerMutabilityCompatible(expected: syn.PointerMutability, actual: syn.PointerMutability) bool {
    return switch (expected) {
        .read_only => true,
        .read_write => actual == .read_write,
    };
}

pub fn typesCompatible(expected: sg.Type, actual: sg.Type) bool {
    return switch (expected) {
        .builtin => |eb| switch (actual) {
            .builtin => |ab| eb == ab,
            else => false,
        },
        .abstract_type => |eat| switch (actual) {
            .abstract_type => |aat| std.mem.eql(u8, eat.name, aat.name),
            else => false,
        },
        .struct_type => |est| switch (actual) {
            .struct_type => |ast| blk: {
                if (est.fields.len != ast.fields.len) break :blk false;
                var i: usize = 0;
                while (i < est.fields.len) : (i += 1) {
                    const ef = est.fields[i];
                    const af = ast.fields[i];
                    if (!typesCompatible(ef.ty, af.ty)) break :blk false;
                }
                break :blk true;
            },
            else => false,
        },
        .pointer_type => |ept_ptr| switch (actual) {
            .pointer_type => |apt_ptr| blk: {
                const ept = ept_ptr.*;
                const apt = apt_ptr.*;

                if (!pointerMutabilityCompatible(ept.mutability, apt.mutability))
                    break :blk false;

                const expected_child = ept.child.*;
                const actual_child = apt.child.*;

                if (isAny(expected_child) or isAny(actual_child))
                    break :blk true;

                break :blk typesCompatible(expected_child, actual_child);
            },
            else => false,
        },
        .array_type => |eat_ptr| switch (actual) {
            .array_type => |aat_ptr| blk_arr: {
                const eat = eat_ptr.*;
                const aat = aat_ptr.*;
                if (eat.length != aat.length) break :blk_arr false;
                break :blk_arr typesCompatible(eat.element_type.*, aat.element_type.*);
            },
            else => false,
        },
    };
}

pub fn functionReturnType(fn_decl: *sg.FunctionDeclaration) sg.Type {
    return switch (fn_decl.output.fields.len) {
        0 => .{ .builtin = .Any },
        1 => fn_decl.output.fields[0].ty,
        else => .{ .struct_type = &fn_decl.output },
    };
}

pub fn typeNameFor(s: *Scope, t: sg.Type) ?[]const u8 {
    var cur: ?*Scope = s;
    while (cur) |sc| : (cur = sc.parent) {
        var it = sc.types.iterator();
        while (it.next()) |entry| {
            const td = entry.value_ptr.*;
            if (typesExactlyEqual(td.ty, t)) return td.name;
        }
    }
    return null;
}

pub fn builtinFromName(name: []const u8) ?sg.BuiltinType {
    return std.meta.stringToEnum(sg.BuiltinType, name);
}

pub fn findFieldByName(st: *const sg.StructType, name: []const u8) ?*const sg.StructTypeField {
    for (st.fields, 0..) |f, i| {
        if (std.mem.eql(u8, f.name, name)) return &st.fields[i];
    }
    return null;
}

fn appendType(buf: *std.array_list.Managed(u8), t: sg.Type) !void {
    switch (t) {
        .builtin => |bt| {
            const s = @tagName(bt);
            try buf.appendSlice(s);
        },
        .abstract_type => |at| try buf.appendSlice(at.name),
        .pointer_type => |ptr_info_ptr| {
            const ptr_info = ptr_info_ptr.*;
            const prefix = if (ptr_info.mutability == .read_write) "$&" else "&";
            try buf.appendSlice(prefix);
            try appendType(buf, ptr_info.child.*);
        },
        .struct_type => |st| {
            try buf.appendSlice("{");
            var i: usize = 0;
            while (i < st.fields.len) : (i += 1) {
                const fld = st.fields[i];
                if (i != 0) try buf.appendSlice(", ");
                try buf.appendSlice(".");
                try buf.appendSlice(fld.name);
                try buf.appendSlice(": ");
                try appendType(buf, fld.ty);
            }
            try buf.appendSlice("}");
        },
    }
}

pub fn formatType(t: sg.Type, s: *Scope, allocator: *const std.mem.Allocator) ![]u8 {
    var buf = std.array_list.Managed(u8).init(allocator.*);
    errdefer buf.deinit();
    try appendTypePretty(&buf, t, s);
    return try buf.toOwnedSlice();
}

fn formatOwnedText(bytes: []u8, allocator: *const std.mem.Allocator) OwnedText {
    return .{ .allocator = allocator, .bytes = bytes };
}

fn formatTypeText(ty: sg.Type, s: *Scope, allocator: *const std.mem.Allocator) !OwnedText {
    return formatOwnedText(try formatType(ty, s, allocator), allocator);
}

fn formatTypePairText(expected: sg.Type, actual: sg.Type, s: *Scope, allocator: *const std.mem.Allocator) !TypePairText {
    return .{
        .expected = try formatTypeText(expected, s, allocator),
        .actual = try formatTypeText(actual, s, allocator),
    };
}

pub fn appendTypePretty(buf: *std.array_list.Managed(u8), t: sg.Type, s: *Scope) !void {
    if (typeNameFor(s, t)) |nm| {
        try buf.appendSlice(nm);
        return;
    }
    switch (t) {
        .builtin => |bt| {
            const sname = @tagName(bt);
            try buf.appendSlice(sname);
        },
        .abstract_type => |at| try buf.appendSlice(at.name),
        .pointer_type => |ptr_info_ptr| {
            const ptr_info = ptr_info_ptr.*;
            const prefix = if (ptr_info.mutability == .read_write) "$&" else "&";
            try buf.appendSlice(prefix);
            try appendTypePretty(buf, ptr_info.child.*, s);
        },
        .struct_type => |_| {
            // Fallback: avoid expanding anonymous structs in this context
            try buf.appendSlice("{...}");
        },
        .array_type => |arr_ptr| {
            const arr = arr_ptr.*;
            var tmp: [32]u8 = undefined;
            const len_slice = std.fmt.bufPrint(&tmp, "{d}", .{arr.length}) catch "?";
            try buf.appendSlice("[");
            try buf.appendSlice(len_slice);
            try buf.appendSlice("]");
            try appendTypePretty(buf, arr.element_type.*, s);
        },
    }
}

pub fn formatCallInput(st: *const sg.StructType, s: *Scope, allocator: *const std.mem.Allocator) ![]u8 {
    var buf = std.array_list.Managed(u8).init(allocator.*);
    errdefer buf.deinit();

    try buf.appendSlice("(");
    var i: usize = 0;
    while (i < st.fields.len) : (i += 1) {
        const fld = st.fields[i];
        if (i != 0) try buf.appendSlice(", ");
        try buf.appendSlice(".");
        try buf.appendSlice(fld.name);
        try buf.appendSlice(": ");
        try appendTypePretty(&buf, fld.ty, s);
    }
    try buf.appendSlice(")");

    return try buf.toOwnedSlice();
}

pub fn computeTypeSize(ty: sg.Type) u64 {
    return switch (ty) {
        .builtin => |bt| switch (bt) {
            .Int8, .UInt8, .Char, .Bool => 1,
            .Int16, .UInt16, .Float16 => 2,
            .Int32, .UInt32, .Float32 => 4,
            .Int64, .UInt64, .Float64 => 8,
            .UIntNative => pointer_size_bytes,
            .Type => pointer_size_bytes,
            .Any => pointer_size_bytes,
        },
        .abstract_type => 0,
        .pointer_type => pointer_size_bytes,
        .struct_type => |st| blk: {
            const max_align = computeTypeAlignment(.{ .struct_type = st });
            var size: u64 = 0;
            var idx: usize = 0;
            while (idx < st.fields.len) : (idx += 1) {
                const fld = st.fields[idx];
                const field_align = computeTypeAlignment(fld.ty);
                const field_size = computeTypeSize(fld.ty);
                size = alignForward(size, field_align);
                size += field_size;
            }
            break :blk alignForward(size, max_align);
        },
        .array_type => |arr_ptr| blk_arr: {
            const elem_size = computeTypeSize(arr_ptr.element_type.*);
            const len_u64: u64 = @intCast(arr_ptr.length);
            break :blk_arr elem_size * len_u64;
        },
    };
}

pub fn computeTypeAlignment(ty: sg.Type) u64 {
    return switch (ty) {
        .builtin => |bt| switch (bt) {
            .Int8, .UInt8, .Char, .Bool => 1,
            .Int16, .UInt16, .Float16 => 2,
            .Int32, .UInt32, .Float32 => 4,
            .Int64, .UInt64, .Float64 => 8,
            .UIntNative => pointer_alignment_bytes,
            .Type => pointer_alignment_bytes,
            .Any => pointer_alignment_bytes,
        },
        .abstract_type => 1,
        .pointer_type => pointer_alignment_bytes,
        .struct_type => |st| blk: {
            var max_align: u64 = 1;
            var idx: usize = 0;
            while (idx < st.fields.len) : (idx += 1) {
                const fld_align = computeTypeAlignment(st.fields[idx].ty);
                if (fld_align > max_align) max_align = fld_align;
            }
            break :blk if (max_align == 0) 1 else max_align;
        },
        .array_type => |arr_ptr| computeTypeAlignment(arr_ptr.element_type.*),
    };
}

fn alignForward(value: u64, alignment: u64) u64 {
    if (alignment <= 1) return value;
    const mask = alignment - 1;
    return (value + mask) & ~mask;
}

pub fn makeIntLiteral(
    allocator: *const std.mem.Allocator,
    loc: tok.Location,
    value: i64,
    ty: sg.Type,
) !TypedExpr {
    const node = try allocator.create(sg.SGNode);
    node.* = .{
        .location = loc,
        .sem_type = ty,
        .content = .{ .value_literal = .{ .int_literal = value } },
    };
    return .{ .node = node, .ty = ty };
}

pub fn makeTypeLiteral(
    allocator: *const std.mem.Allocator,
    loc: tok.Location,
    ty: sg.Type,
) !TypedExpr {
    const type_node = try allocator.create(sg.TypeLiteral);
    type_node.* = .{ .ty = ty };
    const node = try allocator.create(sg.SGNode);
    node.* = .{
        .location = loc,
        .sem_type = .{ .builtin = .Type },
        .content = .{ .type_literal = type_node },
    };
    return .{ .node = node, .ty = .{ .builtin = .Type } };
}

pub fn intLiteralAs(
    target: sg.BuiltinType,
    value: i64,
    loc: tok.Location,
    allocator: *const std.mem.Allocator,
    diags: *diagnostics.Diagnostics,
) err.SemErr!?TypedExpr {
    const type_name = @tagName(target);
    return switch (target) {
        .Int8, .Int16, .Int32, .Int64 => blk_signed: {
            const Bounds = struct { min: i64, max: i64 };
            const bounds: Bounds = switch (target) {
                .Int8 => .{ .min = @as(i64, std.math.minInt(i8)), .max = @as(i64, std.math.maxInt(i8)) },
                .Int16 => .{ .min = @as(i64, std.math.minInt(i16)), .max = @as(i64, std.math.maxInt(i16)) },
                .Int32 => .{ .min = @as(i64, std.math.minInt(i32)), .max = @as(i64, std.math.maxInt(i32)) },
                .Int64 => .{ .min = std.math.minInt(i64), .max = std.math.maxInt(i64) },
                else => unreachable,
            };
            if (value < bounds.min or value > bounds.max) {
                try diags.add(
                    loc,
                    .semantic,
                    "integer literal {d} does not fit in '{s}' (min {d}, max {d})",
                    .{ value, type_name, bounds.min, bounds.max },
                );
                return error.Reported;
            }
            break :blk_signed try makeIntLiteral(allocator, loc, value, .{ .builtin = target });
        },
        .UIntNative, .UInt8, .UInt16, .UInt32, .UInt64 => blk_unsigned: {
            if (value < 0) {
                try diags.add(
                    loc,
                    .semantic,
                    "integer literal {d} does not fit in '{s}' (min 0)",
                    .{ value, type_name },
                );
                return error.Reported;
            }
            const max_val: u64 = switch (target) {
                .UIntNative => std.math.maxInt(usize),
                .UInt8 => std.math.maxInt(u8),
                .UInt16 => std.math.maxInt(u16),
                .UInt32 => std.math.maxInt(u32),
                .UInt64 => std.math.maxInt(u64),
                else => unreachable,
            };
            const unsigned_value: u64 = @intCast(value);
            if (unsigned_value > max_val) {
                try diags.add(
                    loc,
                    .semantic,
                    "integer literal {d} does not fit in '{s}' (max {d})",
                    .{ value, type_name, max_val },
                );
                return error.Reported;
            }
            break :blk_unsigned try makeIntLiteral(allocator, loc, value, .{ .builtin = target });
        },
        else => null,
    };
}

fn floatLiteralAs(
    target: sg.BuiltinType,
    value: f64,
    loc: tok.Location,
    allocator: *const std.mem.Allocator,
) err.SemErr!?TypedExpr {
    return switch (target) {
        .Float16, .Float32, .Float64 => blk: {
            const node = try allocator.create(sg.SGNode);
            node.* = .{
                .location = loc,
                .content = .{ .value_literal = .{ .float_literal = value } },
            };
            break :blk TypedExpr{ .node = node, .ty = .{ .builtin = target } };
        },
        else => null,
    };
}

pub fn coerceLiteralToBuiltin(
    target: sg.BuiltinType,
    expr: TypedExpr,
    expr_node: *const syn.STNode,
    allocator: *const std.mem.Allocator,
    diags: *diagnostics.Diagnostics,
) err.SemErr!TypedExpr {
    if (expr.node.content != .value_literal) return expr;

    const lit = expr.node.content.value_literal;
    switch (lit) {
        .int_literal => |value| {
            const maybe = try intLiteralAs(target, value, expr_node.location, allocator, diags);
            if (maybe) |converted| return converted;
        },
        .float_literal => |value| {
            const maybe = try floatLiteralAs(target, value, expr_node.location, allocator);
            if (maybe) |converted| return converted;
        },
        else => {},
    }
    return expr;
}

pub fn coerceExprToType(
    expected: sg.Type,
    expr: TypedExpr,
    expr_node: *const syn.STNode,
    s: *Scope,
    allocator: *const std.mem.Allocator,
    diags: *diagnostics.Diagnostics,
) err.SemErr!TypedExpr {
    if (typesExactlyEqual(expected, expr.ty)) return expr;

    return switch (expected) {
        .array_type => |arr_info| convertListLiteralToArray(expr, arr_info, expr_node.location, s, allocator, diags),
        .builtin => |bt| try coerceLiteralToBuiltin(bt, expr, expr_node, allocator, diags),
        .struct_type => |st| try coerceStructLiteral(st, expr, expr_node, s, allocator, diags),
        else => expr,
    };
}

pub fn convertListLiteralToArray(
    expr: TypedExpr,
    arr_info: *const sg.ArrayType,
    loc: tok.Location,
    s: *Scope,
    allocator: *const std.mem.Allocator,
    diags: *diagnostics.Diagnostics,
) err.SemErr!TypedExpr {
    switch (expr.node.content) {
        .list_literal => |ll| {
            if (ll.elements.len != arr_info.length) {
                try diags.add(
                    loc,
                    .semantic,
                    "array expects {d} elements, but list literal has {d}",
                    .{ arr_info.length, ll.elements.len },
                );
                return error.Reported;
            }

            const expected_elem_ty = arr_info.element_type.*;
            for (ll.element_types, 0..) |elem_ty, idx| {
                if (typesStructurallyEqual(expected_elem_ty, elem_ty)) continue;
                const pair = try formatTypePairText(expected_elem_ty, elem_ty, s, allocator);
                defer pair.deinit();
                try diags.add(
                    loc,
                    .semantic,
                    "array element {d} has type '{s}', expected '{s}'",
                    .{ idx, pair.actual.bytes, pair.expected.bytes },
                );
                return error.Reported;
            }

            const arr_lit = try allocator.create(sg.ArrayLiteral);
            arr_lit.* = .{
                .elements = ll.elements,
                .element_type = expected_elem_ty,
                .length = arr_info.length,
            };

            const node = try allocator.create(sg.SGNode);
            node.* = .{
                .location = loc,
                .content = .{ .array_literal = arr_lit },
            };
            return .{ .node = node, .ty = .{ .array_type = arr_info } };
        },
        else => {},
    }

    const pair = try formatTypePairText(.{ .array_type = arr_info }, expr.ty, s, allocator);
    defer pair.deinit();
    try diags.add(
        loc,
        .semantic,
        "cannot initialize array of type '{s}' with expression of type '{s}'",
        .{ pair.expected.bytes, pair.actual.bytes },
    );
    return error.Reported;
}

pub fn coerceStructLiteral(
    expected: *const sg.StructType,
    expr: TypedExpr,
    expr_node: *const syn.STNode,
    s: *Scope,
    allocator: *const std.mem.Allocator,
    diags: *diagnostics.Diagnostics,
) err.SemErr!TypedExpr {
    if (expr.node.content != .struct_value_literal) return expr;
    const lit = expr.node.content.struct_value_literal;
    const actual_struct = lit.ty.struct_type;

    if (lit.fields.len != actual_struct.fields.len) {
        return expr;
    }

    var coerced_fields = try allocator.alloc(sg.StructValueLiteralField, expected.fields.len);
    errdefer allocator.free(coerced_fields);

    for (lit.fields) |actual_field| {
        if (findFieldByName(expected, actual_field.name) == null) {
            allocator.free(coerced_fields);
            return expr;
        }
    }

    var i: usize = 0;
    while (i < expected.fields.len) : (i += 1) {
        const exp_field = expected.fields[i];
        const act_field_ptr = findFieldByName(actual_struct, exp_field.name);
        const lit_field_ptr = findStructValueFieldByName(lit, exp_field.name);

        if (act_field_ptr != null and lit_field_ptr != null) {
            const act_field = act_field_ptr.?;
            const lit_field = lit_field_ptr.?;
            const field_node = @constCast(lit_field.value);
            var field_expr = TypedExpr{
                .node = field_node,
                .ty = act_field.ty,
            };
            field_expr = try coerceExprToType(exp_field.ty, field_expr, expr_node, s, allocator, diags);
            if (!typesExactlyEqual(exp_field.ty, field_expr.ty)) {
                const pair = try formatTypePairText(exp_field.ty, field_expr.ty, s, allocator);
                defer pair.deinit();
                try diags.add(
                    expr_node.location,
                    .semantic,
                    "cannot initialize field '.{s}' with '{s}' (expected '{s}')",
                    .{ exp_field.name, pair.actual.bytes, pair.expected.bytes },
                );
                allocator.free(coerced_fields);
                return error.Reported;
            }

            coerced_fields[i] = .{ .name = exp_field.name, .value = field_expr.node };
            continue;
        }

        if (exp_field.default_value) |default_node| {
            coerced_fields[i] = .{ .name = exp_field.name, .value = default_node };
            continue;
        }

        allocator.free(coerced_fields);
        return expr;
    }

    const lit_ptr = try allocator.create(sg.StructValueLiteral);
    lit_ptr.* = .{ .fields = coerced_fields, .ty = .{ .struct_type = expected } };

    const node = try allocator.create(sg.SGNode);
    node.* = .{
        .location = expr_node.location,
        .content = .{ .struct_value_literal = lit_ptr },
    };
    return .{ .node = node, .ty = .{ .struct_type = expected } };
}

fn findStructValueFieldByName(lit: *const sg.StructValueLiteral, name: []const u8) ?*const sg.StructValueLiteralField {
    for (lit.fields) |*field| {
        if (std.mem.eql(u8, field.name, name)) return field;
    }
    return null;
}

pub fn ensureReadOnlyPointer(expr_node: *const syn.STNode, te: TypedExpr, allocator: *const std.mem.Allocator, diags: *diagnostics.Diagnostics) err.SemErr!TypedExpr {
    if (te.ty == .pointer_type) return te;

    if (te.node.content != .binding_use) {
        try diags.add(
            expr_node.location,
            .semantic,
            "cannot take the address of this expression; only named variables are addressable",
            .{},
        );
        return error.Reported;
    }

    const child_ty = try allocator.create(sg.Type);
    child_ty.* = te.ty;

    const ptr_info = try allocator.create(sg.PointerType);
    ptr_info.* = .{ .mutability = .read_only, .child = child_ty };

    const addr_node = try allocator.create(sg.SGNode);
    addr_node.* = .{
        .location = expr_node.location,
        .content = .{ .address_of = te.node },
    };
    return .{ .node = addr_node, .ty = .{ .pointer_type = ptr_info } };
}

pub fn ensureMutablePointer(
    expr_node: *const syn.STNode,
    te: TypedExpr,
    s: *Scope,
    allocator: *const std.mem.Allocator,
    diags: *diagnostics.Diagnostics,
) err.SemErr!TypedExpr {
    if (te.ty == .pointer_type) {
        const info = te.ty.pointer_type.*;
        if (info.mutability != .read_write) {
            const ptr_str = try formatTypeText(.{ .pointer_type = te.ty.pointer_type }, s, allocator);
            defer ptr_str.deinit();
            try diags.add(
                expr_node.location,
                .semantic,
                "cannot assign through pointer '{s}' because it is read-only; use '$&' when acquiring it",
                .{ptr_str.bytes},
            );
            return error.Reported;
        }
        return te;
    }

    if (te.node.content != .binding_use) {
        try diags.add(
            expr_node.location,
            .semantic,
            "cannot assign through indexed expression; take '$&' explicitly",
            .{},
        );
        return error.Reported;
    }

    const binding = te.node.content.binding_use;
    if (binding.mutability != .variable) {
        try diags.add(
            expr_node.location,
            .semantic,
            "binding '{s}' is immutable; declare it with '::' or use '&{s}'",
            .{ binding.name, binding.name },
        );
        return error.Reported;
    }

    const child_ty = try allocator.create(sg.Type);
    child_ty.* = te.ty;

    const ptr_info = try allocator.create(sg.PointerType);
    ptr_info.* = .{ .mutability = .read_write, .child = child_ty };

    const addr_node = try allocator.create(sg.SGNode);
    addr_node.* = .{
        .location = expr_node.location,
        .content = .{ .address_of = te.node },
    };
    return .{ .node = addr_node, .ty = .{ .pointer_type = ptr_info } };
}
