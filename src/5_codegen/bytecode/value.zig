const p = @import("../../4_semantics/primitives/schema.zig");

pub const FrameId = enum(u32) { _ };
pub const ContextId = enum(u64) { _ };
// Variant projections use the same representation positions as runtime values.
pub const Projection = union(enum) { field: u32, element: usize, variant: u32 };

// An interpreter address contains no host pointer. Indices are captured when
// borrowing. Context identities are never reused, including across VM resets.
pub const Reference = struct {
    context: ContextId,
    frame: FrameId,
    root: u32,
    path: []const Projection,
    mutability: p.PointerMutability,
    byte_view: ?struct { layout: *const @import("numeric_layout.zig").Layout, offset: usize, endian: @import("std").builtin.Endian } = null,
};

// Runtime erasure retains one immutable code unit selected at construction.
// The context owns this descriptor; its compiler owner retains the code/graph.
pub const Virtual = struct {
    receiver: Reference,
    program: @import("bytecode.zig").Program,
    table: *const @import("bytecode.zig").VirtualTable,
};

pub const Value = union(enum) {
    // Canonical low bits. Signedness and width belong to the checked slot type.
    integer: u64,
    float16: f16,
    float32: f32,
    float64: f64,
    boolean: bool,
    unit,
    // An observed erased value carries no recoverable representation or loan.
    erased,
    record: []const Value,
    array: []const Value,
    reference: Reference,
    virtual_: *const Virtual,
    // Position within the checked representation, never a GlobalVariantId.
    choice: struct { variant: u32, payload: ?*const Value },
};
