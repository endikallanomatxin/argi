const std = @import("std");
const vm = @import("../execution/vm.zig");

pub const help = "--vm-instructions <N> --vm-call-depth <N> --vm-value-cells <N>";

/// Consume one execution option without interpreting unrelated command flags.
/// Zero is a valid budget: it deliberately forbids the corresponding work.
pub fn consume(limits: *vm.Limits, args: []const []const u8, index: *usize) !bool {
    const arg = args[index.*];
    const field: enum { instructions, call_depth, value_cells } = if (std.mem.eql(u8, arg, "--vm-instructions"))
        .instructions
    else if (std.mem.eql(u8, arg, "--vm-call-depth"))
        .call_depth
    else if (std.mem.eql(u8, arg, "--vm-value-cells"))
        .value_cells
    else
        return false;
    if (index.* + 1 >= args.len) return error.MissingExecutionLimit;
    const text = args[index.* + 1];
    if (text.len == 0) return error.InvalidExecutionLimit;
    for (text) |byte| if (!std.ascii.isDigit(byte)) return error.InvalidExecutionLimit;
    const value = std.fmt.parseInt(usize, text, 10) catch return error.InvalidExecutionLimit;
    switch (field) {
        .instructions => limits.instructions = value,
        .call_depth => limits.call_depth = value,
        .value_cells => limits.value_cells = value,
    }
    index.* += 1;
    return true;
}

test "execution options share strict configurable budgets" {
    var limits: vm.Limits = .{};
    var index: usize = 0;
    try std.testing.expect(try consume(&limits, &.{ "--vm-instructions", "0" }, &index));
    try std.testing.expectEqual(@as(usize, 0), limits.instructions);
    try std.testing.expectEqual(@as(usize, 1), index);
    index = 0;
    try std.testing.expect(try consume(&limits, &.{ "--vm-call-depth", "8" }, &index));
    try std.testing.expectEqual(@as(usize, 8), limits.call_depth);
    index = 0;
    try std.testing.expect(try consume(&limits, &.{ "--vm-value-cells", "100" }, &index));
    try std.testing.expectEqual(@as(usize, 100), limits.value_cells);
    for ([_][]const u8{ "", "-1", "+1", "1_000", "9999999999999999999999999999999999" }) |text| {
        index = 0;
        try std.testing.expectError(error.InvalidExecutionLimit, consume(&limits, &.{ "--vm-instructions", text }, &index));
        try std.testing.expectEqual(@as(usize, 0), index);
    }
    index = 0;
    try std.testing.expectError(error.MissingExecutionLimit, consume(&limits, &.{"--vm-instructions"}, &index));
    try std.testing.expect(!try consume(&limits, &.{"--sysroot"}, &index));
}
