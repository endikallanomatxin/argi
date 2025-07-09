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

const Scope = struct {
    parent: ?*Scope,
    symbols: std.StringHashMap(Symbol),

    fn init(a: *const std.mem.Allocator, parent: ?*Scope) !*Scope {
        const p = try a.create(Scope);
        p.* = .{
            .parent = parent,
            .symbols = std.StringHashMap(Symbol).init(a.*),
        };
        return p;
    }

    fn deinit(self: *Scope) void {
        self.symbols.deinit(); // libera sólo sus claves
        // el objeto Scope se libera desde quien lo haya creado
    }

    /// Búsqueda recursiva
    fn lookup(self: *Scope, name: []const u8) ?*Symbol {
        if (self.symbols.getPtr(name)) |s| return s;
        if (self.parent) |p| return p.lookup(name);
        return null;
    }
};

// ────────────────────────────────────────────── CodeGenerator ──
pub const CodeGenerator = struct {
    allocator: *const std.mem.Allocator,
    ast: []const *sem.SGNode,

    module: llvm.c.LLVMModuleRef,
    builder: llvm.c.LLVMBuilderRef,
    current_return_type: ?llvm.c.LLVMTypeRef = null,

    global_scope: *Scope, // nunca se destruye hasta el final
    current_scope: *Scope, // apunta al scope donde estamos ahora

    pub fn init(a: *const std.mem.Allocator, ast: []const *sem.SGNode) !CodeGenerator {
        const m = c.LLVMModuleCreateWithName("argi_module");
        if (m == null) return CodegenError.ModuleCreationFailed;

        const b = c.LLVMCreateBuilder();
        const gscope = try Scope.init(a, null);

        return .{
            .allocator = a,
            .ast = ast,
            .module = m,
            .builder = b,
            .global_scope = gscope,
            .current_scope = gscope,
        };
    }

    pub fn deinit(self: *CodeGenerator) void {
        if (self.builder) |b| c.LLVMDisposeBuilder(b);

        // Recorremos la cadena y liberamos cada scope
        var s: ?*Scope = self.current_scope;
        while (s) |sc| {
            const prev = sc.parent;
            sc.deinit();
            self.allocator.destroy(sc);
            s = prev;
        }
    }

    // ──── Scope helpers ─────────────────────────────────────────
    fn pushScope(self: *CodeGenerator) !void {
        self.current_scope = try Scope.init(self.allocator, self.current_scope);
    }

    fn popScope(self: *CodeGenerator) void {
        const old = self.current_scope;
        self.current_scope = old.parent.?; // global nunca se “pop-ea”
        old.deinit();
        self.allocator.destroy(old);
    }

    // ── top-level drive ───────────────────────
    pub fn generate(self: *CodeGenerator) !llvm.c.LLVMModuleRef {
        std.debug.print("\n\nGenerating LLVM IR...\n", .{});

        for (self.ast) |n|
            _ = self.visitNode(n) catch |e| {
                std.debug.print("codegen error: {any}\n", .{e});
                return CodegenError.CompilationFailed;
            };

        var msg: [*c]u8 = null;
        if (c.LLVMVerifyModule(self.module, c.LLVMReturnStatusAction, &msg) != 0) {
            std.debug.print("LLVM verification failed: {s}\n", .{msg});
            c.LLVMDisposeMessage(msg);
            return CodegenError.ModuleCreationFailed;
        }
        return self.module;
    }

    // ────────────────────────────────────────── visitor dispatch ──
    fn visitNode(self: *CodeGenerator, n: *const sem.SGNode) CodegenError!?TypedValue {
        return switch (n.*) {
            .function_declaration => |f| {
                self.genFunction(f) catch |e| {
                    std.debug.print("Error generating function {s}: {any}\n", .{ f.name, e });
                    return e;
                };
                return null;
            },
            .type_declaration => |_| {
                return null;
            },
            .binding_declaration => |b| {
                if (self.current_scope.lookup(b.name) != null)
                    return self.genBindingUse(b) catch |e| {
                        std.debug.print("Error generating binding {s}: {any}\n", .{ b.name, e });
                        return e;
                    };
                self.genBindingDecl(b) catch |e| {
                    std.debug.print("Error generating binding declaration {s}: {any}\n", .{ b.name, e });
                    return e;
                };
                return null;
            },
            .binding_assignment => |a| {
                _ = self.genAssignment(a) catch |e| {
                    std.debug.print("Error generating assignment for {s}: {any}\n", .{ a.sym_id.name, e });
                    return e;
                };
                return null;
            },
            .binding_use => |b| self.genBindingUse(b) catch |e| {
                std.debug.print("Error generating binding use {s}: {any}\n", .{ b.name, e });
                return e;
            },
            .code_block => |cb| {
                self.genCodeBlock(cb) catch |e| {
                    std.debug.print("Error generating code block: {any}\n", .{e});
                    return e;
                };
                return null;
            },
            .return_statement => |r| {
                self.genReturn(r) catch |e| {
                    std.debug.print("Error generating return statement: {any}\n", .{e});
                    return e;
                };
                return null;
            },
            .value_literal => |v| self.genValueLiteral(&v) catch |e| {
                std.debug.print("Error generating value literal: {any}\n", .{e});
                return e;
            },
            .binary_operation => |bo| self.genBinaryOp(&bo) catch |e| {
                std.debug.print("Error generating binary operation: {any}\n", .{e});
                return e;
            },
            .comparison => |comp| self.genComparison(&comp) catch |e| {
                std.debug.print("Error generating comparison: {any}\n", .{e});
                return e;
            },
            .if_statement => |ifs| {
                self.genIfStatement(ifs) catch |e| {
                    std.debug.print("Error generating if statement: {any}\n", .{e});
                    return e;
                };
                return null;
            },
            .function_call => |fc| self.genFunctionCall(fc) catch |e| {
                std.debug.print("Error generating function call: {any}\n", .{e});
                return e;
            },
            .struct_value_literal => |sl| self.genStructValueLiteral(sl) catch |e| {
                std.debug.print("Error generating struct value literal: {any}\n", .{e});
                return e;
            },
            .struct_field_access => |sfa| self.genStructFieldAccess(sfa) catch |e| {
                std.debug.print("Error generating struct field access: {any}\n", .{e});
                return e;
            },
            .address_of => |a| self.genAddressOf(a) catch |e| {
                std.debug.print("Error generating address of: {any}\n", .{e});
                return e;
            },
            .dereference => |d| self.genDereference(d) catch |e| {
                std.debug.print("Error generating dereference: {any}\n", .{e});
                return e;
            },
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
            .pointer_type => |sub| blk: {
                const sub_ty = try self.toLLVMType(sub.*);
                break :blk c.LLVMPointerType(sub_ty, 0);
            },
        };
    }

    fn genFunction(self: *CodeGenerator, f: *sem.FunctionDeclaration) !void {
        const is_extern = (f.body == null);

        var fn_ty: llvm.c.LLVMTypeRef = undefined;
        var return_ty: llvm.c.LLVMTypeRef = undefined;
        var uses_sret = false;

        // ─── signatura ───────────────────────────────────────────────────
        if (is_extern) {
            const sig = try self.makeExternSignature(f);
            fn_ty = sig.fn_ty;
            return_ty = sig.ret_ty;
            uses_sret = sig.sret;
        } else {
            const input_ty = try self.toLLVMType(.{ .struct_type = &f.input });
            return_ty = try self.toLLVMType(.{ .struct_type = &f.output });
            fn_ty = c.LLVMFunctionType(
                return_ty,
                blk: {
                    var a = try self.allocator.alloc(llvm.c.LLVMTypeRef, 1);
                    a[0] = input_ty;
                    break :blk a.ptr;
                },
                1,
                0,
            );
        }

        // ─── creación / tabla de símbolos ────────────────────────────────
        const cname = try self.dupZ(f.name);
        const fn_ref = c.LLVMAddFunction(self.module, cname.ptr, fn_ty);

        if (is_extern and uses_sret) {
            const kind = c.LLVMGetEnumAttributeKindForName("sret", 4);
            const attr = c.LLVMCreateEnumAttribute(c.LLVMGetGlobalContext(), kind, 0);
            c.LLVMAddAttributeAtIndex(fn_ref, 1, attr); // 1-based
        }

        try self.current_scope.symbols.put(
            f.name,
            .{ .cname = cname, .mutability = .constant, .type_ref = fn_ty, .ref = fn_ref },
        );

        // ─── funciones externas: ¡nada más que hacer! ────────────────────
        if (is_extern) return;

        // ─── a partir de aquí es tu código original (cuerpo interno) ─────
        const entry = c.LLVMAppendBasicBlock(fn_ref, "entry");
        c.LLVMPositionBuilderAtEnd(self.builder, entry);

        try self.pushScope();
        defer self.popScope();

        const prev_rt = self.current_return_type;
        self.current_return_type = return_ty;
        defer self.current_return_type = prev_rt;

        // registrar parámetros de entrada
        for (f.input.fields) |fld| {
            const bd = sem.BindingDeclaration{
                .name = fld.name,
                .mutability = syn.Mutability.constant,
                .ty = fld.ty,
                .initialization = null,
            };
            try self.genBindingDecl(&bd);
        }

        // extraer struct-input
        const param_agg = c.LLVMGetParam(fn_ref, 0);
        for (f.input.fields, 0..) |fld, i| {
            const sym = self.current_scope.lookup(fld.name).?;
            const v = c.LLVMBuildExtractValue(self.builder, param_agg, @intCast(i), "arg");
            _ = c.LLVMBuildStore(self.builder, v, sym.ref);
            sym.initialized = true;
        }

        // registrar parámetros de salida
        for (f.output.fields) |fld| {
            const bd = sem.BindingDeclaration{
                .name = fld.name,
                .mutability = syn.Mutability.variable,
                .ty = fld.ty,
                .initialization = null,
            };
            try self.genBindingDecl(&bd);
        }

        // cuerpo del usuario
        try self.genCodeBlock(f.body.?);

        // return implícito si falta
        const cur_bb = c.LLVMGetInsertBlock(self.builder);
        if (c.LLVMGetBasicBlockTerminator(cur_bb) == null) {
            if (return_ty == c.LLVMVoidType()) {
                _ = c.LLVMBuildRetVoid(self.builder);
            } else {
                var agg = c.LLVMGetUndef(return_ty);
                for (f.output.fields, 0..) |fld, i| {
                    const sym = self.current_scope.lookup(fld.name).?;
                    const v = c.LLVMBuildLoad2(self.builder, sym.type_ref, sym.ref, "");
                    agg = c.LLVMBuildInsertValue(self.builder, agg, v, @intCast(i), "");
                }
                _ = c.LLVMBuildRet(self.builder, agg);
            }
        }
    }

    // ────────────────────────── extern helpers ──
    /// Construye la signatura LLVM correcta para una función *extern*
    /// usando la ABI de C:
    ///   · cada campo de `input` → parámetro independiente
    ///   · 0 retornos → `void`
    ///   · 1 retorno  → ese tipo
    ///   · ≥2 retornos → `void` + primer parámetro `sret` (&struct)
    fn makeExternSignature(self: *CodeGenerator, f: *const sem.FunctionDeclaration) !struct { fn_ty: llvm.c.LLVMTypeRef, ret_ty: llvm.c.LLVMTypeRef, sret: bool } {
        const need_sret = f.output.fields.len > 1;
        const total: usize = f.input.fields.len + (if (need_sret) @as(usize, 1) else @as(usize, 0));

        var arg_tys = try self.allocator.alloc(llvm.c.LLVMTypeRef, total);
        var idx: usize = 0;

        if (need_sret) {
            const sret_ty = try self.toLLVMType(.{ .struct_type = &f.output });
            arg_tys[0] = c.LLVMPointerType(sret_ty, 0);
            idx = 1;
        }
        for (f.input.fields, 0..) |fld, i|
            arg_tys[idx + i] = try self.toLLVMType(fld.ty);

        var ret_ty: llvm.c.LLVMTypeRef = c.LLVMVoidType();
        if (f.output.fields.len == 1)
            ret_ty = try self.toLLVMType(f.output.fields[0].ty);

        const fn_ty = c.LLVMFunctionType(
            ret_ty,
            if (total == 0) null else arg_tys.ptr,
            @intCast(total),
            0,
        );
        return .{ .fn_ty = fn_ty, .ret_ty = ret_ty, .sret = need_sret };
    }

    // ────────────────────────────────────────── bindings ──
    fn genBindingDecl(self: *CodeGenerator, b: *const sem.BindingDeclaration) !void {
        if (self.current_scope.lookup(b.name) != null)
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
        try self.current_scope.symbols.put(b.name, .{
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
        const sym = self.current_scope.lookup(b.name) orelse
            return CodegenError.SymbolNotFound;
        const val = c.LLVMBuildLoad2(self.builder, sym.type_ref, sym.ref, sym.cname.ptr);
        return .{ .value_ref = val, .type_ref = sym.type_ref };
    }

    // ────────────────────────────────────────── assignment ──
    fn genAssignment(self: *CodeGenerator, a: *sem.Assignment) !TypedValue {
        const sym_ptr = self.current_scope.lookup(a.sym_id.name) orelse
            return CodegenError.SymbolNotFound;

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

        _ = c.LLVMBuildStore(self.builder, rhs_val, sym_ptr.*.ref);
        sym_ptr.*.initialized = true;
        return .{ .value_ref = rhs_val, .type_ref = sym_ptr.*.type_ref };
    }

    // ────────────────────────────────────────── literals ──
    fn genValueLiteral(self: *CodeGenerator, l: *const sem.ValueLiteral) !TypedValue {
        _ = self;
        return switch (l.*) {
            .int_literal => |v| .{ .type_ref = c.LLVMInt32Type(), .value_ref = c.LLVMConstInt(c.LLVMInt32Type(), @intCast(v), 0) },
            .float_literal => |f| .{ .type_ref = c.LLVMFloatType(), .value_ref = c.LLVMConstReal(c.LLVMFloatType(), f) },
            .char_literal => |ch| .{ .type_ref = c.LLVMInt8Type(), .value_ref = c.LLVMConstInt(c.LLVMInt8Type(), @intCast(ch), 0) },
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
        };

        return .{ .value_ref = val, .type_ref = lhs.type_ref };
    }

    // ────────────────────────────────────────── comparison ──
    fn genComparison(self: *CodeGenerator, co: *const sem.Comparison) !TypedValue {
        const lhs = (try self.visitNode(co.left)) orelse return CodegenError.ValueNotFound;
        const rhs = (try self.visitNode(co.right)) orelse return CodegenError.ValueNotFound;

        // promociones int→float como antes …
        const is_float = lhs.type_ref == c.LLVMFloatType();

        const val = switch (co.operator) {
            .equal => if (is_float)
                c.LLVMBuildFCmp(self.builder, c.LLVMRealOEQ, lhs.value_ref, rhs.value_ref, "feq")
            else
                c.LLVMBuildICmp(self.builder, c.LLVMIntEQ, lhs.value_ref, rhs.value_ref, "ieq"),

            .not_equal => if (is_float)
                c.LLVMBuildFCmp(self.builder, c.LLVMRealONE, lhs.value_ref, rhs.value_ref, "fne")
            else
                c.LLVMBuildICmp(self.builder, c.LLVMIntNE, lhs.value_ref, rhs.value_ref, "ine"),

            .less_than => if (is_float)
                c.LLVMBuildFCmp(self.builder, c.LLVMRealOLT, lhs.value_ref, rhs.value_ref, "flt")
            else
                c.LLVMBuildICmp(self.builder, c.LLVMIntSLT, lhs.value_ref, rhs.value_ref, "ilt"),

            .greater_than => if (is_float)
                c.LLVMBuildFCmp(self.builder, c.LLVMRealOGT, lhs.value_ref, rhs.value_ref, "fgt")
            else
                c.LLVMBuildICmp(self.builder, c.LLVMIntSGT, lhs.value_ref, rhs.value_ref, "igt"),

            .less_than_or_equal => if (is_float)
                c.LLVMBuildFCmp(self.builder, c.LLVMRealOLE, lhs.value_ref, rhs.value_ref, "fle")
            else
                c.LLVMBuildICmp(self.builder, c.LLVMIntSLE, lhs.value_ref, rhs.value_ref, "ile"),

            .greater_than_or_equal => if (is_float)
                c.LLVMBuildFCmp(self.builder, c.LLVMRealOGE, lhs.value_ref, rhs.value_ref, "fge")
            else
                c.LLVMBuildICmp(self.builder, c.LLVMIntSGE, lhs.value_ref, rhs.value_ref, "ige"),
        };

        return .{ .value_ref = val, .type_ref = c.LLVMInt1Type() };
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

            const ret_ty = self.current_return_type orelse
                return CodegenError.InvalidType;

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
        const sym = self.current_scope.lookup(fc.callee.name) orelse
            return CodegenError.SymbolNotFound;
        const callee_decl = fc.callee;
        const is_extern = (callee_decl.body == null);

        // ─────── llamadas INTERNAS (idénticas a antes) ───────────────────
        if (!is_extern) {
            const fn_ty = sym.type_ref;
            const ret_ty = c.LLVMGetReturnType(fn_ty);

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

        // ─────── llamadas EXTERN ─────────────────────────────────────────
        const in_tv = (try self.visitNode(fc.input)).?;
        const in_val = in_tv.value_ref;

        const need_sret = callee_decl.output.fields.len > 1;
        const total: usize = callee_decl.input.fields.len + (if (need_sret) @as(usize, 1) else @as(usize, 0));
        var argv = try self.allocator.alloc(llvm.c.LLVMValueRef, total);

        var idx: usize = 0;
        var sret_tmp: llvm.c.LLVMValueRef = null;
        var sret_ty: llvm.c.LLVMTypeRef = c.LLVMVoidType();

        if (need_sret) {
            sret_ty = try self.toLLVMType(.{ .struct_type = &callee_decl.output });
            sret_tmp = c.LLVMBuildAlloca(self.builder, sret_ty, "sret");
            argv[0] = sret_tmp;
            idx = 1;
        }

        // aplanar struct-input
        for (callee_decl.input.fields, 0..) |fld, i| {
            const raw = c.LLVMBuildExtractValue(self.builder, in_val, @intCast(i), "");
            const pty = try self.toLLVMType(fld.ty);

            // cast típico i8→i32 (ej. putchar)
            const val =
                if (pty == c.LLVMInt32Type() and c.LLVMTypeOf(raw) == c.LLVMInt8Type())
                    c.LLVMBuildSExt(self.builder, raw, pty, "sext")
                else
                    raw;

            argv[idx] = val;
            idx += 1;
        }

        _ = c.LLVMBuildCall2(
            self.builder,
            sym.type_ref,
            sym.ref,
            argv.ptr,
            @intCast(idx),
            "",
        );

        // retorno según nº de campos
        switch (callee_decl.output.fields.len) {
            0 => return null,
            1 => {
                // el valor ya está retornado por la instrucción `call`
                const ret_ty = c.LLVMGetReturnType(sym.type_ref);
                const call_val = c.LLVMBuildCall2(
                    self.builder,
                    sym.type_ref,
                    sym.ref,
                    argv.ptr,
                    @intCast(idx),
                    "calltmp",
                );
                return .{ .value_ref = call_val, .type_ref = ret_ty };
            },
            else => {
                const loaded = c.LLVMBuildLoad2(self.builder, sret_ty, sret_tmp, "ret");
                return .{ .value_ref = loaded, .type_ref = sret_ty };
            },
        }
    }

    // ────────────────────────────────────────── struct literal ──
    fn genStructValueLiteral(self: *CodeGenerator, sl: *const sem.StructValueLiteral) !?TypedValue {
        const cnt = sl.fields.len;
        var vals = try self.allocator.alloc(llvm.c.LLVMValueRef, cnt);
        for (sl.fields, 0..) |f, i|
            vals[i] = (try self.visitNode(f.value)).?.value_ref;

        const ty = try self.toLLVMType(sl.ty);

        // construir el agregado en tiempo de ejecución
        var agg = c.LLVMGetUndef(ty);
        for (vals, 0..) |v, i|
            agg = c.LLVMBuildInsertValue(self.builder, agg, v, @intCast(i), "lit.insert");

        return .{ .value_ref = agg, .type_ref = ty };
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

    // ────────────────────────────────────────── address-of ──
    fn genAddressOf(self: *CodeGenerator, node: *const sem.SGNode) !TypedValue {
        // node es el SG del binding_use
        const bu = node.*.binding_use;
        const sym = self.current_scope.lookup(bu.name) orelse
            return CodegenError.SymbolNotFound;

        const ptr_ty = c.LLVMPointerType(sym.type_ref, 0);
        return .{ .value_ref = sym.ref, .type_ref = ptr_ty };
    }

    fn genDereference(self: *CodeGenerator, d: *const sem.Dereference) !TypedValue {
        const tv = (try self.visitNode(d.pointer)) orelse return CodegenError.ValueNotFound;

        // El tipo LLVM lo sacamos del result_ty semántico
        const pointee_ty = try self.toLLVMType(d.ty);

        const deref_val = c.LLVMBuildLoad2(self.builder, pointee_ty, tv.value_ref, "deref");
        return .{ .value_ref = deref_val, .type_ref = pointee_ty };
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
