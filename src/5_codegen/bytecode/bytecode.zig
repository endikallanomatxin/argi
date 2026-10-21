const std = @import("std");
const g = @import("../../4_semantics/global/graph.zig");
const types = @import("../../4_semantics/global/types.zig");
const p = @import("../../4_semantics/primitives/schema.zig");

pub const Slot = u32;
// Internal write access cannot be copied into language values or passed/returned
// as a safe reference. A function captures it before evaluating a store's RHS.
pub const Destination = u32;
pub const Type = g.GlobalTypeId;
pub const LoadInterpretation = enum(u8) { value, erased, signed_byte, unsigned_byte };

pub fn loadInterpretation(graph: *const g.GlobalSemanticGraph, ty: Type) LoadInterpretation {
    if (types.isBuiltin(graph, ty, .Any)) return .erased;
    if (integerBounds(graph, ty)) |bounds| {
        if (bounds.maximum - bounds.minimum == 255) return if (bounds.minimum < 0) .signed_byte else .unsigned_byte;
    }
    return .value;
}
// Checked operation interpretation, independent of semantic graph identities.
// One byte avoids retaining full integer bounds in every instruction.
pub const ScalarKind = enum(u8) {
    unresolved,
    i8,
    u8,
    i16,
    u16,
    i32,
    u32,
    i64,
    u64,
    f16,
    f32,
    f64,
    boolean,
    choice,

    pub fn bounds(self: ScalarKind) ?p.IntegerRange {
        return switch (self) {
            .i8 => p.integerRangeForWidth(8, true),
            .u8 => p.integerRangeForWidth(8, false),
            .i16 => p.integerRangeForWidth(16, true),
            .u16 => p.integerRangeForWidth(16, false),
            .i32 => p.integerRangeForWidth(32, true),
            .u32 => p.integerRangeForWidth(32, false),
            .i64 => p.integerRangeForWidth(64, true),
            .u64 => p.integerRangeForWidth(64, false),
            else => null,
        };
    }

    pub fn floating(self: ScalarKind) bool {
        return self == .f16 or self == .f32 or self == .f64;
    }
};

pub fn scalarKind(graph: *const g.GlobalSemanticGraph, ty: Type) ScalarKind {
    if (integerBounds(graph, ty)) |range| {
        inline for ([_]ScalarKind{ .i8, .u8, .i16, .u16, .i32, .u32, .i64, .u64 }) |kind| {
            const candidate = kind.bounds().?;
            if (candidate.minimum == range.minimum and candidate.maximum == range.maximum) return kind;
        }
    }
    if (types.isBuiltin(graph, ty, .Float16)) return .f16;
    if (types.isBuiltin(graph, ty, .Float32)) return .f32;
    if (types.isBuiltin(graph, ty, .Float64)) return .f64;
    if (types.isBuiltin(graph, ty, .Bool)) return .boolean;
    if (types.variants(graph, ty) != null) return .choice;
    return .unresolved;
}
pub const SessionNamespace = enum(u64) { _ };
// Runtime storage is keyed by durable graph bindings inside one compilation
// namespace. Each binding has a value slot followed only by cleanup flag slots.
pub const SessionBinding = struct { binding: g.GlobalBindingId, slots: []const Type, cleanup: []const Cleanup = &.{} };
// The compilation owner issues the namespace and preserves binding/type
// identities and layouts across revisions. It must never stamp independently
// rebuilt graphs with the same namespace. This metadata is immutable like code.
pub const Session = struct { namespace: SessionNamespace, bindings: []const SessionBinding };
pub const Value = @import("value.zig").Value;
// A place starts in local storage and can follow checked safe references.
// Index operands are snapshots evaluated by lowering in source order.
// Representation descriptors are finalized by lowering and checked by verify;
// runtime traversal needs neither semantic type lookup nor variant resolution.
pub const Projection = union(enum) {
    field: u32,
    element: struct { slot: Slot, kind: ScalarKind = .unresolved },
    variant: struct { identity: g.GlobalVariantId, ordinal: u32 = std.math.maxInt(u32) },
    dereference,
};
pub const Place = struct {
    // Root indexes local slots, the typed session table, or a global binding ID.
    // Dynamic index operands always name local slots in the executing frame.
    root: u32,
    region: enum { local, session, global } = .local,
    path: []const Projection,
};

