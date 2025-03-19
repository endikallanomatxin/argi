const std = @import("std");
const llvm = @import("llvm.zig");
const c = llvm.c;

const parser = @import("parser.zig");

pub const Error = error{
    ModuleCreationFailed,
    SymbolNotFound,
    OutOfMemory,
};

pub fn generateIR(ast: std.ArrayList(*parser.ASTNode), filename: []const u8, allocator: *const std.mem.Allocator) !llvm.c.LLVMModuleRef {
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

    const builder = llvm.c.LLVMCreateBuilder();
    c.LLVMPositionBuilderAtEnd(builder, entry_bb);

    // 1) Creamos context y un IR builder
    var context = IRGenContext.init(builder, module, allocator);

    // 2) Visitar cada nodo del AST
    for (ast.items) |node| {
        _ = visitNode(&context, node) catch |err| {
            // Maneja el error (por ej. problema al compilar)
            std.debug.print("Error al compilar: {any}\n", .{err});
            break;
        };
    }

    // 3) Finalizamos la función, si no hay ya un return
    //   (depende de tu diseño: si no se ve un "return" explícito,
    //    igual generas un `ret void` o `ret 0`.)
    _ = c.LLVMBuildRetVoid(builder);

    // Liberar el builder
    c.LLVMDisposeBuilder(builder);

    return module;
}

pub const IRGenContext = struct {
    builder: llvm.c.LLVMBuilderRef,
    module: llvm.c.LLVMModuleRef,
    var_table: std.StringHashMap(llvm.c.LLVMValueRef),
    allocator: *const std.mem.Allocator, // Quitar 'const'

    pub fn init(builder: llvm.c.LLVMBuilderRef, module: llvm.c.LLVMModuleRef, allocator: *const std.mem.Allocator) IRGenContext {
        return IRGenContext{
            .builder = builder,
            .module = module,
            .var_table = std.StringHashMap(llvm.c.LLVMValueRef).init(allocator.*),
            .allocator = allocator,
        };
    }
    // ...
};

fn visitNode(context: *IRGenContext, node: *parser.ASTNode) Error!llvm.c.LLVMValueRef {
    switch (node.*) {
        .decl => |declPtr| {
            const decl = declPtr.*;
            return genDeclaration(context, decl);
        },
        .returnStmt => |retStmtPtr| {
            const retStmt = retStmtPtr.*;
            return genReturn(context, retStmt);
        },
        .codeBlock => |blockPtr| {
            const block = blockPtr.*;
            return genCodeBlock(context, block);
        },
        .valueLiteral => |valLiteralPtr| {
            return genValueLiteral(context, valLiteralPtr.*);
        },
        .identifier => |ident| {
            return genIdentifier(context, ident);
        },
        else => {
            // Manejar otros tipos que tengas
            return llvm.c.LLVMConstNull(llvm.c.LLVMVoidType());
        },
    }
}

fn dupZ(allocator: *const std.mem.Allocator, src: []const u8) ![]u8 {
    var buffer = try allocator.alloc(u8, src.len + 1);
    var i: usize = 0;
    while (i < src.len) : (i += 1) {
        buffer[i] = src[i];
    }
    buffer[src.len] = 0;
    return buffer;
}

fn genDeclaration(context: *IRGenContext, decl: parser.Decl) !llvm.c.LLVMValueRef {
    // Si el nombre es "main", procesamos el cuerpo (codeBlock) sin hacer un alloca
    if (std.mem.eql(u8, decl.name, "main")) {
        return visitNode(context, decl.value);
    }
    const i32_type = llvm.c.LLVMInt32Type();
    // Creamos una versión null-terminated del nombre.
    const c_name = try dupZ(context.allocator, decl.name);
    const alloc = llvm.c.LLVMBuildAlloca(context.builder, i32_type, c_name.ptr);
    try context.var_table.put(decl.name, alloc);
    const valueNode = decl.value;
    const rhsValue = try visitNode(context, valueNode);
    _ = llvm.c.LLVMBuildStore(context.builder, rhsValue, alloc);
    return alloc;
}

fn genValueLiteral(context: *IRGenContext, valLit: parser.ValueLiteral) !llvm.c.LLVMValueRef {
    _ = context;
    switch (valLit) {
        .intLiteral => |intLitPtr| {
            const i32_type = llvm.c.LLVMInt32Type();
            return llvm.c.LLVMConstInt(i32_type, @bitCast(intLitPtr.value), 0);
        },
        else => {
            return llvm.c.LLVMConstNull(llvm.c.LLVMVoidType());
        },
    }
}

fn genIdentifier(context: *IRGenContext, ident: []const u8) !llvm.c.LLVMValueRef {
    const maybeAlloc = context.var_table.get(ident);
    if (maybeAlloc) |alloc| {
        // load el valor
        return llvm.c.LLVMBuildLoad2(context.builder, llvm.c.LLVMInt32Type(), // asumiendo i32
            alloc, "tmpLoad");
    } else {
        return error.SymbolNotFound;
    }
}

fn genCodeBlock(context: *IRGenContext, block: parser.CodeBlock) !llvm.c.LLVMValueRef {
    var lastValue: llvm.c.LLVMValueRef = llvm.c.LLVMConstNull(llvm.c.LLVMVoidType());
    for (block.items) |stmt| {
        lastValue = try visitNode(context, stmt);
    }
    return lastValue;
}

fn genReturn(context: *IRGenContext, retStmt: parser.ReturnStmt) !llvm.c.LLVMValueRef {
    if (retStmt.expression) |expr| {
        const val = try visitNode(context, expr);
        return llvm.c.LLVMBuildRet(context.builder, val);
    } else {
        // Return void
        return llvm.c.LLVMBuildRetVoid(context.builder);
    }
}
