const std = @import("std");
const graph_mod = @import("graph.zig");
const types = @import("types.zig");

/// The supported foreign scalar boundary is deliberately narrower than ordinary
/// LLVM type lowering. Record layout alone does not establish how a platform's
/// C ABI classifies an aggregate argument or result. Extend this predicate only
/// alongside matching call lowering and cross-language executable tests.
/// Aggregate classification must consider the full function signature: SysV
/// register exhaustion can move an entire argument to memory even when that
/// same record uses registers in another function. A per-type layout cache
/// cannot encode that calling convention.
pub fn supportsCValue(graph: *const graph_mod.GlobalSemanticGraph, ty: graph_mod.GlobalTypeId) bool {
    return classifyValue(graph, ty, @import("builtin").target, false) != null;
}

fn supportsScalarValue(graph: *const graph_mod.GlobalSemanticGraph, ty: graph_mod.GlobalTypeId, depth: usize) bool {
    if (depth >= 32) return false;
    if (isRawPointer(graph, ty)) return true;
    return switch (graph.types.items[@intFromEnum(ty)]) {
        .builtin => |builtin| switch (builtin) {
            .Int8, .Int16, .Int32, .Int64, .UInt8, .UInt16, .UInt32, .UInt64, .UIntNative, .Float32, .Float64, .Char, .Bool => true,
            else => false,
        },
        // Legacy bindings use references as pointer parameters. Their pointee
        // layout and foreign effects remain obligations of the binding.
        .pointer => true,
        .declared => |id| graph.declaration(id).choice_variants != null and
            graph.declaration(id).choice_layout == .c_enum,
        .structural_choice => |shape| shape.layout == .c_enum,
        .generic => if (types.genericInstance(graph, ty)) |instance| switch (instance.shape) {
            .alias => |target| supportsScalarValue(graph, target, depth + 1),
            .choice => |shape| shape.layout == .c_enum,
            else => false,
        } else false,
        else => false,
    };
}

/// Foreign imports have a logical reached capability argument. It participates
/// in ordinary dependency resolution and safety, but never in the C ABI. Add
/// it after relocation so its nominal identity comes from bundled core rather
/// than a user declaration with the same spelling.
pub fn prepareForeignCapabilities(allocator: std.mem.Allocator, graph: *graph_mod.GlobalSemanticGraph) !void {
    var capability: ?graph_mod.GlobalTypeId = null;
    for (graph.declarations.items, 0..) |declaration, index| {
        if (!std.mem.eql(u8, graph.text(declaration.name), "ForeignFunctionInterface")) continue;
        const owner = graph.moduleForDeclaration(@enumFromInt(index)) orelse continue;
        if (!graph.modules.items[@intFromEnum(owner)].is_bundled_core) continue;
        capability = declaration.type_id;
        break;
    }
    const child = capability orelse return;
    const pointer: graph_mod.GlobalTypeId = @enumFromInt(graph.types.items.len);
    try graph.types.append(allocator, .{ .pointer = .{ .child = child, .mutability = .read_write } });
    const name = try graph.addString(allocator, "ffi");
    for (graph.functions.items) |*function| {
        if (!function.flags.is_c_abi or function.flags.has_declared_body or function.flags.is_abstract_dispatch) continue;
        const source = graph.declaration(function.declaration).source;
        const segment_start: u32 = @intCast(graph.reach_segments.items.len);
        try graph.reach_segments.append(allocator, name);
        const alternative_start: u32 = @intCast(graph.reach_alternatives.items.len);
        try graph.reach_alternatives.append(allocator, .{ .segments = .{ .start = segment_start, .len = 1 } });
        const reach: graph_mod.GlobalReachId = @enumFromInt(graph.reaches.items.len);
        try graph.reaches.append(allocator, .{ .alternatives = .{ .start = alternative_start, .len = 1 } });
        const fallback: graph_mod.GlobalNodeId = @enumFromInt(graph.nodes.items.len);
        try graph.nodes.append(allocator, .{ .source = source, .ty = pointer, .content = .{ .reach_directive = reach } });
        const old_fields = try allocator.dupe(graph_mod.Field, graph.fields.items[function.input.start..][0..function.input.len]);
        defer allocator.free(old_fields);
        const field_start: u32 = @intCast(graph.fields.items.len);
        try graph.fields.appendSlice(allocator, old_fields);
        try graph.fields.append(allocator, .{ .name = name, .ty = pointer, .source = source, .default_value = fallback });
        const old_bindings = try allocator.dupe(graph_mod.GlobalBindingId, graph.binding_refs.items[function.input_bindings.start..][0..function.input_bindings.len]);
        defer allocator.free(old_bindings);
        const binding: graph_mod.GlobalBindingId = @enumFromInt(graph.bindings.items.len);
        try graph.bindings.append(allocator, .{ .name = name, .ty = pointer, .source = source, .mutability = .constant });
        const binding_start: u32 = @intCast(graph.binding_refs.items.len);
        try graph.binding_refs.appendSlice(allocator, old_bindings);
        try graph.binding_refs.append(allocator, binding);
        function.input = .{ .start = field_start, .len = function.input.len + 1 };
        function.input_bindings = .{ .start = binding_start, .len = function.input_bindings.len + 1 };
        function.flags.has_foreign_capability = true;
    }
}

