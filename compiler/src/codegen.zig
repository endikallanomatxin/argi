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
        .Bool => c.LLVMInt1Type(),
        .Void => c.LLVMVoidType(),
        .Struct => c.LLVMStructType(null, 0, 0),
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
    symbol_table: std.StringHashMap(Symbol), // tabla actual (global + locals)

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
    }

    // ───── public entry point ───────────────────────────────────────────────
    pub fn generate(self: *CodeGenerator) !llvm.c.LLVMModuleRef {
        // Recorremos todos los nodos top-level (incluye funciones y declaraciones globales)
        for (self.ast.items) |n| {
            _ = self.visitNode(n) catch |e| {
                std.debug.print("Error al compilar: {any}\n", .{e});
                return CodegenError.CompilationFailed;
            };
        }

        // Validación del IR
        var err_msg: [*c]u8 = null;
        if (c.LLVMVerifyModule(self.module, c.LLVMPrintMessageAction, &err_msg) != 0) {
            return CodegenError.ModuleCreationFailed;
        }
        return self.module;
    }

    // ─────────────────────────────────────────────────────────────────── visit
    fn visitNode(self: *CodeGenerator, node: *const sem.SGNode) CodegenError!?TypedValue {
        switch (node.*) {
            .function_declaration => |fd| {
                // std.debug.print("Generando función: {s}\n", .{fd.name});
                try self.genFunction(fd);
                return null;
            },
            .binding_declaration => |bd| {
                // std.debug.print("Generando binding: {s}\n", .{bd.name});
                if (self.symbol_table.contains(bd.name)) {
                    // Si ya está en la tabla → es un “uso” de variable
                    return try self.genBindingUse(bd);
                } else {
                    // Primera vez: hacemos alloca y lo insertamos en la tabla
                    try self.genBindingDecl(bd);
                    return null;
                }
            },
            .binding_assignment => |asgn| {
                // std.debug.print("Generando asignación: {s}\n", .{asgn.sym_id.name});
                _ = try self.genAssignment(asgn);
                return null;
            },
            .binding_use => |bu| {
                // std.debug.print("Generando uso de binding: {s}\n", .{bu.name});
                return try self.genBindingUse(bu);
            },
            .code_block => |cb| {
                // std.debug.print("Generando bloque de código\n", .{});
                try self.genCodeBlock(cb);
                return null;
            },
            .return_statement => |rs| {
                // std.debug.print("Generando retorno\n", .{});
                try self.genReturn(rs);
                return null;
            },
            .value_literal => |vl| {
                // std.debug.print("Generando literal de valor\n", .{});
                return try self.genValueLiteral(&vl);
            },
            .binary_operation => |bo| {
                // std.debug.print("Generando operación binaria\n", .{});
                return try self.genBinaryOp(&bo);
            },
            .if_statement => |ifs| {
                // std.debug.print("Generando if statement\n", .{});
                try self.genIfStatement(ifs);
                return null;
            },
            .function_call => |fc| {
                // std.debug.print("Generando llamada a función: {s}\n", .{fc.callee.name});
                return try self.genFunctionCall(fc);
            },
            .struct_literal => |sl| {
                // std.debug.print("Generando struct literal\n", .{});
                return try self.genStructLiteral(sl);
            },
            else => return CodegenError.UnknownNode,
        }
    }

    // ────────────────────────────────────────────────────────── functions ────
    fn genFunction(self: *CodeGenerator, fd: *sem.FunctionDeclaration) !void {
        // 1) calculamos el tipo de retorno
        const ret_type = if (fd.return_type) |t| switch (t) {
            .builtin => |bt| try builtinToLLVM(bt),
            else => return CodegenError.InvalidType,
        } else c.LLVMVoidType();

        // 2) creamos el LLVMFunctionType con parámetros
        const param_count: usize = fd.params.items.len;
        var param_types: ?[*]llvm.c.LLVMTypeRef = null;
        if (param_count > 0) {
            var tmp = try self.allocator.alloc(llvm.c.LLVMTypeRef, param_count);
            for (fd.params.items, 0..) |p, i| {
                tmp[i] = switch (p.ty) {
                    .builtin => |bt| try builtinToLLVM(bt),
                    else => return CodegenError.InvalidType,
                };
            }
            param_types = @ptrCast(tmp.ptr);
        }
        const fn_type = c.LLVMFunctionType(
            ret_type,
            param_types orelse null,
            @intCast(param_count),
            0,
        );
        const c_name = try self.dupZ(fd.name);
        const fun_ref = c.LLVMAddFunction(self.module, c_name.ptr, fn_type);

        // 3) guardamos la función en la tabla (global)
        try self.symbol_table.put(fd.name, .{
            .cname = c_name,
            .mutability = .constant,
            .type_ref = fn_type,
            .ref = fun_ref,
        });

        // 4) creamos el bloque “entry” y posicionamos el builder ahí
        const entry_bb = c.LLVMAppendBasicBlock(fun_ref, "entry");
        c.LLVMPositionBuilderAtEnd(self.builder, entry_bb);

        // 5) creamos una tabla local “vacía” y copiamos allí todas las entradas actuales
        //    (de ese modo, dentro del cuerpo de la función seguiremos viendo las funciones top-level)

        var old_table = self.symbol_table;
        var new_table = std.StringHashMap(Symbol).init(self.allocator.*);
        // copiamos cada par <clave,value> de old_table a new_table:
        var it = old_table.iterator();
        while (it.next()) |entry| {
            // entry.key_ptr.* es el nombre; entry.value es la struct Symbol con LLVMValueRef, etc.
            _ = try new_table.put(entry.key_ptr.*, entry.value_ptr.*);
        }
        // reemplazamos temporalmente la tabla global por la local “sembrada”
        self.symbol_table = new_table;

        // 6) registrar parámetros en la tabla local
        var idx_param: usize = 0;
        for (fd.params.items) |p| {
            const llvm_ty = switch (p.ty) {
                .builtin => |bt| try builtinToLLVM(bt),
                else => return CodegenError.InvalidType,
            };
            const llvm_param = c.LLVMGetParam(fun_ref, @intCast(idx_param));
            const c_pname = try self.dupZ(p.name);
            c.LLVMSetValueName2(llvm_param, c_pname.ptr, p.name.len);
            const alloca = c.LLVMBuildAlloca(self.builder, llvm_ty, c_pname.ptr);
            _ = c.LLVMBuildStore(self.builder, llvm_param, alloca);
            try self.symbol_table.put(p.name, .{
                .cname = c_pname,
                .mutability = p.mutability,
                .type_ref = llvm_ty,
                .ref = alloca,
            });
            idx_param += 1;
        }

        // allocate return parameters (with defaults if any)
        for (fd.return_params.items) |p| {
            try self.genBindingDecl(p);
        }

        // 7) generamos el cuerpo de la función (ya puede usar both globals + locals)
        try self.genCodeBlock(fd.body);

        // 8) si no se emitió ningún return explícito, usamos los parámetros de retorno
        if (c.LLVMGetBasicBlockTerminator(c.LLVMGetInsertBlock(self.builder)) == null) {
            if (fd.return_params.items.len == 0) {
                if (ret_type == c.LLVMVoidType()) {
                    _ = c.LLVMBuildRetVoid(self.builder);
                } else {
                    _ = c.LLVMBuildRet(self.builder, c.LLVMGetUndef(ret_type));
                }
            } else if (fd.return_params.items.len == 1) {
                const rp = fd.return_params.items[0];
                const sym = self.symbol_table.get(rp.name) orelse return CodegenError.SymbolNotFound;
                const val = c.LLVMBuildLoad2(self.builder, sym.type_ref, sym.ref, sym.cname.ptr);
                _ = c.LLVMBuildRet(self.builder, val);
            } else {
                const count: usize = fd.return_params.items.len;
                var vals = try self.allocator.alloc(llvm.c.LLVMValueRef, count);
                var types = try self.allocator.alloc(llvm.c.LLVMTypeRef, count);
                for (fd.return_params.items, 0..) |rp, i| {
                    const sym = self.symbol_table.get(rp.name) orelse return CodegenError.SymbolNotFound;
                    vals[i] = c.LLVMBuildLoad2(self.builder, sym.type_ref, sym.ref, sym.cname.ptr);
                    types[i] = sym.type_ref;
                }
                const struct_ty = c.LLVMStructType(types.ptr, @intCast(count), 0);
                var agg = c.LLVMGetUndef(struct_ty);
                for (vals, 0..) |v, i| {
                    agg = c.LLVMBuildInsertValue(self.builder, agg, v, @intCast(i), "retfld");
                }
                _ = c.LLVMBuildRet(self.builder, agg);
            }
        }

        // 9) devolvemos la tabla antigua (global) y liberamos la local
        self.symbol_table.deinit();
        self.symbol_table = old_table;
    }

    // ────────────────────────────────────────────────────────── variables ────
    fn genBindingDecl(self: *CodeGenerator, bd: *sem.BindingDeclaration) !void {
        if (self.symbol_table.contains(bd.name))
            return CodegenError.SymbolAlreadyDefined;

        // ── 1.  ¿Hay inicialización?  primero la visitamos ────────────────
        var init_tv_opt: ?TypedValue = null;
        if (bd.initialization) |init_node| {
            init_tv_opt = try self.visitNode(init_node); // ← ①
        }

        // ── 2.  Deducir el tipo LLVM ──────────────────────────────────────
        const llvm_ty: llvm.c.LLVMTypeRef = switch (bd.ty) {
            .builtin => |bt| blk: {
                if (bt == .Struct) {
                    // Si existe inicializador, reaprovechamos SU type_ref.
                    if (init_tv_opt) |tv| {
                        break :blk tv.type_ref; // ← usa el mismo tipo
                    }
                }
                // Para cualquier otro caso delegamos al helper.
                break :blk try builtinToLLVM(bt);
            },
            else => return CodegenError.InvalidType,
        };

        // ── 3.  Reserva y registra en la tabla de símbolos ────────────────
        const c_name = try self.dupZ(bd.name);
        const alloca = c.LLVMBuildAlloca(self.builder, llvm_ty, c_name.ptr);
        try self.symbol_table.put(bd.name, .{
            .cname = c_name,
            .mutability = bd.mutability,
            .type_ref = llvm_ty,
            .ref = alloca,
        });

        // ── 4.  Si había inicialización, almacenar el valor ───────────────
        if (init_tv_opt) |tv| {
            _ = c.LLVMBuildStore(self.builder, tv.value_ref, alloca);
        }
    }

    fn genBindingUse(self: *CodeGenerator, bd: *sem.BindingDeclaration) !TypedValue {
        const sym = self.symbol_table.get(bd.name) orelse return CodegenError.SymbolNotFound;
        const load = c.LLVMBuildLoad2(self.builder, sym.type_ref, sym.ref, sym.cname.ptr);
        return .{ .value_ref = load, .type_ref = sym.type_ref };
    }

    // ───────────────────────────────────────────────────────── assignment ────
    fn genAssignment(self: *CodeGenerator, asgn: *sem.Assignment) !TypedValue {
        const sym = self.symbol_table.get(asgn.sym_id.name) orelse return CodegenError.SymbolNotFound;

        if (sym.mutability == .constant) {
            return CodegenError.ConstantReassignment;
        }
        const rhs_tv_opt = try self.visitNode(asgn.value);
        const rhs_tv = rhs_tv_opt orelse return CodegenError.ValueNotFound;

        var final_val = rhs_tv.value_ref;
        if (sym.type_ref == c.LLVMFloatType() and rhs_tv.type_ref == c.LLVMInt32Type()) {
            final_val = c.LLVMBuildSIToFP(self.builder, rhs_tv.value_ref, sym.type_ref, "int_to_float");
        } else if (sym.type_ref != rhs_tv.type_ref) {
            return CodegenError.InvalidType;
        }
        _ = c.LLVMBuildStore(self.builder, final_val, sym.ref);
        return .{ .value_ref = final_val, .type_ref = sym.type_ref };
    }

    // ────────────────────────────────────────────────────────── literals ─────
    fn genValueLiteral(self: *CodeGenerator, lit: *const sem.ValueLiteral) !TypedValue {
        _ = self; // unused
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

        if (lhs.type_ref == c.LLVMFloatType() and rhs.type_ref == c.LLVMInt32Type()) {
            rhs = .{
                .type_ref = c.LLVMFloatType(),
                .value_ref = c.LLVMBuildSIToFP(self.builder, rhs.value_ref, c.LLVMFloatType(), "int_to_float"),
            };
        } else if (rhs.type_ref == c.LLVMFloatType() and lhs.type_ref == c.LLVMInt32Type()) {
            lhs = .{
                .type_ref = c.LLVMFloatType(),
                .value_ref = c.LLVMBuildSIToFP(self.builder, lhs.value_ref, c.LLVMFloatType(), "int_to_float"),
            };
        }

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
            .equals => if (is_float)
                c.LLVMBuildFCmp(self.builder, c.LLVMRealOEQ, lhs.value_ref, rhs.value_ref, "feq")
            else
                c.LLVMBuildICmp(self.builder, c.LLVMIntEQ, lhs.value_ref, rhs.value_ref, "ieq"),
            .not_equals => if (is_float)
                c.LLVMBuildFCmp(self.builder, c.LLVMRealONE, lhs.value_ref, rhs.value_ref, "fne")
            else
                c.LLVMBuildICmp(self.builder, c.LLVMIntNE, lhs.value_ref, rhs.value_ref, "ine"),
        };
        const ty = switch (bo.operator) {
            .equals, .not_equals => c.LLVMInt1Type(),
            else => lhs.type_ref,
        };
        return .{ .value_ref = val, .type_ref = ty };
    }

    fn genIfStatement(self: *CodeGenerator, ifs: *const sem.IfStatement) !void {
        const cond_tv = (try self.visitNode(ifs.condition)) orelse return CodegenError.ValueNotFound;
        var cond_val = cond_tv.value_ref;
        if (cond_tv.type_ref == c.LLVMFloatType()) {
            const zero = c.LLVMConstReal(c.LLVMFloatType(), 0.0);
            cond_val = c.LLVMBuildFCmp(self.builder, c.LLVMRealONE, cond_val, zero, "ifcond");
        } else if (cond_tv.type_ref == c.LLVMInt32Type()) {
            const zero = c.LLVMConstInt(c.LLVMInt32Type(), 0, 0);
            cond_val = c.LLVMBuildICmp(self.builder, c.LLVMIntNE, cond_val, zero, "ifcond");
        }

        const current_bb = c.LLVMGetInsertBlock(self.builder);
        const func = c.LLVMGetBasicBlockParent(current_bb);

        const then_bb = c.LLVMAppendBasicBlock(func, "then");
        const merge_bb = c.LLVMAppendBasicBlock(func, "ifend");

        var else_bb: ?llvm.c.LLVMBasicBlockRef = null;
        if (ifs.else_block) |_| {
            else_bb = c.LLVMAppendBasicBlock(func, "else");
            _ = c.LLVMBuildCondBr(self.builder, cond_val, then_bb, else_bb.?);
        } else {
            _ = c.LLVMBuildCondBr(self.builder, cond_val, then_bb, merge_bb);
        }

        c.LLVMPositionBuilderAtEnd(self.builder, then_bb);
        try self.genCodeBlock(ifs.then_block);
        if (c.LLVMGetBasicBlockTerminator(then_bb) == null)
            _ = c.LLVMBuildBr(self.builder, merge_bb);

        if (ifs.else_block) |eb| {
            c.LLVMPositionBuilderAtEnd(self.builder, else_bb.?);
            try self.genCodeBlock(eb);
            if (c.LLVMGetBasicBlockTerminator(else_bb.?) == null)
                _ = c.LLVMBuildBr(self.builder, merge_bb);
        }

        c.LLVMPositionBuilderAtEnd(self.builder, merge_bb);
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

    // ──────────────────────────────────────────────────────── function call ───
    fn genFunctionCall(self: *CodeGenerator, fc: *const sem.FunctionCall) CodegenError!?TypedValue {
        const sym = self.symbol_table.get(fc.callee.name) orelse return CodegenError.SymbolNotFound;
        const fun_ref = sym.ref;

        const fn_type = sym.type_ref;
        const ret_ty = c.LLVMGetReturnType(fn_type);
        // --- preparar argumentos ----------------------------------------
        const argc: usize = fc.args.len;

        // Por defecto NULL para cumplir contrato de LLVM
        var args_ptr: ?[*]llvm.c.LLVMValueRef = null;

        if (argc > 0) {
            // Sólo alocamos si de verdad hay argumentos
            var argv = try self.allocator.alloc(llvm.c.LLVMValueRef, argc);

            for (fc.args, 0..) |arg_node, i| {
                const tv = (try self.visitNode(&arg_node)) orelse
                    return CodegenError.ValueNotFound;
                argv[i] = tv.value_ref;
            }
            args_ptr = @ptrCast(argv.ptr); // ahora sí
        }

        // --- emitir llamada ---------------------------------------------
        const call_val = c.LLVMBuildCall2(
            self.builder,
            fn_type,
            fun_ref,
            args_ptr orelse null, // NULL cuando argc == 0
            @intCast(argc),
            "calltmp",
        );

        if (ret_ty == c.LLVMVoidType())
            return null;

        return .{ .value_ref = call_val, .type_ref = ret_ty };
    }

    fn genStructLiteral(self: *CodeGenerator, sl: *const sem.StructLiteral) CodegenError!?TypedValue {
        const field_count: usize = sl.fields.len;
        if (field_count == 0) {
            const ty = c.LLVMStructType(null, 0, 0);
            const val = c.LLVMGetUndef(ty);
            return .{ .value_ref = val, .type_ref = ty };
        }
        var vals = try self.allocator.alloc(llvm.c.LLVMValueRef, field_count);
        var types = try self.allocator.alloc(llvm.c.LLVMTypeRef, field_count);
        for (sl.fields, 0..) |f, i| {
            const tv = (try self.visitNode(f.value)) orelse return CodegenError.ValueNotFound;
            vals[i] = tv.value_ref;
            types[i] = tv.type_ref;
        }
        const ty = c.LLVMStructType(types.ptr, @intCast(field_count), 0);
        const val = c.LLVMConstNamedStruct(ty, vals.ptr, @intCast(field_count));
        return .{ .value_ref = val, .type_ref = ty };
    }
    // ────────────────────────────────────────────────────────── code block ───
    fn genCodeBlock(self: *CodeGenerator, cb: *const sem.CodeBlock) !void {
        for (cb.nodes.items) |n| {
            _ = try self.visitNode(n);
        }
    }

    // ────────────────────────────────────────────────────────── utilities ────
    fn dupZ(self: *CodeGenerator, s: []const u8) ![]u8 {
        const buf = try self.allocator.alloc(u8, s.len + 1);
        std.mem.copyForwards(u8, buf, s);
        buf[s.len] = 0;
        return buf;
    }
};
