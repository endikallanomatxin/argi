const std = @import("std");
const repl = @import("../repl.zig");

pub fn start() !void {
    std.debug.print("Iniciando REPL de argi...\n", .{});
    try repl.loop();
}
