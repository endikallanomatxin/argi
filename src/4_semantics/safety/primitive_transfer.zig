const primitives = @import("../primitives/schema.zig");

/// Primitive semantics shared by concrete checking and symbolic summary
/// inference. Each pass interprets these operations in its own state model;
/// adding a primitive requires deciding all three effects in one place.
pub const Transfer = struct {
    value: Value,
    input: Input = .none,
    opaque_state: Opaque = .none,

    pub const Value = enum {
        empty,
        raw_storage,
        fresh_reference,
        inherited_reference,
        inherited_storage,
        allocation,
        reference_copy,
        restrict_reference,
        depend_on,
        relocate,
        opaque_move,
        opaque_move_out,
        opaque_relocate,
        opaque_mark_empty,
        opaque_drop,
    };

    pub const Input = enum { none, consume_opaque_owner, relocate, ignore };
    pub const Opaque = enum { none, clear_empty, store_hidden, mark_empty };
};

pub fn forPrimitive(primitive: primitives.SafetyPrimitive) Transfer {
    return switch (primitive) {
        .none => .{ .value = .empty },
        .raw_allocated_storage => .{ .value = .raw_storage },
        .establish_fresh_reference => .{ .value = .fresh_reference },
        .establish_inherited_reference => .{ .value = .inherited_reference },
        .establish_inherited_storage => .{ .value = .inherited_storage },
        .establish_allocation => .{ .value = .allocation },
        .reference_offset, .mutable_reference_offset, .reinterpret_reference, .mutable_reinterpret_reference, .read_reference => .{ .value = .reference_copy },
        .restrict_reference => .{ .value = .restrict_reference },
        .depend_on => .{ .value = .depend_on },
        .relocate => .{ .value = .relocate, .input = .relocate },
        .trusted_opaque_move => .{
            .value = .opaque_move,
            .input = .consume_opaque_owner,
            .opaque_state = .clear_empty,
        },
        .trusted_opaque_move_in => .{
            .value = .opaque_move,
            .input = .consume_opaque_owner,
            .opaque_state = .store_hidden,
        },
        .trusted_opaque_move_out => .{ .value = .opaque_move_out },
        .trusted_opaque_relocate => .{ .value = .opaque_relocate, .input = .ignore },
        .trusted_opaque_drop => .{ .value = .opaque_drop },
        .trusted_opaque_mark_empty => .{ .value = .opaque_mark_empty, .opaque_state = .mark_empty },
    };
}

/// A move with two arguments discovers its storage domain from the owner.
/// The three-argument form names the storage domain explicitly.
pub const OpaqueMoveOperands = struct {
    owner: usize,
    storage: ?usize,
};

pub fn opaqueMoveOperands(argument_count: usize) ?OpaqueMoveOperands {
    return switch (argument_count) {
        2 => .{ .owner = 1, .storage = null },
        3 => .{ .owner = 2, .storage = 0 },
        else => null,
    };
}
