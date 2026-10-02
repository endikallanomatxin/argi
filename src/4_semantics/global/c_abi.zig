const std = @import("std");
const graph_mod = @import("graph.zig");
const types = @import("types.zig");

/// The supported foreign value boundary is deliberately narrower than ordinary
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
        .pointer => |pointer| types.incompleteDeclaration(graph, pointer.child) == null,
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
    if (supportsScalarValue(graph, ty, depth)) return true;
    return switch (graph.types.items[@intFromEnum(ty)]) {
        .declared => |id| blk: {
            const declaration = graph.declaration(id);
            if (declaration.struct_layout == .regular) break :blk false;
            break :blk fieldsHaveRepresentation(graph, declaration.struct_fields orelse break :blk false, depth);
        },
        .structural => |shape| shape.layout != .regular and fieldsHaveRepresentation(graph, shape.fields, depth),
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

pub const WordClass = enum { integer, float, float_pair, double };
pub const RecordForm = enum { single, split, array };
pub const ValueKind = enum { scalar, record_words, record_indirect };
pub const ValuePlan = struct {
    ty: graph_mod.GlobalTypeId,
    kind: ValueKind = .scalar,
    size: u64 = 0,
    alignment: u32 = 1,
    word_bits: [4]u16 = .{ 0, 0, 0, 0 },
    word_classes: [4]WordClass = @splat(.integer),
    word_offsets: [4]u8 = .{ 0, 8, 16, 24 },
    stack_alignment: u32 = 0,
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

fn supportsRecordTarget(target: std.Target) bool {
    return target.ptrBitWidth() == 64 and (isSysVX64(target) or (target.cpu.arch == .aarch64 and (target.os.tag == .linux or target.os.tag.isDarwin())));
}

/// RawPointer leaves are addresses, including inside arrays and unions.
/// Legacy reference fields cannot silently acquire safe provenance.
fn recordStorage(graph: *const graph_mod.GlobalSemanticGraph, ty: graph_mod.GlobalTypeId, depth: usize) bool {
    if (depth >= 32) return false;
    if (isRawPointer(graph, ty)) return true;
    const semantic = graph.resolvedSemanticType(ty) orelse return false;
    return switch (semantic) {
        .builtin => |value| switch (value) {
            .Int8, .Int16, .Int32, .Int64, .UInt8, .UInt16, .UInt32, .UInt64, .UIntNative, .Char, .Bool, .Float32, .Float64 => true,
            else => false,
        },
        .declared => |id| blk: {
            const declaration = graph.declaration(id);
            if (declaration.choice_layout == .c_enum and declaration.choice_variants != null) break :blk true;
            if (declaration.struct_layout == .regular) break :blk false;
            break :blk recordFields(graph, declaration.struct_fields orelse break :blk false, depth);
        },
        .structural => |shape| shape.layout != .regular and recordFields(graph, shape.fields, depth),
        .structural_choice => |shape| shape.layout == .c_enum,
        .array => |shape| shape.length != 0 and recordStorage(graph, shape.element, depth + 1),
        .generic => if (types.genericInstance(graph, ty)) |instance| switch (instance.shape) {
            .alias => |value| recordStorage(graph, value, depth + 1),
            .array => |shape| shape.length != 0 and recordStorage(graph, shape.element, depth + 1),
            .structure => |shape| shape.layout != .regular and recordFields(graph, shape.fields, depth),
            .choice => |shape| shape.layout == .c_enum,
        } else false,
        else => false,
    };
}

fn recordFields(graph: *const graph_mod.GlobalSemanticGraph, fields: graph_mod.FieldRange, depth: usize) bool {
    if (fields.len == 0) return false;
    for (graph.fields.items[fields.start..][0..fields.len]) |field| {
        if (!recordStorage(graph, field.ty, depth + 1)) return false;
    }
    return true;
}

// Collect leaves after C layout, not declaration nesting: arrays and nested
// records participate in homogeneous aggregate detection. SysV INTEGER wins
// over SSE within an eightbyte; padding contributes neither a class nor bits.
const NumericShape = struct {
    classes: [2]?WordClass = .{ null, null },
    bits: [2]u16 = .{ 0, 0 },
    float_mask: [2]u8 = .{ 0, 0 },
    homogeneous: bool = true,
    float_bits: u16 = 0,
    float_count: u8 = 0,

    fn leaf(self: *NumericShape, offset: u64, size: u64, floating: bool) void {
        if (!floating) {
            self.homogeneous = false;
        } else {
            const bits: u16 = @intCast(size * 8);
            if (self.float_bits != 0 and self.float_bits != bits) self.homogeneous = false;
            self.float_bits = bits;
            self.float_count = @min(5, self.float_count + 1);
        }
        if (offset >= 16) return;
        const slot: usize = @intCast(offset / 8);
        const end: u16 = @intCast((offset % 8 + size) * 8);
        self.bits[slot] = @max(self.bits[slot], end);
        const class: WordClass = if (!floating) .integer else if (size == 8) .double else .float;
        if (floating and size == 4) self.float_mask[slot] |= @as(u8, 1) << @intCast(offset % 8 / 4);
        self.mergeClass(slot, class);
    }

    fn mergeClass(self: *NumericShape, slot: usize, other: ?WordClass) void {
        const previous = self.classes[slot];
        self.classes[slot] = if (previous == .integer or other == .integer)
            .integer
        else if (previous == .double or other == .double)
            .double
        else if (self.float_mask[slot] == 3)
            .float_pair
        else
            previous orelse other;
    }

    fn merge(self: *NumericShape, other: NumericShape, overlapping: bool) void {
        self.homogeneous = self.homogeneous and other.homogeneous;
        if (self.float_bits != 0 and other.float_bits != 0 and self.float_bits != other.float_bits) self.homogeneous = false;
        if (self.float_bits == 0) self.float_bits = other.float_bits;
        // Union alternatives share addresses. HFA size counts the largest
        // alternative, whereas sequential record members add their counts.
        self.float_count = if (overlapping) @max(self.float_count, other.float_count) else @min(5, self.float_count + other.float_count);
        for (0..2) |slot| {
            self.bits[slot] = @max(self.bits[slot], other.bits[slot]);
            self.float_mask[slot] |= other.float_mask[slot];
            self.mergeClass(slot, other.classes[slot]);
        }
    }
};

fn numericShape(graph: *const graph_mod.GlobalSemanticGraph, ty: graph_mod.GlobalTypeId, offset: u64, shape: *NumericShape, depth: usize) void {
    if (depth >= 32) return;
    if (isRawPointer(graph, ty)) {
        const layout = types.layoutOf(graph, ty) catch return;
        shape.leaf(offset, layout.size, false);
        return;
    }
    const semantic = graph.resolvedSemanticType(ty) orelse return;
    var fields: ?graph_mod.FieldRange = null;
    var overlapping = false;
    var array: ?struct { element: graph_mod.GlobalTypeId, length: u64 } = null;
    switch (semantic) {
        .builtin, .structural_choice => {
            const layout = types.layoutOf(graph, ty) catch return;
            shape.leaf(offset, layout.size, scalarIsFloating(graph, ty));
            return;
        },
        .declared => |id| {
            const declaration = graph.declaration(id);
            if (declaration.choice_variants != null) {
                const layout = types.layoutOf(graph, ty) catch return;
                shape.leaf(offset, layout.size, false);
                return;
            }
            fields = declaration.struct_fields;
            overlapping = declaration.struct_layout == .c_union;
        },
        .structural => |record| {
            fields = record.fields;
            overlapping = record.layout == .c_union;
        },
        .array => |value| array = .{ .element = value.element, .length = value.length },
        .generic => if (types.genericInstance(graph, ty)) |instance| switch (instance.shape) {
            .alias => |value| return numericShape(graph, value, offset, shape, depth + 1),
            .structure => |record| {
                fields = record.fields;
                overlapping = record.layout == .c_union;
            },
            .array => |value| array = .{ .element = value.element, .length = value.length },
            .choice => {
                const layout = types.layoutOf(graph, ty) catch return;
                shape.leaf(offset, layout.size, false);
                return;
            },
        },
        else => return,
    }
    if (fields) |range| {
        if (overlapping) {
            var combined: NumericShape = .{};
            for (graph.fields.items[range.start..][0..range.len]) |field| {
                var member: NumericShape = .{};
                numericShape(graph, field.ty, offset, &member, depth + 1);
                combined.merge(member, true);
            }
            shape.merge(combined, false);
            return;
        }
        var position = offset;
        for (graph.fields.items[range.start..][0..range.len]) |field| {
            const layout = types.layoutOf(graph, field.ty) catch return;
            position = std.mem.alignForward(u64, position, layout.alignment);
            numericShape(graph, field.ty, position, shape, depth + 1);
            position += layout.size;
        }
    } else if (array) |value| {
        const layout = types.layoutOf(graph, value.element) catch return;
        const stride = std.mem.alignForward(u64, layout.size, layout.alignment);
        // More than four elements cannot be an HFA. Inspect enough elements to
        // classify both SysV eightbytes without walking a large storage array.
        if (value.length > 4) shape.homogeneous = false;
        for (0..@min(value.length, 16)) |index| numericShape(graph, value.element, offset + index * stride, shape, depth + 1);
    }
}

fn classifyValue(graph: *const graph_mod.GlobalSemanticGraph, ty: graph_mod.GlobalTypeId, target: std.Target, result: bool) ?ValuePlan {
    if (supportsScalarValue(graph, ty, 0)) return .{ .ty = ty, .extension = scalarExtension(graph, ty, target) };
    // An array has C storage representation but is not itself a by-value C
    // parameter. Only explicit record identities enter composite classification.
    if (types.fields(graph, ty) == null or !supportsRecordTarget(target) or !recordStorage(graph, ty, 0)) return null;
    const layout = types.layoutOf(graph, ty) catch return null;
    if (layout.size == 0 or layout.size > std.math.maxInt(i64) or layout.alignment > 8) return null;
    var plan: ValuePlan = .{ .ty = ty, .size = layout.size, .alignment = @intCast(layout.alignment), .kind = .record_indirect };
    // Four doubles are the largest supported HFA. Larger records
    // always use memory, so avoid expanding nested arrays just to classify them.
    if (layout.size > 32) {
        plan.byval = isSysVX64(target) and !result;
        return plan;
    }
    var shape: NumericShape = .{};
    numericShape(graph, ty, 0, &shape, 0);
    if (!isSysVX64(target) and shape.homogeneous and shape.float_count > 0 and shape.float_count <= 4) {
        plan.kind = .record_words;
        plan.words = shape.float_count;
        plan.form = if (result) .split else .array;
        plan.stack_alignment = if (!result and !target.os.tag.isDarwin()) 8 else 0;
        for (0..plan.words) |index| {
            plan.word_bits[index] = shape.float_bits;
            plan.word_classes[index] = if (shape.float_bits == 32) .float else .double;
            plan.word_offsets[index] = @intCast(index * (shape.float_bits / 8));
        }
        return plan;
    }
    if (layout.size > 16) {
        plan.byval = isSysVX64(target) and !result;
        return plan;
    }
    plan.kind = .record_words;
    plan.words = if (layout.size > 8) 2 else 1;
    if (isSysVX64(target)) {
        plan.form = if (plan.words == 2) .split else .single;
        for (0..plan.words) |index| {
            plan.word_classes[index] = shape.classes[index] orelse .integer;
            plan.word_bits[index] = shape.bits[index];
        }
    } else {
        plan.form = if (plan.words == 2) .array else .single;
        plan.word_bits = .{ if (result and plan.words == 1) @intCast(layout.size * 8) else 64, if (plan.words == 2) 64 else 0, 0, 0 };
    }
    return plan;
}

/// Signature planning is shared by declarations, incoming bindings, outgoing
/// calls, and returns. SysV aggregate arguments reserve all required integer
/// and SSE registers together, or consume none when passed byval. This leaves
/// the remaining registers available to later scalar arguments. AAPCS64 indirect
/// arguments instead pass a pointer to a caller-owned copy.
pub fn classifyFunction(allocator: std.mem.Allocator, graph: *const graph_mod.GlobalSemanticGraph, function: graph_mod.Function, target: std.Target) !FunctionPlan {
    if (function.output.len > 1) return error.UnsupportedCABI;
    const output = if (function.output.len == 1) classifyValue(graph, graph.fields.items[function.output.start].ty, target, true) orelse return error.UnsupportedCABI else null;
    const sret = if (output) |value| value.kind == .record_indirect else false;
    const inputs = try allocator.alloc(ValuePlan, physicalInputCount(function));
    errdefer allocator.free(inputs);
    var cursor: u32 = if (sret) 1 else 0;
    var integer_registers: u32 = if (isSysVX64(target)) (if (sret) @as(u32, 5) else 6) else 8;
    var float_registers: u32 = 8;
    for (graph.fields.items[function.input.start..][0..inputs.len], inputs) |field, *plan| {
        plan.* = classifyValue(graph, field.ty, target, false) orelse return error.UnsupportedCABI;
        var integers: u32 = 0;
        var floats: u32 = 0;
        if (plan.kind == .record_words) for (plan.word_classes[0..plan.words]) |class| {
            if (class == .integer) integers += 1 else floats += 1;
        };
        if (isSysVX64(target) and plan.kind == .record_words and plan.words > 1 and (integer_registers < integers or float_registers < floats)) {
            plan.kind = .record_indirect;
            plan.byval = true;
        }
        plan.parameter_index = cursor;
        cursor += plan.parameterCount();
        const registers: u32 = switch (plan.kind) {
            .record_indirect => if (plan.byval) 0 else 1,
            .record_words => integers,
            .scalar => if (scalarIsFloating(graph, field.ty)) 0 else 1,
        };
        integer_registers -= @min(integer_registers, registers);
        const floating: u32 = if (plan.kind == .record_words) floats else if (plan.kind == .scalar and scalarIsFloating(graph, field.ty)) 1 else 0;
        float_registers -= @min(float_registers, floating);
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
        if (parameterExtension(left, index) != parameterExtension(right, index) or parameterStackAlignment(left, index) != parameterStackAlignment(right, index)) return false;
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

fn parameterStackAlignment(plan: FunctionPlan, index: usize) u32 {
    for (plan.inputs) |input| if (input.parameter_index == index) return input.stack_alignment;
    return 0;
}

test "C numeric record planning tracks SSE exhaustion and ARM homogeneous aggregates" {
    const allocator = std.testing.allocator;
    var graph: graph_mod.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);
    try graph.types.appendSlice(allocator, &.{
        .{ .builtin = .Float32 },
        .{ .builtin = .Float64 },
        .{ .structural = .{ .fields = .{ .start = 0, .len = 3 }, .layout = .c_struct } },
        .{ .structural = .{ .fields = .{ .start = 3, .len = 4 }, .layout = .c_struct } },
    });
    const field: graph_mod.Field = .{ .name = .{ .start = 0, .len = 0 }, .ty = @enumFromInt(0), .source = .{ .file_index = 0, .offset = 0 } };
    try graph.fields.appendNTimes(allocator, field, 3);
    var double = field;
    double.ty = @enumFromInt(1);
    try graph.fields.appendNTimes(allocator, double, 4);
    try graph.fields.appendNTimes(allocator, field, 7);
    var record = field;
    record.ty = @enumFromInt(2);
    try graph.fields.append(allocator, record);
    try graph.fields.append(allocator, field);
    try graph.fields.append(allocator, record);
    const function: graph_mod.Function = .{ .declaration = @enumFromInt(0), .input = .{ .start = 7, .len = 9 }, .output = .{ .start = 16, .len = 1 } };
    try graph.fields.append(allocator, field);
    try graph.fields.append(allocator, double);
    try graph.fields.appendNTimes(allocator, field, 5);
    try graph.types.appendSlice(allocator, &.{
        .{ .structural = .{ .fields = .{ .start = 17, .len = 2 }, .layout = .c_struct } },
        .{ .structural = .{ .fields = .{ .start = 19, .len = 5 }, .layout = .c_struct } },
    });
    try std.testing.expect(supportsRepresentation(&graph, @enumFromInt(2)));
    var target = @import("builtin").target;
    target.cpu.arch = .x86_64;
    target.os.tag = .linux;
    var sysv = try classifyFunction(allocator, &graph, function, target);
    defer sysv.deinit(allocator);
    try std.testing.expect(sysv.inputs[7].byval);
    try std.testing.expectEqual(WordClass.float_pair, sysv.result.?.word_classes[0]);
    try std.testing.expectEqual(WordClass.float, sysv.result.?.word_classes[1]);
    try std.testing.expectEqual(ValueKind.record_indirect, classifyValue(&graph, @enumFromInt(3), target, true).?.kind);
    target.cpu.arch = .aarch64;
    var arm = try classifyFunction(allocator, &graph, function, target);
    defer arm.deinit(allocator);
    try std.testing.expect(!arm.inputs[7].byval);
    try std.testing.expectEqual(@as(u8, 3), arm.inputs[7].words);
    try std.testing.expectEqual(@as(u8, 4), arm.inputs[7].word_offsets[1]);
    try std.testing.expectEqual(@as(u32, 8), arm.inputs[7].stack_alignment);
    const hfa = classifyValue(&graph, @enumFromInt(3), target, true).?;
    try std.testing.expectEqual(ValueKind.record_words, hfa.kind);
    try std.testing.expectEqual(@as(u8, 4), hfa.words);
    try std.testing.expectEqual(WordClass.double, hfa.word_classes[3]);
    const mixed_widths = classifyValue(&graph, @enumFromInt(4), target, false).?;
    try std.testing.expectEqual(WordClass.integer, mixed_widths.word_classes[0]);
    try std.testing.expectEqual(ValueKind.record_indirect, classifyValue(&graph, @enumFromInt(5), target, false).?.kind);
    target.os.tag = .macos;
    try std.testing.expectEqual(@as(u32, 0), classifyValue(&graph, @enumFromInt(2), target, false).?.stack_alignment);
}

test "C union classification merges shared storage and homogeneous member counts" {
    const allocator = std.testing.allocator;
    var graph: graph_mod.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);
    try graph.types.appendSlice(allocator, &.{
        .{ .builtin = .Float32 },
        .{ .array = .{ .element = @enumFromInt(0), .length = 3 } },
        .{ .structural = .{ .fields = .{ .start = 0, .len = 2 }, .layout = .c_union } },
        .{ .structural = .{ .fields = .{ .start = 2, .len = 2 }, .layout = .c_union } },
        .{ .structural = .{ .fields = .{ .start = 4, .len = 2 }, .layout = .c_struct } },
    });
    const field: graph_mod.Field = .{ .name = .{ .start = 0, .len = 0 }, .ty = @enumFromInt(0), .source = .{ .file_index = 0, .offset = 0 } };
    try graph.fields.appendNTimes(allocator, field, 3);
    var array = field;
    array.ty = @enumFromInt(1);
    try graph.fields.append(allocator, array);
    var nested = field;
    nested.ty = @enumFromInt(3);
    try graph.fields.append(allocator, nested);
    try graph.fields.append(allocator, field);
    var target = @import("builtin").target;
    target.cpu.arch = .x86_64;
    target.os.tag = .linux;
    const single = classifyValue(&graph, @enumFromInt(2), target, false).?;
    try std.testing.expectEqual(WordClass.float, single.word_classes[0]);
    const floats = classifyValue(&graph, @enumFromInt(3), target, false).?;
    try std.testing.expectEqual(WordClass.float_pair, floats.word_classes[0]);
    try std.testing.expectEqual(WordClass.float, floats.word_classes[1]);
    target.cpu.arch = .aarch64;
    const hfa = classifyValue(&graph, @enumFromInt(3), target, false).?;
    try std.testing.expectEqual(@as(u8, 3), hfa.words);
    const combined = classifyValue(&graph, @enumFromInt(4), target, false).?;
    try std.testing.expectEqual(@as(u8, 4), combined.words);
}
