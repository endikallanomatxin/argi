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
};

/// Representa una entrada de símbolo (variable o función) en la tabla de símbolos.
const Symbol = struct {
    cname: []u8,
    mutability: parser.Mutability,
    llvm_type: llvm.c.LLVMTypeRef,
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
    fn visitNode(self: *CodeGenerator, node: *parser.ASTNode) Error!?c.LLVMValueRef {
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
        _ = try self.genCodeBlock(decl.value.codeBlock);

        // Restauramos la posición original del builder
        if (oldBlock) |ob| {
            c.LLVMPositionBuilderAtEnd(self.builder, ob);
        }
    }

    /// Genera IR para una variable o constante en ámbito local.
    fn genVarOrConstDeclaration(self: *CodeGenerator, decl: *parser.Declaration) !void {
        const c_name = try self.dupZ(decl.name);

        // Verificamos redefiniciones por ahora
        if (self.symbol_table.contains(decl.name)) {
            return Error.SymbolAlreadyDefined;
        }

        // Generamos la expresión asociada al valor
        const value = try self.visitNode(decl.value);

        // Por simplicidad, asumimos i32
        // TODO: soportar más tipos o inferirlo dinámicamente
        const i32_type = c.LLVMInt32Type();

        // Alloca en la función actual
        const alloc = c.LLVMBuildAlloca(self.builder, i32_type, c_name.ptr);

        // Guardamos el símbolo
        try self.symbol_table.put(
            decl.name,
            Symbol{
                .cname = c_name,
                .mutability = decl.mutability,
                .llvm_type = i32_type,
                .value_ref = alloc,
            },
        );

        // Almacenar el valor inicial en la variable
        if (value) |v| {
            _ = c.LLVMBuildStore(self.builder, v, alloc);
        } else {
            return Error.ValueNotFound;
        }
    }

    /// Genera IR para una asignación: busca la variable y almacena el nuevo valor.
    fn genAssignment(self: *CodeGenerator, assign: *parser.Assignment) !llvm.c.LLVMValueRef {
        const symbol = self.symbol_table.get(assign.name);
        if (symbol) |s| {
            if (s.mutability == parser.Mutability.Const) {
                return Error.ConstantReassignment;
            }
            const val = try self.visitNode(assign.value);
            if (val) |v| {
                _ = c.LLVMBuildStore(self.builder, v, s.value_ref);
                return v;
            } else {
                return Error.ValueNotFound;
            }
        } else {
            return Error.SymbolNotFound;
        }
    }

    /// Genera IR para una instrucción return: `return <expr?>`.
    fn genReturn(self: *CodeGenerator, retStmt: *parser.ReturnStmt) !void {
        if (retStmt.expression) |expr| {
            const val = try self.visitNode(expr);
            if (val) |v| {
                _ = c.LLVMBuildRet(self.builder, v);
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
    fn genValueLiteral(self: *CodeGenerator, valLit: *parser.ValueLiteral) !llvm.c.LLVMValueRef {
        _ = self;
        switch (valLit.*) {
            .intLiteral => |intLitPtr| {
                const i32_type = c.LLVMInt32Type();
                // Devolvemos la constante entera
                return c.LLVMConstInt(i32_type, @bitCast(intLitPtr.value), 0);
            },
            else => {
                // En esta demo, si no es int, devolvemos un "void" nulo
                return c.LLVMConstNull(c.LLVMVoidType());
            },
        }
    }

    /// Genera IR para un identificador: realiza un load de la variable.
    fn genIdentifier(self: *CodeGenerator, ident: []const u8) !llvm.c.LLVMValueRef {
        const symbol = self.symbol_table.get(ident);
        if (symbol) |s| {
            return c.LLVMBuildLoad2(
                self.builder,
                s.llvm_type,
                s.value_ref,
                s.cname.ptr,
            );
        } else {
            return Error.SymbolNotFound;
        }
    }

    /// Genera IR para una operación binaria aritmética.
    fn genBinaryOperation(self: *CodeGenerator, binOpPtr: *parser.BinaryOperation) !llvm.c.LLVMValueRef {
        const left = try self.visitNode(binOpPtr.left);
        const right = try self.visitNode(binOpPtr.right);

        if (left) |l| {
            if (right) |r| {
                switch (binOpPtr.operator) {
                    .Addition => {
                        return c.LLVMBuildAdd(self.builder, l, r, "addtmp");
                    },
                    .Subtraction => {
                        return c.LLVMBuildSub(self.builder, l, r, "subtmp");
                    },
                    .Multiplication => {
                        return c.LLVMBuildMul(self.builder, l, r, "multmp");
                    },
                    .Division => {
                        return c.LLVMBuildSDiv(self.builder, l, r, "divtmp");
                    },
                    .Modulo => {
                        return c.LLVMBuildSRem(self.builder, l, r, "modtmp");
                    },
                }
            } else {
                return Error.ValueNotFound;
            }
        } else {
            return Error.ValueNotFound;
        }
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