pub fn physicalInputCount(function: graph_mod.Function) u32 {
    return function.input.len - @as(u32, if (function.flags.has_foreign_capability) 1 else 0);
}

/// Only the bundled RawPointer value has this ABI adaptation. A structurally
/// identical user record still requires explicit C record layout/classification.
pub fn isRawPointer(graph: *const graph_mod.GlobalSemanticGraph, ty: graph_mod.GlobalTypeId) bool {
    return rawPointerDepth(graph, ty, 0);
}

fn rawPointerDepth(graph: *const graph_mod.GlobalSemanticGraph, ty: graph_mod.GlobalTypeId, depth: usize) bool {
    if (depth >= 32) return false;
    const generic = switch (graph.types.items[@intFromEnum(ty)]) {
        .generic => |value| value,
        else => return false,
    };
    const instance = types.genericInstance(graph, ty) orelse return false;
    switch (instance.shape) {
        .alias => |target| return rawPointerDepth(graph, target, depth + 1),
        .structure => |shape| {
            const declaration = graph.declaration(generic.base);
            if (!std.mem.eql(u8, graph.text(declaration.name), "RawPointer")) return false;
            const module = graph.moduleForDeclaration(generic.base) orelse return false;
            if (!graph.modules.items[@intFromEnum(module)].is_bundled_core or shape.fields.len != 1) return false;
            const field = graph.fields.items[shape.fields.start];
            return std.mem.eql(u8, graph.text(field.name), "address") and types.isBuiltin(graph, field.ty, .UIntNative);
        },
        else => return false,
    }
}

/// Representation compatibility is independent of argument/result classification.
/// A C record can be addressed by pointer before its by-value ABI is supported.
pub fn supportsRepresentation(graph: *const graph_mod.GlobalSemanticGraph, ty: graph_mod.GlobalTypeId) bool {
    return representationDepth(graph, ty, 0);
}

fn representationDepth(graph: *const graph_mod.GlobalSemanticGraph, ty: graph_mod.GlobalTypeId, depth: usize) bool {
    if (depth >= 32) return false;
    if (supportsCValue(graph, ty)) return true;
    return switch (graph.types.items[@intFromEnum(ty)]) {
        .declared => |id| blk: {
            const declaration = graph.declaration(id);
            if (declaration.struct_layout == .regular) break :blk false;
            break :blk fieldsHaveRepresentation(graph, declaration.struct_fields orelse break :blk false, depth);
        },
        .array => |shape| shape.length != 0 and representationDepth(graph, shape.element, depth + 1),
        .generic => if (types.genericInstance(graph, ty)) |instance| switch (instance.shape) {
            .alias => |target| representationDepth(graph, target, depth + 1),
            .array => |shape| shape.length != 0 and representationDepth(graph, shape.element, depth + 1),
            .structure => |shape| shape.layout != .regular and fieldsHaveRepresentation(graph, shape.fields, depth),
            else => false,
        } else false,
        else => false,
    };
}

fn fieldsHaveRepresentation(graph: *const graph_mod.GlobalSemanticGraph, range: graph_mod.FieldRange, depth: usize) bool {
    if (range.len == 0) return false;
    for (graph.fields.items[range.start..][0..range.len]) |field| {
        if (!representationDepth(graph, field.ty, depth + 1)) return false;
    }
    return true;
}

pub const ScalarExtension = enum { none, signed, unsigned };

/// Narrow scalar extension is a target calling-convention rule, independent
/// of its in-memory size. Darwin ARM64 differs from Linux AAPCS64 here.
pub fn scalarExtensionForTarget(builtin_type: @import("../primitives/schema.zig").BuiltinType, target: std.Target) ScalarExtension {
    const extends = switch (target.cpu.arch) {
        .x86_64, .x86 => target.os.tag != .windows,
        .aarch64 => target.os.tag.isDarwin(),
        else => false,
    };
    if (!extends) return .none;
    return switch (builtin_type) {
        .Int8, .Int16 => .signed,
        .UInt8, .UInt16, .Bool => .unsigned,
        else => .none,
    };
}

