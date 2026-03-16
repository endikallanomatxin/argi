const std = @import("std");
const tok = @import("../2_tokens/token.zig");
const sg = @import("semantic_graph.zig");
const diagnostic = @import("../1_base/diagnostic.zig");

const typ = @import("types.zig");

const Scope = @import("scope.zig").Scope;
const SemErr = @import("errors.zig").SemErr;

// Abstract typing support
pub const AbstractFunctionReqSem = struct {
    name: []const u8,
    input: sg.StructType,
    output: sg.StructType,
    // indices of input fields whose type was 'Self'
    input_self_indices: []const u32,
    output_self_indices: []const u32,
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
        .abstract_type => switch (actual) {
            .abstract_type => 0,
            else => 1,
        },
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

pub fn typesCompatibleForDispatch(expected: sg.Type, actual: sg.Type, s: *Scope) bool {
    return switch (expected) {
        .builtin => |eb| switch (actual) {
            .builtin => |ab| eb == ab,
            else => false,
        },
        .abstract_type => |eat| switch (actual) {
            .abstract_type => |aat| std.mem.eql(u8, eat.name, aat.name),
            else => typeImplementsAbstract(eat.name, actual, s),
        },
        .struct_type => |est| switch (actual) {
            .struct_type => |ast| blk: {
                if (est.fields.len != ast.fields.len) break :blk false;
                var i: usize = 0;
                while (i < est.fields.len) : (i += 1) {
                    if (!typesCompatibleForDispatch(est.fields[i].ty, ast.fields[i].ty, s)) break :blk false;
                }
                break :blk true;
            },
            else => false,
        },
        .pointer_type => |ept_ptr| switch (actual) {
            .pointer_type => |apt_ptr| blk: {
                const ept = ept_ptr.*;
                const apt = apt_ptr.*;

                if (!typ.pointerMutabilityCompatible(ept.mutability, apt.mutability))
                    break :blk false;

                const expected_child = ept.child.*;
                const actual_child = apt.child.*;

                if (typ.isAny(expected_child) or typ.isAny(actual_child))
                    break :blk true;

                break :blk typesCompatibleForDispatch(expected_child, actual_child, s);
            },
            else => false,
        },
        .array_type => |eat_ptr| switch (actual) {
            .array_type => |aat_ptr| blk_arr: {
                const eat = eat_ptr.*;
                const aat = aat_ptr.*;
                if (eat.length != aat.length) break :blk_arr false;
                break :blk_arr typesCompatibleForDispatch(eat.element_type.*, aat.element_type.*, s);
            },
            else => false,
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

        if (containsIndex(rq.input_self_indices, @intCast(i))) {
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
    concrete: sg.Type,
    param_bindings: []?sg.Type,
    s: *Scope,
) bool {
    if (cand_out.fields.len != rq.output.fields.len) return false;

    var i: usize = 0;
    while (i < rq.output.fields.len) : (i += 1) {
        const ro = rq.output.fields[i];
        const co = cand_out.fields[i];

        if (containsIndex(rq.output_self_indices, @intCast(i))) {
            if (!typ.typesExactlyEqual(concrete, co.ty)) return false;
            continue;
        }

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

pub fn resolveOverload(name: []const u8, in_ty: sg.Type, s: *Scope) SemErr!*sg.FunctionDeclaration {
    var best: ?*sg.FunctionDeclaration = null;
    var best_score: u32 = std.math.maxInt(u32);
    var ambiguous = false;

    var cur: ?*Scope = s;
    while (cur) |sc| : (cur = sc.parent) {
        if (sc.functions.getPtr(name)) |list_ptr| {
            for (list_ptr.items) |cand| {
                const expected: sg.Type = .{ .struct_type = &cand.input };
                if (!typesCompatibleForDispatch(expected, in_ty, s)) continue;

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

pub fn ensureConformance(info: *AbstractInfo, concrete: sg.Type, s: *Scope, allocator: *const std.mem.Allocator) SemErr!void {
    for (info.requirements) |rq| {
        if (!(try existsFunctionForRequirement(info, rq, concrete, s, allocator)))
            return error.SymbolNotFound;
    }
}

fn buildExpectedInputWithConcrete(rq: *const AbstractFunctionReqSem, concrete: sg.Type, allocator: *const std.mem.Allocator) !*sg.StructType {
    var fields = try allocator.alloc(sg.StructTypeField, rq.input.fields.len);
    for (rq.input.fields, 0..) |f, i| {
        const is_self = containsIndex(rq.input_self_indices, @intCast(i));
        fields[i] = .{ .name = f.name, .ty = if (is_self) concrete else f.ty, .default_value = null };
    }
    const st_ptr = try allocator.create(sg.StructType);
    st_ptr.* = .{ .fields = fields };
    return st_ptr;
}

fn existsFunctionForRequirement(
    info: *const AbstractInfo,
    rq: AbstractFunctionReqSem,
    concrete: sg.Type,
    s: *Scope,
    allocator: *const std.mem.Allocator,
) SemErr!bool {
    var cur: ?*Scope = s;
    while (cur) |sc| : (cur = sc.parent) {
        if (sc.functions.getPtr(rq.name)) |lst| {
            for (lst.items) |cand| {
                if (info.param_names.len == 0) {
                    const empty: []?sg.Type = &[_]?sg.Type{};
                    if (!funcInputMatchesRequirement(&rq, &cand.input, concrete, empty, s))
                        continue;
                    if (!funcOutputMatchesRequirement(&rq, &cand.output, concrete, empty, s))
                        continue;
                    return true;
                } else {
                    var bindings = try allocator.alloc(?sg.Type, info.param_names.len);
                    defer allocator.free(bindings);
                    for (bindings, 0..) |_, idx| bindings[idx] = null;

                    if (!funcInputMatchesRequirement(&rq, &cand.input, concrete, bindings, s))
                        continue;
                    if (!funcOutputMatchesRequirement(&rq, &cand.output, concrete, bindings, s))
                        continue;
                    return true;
                }
            }
        }
    }
    return false;
}

pub fn verifyAbstracts(s: *Scope, allocator: *const std.mem.Allocator, diags: *diagnostic.Diagnostics) !void {
    var any_error = false;
    var it = s.abstract_impls.iterator();
    while (it.next()) |entry| {
        const abs_name = entry.key_ptr.*;
        const impls = entry.value_ptr.*;
        const info = s.lookupAbstractInfo(abs_name) orelse continue;

        for (impls.items) |impl| {
            const conc = impl.ty;
            for (info.requirements) |rq| {
                if (try existsFunctionForRequirement(info, rq, conc, s, allocator)) continue;

                // Build expected input with concrete substituted for Self
                const exp_in = try buildExpectedInputWithConcrete(&rq, conc, allocator);
                const in_ty: sg.Type = .{ .struct_type = exp_in };

                // Produce candidates string
                const candidates = buildOverloadCandidatesString(rq.name, in_ty, s, allocator) catch "";

                // Build signature string
                var buf = std.array_list.Managed(u8).init(allocator.*);
                defer buf.deinit();
                try buf.appendSlice(rq.name);
                try buf.appendSlice(" (");
                var i: usize = 0;
                while (i < exp_in.fields.len) : (i += 1) {
                    const fld = exp_in.fields[i];
                    if (i != 0) try buf.appendSlice(", ");
                    try buf.appendSlice(".");
                    try buf.appendSlice(fld.name);
                    try buf.appendSlice(": ");
                    try typ.appendTypePretty(&buf, fld.ty, s);
                }
                try buf.appendSlice(")");

                // Report diagnostic at the 'canbe' site
                if (candidates.len > 0) {
                    try diags.add(
                        impl.location,
                        .semantic,
                        "type does not implement abstract '{s}':\n  missing function: {s}\n  possible overloads:\n{s}",
                        .{ abs_name, buf.items, candidates },
                    );
                } else {
                    try diags.add(
                        impl.location,
                        .semantic,
                        "type does not implement abstract '{s}':\n  missing function: {s}",
                        .{ abs_name, buf.items },
                    );
                }
                any_error = true;
            }
        }
    }

    // Also verify defaults conform to their abstracts
    var it_def = s.abstract_defaults.iterator();
    while (it_def.next()) |entry2| {
        const abs_name2 = entry2.key_ptr.*;
        const def_entry = entry2.value_ptr.*;
        const info2 = s.lookupAbstractInfo(abs_name2) orelse continue;
        const conc2 = def_entry.ty;
        for (info2.requirements) |rq2| {
            if (try existsFunctionForRequirement(info2, rq2, conc2, s, allocator)) continue;

            const exp_in2 = try buildExpectedInputWithConcrete(&rq2, conc2, allocator);
            const in_ty2: sg.Type = .{ .struct_type = exp_in2 };
            const candidates2 = buildOverloadCandidatesString(rq2.name, in_ty2, s, allocator) catch "";

            var buf2 = std.array_list.Managed(u8).init(allocator.*);
            defer buf2.deinit();
            try buf2.appendSlice(rq2.name);
            try buf2.appendSlice(" (");
            var j: usize = 0;
            while (j < exp_in2.fields.len) : (j += 1) {
                const fld2 = exp_in2.fields[j];
                if (j != 0) try buf2.appendSlice(", ");
                try buf2.appendSlice(".");
                try buf2.appendSlice(fld2.name);
                try buf2.appendSlice(": ");
                try typ.appendTypePretty(&buf2, fld2.ty, s);
            }
            try buf2.appendSlice(")");

            if (candidates2.len > 0) {
                try diags.add(
                    def_entry.location,
                    .semantic,
                    "default type does not implement abstract '{s}':\n  missing function: {s}\n  possible overloads:\n{s}",
                    .{ abs_name2, buf2.items, candidates2 },
                );
            } else {
                try diags.add(
                    def_entry.location,
                    .semantic,
                    "default type does not implement abstract '{s}':\n  missing function: {s}",
                    .{ abs_name2, buf2.items },
                );
            }
            any_error = true;
        }
    }
    if (any_error) return error.SymbolNotFound;
}

pub fn buildOverloadCandidatesString(name: []const u8, in_ty: sg.Type, s: *Scope, allocator: *const std.mem.Allocator) ![]u8 {
    var buf = std.array_list.Managed(u8).init(allocator.*);
    var cur: ?*Scope = s;
    var first: bool = true;
    while (cur) |sc| : (cur = sc.parent) {
        if (sc.functions.getPtr(name)) |list_ptr| {
            for (list_ptr.items) |cand| {
                const expected: sg.Type = .{ .struct_type = &cand.input };
                if (!typesCompatibleForDispatch(expected, in_ty, s)) continue;
                if (!first) try buf.appendSlice("\n");
                first = false;
                try buf.appendSlice("  - ");
                try appendFunctionSignature(&buf, cand, s);
                try buf.appendSlice("\n      file: ");
                try buf.appendSlice(cand.location.file);
                try buf.appendSlice(":");
                try buf.appendSlice(std.fmt.allocPrint(allocator.*, "{d}:{d}", .{ cand.location.line, cand.location.column }) catch "");
            }
        }
    }
    return try buf.toOwnedSlice();
}

pub fn collectFunctionSignatures(name: []const u8, s: *Scope, allocator: *const std.mem.Allocator) ![]u8 {
    var buf = std.array_list.Managed(u8).init(allocator.*);
    errdefer buf.deinit();

    var cur: ?*Scope = s;
    var first = true;
    while (cur) |sc| : (cur = sc.parent) {
        if (sc.functions.getPtr(name)) |list_ptr| {
            for (list_ptr.items) |cand| {
                if (!first) try buf.appendSlice("\n");
                first = false;
                try buf.appendSlice("  - ");
                try appendFunctionSignature(&buf, cand, s);
            }
        }
    }

    if (first) {
        try buf.appendSlice("  (none)");
    }

    return try buf.toOwnedSlice();
}

pub fn appendFunctionSignature(buf: *std.array_list.Managed(u8), f: *const sg.FunctionDeclaration, s: *Scope) !void {
    try buf.appendSlice(f.name);
    try buf.appendSlice(" (");
    var i: usize = 0;
    while (i < f.input.fields.len) : (i += 1) {
        const fld = f.input.fields[i];
        if (i != 0) try buf.appendSlice(", ");
        try buf.appendSlice(".");
        try buf.appendSlice(fld.name);
        try buf.appendSlice(": ");
        try typ.appendTypePretty(buf, fld.ty, s);
    }
    try buf.appendSlice(") -> (");
    i = 0;
    while (i < f.output.fields.len) : (i += 1) {
        const ofld = f.output.fields[i];
        if (i != 0) try buf.appendSlice(", ");
        try buf.appendSlice(".");
        try buf.appendSlice(ofld.name);
        try buf.appendSlice(": ");
        try typ.appendTypePretty(buf, ofld.ty, s);
    }
    try buf.appendSlice(")");
}

pub fn containsIndex(list: []const u32, idx: u32) bool {
    for (list) |v| if (v == idx) return true;
    return false;
}
