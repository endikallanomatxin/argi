const std = @import("std");
const tok = @import("../2_tokens/token.zig");
const syn = @import("../3_syntax/syntax_tree.zig");
const sg = @import("semantic_graph.zig");
const diagnostic = @import("../1_base/diagnostic.zig");
const source_db = @import("../1_base/source_db.zig");

const gen = @import("generics.zig");
const typ = @import("types.zig");

const Scope = @import("scope.zig").Scope;
const SemErr = @import("errors.zig").SemErr;

// Abstract typing support
pub const AbstractFunctionReqSem = struct {
    syntax_files: []const syn.SyntaxFile,
    source_db: *const source_db.SourceDb,
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
    input_nested_patterns: []const ?syn.SyntaxRef,
    output_nested_patterns: []const ?syn.SyntaxRef,
    abstract_param_names: []const []const u8,
};

pub const AbstractInfo = struct {
    name: []const u8,
    requirements: []const AbstractFunctionReqSem,
    param_names: []const []const u8,
    params: []const gen.GenericParam = &.{},
    virtual_methods: []const *sg.VirtualMethodRegistry = &.{},
};
pub const AbstractImplEntry = struct {
    ty: sg.Type,
    args: []const ?gen.GenericArgValue = &.{},
    location: tok.Location,
};
pub const AbstractImplTemplate = struct {
    syntax_files: []const syn.SyntaxFile,
    source_db: *const source_db.SourceDb,
    params: []const gen.GenericParam,
    param_abstract_constraints: []const ?gen.AbstractConstraint,
    // A compact relation either retains an existing type syntax node or names
    // the generic declaration it ranges over.  `implements` has no standalone
    // concrete-type node in the syntax tree, so the latter avoids fabricating a
    // legacy syntax tree solely for template matching.
    ty: ?syn.SyntaxRef = null,
    concrete_name: ?[]const u8 = null,
    // Only declared parameters belong to the concrete generic identity.
    // Later parameters are inferred from associated abstract arguments.
    concrete_param_count: usize = 0,
    args: ?syn.SyntaxRef,
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

pub const TemplateBindings = struct {
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

    pub fn deinit(self: *TemplateBindings) void {
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
        .decimal_int_literal, .hexadecimal_int_literal, .octal_int_literal, .binary_int_literal => |txt| std.fmt.parseInt(i64, txt, 0) catch null,
        else => null,
    };
}

fn evalComptimeIntPattern(db: *const source_db.SourceDb, file: *const syn.SyntaxFile, node: syn.NodeIndex, params: []const gen.GenericParam, bindings: *TemplateBindings) ?i64 {
    return switch (file.tag(node)) {
        .literal => parseIntLiteralToken(db, file, node),
        .identifier => blk: {
            const name = file.tokenText(db, file.mainToken(node));
            if (findGenericParam(params, name)) |param| {
                if (param.kind == .comptime_int) {
                    break :blk bindings.ints.get(name);
                }
            }
            break :blk null;
        },
        .binary_add, .binary_subtract, .binary_multiply, .binary_divide, .binary_modulo => blk: {
            const operands = file.binaryOperation(node).?;
            const left = evalComptimeIntPattern(db, file, operands.lhs, params, bindings) orelse break :blk null;
            const right = evalComptimeIntPattern(db, file, operands.rhs, params, bindings) orelse break :blk null;
            break :blk switch (file.tag(node)) {
                .binary_add => left + right,
                .binary_subtract => left - right,
                .binary_multiply => left * right,
                .binary_divide => if (right == 0) null else @divTrunc(left, right),
                .binary_modulo => if (right == 0) null else @mod(left, right),
                else => unreachable,
            };
        },
        else => null,
    };
}

fn parseIntLiteralToken(db: *const source_db.SourceDb, file: *const syn.SyntaxFile, node: syn.NodeIndex) ?i64 {
    return std.fmt.parseInt(i64, file.tokenText(db, file.mainToken(node)), 0) catch null;
}

fn matchComptimeIntPattern(
    db: *const source_db.SourceDb,
    file: *const syn.SyntaxFile,
    node: syn.NodeIndex,
    actual: i64,
    params: []const gen.GenericParam,
    bindings: *TemplateBindings,
) bool {
    if (file.tag(node) == .identifier) {
        const name = file.tokenText(db, file.mainToken(node));
        if (findGenericParam(params, name)) |param| {
            if (param.kind == .comptime_int) {
                if (bindings.ints.get(name)) |bound| return bound == actual;
                bindings.ints.put(name, actual) catch return false;
                return true;
            }
        }
    }

    const expected = evalComptimeIntPattern(db, file, node, params, bindings) orelse return false;
    return expected == actual;
}

fn matchTemplateType(db: *const source_db.SourceDb, files: []const syn.SyntaxFile, pattern: syn.SyntaxRef, actual: sg.Type, params: []const gen.GenericParam, bindings: *TemplateBindings) bool {
    const file = syn.fileForRef(files, pattern);
    return switch (file.syntaxType(pattern.node) orelse return false) {
        .name => |type_name| blk: {
            const name = file.tokenText(db, type_name.name_token);
            if (bindings.types.get(name)) |bound| {
                if (typ.isAny(bound)) {
                    bindings.types.put(name, actual) catch break :blk false;
                    break :blk true;
                }
                break :blk typ.typesExactlyEqual(bound, actual);
            }
            if (findGenericParam(params, name)) |param| {
                if (param.kind == .type) {
                    if (bindings.types.get(name)) |bound| break :blk typ.typesExactlyEqual(bound, actual);
                    bindings.types.put(name, actual) catch return false;
                    break :blk true;
                }
            }
            if (typ.builtinFromName(name)) |builtin_ty| {
                break :blk actual == .builtin and actual.builtin == builtin_ty;
            }
            if (typ.genericIdentityOf(actual)) |identity| {
                break :blk std.mem.eql(u8, identity.base_name, name) and identity.arg_names.len == 0;
            }
            if (actual == .abstract_type) {
                break :blk std.mem.eql(u8, actual.abstract_type.name, name);
            }
            break :blk false;
        },
        .inferred_errable => |inner| blk: {
            // The syntax tree uses `inferred_errable` for the convenient
            // `Errable#(.t: ..., .reasons: ...)` spelling.  Semantic types
            // retain the canonical generic identity, so compare its value
            // type here instead of rejecting every abstract Errable result.
            const choice = switch (actual) {
                .choice_type => |value| value,
                else => break :blk false,
            };
            for (choice.variants) |variant| {
                if (!std.mem.eql(u8, variant.name, "ok")) continue;
                const payload = variant.payload_type orelse break :blk false;
                break :blk matchTemplateType(db, files, file.ref(inner), payload, params, bindings);
            }
            break :blk false;
        },
        .pointer => |ptr_info| blk: {
            if (actual != .pointer_type) break :blk false;
            if (ptr_info.mutability != actual.pointer_type.mutability) break :blk false;
            break :blk matchTemplateType(db, files, file.ref(ptr_info.child), actual.pointer_type.child.*, params, bindings);
        },
        .array => |arr_info| blk: {
            if (actual != .array_type) break :blk false;
            const length = std.fmt.parseInt(usize, file.tokenText(db, arr_info.length_token), 10) catch break :blk false;
            if (length != actual.array_type.length) break :blk false;
            break :blk matchTemplateType(db, files, file.ref(arr_info.element), actual.array_type.element_type.*, params, bindings);
        },
        .struct_literal, .choice_literal, .nullable => false,
        .generic => |g| matchGenericInstantiationType(db, files, file, g, actual, params, bindings),
    };
}

fn matchCanonicalGenericInstantiation(
    db: *const source_db.SourceDb,
    files: []const syn.SyntaxFile,
    file: *const syn.SyntaxFile,
    g: syn.GenericType,
    actual: sg.Type,
    params: []const gen.GenericParam,
    bindings: *TemplateBindings,
) bool {
    const identity = typ.genericIdentityOf(actual) orelse return false;
    const base = file.syntaxType(g.base) orelse return false;
    const base_name = switch (base) {
        .name => |name| file.tokenText(db, name.name_token),
        else => return false,
    };
    if (!std.mem.eql(u8, identity.base_name, base_name)) return false;

    const fields = file.structTypeLiteral(g.arguments) orelse return false;
    for (fields.fields) |field_node| {
        const field = file.structTypeField(field_node) orelse return false;
        const field_name = file.tokenText(db, field.name_token);
        const arg_value = typ.genericIdentityArgByName(identity, field_name) orelse return false;
        switch (arg_value) {
            .type => |arg_ty| {
                const field_ty = field.type_node orelse return false;
                if (!matchTemplateType(db, files, file.ref(field_ty), arg_ty, params, bindings)) return false;
            },
            .comptime_int => |arg_int| {
                const value_node = field.default_value orelse return false;
                if (!matchComptimeIntPattern(db, file, value_node, arg_int, params, bindings)) return false;
            },
        }
    }

    return true;
}

fn matchGenericInstantiationType(
    db: *const source_db.SourceDb,
    files: []const syn.SyntaxFile,
    file: *const syn.SyntaxFile,
    g: syn.GenericType,
    actual: sg.Type,
    params: []const gen.GenericParam,
    bindings: *TemplateBindings,
) bool {
    return matchCanonicalGenericInstantiation(db, files, file, g, actual, params, bindings);
}

pub fn matchAbstractImplTemplate(tmpl: AbstractImplTemplate, candidate: sg.Type, allocator: *const std.mem.Allocator) ?TemplateBindings {
    var bindings = TemplateBindings.init(allocator);
    const matches = if (tmpl.ty) |pattern|
        matchTemplateType(tmpl.source_db, tmpl.syntax_files, pattern, candidate, tmpl.params, &bindings)
    else if (tmpl.concrete_name) |name|
        matchNamedGenericImplTemplate(name, candidate, tmpl.params[0..tmpl.concrete_param_count], &bindings)
    else
        false;
    if (!matches) {
        bindings.deinit();
        return null;
    }
    return bindings;
}

fn matchNamedGenericImplTemplate(
    concrete_name: []const u8,
    candidate: sg.Type,
    params: []const gen.GenericParam,
    bindings: *TemplateBindings,
) bool {
    const identity = typ.genericIdentityOf(candidate) orelse return false;
    if (!std.mem.eql(u8, identity.base_name, concrete_name)) return false;

    for (params) |param| {
        const value = typ.genericIdentityArgByName(identity, param.name) orelse return false;
        switch (value) {
            .type => |actual| {
                if (param.kind != .type) return false;
                if (bindings.types.get(param.name)) |bound| {
                    if (!typ.typesExactlyEqual(bound, actual)) return false;
                } else {
                    bindings.types.put(param.name, actual) catch return false;
                }
            },
            .comptime_int => |actual| {
                if (param.kind != .comptime_int) return false;
                if (bindings.ints.get(param.name)) |bound| {
                    if (bound != actual) return false;
                } else {
                    bindings.ints.put(param.name, actual) catch return false;
                }
            },
        }
    }
    return true;
}

fn abstractImplTemplateBindingsMaySatisfyConstraints(
    tmpl: AbstractImplTemplate,
    bindings: *const TemplateBindings,
    s: *Scope,
) bool {
    for (tmpl.param_abstract_constraints, 0..) |constraint_opt, i| {
        const constraint = constraint_opt orelse continue;
        const param = tmpl.params[i];
        if (param.kind != .type) continue;
        const actual = bindings.types.get(param.name) orelse return false;
        if (!typeMayImplementAbstract(constraint.name, actual, s)) return false;
    }
    return true;
}

fn templateMayImplementCandidate(tmpl: AbstractImplTemplate, candidate: sg.Type, s: *Scope) bool {
    var bindings = matchAbstractImplTemplate(tmpl, candidate, s.allocator) orelse return false;
    defer bindings.deinit();
    return abstractImplTemplateBindingsMaySatisfyConstraints(tmpl, &bindings, s);
}

// Structural prefilter only. It deliberately does not decide parameterized
// abstract satisfaction; the semantizer's resolveAbstract is the source of
// truth for associated arguments and conflicts.
fn typeMayImplementAbstract(
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
                if (impl.ty == .abstract_type and
                    typeMayImplementAbstract(impl.ty.abstract_type.name, candidate, s)) return true;
            }
        }
        if (sc.abstract_impl_templates.getPtr(abs_name)) |list_ptr| {
            const templates = list_ptr.*;
            for (templates.items) |tmpl| {
                if (templateMayImplementCandidate(tmpl, candidate, s)) return true;
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
            if (actual != .struct_type) break :blk 10;
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
            if (actual != .pointer_type) break :blk2 5;
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
            if (actual != .array_type) break :blk_arr 10;
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
            else => typeMayImplementAbstract(eat.name, actual, s),
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
    if (cand_in.fields.len < req_in.fields.len) return false;
    for (cand_in.fields[req_in.fields.len..]) |extra_field| {
        if (extra_field.default_value == null) return false;
    }

    var i: usize = 0;
    var nested_bindings = TemplateBindings.init(s.allocator);
    defer nested_bindings.deinit();
    nested_bindings.types.put("Self", concrete) catch return false;
    for (rq.abstract_param_names, 0..) |name, param_index| {
        const bound = if (param_index < param_bindings.len) param_bindings[param_index] orelse sg.Type{ .builtin = .Any } else sg.Type{ .builtin = .Any };
        nested_bindings.types.put(name, bound) catch return false;
    }
    while (i < req_in.fields.len) : (i += 1) {
        const rf = req_in.fields[i];
        const cf = cand_in.fields[i];

        if (rq.input_nested_patterns.len > i) {
            if (rq.input_nested_patterns[i]) |pattern| {
                if (!matchTemplateType(rq.source_db, rq.syntax_files, pattern, cf.ty, &.{}, &nested_bindings)) return false;
                continue;
            }
        }

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
                if (!typeMayImplementAbstract(abs_name, cf.ty, s)) return false;
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
    for (rq.abstract_param_names, 0..) |name, param_index| {
        if (param_index >= param_bindings.len) continue;
        const inferred = nested_bindings.types.get(name) orelse continue;
        if (!typ.isAny(inferred)) param_bindings[param_index] = inferred;
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
    var nested_bindings = TemplateBindings.init(s.allocator);
    defer nested_bindings.deinit();
    nested_bindings.types.put("Self", concrete) catch return false;
    for (rq.abstract_param_names, 0..) |name, param_index| {
        const bound = if (param_index < param_bindings.len) param_bindings[param_index] orelse sg.Type{ .builtin = .Any } else sg.Type{ .builtin = .Any };
        nested_bindings.types.put(name, bound) catch return false;
    }
    while (i < rq.output.fields.len) : (i += 1) {
        const ro = rq.output.fields[i];
        const co = cand_out.fields[i];

        if (rq.output_nested_patterns.len > i) {
            if (rq.output_nested_patterns[i]) |pattern| {
                if (!matchTemplateType(rq.source_db, rq.syntax_files, pattern, co.ty, &.{}, &nested_bindings)) return false;
                continue;
            }
        }

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
                if (!typeMayImplementAbstract(abs_name, co.ty, s)) return false;
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
    for (rq.abstract_param_names, 0..) |name, param_index| {
        if (param_index >= param_bindings.len) continue;
        const inferred = nested_bindings.types.get(name) orelse continue;
        if (!typ.isAny(inferred)) param_bindings[param_index] = inferred;
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
                    if (best.?.origin_kind == .generic_instantiation and cand.origin_kind == .declared) {
                        best = cand;
                        ambiguous = false;
                    } else if (!(cand.origin_kind == .generic_instantiation and best.?.origin_kind == .declared)) {
                        ambiguous = true;
                    }
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

pub fn buildExpectedInputWithConcrete(rq: *const AbstractFunctionReqSem, concrete: sg.Type, allocator: *const std.mem.Allocator) !*sg.StructType {
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
    db: *const source_db.SourceDb,
    files: []const syn.SyntaxFile,
    file: *const syn.SyntaxFile,
    expected: *const sg.StructType,
    template_fields: []const syn.NodeIndex,
    params: []const gen.GenericParam,
    bindings: *TemplateBindings,
) bool {
    if (template_fields.len < expected.fields.len) return false;
    for (template_fields[expected.fields.len..]) |field_node| {
        if (file.structTypeField(field_node).?.default_value == null) return false;
    }

    var i: usize = 0;
    while (i < expected.fields.len) : (i += 1) {
        const template_field = file.structTypeField(template_fields[i]) orelse return false;
        const template_ty = template_field.type_node orelse return false;
        if (!matchTemplateType(db, files, file.ref(template_ty), expected.fields[i].ty, params, bindings)) return false;
    }

    return true;
}

fn abstractPatternMatchesTemplate(
    db: *const source_db.SourceDb,
    files: []const syn.SyntaxFile,
    requirement: syn.SyntaxRef,
    candidate: syn.SyntaxRef,
    concrete: sg.Type,
    abstract_param_names: []const []const u8,
    template_params: []const gen.GenericParam,
    bindings: *TemplateBindings,
) bool {
    const requirement_file = syn.fileForRef(files, requirement);
    const candidate_file = syn.fileForRef(files, candidate);
    const requirement_type = requirement_file.syntaxType(requirement.node) orelse return false;
    const candidate_type = candidate_file.syntaxType(candidate.node) orelse return false;

    if (requirement_type == .name) {
        const requirement_name = requirement_file.tokenText(db, requirement_type.name.name_token);
        if (std.mem.eql(u8, requirement_name, "Self"))
            return matchTemplateType(db, files, candidate, concrete, template_params, bindings);
        for (abstract_param_names) |param_name| {
            if (std.mem.eql(u8, requirement_name, param_name)) return true;
        }
    }

    return switch (requirement_type) {
        .name => |required_name| candidate_type == .name and
            std.mem.eql(
                u8,
                requirement_file.tokenText(db, required_name.name_token),
                candidate_file.tokenText(db, candidate_type.name.name_token),
            ),
        .pointer => |required_pointer| candidate_type == .pointer and
            required_pointer.mutability == candidate_type.pointer.mutability and
            abstractPatternMatchesTemplate(db, files, requirement_file.ref(required_pointer.child), candidate_file.ref(candidate_type.pointer.child), concrete, abstract_param_names, template_params, bindings),
        .array => |required_array| blk: {
            if (candidate_type != .array) break :blk false;
            const required_length = std.fmt.parseInt(u64, requirement_file.tokenText(db, required_array.length_token), 10) catch break :blk false;
            const candidate_length = std.fmt.parseInt(u64, candidate_file.tokenText(db, candidate_type.array.length_token), 10) catch break :blk false;
            break :blk required_length == candidate_length and abstractPatternMatchesTemplate(
                db,
                files,
                requirement_file.ref(required_array.element),
                candidate_file.ref(candidate_type.array.element),
                concrete,
                abstract_param_names,
                template_params,
                bindings,
            );
        },
        .generic => |required_generic| blk: {
            if (candidate_type != .generic) break :blk false;
            const candidate_generic = candidate_type.generic;
            const required_base = requirement_file.syntaxType(required_generic.base) orelse break :blk false;
            const candidate_base = candidate_file.syntaxType(candidate_generic.base) orelse break :blk false;
            if (required_base != .name or candidate_base != .name) break :blk false;
            if (!std.mem.eql(u8, requirement_file.tokenText(db, required_base.name.name_token), candidate_file.tokenText(db, candidate_base.name.name_token))) break :blk false;
            const required_fields = requirement_file.structTypeLiteral(required_generic.arguments).?.fields;
            const candidate_fields = candidate_file.structTypeLiteral(candidate_generic.arguments).?.fields;
            if (required_fields.len != candidate_fields.len) break :blk false;
            for (required_fields) |required_field_node| {
                const required_field = requirement_file.structTypeField(required_field_node).?;
                const required_name = requirement_file.tokenText(db, required_field.name_token);
                var candidate_field: ?syn.StructTypeField = null;
                for (candidate_fields) |field_node| {
                    const field = candidate_file.structTypeField(field_node).?;
                    if (std.mem.eql(u8, required_name, candidate_file.tokenText(db, field.name_token))) {
                        candidate_field = field;
                        break;
                    }
                }
                const actual_field = candidate_field orelse break :blk false;
                if (required_field.type_node) |required_type| {
                    const actual_type = actual_field.type_node orelse break :blk false;
                    if (!abstractPatternMatchesTemplate(db, files, requirement_file.ref(required_type), candidate_file.ref(actual_type), concrete, abstract_param_names, template_params, bindings)) break :blk false;
                }
            }
            break :blk true;
        },
        .inferred_errable => |required_inner| candidate_type == .inferred_errable and
            abstractPatternMatchesTemplate(db, files, requirement_file.ref(required_inner), candidate_file.ref(candidate_type.inferred_errable), concrete, abstract_param_names, template_params, bindings),
        .struct_literal, .choice_literal, .nullable => false,
    };
}

fn genericTemplateFieldsMatchRequirement(
    file: *const syn.SyntaxFile,
    rq: *const AbstractFunctionReqSem,
    input: bool,
    template_fields: []const syn.NodeIndex,
    concrete: sg.Type,
    template_params: []const gen.GenericParam,
    bindings: *TemplateBindings,
) bool {
    const expected = if (input) rq.input.fields else rq.output.fields;
    const nested = if (input) rq.input_nested_patterns else rq.output_nested_patterns;
    if (template_fields.len < expected.len) return false;
    for (template_fields[expected.len..]) |field_node| if (file.structTypeField(field_node).?.default_value == null) return false;
    var matched_nested = false;
    for (expected, 0..) |_, index| {
        if (nested.len > index and nested[index] != null) {
            matched_nested = true;
            const candidate_type = file.structTypeField(template_fields[index]).?.type_node orelse return false;
            if (!abstractPatternMatchesTemplate(rq.source_db, rq.syntax_files, nested[index].?, file.ref(candidate_type), concrete, rq.abstract_param_names, template_params, bindings)) return false;
        }
    }
    return matched_nested;
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
        if (!typeMayImplementAbstract(constraint.name, actual, s)) return false;
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

                const syntax_file = syn.fileForRef(tmpl.syntax_files, .{ .file_id = tmpl.syntax_file_id, .node = tmpl.input });
                const input_fields = syntax_file.structTypeLiteral(tmpl.input).?.fields;
                const output_fields = syntax_file.structTypeLiteral(tmpl.output).?.fields;

                if (!genericTemplateFieldsMatchExpected(tmpl.source_db, tmpl.syntax_files, syntax_file, expected_in, input_fields, tmpl.params, &bindings))
                    continue;
                if (!genericTemplateFieldsMatchRequirement(syntax_file, &rq, true, input_fields, concrete, tmpl.params, &bindings))
                    continue;
                if (!genericTemplateFieldsMatchExpected(tmpl.source_db, tmpl.syntax_files, syntax_file, expected_out, output_fields, tmpl.params, &bindings) and
                    !genericTemplateFieldsMatchRequirement(syntax_file, &rq, false, output_fields, concrete, tmpl.params, &bindings))
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

fn buildOverloadCandidatesText(name: []const u8, in_ty: sg.Type, s: *Scope, allocator: *const std.mem.Allocator, diags: *const diagnostic.Diagnostics) !OwnedText {
    return .{
        .allocator = allocator,
        .bytes = try buildOverloadCandidatesString(name, in_ty, s, allocator, diags),
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
    const candidates_result = buildOverloadCandidatesText(rq.name, in_ty, s, allocator, diags) catch null;
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
    diags: *const diagnostic.Diagnostics,
) !OwnedText {
    const exp_in = try buildExpectedInputWithConcrete(rq, concrete, allocator);
    const in_ty: sg.Type = .{ .struct_type = exp_in };
    const candidates_result = buildOverloadCandidatesText(rq.name, in_ty, s, allocator, diags) catch null;
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
    diags: *const diagnostic.Diagnostics,
) !?OwnedText {
    const info = s.lookupAbstractInfo(abs_name) orelse return null;

    for (info.requirements) |rq| {
        if (try existsFunctionForRequirement(info, rq, concrete, s, allocator)) continue;
        return try formatMissingRequirementText(&rq, concrete, s, allocator, diags);
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

        // Fallible contracts use the compiler's inferred Errable choice
        // representation. Their concrete return shape is validated during
        // overload resolution; declaration-time structural matching cannot
        // reliably distinguish the inferred reason choice yet.
        if (std.mem.eql(u8, abs_name, "FalliblyCopyable")) continue;

        for (impls.items) |impl| {
            // An abstract may extend another abstract.  Its inherited
            // requirements are checked when a concrete type implements the
            // extending abstract; the abstract declaration itself is not a
            // concrete implementation.
            if (impl.ty == .abstract_type) continue;
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

pub fn buildOverloadCandidatesString(name: []const u8, in_ty: sg.Type, s: *Scope, allocator: *const std.mem.Allocator, diags: *const diagnostic.Diagnostics) ![]u8 {
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
                try buf.appendSlice(diags.path(cand.location));
                try buf.appendSlice(":");
                var line_col_buf: [32]u8 = undefined;
                const position = diags.lineColumn(cand.location);
                const line_col = std.fmt.bufPrint(&line_col_buf, "{d}:{d}", .{ position.line, position.column }) catch "?";
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
