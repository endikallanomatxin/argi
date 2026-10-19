const std = @import("std");
const host = @import("../execution/host.zig");
const p = @import("../4_semantics/primitives/schema.zig");

// These are context-local endpoint tokens, never native addresses. Only output
// endpoints are enabled; opening files and reading stdin remain unavailable.
pub const Output = struct {
    writer: *std.Io.Writer,
    error_writer: *std.Io.Writer,

    fn endpoint(_: ?*anyopaque, inputs: []const i128, outputs: []i128) !void {
        outputs[0] = if (inputs[0] == 1 or inputs[0] == 2) inputs[0] else 0;
    }
    fn write(data: ?*anyopaque, inputs: []const i128, outputs: []i128) !void {
        const self: *Output = @ptrCast(@alignCast(data.?));
        outputs[0] = -1;
        if (inputs[0] != 1 and inputs[0] != 2) return;
        (if (inputs[0] == 1) self.writer else self.error_writer).writeByte(@intCast(inputs[1])) catch return;
        outputs[0] = 0;
    }
    fn flush(data: ?*anyopaque, inputs: []const i128, outputs: []i128) !void {
        const self: *Output = @ptrCast(@alignCast(data.?));
        outputs[0] = -1;
        if (inputs[0] != 1 and inputs[0] != 2) return;
        (if (inputs[0] == 1) self.writer else self.error_writer).flush() catch return;
        outputs[0] = 0;
    }
    pub fn bindings(self: *Output) [3]host.Binding {
        const i32_range = comptime p.integerRangeForWidth(32, true);
        const byte_range = comptime p.integerRangeForWidth(8, false);
        const native_range = comptime p.integerRangeForWidth(@bitSizeOf(usize), false);
        return .{
            .{ .symbol = "_argi_standard_stream", .inputs = comptime &.{i32_range}, .outputs = comptime &.{native_range}, .call = endpoint },
            .{ .symbol = "_argi_file_write_byte", .inputs = comptime &.{ native_range, byte_range }, .outputs = comptime &.{i32_range}, .data = self, .call = write },
            .{ .symbol = "_argi_file_flush", .inputs = comptime &.{native_range}, .outputs = comptime &.{i32_range}, .data = self, .call = flush },
        };
    }
};

test "REPL output adapters report failed writes and reject unknown endpoints" {
    var output = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer output.deinit();
    var failure: std.Io.Writer = .failing;
    var adapter: Output = .{ .writer = &failure, .error_writer = &output.writer };
    const bindings = adapter.bindings();
    var status: [1]i128 = undefined;
    try bindings[1].call(bindings[1].data, &.{ 1, 65 }, &status);
    try std.testing.expectEqual(@as(i128, -1), status[0]);
    try bindings[1].call(bindings[1].data, &.{ 2, 66 }, &status);
    try std.testing.expectEqual(@as(i128, 0), status[0]);
    try std.testing.expectEqualStrings("B", output.written());
    try bindings[1].call(bindings[1].data, &.{ 99, 67 }, &status);
    try std.testing.expectEqual(@as(i128, -1), status[0]);
    try std.testing.expectEqualStrings("B", output.written());
    try bindings[2].call(bindings[2].data, &.{99}, &status);
    try std.testing.expectEqual(@as(i128, -1), status[0]);
}