// Compiler-selected cleanup state is attached to storage, not copied values or
// reference slots. Paths are concrete layout projections, never dereferences.
// Entries are sorted by root and path; each subtree is contiguous for bounded
// lookup and updates. Flag cells start false independently of value occupancy.
pub const Cleanup = struct {
    root: Slot,
    path: []const @import("value.zig").Projection,
    flag: Slot,
    // A choice can retain its discriminant after losing part of its payload.
    presence: ?Slot = null,
};
pub const CleanupAccess = @import("../cleanup_plan.zig").Access;

pub fn cleanupOrder(a: Cleanup, c: Cleanup) std.math.Order {
    const root = std.math.order(a.root, c.root);
    if (root != .eq) return root;
    for (a.path[0..@min(a.path.len, c.path.len)], c.path[0..@min(a.path.len, c.path.len)]) |left, right| {
        const tag = std.math.order(@intFromEnum(left), @intFromEnum(right));
        if (tag != .eq) return tag;
        const order = switch (left) {
            .field => |index| std.math.order(index, right.field),
            .element => |index| std.math.order(index, right.element),
            .variant => |index| std.math.order(index, right.variant),
        };
        if (order != .eq) return order;
    }
    return std.math.order(a.path.len, c.path.len);
}

pub fn cleanupContains(parent: Cleanup, child: Cleanup) bool {
    if (parent.root != child.root or parent.path.len > child.path.len) return false;
    for (parent.path, child.path[0..parent.path.len]) |left, right| if (!std.meta.eql(left, right)) return false;
    return true;
}

// Erasure is lowered once into code/ABI data. The executor never consults
// conformance registries or declaration-level safety metadata.
pub const VirtualTable = struct {
    virtual_type: Type,
    concrete_type: Type,
    methods: []const struct { function: g.GlobalFunctionId, receiver_input_index: u32 },
};
pub const VirtualSignature = struct {
    virtual_type: Type,
    inputs: []const Type,
    outputs: []const Type,
    receiver_input_index: u32,
    receiver_permission: p.PointerMutability,
    method_index: u32,
    method_count: u32,
};

// Keep infrequent call metadata behind one immutable descriptor so virtual
// calls do not widen the tagged payload of every bytecode instruction.
pub const VirtualInvocation = struct {
    outputs: []const Slot,
    args: []const Slot,
    handle: Slot,
    signature: VirtualSignature,
};

// Immutable diagnostic coordinates. Context registration assigns durable IDs;
// descriptors belong to the same retained compilation unit as their code.
pub const TraceLocation = struct {
    path: []const u8,
    offset: u32,
    line: u32,
    column: u32,
    source_line: []const u8,
};

