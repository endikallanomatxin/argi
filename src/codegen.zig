const std = @import("std");
const llvm = @import("llvm.zig");
const c = llvm.c;
const parser = @import("parser.zig");

pub const Error = error{
    ModuleCreationFailed,
    SymbolNotFound,
    OutOfMemory,
    UnknownNode,
};

pub fn dupZ(allocator: *const std.mem.Allocator, src: []const u8) ![]u8 {
    var buffer = try allocator.alloc(u8, src.len + 1);
    var i: usize = 0;
    while (i < src.len) : (i += 1) {
        buffer[i] = src[i];
    }
    buffer[src.len] = 0;
    return buffer;
}

/// Genera IR a partir del AST, sin crear manualmente la función main.
pub fn generateIR(ast: std.ArrayList(*parser.ASTNode), filename: []const u8, allocator: *const std.mem.Allocator) !llvm.c.LLVMModuleRef {
    std.debug.print("Generando IR para {s}\n", .{filename});

    // Creamos el módulo
    const module = c.LLVMModuleCreateWithName("dummy_module");
    if (module == null) return Error.ModuleCreationFailed;
    std.debug.print("Módulo creado.\n", .{});

    // Creamos un IRGenContext con un builder "vacío" (todavía sin un BasicBlock posicionado).
    const builder = c.LLVMCreateBuilder();
    var context = IRGenContext.init(builder, module, allocator);
    std.debug.print("Contexto creado.\n", .{});

    // Recorremos el AST, que será el que defina main u otras funciones
    for (ast.items) |node| {
        visitNode(&context, node) catch |err| {
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

// El AST tiene esta pinta:
//
// Declaration main (const) = Bloque de código:
//    Declaration x (var) = IntLiteral 42
//    return IntLiteral 0

/// Visita un nodo del AST y genera IR correspondiente
fn visitNode(context: *IRGenContext, node: *parser.ASTNode) Error!void {
    switch (node.*) {
        .decl => |declPtr| {
            if (declPtr.*.isFunction()) {
                _ = try genFunction(context, declPtr);
                return;
            } else {
                _ = try genVar(context, declPtr);
                return;
            }
        },
        .returnStmt => |retStmtPtr| {
            _ = try genReturn(context, retStmtPtr);
            return;
        },
        .codeBlock => |blockPtr| {
            _ = try genCodeBlock(context, blockPtr);
            return;
        },
        .valueLiteral => |valLiteralPtr| {
            _ = try genValueLiteral(context, valLiteralPtr);
            return;
        },
        .identifier => |ident| {
            _ = try genIdentifier(context, ident);
            return;
        },
        else => {
            return Error.UnknownNode;
        },
    }
}

fn genFunction(context: *IRGenContext, decl: *parser.Decl) !void {
    std.debug.print("genFunction: Generating for '{s}'...\n", .{decl.name});

    std.debug.print("Generating type for '{s}'...\n", .{decl.name});
    // Creamos el tipo: supongamos i32 sin parámetros
    const fnType = c.LLVMFunctionType(c.LLVMInt32Type(), null, 0, 0);

    std.debug.print("Adding function '{s}' to module...\n", .{decl.name});
    // Nombre nulo-terminado
    const c_name = try dupZ(context.allocator, decl.name);
    // Creamos la función en el módulo
    const func = c.LLVMAddFunction(context.module, c_name.ptr, fnType);

    std.debug.print("Creating entry block for '{s}'...\n", .{decl.name});
    // Creamos un BasicBlock "entry"
    const entryBB = c.LLVMAppendBasicBlock(func, "entry");
    // Guardamos la posición previa del builder
    const oldBlock = c.LLVMGetInsertBlock(context.builder);

    std.debug.print("Setting builder position at end of entry block...\n", .{});
    // Movemos el builder al final de "entry"
    c.LLVMPositionBuilderAtEnd(context.builder, entryBB);

    std.debug.print("Visiting function body of '{s}'...\n", .{decl.name});
    _ = try genCodeBlock(context, decl.value.codeBlock);

    std.debug.print("Restoring builder position...\n", .{});
    // Restauramos la posición original del builder
    if (oldBlock) |ob| {
        c.LLVMPositionBuilderAtEnd(context.builder, ob);
    }

    return;
}

/// Genera IR para una declaración de variable
fn genVar(context: *IRGenContext, decl: *parser.Decl) !void {
    std.debug.print("genVar: Generating for var '{s}'...\n", .{decl.name});

    // Hacemos alloca
    const i32_type = c.LLVMInt32Type();
    const c_name = try dupZ(context.allocator, decl.name);
    const alloc = c.LLVMBuildAlloca(context.builder, i32_type, c_name.ptr);

    // Guardamos en var_table
    try context.var_table.put(decl.name, alloc);

    // Generamos la parte derecha (rhsValue)
    // const rhsValue = try visitNode(context, decl.value);
    const rhsValue = c.LLVMConstInt(i32_type, 42, 0);

    // Hacemos store
    _ = c.LLVMBuildStore(context.builder, rhsValue, alloc);

    return;
}

fn genReturn(context: *IRGenContext, retStmt: *parser.ReturnStmt) !void {
    std.debug.print("genReturn: Starting.\n", .{});
    if (retStmt.expression) |expr| {
        std.debug.print("genReturn: There's an expression to return.\n", .{});
        // const val = try visitNode(context, expr);
        _ = expr;
        const val = c.LLVMConstInt(c.LLVMInt32Type(), 0, 0);
        std.debug.print("genReturn: About to LLVMBuildRet(...)\n", .{});
        _ = c.LLVMBuildRet(context.builder, val);
        return;
    } else {
        std.debug.print("genReturn: Return void.\n", .{});
        _ = c.LLVMBuildRetVoid(context.builder);
        return;
    }
}

fn genCodeBlock(context: *IRGenContext, block: *parser.CodeBlock) !void {
    for (block.items) |stmt| {
        try visitNode(context, stmt);
    }
}

fn genValueLiteral(context: *IRGenContext, valLit: *parser.ValueLiteral) !llvm.c.LLVMValueRef {
    _ = context;
    switch (valLit.*) {
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
