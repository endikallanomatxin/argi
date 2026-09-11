const std = @import("std");

pub const OperatorKind = enum(u8) {
    add,
    equal,
    not_equal,
    get,
    set,
    get_ro_pointer,
    get_rw_pointer,
};

test "callable operator identity is compact" {
    try std.testing.expectEqual(@as(usize, 1), @sizeOf(OperatorKind));
}
