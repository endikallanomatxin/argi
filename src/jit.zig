const std = @import("std");

pub fn run(filename: []const u8) !void {
    std.debug.print("Ejecutando {s} en JIT...\n", .{filename});

    // Se leerá el archivo y se generará el código en memoria.
    // Luego, usaremos LLVM JIT para ejecutarlo.
}
