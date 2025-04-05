const std = @import("std");

pub fn loop() !void {
    var reader = std.io.getStdIn().reader();
    var stdout = std.io.getStdOut().writer();
    var buffer: [1024]u8 = undefined;

    while (true) {
        try stdout.writeAll("argi> ");
        const input = try reader.readUntilDelimiterOrEof(&buffer, '\n');
        if (input == null) break;

        std.debug.print("Interpretando: {s}\n", .{input.?});

        // Aquí invocaríamos `jit.run(input.?)`
    }
}