pub const Instruction = struct {
    source: p.SourceRef,
    op: union(enum) {
        reserve_storage: struct { dst: Slot, layout: @import("storage_layout.zig").Layout, reset: bool = false },
        borrow_storage: struct { dst: Slot, place: Place, permission: p.PointerMutability },
        constant: struct { dst: Slot, value: Value },
        resolve_location: struct { dst: Slot, id: Slot },
        trace_location: struct { dst: Slot, location: *const TraceLocation },
        static_bytes: struct { dst: Slot, bytes: []const u8 },
        acquired_reference: struct { dst: Slot, address: Slot, layout: *const @import("numeric_layout.zig").Layout, permission: p.PointerMutability, endian: std.builtin.Endian },
        erase_reference: struct { dst: Slot, src: Slot },
        numeric_bytes: struct { dst: Slot, src: Slot, layout: *const @import("numeric_layout.zig").Layout, permission: p.PointerMutability, endian: std.builtin.Endian },
        offset_reference: struct { dst: Slot, src: Slot, elements: Slot },
        virtualize: struct { dst: Slot, receiver: Slot, table: *const VirtualTable },
        virtual_call: *const VirtualInvocation,
        copy: struct { dst: Slot, src: Slot },
        session_declare: struct { binding: u32, layout: ?@import("storage_layout.zig").Layout = null },
        session_initialize: struct { binding: u32, value: Slot, reinitialize: bool = false },
        readonly: struct { dst: Slot, src: Slot },
        binary: struct { dst: Slot, left: Slot, right: Slot, operator: p.BinaryOperator, kind: ScalarKind = .unresolved },
        compare: struct { dst: Slot, left: Slot, right: Slot, operator: p.ComparisonOperator, kind: ScalarKind = .unresolved },
        record: struct { dst: Slot, fields: []const Slot },
        field: struct { dst: Slot, base: Slot, index: u32 },
        array: struct { dst: Slot, elements: []const Slot },
        index: struct { dst: Slot, base: Slot, index: Slot, kind: ScalarKind = .unresolved },
        choice: struct { dst: Slot, variant: g.GlobalVariantId, ordinal: u32 = std.math.maxInt(u32), payload: ?Slot },
        payload: struct { dst: Slot, src: Slot, variant: g.GlobalVariantId, ordinal: u32 = std.math.maxInt(u32) },
        is_variant: struct { dst: Slot, src: Slot, variant: g.GlobalVariantId, ordinal: u32 = std.math.maxInt(u32), invert: bool },
        branch_storage_variant: struct { place: Place, variant: g.GlobalVariantId, ordinal: u32, yes: u32, no: u32 },
        branch_variant: struct { src: Slot, variant: g.GlobalVariantId, ordinal: u32 = std.math.maxInt(u32), yes: u32, no: u32 },
        borrow: struct { dst: Slot, place: Place, permission: p.PointerMutability },
        load: struct { dst: Slot, place: Place, interpretation: LoadInterpretation = .value },
        check_place: Place,
        // Initialization activation and old-value destruction are independent:
        // scalar fields can carry initialization flags without owning resources.
        capture_write: struct { dst: Destination, place: Place, activate_cleanup: bool = false, require_cleanup: bool = true },
        // Lowering emits these three consecutively after RHS preparation.
        // Activation consumes the captured destination; store changes only data.
        check_write_cleanup: Destination,
        store: struct { destination: Destination, value: Slot },
        activate_write_cleanup: Destination,
        cleanup_test: struct { dst: Slot, place: Place },
        branch_cleanup: struct { place: Place, yes: u32, no: u32, access: CleanupAccess = .complete },
        cleanup_set: struct { place: Place, enabled: bool },
        memory_call: struct { outputs: []const Slot, function: g.GlobalFunctionId, operation: @import("memory_boundary.zig").Operation, args: []const Slot },
        host_call: struct { outputs: []const Slot, function: u32, args: []const Slot },
        call: struct { outputs: []const Slot, function: g.GlobalFunctionId, args: []const Slot },
        branch: struct { condition: Slot, yes: u32, no: u32 },
        jump: u32,
        ret: []const Slot,
        abort_,
        trap: enum { runtime_storage },
    },
};
pub const Function = struct {
    slots: []const Type,
    inputs: []const Slot,
    outputs: []const Slot,
    code: []const Instruction,
    cleanup: []const Cleanup = &.{},
    write_destinations: []const Type = &.{},
};

// Bytecode borrows the finalized graph's type and function identities. Its owner
// must retain that graph; execution never calls semantic resolution.
// Program is unverified data. Vm.init validates it once; instructions, function
// tables and graph metadata must then remain unchanged until Vm.deinit.
// A shared context can retain virtual code after Vm.deinit. Its owner must
// retain those backing tables and graphs until context reset or destruction.
pub const Global = struct { binding: g.GlobalBindingId, ty: Type, initializer: Function };

