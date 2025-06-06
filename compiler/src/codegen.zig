const std = @import("std");
const llvm = @import("llvm.zig");
const c = llvm.c;
const sem = @import("semantic_graph.zig");
const syn = @import("syntax_tree.zig");

// ─────────────────────────────────────────────────────────────────────────────
//  Errors
// ─────────────────────────────────────────────────────────────────────────────
pub const CodegenError = error{
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

// ─────────────────────────────────────────────────────────────────────────────
//  Helpers
// ─────────────────────────────────────────────────────────────────────────────
fn builtinToLLVM(bt: sem.BuiltinType) CodegenError!llvm.c.LLVMTypeRef {
    return switch (bt) {
        .Int32 => c.LLVMInt32Type(),
        .Float32 => c.LLVMFloatType(),
        // Amplía aquí cuando soportes más tipos
        else => CodegenError.InvalidType,
    };
}

// ─────────────────────────────────────────────────────────────────────────────
//  Symbol table entry
// ─────────────────────────────────────────────────────────────────────────────
const Symbol = struct {
    cname: []u8, // null-terminated name
    mutability: syn.Mutability, // .constant | .variable
    type_ref: llvm.c.LLVMTypeRef,
    ref: llvm.c.LLVMValueRef, // alloca ó función
};

// Pequeña tupla “valor + tipo” para expresiones
const TypedValue = struct {
    value_ref: llvm.c.LLVMValueRef,
    type_ref: llvm.c.LLVMTypeRef,
};

// ─────────────────────────────────────────────────────────────────────────────
//  CodeGenerator
// ─────────────────────────────────────────────────────────────────────────────
pub const CodeGenerator = struct {
    allocator: *const std.mem.Allocator,
    ast: std.ArrayList(*sem.SGNode), // nodos raíz
    module: llvm.c.LLVMModuleRef,
    builder: llvm.c.LLVMBuilderRef,
    symbol_table: std.StringHashMap(Symbol), // «scope» actual

    // ───── init / deinit ────────────────────────────────────────────────────
    pub fn init(alloc: *const std.mem.Allocator, ast: std.ArrayList(*sem.SGNode)) !CodeGenerator {
        const m = c.LLVMModuleCreateWithName("argi_module");
        if (m == null) return CodegenError.ModuleCreationFailed;

        const b = c.LLVMCreateBuilder();
        return .{
            .allocator = alloc,
            .ast = ast,
            .module = m,
            .builder = b,
            .symbol_table = std.StringHashMap(Symbol).init(alloc.*),
        };
    }

    pub fn deinit(self: *CodeGenerator) void {
        if (self.builder) |b| c.LLVMDisposeBuilder(b);
        self.symbol_table.deinit();
        // (No liberamos el módulo: déjalo al llamador).
    }

    // ───── public entry point ───────────────────────────────────────────────
    pub fn generate(self: *CodeGenerator) !llvm.c.LLVMModuleRef {
        for (self.ast.items) |n|
            _ = self.visitNode(n) catch |e| {
                std.debug.print("Error al compilar: {any}\n", .{e});
                return CodegenError.CompilationFailed;
            };

        // Validación del IR
        var err_msg: [*c]u8 = null;
        if (c.LLVMVerifyModule(self.module, c.LLVMPrintMessageAction, &err_msg) != 0)
            return CodegenError.ModuleCreationFailed;

        return self.module;
    }

    // ─────────────────────────────────────────────────────────────────── visit
    fn visitNode(self: *CodeGenerator, node: *const sem.SGNode) CodegenError!?TypedValue {
        switch (node.*) {
            .function_declaration => |fd| {
                std.debug.print("Generando función: {s}\n", .{fd.name});
                try self.genFunction(fd);
                return null; // no devuelve valor
            },
            .binding_declaration => |bd| {
                std.debug.print("Generando binding: {s}\n", .{bd.name});
                if (self.symbol_table.contains(bd.name)) {
                    // uso de la variable: cargamos ('load') y devolvemos TypedValue
                    return try self.genBindingUse(bd);
                } else {
                    // primera vez: hacemos alloc y devolvemos null
                    try self.genBindingDecl(bd);
                    return null;
                }
            },
            .binding_assignment => |as| {
                std.debug.print("Generando asignación: {s}\n", .{as.sym_id.name});
                _ = try self.genAssignment(as);
                return null;
            },
            .binding_use => |bu| {
                std.debug.print("Generando uso de binding: {s}\n", .{bu.name});
                // “bu” es un *BindingDeclaration que ya existe en la tabla de símbolos.
                // GenBindingUse cargará (load) el valor y devolverá un TypedValue.
                return try self.genBindingUse(bu);
            },
            .code_block => |cb| {
                std.debug.print("Generando bloque de código\n", .{});
                try self.genCodeBlock(cb);
                return null;
            },
            .return_statement => |rs| {
                std.debug.print("Generando retorno\n", .{});
                try self.genReturn(rs);
                return null;
            },
            .value_literal => |vl| {
                return try self.genValueLiteral(&vl);
            },
            .binary_operation => |bo| {
                return try self.genBinaryOp(&bo);
            },
            .function_call, .if_statement, .while_statement, .for_statement, .switch_statement, .break_statement, .continue_statement => return CodegenError.NotYetImplemented,
            else => return CodegenError.UnknownNode,
        }
    }

    // ────────────────────────────────────────────────────────── functions ────
    fn genFunction(self: *CodeGenerator, fd: *sem.FunctionDeclaration) !void {
        const ret_type = if (fd.return_type) |t|
            switch (t) {
                .builtin => |bt| try builtinToLLVM(bt),
                else => return CodegenError.InvalidType,
            }
        else
            c.LLVMVoidType();

        const fn_type = c.LLVMFunctionType(ret_type, null, 0, 0);
        const c_name = try self.dupZ(fd.name);
        const fun_ref = c.LLVMAddFunction(self.module, c_name.ptr, fn_type);

        // guarda símbolo global
        try self.symbol_table.put(fd.name, .{
            .cname = c_name,
            .mutability = .constant,
            .type_ref = fn_type,
            .ref = fun_ref,
        });

        // CREAMOS el bloque "entry":
        const entry = c.LLVMAppendBasicBlock(fun_ref, "entry");
        // NOTA: ya no guardamos/restauramos old_bb. Simplemente posicionamos el builder ahí:
        c.LLVMPositionBuilderAtEnd(self.builder, entry);

        // scope local
        const old_table = self.symbol_table;
        self.symbol_table = std.StringHashMap(Symbol).init(self.allocator.*);

        try self.genCodeBlock(fd.body);

        // Si el cuerpo no devuelve, añade un `ret void` o `ret undef`
        if (c.LLVMGetBasicBlockTerminator(entry) == null) {
            if (ret_type == c.LLVMVoidType()) {
                _ = c.LLVMBuildRetVoid(self.builder);
            } else {
                _ = c.LLVMBuildRet(self.builder, c.LLVMGetUndef(ret_type));
            }
        }

        // liberamos la simbol table local y restauramos la de nivel superior:
        self.symbol_table.deinit();
        self.symbol_table = old_table;
    }

    // ────────────────────────────────────────────────────────── variables ────
    fn genBindingDecl(self: *CodeGenerator, bd: *sem.BindingDeclaration) !void {
        if (self.symbol_table.contains(bd.name))
            return CodegenError.SymbolAlreadyDefined;

        const llvm_ty = switch (bd.ty) {
            .builtin => |bt| try builtinToLLVM(bt),
            else => return CodegenError.InvalidType,
        };

        const c_name = try self.dupZ(bd.name);
        const alloca = c.LLVMBuildAlloca(self.builder, llvm_ty, c_name.ptr);

        try self.symbol_table.put(bd.name, .{
            .cname = c_name,
            .mutability = bd.mutability,
            .type_ref = llvm_ty,
            .ref = alloca,
        });

        // inicialización implícita
        if (bd.initialization) |init_node| {
            // Evaluar la expresión del inicializador:
            const init_tv_opt = try self.visitNode(init_node);
            const init_tv = init_tv_opt orelse return CodegenError.ValueNotFound;

            var store_val = init_tv.value_ref;
            // Si la variable es Float32 y el literal vino como Int32, hacemos SICast:
            if (llvm_ty == c.LLVMFloatType() and init_tv.type_ref == c.LLVMInt32Type()) {
                store_val = c.LLVMBuildSIToFP(self.builder, init_tv.value_ref, llvm_ty, "int_to_float");
            } else if (init_tv.type_ref != llvm_ty) {
                return CodegenError.InvalidType;
            }
            // Ahora sí, “almacenamos” directamente el valor en el alloca recién creado:
            _ = c.LLVMBuildStore(self.builder, store_val, alloca);
        }
    }

    fn genBindingUse(self: *CodeGenerator, bd: *sem.BindingDeclaration) !TypedValue {
        const sym = self.symbol_table.get(bd.name) orelse return CodegenError.SymbolNotFound;
        const load = c.LLVMBuildLoad2(self.builder, sym.type_ref, sym.ref, sym.cname.ptr);
        return .{ .value_ref = load, .type_ref = sym.type_ref };
    }

    // ───────────────────────────────────────────────────────── assignment ────
    fn genAssignment(self: *CodeGenerator, as: *sem.Assignment) !TypedValue {
        const sym = self.symbol_table.get(as.sym_id.name) orelse return CodegenError.SymbolNotFound;

        if (sym.mutability == .constant)
            return CodegenError.ConstantReassignment;

        const rhs_tv_opt = try self.visitNode(as.value);
        const rhs_tv = rhs_tv_opt orelse return CodegenError.ValueNotFound;

        var final_val = rhs_tv.value_ref;

        // cast implícito int→float
        if (sym.type_ref == c.LLVMFloatType() and
            rhs_tv.type_ref == c.LLVMInt32Type())
        {
            final_val = c.LLVMBuildSIToFP(self.builder, rhs_tv.value_ref, sym.type_ref, "int_to_float");
        } else if (sym.type_ref != rhs_tv.type_ref) {
            return CodegenError.InvalidType;
        }

        _ = c.LLVMBuildStore(self.builder, final_val, sym.ref);
        return .{ .value_ref = final_val, .type_ref = sym.type_ref };
    }

    // ────────────────────────────────────────────────────────── literals ─────
    fn genValueLiteral(self: *CodeGenerator, lit: *const sem.ValueLiteral) !TypedValue {
        _ = self; // ← evitar “unused parameter”
        return switch (lit.*) {
            .int_literal => |v| .{
                .type_ref = c.LLVMInt32Type(),
                .value_ref = c.LLVMConstInt(c.LLVMInt32Type(), @intCast(v), 0),
            },
            .float_literal => |f| .{
                .type_ref = c.LLVMFloatType(),
                .value_ref = c.LLVMConstReal(c.LLVMFloatType(), f),
            },
            else => CodegenError.NotYetImplemented,
        };
    }

    // ───────────────────────────────────────────────────────── binary op ─────
    fn genBinaryOp(self: *CodeGenerator, bo: *const sem.BinaryOperation) !TypedValue {
        var lhs = (try self.visitNode(bo.left)) orelse return CodegenError.ValueNotFound;
        var rhs = (try self.visitNode(bo.right)) orelse return CodegenError.ValueNotFound;

        // promote int→float si hace falta
        if (lhs.type_ref == c.LLVMFloatType() and rhs.type_ref == c.LLVMInt32Type())
            rhs = .{
                .type_ref = c.LLVMFloatType(),
                .value_ref = c.LLVMBuildSIToFP(self.builder, rhs.value_ref, c.LLVMFloatType(), "int_to_float"),
            }
        else if (rhs.type_ref == c.LLVMFloatType() and lhs.type_ref == c.LLVMInt32Type())
            lhs = .{
                .type_ref = c.LLVMFloatType(),
                .value_ref = c.LLVMBuildSIToFP(self.builder, lhs.value_ref, c.LLVMFloatType(), "int_to_float"),
            };

        const is_float = lhs.type_ref == c.LLVMFloatType();
        const val = switch (bo.operator) {
            .addition => if (is_float)
                c.LLVMBuildFAdd(self.builder, lhs.value_ref, rhs.value_ref, "fadd")
            else
                c.LLVMBuildAdd(self.builder, lhs.value_ref, rhs.value_ref, "iadd"),
            .subtraction => if (is_float)
                c.LLVMBuildFSub(self.builder, lhs.value_ref, rhs.value_ref, "fsub")
            else
                c.LLVMBuildSub(self.builder, lhs.value_ref, rhs.value_ref, "isub"),
            .multiplication => if (is_float)
                c.LLVMBuildFMul(self.builder, lhs.value_ref, rhs.value_ref, "fmul")
            else
                c.LLVMBuildMul(self.builder, lhs.value_ref, rhs.value_ref, "imul"),
            .division => if (is_float)
                c.LLVMBuildFDiv(self.builder, lhs.value_ref, rhs.value_ref, "fdiv")
            else
                c.LLVMBuildSDiv(self.builder, lhs.value_ref, rhs.value_ref, "idiv"),
            .modulo => if (is_float)
                c.LLVMBuildFRem(self.builder, lhs.value_ref, rhs.value_ref, "frem")
            else
                c.LLVMBuildSRem(self.builder, lhs.value_ref, rhs.value_ref, "irem"),
        };

        return .{ .value_ref = val, .type_ref = lhs.type_ref };
    }

    // ─────────────────────────────────────────────────────────── return ──────
    fn genReturn(self: *CodeGenerator, rs: *sem.ReturnStatement) !void {
        if (rs.expression) |e| {
            const tv_opt = try self.visitNode(e);
            if (tv_opt) |tv| {
                _ = c.LLVMBuildRet(self.builder, tv.value_ref);
                return;
            }
            return CodegenError.ValueNotFound;
        }
        _ = c.LLVMBuildRetVoid(self.builder);
    }

    // ────────────────────────────────────────────────────────── code block ───
    fn genCodeBlock(self: *CodeGenerator, cb: *const sem.CodeBlock) !void {
        for (cb.nodes.items) |n| _ = try self.visitNode(n);
    }

    // ────────────────────────────────────────────────────────── utilities ────
    fn dupZ(self: *CodeGenerator, s: []const u8) ![]u8 {
        const buf = try self.allocator.alloc(u8, s.len + 1);
        std.mem.copyForwards(u8, buf, s);
        buf[s.len] = 0;
        return buf;
    }
};
