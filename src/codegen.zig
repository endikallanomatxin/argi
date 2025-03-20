const std = @import("std");
const llvm = @import("llvm.zig");
const c = llvm.c;
const parser = @import("parser.zig");

pub const Error = error{
    ModuleCreationFailed,
    SymbolNotFound,
    OutOfMemory,
};

/// Genera IR a partir del AST, sin crear manualmente la función main.
pub fn generateIR(ast: std.ArrayList(*parser.ASTNode), filename: []const u8, allocator: *const std.mem.Allocator) !llvm.c.LLVMModuleRef {
    std.debug.print("Generando IR para {s}\n", .{filename});

    // Creamos el módulo
    const module = c.LLVMModuleCreateWithName("dummy_module");
    if (module == null) return Error.ModuleCreationFailed;

    // Creamos un IRGenContext con un builder "vacío" (todavía sin un BasicBlock posicionado).
    const builder = c.LLVMCreateBuilder();
    var context = IRGenContext.init(builder, module, allocator);

    // Recorremos el AST, que será el que defina main u otras funciones
    for (ast.items) |node| {
        _ = visitNode(&context, node) catch |err| {
            std.debug.print("Error al compilar: {any}\n", .{err});
            break;
        };
    }

    // Verificamos que el IR sea válido
    var error_msg: [*c]u8 = null;
    const rc = c.LLVMVerifyModule(module, c.LLVMPrintMessageAction, &error_msg);
    if (rc != 0) {
        std.debug.print("LLVMVerifyModule detectó IR inválido:\n{s}\n", .{error_msg});
        return Error.ModuleCreationFailed;
    }

    // Liberar builder
    c.LLVMDisposeBuilder(builder);

    return module;
}

/// Contexto para la generación de IR
pub const IRGenContext = struct {
    builder: llvm.c.LLVMBuilderRef,
    module: llvm.c.LLVMModuleRef,
    var_table: std.StringHashMap(llvm.c.LLVMValueRef),
    allocator: *const std.mem.Allocator,

    pub fn init(builder: llvm.c.LLVMBuilderRef, module: llvm.c.LLVMModuleRef, allocator: *const std.mem.Allocator) IRGenContext {
        return IRGenContext{
            .builder = builder,
            .module = module,
            .var_table = std.StringHashMap(llvm.c.LLVMValueRef).init(allocator.*),
            .allocator = allocator,
        };
    }
};

/// Visita un nodo del AST y genera IR correspondiente
fn visitNode(context: *IRGenContext, node: *parser.ASTNode) Error!llvm.c.LLVMValueRef {
    switch (node.*) {
        .decl => |declPtr| {
            return genDeclaration(context, declPtr.*);
        },
        .returnStmt => |retStmtPtr| {
            return genReturn(context, retStmtPtr.*);
        },
        .codeBlock => |blockPtr| {
            return genCodeBlock(context, blockPtr.*);
        },
        .valueLiteral => |valLiteralPtr| {
            return genValueLiteral(context, valLiteralPtr.*);
        },
        .identifier => |ident| {
            return genIdentifier(context, ident);
        },
        else => {
            // Otros tipos de nodo
            return llvm.c.LLVMConstNull(llvm.c.LLVMVoidType());
        },
    }
}

/// Duplicar un slice en uno null-terminated
fn dupZ(allocator: *const std.mem.Allocator, src: []const u8) ![]u8 {
    var buffer = try allocator.alloc(u8, src.len + 1);
    var i: usize = 0;
    while (i < src.len) : (i += 1) {
        buffer[i] = src[i];
    }
    buffer[src.len] = 0;
    return buffer;
}

/// Genera la IR para una declaración (puede ser variable o función).
fn genDeclaration(context: *IRGenContext, decl: parser.Decl) !llvm.c.LLVMValueRef {
    // Detectamos si es función o variable
    if (decl.isFunction()) {
        // Generar una función (puede ser main u otra).
        return genFunction(context, decl);
    } else {
        // Es una variable/const
        return genVar(context, decl);
    }
}

