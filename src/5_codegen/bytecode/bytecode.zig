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
    if (isBuiltinRepresentation(graph, ty, .Any)) return .erased;
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
    if (isBuiltinRepresentation(graph, ty, .Float16)) return .f16;
    if (isBuiltinRepresentation(graph, ty, .Float32)) return .f32;
    if (isBuiltinRepresentation(graph, ty, .Float64)) return .f64;
    if (isBuiltinRepresentation(graph, ty, .Bool)) return .boolean;
    if (types.variants(graph, ty) != null) return .choice;
    return .unresolved;
}
pub const SessionNamespace = enum(u64) { _ };
// Runtime storage is keyed by durable graph bindings inside one compilation
// namespace. Cleanup flags have separate compact storage, never value slots.
pub const SessionBinding = struct { binding: g.GlobalBindingId, ty: Type, cleanup: []const Cleanup = &.{} };
// The compilation owner issues the namespace and preserves binding/type
// identities and layouts across revisions. It must never stamp independently
// rebuilt graphs with the same namespace. Binding indices are unit-local;
// persistent storage is keyed by binding IDs. Published metadata is immutable.
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

// One immutable shape per owner, shared by every projection and value of that
// type. Flags occupy the layout's preorder range in the frame's byte buffer.
pub const Cleanup = struct {
    root: Slot,
    offset: usize = 0,
    layout: *const @import("../cleanup_layout.zig").Layout = &.{},
};
pub const CleanupAccess = @import("../cleanup_plan.zig").Access;

pub fn cleanupFlagCount(cleanup: []const Cleanup) !usize {
    var count: usize = 0;
    for (cleanup) |entry| {
        if (entry.offset != count or entry.layout.count == 0) return error.InvalidCleanupLayout;
        count = try std.math.add(usize, count, entry.layout.count);
    }
    return count;
}

