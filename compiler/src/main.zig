const std = @import("std");
const build_cmd = @import("commands/build.zig");
const lsp_cmd = @import("commands/lsp.zig");

pub fn main() !void {
    const args = std.process.argsAlloc(std.heap.page_allocator) catch return;
    defer std.process.argsFree(std.heap.page_allocator, args);

    if (args.len < 2) {
        std.debug.print("Uso: argi <comando> [archivo]\n", .{});
        std.debug.print("Comandos disponibles:\n", .{});
        std.debug.print("  build <file.rg>  - Compila el código a un binario\n", .{});
        std.debug.print("  lsp              - Inicia el servidor LSP\n", .{});
        return;
    }

    const command = args[1];

    if (std.mem.eql(u8, command, "build")) {
        if (args.len < 3) {
            std.debug.print("Error: Se necesita un archivo\n", .{});
            return;
        }
        build_cmd.compile(args[2]) catch |err| {
            std.debug.print("Error al compilar: {any}\n", .{err});
            return;
        };
    } else if (std.mem.eql(u8, command, "lsp")) {
        try lsp_cmd.start();
    } else {
        std.debug.print("Error: Comando desconocido\n", .{});
    }
}
