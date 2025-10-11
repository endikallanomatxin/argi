const std = @import("std");
const tok = @import("../2_tokens/token.zig");
const syn = @import("../3_syntax/syntax_tree.zig");
const sem = @import("semantic_graph.zig");
const sgp = @import("semantic_graph_print.zig");
const diagnostic = @import("../1_base/diagnostic.zig");

pub const TypedExpr = struct {
    node: *sem.SGNode,
    ty: sem.Type,
};

pub const BuiltinTypeInfoKind = enum {
    size,
    alignment,
};

pub const pointer_size_bytes: u64 = @sizeOf(*usize);
pub const pointer_alignment_bytes: u64 = pointer_size_bytes;

pub fn typesStructurallyEqual(a: sem.Type, b: sem.Type) bool {
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
pub fn typesExactlyEqual(a: sem.Type, b: sem.Type) bool {
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

pub fn isAny(t: sem.Type) bool {
    return switch (t) {
        .builtin => |bt| bt == .Any,
        else => false,
    };
}

pub fn isIntegerType(t: sem.Type) bool {
    return switch (t) {
        .builtin => |bt| switch (bt) {
            .Int8, .Int16, .Int32, .Int64, .UInt8, .UInt16, .UInt32, .UInt64 => true,
            else => false,
        },
        else => false,
    };
}

pub fn pointerMutabilityCompatible(expected: syn.PointerMutability, actual: syn.PointerMutability) bool {
    return switch (expected) {
        .read_only => true,
        .read_write => actual == .read_write,
    };
}

pub fn typesCompatible(expected: sem.Type, actual: sem.Type) bool {
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

const Scope = @import("scope.zig").Scope;

pub fn typeNameFor(s: *Scope, t: sem.Type) ?[]const u8 {
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
