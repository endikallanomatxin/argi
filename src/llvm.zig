// src/llvm.zig

pub const c = @cImport({
    @cInclude("llvm-c/Core.h");
    @cInclude("llvm-c/ExecutionEngine.h");
    // Añade aquí todos los headers LLVM que uses
});
