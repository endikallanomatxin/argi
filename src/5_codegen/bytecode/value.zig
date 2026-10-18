const p = @import("../../4_semantics/primitives/schema.zig");

pub const FrameId = enum(u32) { _ };
pub const ContextId = enum(u64) { _ };
pub const Projection = union(enum) { field: u32, element: usize, variant: u32 };

// An interpreter address contains no host pointer. Indices are captured when
// borrowing. Context identities are never reused, including across VM resets.
pub const Reference = struct {
    context: ContextId,
    frame: FrameId,
    root: u32,
    path: []const Projection,
    mutability: p.PointerMutability,
};

// Runtime erasure retains one immutable code unit selected at construction.
// The context owns this descriptor; its compiler owner retains the code/graph.
pub const Virtual = struct {
    receiver: Reference,
    program: @import("bytecode.zig").Program,
    table: *const @import("bytecode.zig").VirtualTable,
};

pub const Value = union(enum) {
    integer: i128,
    boolean: bool,
    unit,
    record: []const Value,
    array: []const Value,
    reference: Reference,
    virtual_: *const Virtual,
    choice: struct { variant: u32, payload: ?*const Value },
};
