const p = @import("../../4_semantics/primitives/schema.zig");

pub const FrameId = enum(u32) { _ };
pub const Projection = union(enum) { field: u32, element: usize };

// An interpreter address contains no host pointer. Indices are captured when
// borrowing, and frame identities are never reused within an execution.
pub const Reference = struct {
    frame: FrameId,
    root: u32,
    path: []const Projection,
    mutability: p.PointerMutability,
};

pub const Value = union(enum) {
    integer: i128,
    boolean: bool,
    unit,
    record: []const Value,
    array: []const Value,
    reference: Reference,
};
