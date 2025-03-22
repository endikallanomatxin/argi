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
    ConstantReassignment,
    CompilationFailed,
    ExpressionNotFound,
    InvalidType,
};

/// Representa una entrada de símbolo (variable o función) en la tabla de símbolos.
const Symbol = struct {
    cname: []u8,
    mutability: parser.Mutability,
    type_ref: llvm.c.LLVMTypeRef,
    ref: llvm.c.LLVMValueRef,
};

const TypedValue = struct {
    type_ref: llvm.c.LLVMTypeRef,
    value_ref: llvm.c.LLVMValueRef,
};

/// CodeGenerator es el tipo que se encarga de producir IR a partir de un AST.
pub const CodeGenerator = struct {
    allocator: *const std.mem.Allocator,
    ast: std.ArrayList(*parser.ASTNode),
    builder: llvm.c.LLVMBuilderRef,
    module: llvm.c.LLVMModuleRef,
    symbol_table: std.StringHashMap(Symbol),

    /// Crea un nuevo CodeGenerator, generando un módulo y un builder vacíos.
    pub fn init(allocator: *const std.mem.Allocator, ast: std.ArrayList(*parser.ASTNode)) !CodeGenerator {
        const module = c.LLVMModuleCreateWithName("dummy_module");
        if (module == null) {
            std.debug.print("Error al crear el módulo LLVM\n", .{});
            return Error.ModuleCreationFailed;
        }

        const builder = c.LLVMCreateBuilder();

        return CodeGenerator{
            .allocator = allocator,
            .ast = ast,
            .builder = builder,
            .module = module,
            .symbol_table = std.StringHashMap(Symbol).init(allocator.*),
        };
    }

    /// Genera IR a partir del AST, retornando el módulo LLVM resultante.
    /// Una vez generado, el IR se valida para asegurar que sea correcto.
    pub fn generate(self: *CodeGenerator) !llvm.c.LLVMModuleRef {
        std.debug.print("\n\nCODEGEN\n", .{});

        // Recorremos el AST, que puede definir funciones u otros símbolos
        for (self.ast.items) |node| {
            _ = self.visitNode(node) catch |err| {
                std.debug.print("Error al compilar: {any}\n", .{err});
                return Error.CompilationFailed;
            };
        }

        // Verificamos que el IR sea válido
        var error_msg: [*c]u8 = null;
        const rc = c.LLVMVerifyModule(self.module, c.LLVMPrintMessageAction, &error_msg);
        if (rc != 0) {
            std.debug.print("LLVMVerifyModule detectó IR inválido:\n{s}\n", .{error_msg});
            return Error.ModuleCreationFailed;
        }

        return self.module;
    }

    /// Libera los recursos asociados al CodeGenerator.
    pub fn deinit(self: *CodeGenerator) void {
        if (self.builder) |b| {
            c.LLVMDisposeBuilder(b);
        }
        self.symbol_table.deinit();
        // NOTA: No destruimos el módulo aquí (c.LLVMDisposeModule) si se
        // necesita más adelante. El usuario podría hacerlo por su cuenta.
    }

    /// Visitamos un nodo del AST y generamos IR correspondiente.
    fn visitNode(self: *CodeGenerator, node: *parser.ASTNode) Error!?TypedValue {
        switch (node.*) {
            .declaration => |declPtr| {
                std.debug.print("Generating declaration\n", .{});
                _ = try self.genDeclaration(declPtr);
                return null;
            },
            .assignment => |assignPtr| {
                std.debug.print("Generating assignment\n", .{});
                return try self.genAssignment(assignPtr);
            },
            .returnStmt => |retStmtPtr| {
                std.debug.print("Generating return\n", .{});
                _ = try self.genReturn(retStmtPtr);
                return null;
            },
            .codeBlock => |blockPtr| {
                std.debug.print("Generating code block\n", .{});
                _ = try self.genCodeBlock(blockPtr);
                return null;
            },
            .valueLiteral => |valLiteralPtr| {
                std.debug.print("Generating value literal\n", .{});
                return try self.genValueLiteral(valLiteralPtr);
            },
            .identifier => |ident| {
                std.debug.print("Generating identifier\n", .{});
                return try self.genIdentifier(ident);
            },
            .binaryOperation => |binOpPtr| {
                std.debug.print("Generating binary op\n", .{});
                return try self.genBinaryOperation(binOpPtr);
            },
            else => {
                return Error.UnknownNode;
            },
        }
    }

    /// Genera IR para una declaración: puede ser de variable/constante o de función top-level.
    fn genDeclaration(self: *CodeGenerator, decl: *parser.Declaration) !void {
        // Si es una "const" y apunta a un bloque de código, asumimos que es una función.
        if (decl.mutability == parser.Mutability.Const and decl.isFunction()) {
            return try self.genTopLevelFunction(decl);
        } else {
            return try self.genVarOrConstDeclaration(decl);
        }
    }

    /// Genera IR para una declaración de función "top-level".
    fn genTopLevelFunction(self: *CodeGenerator, decl: *parser.Declaration) !void {
        // Creamos un tipo de función. Aquí se asume que es i32 sin parámetros.
        // TODO: soportar parámetros y otros tipos.
        const fn_type = c.LLVMFunctionType(c.LLVMInt32Type(), null, 0, 0);

        // Convertimos el nombre a null-terminated
        const c_name = try self.dupZ(decl.name);

        // Creamos la función en el módulo
        const func = c.LLVMAddFunction(self.module, c_name.ptr, fn_type);

        // Creamos un bloque básico "entry"
        const entryBB = c.LLVMAppendBasicBlock(func, "entry");
        // Guardamos la posición previa del builder
        const oldBlock = c.LLVMGetInsertBlock(self.builder);

        // Posicionamos el builder al final de "entry"
        c.LLVMPositionBuilderAtEnd(self.builder, entryBB);

        // Generamos el interior de la función
        if (decl.value) |v| {
            _ = try self.genCodeBlock(v.codeBlock);
        } else {
            return Error.ExpressionNotFound;
        }

        // Restauramos la posición original del builder
        if (oldBlock) |ob| {
            c.LLVMPositionBuilderAtEnd(self.builder, ob);
        }
    }

    /// Genera IR para una variable o constante en ámbito local.
    fn genVarOrConstDeclaration(self: *CodeGenerator, decl: *parser.Declaration) !void {
        const c_name = try self.dupZ(decl.name);

        if (self.symbol_table.contains(decl.name)) {
            return Error.SymbolAlreadyDefined;
        }

        var value_ref: ?llvm.c.LLVMValueRef = null;
        var type_ref: ?llvm.c.LLVMTypeRef = null;

        if (decl.value) |v| {
            // Obtenemos el valor y su tipo
            const tv_opt = try self.visitNode(v);
            const tv = tv_opt orelse return Error.ValueNotFound;

            value_ref = tv.value_ref;

            // Check type compatibility
            if (decl.type) |t| {
                std.debug.print("Checking type compatibility\n", .{});
                const expected_type = try toLLVMType(t);
                if (tv.type_ref != expected_type) {
                    return Error.InvalidType;
                }
            }
            type_ref = tv.type_ref;
        } else {
            // Si no hay valor, declaramos la variable sin inicializar
            if (decl.type) |t| {
                type_ref = try toLLVMType(t);
            } else {
                return Error.NotYetImplemented;
            }
        }

        // Creamos la alloca usando tv.type_ref en lugar de i32
        const alloc = c.LLVMBuildAlloca(self.builder, type_ref orelse return Error.InvalidType, c_name.ptr);

        // Guardamos en la tabla de símbolos
        try self.symbol_table.put(
            decl.name,
            Symbol{
                .cname = c_name,
                .mutability = decl.mutability,
                .type_ref = type_ref orelse return Error.InvalidType,
                .ref = alloc,
            },
        );

        // Almacenar el valor en la variable
        if (value_ref) |v| {
            _ = c.LLVMBuildStore(self.builder, v, alloc);
        }
    }

    /// Genera IR para una asignación: busca la variable y almacena el nuevo valor.
    fn genAssignment(self: *CodeGenerator, assign: *parser.Assignment) !TypedValue {
        const symbol_opt = self.symbol_table.get(assign.name);
        const symbol = symbol_opt orelse return Error.SymbolNotFound;
        if (symbol.mutability == parser.Mutability.Const) {
            return Error.ConstantReassignment;
        }

        const tv_opt = try self.visitNode(assign.value);
        const tv = tv_opt orelse return Error.ValueNotFound;

        // Si la variable se declaró como float y tv es int, haz cast
        // O al revés. Ejemplo: "int -> float" con LLVMBuildSIToFP, etc.
        var final_value_ref: llvm.c.LLVMValueRef = tv.value_ref;
        if (symbol.type_ref == c.LLVMFloatType() and tv.type_ref == c.LLVMInt32Type()) {
            // Cambiamos de int a float
            final_value_ref = c.LLVMBuildSIToFP(self.builder, tv.value_ref, symbol.type_ref, "int_to_float");
            // TODO: Pensar si queremos permitir esto
        } else if (symbol.type_ref == c.LLVMInt32Type() and tv.type_ref == c.LLVMFloatType()) {
            // Para ejemplo, un "floor" implícito:
            // final_value_ref = c.LLVMBuildFPToSI(self.builder, tv.value_ref, symbol.type_ref, "float_to_int");
            return Error.InvalidType;
        }

        _ = c.LLVMBuildStore(self.builder, final_value_ref, symbol.ref);

        // Retornamos un TypedValue con el tipo original de la variable
        // (que no cambia) y el valor final que guardamos
        return TypedValue{
            .value_ref = final_value_ref,
            .type_ref = symbol.type_ref,
        };
    }

    /// Genera IR para una instrucción return: `return <expr?>`.
    fn genReturn(self: *CodeGenerator, retStmt: *parser.ReturnStmt) !void {
        if (retStmt.expression) |expr| {
            const val = try self.visitNode(expr);
            if (val) |v| {
                _ = c.LLVMBuildRet(self.builder, v.value_ref);
                return;
            } else {
                return Error.ValueNotFound;
            }
        } else {
            _ = c.LLVMBuildRetVoid(self.builder);
            return;
        }
    }

    /// Genera IR para un bloque de código: secuencia de sentencias.
    fn genCodeBlock(self: *CodeGenerator, block: *parser.CodeBlock) !void {
        for (block.items) |stmt| {
            _ = try self.visitNode(stmt);
            // No se realiza un control de flujo especial aquí (por ejemplo, un "return" temprano).
        }
    }

    /// Genera IR para un literal de valor (sólo entero, como demo).
    fn genValueLiteral(self: *CodeGenerator, valLit: *parser.ValueLiteral) !TypedValue {
        _ = self;
        switch (valLit.*) {
            .intLiteral => |intLitPtr| {
                const i32_type = c.LLVMInt32Type();
                const val_ref = c.LLVMConstInt(i32_type, @bitCast(intLitPtr.value), 0);
                return TypedValue{ .value_ref = val_ref, .type_ref = i32_type };
            },
            .floatLiteral => |floatLitPtr| {
                const f32_type = c.LLVMFloatType();
                // Si quisieras double => c.LLVMDoubleType();
                const val_ref = c.LLVMConstReal(f32_type, @floatCast(floatLitPtr.value));
                return TypedValue{ .value_ref = val_ref, .type_ref = f32_type };
            },
            else => {
                // Para simplificar, devolvemos un "void" con type void*
                // o podrías lanzar un error
                const void_type = c.LLVMVoidType();
                const null_val = c.LLVMConstNull(void_type);
                return TypedValue{ .value_ref = null_val, .type_ref = void_type };
            },
        }
    }
    /// Genera IR para un identificador: realiza un load de la variable.
    fn genIdentifier(self: *CodeGenerator, ident: []const u8) !TypedValue {
        const symbol = self.symbol_table.get(ident);
        if (symbol) |s| {
            const load_val = c.LLVMBuildLoad2(
                self.builder,
                s.type_ref,
                s.ref,
                s.cname.ptr,
            );
            return TypedValue{ .value_ref = load_val, .type_ref = s.type_ref };
        } else {
            return Error.SymbolNotFound;
        }
    }

    /// Genera IR para una operación binaria aritmética.
    fn genBinaryOperation(self: *CodeGenerator, binOpPtr: *parser.BinaryOperation) !TypedValue {
        // Obtenemos los operandos con su tipo
        const left_opt = self.visitNode(binOpPtr.left) catch return Error.ValueNotFound;
        const right_opt = self.visitNode(binOpPtr.right) catch return Error.ValueNotFound;

        var left = left_opt orelse return Error.ValueNotFound;
        var right = right_opt orelse return Error.ValueNotFound;

        // Logica de unificación:
        // 1. Si un operando es float, convertimos el otro a float
        //    (o lanza error si no quieres autoconversión).
        if (left.type_ref == c.LLVMFloatType() and right.type_ref == c.LLVMInt32Type()) {
            const cast = c.LLVMBuildSIToFP(self.builder, right.value_ref, c.LLVMFloatType(), "int_to_float");
            right = TypedValue{ .value_ref = cast, .type_ref = c.LLVMFloatType() };
        } else if (left.type_ref == c.LLVMInt32Type() and right.type_ref == c.LLVMFloatType()) {
            const cast = c.LLVMBuildSIToFP(self.builder, left.value_ref, c.LLVMFloatType(), "int_to_float");
            left = TypedValue{ .value_ref = cast, .type_ref = c.LLVMFloatType() };
        }

        const isFloatOp = (left.type_ref == c.LLVMFloatType());

        // Construimos la instrucción
        const result_value = switch (binOpPtr.operator) {
            .Addition => if (isFloatOp)
                c.LLVMBuildFAdd(self.builder, left.value_ref, right.value_ref, "faddtmp")
            else
                c.LLVMBuildAdd(self.builder, left.value_ref, right.value_ref, "addtmp"),

            .Subtraction => if (isFloatOp)
                c.LLVMBuildFSub(self.builder, left.value_ref, right.value_ref, "fsubtmp")
            else
                c.LLVMBuildSub(self.builder, left.value_ref, right.value_ref, "subtmp"),

            .Multiplication => if (isFloatOp)
                c.LLVMBuildFMul(self.builder, left.value_ref, right.value_ref, "fmultmp")
            else
                c.LLVMBuildMul(self.builder, left.value_ref, right.value_ref, "multmp"),

            .Division => if (isFloatOp)
                c.LLVMBuildFDiv(self.builder, left.value_ref, right.value_ref, "fdivtmp")
            else
                c.LLVMBuildSDiv(self.builder, left.value_ref, right.value_ref, "divtmp"),

            .Modulo => if (isFloatOp)
                // En LLVM no hay frem directo, habría que emular con intrinsics o
                // c.LLVMBuildFRem si tu versión de LLVM lo soporta
                // (algunas versiones lo tienen, otras no).
                c.LLVMBuildFRem(self.builder, left.value_ref, right.value_ref, "fremtmp")
            else
                c.LLVMBuildSRem(self.builder, left.value_ref, right.value_ref, "modtmp"),
        };

        // El tipo de la expresión final es float si alguno era float
        const final_type = if (isFloatOp) c.LLVMFloatType() else c.LLVMInt32Type();

        return TypedValue{
            .value_ref = result_value,
            .type_ref = final_type,
        };
    }

    /// Duplica un slice de u8 en un buffer null-terminated (para los símbolos en LLVM).
    fn dupZ(self: *CodeGenerator, src: []const u8) ![]u8 {
        var buffer = try self.allocator.alloc(u8, src.len + 1);
        var i: usize = 0;
        while (i < src.len) : (i += 1) {
            buffer[i] = src[i];
        }
        buffer[src.len] = 0;
        return buffer;
    }
};

fn toLLVMType(t: parser.Type) !llvm.c.LLVMTypeRef {
    switch (t) {
        parser.Type.Int => return c.LLVMInt32Type(),
        parser.Type.Float => return c.LLVMFloatType(),
        else => return Error.InvalidType,
    }
}
