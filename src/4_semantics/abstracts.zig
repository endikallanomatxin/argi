const std = @import("std");
const tok = @import("../2_tokens/token.zig");
const syn = @import("../3_syntax/syntax_tree.zig");
const sg = @import("semantic_graph.zig");
const diagnostic = @import("../1_base/diagnostic.zig");

const gen = @import("generics.zig");
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
    input_pointer_self_indices: []const u32,
    output_pointer_self_indices: []const u32,
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
pub const AbstractImplTemplate = struct {
    params: []const gen.GenericParam,
    ty: syn.Type,
    location: tok.Location,
};
pub const AbstractDefaultEntry = struct {
    ty: sg.Type,
    location: tok.Location,
};

const OwnedText = struct {
    allocator: *const std.mem.Allocator,
    bytes: []u8,

    pub fn deinit(self: OwnedText) void {
        self.allocator.free(self.bytes);
    }
};

const MissingRequirementContext = struct {
    label: []const u8,
    abstract_name: []const u8,
    concrete: sg.Type,
    location: tok.Location,
};

const TemplateBindings = struct {
    allocator: *const std.mem.Allocator,
    types: std.StringHashMap(sg.Type),
    ints: std.StringHashMap(i64),

    fn init(allocator: *const std.mem.Allocator) TemplateBindings {
        return .{
            .allocator = allocator,
            .types = std.StringHashMap(sg.Type).init(allocator.*),
            .ints = std.StringHashMap(i64).init(allocator.*),
        };
    }

    fn deinit(self: *TemplateBindings) void {
        self.types.deinit();
        self.ints.deinit();
    }
};

fn findGenericParam(params: []const gen.GenericParam, name: []const u8) ?gen.GenericParam {
    for (params) |param| {
        if (std.mem.eql(u8, param.name, name)) return param;
    }
    return null;
}

fn parseIntLiteral(lit: tok.Literal) ?i64 {
    return switch (lit) {
        .decimal_int_literal, .hexadecimal_int_literal, .octal_int_literal, .binary_int_literal => |txt|
            std.fmt.parseInt(i64, txt, 0) catch null,
        else => null,
    };
}

fn evalComptimeIntPattern(node: *const syn.STNode, params: []const gen.GenericParam, bindings: *TemplateBindings) ?i64 {
    return switch (node.content) {
        .literal => |lit| parseIntLiteral(lit),
        .identifier => |name| blk: {
            if (findGenericParam(params, name)) |param| {
                if (param.kind == .comptime_int) {
                    break :blk bindings.ints.get(name);
                }
            }
            break :blk null;
        },
        .binary_operation => |bo| blk: {
            const left = evalComptimeIntPattern(bo.left, params, bindings) orelse break :blk null;
            const right = evalComptimeIntPattern(bo.right, params, bindings) orelse break :blk null;
            break :blk switch (bo.operator) {
                .addition => left + right,
                .subtraction => left - right,
                .multiplication => left * right,
                .division => if (right == 0) null else @divTrunc(left, right),
                .modulo => if (right == 0) null else @mod(left, right),
            };
        },
        else => null,
    };
}

fn matchComptimeIntPattern(node: *const syn.STNode, actual: i64, params: []const gen.GenericParam, bindings: *TemplateBindings) bool {
    if (node.content == .identifier) {
        const name = node.content.identifier;
        if (findGenericParam(params, name)) |param| {
            if (param.kind == .comptime_int) {
                if (bindings.ints.get(name)) |bound| return bound == actual;
                bindings.ints.put(name, actual) catch return false;
                return true;
            }
        }
    }

    const expected = evalComptimeIntPattern(node, params, bindings) orelse return false;
    return expected == actual;
}

