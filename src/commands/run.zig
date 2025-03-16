const std = @import("std");
const jit = @import("../jit.zig");

pub fn execute(filename: []const u8) !void {
    std.debug.print("Ejecutando: {s}\n", .{filename});
    try jit.run(filename);
}