pub const Program = struct {
    host_functions: []const g.GlobalFunctionId = &.{},
    globals: []const Global = &.{},
    graph: *const g.GlobalSemanticGraph,
    functions: []const ?Function,
    expression: ?*const Function = null,
    session: ?Session = null,
};

pub fn integerBounds(graph: *const g.GlobalSemanticGraph, ty: Type) ?p.IntegerRange {
    const semantic = graph.semanticType(ty);
    if (semantic != .builtin) return null;
    return p.integerRange(semantic.builtin, graph.target.stdTarget());
}

pub fn floatType(graph: *const g.GlobalSemanticGraph, ty: Type) bool {
    return types.isBuiltin(graph, ty, .Float16) or types.isBuiltin(graph, ty, .Float32) or types.isBuiltin(graph, ty, .Float64);
}

pub fn supportedType(graph: *const g.GlobalSemanticGraph, ty: Type, depth: usize) bool {
    if (depth > 64 or @intFromEnum(ty) >= graph.types.items.len) return false;
    if (integerBounds(graph, ty) != null or floatType(graph, ty)) return true;
    const semantic = graph.semanticType(ty);
    if (semantic == .builtin) return semantic.builtin == .Bool or semantic.builtin == .Void or semantic.builtin == .Any;
    if (semantic == .virtual) return true;
    if (semantic == .pointer) return types.isBuiltin(graph, semantic.pointer.child, .Any) or supportedType(graph, semantic.pointer.child, depth + 1);
    if (types.arrayElement(graph, ty)) |element| return supportedType(graph, element, depth + 1);
    if (types.variants(graph, ty)) |variants| {
        if (!regularChoice(graph, ty, depth)) return false;
        for (graph.variants.items[variants.start..][0..variants.len]) |variant| if (variant.payload_type) |payload| {
            if (!supportedType(graph, payload, depth + 1)) return false;
        };
        return true;
    }
    const fields = types.fields(graph, ty) orelse return false;
    for (graph.fields.items[fields.start..][0..fields.len]) |field| if (!supportedType(graph, field.ty, depth + 1)) return false;
    return true;
}

fn regularChoice(graph: *const g.GlobalSemanticGraph, ty: Type, depth: usize) bool {
    if (depth > 64) return false;
    return switch (graph.semanticType(ty)) {
        .structural_choice => |shape| shape.layout == .regular,
        .inferred_choice => true,
        .declared => |id| graph.declaration(id).choice_layout == .regular,
        .generic => if (types.genericInstance(graph, ty)) |instance| switch (instance.shape) {
            .choice => |shape| shape.layout == .regular,
            .alias => |child| regularChoice(graph, child, depth + 1),
            else => false,
        } else false,
        else => false,
    };
}

pub fn valueFits(graph: *const g.GlobalSemanticGraph, ty: Type, value: Value) bool {
    return switch (value) {
        .integer => |n| if (integerBounds(graph, ty)) |range| n <= range.maximum - range.minimum else false,
        .float16 => types.isBuiltin(graph, ty, .Float16),
        .float32 => types.isBuiltin(graph, ty, .Float32),
        .float64 => types.isBuiltin(graph, ty, .Float64),
        .boolean => graph.semanticType(ty) == .builtin and graph.semanticType(ty).builtin == .Bool,
        .unit => graph.semanticType(ty) == .builtin and graph.semanticType(ty).builtin == .Void,
        .erased => types.isBuiltin(graph, ty, .Any),
        .array => |values| blk: {
            const element = types.arrayElement(graph, ty) orelse break :blk false;
            if (types.arrayLength(graph, ty).? != values.len) break :blk false;
            for (values) |v| if (!valueFits(graph, element, v)) break :blk false;
            break :blk true;
        },
        // Reference values are created by borrow instructions, never constants
        // or external inputs. Their shape and access are checked separately.
        .reference, .virtual_ => false,
        .choice => |choice| blk: {
            const identity = variantIdentity(graph, ty, choice.variant) catch break :blk false;
            const variant = graph.variants.items[@intFromEnum(identity)];
            if (variant.payload_type) |payload_type| {
                const payload = choice.payload orelse break :blk false;
                break :blk valueFits(graph, payload_type, payload.*);
            }
            break :blk choice.payload == null;
        },
        .record => |values| blk: {
            const fields = types.fields(graph, ty) orelse break :blk false;
            if (fields.len != values.len) break :blk false;
            for (graph.fields.items[fields.start..][0..fields.len], values) |field, v| if (!valueFits(graph, field.ty, v)) break :blk false;
            break :blk true;
        },
    };
}