/// Genera IR para una declaración de función
fn genFunction(context: *IRGenContext, decl: parser.Decl) !llvm.c.LLVMValueRef {
    // Creamos el tipo de función. Suponiendo que devuelva i32 y no tiene args.
    // (Si en tu AST tienes decl.args, podrías construirlo dinámicamente).
    const fnTy = c.LLVMFunctionType(c.LLVMInt32Type(), null, 0, 0);

    // Creamos la cadena null-terminated con el nombre
    const c_name = try dupZ(context.allocator, decl.name);
    // Creamos la función
    const fnVal = c.LLVMAddFunction(context.module, c_name.ptr, fnTy);

    // Creamos un BasicBlock "entry"
    const entryBB = c.LLVMAppendBasicBlock(fnVal, "entry");

    // Guardamos la posición anterior del builder (no es estrictamente necesario
    // pero puede ser útil si tu builder ya estaba posicionado en otra parte).
    const oldBlock = c.LLVMGetInsertBlock(context.builder);

    // Movemos el builder al final de "entry" de esta nueva función
    c.LLVMPositionBuilderAtEnd(context.builder, entryBB);

    // Visitamos el cuerpo (un codeBlock, presumably)
    // Esto generará las sentencias, etc.
    _ = visitNode(context, decl.value) catch |err| {
        std.debug.print("Error generando body de funcion '{s}': {any}\n", .{ decl.name, err });
        // Podrías forzar un ret "0" o ret void en caso de error
    };

    // Si el AST no generó un return explícito, generamos un return 0
    // (Este approach se puede mejorar rastreando si ya hubo un return.)
    _ = c.LLVMBuildRet(context.builder, c.LLVMConstInt(c.LLVMInt32Type(), 0, 0));

    // Restauramos posición del builder
    if (oldBlock) |ob| {
        c.LLVMPositionBuilderAtEnd(context.builder, ob);
    }

    return fnVal;
}

/// Genera IR para una declaración de variable
fn genVar(context: *IRGenContext, decl: parser.Decl) !llvm.c.LLVMValueRef {
    std.debug.print("genVar: Generating for var '{s}'...\n", .{decl.name});

    // Hacemos alloca
    const i32_type = c.LLVMInt32Type();
    const c_name = try dupZ(context.allocator, decl.name);
    const alloc = c.LLVMBuildAlloca(context.builder, i32_type, c_name.ptr);

    // Guardamos en var_table
    try context.var_table.put(decl.name, alloc);

    // Generamos la parte derecha (rhsValue)
    const rhsValue = try visitNode(context, decl.value);

    // Hacemos store
    _ = c.LLVMBuildStore(context.builder, rhsValue, alloc);

    return alloc;
}

fn genReturn(context: *IRGenContext, retStmt: parser.ReturnStmt) !llvm.c.LLVMValueRef {
    std.debug.print("genReturn: Starting.\n", .{});
    if (retStmt.expression) |expr| {
        std.debug.print("genReturn: There's an expression to return.\n", .{});
        const val = try visitNode(context, expr);
        std.debug.print("genReturn: About to LLVMBuildRet(...)\n", .{});
        return c.LLVMBuildRet(context.builder, val);
    } else {
        std.debug.print("genReturn: Return void.\n", .{});
        return c.LLVMBuildRetVoid(context.builder);
    }
}

fn genCodeBlock(context: *IRGenContext, block: parser.CodeBlock) !llvm.c.LLVMValueRef {
    var lastValue: llvm.c.LLVMValueRef = llvm.c.LLVMConstNull(llvm.c.LLVMVoidType());
    for (block.items) |stmt| {
        lastValue = try visitNode(context, stmt);
    }
    return lastValue;
}

fn genValueLiteral(context: *IRGenContext, valLit: parser.ValueLiteral) !llvm.c.LLVMValueRef {
    _ = context;
    switch (valLit) {
        .intLiteral => |intLitPtr| {
            const i32_type = c.LLVMInt32Type();
            return c.LLVMConstInt(i32_type, @bitCast(intLitPtr.value), 0);
        },
        else => {
            return c.LLVMConstNull(llvm.c.LLVMVoidType());
        },
    }
}

fn genIdentifier(context: *IRGenContext, ident: []const u8) !llvm.c.LLVMValueRef {
    const maybeAlloc = context.var_table.get(ident);
    if (maybeAlloc) |alloc| {
        // load el valor
        return c.LLVMBuildLoad2(
            context.builder,
            c.LLVMInt32Type(), // asumiendo i32
            alloc,
            "tmpLoad",
        );
    } else {
        return Error.SymbolNotFound;
    }
}