pub fn scalarExtension(graph: *const graph_mod.GlobalSemanticGraph, ty: graph_mod.GlobalTypeId, target: std.Target) ScalarExtension {
    var current = ty;
    for (0..32) |_| {
        const semantic = graph.resolvedSemanticType(current) orelse return .none;
        switch (semantic) {
            .builtin => |value| return scalarExtensionForTarget(value, target),
            .generic => {
                const instance = types.genericInstance(graph, current) orelse return .none;
                current = switch (instance.shape) {
                    .alias => |value| value,
                    else => return .none,
                };
            },
            else => return .none,
        }
    }
    return .none;
}

test "C narrow scalar extension follows the native ABI family" {
    var target = @import("builtin").target;
    target.cpu.arch = .x86_64;
    target.os.tag = .linux;
    try std.testing.expectEqual(ScalarExtension.signed, scalarExtensionForTarget(.Int16, target));
    try std.testing.expectEqual(ScalarExtension.unsigned, scalarExtensionForTarget(.Bool, target));
    target.cpu.arch = .aarch64;
    try std.testing.expectEqual(ScalarExtension.none, scalarExtensionForTarget(.Int16, target));
    target.os.tag = .macos;
    try std.testing.expectEqual(ScalarExtension.signed, scalarExtensionForTarget(.Int16, target));
    try std.testing.expectEqual(ScalarExtension.unsigned, scalarExtensionForTarget(.UInt8, target));
    try std.testing.expectEqual(ScalarExtension.none, scalarExtensionForTarget(.Int32, target));
}

pub const RecordForm = enum { single, split, array };
pub const ValueKind = enum { scalar, record_words, record_indirect };
pub const ValuePlan = struct {
    ty: graph_mod.GlobalTypeId,
    kind: ValueKind = .scalar,
    size: u64 = 0,
    alignment: u32 = 1,
    word_bits: [2]u16 = .{ 0, 0 },
    words: u8 = 0,
    form: RecordForm = .single,
    byval: bool = false,
    extension: ScalarExtension = .none,
    parameter_index: u32 = 0,

    pub fn parameterCount(self: ValuePlan) u32 {
        return if (self.kind == .record_words and self.form == .split) self.words else 1;
    }
};

pub const FunctionPlan = struct {
    inputs: []ValuePlan,
    result: ?ValuePlan,
    parameter_count: u32,
    uses_sret: bool,

    pub fn deinit(self: *FunctionPlan, allocator: std.mem.Allocator) void {
        allocator.free(self.inputs);
    }
};

fn isSysVX64(target: std.Target) bool {
    return target.cpu.arch == .x86_64 and (target.os.tag == .linux or target.os.tag.isDarwin());
}

fn supportsIntegerRecords(target: std.Target) bool {
    return target.ptrBitWidth() == 64 and (isSysVX64(target) or (target.cpu.arch == .aarch64 and (target.os.tag == .linux or target.os.tag.isDarwin())));
}

/// Integer-only C records share the INTEGER class on SysV and the ordinary
/// composite class on AAPCS64. Floating, pointer-bearing, union, and over-aligned
/// records need separate classification/effect handling and remain rejected.
fn integerRecordStorage(graph: *const graph_mod.GlobalSemanticGraph, ty: graph_mod.GlobalTypeId, depth: usize) bool {
    if (depth >= 32) return false;
    const semantic = graph.resolvedSemanticType(ty) orelse return false;
    return switch (semantic) {
        .builtin => |value| switch (value) {
            .Int8, .Int16, .Int32, .Int64, .UInt8, .UInt16, .UInt32, .UInt64, .UIntNative, .Char, .Bool => true,
            else => false,
        },
        .declared => |id| blk: {
            const declaration = graph.declaration(id);
            if (declaration.choice_layout == .c_enum and declaration.choice_variants != null) break :blk true;
            if (declaration.struct_layout != .c_struct) break :blk false;
            break :blk integerFields(graph, declaration.struct_fields orelse break :blk false, depth);
        },
        .structural => |shape| shape.layout == .c_struct and integerFields(graph, shape.fields, depth),
        .structural_choice => |shape| shape.layout == .c_enum,
        .array => |shape| shape.length != 0 and integerRecordStorage(graph, shape.element, depth + 1),
        .generic => if (types.genericInstance(graph, ty)) |instance| switch (instance.shape) {
            .alias => |value| integerRecordStorage(graph, value, depth + 1),
            .array => |shape| shape.length != 0 and integerRecordStorage(graph, shape.element, depth + 1),
            .structure => |shape| shape.layout == .c_struct and integerFields(graph, shape.fields, depth),
            .choice => |shape| shape.layout == .c_enum,
        } else false,
        else => false,
    };
}