pub const verify = @import("verify.zig").verify;

pub fn choiceVariant(graph: *const g.GlobalSemanticGraph, ty: Type, id: g.GlobalVariantId) !g.ChoiceVariant {
    const range = types.variants(graph, ty) orelse return error.InvalidBytecode;
    const raw = @intFromEnum(id);
    if (raw < range.start or raw - range.start >= range.len) return error.InvalidBytecode;
    return graph.variants.items[raw];
}

/// Semantic identities select and verify operations; runtime discriminants are
/// positions within an already-checked choice representation.
pub fn variantOrdinal(graph: *const g.GlobalSemanticGraph, ty: Type, id: g.GlobalVariantId) !u32 {
    _ = try choiceVariant(graph, ty, id);
    return @intFromEnum(id) - (types.variants(graph, ty) orelse return error.InvalidBytecode).start;
}

pub fn variantIdentity(graph: *const g.GlobalSemanticGraph, ty: Type, ordinal: u32) !g.GlobalVariantId {
    const range = types.variants(graph, ty) orelse return error.InvalidBytecode;
    if (ordinal >= range.len) return error.InvalidBytecode;
    return @enumFromInt(range.start + ordinal);
}

// Resolve representation descriptors while semantic types are available.
// The executor traverses the finalized path without consulting this graph.
pub fn finalizePath(graph: *const g.GlobalSemanticGraph, root_type: Type, path: []const Projection, out: []Projection) !void {
    if (path.len != out.len) return error.InvalidBytecode;
    var ty = root_type;
    for (path, out) |part, *runtime| {
        runtime.* = part;
        switch (part) {
            .field => |index| {
                const fields = types.fields(graph, ty) orelse return error.InvalidBytecode;
                if (index >= fields.len) return error.InvalidBytecode;
                ty = graph.fields.items[fields.start + index].ty;
            },
            .variant => |identity| {
                runtime.* = .{ .variant = .{ .identity = identity.identity, .ordinal = try variantOrdinal(graph, ty, identity.identity) } };
                ty = (try choiceVariant(graph, ty, identity.identity)).payload_type orelse return error.InvalidBytecode;
            },
            .element => ty = types.arrayElement(graph, ty) orelse return error.InvalidBytecode,
            .dereference => {
                const pointer = graph.semanticType(ty);
                if (pointer != .pointer) return error.InvalidBytecode;
                ty = pointer.pointer.child;
            },
        }
    }
}

pub fn runtimeCleanupPath(allocator: std.mem.Allocator, graph: *const g.GlobalSemanticGraph, ty: Type, path: []const Projection) ![]const @import("value.zig").Projection {
    var normalized: [64]Projection = undefined;
    if (path.len > normalized.len) return error.InvalidBytecode;
    try finalizePath(graph, ty, path, normalized[0..path.len]);
    const result = try allocator.alloc(@import("value.zig").Projection, path.len);
    errdefer allocator.free(result);
    for (normalized[0..path.len], result) |part, *out| out.* = switch (part) {
        .field => |index| .{ .field = index },
        .variant => |ordinal| .{ .variant = ordinal.ordinal },
        else => return error.InvalidBytecode,
    };
    return result;
}
