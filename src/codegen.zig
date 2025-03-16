const std = @import("std");
const llvm = @import("llvm.zig");
const c = llvm.c;

pub const Error = error{
    ModuleCreationFailed,
};

pub fn generateIR(filename: []const u8) !c.LLVMModuleRef {
    std.debug.print("Generando IR para {s}\n", .{filename});

    // Crear el módulo LLVM con un nombre (por ejemplo, "dummy_module").
    const module = c.LLVMModuleCreateWithName("dummy_module");
    if (module == null) {
        return Error.ModuleCreationFailed;
    }

    // --- Crear la función 'main' ---
    // Definir el tipo void.
    const void_type = c.LLVMVoidType();
    // Función sin parámetros: tipo void ().
    const func_type = c.LLVMFunctionType(void_type, null, 0, 0);
    // Agregar la función 'main' al módulo.
    const main_fn = c.LLVMAddFunction(module, "main", func_type);

    // --- Crear el bloque básico 'entry' ---
    const entry_bb = c.LLVMAppendBasicBlock(main_fn, "entry");

    // Crear un builder y posicionarlo al final del bloque 'entry'.
    const builder = c.LLVMCreateBuilder();
    c.LLVMPositionBuilderAtEnd(builder, entry_bb);

    // --- Generar IR para la declaración: x := 42 ---
    // Suponemos que, por inferencia, el tipo es "Int" (en este caso, usaremos int32).
    const int32_type = c.LLVMInt32Type();
    // Reservar espacio para la variable 'x' con un alloca.
    const x_alloca = c.LLVMBuildAlloca(builder, int32_type, "x");
    // Crear la constante entera 42.
    const const42 = c.LLVMConstInt(int32_type, 42, 0);
    // Almacenar el valor 42 en la variable 'x'.
    _ = c.LLVMBuildStore(builder, const42, x_alloca);

    // --- Finalizar la función con un 'return void' ---
    _ = c.LLVMBuildRetVoid(builder);

    // Liberar el builder (buena práctica, aunque no estrictamente obligatorio).
    c.LLVMDisposeBuilder(builder);

    return module;
}