fn integerFields(graph: *const graph_mod.GlobalSemanticGraph, fields: graph_mod.FieldRange, depth: usize) bool {
    if (fields.len == 0) return false;
    for (graph.fields.items[fields.start..][0..fields.len]) |field| {
        if (!integerRecordStorage(graph, field.ty, depth + 1)) return false;
    }
    return true;
}

fn classifyValue(graph: *const graph_mod.GlobalSemanticGraph, ty: graph_mod.GlobalTypeId, target: std.Target, result: bool) ?ValuePlan {
    if (supportsScalarValue(graph, ty, 0)) return .{ .ty = ty, .extension = scalarExtension(graph, ty, target) };
    // An array has C storage representation but is not itself a by-value C
    // parameter. Only explicit record identities enter composite classification.
    if (types.fields(graph, ty) == null or !supportsIntegerRecords(target) or !integerRecordStorage(graph, ty, 0)) return null;
    const layout = types.layoutOf(graph, ty) catch return null;
    if (layout.size == 0 or layout.size > std.math.maxInt(i64) or layout.alignment > 8) return null;
    var plan: ValuePlan = .{ .ty = ty, .size = layout.size, .alignment = @intCast(layout.alignment), .kind = .record_indirect };
    if (layout.size > 16) {
        plan.byval = isSysVX64(target) and !result;
        return plan;
    }
    plan.kind = .record_words;
    plan.words = if (layout.size > 8) 2 else 1;
    if (isSysVX64(target)) {
        plan.form = if (plan.words == 2) .split else .single;
        plan.word_bits = .{ @intCast(@as(u64, @min(layout.size, 8)) * 8), if (plan.words == 2) @intCast((layout.size - 8) * 8) else 0 };
    } else {
        plan.form = if (plan.words == 2) .array else .single;
        plan.word_bits = .{ if (result and plan.words == 1) @intCast(layout.size * 8) else 64, if (plan.words == 2) 64 else 0 };
    }
    return plan;
}

/// Signature planning is shared by declarations, incoming bindings, outgoing
/// calls, and returns. Byval arguments consume no SysV integer register, leaving
/// a remaining register available to later scalar arguments. AAPCS64 indirect
/// arguments instead pass a pointer to a caller-owned copy.
pub fn classifyFunction(allocator: std.mem.Allocator, graph: *const graph_mod.GlobalSemanticGraph, function: graph_mod.Function, target: std.Target) !FunctionPlan {
    if (function.output.len > 1) return error.UnsupportedCABI;
    const output = if (function.output.len == 1) classifyValue(graph, graph.fields.items[function.output.start].ty, target, true) orelse return error.UnsupportedCABI else null;
    const sret = if (output) |value| value.kind == .record_indirect else false;
    const inputs = try allocator.alloc(ValuePlan, physicalInputCount(function));
    errdefer allocator.free(inputs);
    var cursor: u32 = if (sret) 1 else 0;
    var integer_registers: u32 = if (isSysVX64(target)) (if (sret) @as(u32, 5) else 6) else 8;
    for (graph.fields.items[function.input.start..][0..inputs.len], inputs) |field, *plan| {
        plan.* = classifyValue(graph, field.ty, target, false) orelse return error.UnsupportedCABI;
        if (isSysVX64(target) and plan.kind == .record_words and plan.words == 2 and integer_registers < 2) {
            plan.kind = .record_indirect;
            plan.byval = true;
        }
        plan.parameter_index = cursor;
        cursor += plan.parameterCount();
        const registers: u32 = switch (plan.kind) {
            .record_indirect => if (plan.byval) 0 else 1,
            .record_words => plan.words,
            .scalar => if (scalarIsFloating(graph, field.ty)) 0 else 1,
        };
        integer_registers -= @min(integer_registers, registers);
    }
    return .{ .inputs = inputs, .result = output, .parameter_count = cursor, .uses_sret = sret };
}

