const std = @import("std");
const tok = @import("../2_tokens/token.zig");
const syn = @import("../3_syntax/syntax_tree.zig");
const sg = @import("semantic_graph.zig");
const sgp = @import("semantic_graph_print.zig");
const diagnostic = @import("../1_base/diagnostic.zig");

pub const TypedExpr = struct {
    node: *sg.SGNode,
    ty: sg.Type,
};

pub const BuiltinTypeInfoKind = enum {
    size,
    alignment,
};

pub const pointer_size_bytes: u64 = @sizeOf(*usize);
pub const pointer_alignment_bytes: u64 = pointer_size_bytes;

pub fn typesStructurallyEqual(a: sg.Type, b: sg.Type) bool {
    return switch (a) {
        .builtin => |ab| switch (b) {
            .builtin => |bb| ab == bb,
            else => false,
        },

        .struct_type => |ast| switch (b) {
            .builtin => false,

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
            .Int8, .Int16, .Int32, .Int64, .UInt8, .UInt16, .UInt32, .UInt64 => true,
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

const Scope = @import("scope.zig").Scope;

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

fn appendType(buf: *std.ArrayList(u8), t: sg.Type) !void {
    switch (t) {
        .builtin => |bt| {
            const s = @tagName(bt);
            try buf.appendSlice(s);
        },
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
    var buf = std.ArrayList(u8).init(allocator.*);
    errdefer buf.deinit();
    try appendTypePretty(&buf, t, s);
    return try buf.toOwnedSlice();
}

pub fn appendTypePretty(buf: *std.ArrayList(u8), t: sg.Type, s: *Scope) !void {
    if (typeNameFor(s, t)) |nm| {
        try buf.appendSlice(nm);
        return;
    }
    switch (t) {
        .builtin => |bt| {
            const sname = @tagName(bt);
            try buf.appendSlice(sname);
        },
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
    var buf = std.ArrayList(u8).init(allocator.*);
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
