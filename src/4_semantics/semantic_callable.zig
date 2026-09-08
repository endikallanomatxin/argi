const std = @import("std");
const syn = @import("../3_syntax/syntax_tree.zig");

pub const OperatorKind = enum(u8) {
    add,
    equal,
    not_equal,
    get,
    set,
    get_ro_pointer,
    get_rw_pointer,
};

pub fn fromSyntax(value: syn.OperatorName) OperatorKind {
    return switch (value) {
        .add => .add,
        .equal => .equal,
        .not_equal => .not_equal,
        .get => .get,
        .set => .set,
        .get_ro_pointer => .get_ro_pointer,
        .get_rw_pointer => .get_rw_pointer,
    };
}

test "callable operator identity is compact and syntax-independent at use sites" {
    try std.testing.expectEqual(@as(usize, 1), @sizeOf(OperatorKind));
    try std.testing.expectEqual(OperatorKind.get, fromSyntax(.get));
}
