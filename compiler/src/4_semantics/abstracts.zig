const std = @import("std");
const tok = @import("../2_tokens/token.zig");
const syn = @import("../3_syntax/syntax_tree.zig");
const sg = @import("semantic_graph.zig");
const sem = @import("semantizer.zig");
const sgp = @import("semantic_graph_print.zig");
const diagnostic = @import("../1_base/diagnostic.zig");

const typ = @import("types.zig");
const helpers = @import("helpers.zig");

const Scope = @import("scope.zig").Scope;

// Abstract typing support
pub const AbstractFunctionReqSem = struct {
    name: []const u8,
    input: sg.StructType,
    output: sg.StructType,
    // indices of input fields whose type was 'Self'
    input_self_indices: []const u32,
    // parallel slices to track generic parameter usage per field
    input_generic_param_indices: []const ?u32,
    output_generic_param_indices: []const ?u32,
    // optional abstract requirements per field (null if none)
    input_abstract_requirements: []const ?[]const u8,
    output_abstract_requirements: []const ?[]const u8,
};

pub const AbstractInfo = struct {
    name: []const u8,
    requirements: []const AbstractFunctionReqSem,
    param_names: []const []const u8,
};
pub const AbstractImplEntry = struct {
    ty: sg.Type,
    location: tok.Location,
};
pub const AbstractDefaultEntry = struct {
    ty: sg.Type,
    location: tok.Location,
};

pub fn typeImplementsAbstract(
    abs_name: []const u8,
    candidate: sg.Type,
    s: *Scope,
) bool {
    var cur: ?*Scope = s;
    while (cur) |sc| : (cur = sc.parent) {
        if (sc.abstract_impls.getPtr(abs_name)) |list_ptr| {
            const impls = list_ptr.*;
            for (impls.items) |impl| {
                if (typ.typesExactlyEqual(impl.ty, candidate)) return true;
            }
        }
    }

    var cur_def: ?*Scope = s;
    while (cur_def) |sc| : (cur_def = sc.parent) {
        if (sc.abstract_defaults.getPtr(abs_name)) |def_entry| {
            if (typ.typesExactlyEqual(def_entry.*.ty, candidate)) return true;
        }
    }

    return false;
}

// Lower score = more specific. Assumes typesStructurallyEqual(expected, actual) already true.
pub fn specificityScore(expected: sg.Type, actual: sg.Type) u32 {
    return switch (expected) {
        .builtin => 0,
        .struct_type => |est| blk: {
            var sum: u32 = 0;
            const ast = actual.struct_type;
            var i: usize = 0;
            while (i < est.fields.len) : (i += 1) {
                const fe = est.fields[i];
                const fa = ast.fields[i];
                sum += specificityScore(fe.ty, fa.ty);
            }
            break :blk sum;
        },
        .pointer_type => |ept_ptr| blk2: {
            const apt_ptr = actual.pointer_type;
            const ept = ept_ptr.*;
            const apt = apt_ptr.*;

            if (ept.mutability != apt.mutability)
                break :blk2 5;

            const expected_child = ept.child.*;
            const actual_child = apt.child.*;

            if (typ.isAny(expected_child) or typ.isAny(actual_child))
                break :blk2 1;

            break :blk2 specificityScore(expected_child, actual_child);
        },
        .array_type => |eat_ptr| blk_arr: {
            const aat_ptr = actual.array_type;
            const eat = eat_ptr.*;
            const aat = aat_ptr.*;
            if (eat.length != aat.length) break :blk_arr 10;
            break :blk_arr specificityScore(eat.element_type.*, aat.element_type.*);
        },
    };
}

pub fn funcInputMatchesRequirement(
    rq: *const AbstractFunctionReqSem,
    cand_in: *const sg.StructType,
    concrete: sg.Type,
    param_bindings: []?sg.Type,
    s: *Scope,
) bool {
    const req_in = &rq.input;
    if (cand_in.fields.len != req_in.fields.len) return false;

    var i: usize = 0;
    while (i < req_in.fields.len) : (i += 1) {
        const rf = req_in.fields[i];
        const cf = cand_in.fields[i];

        if (helpers.containsIndex(rq.input_self_indices, @intCast(i))) {
            if (!typ.typesExactlyEqual(concrete, cf.ty)) return false;
            continue;
        }

        if (rq.input_abstract_requirements.len > i) {
            if (rq.input_abstract_requirements[i]) |abs_name| {
                if (!typeImplementsAbstract(abs_name, cf.ty, s)) return false;
                continue;
            }
        }

        if (rq.input_generic_param_indices.len > i) {
            if (rq.input_generic_param_indices[i]) |gi| {
                if (gi >= param_bindings.len) return false;
                if (param_bindings[gi]) |bound| {
                    if (!typ.typesExactlyEqual(bound, cf.ty)) return false;
                } else {
                    param_bindings[gi] = cf.ty;
                }
                continue;
            }
        }

        if (!typ.typesExactlyEqual(rf.ty, cf.ty)) return false;
    }
    return true;
}

pub fn funcOutputMatchesRequirement(
    rq: *const AbstractFunctionReqSem,
    cand_out: *const sg.StructType,
    param_bindings: []?sg.Type,
    s: *Scope,
) bool {
    if (cand_out.fields.len != rq.output.fields.len) return false;

    var i: usize = 0;
    while (i < rq.output.fields.len) : (i += 1) {
        const ro = rq.output.fields[i];
        const co = cand_out.fields[i];

        if (rq.output_abstract_requirements.len > i) {
            if (rq.output_abstract_requirements[i]) |abs_name| {
                if (!typeImplementsAbstract(abs_name, co.ty, s)) return false;
                continue;
            }
        }

        if (rq.output_generic_param_indices.len > i) {
            if (rq.output_generic_param_indices[i]) |gi| {
                if (gi >= param_bindings.len) return false;
                if (param_bindings[gi]) |bound| {
                    if (!typ.typesExactlyEqual(bound, co.ty)) return false;
                } else {
                    param_bindings[gi] = co.ty;
                }
                continue;
            }
        }

        if (!typ.typesExactlyEqual(ro.ty, co.ty)) return false;
    }
    return true;
}

pub fn resolveOverload(name: []const u8, in_ty: sg.Type, s: *Scope) sem.SemErr!*sg.FunctionDeclaration {
    var best: ?*sg.FunctionDeclaration = null;
    var best_score: u32 = std.math.maxInt(u32);
    var ambiguous = false;

    var cur: ?*Scope = s;
    while (cur) |sc| : (cur = sc.parent) {
        if (sc.functions.getPtr(name)) |list_ptr| {
            for (list_ptr.items) |cand| {
                const expected: sg.Type = .{ .struct_type = &cand.input };
                if (!typ.typesCompatible(expected, in_ty)) continue;

                const score = specificityScore(expected, in_ty);
                if (best == null or score < best_score) {
                    best = cand;
                    best_score = score;
                    ambiguous = false;
                } else if (score == best_score) {
                    // ambiguous with same specificity
                    ambiguous = true;
                }
            }
        }
    }
    if (best == null) return error.SymbolNotFound;
    if (ambiguous) return error.AmbiguousOverload;
    return best.?;
}
