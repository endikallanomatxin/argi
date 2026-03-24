const std = @import("std");
const llvm = @import("llvm.zig");
const c = llvm.c;
const sem = @import("../4_semantics/semantic_graph.zig");
const sem_types = @import("../4_semantics/types.zig");
const syn = @import("../3_syntax/syntax_tree.zig");
const tok = @import("../2_tokens/token.zig");
const diagnostic = @import("../1_base/diagnostic.zig");

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
    sem_type: ?sem.Type = null,
    initialized: bool = false, // para bindings
};

const TypedValue = struct {
    value_ref: llvm.c.LLVMValueRef,
    type_ref: llvm.c.LLVMTypeRef,
    sem_type: ?sem.Type = null,
};

const LoopContext = struct {
    break_block: llvm.c.LLVMBasicBlockRef,
    continue_block: llvm.c.LLVMBasicBlockRef,
};

fn isUnsignedBuiltin(sem_ty: ?sem.Type) bool {
    if (sem_ty) |t| {
        if (t == .builtin) {
            return switch (t.builtin) {
                .UIntNative, .UInt8, .UInt16, .UInt32, .UInt64 => true,
                else => false,
            };
        }
    }
    return false;
}

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
    main_candidate: ?*sem.FunctionDeclaration = null,
    runtime_argc_global: ?llvm.c.LLVMValueRef = null,
    runtime_argv_global: ?llvm.c.LLVMValueRef = null,

    loop_stack: std.array_list.Managed(LoopContext),

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
            .loop_stack = std.array_list.Managed(LoopContext).init(a.*),
        };
    }

    pub fn deinit(self: *CodeGenerator) void {
        if (self.builder) |b| c.LLVMDisposeBuilder(b);

        self.loop_stack.deinit();

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

        if (self.main_candidate) |f| {
            try self.genCMainWrapper(f);
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
            .move_value => |inner| self.genMoveValue(inner) catch |e| {
                try self.diags.add(n.location, .codegen, "error generating move value: {s}", .{@errorName(e)});
                return e;
            },
            .auto_deinit_binding => |adb| {
                self.genAutoDeinitBinding(adb) catch |e| {
                    try self.diags.add(n.location, .codegen, "error generating auto deinit for {s}: {s}", .{ adb.binding.name, @errorName(e) });
                    return e;
                };
                return null;
            },
            .code_block => |cb| {
                return self.genCodeBlock(cb) catch |e| {
                    try self.diags.add(n.location, .codegen, "error generating code block: {s}", .{@errorName(e)});
                    return e;
                };
            },
            .return_statement => |r| {
                self.genReturn(r) catch |e| {
                    try self.diags.add(n.location, .codegen, "error generating return statement: {s}", .{@errorName(e)});
                    return e;
                };
                return null;
            },
            .break_statement => {
                self.genBreak(n.location) catch |e| {
                    try self.diags.add(n.location, .codegen, "error generating break statement: {s}", .{@errorName(e)});
                    return e;
                };
                return null;
            },
            .continue_statement => {
                self.genContinue(n.location) catch |e| {
                    try self.diags.add(n.location, .codegen, "error generating continue statement: {s}", .{@errorName(e)});
                    return e;
                };
                return null;
            },
            .value_literal => |_| self.genValueLiteral(n) catch |e| {
                try self.diags.add(n.location, .codegen, "error generating value literal: {s}", .{@errorName(e)});
                return e;
            },
            .choice_literal => |lit| self.genChoiceLiteral(lit) catch |e| {
                try self.diags.add(n.location, .codegen, "error generating choice literal: {s}", .{@errorName(e)});
                return e;
            },
            .array_literal => |al| self.genArrayLiteral(al) catch |e| {
                try self.diags.add(n.location, .codegen, "error generating array literal: {s}", .{@errorName(e)});
                return e;
            },
            .struct_field_store => |sf| {
                self.genStructFieldStore(&sf) catch |e| {
                    try self.diags.add(n.location, .codegen, "error generating struct field store: {s}", .{@errorName(e)});
                    return e;
                };
                return null;
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
            .while_statement => |w| {
                self.genWhileStatement(w) catch |e| {
                    try self.diags.add(n.location, .codegen, "error generating while statement: {s}", .{@errorName(e)});
                    return e;
                };
                return null;
            },
            .switch_statement => |sw| {
                self.genSwitchStatement(sw) catch |e| {
                    try self.diags.add(n.location, .codegen, "error generating switch statement: {s}", .{@errorName(e)});
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
            .choice_payload_access => |acc| self.genChoicePayloadAccess(acc) catch |e| {
                try self.diags.add(n.location, .codegen, "error generating choice payload access: {s}", .{@errorName(e)});
                return e;
            },
            .address_of => |_| self.genAddressOf(n) catch |e| {
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
            .explicit_cast => |ec| self.genExplicitCast(ec) catch |e| {
                try self.diags.add(n.location, .codegen, "error generating explicit cast: {s}", .{@errorName(e)});
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
                .UIntNative => switch (sem_types.pointer_size_bytes) {
                    2 => c.LLVMInt16Type(),
                    4 => c.LLVMInt32Type(),
                    8 => c.LLVMInt64Type(),
                    else => return CodegenError.InvalidType,
                },
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
            .choice_type => |ct| blk_choice: {
                const field_count: usize = ct.variants.len + 1;
                var fields = try self.allocator.alloc(llvm.c.LLVMTypeRef, field_count);
                fields[0] = c.LLVMInt32Type();
                for (ct.variants, 0..) |variant, idx| {
                    const payload_ty = variant.payload_type orelse sem.Type{ .builtin = .UInt8 };
                    fields[idx + 1] = try self.toLLVMType(payload_ty);
                }
                break :blk_choice c.LLVMStructType(fields.ptr, @intCast(field_count), 0);
            },
            .abstract_type => CodegenError.InvalidType,
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

    fn encodeType(self: *CodeGenerator, buf: *std.array_list.Managed(u8), t: sem.Type) !void {
        switch (t) {
            .builtin => |bt| {
                const s = switch (bt) {
                    .Int8 => "i8",
                    .Int16 => "i16",
                    .Int32 => "i32",
                    .Int64 => "i64",
                    .UIntNative => "unative",
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
            .choice_type => |_| {
                try buf.appendSlice("choice");
            },
            .abstract_type => |at| {
                try buf.appendSlice("abs_");
                try buf.appendSlice(at.name);
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
        var buf = std.array_list.Managed(u8).init(self.allocator.*);
        try buf.appendSlice(f.name);
        try buf.appendSlice("__in_");
        try self.encodeType(&buf, .{ .struct_type = &f.input });
        // not including output in the mangle for now
        return try buf.toOwnedSlice();
    }

    fn isWrappableMainCandidate(f: *const sem.FunctionDeclaration) bool {
        if (!isMainName(f.name)) return false;
        if (f.output.fields.len != 1) return false;
        const fld = f.output.fields[0];
        if (!std.mem.eql(u8, fld.name, "status_code")) return false;
        return switch (fld.ty) {
            .builtin => |bt| bt == .Int32,
            else => false,
        };
    }

    fn functionSymbolKey(self: *CodeGenerator, f: *const sem.FunctionDeclaration) ![]const u8 {
        if (f.isExtern()) return f.name;
        return try self.mangledNameFor(f);
    }

    fn genFunction(self: *CodeGenerator, f: *sem.FunctionDeclaration) !void {
        const prev_fn = self.current_fn_decl;
        self.current_fn_decl = f;
        defer self.current_fn_decl = prev_fn;

        if (isWrappableMainCandidate(f)) {
            self.main_candidate = f;
        }

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
        const key_name = try self.functionSymbolKey(f);
        const cname = try self.dupZ(key_name);
        const fn_ref = c.LLVMAddFunction(self.module, cname.ptr, fn_ty);

        if (is_extern and uses_sret) {
            const kind = c.LLVMGetEnumAttributeKindForName("sret", 4);
            const attr = c.LLVMCreateEnumAttribute(c.LLVMGetGlobalContext(), kind, 0);
            c.LLVMAddAttributeAtIndex(fn_ref, 1, attr); // 1-based
        }

        try self.current_scope.symbols.put(
            key_name,
            .{ .cname = cname, .mutability = .constant, .type_ref = fn_ty, .ref = fn_ref, .sem_type = null },
        );

        if (is_extern and std.mem.eql(u8, f.name, "__argi_runtime_argc")) {
            try self.ensureRuntimeArgGlobals();
            const entry = c.LLVMAppendBasicBlock(fn_ref, "entry");
            c.LLVMPositionBuilderAtEnd(self.builder, entry);
            const argc_ptr = self.runtime_argc_global orelse return CodegenError.InvalidType;
            const native_uint_ty = try self.toLLVMType(.{ .builtin = .UIntNative });
            const value = c.LLVMBuildLoad2(self.builder, native_uint_ty, argc_ptr, "runtime.argc");
            _ = c.LLVMBuildRet(self.builder, value);
            return;
        }

        if (is_extern and std.mem.eql(u8, f.name, "__argi_runtime_argv")) {
            try self.ensureRuntimeArgGlobals();
            const entry = c.LLVMAppendBasicBlock(fn_ref, "entry");
            c.LLVMPositionBuilderAtEnd(self.builder, entry);
            const argv_ptr = self.runtime_argv_global orelse return CodegenError.InvalidType;
            const native_uint_ty = try self.toLLVMType(.{ .builtin = .UIntNative });
            const value = c.LLVMBuildLoad2(self.builder, native_uint_ty, argv_ptr, "runtime.argv");
            _ = c.LLVMBuildRet(self.builder, value);
            return;
        }

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
                .origin_file = f.location.file,
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
                .origin_file = f.location.file,
                .mutability = syn.Mutability.variable,
                .ty = fld.ty,
                .initialization = null,
            };
            try self.genBindingDecl(&bd);
        }

        // cuerpo del usuario
        _ = try self.genCodeBlock(f.body.?);

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
            const cur_bb = c.LLVMGetInsertBlock(self.builder);
            const fnc = c.LLVMGetBasicBlockParent(cur_bb);
            const entry_bb = c.LLVMGetEntryBasicBlock(fnc);
            const tmp_builder = c.LLVMCreateBuilder();
            defer c.LLVMDisposeBuilder(tmp_builder);

            if (c.LLVMGetFirstInstruction(entry_bb)) |first_inst| {
                c.LLVMPositionBuilderBefore(tmp_builder, first_inst);
            } else {
                c.LLVMPositionBuilderAtEnd(tmp_builder, entry_bb);
            }

            storage = c.LLVMBuildAlloca(tmp_builder, llvm_decl_ty, cname.ptr);
        }

        // 4) registrar en la tabla
        try self.current_scope.symbols.put(b.name, .{
            .cname = cname,
            .mutability = b.mutability,
            .type_ref = llvm_decl_ty,
            .ref = storage,
            .sem_type = b.ty,
            .initialized = init_tv != null,
        });

        // 5) almacenar valor inicial
        if (init_tv) |tv_raw| {
            const tv = tv_raw;
            // Global initializers must be constant; for now, only allow none
            if (self.current_scope.parent == null) {
                // Non-constant global init not supported yet; ignore for now
                // (could enhance by constant-folding later)
                return;
            }

            if (tv.type_ref == llvm_decl_ty) {
                _ = c.LLVMBuildStore(self.builder, tv.value_ref, storage);
            } else {
                return CodegenError.InvalidType;
            }
        }
    }

    fn genBindingUse(self: *CodeGenerator, b: *sem.BindingDeclaration) !TypedValue {
        const sym = self.current_scope.lookup(b.name) orelse
            return CodegenError.SymbolNotFound;
        const val = c.LLVMBuildLoad2(self.builder, sym.type_ref, sym.ref, sym.cname.ptr);
        return .{ .value_ref = val, .type_ref = sym.type_ref, .sem_type = sym.sem_type };
    }

    fn genMoveValue(self: *CodeGenerator, inner: *const sem.SGNode) !TypedValue {
        if (inner.content != .binding_use) return CodegenError.InvalidType;
        const binding = inner.content.binding_use;
        const sym = self.current_scope.lookup(binding.name) orelse
            return CodegenError.SymbolNotFound;

        const val = c.LLVMBuildLoad2(self.builder, sym.type_ref, sym.ref, sym.cname.ptr);
        sym.initialized = false;
        return .{ .value_ref = val, .type_ref = sym.type_ref, .sem_type = sym.sem_type };
    }

    fn genAutoDeinitBinding(self: *CodeGenerator, adb: *const sem.AutoDeinitBinding) !void {
        const sym = self.current_scope.lookup(adb.binding.name) orelse
            return CodegenError.SymbolNotFound;
        if (!sym.initialized) return;

        const deinit_fn_name = try self.mangledNameFor(adb.deinit_fn);
        _ = self.current_scope.lookup(deinit_fn_name) orelse
            self.current_scope.lookup(adb.deinit_fn.name) orelse
            return CodegenError.SymbolNotFound;

        const binding_use = try sem.makeSGNode(.{ .binding_use = @constCast(adb.binding) }, adb.deinit_fn.location, self.allocator);
        const addr_node = try sem.makeSGNode(.{ .address_of = binding_use }, adb.deinit_fn.location, self.allocator);

        const arg_fields = try self.allocator.alloc(sem.StructValueLiteralField, 1);
        arg_fields[0] = .{ .name = adb.deinit_fn.input.fields[0].name, .value = addr_node };

        const args_struct = try self.allocator.create(sem.StructValueLiteral);
        args_struct.* = .{
            .fields = arg_fields,
            .ty = .{ .struct_type = &adb.deinit_fn.input },
        };

        const args_node = try sem.makeSGNode(.{ .struct_value_literal = args_struct }, adb.deinit_fn.location, self.allocator);
        const call = try self.allocator.create(sem.FunctionCall);
        call.* = .{ .callee = adb.deinit_fn, .input = args_node };
        const call_node = try sem.makeSGNode(.{ .function_call = call }, adb.deinit_fn.location, self.allocator);
        _ = try self.visitNode(call_node);
        sym.initialized = false;
    }

    // ────────────────────────────────────────── assignment ──
    fn genAssignment(self: *CodeGenerator, a: *sem.Assignment) !TypedValue {
        const sym_ptr = self.current_scope.lookup(a.sym_id.name) orelse
            return CodegenError.SymbolNotFound;

        // Const sólo falla si *ya* estaba inicializado
        if (sym_ptr.*.mutability == .constant and sym_ptr.*.initialized)
            return CodegenError.ConstantReassignment;

        const rhs = (try self.visitNode(a.value)) orelse return CodegenError.ValueNotFound;
        const rhs_val = rhs.value_ref;
        const rhs_ty = rhs.type_ref;

        if (sym_ptr.*.type_ref != rhs_ty)
            return CodegenError.InvalidType;

        _ = c.LLVMBuildStore(self.builder, rhs_val, sym_ptr.*.ref);
        sym_ptr.*.initialized = true;
        return .{ .value_ref = rhs_val, .type_ref = sym_ptr.*.type_ref, .sem_type = sym_ptr.*.sem_type };
    }

    // ────────────────────────────────────────── literals ──
    fn genValueLiteral(self: *CodeGenerator, n: *const sem.SGNode) !TypedValue {
        const l = n.content.value_literal;
        const sem_ty = if (n.sem_type) |ty| ty else self.inferLiteralSemType(n);

        return switch (l) {
            .int_literal => |v| blk_int: {
                const target_ty = if (sem_ty) |t| try self.toLLVMType(t) else c.LLVMInt32Type();
                break :blk_int .{
                    .type_ref = target_ty,
                    .value_ref = c.LLVMConstInt(target_ty, @bitCast(v), if (v < 0) 1 else 0),
                    .sem_type = sem_ty,
                };
            },
            .float_literal => |f| blk_float: {
                const target_ty = if (sem_ty) |t| try self.toLLVMType(t) else c.LLVMFloatType();
                break :blk_float .{
                    .type_ref = target_ty,
                    .value_ref = c.LLVMConstReal(target_ty, f),
                    .sem_type = sem_ty,
                };
            },
            .char_literal => |ch| .{ .type_ref = c.LLVMInt8Type(), .value_ref = c.LLVMConstInt(c.LLVMInt8Type(), @intCast(ch), 0), .sem_type = sem_ty },
            .string_literal => |str| blk: {
                // TODO: For now, we will use c-like strings.
                // Later on, this should be a proper string type.

                const str_z = try self.dupZ(str);

                // Crea un global interno y recibe el i8* a su inicio
                const gptr = c.LLVMBuildGlobalStringPtr(
                    self.builder,
                    str_z.ptr,
                    "strlit",
                );
                break :blk .{
                    .type_ref = c.LLVMPointerType(c.LLVMInt8Type(), 0),
                    .value_ref = gptr,
                    .sem_type = sem_ty,
                };
            },
            else => CodegenError.NotYetImplemented,
        };
    }

    fn genChoiceLiteral(self: *CodeGenerator, lit: *const sem.ChoiceLiteral) !TypedValue {
        const choice_ty = sem.Type{ .choice_type = lit.choice_type };
        const llvm_ty = try self.toLLVMType(choice_ty);

        var agg = c.LLVMGetUndef(llvm_ty);
        const tag_val = c.LLVMConstInt(c.LLVMInt32Type(), @intCast(lit.variant_index), 0);
        agg = c.LLVMBuildInsertValue(self.builder, agg, tag_val, 0, "choice.tag");

        if (lit.payload) |payload_node| {
            const payload_tv = (try self.visitNode(payload_node)) orelse return CodegenError.ValueNotFound;
            agg = c.LLVMBuildInsertValue(
                self.builder,
                agg,
                payload_tv.value_ref,
                lit.variant_index + 1,
                "choice.payload",
            );
        }

        return .{ .value_ref = agg, .type_ref = llvm_ty, .sem_type = choice_ty };
    }

    fn inferLiteralSemType(self: *CodeGenerator, n: *const sem.SGNode) ?sem.Type {
        _ = self;
        return switch (n.content.value_literal) {
            .int_literal => null,
            .float_literal => null,
            .char_literal => .{ .builtin = .Char },
            .string_literal => null,
            .bool_literal => .{ .builtin = .Bool },
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

    fn expectNativeIndex(self: *CodeGenerator, tv: TypedValue) !llvm.c.LLVMValueRef {
        const native_index_ty = try self.toLLVMType(.{ .builtin = .UIntNative });
        if (tv.type_ref != native_index_ty)
            return CodegenError.InvalidType;
        return tv.value_ref;
    }

    fn genArrayElementPointer(
        self: *CodeGenerator,
        array_ptr_tv: TypedValue,
        array_ty_ref: llvm.c.LLVMTypeRef,
        index_val: llvm.c.LLVMValueRef,
    ) !llvm.c.LLVMValueRef {
        const index_ty = try self.toLLVMType(.{ .builtin = .UIntNative });
        const zero = c.LLVMConstInt(index_ty, 0, 0);
        var indices = [_]llvm.c.LLVMValueRef{ zero, index_val };
        return c.LLVMBuildGEP2(self.builder, array_ty_ref, array_ptr_tv.value_ref, &indices, 2, "array.elem.ptr");
    }

    fn genArrayIndex(self: *CodeGenerator, ai: *const sem.ArrayIndex) !TypedValue {
        const array_ptr_tv_opt = try self.visitNode(ai.array_ptr);
        const array_ptr_tv = array_ptr_tv_opt orelse return CodegenError.ValueNotFound;

        const idx_tv_opt = try self.visitNode(ai.index);
        const idx_tv = idx_tv_opt orelse return CodegenError.ValueNotFound;
        const index_val = try self.expectNativeIndex(idx_tv);
        const array_ty_ref = try self.toLLVMType(.{ .array_type = ai.array_type });
        const elem_ptr = try self.genArrayElementPointer(array_ptr_tv, array_ty_ref, index_val);
        const elem_ty_ref = try self.toLLVMType(ai.element_type);
        const loaded = c.LLVMBuildLoad2(self.builder, elem_ty_ref, elem_ptr, "array.elem");
        return .{ .value_ref = loaded, .type_ref = elem_ty_ref, .sem_type = ai.element_type };
    }

    fn genArrayStore(self: *CodeGenerator, as: *const sem.ArrayStore) !void {
        const array_ptr_tv_opt = try self.visitNode(as.array_ptr);
        const array_ptr_tv = array_ptr_tv_opt orelse return CodegenError.ValueNotFound;

        const idx_tv_opt = try self.visitNode(as.index);
        const idx_tv = idx_tv_opt orelse return CodegenError.ValueNotFound;
        const index_val = try self.expectNativeIndex(idx_tv);

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
        const lhs_tv = (try self.visitNode(bo.left)) orelse return CodegenError.ValueNotFound;
        const rhs_tv = (try self.visitNode(bo.right)) orelse return CodegenError.ValueNotFound;

        if (bo.operator == .addition) {
            const lhs_kind = c.LLVMGetTypeKind(lhs_tv.type_ref);
            const rhs_kind = c.LLVMGetTypeKind(rhs_tv.type_ref);
            if (lhs_kind == c.LLVMPointerTypeKind and rhs_kind == c.LLVMIntegerTypeKind)
                return try self.buildPointerOffset(lhs_tv, rhs_tv, "ptr.add");
            if (lhs_kind == c.LLVMIntegerTypeKind and rhs_kind == c.LLVMPointerTypeKind)
                return try self.buildPointerOffset(rhs_tv, lhs_tv, "ptr.add");
        }

        if (lhs_tv.type_ref != rhs_tv.type_ref)
            return CodegenError.InvalidType;

        const is_float = lhs_tv.type_ref == c.LLVMFloatType();
        const use_unsigned = isUnsignedBuiltin(lhs_tv.sem_type);

        const val = switch (bo.operator) {
            .addition => if (is_float) c.LLVMBuildFAdd(self.builder, lhs_tv.value_ref, rhs_tv.value_ref, "add") else c.LLVMBuildAdd(self.builder, lhs_tv.value_ref, rhs_tv.value_ref, "add"),
            .subtraction => if (is_float) c.LLVMBuildFSub(self.builder, lhs_tv.value_ref, rhs_tv.value_ref, "sub") else c.LLVMBuildSub(self.builder, lhs_tv.value_ref, rhs_tv.value_ref, "sub"),
            .multiplication => if (is_float) c.LLVMBuildFMul(self.builder, lhs_tv.value_ref, rhs_tv.value_ref, "mul") else c.LLVMBuildMul(self.builder, lhs_tv.value_ref, rhs_tv.value_ref, "mul"),
            .division => if (is_float)
                c.LLVMBuildFDiv(self.builder, lhs_tv.value_ref, rhs_tv.value_ref, "div")
            else if (use_unsigned)
                c.LLVMBuildUDiv(self.builder, lhs_tv.value_ref, rhs_tv.value_ref, "div")
            else
                c.LLVMBuildSDiv(self.builder, lhs_tv.value_ref, rhs_tv.value_ref, "div"),
            .modulo => if (is_float)
                c.LLVMBuildFRem(self.builder, lhs_tv.value_ref, rhs_tv.value_ref, "rem")
            else if (use_unsigned)
                c.LLVMBuildURem(self.builder, lhs_tv.value_ref, rhs_tv.value_ref, "rem")
            else
                c.LLVMBuildSRem(self.builder, lhs_tv.value_ref, rhs_tv.value_ref, "rem"),
        };

        return .{ .value_ref = val, .type_ref = lhs_tv.type_ref, .sem_type = lhs_tv.sem_type };
    }

    fn buildPointerOffset(
        self: *CodeGenerator,
        ptr: TypedValue,
        index: TypedValue,
        name: []const u8,
    ) !TypedValue {
        const idx_ty = c.LLVMInt64Type();
        const idx_val = index.value_ref;
        if (c.LLVMTypeOf(idx_val) != idx_ty)
            return CodegenError.InvalidType;

        var indices = [_]llvm.c.LLVMValueRef{idx_val};
        const elem_ty = c.LLVMGetElementType(ptr.type_ref);
        const name_z = try self.dupZ(name);
        const result = c.LLVMBuildGEP2(self.builder, elem_ty, ptr.value_ref, &indices, 1, name_z.ptr);
        return .{ .value_ref = result, .type_ref = ptr.type_ref };
    }

    // ────────────────────────────────────────── comparison ──
    fn genComparison(self: *CodeGenerator, co: *const sem.Comparison) !TypedValue {
        const lhs_tv = (try self.visitNode(co.left)) orelse return CodegenError.ValueNotFound;
        const rhs_tv = (try self.visitNode(co.right)) orelse return CodegenError.ValueNotFound;

        if (lhs_tv.type_ref != rhs_tv.type_ref)
            return CodegenError.InvalidType;

        if (lhs_tv.sem_type) |lhs_sem_ty| {
            if (lhs_sem_ty == .choice_type) {
                const lhs_tag = c.LLVMBuildExtractValue(self.builder, lhs_tv.value_ref, 0, "choice.lhs.tag");
                const rhs_tag = c.LLVMBuildExtractValue(self.builder, rhs_tv.value_ref, 0, "choice.rhs.tag");
                const val = switch (co.operator) {
                    .equal => c.LLVMBuildICmp(self.builder, c.LLVMIntEQ, lhs_tag, rhs_tag, "choice.eq"),
                    .not_equal => c.LLVMBuildICmp(self.builder, c.LLVMIntNE, lhs_tag, rhs_tag, "choice.ne"),
                    .less_than => c.LLVMBuildICmp(self.builder, c.LLVMIntSLT, lhs_tag, rhs_tag, "choice.lt"),
                    .greater_than => c.LLVMBuildICmp(self.builder, c.LLVMIntSGT, lhs_tag, rhs_tag, "choice.gt"),
                    .less_than_or_equal => c.LLVMBuildICmp(self.builder, c.LLVMIntSLE, lhs_tag, rhs_tag, "choice.le"),
                    .greater_than_or_equal => c.LLVMBuildICmp(self.builder, c.LLVMIntSGE, lhs_tag, rhs_tag, "choice.ge"),
                };
                return .{ .value_ref = val, .type_ref = c.LLVMInt1Type() };
            }
        }

        const is_float = lhs_tv.type_ref == c.LLVMFloatType();
        const use_unsigned = isUnsignedBuiltin(lhs_tv.sem_type);

        const val = switch (co.operator) {
            .equal => if (is_float)
                c.LLVMBuildFCmp(self.builder, c.LLVMRealOEQ, lhs_tv.value_ref, rhs_tv.value_ref, "feq")
            else
                c.LLVMBuildICmp(self.builder, c.LLVMIntEQ, lhs_tv.value_ref, rhs_tv.value_ref, "ieq"),

            .not_equal => if (is_float)
                c.LLVMBuildFCmp(self.builder, c.LLVMRealONE, lhs_tv.value_ref, rhs_tv.value_ref, "fne")
            else
                c.LLVMBuildICmp(self.builder, c.LLVMIntNE, lhs_tv.value_ref, rhs_tv.value_ref, "ine"),

            .less_than => if (is_float)
                c.LLVMBuildFCmp(self.builder, c.LLVMRealOLT, lhs_tv.value_ref, rhs_tv.value_ref, "flt")
            else if (use_unsigned)
                c.LLVMBuildICmp(self.builder, c.LLVMIntULT, lhs_tv.value_ref, rhs_tv.value_ref, "ilt")
            else
                c.LLVMBuildICmp(self.builder, c.LLVMIntSLT, lhs_tv.value_ref, rhs_tv.value_ref, "ilt"),

            .greater_than => if (is_float)
                c.LLVMBuildFCmp(self.builder, c.LLVMRealOGT, lhs_tv.value_ref, rhs_tv.value_ref, "fgt")
            else if (use_unsigned)
                c.LLVMBuildICmp(self.builder, c.LLVMIntUGT, lhs_tv.value_ref, rhs_tv.value_ref, "igt")
            else
                c.LLVMBuildICmp(self.builder, c.LLVMIntSGT, lhs_tv.value_ref, rhs_tv.value_ref, "igt"),

            .less_than_or_equal => if (is_float)
                c.LLVMBuildFCmp(self.builder, c.LLVMRealOLE, lhs_tv.value_ref, rhs_tv.value_ref, "fle")
            else if (use_unsigned)
                c.LLVMBuildICmp(self.builder, c.LLVMIntULE, lhs_tv.value_ref, rhs_tv.value_ref, "ile")
            else
                c.LLVMBuildICmp(self.builder, c.LLVMIntSLE, lhs_tv.value_ref, rhs_tv.value_ref, "ile"),

            .greater_than_or_equal => if (is_float)
                c.LLVMBuildFCmp(self.builder, c.LLVMRealOGE, lhs_tv.value_ref, rhs_tv.value_ref, "fge")
            else if (use_unsigned)
                c.LLVMBuildICmp(self.builder, c.LLVMIntUGE, lhs_tv.value_ref, rhs_tv.value_ref, "ige")
            else
                c.LLVMBuildICmp(self.builder, c.LLVMIntSGE, lhs_tv.value_ref, rhs_tv.value_ref, "ige"),
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
        _ = try self.genCodeBlock(i.then_block);
        if (c.LLVMGetBasicBlockTerminator(thenB) == null)
            _ = c.LLVMBuildBr(self.builder, endB);

        if (i.else_block) |eb| {
            c.LLVMPositionBuilderAtEnd(self.builder, elseB.?);
            _ = try self.genCodeBlock(eb);
            if (c.LLVMGetBasicBlockTerminator(elseB.?) == null)
                _ = c.LLVMBuildBr(self.builder, endB);
        }
        c.LLVMPositionBuilderAtEnd(self.builder, endB);
    }

    fn genWhileStatement(self: *CodeGenerator, w: *const sem.WhileStatement) !void {
        const cur_bb = c.LLVMGetInsertBlock(self.builder);
        const fnc = c.LLVMGetBasicBlockParent(cur_bb);
        const condB = c.LLVMAppendBasicBlock(fnc, "while.cond");
        const bodyB = c.LLVMAppendBasicBlock(fnc, "while.body");
        const endB = c.LLVMAppendBasicBlock(fnc, "while.end");

        _ = c.LLVMBuildBr(self.builder, condB);

        c.LLVMPositionBuilderAtEnd(self.builder, condB);
        const cond_tv = (try self.visitNode(w.condition)) orelse return CodegenError.ValueNotFound;
        _ = c.LLVMBuildCondBr(self.builder, cond_tv.value_ref, bodyB, endB);

        c.LLVMPositionBuilderAtEnd(self.builder, bodyB);
        try self.loop_stack.append(.{ .break_block = endB, .continue_block = condB });
        defer _ = self.loop_stack.pop();
        _ = try self.genCodeBlock(w.body);
        if (c.LLVMGetBasicBlockTerminator(bodyB) == null)
            _ = c.LLVMBuildBr(self.builder, condB);

        c.LLVMPositionBuilderAtEnd(self.builder, endB);
    }

    fn genBreak(self: *CodeGenerator, loc: tok.Location) !void {
        if (self.loop_stack.items.len == 0) {
            try self.diags.add(loc, .codegen, "break used outside of a loop", .{});
            return CodegenError.CompilationFailed;
        }
        const loop_ctx = self.loop_stack.items[self.loop_stack.items.len - 1];
        _ = c.LLVMBuildBr(self.builder, loop_ctx.break_block);
    }

    fn genContinue(self: *CodeGenerator, loc: tok.Location) !void {
        if (self.loop_stack.items.len == 0) {
            try self.diags.add(loc, .codegen, "continue used outside of a loop", .{});
            return CodegenError.CompilationFailed;
        }
        const loop_ctx = self.loop_stack.items[self.loop_stack.items.len - 1];
        _ = c.LLVMBuildBr(self.builder, loop_ctx.continue_block);
    }

    fn genSwitchStatement(self: *CodeGenerator, sw: *const sem.SwitchStatement) !void {
        const expr_tv = (try self.visitNode(sw.expression)) orelse return CodegenError.ValueNotFound;
        const tag_val = c.LLVMBuildExtractValue(self.builder, expr_tv.value_ref, 0, "match.tag");

        const cur_bb = c.LLVMGetInsertBlock(self.builder);
        const fnc = c.LLVMGetBasicBlockParent(cur_bb);
        const endB = c.LLVMAppendBasicBlock(fnc, "match.end");
        const defaultB = if (sw.default_case != null) c.LLVMAppendBasicBlock(fnc, "match.default") else endB;

        const switch_inst = c.LLVMBuildSwitch(self.builder, tag_val, defaultB, @intCast(sw.cases.len));
        var case_blocks = try self.allocator.alloc(c.LLVMBasicBlockRef, sw.cases.len);
        defer self.allocator.free(case_blocks);

        for (sw.cases, 0..) |case_item, idx| {
            const case_name = try std.fmt.allocPrint(self.allocator.*, "match.case.{d}", .{idx});
            const case_name_z = try self.dupZ(case_name);
            case_blocks[idx] = c.LLVMAppendBasicBlock(fnc, case_name_z.ptr);
            const case_lit = case_item.value.content.choice_literal;
            const case_tag = c.LLVMConstInt(c.LLVMInt32Type(), case_lit.variant_index, 0);
            c.LLVMAddCase(switch_inst, case_tag, case_blocks[idx]);
        }

        for (sw.cases, 0..) |case_item, idx| {
            c.LLVMPositionBuilderAtEnd(self.builder, case_blocks[idx]);
            _ = try self.genCodeBlock(case_item.body);
            if (c.LLVMGetBasicBlockTerminator(case_blocks[idx]) == null)
                _ = c.LLVMBuildBr(self.builder, endB);
        }

        if (sw.default_case) |default_case| {
            c.LLVMPositionBuilderAtEnd(self.builder, defaultB);
            _ = try self.genCodeBlock(default_case);
            if (c.LLVMGetBasicBlockTerminator(defaultB) == null)
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
        const key_name = try self.functionSymbolKey(fc.callee);
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
                try self.current_scope.symbols.put(key_name, .{ .cname = cname, .mutability = .constant, .type_ref = fnty, .ref = fn_ref, .sem_type = null });
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
                return .{ .value_ref = extracted, .type_ref = elem_ty, .sem_type = callee_decl.output.fields[0].ty };
            }

            return .{
                .value_ref = call_val,
                .type_ref = ret_ty,
                .sem_type = .{ .struct_type = &callee_decl.output },
            };
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
                return .{ .value_ref = call_inst, .type_ref = ret_ty, .sem_type = callee_decl.output.fields[0].ty };
            },
            else => {
                const loaded = c.LLVMBuildLoad2(self.builder, sret_ty, sret_tmp, "ret");
                return .{ .value_ref = loaded, .type_ref = sret_ty, .sem_type = .{ .struct_type = &callee_decl.output } };
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

        const key_name = try self.functionSymbolKey(ti.init_fn);
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
            try self.current_scope.symbols.put(key_name, .{ .cname = cname, .mutability = .constant, .type_ref = fnty, .ref = fn_ref, .sem_type = null });
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
        const ty = try self.toLLVMType(sl.ty);
        var vals = try self.allocator.alloc(TypedValue, cnt);
        defer self.allocator.free(vals);

        for (sl.fields, 0..) |f, i| {
            const field_tv_opt = try self.visitNode(f.value);
            const field_tv = field_tv_opt orelse return CodegenError.ValueNotFound;
            const field_ll_ty = c.LLVMStructGetTypeAtIndex(ty, @intCast(i));
            if (field_tv.type_ref != field_ll_ty)
                return CodegenError.InvalidType;
            vals[i] = field_tv;
        }

        // construir el agregado en tiempo de ejecución
        var agg = c.LLVMGetUndef(ty);
        for (vals, 0..) |tv, i|
            agg = c.LLVMBuildInsertValue(self.builder, agg, tv.value_ref, @intCast(i), "lit.insert");

        return .{ .value_ref = agg, .type_ref = ty, .sem_type = sl.ty };
    }

    // ────────────────────────────────────────── struct field access ──
    fn genStructFieldAccess(self: *CodeGenerator, fa: *const sem.StructFieldAccess) !TypedValue {
        const base = (try self.visitNode(fa.struct_value)) orelse
            return CodegenError.ValueNotFound;

        // el índice ya viene resuelto por el semantizador
        const val = c.LLVMBuildExtractValue(self.builder, base.value_ref, fa.field_index, "fld");

        const field_ty = c.LLVMStructGetTypeAtIndex(base.type_ref, fa.field_index);
        var field_sem_ty: ?sem.Type = null;
        if (base.sem_type) |sem_ty| {
            if (sem_ty == .struct_type) {
                field_sem_ty = sem_ty.struct_type.fields[fa.field_index].ty;
            }
        }

        return .{ .value_ref = val, .type_ref = field_ty, .sem_type = field_sem_ty };
    }

    fn genChoicePayloadAccess(self: *CodeGenerator, acc: *const sem.ChoicePayloadAccess) !TypedValue {
        const base = (try self.visitNode(acc.choice_value)) orelse return CodegenError.ValueNotFound;
        const val = c.LLVMBuildExtractValue(self.builder, base.value_ref, acc.variant_index + 1, "choice.payload");
        const payload_ty = try self.toLLVMType(acc.payload_type);
        return .{ .value_ref = val, .type_ref = payload_ty, .sem_type = acc.payload_type };
    }

    fn genStructFieldStore(self: *CodeGenerator, sf: *const sem.StructFieldStore) !void {
        const struct_ptr_tv_opt = try self.visitNode(sf.struct_ptr);
        const struct_ptr_tv = struct_ptr_tv_opt orelse return CodegenError.ValueNotFound;

        if (c.LLVMGetTypeKind(struct_ptr_tv.type_ref) != c.LLVMPointerTypeKind)
            return CodegenError.InvalidType;

        const struct_ty_ref = try self.toLLVMType(.{ .struct_type = sf.struct_type });
        const field_ptr = c.LLVMBuildStructGEP2(
            self.builder,
            struct_ty_ref,
            struct_ptr_tv.value_ref,
            sf.field_index,
            "field.ptr",
        );

        const value_tv_opt = try self.visitNode(sf.value);
        const value_tv = value_tv_opt orelse return CodegenError.ValueNotFound;
        const field_ty_ref = try self.toLLVMType(sf.field_type);
        if (value_tv.type_ref != field_ty_ref)
            return CodegenError.InvalidType;

        _ = c.LLVMBuildStore(self.builder, value_tv.value_ref, field_ptr);
    }

    // ────────────────────────────────────────── address-of ──
    fn genAddressOf(self: *CodeGenerator, node: *const sem.SGNode) !TypedValue {
        const target = node.content.address_of;
        const ptr_tv = try self.genAddressablePointer(target);
        return .{ .value_ref = ptr_tv.value_ref, .type_ref = ptr_tv.type_ref, .sem_type = node.sem_type };
    }

    fn addressableValueType(self: *CodeGenerator, target: *const sem.SGNode) !sem.Type {
        return switch (target.content) {
            .binding_use => |bu| blk: {
                const sym = self.current_scope.lookup(bu.name) orelse return CodegenError.SymbolNotFound;
                break :blk sym.sem_type orelse return CodegenError.InvalidType;
            },
            .struct_field_access => |sfa| blk: {
                const base_ty = try self.addressableValueType(sfa.struct_value);
                if (base_ty != .struct_type) return CodegenError.InvalidType;
                if (sfa.field_index >= base_ty.struct_type.fields.len) return CodegenError.InvalidType;
                break :blk base_ty.struct_type.fields[sfa.field_index].ty;
            },
            .dereference => |d| d.ty,
            else => CodegenError.InvalidType,
        };
    }

    fn genAddressablePointer(self: *CodeGenerator, target: *const sem.SGNode) !TypedValue {
        return switch (target.content) {
            .binding_use => |bu| blk: {
                const sym = self.current_scope.lookup(bu.name) orelse
                    return CodegenError.SymbolNotFound;
                const ptr_ty = c.LLVMPointerType(sym.type_ref, 0);
                break :blk .{ .value_ref = sym.ref, .type_ref = ptr_ty, .sem_type = null };
            },
            .struct_field_access => |sfa| blk: {
                const base_ptr = try self.genAddressablePointer(sfa.struct_value);
                const base_sem_ty = try self.addressableValueType(sfa.struct_value);
                if (base_sem_ty != .struct_type) return CodegenError.InvalidType;
                const struct_ty_ref = try self.toLLVMType(.{ .struct_type = base_sem_ty.struct_type });
                const field_ptr = c.LLVMBuildStructGEP2(
                    self.builder,
                    struct_ty_ref,
                    base_ptr.value_ref,
                    sfa.field_index,
                    "field.addr",
                );
                const field_ty_ref = c.LLVMStructGetTypeAtIndex(struct_ty_ref, sfa.field_index);
                break :blk .{ .value_ref = field_ptr, .type_ref = c.LLVMPointerType(field_ty_ref, 0), .sem_type = null };
            },
            .dereference => |d| blk: {
                const ptr_tv = (try self.visitNode(d.pointer)) orelse return CodegenError.ValueNotFound;
                break :blk ptr_tv;
            },
            else => CodegenError.InvalidType,
        };
    }

    fn genDereference(self: *CodeGenerator, d: *const sem.Dereference) !TypedValue {
        const tv = (try self.visitNode(d.pointer)) orelse return CodegenError.ValueNotFound;

        // El tipo LLVM lo sacamos del result_ty semántico
        const pointee_ty = try self.toLLVMType(d.ty);

        const deref_val = c.LLVMBuildLoad2(self.builder, pointee_ty, tv.value_ref, "deref");
        return .{ .value_ref = deref_val, .type_ref = pointee_ty, .sem_type = d.ty };
    }

    fn genExplicitCast(self: *CodeGenerator, ec: sem.ExplicitCast) !TypedValue {
        const value_tv = (try self.visitNode(ec.value)) orelse return CodegenError.ValueNotFound;
        const target_ty = try self.toLLVMType(ec.target_type);

        const source_sem_ty = value_tv.sem_type orelse return CodegenError.InvalidType;
        const source_is_ptr = source_sem_ty == .pointer_type;
        const source_is_int = switch (source_sem_ty) {
            .builtin => |bt| switch (bt) {
                .UIntNative => true,
                else => false,
            },
            else => false,
        };
        const target_is_ptr = ec.target_type == .pointer_type;
        const target_is_int = switch (ec.target_type) {
            .builtin => |bt| switch (bt) {
                .UIntNative => true,
                else => false,
            },
            else => false,
        };

        if (source_is_ptr and target_is_int) {
            const casted = c.LLVMBuildPtrToInt(self.builder, value_tv.value_ref, target_ty, "ptr.to.int");
            return .{ .value_ref = casted, .type_ref = target_ty, .sem_type = ec.target_type };
        }
        if (source_is_int and target_is_ptr) {
            const casted = c.LLVMBuildIntToPtr(self.builder, value_tv.value_ref, target_ty, "int.to.ptr");
            return .{ .value_ref = casted, .type_ref = target_ty, .sem_type = ec.target_type };
        }

        return CodegenError.InvalidType;
    }

    //──────────────────────────────────────── pointer store ──
    fn genPointerAssignment(self: *CodeGenerator, pa: sem.PointerAssignment) !void {
        const ptr_tv = switch (pa.pointer.content) {
            .dereference => |d| (try self.visitNode(d.pointer)) orelse return CodegenError.ValueNotFound,
            else => (try self.visitNode(pa.pointer)) orelse return CodegenError.ValueNotFound,
        };
        const rhs_tv = (try self.visitNode(pa.value)) orelse return CodegenError.ValueNotFound;

        if (c.LLVMGetTypeKind(ptr_tv.type_ref) != c.LLVMPointerTypeKind)
            return CodegenError.InvalidType;

        _ = c.LLVMBuildStore(self.builder, rhs_tv.value_ref, ptr_tv.value_ref);
    }
    // ────────────────────────────────────────── misc helpers ──
    fn genCodeBlock(self: *CodeGenerator, cb: *const sem.CodeBlock) !?TypedValue {
        try self.pushScope();
        defer self.popScope();
        for (cb.nodes) |n| _ = try self.visitNode(n);
        if (cb.ret_val) |ret_val| {
            return try self.visitNode(ret_val);
        }
        return null;
    }

    fn dupZ(self: *CodeGenerator, s: []const u8) ![]u8 {
        const buf = try self.allocator.alloc(u8, s.len + 1);
        std.mem.copyForwards(u8, buf, s);
        buf[s.len] = 0;
        return buf;
    }

    fn genAutoMaterializedValue(self: *CodeGenerator, ty: sem.Type) !TypedValue {
        const llvm_ty = try self.toLLVMType(ty);
        return switch (ty) {
            .builtin => |bt| switch (bt) {
                .Float16, .Float32, .Float64 => .{
                    .value_ref = c.LLVMConstReal(llvm_ty, 0.0),
                    .type_ref = llvm_ty,
                    .sem_type = ty,
                },
                else => .{
                    .value_ref = c.LLVMConstNull(llvm_ty),
                    .type_ref = llvm_ty,
                    .sem_type = ty,
                },
            },
            .array_type => .{
                .value_ref = c.LLVMConstNull(llvm_ty),
                .type_ref = llvm_ty,
                .sem_type = ty,
            },
            .struct_type => |st| blk: {
                var agg = c.LLVMGetUndef(llvm_ty);
                for (st.fields, 0..) |field, idx| {
                    const field_tv = if (field.default_value) |default_node|
                        (try self.visitNode(default_node)) orelse return CodegenError.ValueNotFound
                    else
                        try self.genAutoMaterializedValue(field.ty);
                    agg = c.LLVMBuildInsertValue(self.builder, agg, field_tv.value_ref, @intCast(idx), "main.auto.field");
                }
                break :blk .{
                    .value_ref = agg,
                    .type_ref = llvm_ty,
                    .sem_type = ty,
                };
            },
            .pointer_type => |ptr_info| blk: {
                const child_tv = try self.genAutoMaterializedValue(ptr_info.child.*);
                const storage = c.LLVMBuildAlloca(self.builder, child_tv.type_ref, "main.auto.ptr");
                _ = c.LLVMBuildStore(self.builder, child_tv.value_ref, storage);
                break :blk .{
                    .value_ref = storage,
                    .type_ref = llvm_ty,
                    .sem_type = ty,
                };
            },
            .choice_type, .abstract_type => CodegenError.InvalidType,
        };
    }

    fn ensureRuntimeArgGlobals(self: *CodeGenerator) !void {
        if (self.runtime_argc_global != null and self.runtime_argv_global != null) return;

        const native_uint_ty = try self.toLLVMType(.{ .builtin = .UIntNative });
        const argc_name = try self.dupZ("__argi_runtime_argc_global");
        const argv_name = try self.dupZ("__argi_runtime_argv_global");

        const argc_global = c.LLVMAddGlobal(self.module, native_uint_ty, argc_name.ptr);
        c.LLVMSetInitializer(argc_global, c.LLVMConstNull(native_uint_ty));

        const argv_global = c.LLVMAddGlobal(self.module, native_uint_ty, argv_name.ptr);
        c.LLVMSetInitializer(argv_global, c.LLVMConstNull(native_uint_ty));

        self.runtime_argc_global = argc_global;
        self.runtime_argv_global = argv_global;
    }

    fn ensureRuntimeArgFunctions(self: *CodeGenerator) !void {
        try self.ensureRuntimeArgGlobals();

        const native_uint_ty = try self.toLLVMType(.{ .builtin = .UIntNative });
        const fn_ty = c.LLVMFunctionType(native_uint_ty, null, 0, 0);

        const argc_name = try self.dupZ("__argi_runtime_argc");
        const argc_fn = c.LLVMAddFunction(self.module, argc_name.ptr, fn_ty);
        if (c.LLVMGetFirstBasicBlock(argc_fn) == null) {
            const entry = c.LLVMAppendBasicBlock(argc_fn, "entry");
            c.LLVMPositionBuilderAtEnd(self.builder, entry);
            const value = c.LLVMBuildLoad2(self.builder, native_uint_ty, self.runtime_argc_global.?, "runtime.argc");
            _ = c.LLVMBuildRet(self.builder, value);
        }

        const argv_name = try self.dupZ("__argi_runtime_argv");
        const argv_fn = c.LLVMAddFunction(self.module, argv_name.ptr, fn_ty);
        if (c.LLVMGetFirstBasicBlock(argv_fn) == null) {
            const entry = c.LLVMAppendBasicBlock(argv_fn, "entry");
            c.LLVMPositionBuilderAtEnd(self.builder, entry);
            const value = c.LLVMBuildLoad2(self.builder, native_uint_ty, self.runtime_argv_global.?, "runtime.argv");
            _ = c.LLVMBuildRet(self.builder, value);
        }
    }

    fn findZeroArgInitForType(self: *CodeGenerator, ty: sem.Type) ?*const sem.FunctionDeclaration {
        for (self.ast) |node| {
            if (node.content != .function_declaration) continue;
            const f = node.content.function_declaration;
            if (!std.mem.eql(u8, f.name, "init")) continue;
            if (f.input.fields.len != 1) continue;
            const first = f.input.fields[0];
            if (!std.mem.eql(u8, first.name, "p")) continue;
            if (first.ty != .pointer_type) continue;
            if (!sem_types.typesExactlyEqual(first.ty.pointer_type.child.*, ty)) continue;
            return f;
        }
        return null;
    }

    fn genConstructedTypeValue(self: *CodeGenerator, ty: sem.Type) !TypedValue {
        const init_fn = self.findZeroArgInitForType(ty) orelse return CodegenError.ValueNotFound;
        const result_ty_ref = try self.toLLVMType(ty);
        const storage = c.LLVMBuildAlloca(self.builder, result_ty_ref, "main.ctor.tmp");
        const init_input_ty_ref = try self.toLLVMType(.{ .struct_type = &init_fn.input });
        var agg = c.LLVMGetUndef(init_input_ty_ref);
        agg = c.LLVMBuildInsertValue(self.builder, agg, storage, 0, "main.ctor.arg.p");

        const key_name = try self.functionSymbolKey(init_fn);
        const fn_sym = self.current_scope.lookup(key_name) orelse return CodegenError.SymbolNotFound;

        var argv = try self.allocator.alloc(llvm.c.LLVMValueRef, 1);
        defer self.allocator.free(argv);
        argv[0] = agg;
        _ = c.LLVMBuildCall2(self.builder, fn_sym.type_ref, fn_sym.ref, argv.ptr, 1, "");

        const value = c.LLVMBuildLoad2(self.builder, result_ty_ref, storage, "main.ctor.load");
        return .{ .value_ref = value, .type_ref = result_ty_ref, .sem_type = ty };
    }

    fn genMainInputFieldValue(self: *CodeGenerator, field: sem.StructTypeField) !TypedValue {
        if (field.default_value) |default_node| {
            const field_tv_opt = try self.visitNode(default_node);
            return field_tv_opt orelse return CodegenError.ValueNotFound;
        }

        if (std.mem.eql(u8, field.name, "system")) {
            return try self.genConstructedTypeValue(field.ty);
        }

        return CodegenError.ValueNotFound;
    }

    fn genCMainWrapper(self: *CodeGenerator, user_main: *const sem.FunctionDeclaration) !void {
        try self.ensureRuntimeArgGlobals();
        try self.ensureRuntimeArgFunctions();

        const user_key = try self.functionSymbolKey(user_main);
        const user_sym = self.global_scope.lookup(user_key) orelse return CodegenError.SymbolNotFound;

        const int32_ty = c.LLVMInt32Type();
        const i8_ptr_ty = c.LLVMPointerType(c.LLVMInt8Type(), 0);
        const argv_ptr_ty = c.LLVMPointerType(i8_ptr_ty, 0);
        var param_tys = [_]llvm.c.LLVMTypeRef{ int32_ty, argv_ptr_ty };
        const wrapper_fn_ty = c.LLVMFunctionType(int32_ty, &param_tys, 2, 0);

        const cname = try self.dupZ("main");
        const fn_ref = c.LLVMAddFunction(self.module, cname.ptr, wrapper_fn_ty);
        const entry = c.LLVMAppendBasicBlock(fn_ref, "entry");
        c.LLVMPositionBuilderAtEnd(self.builder, entry);

        const argc_param = c.LLVMGetParam(fn_ref, 0);
        const argv_param = c.LLVMGetParam(fn_ref, 1);
        const native_uint_ty = try self.toLLVMType(.{ .builtin = .UIntNative });

        const argc_native = c.LLVMBuildZExt(self.builder, argc_param, native_uint_ty, "argc.native");
        _ = c.LLVMBuildStore(self.builder, argc_native, self.runtime_argc_global.?);

        const argv_native = c.LLVMBuildPtrToInt(self.builder, argv_param, native_uint_ty, "argv.native");
        _ = c.LLVMBuildStore(self.builder, argv_native, self.runtime_argv_global.?);

        var input_agg = c.LLVMGetUndef(try self.toLLVMType(.{ .struct_type = &user_main.input }));
        for (user_main.input.fields, 0..) |field, idx| {
            const field_tv = try self.genMainInputFieldValue(field);
            input_agg = c.LLVMBuildInsertValue(
                self.builder,
                input_agg,
                field_tv.value_ref,
                @intCast(idx),
                "main.default",
            );
        }

        var argv = try self.allocator.alloc(llvm.c.LLVMValueRef, 1);
        defer self.allocator.free(argv);
        argv[0] = input_agg;

        const result = c.LLVMBuildCall2(self.builder, user_sym.type_ref, user_sym.ref, argv.ptr, 1, "main.call");
        const status = if (c.LLVMGetTypeKind(c.LLVMTypeOf(result)) == c.LLVMStructTypeKind)
            c.LLVMBuildExtractValue(self.builder, result, 0, "main.status")
        else
            result;
        _ = c.LLVMBuildRet(self.builder, status);
    }
};
