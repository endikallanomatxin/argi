const std = @import("std");
const llvm = @import("llvm.zig");
const c = llvm.c;
const sem = @import("semantic_graph.zig");
const syn = @import("syntax_tree.zig");

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

// ────────────────────────────────────────────── helpers ──
const Symbol = struct {
    cname: []u8,
    mutability: syn.Mutability,
    type_ref: llvm.c.LLVMTypeRef,
    ref: llvm.c.LLVMValueRef, // alloca ó función
    initialized: bool = false, // para bindings
};

const TypedValue = struct {
    value_ref: llvm.c.LLVMValueRef,
    type_ref: llvm.c.LLVMTypeRef,
};

// ────────────────────────────────────────────── CodeGenerator ──
pub const CodeGenerator = struct {
    allocator: *const std.mem.Allocator,
    ast: []const *sem.SGNode,
    module: llvm.c.LLVMModuleRef,
    builder: llvm.c.LLVMBuilderRef,
    symbol_table: std.StringHashMap(Symbol),
    current_ret_type: ?llvm.c.LLVMTypeRef = null, // para funciones

    // ── init / deinit ─────────────────────────
    pub fn init(a: *const std.mem.Allocator, ast: []const *sem.SGNode) !CodeGenerator {
        const m = c.LLVMModuleCreateWithName("argi_module");
        if (m == null) return CodegenError.ModuleCreationFailed;
        const b = c.LLVMCreateBuilder();
        return .{
            .allocator = a,
            .ast = ast,
            .module = m,
            .builder = b,
            .symbol_table = std.StringHashMap(Symbol).init(a.*),
        };
    }

    pub fn deinit(self: *CodeGenerator) void {
        if (self.builder) |b| c.LLVMDisposeBuilder(b);
        self.symbol_table.deinit();
    }

    // ── top-level drive ───────────────────────
    pub fn generate(self: *CodeGenerator) !llvm.c.LLVMModuleRef {
        for (self.ast) |n|
            _ = self.visitNode(n) catch |e| {
                std.debug.print("codegen error: {any}\n", .{e});
                return CodegenError.CompilationFailed;
            };

        if (c.LLVMVerifyModule(self.module, c.LLVMPrintMessageAction, null) != 0)
            return CodegenError.ModuleCreationFailed;
        return self.module;
    }

    // ────────────────────────────────────────── visitor dispatch ──
    fn visitNode(self: *CodeGenerator, n: *const sem.SGNode) CodegenError!?TypedValue {
        return switch (n.*) {
            .function_declaration => |f| {
                try self.genFunction(f);
                return null;
            },
            .binding_declaration => |b| {
                if (self.symbol_table.contains(b.name))
                    return try self.genBindingUse(b);
                try self.genBindingDecl(b);
                return null;
            },
            .binding_assignment => |a| {
                _ = try self.genAssignment(a);
                return null;
            },
            .binding_use => |b| try self.genBindingUse(b),
            .code_block => |cb| {
                try self.genCodeBlock(cb);
                return null;
            },
            .return_statement => |r| {
                try self.genReturn(r);
                return null;
            },
            .value_literal => |v| try self.genValueLiteral(&v),
            .binary_operation => |bo| try self.genBinaryOp(&bo),
            .if_statement => |ifs| {
                try self.genIfStatement(ifs);
                return null;
            },
            .function_call => |fc| try self.genFunctionCall(fc),
            .struct_value_literal => |sl| try self.genStructValueLiteral(sl),
            .struct_field_access => |sfa| try self.genStructFieldAccess(sfa),
            else => CodegenError.UnknownNode,
        };
    }
    // ────────────────────────────────────────────── type lowering ──
    fn toLLVMType(self: *CodeGenerator, t: sem.Type) CodegenError!llvm.c.LLVMTypeRef {
        return switch (t) {
            .builtin => |bt| switch (bt) {
                .Int8 => c.LLVMInt8Type(),
                .Int16 => c.LLVMInt16Type(),
                .Int32 => c.LLVMInt32Type(),
                .Int64 => c.LLVMInt64Type(),
                .UInt8 => c.LLVMInt8Type(), // Checkear lo de signed o unsigned.
                .UInt16 => c.LLVMInt16Type(),
                .UInt32 => c.LLVMInt32Type(),
                .UInt64 => c.LLVMInt64Type(),
                .Float16 => c.LLVMHalfType(),
                .Float32 => c.LLVMFloatType(),
                .Float64 => c.LLVMDoubleType(),
                .Char => c.LLVMInt8Type(),
                .Bool => c.LLVMInt1Type(),
                .Void => c.LLVMVoidType(),
            },
            .struct_type => |st| blk: {
                // Anonymous struct generation with the given fields
                var fields = try self.allocator.alloc(llvm.c.LLVMTypeRef, st.fields.len);
                for (st.fields, 0..) |f, i| {
                    fields[i] = try self.toLLVMType(f.ty);
                }
                const struct_ty = c.LLVMStructType(fields.ptr, @intCast(st.fields.len), 0);

                // Set the field names if available
                if (st.fields.len > 0) {
                    c.LLVMStructSetBody(struct_ty, fields.ptr, @intCast(st.fields.len), 0);
                }
                break :blk struct_ty;
            },
        };
    }

    fn genFunction(self: *CodeGenerator, f: *sem.FunctionDeclaration) !void {
        // 1) Input and return types
        const input_type = try self.toLLVMType(.{ .struct_type = &f.input });
        const return_type = try self.toLLVMType(.{ .struct_type = &f.output });

        // 3) creación de la función
        const fn_ty = c.LLVMFunctionType(
            return_type,
            blk: {
                var arr = try self.allocator.alloc(llvm.c.LLVMTypeRef, 1);
                arr[0] = input_type;
                break :blk arr.ptr;
            },
            1,
            0,
        );
        const cname = try self.dupZ(f.name);
        const fn_ref = c.LLVMAddFunction(self.module, cname.ptr, fn_ty);
        try self.symbol_table.put(f.name, .{ .cname = cname, .mutability = .constant, .type_ref = fn_ty, .ref = fn_ref });

        // 4) entry-bb & builder
        const entry_bb = c.LLVMAppendBasicBlock(fn_ref, "entry");
        c.LLVMPositionBuilderAtEnd(self.builder, entry_bb);

        // 5) tabla de símbolos local (copia de la global)
        var previous_symbol_table = self.symbol_table;
        var local_symbol_table = std.StringHashMap(Symbol).init(self.allocator.*);
        var it = previous_symbol_table.iterator();
        while (it.next()) |e| _ = try local_symbol_table.put(e.key_ptr.*, e.value_ptr.*);
        self.symbol_table = local_symbol_table;
        defer self.symbol_table = previous_symbol_table;
        defer local_symbol_table.deinit();

        const prev_rt = self.current_ret_type;
        self.current_ret_type = return_type;
        defer self.current_ret_type = prev_rt;

        // 6) registrar args en la tabla local
        for (f.input.fields) |field| {
            // Generate binding declaration for each input parameter
            const binding_declaration = sem.BindingDeclaration{
                .name = field.name,
                .mutability = syn.Mutability.constant,
                .ty = field.ty,
                .initialization = null, // No initialization for input params
            };
            try self.genBindingDecl(&binding_declaration);
        }

        // 7) extraer los parámetros de entrada
        const param_agg = c.LLVMGetParam(fn_ref, 0);
        for (f.input.fields, 0..) |field, idx| {
            const sym_ptr = self.symbol_table.getPtr(field.name) orelse
                return CodegenError.SymbolNotFound;

            const elem =
                c.LLVMBuildExtractValue(self.builder, param_agg, @intCast(idx), "arg.extract");
            _ = c.LLVMBuildStore(self.builder, elem, sym_ptr.*.ref);
            sym_ptr.*.initialized = true; // ahora sí está inicializado
        }

        // 8) registrar args de retorno en la tabla local
        for (f.output.fields) |field| {
            // Generate binding declaration for each output parameter
            const binding_declaration = sem.BindingDeclaration{
                .name = field.name,
                .mutability = syn.Mutability.variable,
                .ty = field.ty,
                .initialization = null, // No initialization for output params
            };
            try self.genBindingDecl(&binding_declaration);
        }

        // 7) código del cuerpo
        try self.genCodeBlock(f.body);

        // 8) Gestionar la ausencia de return explícito
        const cur_bb = c.LLVMGetInsertBlock(self.builder);
        if (c.LLVMGetBasicBlockTerminator(cur_bb) == null) {
            if (return_type == c.LLVMVoidType()) {
                _ = c.LLVMBuildRetVoid(self.builder);
            } else {
                // Construir el struct de retorno a partir de los parámetros de salida
                const field_cnt = f.output.fields.len;
                var vals = try self.allocator.alloc(llvm.c.LLVMValueRef, field_cnt);

                for (f.output.fields, 0..) |fld, i| {
                    const sym = self.symbol_table.get(fld.name) orelse
                        return CodegenError.SymbolNotFound;
                    vals[i] = c.LLVMBuildLoad2(self.builder, sym.type_ref, sym.ref, sym.cname.ptr);
                }

                // LLVM no permite crear un struct "const" con valores en tiempo de
                // ejecución, así que construimos uno dinámicamente:
                var ret_val = c.LLVMGetUndef(return_type);
                for (vals, 0..) |v, i| {
                    ret_val = c.LLVMBuildInsertValue(self.builder, ret_val, v, @intCast(i), "ret.agg");
                }
                _ = c.LLVMBuildRet(self.builder, ret_val);
            }
        }
    }

    // ────────────────────────────────────────── bindings ──
    fn genBindingDecl(self: *CodeGenerator, b: *const sem.BindingDeclaration) !void {
        if (self.symbol_table.contains(b.name))
            return CodegenError.SymbolAlreadyDefined;

        // 1) posible inicialización
        var init_tv: ?TypedValue = null;
        if (b.initialization) |n|
            init_tv = try self.visitNode(n);

        // 2) tipo declarado (siempre está resuelto por el semantizador)
        const llvm_decl_ty = try self.toLLVMType(b.ty);

        // 3) reserva de espacio
        const cname = try self.dupZ(b.name);
        const alloca = c.LLVMBuildAlloca(self.builder, llvm_decl_ty, cname.ptr);

        // 4) registrar en la tabla
        try self.symbol_table.put(b.name, .{
            .cname = cname,
            .mutability = b.mutability,
            .type_ref = llvm_decl_ty,
            .ref = alloca,
            .initialized = init_tv != null,
        });

        // 5) almacenar valor inicial, manejando struct-parciales
        if (init_tv) |tv| {
            if (tv.type_ref == llvm_decl_ty) {
                // tipos idénticos → copiar tal cual
                _ = c.LLVMBuildStore(self.builder, tv.value_ref, alloca);
            } else if (c.LLVMGetTypeKind(tv.type_ref) == c.LLVMStructTypeKind and
                c.LLVMGetTypeKind(llvm_decl_ty) == c.LLVMStructTypeKind)
            {
                // El literal proporciona solo un subconjunto de campos:
                // construimos un agregado del tamaño correcto, rellenando
                // con `undef` los campos faltantes.
                var agg = c.LLVMGetUndef(llvm_decl_ty);

                const provided_cnt = c.LLVMCountStructElementTypes(tv.type_ref);
                var idx: u32 = 0;
                while (idx < provided_cnt) : (idx += 1) {
                    const elem = c.LLVMBuildExtractValue(
                        self.builder,
                        tv.value_ref,
                        idx,
                        "init.extract",
                    );
                    agg = c.LLVMBuildInsertValue(
                        self.builder,
                        agg,
                        elem,
                        idx,
                        "init.insert",
                    );
                }

                // después de haber copiado los que sí aporta el literal…
                var i: u32 = provided_cnt;
                while (i < c.LLVMCountStructElementTypes(llvm_decl_ty)) : (i += 1) {
                    // 1) buscamos si el campo i tiene default_value semántico
                    const field_sem = b.ty.struct_type.fields[i];
                    if (field_sem.default_value) |dflt_node| {
                        // evaluamos el nodo (debería dar un TypedValue constante)
                        const tv_default = (try self.visitNode(dflt_node)).?;
                        agg = c.LLVMBuildInsertValue(self.builder, agg, tv_default.value_ref, i, "init.default");
                    } else {
                        // 2) si no hay default explícito ya dejamos el `undef` (comporta‐miento previo)
                        agg = c.LLVMBuildInsertValue(self.builder, agg, c.LLVMGetUndef(c.LLVMStructGetTypeAtIndex(llvm_decl_ty, i)), i, "init.undef");
                    }
                }

                _ = c.LLVMBuildStore(self.builder, agg, alloca);
            } else {
                return CodegenError.InvalidType;
            }
        }
    }

    fn genBindingUse(self: *CodeGenerator, b: *sem.BindingDeclaration) !TypedValue {
        const sym = self.symbol_table.get(b.name) orelse return CodegenError.SymbolNotFound;
        const val = c.LLVMBuildLoad2(self.builder, sym.type_ref, sym.ref, sym.cname.ptr);
        return .{ .value_ref = val, .type_ref = sym.type_ref };
    }

    // ────────────────────────────────────────── assignment ──
    fn genAssignment(self: *CodeGenerator, a: *sem.Assignment) !TypedValue {
        const sym_ptr = self.symbol_table.getPtr(a.sym_id.name) orelse return CodegenError.SymbolNotFound;

        // Const sólo falla si *ya* estaba inicializado
        if (sym_ptr.*.mutability == .constant and sym_ptr.*.initialized)
            return CodegenError.ConstantReassignment;

        const rhs = (try self.visitNode(a.value)) orelse return CodegenError.ValueNotFound;
        var rhs_val = rhs.value_ref;
        var rhs_ty = rhs.type_ref;

        if (sym_ptr.*.type_ref != rhs_ty and
            c.LLVMGetTypeKind(rhs_ty) == c.LLVMStructTypeKind)
        {
            const field_count = c.LLVMCountStructElementTypes(rhs_ty);

            var i: u32 = 0;
            var extracted: bool = false;
            while (i < field_count) : (i += 1) {
                const fty = c.LLVMStructGetTypeAtIndex(rhs_ty, i);
                if (fty == sym_ptr.*.type_ref) {
                    rhs_val = c.LLVMBuildExtractValue(self.builder, rhs_val, i, "tmp.unpack");
                    rhs_ty = fty;
                    extracted = true;
                    break;
                }
            }

            // Si no encontramos ninguno que coincida dejamos que la comprobación
            // de tipo más abajo lance `InvalidType`.
            if (!extracted) {}
        }

        if (sym_ptr.*.type_ref != rhs_ty)
            return CodegenError.InvalidType;

        _ = c.LLVMBuildStore(self.builder, rhs.value_ref, sym_ptr.*.ref);
        sym_ptr.*.initialized = true; // primera y única escritura para const
        return .{ .value_ref = rhs.value_ref, .type_ref = sym_ptr.*.type_ref };
    }

    // ────────────────────────────────────────── literals ──
    fn genValueLiteral(self: *CodeGenerator, l: *const sem.ValueLiteral) !TypedValue {
        _ = self;
        return switch (l.*) {
            .int_literal => |v| .{ .type_ref = c.LLVMInt32Type(), .value_ref = c.LLVMConstInt(c.LLVMInt32Type(), @intCast(v), 0) },
            .float_literal => |f| .{ .type_ref = c.LLVMFloatType(), .value_ref = c.LLVMConstReal(c.LLVMFloatType(), f) },
            else => CodegenError.NotYetImplemented,
        };
    }

    // ────────────────────────────────────────── binary-op (sin coerciones) ──
    fn genBinaryOp(self: *CodeGenerator, bo: *const sem.BinaryOperation) !TypedValue {
        const lhs = (try self.visitNode(bo.left)) orelse return CodegenError.ValueNotFound;
        const rhs = (try self.visitNode(bo.right)) orelse return CodegenError.ValueNotFound;

        const is_float = lhs.type_ref == c.LLVMFloatType();
        const val = switch (bo.operator) {
            .addition => if (is_float) c.LLVMBuildFAdd(self.builder, lhs.value_ref, rhs.value_ref, "add") else c.LLVMBuildAdd(self.builder, lhs.value_ref, rhs.value_ref, "add"),
            .subtraction => if (is_float) c.LLVMBuildFSub(self.builder, lhs.value_ref, rhs.value_ref, "sub") else c.LLVMBuildSub(self.builder, lhs.value_ref, rhs.value_ref, "sub"),
            .multiplication => if (is_float) c.LLVMBuildFMul(self.builder, lhs.value_ref, rhs.value_ref, "mul") else c.LLVMBuildMul(self.builder, lhs.value_ref, rhs.value_ref, "mul"),
            .division => if (is_float) c.LLVMBuildFDiv(self.builder, lhs.value_ref, rhs.value_ref, "div") else c.LLVMBuildSDiv(self.builder, lhs.value_ref, rhs.value_ref, "div"),
            .modulo => if (is_float) c.LLVMBuildFRem(self.builder, lhs.value_ref, rhs.value_ref, "rem") else c.LLVMBuildSRem(self.builder, lhs.value_ref, rhs.value_ref, "rem"),
            .equals => if (is_float) c.LLVMBuildFCmp(self.builder, c.LLVMRealOEQ, lhs.value_ref, rhs.value_ref, "eq") else c.LLVMBuildICmp(self.builder, c.LLVMIntEQ, lhs.value_ref, rhs.value_ref, "eq"),
            .not_equals => if (is_float) c.LLVMBuildFCmp(self.builder, c.LLVMRealONE, lhs.value_ref, rhs.value_ref, "ne") else c.LLVMBuildICmp(self.builder, c.LLVMIntNE, lhs.value_ref, rhs.value_ref, "ne"),
        };

        const out_ty = switch (bo.operator) {
            .equals, .not_equals => c.LLVMInt1Type(),
            else => lhs.type_ref,
        };
        return .{ .value_ref = val, .type_ref = out_ty };
    }

    // ────────────────────────────────────────── if ──
    fn genIfStatement(self: *CodeGenerator, i: *const sem.IfStatement) !void {
        const cond_tv = (try self.visitNode(i.condition)) orelse return CodegenError.ValueNotFound;
        const cond_val = cond_tv.value_ref;

        const cur_bb = c.LLVMGetInsertBlock(self.builder);
        const fnc = c.LLVMGetBasicBlockParent(cur_bb);
        const thenB = c.LLVMAppendBasicBlock(fnc, "then");
        const endB = c.LLVMAppendBasicBlock(fnc, "ifend");
        const elseB = if (i.else_block) |_|
            c.LLVMAppendBasicBlock(fnc, "else")
        else
            null;

        _ = c.LLVMBuildCondBr(self.builder, cond_val, thenB, elseB orelse endB);

        c.LLVMPositionBuilderAtEnd(self.builder, thenB);
        try self.genCodeBlock(i.then_block);
        if (c.LLVMGetBasicBlockTerminator(thenB) == null)
            _ = c.LLVMBuildBr(self.builder, endB);

        if (i.else_block) |eb| {
            c.LLVMPositionBuilderAtEnd(self.builder, elseB.?);
            try self.genCodeBlock(eb);
            if (c.LLVMGetBasicBlockTerminator(elseB.?) == null)
                _ = c.LLVMBuildBr(self.builder, endB);
        }
        c.LLVMPositionBuilderAtEnd(self.builder, endB);
    }

    // ────────────────────────────────────────── return ──
    fn genReturn(self: *CodeGenerator, r: *sem.ReturnStatement) !void {
        if (r.expression) |e| {
            const tv = (try self.visitNode(e)) orelse return CodegenError.ValueNotFound;

            const ret_ty = self.current_ret_type orelse return CodegenError.InvalidType;

            // caso “coincide tal cual”
            if (ret_ty == tv.type_ref) {
                _ = c.LLVMBuildRet(self.builder, tv.value_ref);
                return;
            }

            // caso “struct de 1 campo” y ese campo coincide
            if (c.LLVMGetTypeKind(ret_ty) == c.LLVMStructTypeKind and
                c.LLVMCountStructElementTypes(ret_ty) == 1 and
                c.LLVMStructGetTypeAtIndex(ret_ty, 0) == tv.type_ref)
            {
                var agg = c.LLVMGetUndef(ret_ty);
                agg = c.LLVMBuildInsertValue(self.builder, agg, tv.value_ref, 0, "ret.pack");
                _ = c.LLVMBuildRet(self.builder, agg);
                return;
            }

            return CodegenError.InvalidType;
        }

        _ = c.LLVMBuildRetVoid(self.builder);
    }

    // ────────────────────────────────────────── call ──
    fn genFunctionCall(self: *CodeGenerator, fc: *const sem.FunctionCall) CodegenError!?TypedValue {
        const sym = self.symbol_table.get(fc.callee.name) orelse
            return CodegenError.SymbolNotFound;
        const fn_ty = sym.type_ref;
        const ret_ty = c.LLVMGetReturnType(fn_ty);

        // único parámetro
        var argv = try self.allocator.alloc(llvm.c.LLVMValueRef, 1);
        argv[0] = (try self.visitNode(fc.input)).?.value_ref;

        const call_val = c.LLVMBuildCall2(
            self.builder,
            fn_ty,
            sym.ref,
            argv.ptr,
            1,
            "call",
        );

        return if (ret_ty == c.LLVMVoidType())
            null
        else
            .{ .value_ref = call_val, .type_ref = ret_ty };
    }

    // ────────────────────────────────────────── struct literal ──
    fn genStructValueLiteral(self: *CodeGenerator, sl: *const sem.StructValueLiteral) !?TypedValue {
        const cnt = sl.fields.len;
        var vals = try self.allocator.alloc(llvm.c.LLVMValueRef, cnt);
        for (sl.fields, 0..) |f, i|
            vals[i] = (try self.visitNode(f.value)).?.value_ref;

        const ty = try self.toLLVMType(sl.ty);
        const val = c.LLVMConstNamedStruct(ty, vals.ptr, @intCast(cnt));
        return .{ .value_ref = val, .type_ref = ty };
    }

    // ────────────────────────────────────────── struct field access ──
    fn genStructFieldAccess(self: *CodeGenerator, fa: *const sem.StructFieldAccess) !TypedValue {
        const base = (try self.visitNode(fa.struct_value)) orelse
            return CodegenError.ValueNotFound;

        // el índice ya viene resuelto por el semantizador
        const val = c.LLVMBuildExtractValue(self.builder, base.value_ref, fa.field_index, "fld");

        const field_ty = c.LLVMStructGetTypeAtIndex(base.type_ref, fa.field_index);

        return .{ .value_ref = val, .type_ref = field_ty };
    }

    // ────────────────────────────────────────── misc helpers ──
    fn genCodeBlock(self: *CodeGenerator, cb: *const sem.CodeBlock) !void {
        for (cb.nodes) |n| _ = try self.visitNode(n);
    }

    fn dupZ(self: *CodeGenerator, s: []const u8) ![]u8 {
        const buf = try self.allocator.alloc(u8, s.len + 1);
        std.mem.copyForwards(u8, buf, s);
        buf[s.len] = 0;
        return buf;
    }
};
