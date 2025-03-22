const std = @import("std");
const llvm = @import("llvm.zig");
const c = llvm.c;
const parser = @import("parser.zig");

pub const Error = error{
    ModuleCreationFailed,
    SymbolNotFound,
    SymbolAlreadyDefined,
    OutOfMemory,
    UnknownNode,
    ValueNotFound,
    NotYetImplemented,
};

/// Genera IR a partir del AST, sin crear manualmente la función main.
pub fn generateIR(ast: std.ArrayList(*parser.ASTNode), allocator: *const std.mem.Allocator) !llvm.c.LLVMModuleRef {
    std.debug.print("\n\nCODEGEN\n", .{});

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

const Symbol = struct {
    cname: []u8,
    mutability: parser.Mutability,
    type: llvm.c.LLVMTypeRef,
    value_ref: llvm.c.LLVMValueRef,
};

/// Contexto para la generación de IR
pub const IRGenContext = struct {
    builder: llvm.c.LLVMBuilderRef,
    module: llvm.c.LLVMModuleRef,
    symbol_table: std.StringHashMap(Symbol),
    allocator: *const std.mem.Allocator,

    pub fn init(builder: llvm.c.LLVMBuilderRef, module: llvm.c.LLVMModuleRef, allocator: *const std.mem.Allocator) IRGenContext {
        return IRGenContext{
            .builder = builder,
            .module = module,
            .symbol_table = std.StringHashMap(Symbol).init(allocator.*),
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
fn visitNode(context: *IRGenContext, node: *parser.ASTNode) Error!?c.LLVMValueRef {
    switch (node.*) {
        .declaration => |declPtr| {
            std.debug.print("Generating declaration\n", .{});
            _ = try genDeclaration(context, declPtr);
            return null;
        },
        .assignment => |assignPtr| {
            std.debug.print("Generating assignment\n", .{});
            _ = try genAssignment(context, assignPtr);
            return null;
        },
        .returnStmt => |retStmtPtr| {
            std.debug.print("Generating return\n", .{});
            _ = try genReturn(context, retStmtPtr);
            return null;
        },
        .codeBlock => |blockPtr| {
            std.debug.print("Generating code block\n", .{});
            _ = try genCodeBlock(context, blockPtr);
            return null;
        },
        .valueLiteral => |valLiteralPtr| {
            std.debug.print("Generating value literal\n", .{});
            return try genValueLiteral(valLiteralPtr);
        },
        .identifier => |ident| {
            std.debug.print("Generating identifier\n", .{});
            const value = try genIdentifier(context, ident);
            return value;
        },
        else => {
            return Error.UnknownNode;
        },
    }
}

fn genDeclaration(context: *IRGenContext, decl: *parser.Declaration) !void {
    if (decl.mutability == parser.Mutability.Const and decl.isFunction()) {
        _ = try genTopLevelFunction(context, decl);
    } else {
        _ = try genVarOrConstDeclaration(context, decl);
    }
    return;
}

fn genTopLevelFunction(context: *IRGenContext, decl: *parser.Declaration) !void {

    // Creamos el tipo: supongamos i32 sin parámetros
    // TODO: soportar otros tipos
    const fnType = c.LLVMFunctionType(c.LLVMInt32Type(), null, 0, 0);

    // Nombre nulo-terminado
    const c_name = try dupZ(context.allocator, decl.name);
    // Creamos la función en el módulo
    const func = c.LLVMAddFunction(context.module, c_name.ptr, fnType);

    // Creamos un BasicBlock "entry"
    const entryBB = c.LLVMAppendBasicBlock(func, "entry");
    // Guardamos la posición previa del builder
    const oldBlock = c.LLVMGetInsertBlock(context.builder);

    // Movemos el builder al final de "entry"
    c.LLVMPositionBuilderAtEnd(context.builder, entryBB);

    _ = try genCodeBlock(context, decl.value.codeBlock);

    // Restauramos la posición original del builder
    if (oldBlock) |ob| {
        c.LLVMPositionBuilderAtEnd(context.builder, ob);
    }

    return;
}

/// Genera IR para una declaración de variable
fn genVarOrConstDeclaration(context: *IRGenContext, decl: *parser.Declaration) !void {
    // NOMBRE
    const c_name = try dupZ(context.allocator, decl.name);

    // Comprobamos si existe en la tabla de símbolos
    // POr ahora, evitaremos redefiniciones
    // TODO: Soportar distintos scopes

    if (context.symbol_table.contains(decl.name)) {
        return Error.SymbolAlreadyDefined;
    }

    // VALOR
    const value = try visitNode(context, decl.value);

    // TIPO
    const i32_type = c.LLVMInt32Type();
    // TODO: soportar otros tipos
    // TODO: inferir tipo en base al valor

    // Hacemos alloca
    const alloc = c.LLVMBuildAlloca(context.builder, i32_type, c_name.ptr);

    // Guardamos en la symbol table
    try context.symbol_table.put(decl.name, Symbol{
        .cname = c_name,
        .mutability = decl.mutability,
        .type = i32_type,
        .value_ref = alloc,
    });

    if (value) |v| {
        // Guardamos el valor en el alloc
        _ = c.LLVMBuildStore(context.builder, v, alloc);
    } else {
        return Error.ValueNotFound;
    }
    return;
}

fn genAssignment(context: *IRGenContext, assign: *parser.Assignment) !llvm.c.LLVMValueRef {
    const symbol = context.symbol_table.get(assign.name);
    if (symbol) |s| {
        const val = try visitNode(context, assign.value);
        if (val) |v| {
            _ = c.LLVMBuildStore(context.builder, v, s.value_ref);
            return v;
        } else {
            return Error.ValueNotFound;
        }
    } else {
        return Error.SymbolNotFound;
    }
}

fn genReturn(context: *IRGenContext, retStmt: *parser.ReturnStmt) !void {
    if (retStmt.expression) |expr| {
        const val = try visitNode(context, expr);
        if (val) |v| {
            _ = c.LLVMBuildRet(context.builder, v);
            return;
        } else {
            return Error.ValueNotFound;
        }
    } else {
        _ = c.LLVMBuildRetVoid(context.builder);
        return;
    }
}

fn genCodeBlock(context: *IRGenContext, block: *parser.CodeBlock) !void {
    for (block.items) |stmt| {
        _ = try visitNode(context, stmt);
        // TODO: last statement should return
    }
}

fn genValueLiteral(valLit: *parser.ValueLiteral) !llvm.c.LLVMValueRef {
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
    const symbol = context.symbol_table.get(ident);
    if (symbol) |s| {
        // load el valor
        return c.LLVMBuildLoad2(
            context.builder,
            s.type,
            s.value_ref,
            s.cname.ptr,
        );
    } else {
        return Error.SymbolNotFound;
    }
}

pub fn dupZ(allocator: *const std.mem.Allocator, src: []const u8) ![]u8 {
    var buffer = try allocator.alloc(u8, src.len + 1);
    var i: usize = 0;
    while (i < src.len) : (i += 1) {
        buffer[i] = src[i];
    }
    buffer[src.len] = 0;
    return buffer;
}