// Erasure is lowered once into code/ABI data. The executor never consults
// conformance registries or declaration-level safety metadata.
pub const VirtualTable = struct {
    virtual_type: Type,
    concrete_type: Type,
    methods: []const struct { function: g.GlobalFunctionId, receiver_input_index: u32, receiver_permission: p.PointerMutability },
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

// Acquisition descriptors grow independently of the hot instruction union.
// Lowering owns them immutably alongside layouts and selected cleanup plans.
pub const AcquiredReference = struct { dst: Slot, address: Slot, receipt: ?struct { value: Slot, layout: *const @import("acquired_receipt.zig").Layout } = null, logical_index: ?struct { value: Slot, some_ordinal: u32 } = null, layout: *const @import("numeric_layout.zig").Layout, cleanup: ?*const @import("../cleanup_layout.zig").Layout = null, permission: p.PointerMutability, endian: std.builtin.Endian };

pub const Instruction = struct {
    source: p.SourceRef,
    op: union(enum) {
        prepare_acquired: struct { dst: Slot, receipt: Slot, layout: *const @import("../allocation_metadata.zig").Reservation },
        reserve_storage: struct { dst: Slot, layout: @import("storage_layout.zig").Layout, reset: bool = false },
        borrow_storage: struct { dst: Slot, place: Place, permission: p.PointerMutability },
        constant: struct { dst: Slot, value: Value },
        resolve_location: struct { dst: Slot, id: Slot },
        trace_location: struct { dst: Slot, location: *const TraceLocation },
        static_bytes: struct { dst: Slot, bytes: []const u8 },
        acquired_reference: *const AcquiredReference,
        erase_reference: struct { dst: Slot, src: Slot },
        numeric_bytes: struct { dst: Slot, src: Slot, layout: *const @import("numeric_layout.zig").Layout, permission: p.PointerMutability, endian: std.builtin.Endian },
        offset_reference: struct { dst: Slot, src: Slot, elements: Slot },
        virtualize: struct { dst: Slot, receiver: Slot, table: *const VirtualTable },
        virtual_call: *const VirtualInvocation,
        copy: struct { dst: Slot, src: Slot },
        session_declare: struct { binding: u32, layout: ?@import("storage_layout.zig").Layout = null },
        session_initialize: struct { binding: u32, value: Slot, reinitialize: bool = false },
        readonly: struct { dst: Slot, src: Slot },
        integer_cast: struct { dst: Slot, src: Slot, from: ScalarKind, to: ScalarKind },
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
        // Selected relocation supplies the source/live and destination/vacant
        // proof. Runtime flags describe existing obligations, not permission.
        relocate: struct { source: Slot, destination: Slot, function: g.GlobalFunctionId },
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
// tables must then remain unchanged until Vm.deinit. Graph pools may grow,
// but referenced semantic identities must preserve their established meaning.
// A shared context can retain virtual code after Vm.deinit. Its owner must
// retain those backing tables and graphs until context reset or destruction.
pub const Global = struct { binding: g.GlobalBindingId, ty: Type, initializer: Function };

pub const HostFunction = struct {
    function: g.GlobalFunctionId,
    source: p.SourceRef,
    symbol: []const u8,
    inputs: []const p.IntegerRange,
    outputs: []const p.IntegerRange,
};

pub const Verified = @import("verify.zig").Verified;

pub const FunctionEntry = struct {
    // Imported bodies execute against this previously verified unit.
    origin: ?*const Verified = null,
    // Zero denotes standalone lowering without retained proofs; maxInt forbids reuse.
    safety_revision: u64 = 0,
    id: g.GlobalFunctionId,
    body: *const Function,

    pub fn lessThan(_: void, a: FunctionEntry, other: FunctionEntry) bool {
        return @intFromEnum(a.id) < @intFromEnum(other.id);
    }
};

pub const Program = struct {
    host_functions: []const HostFunction = &.{},
    globals: []const Global = &.{},
    graph: *const g.GlobalSemanticGraph,
    // Strictly ordered by stable semantic ID. Only compiled bodies occupy space.
    functions: []const FunctionEntry,
    expression: ?*const Function = null,
    session: ?Session = null,

    /// Dependency-first imported units, without copying their tables. The
    /// caller owns the returned slice; verified origins form an immutable DAG.
    pub fn dependencies(self: *const Program, allocator: std.mem.Allocator) ![]const *const Program {
        const Walk = struct { program: *const Program, next: usize = 0 };
        var stack: std.ArrayList(Walk) = .empty;
        defer stack.deinit(allocator);
        var visited: std.AutoHashMapUnmanaged(*const Verified, void) = .empty;
        defer visited.deinit(allocator);
        var result: std.ArrayList(*const Program) = .empty;
        errdefer result.deinit(allocator);
        try stack.append(allocator, .{ .program = self });
        while (stack.items.len != 0) {
            const current = &stack.items[stack.items.len - 1];
            if (current.next < current.program.functions.len) {
                const entry = current.program.functions[current.next];
                current.next += 1;
                if (entry.origin) |origin| {
                    const seen = try visited.getOrPut(allocator, origin);
                    if (!seen.found_existing) try stack.append(allocator, .{ .program = origin.program() });
                }
            } else {
                const completed = stack.pop().?;
                if (completed.program != self) try result.append(allocator, completed.program);
            }
        }
        return result.toOwnedSlice(allocator);
    }

    pub const Callee = struct { program: *const Program, body: *const Function };

    pub fn resolve(self: *const Program, id: g.GlobalFunctionId) ?Callee {
        const entry = self.functionEntry(id) orelse return null;
        return .{ .program = if (entry.origin) |origin| origin.program() else self, .body = entry.body };
    }

    pub fn function(self: Program, id: g.GlobalFunctionId) ?*const Function {
        return if (self.functionEntry(id)) |entry| entry.body else null;
    }

    pub fn functionEntry(self: Program, id: g.GlobalFunctionId) ?FunctionEntry {
        var first: usize = 0;
        var end = self.functions.len;
        while (first < end) {
            const middle = first + (end - first) / 2;
            const entry = self.functions[middle];
            if (entry.id == id) return entry;
            if (@intFromEnum(entry.id) < @intFromEnum(id)) first = middle + 1 else end = middle;
        }
        return null;
    }
};

pub fn integerBounds(graph: *const g.GlobalSemanticGraph, ty: Type) ?p.IntegerRange {
    const semantic = types.representation(graph, ty) orelse return null;
    if (semantic != .builtin) return null;
    return p.integerRange(semantic.builtin, graph.target.stdTarget());
}

// Representation queries do not change the nominal identity checked by slots,
// calls and selected contract evidence.
pub fn isBuiltinRepresentation(graph: *const g.GlobalSemanticGraph, ty: Type, builtin: p.BuiltinType) bool {
    const semantic = types.representation(graph, ty) orelse return false;
    return semantic == .builtin and semantic.builtin == builtin;
}

pub fn floatType(graph: *const g.GlobalSemanticGraph, ty: Type) bool {
    return isBuiltinRepresentation(graph, ty, .Float16) or isBuiltinRepresentation(graph, ty, .Float32) or isBuiltinRepresentation(graph, ty, .Float64);
}

pub fn supportedType(graph: *const g.GlobalSemanticGraph, ty: Type, depth: usize) bool {
    if (depth > 64 or @intFromEnum(ty) >= graph.types.items.len) return false;
    if (integerBounds(graph, ty) != null or floatType(graph, ty)) return true;
    const semantic = types.representation(graph, ty) orelse return false;
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
    return switch (types.representation(graph, ty) orelse return false) {
        .structural_choice => |shape| shape.layout == .regular,
        .inferred_choice => true,
        .nominal => |id| graph.typeDefinition(id).choice_layout == .regular,
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
        .float16 => isBuiltinRepresentation(graph, ty, .Float16),
        .float32 => isBuiltinRepresentation(graph, ty, .Float32),
        .float64 => isBuiltinRepresentation(graph, ty, .Float64),
        .boolean => isBuiltinRepresentation(graph, ty, .Bool),
        .unit => isBuiltinRepresentation(graph, ty, .Void),
        .erased => isBuiltinRepresentation(graph, ty, .Any),
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