fn matchTemplateType(pattern: syn.Type, actual: sg.Type, params: []const gen.GenericParam, bindings: *TemplateBindings) bool {
    return switch (pattern) {
        .type_name => |tn| blk: {
            if (findGenericParam(params, tn.string)) |param| {
                if (param.kind == .type) {
                    if (bindings.types.get(tn.string)) |bound| break :blk typ.typesExactlyEqual(bound, actual);
                    bindings.types.put(tn.string, actual) catch return false;
                    break :blk true;
                }
            }
            if (typ.builtinFromName(tn.string)) |builtin_ty| {
                break :blk actual == .builtin and actual.builtin == builtin_ty;
            }
            if (typ.genericIdentityOf(actual)) |identity| {
                break :blk std.mem.eql(u8, identity.base_name, tn.string) and identity.arg_names.len == 0;
            }
            if (actual == .abstract_type) {
                break :blk std.mem.eql(u8, actual.abstract_type.name, tn.string);
            }
            break :blk false;
        },
        .pointer_type => |ptr_info| blk: {
            if (actual != .pointer_type) break :blk false;
            if (ptr_info.mutability != actual.pointer_type.mutability) break :blk false;
            break :blk matchTemplateType(ptr_info.child.*, actual.pointer_type.child.*, params, bindings);
        },
        .array_type => |arr_info| blk: {
            if (actual != .array_type) break :blk false;
            if (arr_info.length != actual.array_type.length) break :blk false;
            break :blk matchTemplateType(arr_info.element.*, actual.array_type.element_type.*, params, bindings);
        },
        .struct_type_literal => false,
        .generic_type_instantiation => |g| matchGenericInstantiationType(g, actual, params, bindings),
    };
}

fn matchCanonicalGenericInstantiation(
    g: @FieldType(syn.Type, "generic_type_instantiation"),
    actual: sg.Type,
    params: []const gen.GenericParam,
    bindings: *TemplateBindings,
) bool {
    const identity = typ.genericIdentityOf(actual) orelse return false;
    if (!std.mem.eql(u8, identity.base_name, g.base_name.string)) return false;

    for (g.args.fields) |field| {
        const arg_value = typ.genericIdentityArgByName(identity, field.name.string) orelse return false;
        switch (arg_value) {
            .type => |arg_ty| {
                const field_ty = field.type orelse return false;
                if (!matchTemplateType(field_ty, arg_ty, params, bindings)) return false;
            },
            .comptime_int => |arg_int| {
                const value_node = field.default_value orelse return false;
                if (!matchComptimeIntPattern(value_node, arg_int, params, bindings)) return false;
            },
        }
    }

    return true;
}

fn matchGenericInstantiationType(
    g: @FieldType(syn.Type, "generic_type_instantiation"),
    actual: sg.Type,
    params: []const gen.GenericParam,
    bindings: *TemplateBindings,
) bool {
    return matchCanonicalGenericInstantiation(g, actual, params, bindings);
}

fn templateImplementsCandidate(tmpl: AbstractImplTemplate, candidate: sg.Type, allocator: *const std.mem.Allocator) bool {
    var bindings = TemplateBindings.init(allocator);
    defer bindings.deinit();
    return matchTemplateType(tmpl.ty, candidate, tmpl.params, &bindings);
}

