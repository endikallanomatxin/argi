const std = @import("std");
const codegen = @import("../codegen.zig");
const llvm = @import("../llvm.zig");
const c = llvm.c;

pub fn compile(filename: []const u8) !void {
    std.debug.print("Compilando archivo: {s}\n", .{filename});

    const module = try codegen.generateIR(filename);

    // Convertimos el nombre a un puntero de C
    const output_filename = "output.ll";
    var err_msg: [*c]u8 = null;

    // 🔥 Guardar el módulo LLVM en un archivo usando `LLVMPrintModuleToFile`
    if (c.LLVMPrintModuleToFile(module, output_filename, &err_msg) != 0) {
        std.debug.print("Error al escribir el módulo LLVM: {s}\n", .{err_msg});
        return error.WriteFailed;
    }

    std.debug.print("Código LLVM IR guardado en {s}\n", .{output_filename});

    // Compilar usando Clang
    const result = std.process.Child.run(.{
        .allocator = std.heap.page_allocator,
        .argv = &[_][]const u8{ "clang", output_filename, "-o", "output" },
    }) catch return;

    _ = result;

    std.debug.print("Compilación completada. Ejecutable generado: ./output\n", .{});
}
