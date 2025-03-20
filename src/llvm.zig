// src/llvm.zig

pub const c = @cImport({
    @cInclude("llvm-c/Core.h");
    @cInclude("llvm-c/ExecutionEngine.h");
    @cInclude("llvm-c/Analysis.h");
    // Añade aquí todos los headers LLVM que uses
});