pub fn typeImplementsAbstract(
    abs_name: []const u8,
    candidate: sg.Type,
    s: *Scope,
) bool {
    if (candidate == .abstract_type and std.mem.eql(u8, candidate.abstract_type.name, abs_name)) {
        return true;
    }

    var cur: ?*Scope = s;
    while (cur) |sc| : (cur = sc.parent) {
        if (sc.abstract_impls.getPtr(abs_name)) |list_ptr| {
            const impls = list_ptr.*;
            for (impls.items) |impl| {
                if (typ.typesExactlyEqual(impl.ty, candidate)) return true;
            }
        }
        if (sc.abstract_impl_templates.getPtr(abs_name)) |list_ptr| {
            const templates = list_ptr.*;
            for (templates.items) |tmpl| {
                if (templateImplementsCandidate(tmpl, candidate, s.allocator)) return true;
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
    if (typ.typesExactlyEqual(expected, actual)) return 0;

    return switch (expected) {
        .builtin => 1,
        .abstract_type => switch (actual) {
            .abstract_type => 0,
            else => 1,
        },
        .choice_type => switch (actual) {
            .choice_type => 0,
            else => 10,
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
            break :blk sum + 1;
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
            break :blk_arr specificityScore(eat.element_type.*, aat.element_type.*) + 1;
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
        .choice_type => |ect| switch (actual) {
            .choice_type => |act| ect == act,
            else => false,
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

                if (expected_child == .struct_type and actual_child == .struct_type) {
                    break :blk typ.typesExactlyEqual(expected_child, actual_child);
                }

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

        if (containsIndex(rq.input_pointer_self_indices, @intCast(i))) {
            if (cf.ty != .pointer_type) return false;
            if (rq.input.fields[i].ty != .pointer_type) return false;
            if (cf.ty.pointer_type.mutability != rq.input.fields[i].ty.pointer_type.mutability) return false;
            if (!typ.typesExactlyEqual(concrete, cf.ty.pointer_type.child.*)) return false;
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

        if (containsIndex(rq.output_pointer_self_indices, @intCast(i))) {
            if (co.ty != .pointer_type) return false;
            if (rq.output.fields[i].ty != .pointer_type) return false;
            if (co.ty.pointer_type.mutability != rq.output.fields[i].ty.pointer_type.mutability) return false;
            if (!typ.typesExactlyEqual(concrete, co.ty.pointer_type.child.*)) return false;
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
        const is_pointer_self = containsIndex(rq.input_pointer_self_indices, @intCast(i));
        const field_ty = if (is_self) blk: {
            break :blk concrete;
        } else if (is_pointer_self and f.ty == .pointer_type) blk: {
            const child = try allocator.create(sg.Type);
            child.* = concrete;
            const sem_ptr = try allocator.create(sg.PointerType);
            sem_ptr.* = .{
                .mutability = f.ty.pointer_type.mutability,
                .child = child,
            };
            break :blk sg.Type{ .pointer_type = sem_ptr };
        } else if (rq.input_abstract_requirements.len > i and rq.input_abstract_requirements[i] != null) blk: {
            const abs_name = rq.input_abstract_requirements[i].?;
            const abs_ptr = try allocator.create(sg.AbstractType);
            abs_ptr.* = .{ .name = abs_name };
            const abs_ty: sg.Type = .{ .abstract_type = abs_ptr };

            if (f.ty == .pointer_type) {
                const child = try allocator.create(sg.Type);
                child.* = abs_ty;
                const sem_ptr = try allocator.create(sg.PointerType);
                sem_ptr.* = .{
                    .mutability = f.ty.pointer_type.mutability,
                    .child = child,
                };
                break :blk sg.Type{ .pointer_type = sem_ptr };
            }

            break :blk abs_ty;
        } else blk: {
            break :blk f.ty;
        };
        fields[i] = .{ .name = f.name, .ty = field_ty, .default_value = null };
    }
    const st_ptr = try allocator.create(sg.StructType);
    st_ptr.* = .{ .fields = fields };
    return st_ptr;
}

fn buildExpectedOutputWithConcrete(rq: *const AbstractFunctionReqSem, concrete: sg.Type, allocator: *const std.mem.Allocator) !*sg.StructType {
    var fields = try allocator.alloc(sg.StructTypeField, rq.output.fields.len);
    for (rq.output.fields, 0..) |f, i| {
        const is_self = containsIndex(rq.output_self_indices, @intCast(i));
        const is_pointer_self = containsIndex(rq.output_pointer_self_indices, @intCast(i));
        const field_ty = if (is_self) blk: {
            break :blk concrete;
        } else if (is_pointer_self and f.ty == .pointer_type) blk: {
            const child = try allocator.create(sg.Type);
            child.* = concrete;
            const sem_ptr = try allocator.create(sg.PointerType);
            sem_ptr.* = .{
                .mutability = f.ty.pointer_type.mutability,
                .child = child,
            };
            break :blk sg.Type{ .pointer_type = sem_ptr };
        } else if (rq.output_abstract_requirements.len > i and rq.output_abstract_requirements[i] != null) blk: {
            const abs_name = rq.output_abstract_requirements[i].?;
            const abs_ptr = try allocator.create(sg.AbstractType);
            abs_ptr.* = .{ .name = abs_name };
            const abs_ty: sg.Type = .{ .abstract_type = abs_ptr };

            if (f.ty == .pointer_type) {
                const child = try allocator.create(sg.Type);
                child.* = abs_ty;
                const sem_ptr = try allocator.create(sg.PointerType);
                sem_ptr.* = .{
                    .mutability = f.ty.pointer_type.mutability,
                    .child = child,
                };
                break :blk sg.Type{ .pointer_type = sem_ptr };
            }

            break :blk abs_ty;
        } else blk: {
            break :blk f.ty;
        };
        fields[i] = .{ .name = f.name, .ty = field_ty, .default_value = null };
    }
    const st_ptr = try allocator.create(sg.StructType);
    st_ptr.* = .{ .fields = fields };
    return st_ptr;
}

fn genericTemplateFieldsMatchExpected(
    expected: *const sg.StructType,
    template_fields: []const syn.StructTypeLiteralField,
    params: []const gen.GenericParam,
    bindings: *TemplateBindings,
) bool {
    if (expected.fields.len != template_fields.len) return false;

    var i: usize = 0;
    while (i < expected.fields.len) : (i += 1) {
        const template_field = template_fields[i];
        const template_ty = template_field.type orelse return false;
        if (!matchTemplateType(template_ty, expected.fields[i].ty, params, bindings)) return false;
    }

    return true;
}

fn templateBindingsSatisfyConstraints(
    tmpl: gen.GenericTemplate,
    bindings: *TemplateBindings,
    s: *Scope,
) bool {
    var i: usize = 0;
    while (i < tmpl.params.len) : (i += 1) {
        const constraint = tmpl.param_abstract_constraints[i] orelse continue;
        const param = tmpl.params[i];
        if (param.kind != .type) continue;
        const actual = bindings.types.get(param.name) orelse return false;
        if (!typeImplementsAbstract(constraint, actual, s)) return false;
    }
    return true;
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

        if (sc.generic_functions.getPtr(rq.name)) |lst| {
            const expected_in = try buildExpectedInputWithConcrete(&rq, concrete, allocator);
            const expected_out = try buildExpectedOutputWithConcrete(&rq, concrete, allocator);

            for (lst.items) |tmpl| {
                if (tmpl.dispatch_kind != .regular and tmpl.dispatch_kind != .abstract_contract) continue;

                var bindings = TemplateBindings.init(allocator);
                defer bindings.deinit();

                if (!genericTemplateFieldsMatchExpected(expected_in, tmpl.input.fields, tmpl.params, &bindings))
                    continue;
                if (!genericTemplateFieldsMatchExpected(expected_out, tmpl.output.fields, tmpl.params, &bindings))
                    continue;
                if (!templateBindingsSatisfyConstraints(tmpl, &bindings, s))
                    continue;

                return true;
            }
        }
    }
    return false;
}

fn appendRequirementSignature(
    buf: *std.array_list.Managed(u8),
    rq_name: []const u8,
    exp_in: *const sg.StructType,
    s: *Scope,
) !void {
    try buf.appendSlice(rq_name);
    try buf.appendSlice(" (");
    for (exp_in.fields, 0..) |fld, i| {
        if (i != 0) try buf.appendSlice(", ");
        try buf.appendSlice(".");
        try buf.appendSlice(fld.name);
        try buf.appendSlice(": ");
        try typ.appendTypePretty(buf, fld.ty, s);
    }
    try buf.appendSlice(")");
}

fn buildOverloadCandidatesText(name: []const u8, in_ty: sg.Type, s: *Scope, allocator: *const std.mem.Allocator) !OwnedText {
    return .{
        .allocator = allocator,
        .bytes = try buildOverloadCandidatesString(name, in_ty, s, allocator),
    };
}

fn reportMissingRequirement(
    ctx: MissingRequirementContext,
    rq: *const AbstractFunctionReqSem,
    s: *Scope,
    allocator: *const std.mem.Allocator,
    diags: *diagnostic.Diagnostics,
) !void {
    const exp_in = try buildExpectedInputWithConcrete(rq, ctx.concrete, allocator);
    const in_ty: sg.Type = .{ .struct_type = exp_in };
    const candidates_result = buildOverloadCandidatesText(rq.name, in_ty, s, allocator) catch null;
    const candidates = if (candidates_result) |owned| owned.bytes else "";
    defer if (candidates_result) |owned| owned.deinit();

    var signature = std.array_list.Managed(u8).init(allocator.*);
    defer signature.deinit();
    try appendRequirementSignature(&signature, rq.name, exp_in, s);

    if (candidates.len > 0) {
        try diags.add(
            ctx.location,
            .semantic,
            "{s} does not implement abstract '{s}':\n  missing function: {s}\n  possible overloads:\n{s}",
            .{ ctx.label, ctx.abstract_name, signature.items, candidates },
        );
        return;
    }

    try diags.add(
        ctx.location,
        .semantic,
        "{s} does not implement abstract '{s}':\n  missing function: {s}",
        .{ ctx.label, ctx.abstract_name, signature.items },
    );
}

fn formatMissingRequirementText(
    rq: *const AbstractFunctionReqSem,
    concrete: sg.Type,
    s: *Scope,
    allocator: *const std.mem.Allocator,
) !OwnedText {
    const exp_in = try buildExpectedInputWithConcrete(rq, concrete, allocator);
    const in_ty: sg.Type = .{ .struct_type = exp_in };
    const candidates_result = buildOverloadCandidatesText(rq.name, in_ty, s, allocator) catch null;
    const candidates = if (candidates_result) |owned| owned.bytes else "";
    defer if (candidates_result) |owned| owned.deinit();

    var signature = std.array_list.Managed(u8).init(allocator.*);
    defer signature.deinit();
    try appendRequirementSignature(&signature, rq.name, exp_in, s);

    var buf = std.array_list.Managed(u8).init(allocator.*);
    errdefer buf.deinit();

    try buf.appendSlice("missing function: ");
    try buf.appendSlice(signature.items);

    if (candidates.len > 0) {
        try buf.appendSlice("\npossible overloads:\n");
        try buf.appendSlice(candidates);
    }

    return .{
        .allocator = allocator,
        .bytes = try buf.toOwnedSlice(),
    };
}

pub fn buildConformanceDetails(
    abs_name: []const u8,
    concrete: sg.Type,
    s: *Scope,
    allocator: *const std.mem.Allocator,
) !?OwnedText {
    const info = s.lookupAbstractInfo(abs_name) orelse return null;

    for (info.requirements) |rq| {
        if (try existsFunctionForRequirement(info, rq, concrete, s, allocator)) continue;
        return try formatMissingRequirementText(&rq, concrete, s, allocator);
    }

    return null;
}

pub fn verifyAbstracts(s: *Scope, allocator: *const std.mem.Allocator, diags: *diagnostic.Diagnostics) !void {
    var any_error = false;

    var it = s.abstract_impls.iterator();
    while (it.next()) |entry| {
        const abs_name = entry.key_ptr.*;
        const impls = entry.value_ptr.*;
        const info = s.lookupAbstractInfo(abs_name) orelse continue;

        for (impls.items) |impl| {
            for (info.requirements) |rq| {
                if (try existsFunctionForRequirement(info, rq, impl.ty, s, allocator)) continue;
                try reportMissingRequirement(.{
                    .label = "type",
                    .abstract_name = abs_name,
                    .concrete = impl.ty,
                    .location = impl.location,
                }, &rq, s, allocator, diags);
                any_error = true;
            }
        }
    }

    var it_def = s.abstract_defaults.iterator();
    while (it_def.next()) |entry| {
        const abs_name = entry.key_ptr.*;
        const def_entry = entry.value_ptr.*;
        const info = s.lookupAbstractInfo(abs_name) orelse continue;

        for (info.requirements) |rq| {
            if (try existsFunctionForRequirement(info, rq, def_entry.ty, s, allocator)) continue;
            try reportMissingRequirement(.{
                .label = "default type",
                .abstract_name = abs_name,
                .concrete = def_entry.ty,
                .location = def_entry.location,
            }, &rq, s, allocator, diags);
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
                var line_col_buf: [32]u8 = undefined;
                const line_col = std.fmt.bufPrint(&line_col_buf, "{d}:{d}", .{ cand.location.line, cand.location.column }) catch "?";
                try buf.appendSlice(line_col);
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
