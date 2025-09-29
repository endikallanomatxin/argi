const std = @import("std");
const llvm = @import("llvm.zig");
const c = llvm.c;
const sem = @import("semantic_graph.zig");
const syn = @import("syntax_tree.zig");
const diagnostic = @import("diagnostic.zig");

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
    diags: *diagnostic.Diagnostics,

    module: llvm.c.LLVMModuleRef,
    builder: llvm.c.LLVMBuilderRef,
    current_return_type: ?llvm.c.LLVMTypeRef = null,
    current_fn_decl: ?*sem.FunctionDeclaration = null,

    global_scope: *Scope, // nunca se destruye hasta el final
    current_scope: *Scope, // apunta al scope donde estamos ahora

    pub fn init(a: *const std.mem.Allocator, ast: []const *sem.SGNode, diags: *diagnostic.Diagnostics) !CodeGenerator {
        const m = c.LLVMModuleCreateWithName("argi_module");
        if (m == null) return CodegenError.ModuleCreationFailed;

        const b = c.LLVMCreateBuilder();
        const gscope = try Scope.init(a, null);

        return .{
            .allocator = a,
            .ast = ast,
            .diags = diags,
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
        for (self.ast) |n| {
            _ = self.visitNode(n) catch |err| {
                try self.diags.add(n.location, .codegen, "code generation error: {s}", .{@errorName(err)});
                return CodegenError.CompilationFailed;
            };
        }

        var msg: [*c]u8 = null;
        const failed = c.LLVMVerifyModule(self.module, c.LLVMReturnStatusAction, &msg) != 0;
        if (failed) {
            if (msg != null) {
                const txt = std.mem.span(msg);
                try self.diags.add(self.ast[0].location, .codegen, "LLVM verification failed: {s}", .{txt});
                c.LLVMDisposeMessage(msg);
            } else {
                try self.diags.add(self.ast[0].location, .codegen, "LLVM verification failed (no message)", .{});
            }
            return CodegenError.ModuleCreationFailed;
        }

        return self.module;
    }

    // ────────────────────────────────────────── visitor dispatch ──
    fn visitNode(self: *CodeGenerator, n: *const sem.SGNode) CodegenError!?TypedValue {
        return switch (n.content) {
            .function_declaration => |f| {
                self.genFunction(f) catch |e| {
                    try self.diags.add(n.location, .codegen, "error generating function {s}: {s}", .{ f.name, @errorName(e) });
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
                        try self.diags.add(n.location, .codegen, "error generating binding {s}: {s}", .{ b.name, @errorName(e) });
                        return e;
                    };
                self.genBindingDecl(b) catch |e| {
                    try self.diags.add(n.location, .codegen, "error generating binding declaration {s}: {s}", .{ b.name, @errorName(e) });
                    return e;
                };
                return null;
            },
            .binding_assignment => |a| {
                _ = self.genAssignment(a) catch |e| {
                    try self.diags.add(n.location, .codegen, "error generating assignment for {s}: {s}", .{ a.sym_id.name, @errorName(e) });
                    return e;
                };
                return null;
            },
            .binding_use => |b| self.genBindingUse(b) catch |e| {
                try self.diags.add(n.location, .codegen, "error generating binding use {s}: {s}", .{ b.name, @errorName(e) });
                return e;
            },
            .code_block => |cb| {
                self.genCodeBlock(cb) catch |e| {
                    try self.diags.add(n.location, .codegen, "error generating code block: {s}", .{@errorName(e)});
                    return e;
                };
                return null;
            },
            .return_statement => |r| {
                self.genReturn(r) catch |e| {
                    try self.diags.add(n.location, .codegen, "error generating return statement: {s}", .{@errorName(e)});
                    return e;
                };
                return null;
            },
            .value_literal => |v| self.genValueLiteral(&v) catch |e| {
                try self.diags.add(n.location, .codegen, "error generating value literal: {s}", .{@errorName(e)});
                return e;
            },
            .array_literal => |al| self.genArrayLiteral(al) catch |e| {
                try self.diags.add(n.location, .codegen, "error generating array literal: {s}", .{@errorName(e)});
                return e;
            },
            .binary_operation => |bo| self.genBinaryOp(&bo) catch |e| {
                try self.diags.add(n.location, .codegen, "error generating binary operation: {s}", .{@errorName(e)});
                return e;
            },
            .comparison => |comp| self.genComparison(&comp) catch |e| {
                try self.diags.add(n.location, .codegen, "error generating comparison: {s}", .{@errorName(e)});
                return e;
            },
            .if_statement => |ifs| {
                self.genIfStatement(ifs) catch |e| {
                    try self.diags.add(n.location, .codegen, "error generating if statement: {s}", .{@errorName(e)});
                    return e;
                };
                return null;
            },
            .function_call => |fc| self.genFunctionCall(fc) catch |e| {
                try self.diags.add(n.location, .codegen, "error generating function call: {s}", .{@errorName(e)});
                return e;
            },
            .struct_value_literal => |sl| self.genStructValueLiteral(sl) catch |e| {
                try self.diags.add(n.location, .codegen, "error generating struct value literal: {s}", .{@errorName(e)});
                return e;
            },
            .list_literal => |_| {
                try self.diags.add(n.location, .codegen, "list literals are compile-time only", .{});
                return CodegenError.NotYetImplemented;
            },
            .struct_field_access => |sfa| self.genStructFieldAccess(sfa) catch |e| {
                try self.diags.add(n.location, .codegen, "error generating struct field access: {s}", .{@errorName(e)});
                return e;
            },
            .address_of => |a| self.genAddressOf(a) catch |e| {
                try self.diags.add(n.location, .codegen, "error generating address-of: {s}", .{@errorName(e)});
                return e;
            },
            .dereference => |d| self.genDereference(&d) catch |e| {
                try self.diags.add(n.location, .codegen, "error generating dereference: {s}", .{@errorName(e)});
                return e;
            },
            .pointer_assignment => |pa| {
                self.genPointerAssignment(pa) catch |e| {
                    try self.diags.add(n.location, .codegen, "error generating pointer assignment: {s}", .{@errorName(e)});
                    return e;
                };
                return null;
            },
            .array_index => |ai| self.genArrayIndex(&ai) catch |e| {
                try self.diags.add(n.location, .codegen, "error generating array index: {s}", .{@errorName(e)});
                return e;
            },
            .array_store => |as| {
                self.genArrayStore(&as) catch |e| {
                    try self.diags.add(n.location, .codegen, "error generating array store: {s}", .{@errorName(e)});
                    return e;
                };
                return null;
            },
            .type_initializer => |ti| self.genTypeInitializer(&ti) catch |e| {
                try self.diags.add(n.location, .codegen, "error generating type initializer: {s}", .{@errorName(e)});
                return e;
            },
            .type_literal => |_| {
                try self.diags.add(n.location, .codegen, "type values are compile-time only", .{});
                return CodegenError.NotYetImplemented;
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
                .Type => c.LLVMPointerType(c.LLVMInt8Type(), 0),
                .Any => c.LLVMInt8Type(), // &Any es i8*
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
            .pointer_type => |ptr_info_ptr| {
                const ptr_info = ptr_info_ptr.*;
                const child_ty = ptr_info.child.*;
                // ¿el pointee es nuestro 'Any' (= builtin.Void)?
                const is_any = switch (child_ty) {
                    .builtin => |bt| bt == .Any,
                    else => false,
                };

                if (is_any) {
                    // &Any  ≡  i8*
                    return c.LLVMPointerType(c.LLVMInt8Type(), 0);
                }

                const sub_ty = try self.toLLVMType(child_ty);
                return c.LLVMPointerType(sub_ty, 0);
            },
            .array_type => |arr_ptr| {
                const elem_ty = try self.toLLVMType(arr_ptr.element_type.*);
                const count: c_uint = @intCast(arr_ptr.length);
                return c.LLVMArrayType(elem_ty, count);
            },
        };
    }

    // ────────────────────────────────────────── name mangling ──
    fn isMainName(name: []const u8) bool {
        return name.len == 4 and name[0] == 'm' and name[1] == 'a' and name[2] == 'i' and name[3] == 'n';
    }

    fn encodeType(self: *CodeGenerator, buf: *std.ArrayList(u8), t: sem.Type) !void {
        switch (t) {
            .builtin => |bt| {
                const s = switch (bt) {
                    .Int8 => "i8",
                    .Int16 => "i16",
                    .Int32 => "i32",
                    .Int64 => "i64",
                    .UInt8 => "u8",
                    .UInt16 => "u16",
                    .UInt32 => "u32",
                    .UInt64 => "u64",
                    .Float16 => "f16",
                    .Float32 => "f32",
                    .Float64 => "f64",
                    .Char => "char",
                    .Bool => "bool",
                    .Type => "type",
                    .Any => "any",
                };
                try buf.appendSlice(s);
            },
            .pointer_type => |ptr_info_ptr| {
                const ptr_info = ptr_info_ptr.*;
                const prefix = if (ptr_info.mutability == .read_write) "prw_" else "pro_";
                try buf.appendSlice(prefix);
                try self.encodeType(buf, ptr_info.child.*);
            },
            .struct_type => |st| {
                try buf.appendSlice("s{");
                var first: bool = true;
                for (st.fields) |f| {
                    if (!first) try buf.appendSlice(",");
                    first = false;
                    try buf.appendSlice(f.name);
                    try buf.appendSlice(":");
                    try self.encodeType(buf, f.ty);
                }
                try buf.appendSlice("}");
            },
            .array_type => |arr_ptr| {
                try buf.appendSlice("arr");
                var tmp: [32]u8 = undefined;
                const len_slice = std.fmt.bufPrint(&tmp, "{d}", .{arr_ptr.length}) catch "?";
                try buf.appendSlice(len_slice);
                try buf.appendSlice("_");
                try self.encodeType(buf, arr_ptr.element_type.*);
            },
        }
    }

    fn mangledNameFor(self: *CodeGenerator, f: *const sem.FunctionDeclaration) ![]u8 {
        var buf = std.ArrayList(u8).init(self.allocator.*);
        try buf.appendSlice(f.name);
        try buf.appendSlice("__in_");
        try self.encodeType(&buf, .{ .struct_type = &f.input });
        // not including output in the mangle for now
        return try buf.toOwnedSlice();
    }

    fn isMainCandidate(f: *const sem.FunctionDeclaration) bool {
        // Heuristic used by tests: no inputs and one named Int32 return "status_code"
        if (f.input.fields.len != 0) return false;
        if (f.output.fields.len != 1) return false;
        const fld = f.output.fields[0];
        if (!std.mem.eql(u8, fld.name, "status_code")) return false;
        return switch (fld.ty) {
            .builtin => |bt| bt == .Int32,
            else => false,
        };
    }

    fn genFunction(self: *CodeGenerator, f: *sem.FunctionDeclaration) !void {
        const prev_fn = self.current_fn_decl;
        self.current_fn_decl = f;
        defer self.current_fn_decl = prev_fn;

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
        const key_name = if (is_extern or isMainName(f.name) or isMainCandidate(f)) f.name else blk: {
            const m = try self.mangledNameFor(f);
            break :blk m;
        };
        const cname = try self.dupZ(key_name);
        const fn_ref = c.LLVMAddFunction(self.module, cname.ptr, fn_ty);

        if (is_extern and uses_sret) {
            const kind = c.LLVMGetEnumAttributeKindForName("sret", 4);
            const attr = c.LLVMCreateEnumAttribute(c.LLVMGetGlobalContext(), kind, 0);
            c.LLVMAddAttributeAtIndex(fn_ref, 1, attr); // 1-based
        }

        try self.current_scope.symbols.put(
            key_name,
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

        const cname = try self.dupZ(b.name);

        // 3) reserva de espacio
        //    - En global scope: crear variable global
        //    - Dentro de función: alloca en el entry
        var storage: llvm.c.LLVMValueRef = null;
        if (self.current_scope.parent == null) {
            // Global variable
            storage = c.LLVMAddGlobal(self.module, llvm_decl_ty, cname.ptr);
            // Use zero initializer for globals (safer than undef)
            const zero = c.LLVMConstNull(llvm_decl_ty);
            c.LLVMSetInitializer(storage, zero);
        } else {
            storage = c.LLVMBuildAlloca(self.builder, llvm_decl_ty, cname.ptr);
        }

        // 4) registrar en la tabla
        try self.current_scope.symbols.put(b.name, .{
            .cname = cname,
            .mutability = b.mutability,
            .type_ref = llvm_decl_ty,
            .ref = storage,
            .initialized = init_tv != null,
        });

        // 5) almacenar valor inicial, manejando struct-parciales
        if (init_tv) |tv| {
            // Global initializers must be constant; for now, only allow none
            if (self.current_scope.parent == null) {
                // Non-constant global init not supported yet; ignore for now
                // (could enhance by constant-folding later)
                return;
            }
            const value_ref = tv.value_ref;
            const target_ty = llvm_decl_ty;

            if (tv.type_ref == llvm_decl_ty) {
                // tipos idénticos → copiar tal cual
                _ = c.LLVMBuildStore(self.builder, tv.value_ref, storage);
            } else if (c.LLVMGetTypeKind(tv.type_ref) == c.LLVMPointerTypeKind and
                c.LLVMGetTypeKind(target_ty) == c.LLVMGetTypeKind(tv.type_ref))
            {
                const casted = c.LLVMBuildBitCast(self.builder, value_ref, target_ty, "ptr.cast");
                _ = c.LLVMBuildStore(self.builder, casted, storage);
            } else if (c.LLVMGetTypeKind(tv.type_ref) == c.LLVMStructTypeKind and
                c.LLVMGetTypeKind(target_ty) != c.LLVMStructTypeKind)
            {
                const field_count = c.LLVMCountStructElementTypes(tv.type_ref);
                var extracted = false;
                var idx: u32 = 0;
                while (idx < field_count) : (idx += 1) {
                    const fty = c.LLVMStructGetTypeAtIndex(tv.type_ref, idx);
                    if (fty == target_ty) {
                        const elem = c.LLVMBuildExtractValue(self.builder, value_ref, idx, "init.extract");
                        _ = c.LLVMBuildStore(self.builder, elem, storage);
                        extracted = true;
                        break;
                    }
                }
                if (!extracted) return CodegenError.InvalidType;
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

                _ = c.LLVMBuildStore(self.builder, agg, storage);
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
        return switch (l.*) {
            .int_literal => |v| .{ .type_ref = c.LLVMInt32Type(), .value_ref = c.LLVMConstInt(c.LLVMInt32Type(), @intCast(v), 0) },
            .float_literal => |f| .{ .type_ref = c.LLVMFloatType(), .value_ref = c.LLVMConstReal(c.LLVMFloatType(), f) },
            .char_literal => |ch| .{ .type_ref = c.LLVMInt8Type(), .value_ref = c.LLVMConstInt(c.LLVMInt8Type(), @intCast(ch), 0) },
            .string_literal => |str| blk: {
                // TODO: For now, we will use c-like strings.
                // Later on, this should be a proper string type.

                // Crea un global interno y recibe el i8* a su inicio
                const gptr = c.LLVMBuildGlobalStringPtr(
                    self.builder,
                    str.ptr, // bytes tal cual (ya con escapes resueltos)
                    "strlit",
                );
                break :blk .{
                    .type_ref = c.LLVMPointerType(c.LLVMInt8Type(), 0),
                    .value_ref = gptr,
                };
            },
            else => CodegenError.NotYetImplemented,
        };
    }

    // ────────────────────────────────────────── binary-op (sin coerciones) ──

    fn genArrayLiteral(self: *CodeGenerator, al: *const sem.ArrayLiteral) !TypedValue {
        const elem_ty_ref = try self.toLLVMType(al.element_type);
        const count: c_uint = @intCast(al.length);
        const array_ty_ref = c.LLVMArrayType(elem_ty_ref, count);

        var agg = c.LLVMGetUndef(array_ty_ref);
        var idx: usize = 0;
        while (idx < al.elements.len) : (idx += 1) {
            const elem_tv_opt = try self.visitNode(al.elements[idx]);
            const elem_tv = elem_tv_opt orelse return CodegenError.ValueNotFound;

            if (elem_tv.type_ref != elem_ty_ref)
                return CodegenError.InvalidType;

            const index_c: c_uint = @intCast(idx);

            agg = c.LLVMBuildInsertValue(
                self.builder,
                agg,
                elem_tv.value_ref,
                index_c,
                "array.elem",
            );
        }

        return .{ .value_ref = agg, .type_ref = array_ty_ref };
    }

    fn castIndexToI32(self: *CodeGenerator, tv: TypedValue) !llvm.c.LLVMValueRef {
        if (tv.type_ref == c.LLVMInt32Type()) return tv.value_ref;
        if (c.LLVMGetTypeKind(tv.type_ref) != c.LLVMIntegerTypeKind)
            return CodegenError.InvalidType;
        return c.LLVMBuildIntCast(self.builder, tv.value_ref, c.LLVMInt32Type(), "array.idx.cast");
    }

    fn genArrayElementPointer(
        self: *CodeGenerator,
        array_ptr_tv: TypedValue,
        array_ty_ref: llvm.c.LLVMTypeRef,
        index_val: llvm.c.LLVMValueRef,
    ) !llvm.c.LLVMValueRef {
        const zero = c.LLVMConstInt(c.LLVMInt32Type(), 0, 0);
        var indices = [_]llvm.c.LLVMValueRef{ zero, index_val };
        return c.LLVMBuildGEP2(self.builder, array_ty_ref, array_ptr_tv.value_ref, &indices, 2, "array.elem.ptr");
    }

    fn genArrayIndex(self: *CodeGenerator, ai: *const sem.ArrayIndex) !TypedValue {
        const array_ptr_tv_opt = try self.visitNode(ai.array_ptr);
        const array_ptr_tv = array_ptr_tv_opt orelse return CodegenError.ValueNotFound;

        const idx_tv_opt = try self.visitNode(ai.index);
        const idx_tv = idx_tv_opt orelse return CodegenError.ValueNotFound;
        const index_val = try self.castIndexToI32(idx_tv);
        const array_ty_ref = try self.toLLVMType(.{ .array_type = ai.array_type });
        const elem_ptr = try self.genArrayElementPointer(array_ptr_tv, array_ty_ref, index_val);
        const elem_ty_ref = try self.toLLVMType(ai.element_type);
        const loaded = c.LLVMBuildLoad2(self.builder, elem_ty_ref, elem_ptr, "array.elem");
        return .{ .value_ref = loaded, .type_ref = elem_ty_ref };
    }

    fn genArrayStore(self: *CodeGenerator, as: *const sem.ArrayStore) !void {
        const array_ptr_tv_opt = try self.visitNode(as.array_ptr);
        const array_ptr_tv = array_ptr_tv_opt orelse return CodegenError.ValueNotFound;

        const idx_tv_opt = try self.visitNode(as.index);
        const idx_tv = idx_tv_opt orelse return CodegenError.ValueNotFound;
        const index_val = try self.castIndexToI32(idx_tv);

        const array_ty_ref = try self.toLLVMType(.{ .array_type = as.array_type });
        const elem_ptr = try self.genArrayElementPointer(array_ptr_tv, array_ty_ref, index_val);

        const value_tv_opt = try self.visitNode(as.value);
        const value_tv = value_tv_opt orelse return CodegenError.ValueNotFound;
        const elem_ty_ref = try self.toLLVMType(as.element_type);

        if (value_tv.type_ref != elem_ty_ref)
            return CodegenError.InvalidType;

        _ = c.LLVMBuildStore(self.builder, value_tv.value_ref, elem_ptr);
    }
    fn genBinaryOp(self: *CodeGenerator, bo: *const sem.BinaryOperation) !TypedValue {
        const lhs = (try self.visitNode(bo.left)) orelse return CodegenError.ValueNotFound;
        const rhs = (try self.visitNode(bo.right)) orelse return CodegenError.ValueNotFound;

        if (bo.operator == .addition) {
            const lhs_kind = c.LLVMGetTypeKind(lhs.type_ref);
            const rhs_kind = c.LLVMGetTypeKind(rhs.type_ref);
            if (lhs_kind == c.LLVMPointerTypeKind and rhs_kind == c.LLVMIntegerTypeKind)
                return try self.buildPointerOffset(lhs, rhs, "ptr.add");
            if (lhs_kind == c.LLVMIntegerTypeKind and rhs_kind == c.LLVMPointerTypeKind)
                return try self.buildPointerOffset(rhs, lhs, "ptr.add");
        }

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

    fn buildPointerOffset(
        self: *CodeGenerator,
        ptr: TypedValue,
        index: TypedValue,
        name: []const u8,
    ) !TypedValue {
        const idx_ty = c.LLVMInt64Type();
        var idx_val = index.value_ref;
        if (c.LLVMTypeOf(idx_val) != idx_ty)
            idx_val = c.LLVMBuildSExt(self.builder, idx_val, idx_ty, "idx.ext");

        var indices = [_]llvm.c.LLVMValueRef{idx_val};
        const elem_ty = c.LLVMGetElementType(ptr.type_ref);
        const name_z = try self.dupZ(name);
        const result = c.LLVMBuildGEP2(self.builder, elem_ty, ptr.value_ref, &indices, 1, name_z.ptr);
        return .{ .value_ref = result, .type_ref = ptr.type_ref };
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
        const ret_ty = self.current_return_type.?;

        // ─── caso "return expr;" ────────────────────────────────────────────
        if (r.expression) |e| {
            const tv = (try self.visitNode(e)) orelse
                return CodegenError.ValueNotFound;

            if (ret_ty == tv.type_ref) {
                _ = c.LLVMBuildRet(self.builder, tv.value_ref);
                return;
            }

            // struct-de-1-campo compactado
            if (c.LLVMGetTypeKind(ret_ty) == c.LLVMStructTypeKind and c.LLVMCountStructElementTypes(ret_ty) == 1 and c.LLVMStructGetTypeAtIndex(ret_ty, 0) == tv.type_ref) {
                var agg = c.LLVMGetUndef(ret_ty);
                agg = c.LLVMBuildInsertValue(self.builder, agg, tv.value_ref, 0, "ret.pack");
                _ = c.LLVMBuildRet(self.builder, agg);
                return;
            }

            return CodegenError.InvalidType;
        }

        // ─── caso "return;"  →  empaquetar los named returns ────────────────
        if (ret_ty == c.LLVMVoidType()) {
            _ = c.LLVMBuildRetVoid(self.builder);
            return;
        }

        // necesitamos saber los campos de salida declarados
        const fdecl = self.current_fn_decl orelse return CodegenError.InvalidType;

        var agg = c.LLVMGetUndef(ret_ty);
        for (fdecl.output.fields, 0..) |fld, i| {
            const sym = self.current_scope.lookup(fld.name).?;
            const v = c.LLVMBuildLoad2(self.builder, sym.type_ref, sym.ref, "");
            agg = c.LLVMBuildInsertValue(self.builder, agg, v, @intCast(i), "");
        }
        _ = c.LLVMBuildRet(self.builder, agg);
    }

    // ────────────────────────────────────────── call ──
    fn genFunctionCall(self: *CodeGenerator, fc: *const sem.FunctionCall) CodegenError!?TypedValue {
        const key_name = if (fc.callee.isExtern() or isMainName(fc.callee.name) or isMainCandidate(fc.callee))
            fc.callee.name
        else
            try self.mangledNameFor(fc.callee);
        const sym = self.current_scope.lookup(key_name) orelse
            return CodegenError.SymbolNotFound;
        const callee_decl = fc.callee;
        const is_extern = (callee_decl.body == null);

        // ─────── llamadas INTERNAS (idénticas a antes) ───────────────────
        if (!is_extern) {
            var sym_opt = self.current_scope.lookup(key_name);
            if (sym_opt == null) {
                // Create a forward declaration for internal function not yet emitted (e.g., monomorphized later)
                const in_ty = try self.toLLVMType(.{ .struct_type = &callee_decl.input });
                const out_ty = try self.toLLVMType(.{ .struct_type = &callee_decl.output });
                const fnty = c.LLVMFunctionType(out_ty, blk: {
                    var a = try self.allocator.alloc(llvm.c.LLVMTypeRef, 1);
                    a[0] = in_ty;
                    break :blk a.ptr;
                }, 1, 0);
                const cname = try self.dupZ(key_name);
                const fn_ref = c.LLVMAddFunction(self.module, cname.ptr, fnty);
                try self.current_scope.symbols.put(key_name, .{ .cname = cname, .mutability = .constant, .type_ref = fnty, .ref = fn_ref });
                sym_opt = self.current_scope.lookup(key_name);
            }

            const fn_ty = sym_opt.?.type_ref;
            const ret_ty = c.LLVMGetReturnType(fn_ty);

            var argv = try self.allocator.alloc(llvm.c.LLVMValueRef, 1);
            argv[0] = (try self.visitNode(fc.input)).?.value_ref;

            const call_name = if (ret_ty == c.LLVMVoidType()) "" else "call";
            const call_val = c.LLVMBuildCall2(
                self.builder,
                fn_ty,
                sym_opt.?.ref,
                argv.ptr,
                1,
                call_name,
            );

            if (ret_ty == c.LLVMVoidType()) {
                return null;
            }

            if (c.LLVMGetTypeKind(ret_ty) == c.LLVMStructTypeKind and callee_decl.output.fields.len == 1) {
                const extracted = c.LLVMBuildExtractValue(self.builder, call_val, 0, "call.unpack");
                const elem_ty = try self.toLLVMType(callee_decl.output.fields[0].ty);
                return .{ .value_ref = extracted, .type_ref = elem_ty };
            }

            return .{ .value_ref = call_val, .type_ref = ret_ty };
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

        // Build the extern call (C ABI)
        const ret_ty = c.LLVMGetReturnType(sym.type_ref);
        const call_name = if (ret_ty == c.LLVMVoidType()) "" else "call";
        const call_inst = c.LLVMBuildCall2(
            self.builder,
            sym.type_ref,
            sym.ref,
            argv.ptr,
            @intCast(idx),
            call_name,
        );

        // Return according to number of return fields
        switch (callee_decl.output.fields.len) {
            0 => return null,
            1 => {
                return .{ .value_ref = call_inst, .type_ref = ret_ty };
            },
            else => {
                const loaded = c.LLVMBuildLoad2(self.builder, sret_ty, sret_tmp, "ret");
                return .{ .value_ref = loaded, .type_ref = sret_ty };
            },
        }
    }

    fn genTypeInitializer(self: *CodeGenerator, ti: *const sem.TypeInitializer) CodegenError!TypedValue {
        const result_ty_ref = try self.toLLVMType(ti.type_decl.ty);
        const storage = c.LLVMBuildAlloca(self.builder, result_ty_ref, "type.init.tmp");

        const total_fields = ti.init_fn.input.fields.len;
        if (total_fields == 0) return CodegenError.InvalidType;
        const user_field_count = total_fields - 1;

        const args_tv_opt = try self.visitNode(ti.args);
        if (user_field_count > 0 and args_tv_opt == null)
            return CodegenError.ValueNotFound;

        const init_input_ty_ref = try self.toLLVMType(.{ .struct_type = &ti.init_fn.input });
        var agg = c.LLVMGetUndef(init_input_ty_ref);
        agg = c.LLVMBuildInsertValue(self.builder, agg, storage, 0, "ctor.arg.p");

        if (user_field_count > 0) {
            const args_tv = args_tv_opt.?;
            var i: usize = 0;
            while (i < user_field_count) : (i += 1) {
                const extracted = c.LLVMBuildExtractValue(
                    self.builder,
                    args_tv.value_ref,
                    @intCast(i),
                    "ctor.arg.extract",
                );
                agg = c.LLVMBuildInsertValue(
                    self.builder,
                    agg,
                    extracted,
                    @intCast(i + 1),
                    "ctor.arg.insert",
                );
            }
        }

        const key_name = if (ti.init_fn.isExtern() or isMainName(ti.init_fn.name) or isMainCandidate(ti.init_fn))
            ti.init_fn.name
        else
            try self.mangledNameFor(ti.init_fn);
        var sym_opt = self.current_scope.lookup(key_name);
        if (sym_opt == null) {
            const in_ty_ref = init_input_ty_ref;
            const out_ty_ref = if (ti.init_fn.output.fields.len == 0)
                c.LLVMVoidType()
            else
                try self.toLLVMType(.{ .struct_type = &ti.init_fn.output });
            const fnty = c.LLVMFunctionType(
                out_ty_ref,
                blk: {
                    var a = try self.allocator.alloc(llvm.c.LLVMTypeRef, 1);
                    a[0] = in_ty_ref;
                    break :blk a.ptr;
                },
                1,
                0,
            );
            const cname = try self.dupZ(key_name);
            const fn_ref = c.LLVMAddFunction(self.module, cname.ptr, fnty);
            try self.current_scope.symbols.put(key_name, .{ .cname = cname, .mutability = .constant, .type_ref = fnty, .ref = fn_ref });
            sym_opt = self.current_scope.lookup(key_name);
        }

        const fn_sym = sym_opt.?;
        var argv = try self.allocator.alloc(llvm.c.LLVMValueRef, 1);
        defer self.allocator.free(argv);
        argv[0] = agg;

        const call_name = if (c.LLVMGetReturnType(fn_sym.type_ref) == c.LLVMVoidType()) "" else "call";
        _ = c.LLVMBuildCall2(self.builder, fn_sym.type_ref, fn_sym.ref, argv.ptr, 1, call_name);

        const result_val = c.LLVMBuildLoad2(self.builder, result_ty_ref, storage, "type.init.result");
        return .{ .value_ref = result_val, .type_ref = result_ty_ref };
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
        const bu = node.content.binding_use;
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

    //──────────────────────────────────────── pointer store ──
    fn genPointerAssignment(self: *CodeGenerator, pa: sem.PointerAssignment) !void {
        const ptr_tv = (try self.visitNode(pa.pointer)) orelse return CodegenError.ValueNotFound;
        const rhs_tv = (try self.visitNode(pa.value)) orelse return CodegenError.ValueNotFound;

        // Basta con emitir la instrucción: tipos ya verificados antes.
        _ = c.LLVMBuildStore(self.builder, rhs_tv.value_ref, ptr_tv.value_ref);
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