fn scalarIsFloating(graph: *const graph_mod.GlobalSemanticGraph, ty: graph_mod.GlobalTypeId) bool {
    var current = ty;
    for (0..32) |_| {
        const semantic = graph.resolvedSemanticType(current) orelse return false;
        switch (semantic) {
            .builtin => |value| return value == .Float32 or value == .Float64,
            .generic => {
                const instance = types.genericInstance(graph, current) orelse return false;
                current = switch (instance.shape) {
                    .alias => |value| value,
                    else => return false,
                };
            },
            else => return false,
        }
    }
    return false;
}

/// LLVM opaque pointer types alone cannot distinguish sret, byval, and ordinary
/// pointer parameters, or narrow integer extension attributes. Symbol reuse
/// compares these obligations as well as the physical LLVM function type.
pub fn sameABIAttributes(left: FunctionPlan, right: FunctionPlan) bool {
    if (left.uses_sret != right.uses_sret) return false;
    const left_return = if (left.result) |value| value.extension else ScalarExtension.none;
    const right_return = if (right.result) |value| value.extension else ScalarExtension.none;
    if (left_return != right_return) return false;
    for (0..left.parameter_count) |index| {
        if (parameterExtension(left, index) != parameterExtension(right, index)) return false;
    }
    if (left.uses_sret and (left.result.?.size != right.result.?.size or left.result.?.alignment != right.result.?.alignment)) return false;
    for (left.inputs) |input| {
        if (!input.byval) continue;
        var matching = false;
        for (right.inputs) |other| {
            if (!other.byval or input.parameter_index != other.parameter_index) continue;
            if (input.size != other.size or input.alignment != other.alignment) return false;
            matching = true;
        }
        if (!matching) return false;
    }
    for (right.inputs) |input| {
        if (!input.byval) continue;
        var matching = false;
        for (left.inputs) |other| if (other.byval and input.parameter_index == other.parameter_index) {
            matching = true;
        };
        if (!matching) return false;
    }
    return true;
}

test "C record signature planning distinguishes SysV byval from AAPCS64 copies" {
    const allocator = std.testing.allocator;
    var graph: graph_mod.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);
    try graph.types.appendSlice(allocator, &.{
        .{ .builtin = .Int32 },                                                           .{ .builtin = .Int64 },
        .{ .structural = .{ .fields = .{ .start = 0, .len = 2 }, .layout = .c_struct } }, .{ .structural = .{ .fields = .{ .start = 0, .len = 3 }, .layout = .c_struct } },
    });
    const field: graph_mod.Field = .{ .name = .{ .start = 0, .len = 0 }, .ty = @enumFromInt(1), .source = .{ .file_index = 0, .offset = 0 } };
    try graph.fields.appendNTimes(allocator, field, 3);
    var integer = field;
    integer.ty = @enumFromInt(0);
    try graph.fields.appendNTimes(allocator, integer, 5);
    var words = field;
    words.ty = @enumFromInt(2);
    try graph.fields.append(allocator, words);
    try graph.fields.append(allocator, integer);
    var output = field;
    output.ty = @enumFromInt(3);
    try graph.fields.append(allocator, output);
    const function: graph_mod.Function = .{ .declaration = @enumFromInt(0), .input = .{ .start = 3, .len = 7 }, .output = .{ .start = 10, .len = 1 } };
    var target = @import("builtin").target;
    target.cpu.arch = .x86_64;
    target.os.tag = .linux;
    var sysv = try classifyFunction(allocator, &graph, function, target);
    defer sysv.deinit(allocator);
    try std.testing.expect(sysv.uses_sret);
    try std.testing.expectEqual(ValueKind.record_indirect, sysv.inputs[5].kind);
    try std.testing.expect(sysv.inputs[5].byval);
    try std.testing.expectEqual(@as(u32, 1), sysv.inputs[0].parameter_index);
    target.cpu.arch = .aarch64;
    var arm = try classifyFunction(allocator, &graph, function, target);
    defer arm.deinit(allocator);
    try std.testing.expect(arm.uses_sret);
    try std.testing.expectEqual(ValueKind.record_words, arm.inputs[5].kind);
    try std.testing.expectEqual(RecordForm.array, arm.inputs[5].form);
    try std.testing.expect(!arm.inputs[5].byval);
    // Opaque LLVM pointer types would not detect this distinction.
    try std.testing.expect(!sameABIAttributes(sysv, arm));
}

fn parameterExtension(plan: FunctionPlan, index: usize) ScalarExtension {
    for (plan.inputs) |input| {
        if (input.parameter_index == index) return input.extension;
    }
    return .none;
}
