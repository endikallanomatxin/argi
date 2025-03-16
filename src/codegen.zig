const std = @import("std");

const llvm = @import("llvm.zig");
const c = llvm.c;

pub const Error = error{
    ModuleCreationFailed,
};

pub fn generateIR(filename: []const u8) !c.LLVMModuleRef {
    std.debug.print("Generando IR para {s}\n", .{filename});

    // Crea un módulo LLVM válido. Aquí usamos un nombre dummy.
    const module_name = "dummy_module";
    const module = c.LLVMModuleCreateWithName(module_name);
    if (module == null) {
        return Error.ModuleCreationFailed;
    }

    // Opcional: podrías agregar funciones dummy u otros elementos si lo deseas.

    return module;
}
