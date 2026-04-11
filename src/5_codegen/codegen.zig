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
    Reported,
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

const BindingStorage = struct {
    ref: llvm.c.LLVMValueRef,
    type_ref: llvm.c.LLVMTypeRef,
    sem_type: ?sem.Type = null,
};

const GlobalInitState = enum {
    uninitialized,
    in_progress,
    done,
};

const LoopContext = struct {
    break_block: llvm.c.LLVMBasicBlockRef,
    continue_block: llvm.c.LLVMBasicBlockRef,
};

const DeinitLookup = struct {
    function: *const sem.FunctionDeclaration,
    self_field_index: u32,
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

    fn lookupLocal(self: *Scope, name: []const u8) ?*Symbol {
        return self.symbols.getPtr(name);
    }
};

// ────────────────────────────────────────────── CodeGenerator ──
pub const CodeGenerator = struct {
    pub const Options = struct {
        selected_test_name: ?[]const u8 = null,
    };

    allocator: *const std.mem.Allocator,
    ast: []const *sem.SGNode,
    diags: *diagnostic.Diagnostics,
    options: Options,

    module: llvm.c.LLVMModuleRef,
    builder: llvm.c.LLVMBuilderRef,
    current_return_type: ?llvm.c.LLVMTypeRef = null,
    current_fn_decl: ?*sem.FunctionDeclaration = null,
    main_candidate: ?*sem.FunctionDeclaration = null,
    selected_test_candidate: ?*sem.FunctionDeclaration = null,
    runtime_argc_global: ?llvm.c.LLVMValueRef = null,
    runtime_argv_global: ?llvm.c.LLVMValueRef = null,
    string_literal_counter: u32 = 0,

    loop_stack: std.array_list.Managed(LoopContext),
    binding_storage: std.AutoHashMap(*const sem.BindingDeclaration, BindingStorage),
    binding_storage_by_name: std.StringHashMap(BindingStorage),
    global_init_state: std.AutoHashMap(*const sem.BindingDeclaration, GlobalInitState),

    global_scope: *Scope, // nunca se destruye hasta el final
    current_scope: *Scope, // apunta al scope donde estamos ahora

    pub fn init(a: *const std.mem.Allocator, ast: []const *sem.SGNode, diags: *diagnostic.Diagnostics, options: Options) !CodeGenerator {
        const m = c.LLVMModuleCreateWithName("argi_module");
        if (m == null) return CodegenError.ModuleCreationFailed;

        const b = c.LLVMCreateBuilder();
        const gscope = try Scope.init(a, null);

        return .{
            .allocator = a,
            .ast = ast,
            .diags = diags,
            .options = options,
            .module = m,
            .builder = b,
            .global_scope = gscope,
            .current_scope = gscope,
            .loop_stack = std.array_list.Managed(LoopContext).init(a.*),
            .binding_storage = std.AutoHashMap(*const sem.BindingDeclaration, BindingStorage).init(a.*),
            .binding_storage_by_name = std.StringHashMap(BindingStorage).init(a.*),
            .global_init_state = std.AutoHashMap(*const sem.BindingDeclaration, GlobalInitState).init(a.*),
        };
    }

    pub fn deinit(self: *CodeGenerator) void {
        if (self.builder) |b| c.LLVMDisposeBuilder(b);

        self.loop_stack.deinit();
        self.binding_storage.deinit();
        self.binding_storage_by_name.deinit();
        self.global_init_state.deinit();

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
        try self.predeclareGlobalBindings();

        for (self.ast) |n| {
            _ = self.visitNode(n) catch |err| {
                if (err == CodegenError.Reported) return CodegenError.CompilationFailed;
                try self.diags.add(n.location, .codegen, "code generation error: {s}", .{@errorName(err)});
                return CodegenError.CompilationFailed;
            };
        }

        if (self.options.selected_test_name) |_| {
            if (self.selected_test_candidate) |f| {
                try self.genCTestWrapper(f);
            }
        } else if (self.main_candidate) |f| {
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

    fn predeclareGlobalBindings(self: *CodeGenerator) !void {
        for (self.ast) |n| {
            switch (n.content) {
                .binding_declaration => |b| try self.predeclareGlobalBindingStorage(b),
                else => {},
            }
        }
    }

    fn predeclareGlobalBindingStorage(self: *CodeGenerator, b: *const sem.BindingDeclaration) !void {
        if (self.global_scope.lookupLocal(b.name) != null) return;

        const llvm_decl_ty = try self.toLLVMType(b.ty);
        const cname = try self.dupZ(b.name);
        const storage = c.LLVMAddGlobal(self.module, llvm_decl_ty, cname.ptr);
        c.LLVMSetInitializer(storage, c.LLVMConstNull(llvm_decl_ty));

        try self.global_scope.symbols.put(b.name, .{
            .cname = cname,
            .mutability = b.mutability,
            .type_ref = llvm_decl_ty,
            .ref = storage,
            .sem_type = b.ty,
            .initialized = false,
        });
        try self.binding_storage.put(b, .{
            .ref = storage,
            .type_ref = llvm_decl_ty,
            .sem_type = b.ty,
        });
        try self.binding_storage_by_name.put(b.name, .{
            .ref = storage,
            .type_ref = llvm_decl_ty,
            .sem_type = b.ty,
        });
        try self.global_init_state.put(b, .uninitialized);
    }

    // ────────────────────────────────────────── visitor dispatch ──
    fn visitNode(self: *CodeGenerator, n: *const sem.SGNode) CodegenError!?TypedValue {
        return switch (n.content) {
            .choice_option_declaration => |_| {
                return null;
            },
            .function_declaration => |f| {
                self.genFunction(f) catch |e| {
                    try self.diags.add(n.location, .codegen, "error generating function {s}: {s}", .{ f.name, @errorName(e) });
                    return e;
                };
                return null;
            },
            .test_declaration => |t| {
                self.genFunction(@constCast(t.function)) catch |e| {
                    try self.diags.add(n.location, .codegen, "error generating test {s}: {s}", .{ t.name, @errorName(e) });
                    return e;
                };
                return null;
            },
            .type_declaration => |_| {
                return null;
            },
            .binding_declaration => |b| {
                if (self.current_scope.parent != null and self.current_scope.lookupLocal(b.name) != null)
                    return self.genBindingUse(b) catch |e| {
                        if (e == CodegenError.Reported) return e;
                        try self.diags.add(n.location, .codegen, "error generating binding {s}: {s}", .{ b.name, @errorName(e) });
                        return e;
                    };
                self.genBindingDecl(b) catch |e| {
                    if (e == CodegenError.Reported) return e;
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
            .reach_directive => |reach| self.genReachDirective(reach) catch |e| {
                try self.diags.add(n.location, .codegen, "error generating #reach directive: {s}", .{@errorName(e)});
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
            .logical_operation => |lo| self.genLogicalOperation(&lo) catch |e| {
                try self.diags.add(n.location, .codegen, "error generating logical operation: {s}", .{@errorName(e)});
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
            .nullable_unwrap_or => |unwrap| self.genNullableUnwrapOr(unwrap) catch |e| {
                try self.diags.add(n.location, .codegen, "error generating nullable unwrap_or: {s}", .{@errorName(e)});
                return e;
            },
            .testing_expect_error => |expect_err| self.genTestingExpectError(expect_err) catch |e| {
                try self.diags.add(n.location, .codegen, "error generating testing.expect_error: {s}", .{@errorName(e)});
                return e;
            },
            .error_propagation => |prop| self.genErrorPropagation(prop) catch |e| {
                try self.diags.add(n.location, .codegen, "error generating error propagation: {s}", .{@errorName(e)});
                return e;
            },
            .error_context => |ctx| self.genErrorContext(ctx) catch |e| {
                try self.diags.add(n.location, .codegen, "error generating contextual error propagation: {s}", .{@errorName(e)});
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
                .Void => c.LLVMStructType(null, 0, 0),
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
                    .Void => "void",
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
        // Include the semantic declaration identity before the structural
        // signature. Input/output types are still useful in the symbol for
        // readability, but generic specializations are not always recoverable
        // from the lowered callable shape alone.
        try buf.writer().print("__f{d}", .{f.id});
        try buf.appendSlice("__in_");
        try self.encodeType(&buf, .{ .struct_type = &f.input });
        try buf.appendSlice("__out_");
        try self.encodeType(&buf, .{ .struct_type = &f.output });
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

        if (self.options.selected_test_name) |test_name| {
            if (f.is_test and std.mem.eql(u8, f.name, test_name)) {
                self.selected_test_candidate = f;
            }
        } else if (isWrappableMainCandidate(f)) {
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
        const fn_ref = blk: {
            if (self.global_scope.lookup(key_name)) |existing| {
                break :blk existing.ref;
            }

            const cname = try self.dupZ(key_name);
            const created = c.LLVMAddFunction(self.module, cname.ptr, fn_ty);

            if (is_extern and uses_sret) {
                const kind = c.LLVMGetEnumAttributeKindForName("sret", 4);
                const attr = c.LLVMCreateEnumAttribute(c.LLVMGetGlobalContext(), kind, 0);
                c.LLVMAddAttributeAtIndex(created, 1, attr); // 1-based
            }

            try self.global_scope.symbols.put(
                key_name,
                .{ .cname = cname, .mutability = .constant, .type_ref = fn_ty, .ref = created, .sem_type = null },
            );
            break :blk created;
        };

        if (is_extern and std.mem.eql(u8, f.name, "argi_runtime_argc")) {
            try self.ensureRuntimeArgGlobals();
            const entry = c.LLVMAppendBasicBlock(fn_ref, "entry");
            c.LLVMPositionBuilderAtEnd(self.builder, entry);
            const argc_ptr = self.runtime_argc_global orelse return CodegenError.InvalidType;
            const native_uint_ty = try self.toLLVMType(.{ .builtin = .UIntNative });
            const value = c.LLVMBuildLoad2(self.builder, native_uint_ty, argc_ptr, "runtime.argc");
            _ = c.LLVMBuildRet(self.builder, value);
            return;
        }

        if (is_extern and std.mem.eql(u8, f.name, "argi_runtime_argv")) {
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
        self.binding_storage_by_name.clearRetainingCapacity();

        const prev_rt = self.current_return_type;
        self.current_return_type = return_ty;
        defer self.current_return_type = prev_rt;

        // registrar parámetros de entrada
        for (f.input.fields) |fld| {
            const bd = sem.BindingDeclaration{
                .name = fld.name,
                .location = f.location,
                .origin_file = f.location.file,
                .mutability = syn.Mutability.constant,
                .ty = fld.ty,
                .initialization = null,
            };
            self.genBindingDecl(&bd) catch |err| {
                try self.diags.add(f.location, .codegen, "error generating input binding '{s}' in function {s}: {s}", .{ fld.name, f.name, @errorName(err) });
                return err;
            };
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
                .location = f.location,
                .origin_file = f.location.file,
                .mutability = syn.Mutability.variable,
                .ty = fld.ty,
                .initialization = fld.default_value,
            };
            self.genBindingDecl(&bd) catch |err| {
                try self.diags.add(f.location, .codegen, "error generating output binding '{s}' in function {s}: {s}", .{ fld.name, f.name, @errorName(err) });
                return err;
            };
        }

        // cuerpo del usuario
        _ = self.genCodeBlock(f.body.?) catch |err| {
            try self.diags.add(f.location, .codegen, "error generating body of function {s}: {s}", .{ f.name, @errorName(err) });
            return err;
        };

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
        const is_global = self.current_scope.parent == null;
        if (!is_global and self.current_scope.lookupLocal(b.name) != null)
            return CodegenError.SymbolAlreadyDefined;

        const llvm_decl_ty = try self.toLLVMType(b.ty);
        var storage: llvm.c.LLVMValueRef = null;
        var init_tv: ?TypedValue = null;

        if (is_global) {
            const existing = self.binding_storage.get(b) orelse return CodegenError.SymbolNotFound;
            storage = existing.ref;
            try self.ensureGlobalBindingInitialized(b);
            return;
        } else {
            if (b.initialization) |n|
                init_tv = try self.visitNode(n);

            const cname = try self.dupZ(b.name);
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
            try self.current_scope.symbols.put(b.name, .{
                .cname = cname,
                .mutability = b.mutability,
                .type_ref = llvm_decl_ty,
                .ref = storage,
                .sem_type = b.ty,
                .initialized = init_tv != null,
            });
            try self.binding_storage.put(b, .{
                .ref = storage,
                .type_ref = llvm_decl_ty,
                .sem_type = b.ty,
            });
            try self.binding_storage_by_name.put(b.name, .{
                .ref = storage,
                .type_ref = llvm_decl_ty,
                .sem_type = b.ty,
            });

            if (init_tv) |tv_raw| {
                var tv = tv_raw;
                if (tv.type_ref != llvm_decl_ty) {
                    tv = try self.coerceValueForStorage(tv, b.ty, llvm_decl_ty);
                }

                if (tv.type_ref == llvm_decl_ty) {
                    _ = c.LLVMBuildStore(self.builder, tv.value_ref, storage);
                } else {
                    return CodegenError.InvalidType;
                }
            }
        }
    }

    // Top-level bindings are emitted as LLVM globals. Their initializers must be
    // constants, and global storage is predeclared before codegen starts so
    // references between module files do not depend on AST order.
    fn ensureGlobalBindingInitialized(self: *CodeGenerator, b: *const sem.BindingDeclaration) CodegenError!void {
        const state = self.global_init_state.get(b) orelse .done;
        switch (state) {
            .done => return,
            .in_progress => {
                try self.diags.add(
                    b.location,
                    .codegen,
                    "module-level binding '{s}' participates in a cyclic initializer dependency",
                    .{b.name},
                );
                return CodegenError.Reported;
            },
            .uninitialized => {},
        }

        try self.global_init_state.put(b, .in_progress);
        errdefer _ = self.global_init_state.put(b, .uninitialized) catch {};

        const storage = self.binding_storage.get(b) orelse return CodegenError.SymbolNotFound;
        if (b.initialization) |init_node| {
            var init_tv = self.genGlobalConstant(init_node) catch |err| switch (err) {
                CodegenError.InvalidType,
                CodegenError.ValueNotFound,
                CodegenError.ExpressionNotFound,
                CodegenError.SymbolNotFound,
                => {
                    try self.diags.add(
                        b.location,
                        .codegen,
                        "module-level binding '{s}' must use a constant initializer for now",
                        .{b.name},
                    );
                    return CodegenError.Reported;
                },
                else => return err,
            };
            if (init_tv.type_ref != storage.type_ref) {
                init_tv = self.coerceGlobalConstant(init_tv, storage.type_ref) catch |err| switch (err) {
                    CodegenError.InvalidType => {
                        try self.diags.add(
                            b.location,
                            .codegen,
                            "module-level binding '{s}' must use a constant initializer for now",
                            .{b.name},
                        );
                        return CodegenError.Reported;
                    },
                    else => return err,
                };
            }
            c.LLVMSetInitializer(storage.ref, init_tv.value_ref);
            if (self.global_scope.lookupLocal(b.name)) |sym| sym.initialized = true;
        }

        try self.global_init_state.put(b, .done);
    }

    fn genGlobalConstant(self: *CodeGenerator, n: *const sem.SGNode) CodegenError!TypedValue {
        return switch (n.content) {
            .value_literal => self.genGlobalValueLiteral(n),
            .binding_use => |binding| blk: {
                if (self.global_init_state.get(binding)) |state| {
                    if (state == .in_progress) {
                        try self.diags.add(
                            binding.location,
                            .codegen,
                            "module-level binding '{s}' participates in a cyclic initializer dependency",
                            .{binding.name},
                        );
                        return CodegenError.Reported;
                    }
                }
                try self.ensureGlobalBindingInitialized(binding);
                const storage = self.binding_storage.get(binding) orelse return CodegenError.SymbolNotFound;
                const init_val = c.LLVMGetInitializer(storage.ref) orelse return CodegenError.InvalidType;
                break :blk .{
                    .value_ref = init_val,
                    .type_ref = storage.type_ref,
                    .sem_type = storage.sem_type,
                };
            },
            .address_of => |target| try self.genGlobalAddressOf(target),
            .binary_operation => |bo| try self.genGlobalBinaryOperation(&bo),
            .comparison => |co| try self.genGlobalComparison(&co),
            .logical_operation => |lo| try self.genGlobalLogicalOperation(&lo),
            else => CodegenError.InvalidType,
        };
    }

    fn genGlobalAddressOf(self: *CodeGenerator, target: *const sem.SGNode) CodegenError!TypedValue {
        return switch (target.content) {
            .binding_use => |binding| blk: {
                if (self.global_init_state.get(binding)) |state| {
                    if (state == .in_progress) {
                        try self.diags.add(
                            binding.location,
                            .codegen,
                            "module-level binding '{s}' participates in a cyclic initializer dependency",
                            .{binding.name},
                        );
                        return CodegenError.Reported;
                    }
                }
                try self.ensureGlobalBindingInitialized(binding);
                const storage = self.binding_storage.get(binding) orelse return CodegenError.SymbolNotFound;
                break :blk .{
                    .value_ref = storage.ref,
                    .type_ref = c.LLVMTypeOf(storage.ref),
                    .sem_type = target.sem_type,
                };
            },
            else => CodegenError.InvalidType,
        };
    }

    fn genGlobalValueLiteral(self: *CodeGenerator, n: *const sem.SGNode) CodegenError!TypedValue {
        return try self.genValueLiteral(n);
    }

    fn isStringViewType(ty: sem.Type) bool {
        if (ty != .struct_type) return false;
        const st = ty.struct_type;
        if (st.fields.len != 2) return false;
        if (!std.mem.eql(u8, st.fields[0].name, "data")) return false;
        if (!std.mem.eql(u8, st.fields[1].name, "length")) return false;
        return st.fields[0].ty == .builtin and st.fields[0].ty.builtin == .UIntNative and
            st.fields[1].ty == .builtin and st.fields[1].ty.builtin == .UIntNative;
    }

    fn emitStringLiteralPointer(self: *CodeGenerator, str: []const u8) !llvm.c.LLVMValueRef {
        const name = try std.fmt.allocPrint(self.allocator.*, "argi.strlit.{d}", .{self.string_literal_counter});
        self.string_literal_counter += 1;

        const ctx = c.LLVMGetModuleContext(self.module);
        const array_ty = c.LLVMArrayType(c.LLVMInt8Type(), @intCast(str.len + 1));
        const initializer = c.LLVMConstStringInContext(ctx, str.ptr, @intCast(str.len), 0);
        const global = c.LLVMAddGlobal(self.module, array_ty, name.ptr);
        c.LLVMSetInitializer(global, initializer);
        c.LLVMSetGlobalConstant(global, 1);
        c.LLVMSetLinkage(global, c.LLVMPrivateLinkage);

        const zero = c.LLVMConstInt(c.LLVMInt32Type(), 0, 0);
        var indices = [_]llvm.c.LLVMValueRef{ zero, zero };
        return c.LLVMConstGEP2(array_ty, global, &indices, 2);
    }

    fn genGlobalBinaryOperation(self: *CodeGenerator, bo: *const sem.BinaryOperation) CodegenError!TypedValue {
        const lhs = try self.genGlobalConstant(bo.left);
        const rhs = try self.genGlobalConstant(bo.right);
        if (lhs.type_ref != rhs.type_ref) return CodegenError.InvalidType;

        const value_ref = switch (bo.operator) {
            .addition => c.LLVMConstAdd(lhs.value_ref, rhs.value_ref),
            .subtraction => c.LLVMConstSub(lhs.value_ref, rhs.value_ref),
            .multiplication => c.LLVMConstMul(lhs.value_ref, rhs.value_ref),
            else => return CodegenError.InvalidType,
        };
        return .{ .value_ref = value_ref, .type_ref = lhs.type_ref, .sem_type = lhs.sem_type };
    }

    fn genGlobalComparison(self: *CodeGenerator, co: *const sem.Comparison) CodegenError!TypedValue {
        const lhs = try self.genGlobalConstant(co.left);
        const rhs = try self.genGlobalConstant(co.right);
        if (lhs.type_ref != rhs.type_ref) return CodegenError.InvalidType;

        const is_float = lhs.type_ref == c.LLVMFloatType();
        const use_unsigned = isUnsignedBuiltin(lhs.sem_type);
        const value_ref = switch (co.operator) {
            .equal => if (is_float) c.LLVMConstFCmp(c.LLVMRealOEQ, lhs.value_ref, rhs.value_ref) else c.LLVMConstICmp(c.LLVMIntEQ, lhs.value_ref, rhs.value_ref),
            .not_equal => if (is_float) c.LLVMConstFCmp(c.LLVMRealONE, lhs.value_ref, rhs.value_ref) else c.LLVMConstICmp(c.LLVMIntNE, lhs.value_ref, rhs.value_ref),
            .less_than => if (is_float) c.LLVMConstFCmp(c.LLVMRealOLT, lhs.value_ref, rhs.value_ref) else if (use_unsigned) c.LLVMConstICmp(c.LLVMIntULT, lhs.value_ref, rhs.value_ref) else c.LLVMConstICmp(c.LLVMIntSLT, lhs.value_ref, rhs.value_ref),
            .greater_than => if (is_float) c.LLVMConstFCmp(c.LLVMRealOGT, lhs.value_ref, rhs.value_ref) else if (use_unsigned) c.LLVMConstICmp(c.LLVMIntUGT, lhs.value_ref, rhs.value_ref) else c.LLVMConstICmp(c.LLVMIntSGT, lhs.value_ref, rhs.value_ref),
            .less_than_or_equal => if (is_float) c.LLVMConstFCmp(c.LLVMRealOLE, lhs.value_ref, rhs.value_ref) else if (use_unsigned) c.LLVMConstICmp(c.LLVMIntULE, lhs.value_ref, rhs.value_ref) else c.LLVMConstICmp(c.LLVMIntSLE, lhs.value_ref, rhs.value_ref),
            .greater_than_or_equal => if (is_float) c.LLVMConstFCmp(c.LLVMRealOGE, lhs.value_ref, rhs.value_ref) else if (use_unsigned) c.LLVMConstICmp(c.LLVMIntUGE, lhs.value_ref, rhs.value_ref) else c.LLVMConstICmp(c.LLVMIntSGE, lhs.value_ref, rhs.value_ref),
        };
        return .{ .value_ref = value_ref, .type_ref = c.LLVMInt1Type(), .sem_type = .{ .builtin = .Bool } };
    }

    fn genGlobalLogicalOperation(self: *CodeGenerator, lo: *const sem.LogicalOperation) CodegenError!TypedValue {
        const lhs = try self.genGlobalConstant(lo.left);
        const rhs = try self.genGlobalConstant(lo.right);
        if (lhs.type_ref != c.LLVMInt1Type() or rhs.type_ref != c.LLVMInt1Type()) return CodegenError.InvalidType;

        const value_ref = switch (lo.operator) {
            .and_ => c.LLVMConstAnd(lhs.value_ref, rhs.value_ref),
            .or_ => c.LLVMConstOr(lhs.value_ref, rhs.value_ref),
        };
        return .{ .value_ref = value_ref, .type_ref = c.LLVMInt1Type(), .sem_type = .{ .builtin = .Bool } };
    }

    fn coerceGlobalConstant(self: *CodeGenerator, tv: TypedValue, target_ty_ref: llvm.c.LLVMTypeRef) CodegenError!TypedValue {
        _ = self;
        if (tv.type_ref == target_ty_ref) return tv;

        if (c.LLVMGetTypeKind(tv.type_ref) == c.LLVMIntegerTypeKind and c.LLVMGetTypeKind(target_ty_ref) == c.LLVMIntegerTypeKind) {
            return .{
                .value_ref = c.LLVMConstIntCast(tv.value_ref, target_ty_ref, if (isUnsignedBuiltin(tv.sem_type)) 0 else 1),
                .type_ref = target_ty_ref,
                .sem_type = tv.sem_type,
            };
        }

        if (c.LLVMGetTypeKind(tv.type_ref) == c.LLVMFloatTypeKind and c.LLVMGetTypeKind(target_ty_ref) == c.LLVMFloatTypeKind) {
            return .{
                .value_ref = c.LLVMConstFPCast(tv.value_ref, target_ty_ref),
                .type_ref = target_ty_ref,
                .sem_type = tv.sem_type,
            };
        }

        return CodegenError.InvalidType;
    }

    fn coerceValueForStorage(
        self: *CodeGenerator,
        tv: TypedValue,
        dest_sem_ty: sem.Type,
        dest_ty_ref: llvm.c.LLVMTypeRef,
    ) !TypedValue {
        const src_sem_ty = tv.sem_type orelse return tv;
        if (!sem_types.typesStructurallyEqual(src_sem_ty, dest_sem_ty)) return tv;

        if (src_sem_ty == .struct_type and dest_sem_ty == .struct_type) {
            const src_fields = src_sem_ty.struct_type.fields;
            const dest_fields = dest_sem_ty.struct_type.fields;
            if (src_fields.len != dest_fields.len) return tv;

            // Semantizing already decided these types are structurally equal.
            // Rebuild the aggregate under the destination LLVM type so stores
            // and struct literals do not depend on nominally identical layouts
            // sharing the exact same LLVM struct handle.
            var agg = c.LLVMGetUndef(dest_ty_ref);
            for (src_fields, 0..) |_, idx| {
                const extracted = c.LLVMBuildExtractValue(self.builder, tv.value_ref, @intCast(idx), "coerce.struct.extract");
                agg = c.LLVMBuildInsertValue(self.builder, agg, extracted, @intCast(idx), "coerce.struct.insert");
            }

            return .{
                .value_ref = agg,
                .type_ref = dest_ty_ref,
                .sem_type = dest_sem_ty,
            };
        }

        return tv;
    }

    fn genBindingUse(self: *CodeGenerator, b: *sem.BindingDeclaration) !TypedValue {
        const insert_block = c.LLVMGetInsertBlock(self.builder);
        if (self.current_scope.lookup(b.name)) |sym| {
            if (insert_block == null) {
                const init_val = c.LLVMGetInitializer(sym.ref) orelse return CodegenError.InvalidType;
                return .{ .value_ref = init_val, .type_ref = sym.type_ref, .sem_type = sym.sem_type };
            }
            const val = c.LLVMBuildLoad2(self.builder, sym.type_ref, sym.ref, sym.cname.ptr);
            return .{ .value_ref = val, .type_ref = sym.type_ref, .sem_type = sym.sem_type };
        }

        const storage = self.binding_storage.get(b) orelse self.binding_storage_by_name.get(b.name) orelse return CodegenError.SymbolNotFound;
        if (insert_block == null) {
            const init_val = c.LLVMGetInitializer(storage.ref) orelse return CodegenError.InvalidType;
            return .{ .value_ref = init_val, .type_ref = storage.type_ref, .sem_type = storage.sem_type };
        }
        const val = c.LLVMBuildLoad2(self.builder, storage.type_ref, storage.ref, "binding.load");
        return .{ .value_ref = val, .type_ref = storage.type_ref, .sem_type = storage.sem_type };
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

    fn genReachDirective(self: *CodeGenerator, reach: *const sem.ReachDirective) !TypedValue {
        for (reach.alternatives) |alt| {
            if (self.genReachAlternative(alt)) |tv| {
                return tv;
            } else |err| switch (err) {
                CodegenError.SymbolNotFound, CodegenError.InvalidType => continue,
                else => return err,
            }
        }
        return CodegenError.SymbolNotFound;
    }

    fn genReachAlternative(self: *CodeGenerator, alt: sem.ReachAlternative) !TypedValue {
        if (alt.segments.len == 0) return CodegenError.InvalidType;

        const base_name = alt.segments[0];
        const sym = self.current_scope.lookup(base_name) orelse return CodegenError.SymbolNotFound;
        var current = TypedValue{
            .value_ref = c.LLVMBuildLoad2(self.builder, sym.type_ref, sym.ref, "reach.base"),
            .type_ref = sym.type_ref,
            .sem_type = sym.sem_type,
        };

        for (alt.segments[1..]) |segment| {
            const current_sem_ty = current.sem_type orelse return CodegenError.InvalidType;
            if (current_sem_ty != .struct_type) return CodegenError.InvalidType;

            const st = current_sem_ty.struct_type;
            const field_index = for (st.fields, 0..) |field, idx| {
                if (std.mem.eql(u8, field.name, segment)) break idx;
            } else return CodegenError.SymbolNotFound;

            const field_ty_ref = c.LLVMStructGetTypeAtIndex(current.type_ref, @intCast(field_index));
            current = .{
                .value_ref = c.LLVMBuildExtractValue(self.builder, current.value_ref, @intCast(field_index), "reach.field"),
                .type_ref = field_ty_ref,
                .sem_type = st.fields[field_index].ty,
            };
        }

        return current;
    }

    fn genAutoDeinitBinding(self: *CodeGenerator, adb: *const sem.AutoDeinitBinding) !void {
        if (self.current_scope.lookup(adb.binding.name)) |sym| {
            if (!sym.initialized) return;

            if (adb.deinit_fn) |deinit_fn| {
                const input_node = adb.input orelse return CodegenError.InvalidType;
                const call = try self.allocator.create(sem.FunctionCall);
                call.* = .{ .callee = deinit_fn, .input = @constCast(input_node) };
                const call_node = try sem.makeSGNode(.{ .function_call = call }, deinit_fn.location, self.allocator);
                _ = try self.visitNode(call_node);
            } else {
                try self.genAutoDeinitPointer(sym.ref, adb.binding.ty, null, null, 0, adb.fields);
            }
            return;
        }

        return;
    }

    fn genAutoDeinitPointer(
        self: *CodeGenerator,
        ptr: llvm.c.LLVMValueRef,
        sem_ty: sem.Type,
        deinit_fn_override: ?*const sem.FunctionDeclaration,
        input_override: ?*const sem.SGNode,
        self_field_index: u32,
        fields: []const sem.AutoDeinitField,
    ) !void {
        if (deinit_fn_override) |deinit_fn| {
            return self.genAutoDeinitCall(ptr, deinit_fn, input_override, self_field_index);
        }

        if (fields.len == 0) {
            if (self.findDeinitInAst(sem_ty)) |deinit_info| {
                return self.genAutoDeinitCall(ptr, deinit_info.function, null, deinit_info.self_field_index);
            }
            return;
        }

        switch (sem_ty) {
            .struct_type => |st| {
                if (fields.len == 0) return;

                const struct_ty_ref = try self.toLLVMType(.{ .struct_type = st });
                for (fields) |field| {
                    const field_ty = st.fields[field.field_index].ty;
                    const field_ptr = c.LLVMBuildStructGEP2(
                        self.builder,
                        struct_ty_ref,
                        ptr,
                        field.field_index,
                        "autodeinit.field",
                    );
                    try self.genAutoDeinitPointer(field_ptr, field_ty, field.deinit_fn, field.input, field.self_field_index, field.fields);
                }
            },
            else => return CodegenError.InvalidType,
        }
    }

    fn genAutoDeinitCall(
        self: *CodeGenerator,
        ptr: llvm.c.LLVMValueRef,
        deinit_fn: *const sem.FunctionDeclaration,
        input_override: ?*const sem.SGNode,
        self_field_index: u32,
    ) !void {
        const key_name = try self.functionSymbolKey(deinit_fn);
        var fn_sym_opt = self.global_scope.lookup(key_name);
        if (fn_sym_opt == null) {
            const in_ty = try self.toLLVMType(.{ .struct_type = &deinit_fn.input });
            const out_ty = try self.toLLVMType(.{ .struct_type = &deinit_fn.output });
            var params = try self.allocator.alloc(llvm.c.LLVMTypeRef, 1);
            defer self.allocator.free(params);
            params[0] = in_ty;
            const fn_ty = c.LLVMFunctionType(out_ty, params.ptr, 1, 0);
            const cname = try self.dupZ(key_name);
            const fn_ref = c.LLVMAddFunction(self.module, cname.ptr, fn_ty);
            try self.global_scope.symbols.put(key_name, .{
                .cname = cname,
                .mutability = .constant,
                .type_ref = fn_ty,
                .ref = fn_ref,
                .sem_type = null,
            });
            fn_sym_opt = self.global_scope.lookup(key_name);
        }
        const fn_sym = fn_sym_opt.?;

        const arg_sem_ty = deinit_fn.input.fields[self_field_index].ty;
        if (arg_sem_ty != .pointer_type) return CodegenError.InvalidType;
        const target_sem_ty = arg_sem_ty.pointer_type.child.*;

        const llvm_arg_ty = try self.toLLVMType(arg_sem_ty);
        if (c.LLVMTypeOf(ptr) != llvm_arg_ty) return CodegenError.InvalidType;

        const input_ty = try self.toLLVMType(.{ .struct_type = &deinit_fn.input });
        var arg_struct = c.LLVMGetUndef(input_ty);
        const input_fields = if (input_override) |input_node|
            switch (input_node.content) {
                .struct_value_literal => |lit| lit.fields,
                else => return CodegenError.InvalidType,
            }
        else
            &.{};
        for (deinit_fn.input.fields, 0..) |field, idx| {
            const field_value = if (idx == self_field_index)
                ptr
            else blk: {
                if (input_override != null) {
                    const input_field = for (input_fields) |*input_field| {
                        if (std.mem.eql(u8, input_field.name, field.name)) break input_field;
                    } else null orelse return CodegenError.InvalidType;
                    const tv = self.genAutoDeinitOverrideValue(input_field.value, ptr, target_sem_ty) catch |err| switch (err) {
                        CodegenError.SymbolNotFound, CodegenError.ValueNotFound, CodegenError.InvalidType => blk_default: {
                            const default_node = field.default_value orelse return;
                            const default_tv = (self.visitNode(default_node) catch return) orelse return;
                            break :blk_default default_tv;
                        },
                        else => return,
                    };
                    break :blk tv.value_ref;
                }
                const default_node = field.default_value orelse return;
                const tv = (self.visitNode(default_node) catch return) orelse return;
                break :blk tv.value_ref;
            };
            arg_struct = c.LLVMBuildInsertValue(self.builder, arg_struct, field_value, @intCast(idx), "autodeinit.arg");
        }

        var argv = try self.allocator.alloc(llvm.c.LLVMValueRef, 1);
        defer self.allocator.free(argv);
        argv[0] = arg_struct;

        _ = c.LLVMBuildCall2(self.builder, fn_sym.type_ref, fn_sym.ref, argv.ptr, 1, "");
    }

    fn isAutoDeinitPlaceholder(node: *const sem.SGNode) bool {
        return node.content == .binding_use and std.mem.eql(u8, node.content.binding_use.name, "__auto_deinit_target");
    }

    fn genAutoDeinitOverrideValue(
        self: *CodeGenerator,
        node: *const sem.SGNode,
        ptr: llvm.c.LLVMValueRef,
        target_sem_ty: sem.Type,
    ) !TypedValue {
        if (isAutoDeinitPlaceholder(node)) {
            const llvm_ty = try self.toLLVMType(target_sem_ty);
            const loaded = c.LLVMBuildLoad2(self.builder, llvm_ty, ptr, "autodeinit.target");
            return .{ .value_ref = loaded, .type_ref = llvm_ty, .sem_type = target_sem_ty };
        }

        return switch (node.content) {
            .struct_field_access => blk: {
                const field_ptr = try self.genAutoDeinitOverridePointer(node, ptr, target_sem_ty);
                const field_ty = try self.addressableValueType(node);
                const llvm_ty = try self.toLLVMType(field_ty);
                const loaded = c.LLVMBuildLoad2(self.builder, llvm_ty, field_ptr.value_ref, "autodeinit.field");
                break :blk .{ .value_ref = loaded, .type_ref = llvm_ty, .sem_type = field_ty };
            },
            .address_of => |addr| try self.genAutoDeinitOverridePointer(addr, ptr, target_sem_ty),
            else => (try self.visitNode(node)) orelse return CodegenError.ValueNotFound,
        };
    }

    fn genAutoDeinitOverridePointer(
        self: *CodeGenerator,
        node: *const sem.SGNode,
        ptr: llvm.c.LLVMValueRef,
        target_sem_ty: sem.Type,
    ) !TypedValue {
        if (isAutoDeinitPlaceholder(node)) {
            return .{
                .value_ref = ptr,
                .type_ref = c.LLVMPointerType(try self.toLLVMType(target_sem_ty), 0),
                .sem_type = null,
            };
        }

        return switch (node.content) {
            .struct_field_access => |sfa| blk: {
                const base_ptr = try self.genAutoDeinitOverridePointer(sfa.struct_value, ptr, target_sem_ty);
                const base_ty = try self.addressableValueType(sfa.struct_value);
                if (base_ty != .struct_type) return CodegenError.InvalidType;
                const struct_ty_ref = try self.toLLVMType(base_ty);
                const field_ptr = c.LLVMBuildStructGEP2(
                    self.builder,
                    struct_ty_ref,
                    base_ptr.value_ref,
                    sfa.field_index,
                    "autodeinit.override.field",
                );
                const field_ty_ref = c.LLVMStructGetTypeAtIndex(struct_ty_ref, sfa.field_index);
                break :blk .{ .value_ref = field_ptr, .type_ref = c.LLVMPointerType(field_ty_ref, 0), .sem_type = null };
            },
            else => try self.genAddressablePointer(node),
        };
    }

    fn findDeinitInAst(self: *CodeGenerator, ty: sem.Type) ?DeinitLookup {
        for (self.ast) |node| {
            if (node.content != .function_declaration) continue;
            const cand = node.content.function_declaration;
            if (!std.mem.eql(u8, cand.name, "deinit")) continue;

            for (cand.input.fields, 0..) |field, idx| {
                if (field.ty != .pointer_type) continue;
                const ptr_info = field.ty.pointer_type.*;
                if (ptr_info.mutability != .read_write) continue;
                if (!sem_types.typesStructurallyEqual(ptr_info.child.*, ty)) continue;

                var other_fields_have_defaults = true;
                for (cand.input.fields, 0..) |other_field, other_idx| {
                    if (other_idx == idx) continue;
                    if (other_field.default_value == null) {
                        other_fields_have_defaults = false;
                        break;
                    }
                }
                if (!other_fields_have_defaults) continue;

                return .{
                    .function = cand,
                    .self_field_index = @intCast(idx),
                };
            }
        }
        return null;
    }

    // ────────────────────────────────────────── assignment ──
    fn genAssignment(self: *CodeGenerator, a: *sem.Assignment) !TypedValue {
        const sym_ptr = self.current_scope.lookup(a.sym_id.name) orelse
            return CodegenError.SymbolNotFound;

        // Const sólo falla si *ya* estaba inicializado
        if (sym_ptr.*.mutability == .constant and sym_ptr.*.initialized)
            return CodegenError.ConstantReassignment;

        if (a.value.content == .type_initializer) {
            const ti = a.value.content.type_initializer;
            const field_ty_ref = try self.toLLVMType(ti.type_decl.ty);
            if (sym_ptr.*.type_ref != field_ty_ref)
                return CodegenError.InvalidType;

            try self.genTypeInitializerInto(&ti, sym_ptr.*.ref);
            sym_ptr.*.initialized = true;
            const loaded = c.LLVMBuildLoad2(self.builder, sym_ptr.*.type_ref, sym_ptr.*.ref, "assign.init.result");
            return .{ .value_ref = loaded, .type_ref = sym_ptr.*.type_ref, .sem_type = sym_ptr.*.sem_type };
        }

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
            .bool_literal => |b| .{
                .type_ref = c.LLVMInt1Type(),
                .value_ref = c.LLVMConstInt(c.LLVMInt1Type(), if (b) 1 else 0, 0),
                .sem_type = sem_ty,
            },
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
                if (sem_ty) |ty| {
                    if (isStringViewType(ty)) {
                        // String literals lower to a static NUL-terminated byte
                        // buffer plus a `StringView { data, length }` descriptor.
                        // The terminator stays available for explicit `&Char`
                        // interop, but it is not the literal's semantic type.
                        const type_ref = try self.toLLVMType(ty);
                        const data_ptr = try self.emitStringLiteralPointer(str);
                        const native_uint_ty = try self.toLLVMType(.{ .builtin = .UIntNative });
                        const data_addr = c.LLVMConstPtrToInt(data_ptr, native_uint_ty);
                        const length = c.LLVMConstInt(native_uint_ty, @intCast(str.len), 0);
                        var fields = [_]llvm.c.LLVMValueRef{ data_addr, length };
                        break :blk .{
                            .type_ref = type_ref,
                            .value_ref = c.LLVMConstNamedStruct(type_ref, &fields, fields.len),
                            .sem_type = sem_ty,
                        };
                    }
                }

                const gptr = try self.emitStringLiteralPointer(str);
                break :blk .{
                    .type_ref = c.LLVMPointerType(c.LLVMInt8Type(), 0),
                    .value_ref = gptr,
                    .sem_type = sem_ty,
                };
            },
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

    fn genLogicalOperation(self: *CodeGenerator, lo: *const sem.LogicalOperation) !TypedValue {
        const lhs_tv = (try self.visitNode(lo.left)) orelse return CodegenError.ValueNotFound;
        if (lhs_tv.type_ref != c.LLVMInt1Type())
            return CodegenError.InvalidType;

        const current_bb = c.LLVMGetInsertBlock(self.builder);
        const current_fn = c.LLVMGetBasicBlockParent(current_bb);
        const rhs_bb = c.LLVMAppendBasicBlock(current_fn, switch (lo.operator) {
            .and_ => "logic.and.rhs",
            .or_ => "logic.or.rhs",
        });
        const merge_bb = c.LLVMAppendBasicBlock(current_fn, switch (lo.operator) {
            .and_ => "logic.and.merge",
            .or_ => "logic.or.merge",
        });

        const short_val = switch (lo.operator) {
            .and_ => c.LLVMConstInt(c.LLVMInt1Type(), 0, 0),
            .or_ => c.LLVMConstInt(c.LLVMInt1Type(), 1, 0),
        };

        switch (lo.operator) {
            .and_ => _ = c.LLVMBuildCondBr(self.builder, lhs_tv.value_ref, rhs_bb, merge_bb),
            .or_ => _ = c.LLVMBuildCondBr(self.builder, lhs_tv.value_ref, merge_bb, rhs_bb),
        }

        c.LLVMPositionBuilderAtEnd(self.builder, rhs_bb);
        const rhs_tv = (try self.visitNode(lo.right)) orelse return CodegenError.ValueNotFound;
        if (rhs_tv.type_ref != c.LLVMInt1Type())
            return CodegenError.InvalidType;
        _ = c.LLVMBuildBr(self.builder, merge_bb);
        const rhs_end_bb = c.LLVMGetInsertBlock(self.builder);

        c.LLVMPositionBuilderAtEnd(self.builder, merge_bb);
        const phi = c.LLVMBuildPhi(self.builder, c.LLVMInt1Type(), switch (lo.operator) {
            .and_ => "logic.and",
            .or_ => "logic.or",
        });
        var incoming_values = [_]llvm.c.LLVMValueRef{ short_val, rhs_tv.value_ref };
        var incoming_blocks = [_]llvm.c.LLVMBasicBlockRef{ current_bb, rhs_end_bb };
        c.LLVMAddIncoming(phi, &incoming_values, &incoming_blocks, 2);

        return .{ .value_ref = phi, .type_ref = c.LLVMInt1Type(), .sem_type = .{ .builtin = .Bool } };
    }

    fn genNullableUnwrapOr(self: *CodeGenerator, unwrap: *const sem.NullableUnwrapOr) !TypedValue {
        const nullable_tv = (try self.visitNode(unwrap.nullable_value)) orelse return CodegenError.ValueNotFound;
        const result_ty_ref = try self.toLLVMType(unwrap.result_type);

        const tag_val = c.LLVMBuildExtractValue(self.builder, nullable_tv.value_ref, 0, "nullable.tag");
        const cur_bb = c.LLVMGetInsertBlock(self.builder);
        const fnc = c.LLVMGetBasicBlockParent(cur_bb);
        const some_bb = c.LLVMAppendBasicBlock(fnc, "nullable.some");
        const none_bb = c.LLVMAppendBasicBlock(fnc, "nullable.none");
        const merge_bb = c.LLVMAppendBasicBlock(fnc, "nullable.merge");

        const some_tag = c.LLVMConstInt(c.LLVMInt32Type(), unwrap.some_variant_index, 0);
        const is_some = c.LLVMBuildICmp(self.builder, c.LLVMIntEQ, tag_val, some_tag, "nullable.is_some");
        _ = c.LLVMBuildCondBr(self.builder, is_some, some_bb, none_bb);

        c.LLVMPositionBuilderAtEnd(self.builder, some_bb);
        const payload_val = c.LLVMBuildExtractValue(
            self.builder,
            nullable_tv.value_ref,
            unwrap.some_variant_index + 1,
            "nullable.payload",
        );
        const some_val = c.LLVMBuildExtractValue(
            self.builder,
            payload_val,
            unwrap.some_value_field_index,
            "nullable.value",
        );
        _ = c.LLVMBuildBr(self.builder, merge_bb);
        const some_end_bb = c.LLVMGetInsertBlock(self.builder);

        c.LLVMPositionBuilderAtEnd(self.builder, none_bb);
        const fallback_tv = (try self.visitNode(unwrap.fallback_value)) orelse return CodegenError.ValueNotFound;
        _ = c.LLVMBuildBr(self.builder, merge_bb);
        const none_end_bb = c.LLVMGetInsertBlock(self.builder);

        c.LLVMPositionBuilderAtEnd(self.builder, merge_bb);
        const phi = c.LLVMBuildPhi(self.builder, result_ty_ref, "nullable.unwrap_or");
        var incoming_values = [_]llvm.c.LLVMValueRef{ some_val, fallback_tv.value_ref };
        var incoming_blocks = [_]llvm.c.LLVMBasicBlockRef{ some_end_bb, none_end_bb };
        c.LLVMAddIncoming(phi, &incoming_values, &incoming_blocks, 2);

        return .{
            .value_ref = phi,
            .type_ref = result_ty_ref,
            .sem_type = unwrap.result_type,
        };
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
        const then_end = c.LLVMGetInsertBlock(self.builder);
        if (c.LLVMGetBasicBlockTerminator(then_end) == null)
            _ = c.LLVMBuildBr(self.builder, endB);

        if (i.else_block) |eb| {
            c.LLVMPositionBuilderAtEnd(self.builder, elseB.?);
            _ = try self.genCodeBlock(eb);
            const else_end = c.LLVMGetInsertBlock(self.builder);
            if (c.LLVMGetBasicBlockTerminator(else_end) == null)
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
        const body_end = c.LLVMGetInsertBlock(self.builder);
        if (c.LLVMGetBasicBlockTerminator(body_end) == null)
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
        const cur_bb = c.LLVMGetInsertBlock(self.builder);
        const fnc = c.LLVMGetBasicBlockParent(cur_bb);
        const after_break = c.LLVMAppendBasicBlock(fnc, "after.break");
        c.LLVMPositionBuilderAtEnd(self.builder, after_break);
    }

    fn genContinue(self: *CodeGenerator, loc: tok.Location) !void {
        if (self.loop_stack.items.len == 0) {
            try self.diags.add(loc, .codegen, "continue used outside of a loop", .{});
            return CodegenError.CompilationFailed;
        }
        const loop_ctx = self.loop_stack.items[self.loop_stack.items.len - 1];
        _ = c.LLVMBuildBr(self.builder, loop_ctx.continue_block);
        const cur_bb = c.LLVMGetInsertBlock(self.builder);
        const fnc = c.LLVMGetBasicBlockParent(cur_bb);
        const after_continue = c.LLVMAppendBasicBlock(fnc, "after.continue");
        c.LLVMPositionBuilderAtEnd(self.builder, after_continue);
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
            const case_end = c.LLVMGetInsertBlock(self.builder);
            if (c.LLVMGetBasicBlockTerminator(case_end) == null)
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

            try self.genCleanupNodes(r.cleanup_nodes);

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
            try self.genCleanupNodes(r.cleanup_nodes);
            _ = c.LLVMBuildRetVoid(self.builder);
            return;
        }

        // necesitamos saber los campos de salida declarados
        const fdecl = self.current_fn_decl orelse return CodegenError.InvalidType;

        try self.genCleanupNodes(r.cleanup_nodes);

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
        const callee_decl = fc.callee;
        const is_extern = (callee_decl.body == null);
        var sym_opt = self.global_scope.lookup(key_name);

        // ─────── llamadas INTERNAS (idénticas a antes) ───────────────────
        if (!is_extern) {
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
                try self.global_scope.symbols.put(key_name, .{ .cname = cname, .mutability = .constant, .type_ref = fnty, .ref = fn_ref, .sem_type = null });
                sym_opt = self.global_scope.lookup(key_name);
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
        const sym = sym_opt orelse return CodegenError.SymbolNotFound;
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

            if (c.LLVMTypeOf(raw) != pty) return CodegenError.InvalidType;
            argv[idx] = raw;
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

    fn genTypeInitializerInto(self: *CodeGenerator, ti: *const sem.TypeInitializer, storage: llvm.c.LLVMValueRef) CodegenError!void {
        // Type initializers conceptually construct the value at its final
        // destination. Lowering through a temporary and then copying breaks
        // types that keep references into their own backing storage.
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
        var sym_opt = self.global_scope.lookup(key_name);
        if (sym_opt == null) {
            const in_ty_ref = init_input_ty_ref;
            const out_ty_ref = try self.toLLVMType(.{ .struct_type = &ti.init_fn.output });
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
            try self.global_scope.symbols.put(key_name, .{ .cname = cname, .mutability = .constant, .type_ref = fnty, .ref = fn_ref, .sem_type = null });
            sym_opt = self.global_scope.lookup(key_name);
        }

        const fn_sym = sym_opt.?;
        var argv = try self.allocator.alloc(llvm.c.LLVMValueRef, 1);
        defer self.allocator.free(argv);
        argv[0] = agg;

        const call_name = if (c.LLVMGetReturnType(fn_sym.type_ref) == c.LLVMVoidType()) "" else "call";
        _ = c.LLVMBuildCall2(self.builder, fn_sym.type_ref, fn_sym.ref, argv.ptr, 1, call_name);
    }

    fn genTypeInitializer(self: *CodeGenerator, ti: *const sem.TypeInitializer) CodegenError!TypedValue {
        const result_ty_ref = try self.toLLVMType(ti.type_decl.ty);
        const storage = c.LLVMBuildAlloca(self.builder, result_ty_ref, "type.init.tmp");

        try self.genTypeInitializerInto(ti, storage);

        const result_val = c.LLVMBuildLoad2(self.builder, result_ty_ref, storage, "type.init.result");
        return .{ .value_ref = result_val, .type_ref = result_ty_ref, .sem_type = ti.type_decl.ty };
    }

    // ────────────────────────────────────────── struct literal ──
    fn genStructValueLiteral(self: *CodeGenerator, sl: *const sem.StructValueLiteral) !?TypedValue {
        const cnt = sl.fields.len;
        const ty = try self.toLLVMType(sl.ty);

        const sem_fields = switch (sl.ty) {
            .struct_type => |st| st.fields,
            .builtin => |builtin| switch (builtin) {
                .Void => &.{},
                else => return CodegenError.InvalidType,
            },
            else => return CodegenError.InvalidType,
        };

        var needs_in_place = false;
        for (sl.fields) |f| {
            if (f.value.content == .type_initializer) {
                needs_in_place = true;
                break;
            }
        }

        if (needs_in_place) {
            const storage = c.LLVMBuildAlloca(self.builder, ty, "lit.tmp");
            for (sl.fields, 0..) |f, i| {
                const field_ptr = c.LLVMBuildStructGEP2(
                    self.builder,
                    ty,
                    storage,
                    @intCast(i),
                    "lit.field.ptr",
                );
                const field_ll_ty = c.LLVMStructGetTypeAtIndex(ty, @intCast(i));

                if (f.value.content == .type_initializer) {
                    const ti = f.value.content.type_initializer;
                    const init_ty_ref = try self.toLLVMType(ti.type_decl.ty);
                    if (init_ty_ref != field_ll_ty)
                        return CodegenError.InvalidType;
                    try self.genTypeInitializerInto(&ti, field_ptr);
                    continue;
                }

                var field_tv = (try self.visitNode(f.value)) orelse return CodegenError.ValueNotFound;
                if (field_tv.type_ref != field_ll_ty) {
                    field_tv = try self.coerceValueForStorage(field_tv, sem_fields[i].ty, field_ll_ty);
                }
                if (field_tv.type_ref != field_ll_ty) return CodegenError.InvalidType;
                _ = c.LLVMBuildStore(self.builder, field_tv.value_ref, field_ptr);
            }

            const agg = c.LLVMBuildLoad2(self.builder, ty, storage, "lit.load");
            return .{ .value_ref = agg, .type_ref = ty, .sem_type = sl.ty };
        }

        var vals = try self.allocator.alloc(TypedValue, cnt);
        defer self.allocator.free(vals);

        for (sl.fields, 0..) |f, i| {
            const field_tv_opt = try self.visitNode(f.value);
            var field_tv = field_tv_opt orelse return CodegenError.ValueNotFound;
            const field_ll_ty = c.LLVMStructGetTypeAtIndex(ty, @intCast(i));
            if (field_tv.type_ref != field_ll_ty) {
                field_tv = try self.coerceValueForStorage(field_tv, sem_fields[i].ty, field_ll_ty);
            }
            if (field_tv.type_ref != field_ll_ty) return CodegenError.InvalidType;
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

    fn genErrorPropagation(self: *CodeGenerator, prop: *const sem.ErrorPropagation) !TypedValue {
        return self.genErrorPropagationImpl(
            prop.errable_value,
            null,
            prop.cleanup_nodes,
            prop.ok_variant_index,
            prop.ok_value_field_index,
            prop.error_variant_index,
            prop.propagated_errable_type,
            prop.propagated_error_variant_index,
            prop.ok_payload_type,
            prop.error_payload_type,
            prop.propagated_error_payload_type,
            prop.line,
            prop.column,
            prop.source_file,
            prop.source_line,
        );
    }

    fn genErrorContext(self: *CodeGenerator, ctx: *const sem.ErrorContext) !TypedValue {
        return self.genErrorPropagationImpl(
            ctx.errable_value,
            ctx.context,
            ctx.cleanup_nodes,
            ctx.ok_variant_index,
            ctx.ok_value_field_index,
            ctx.error_variant_index,
            ctx.propagated_errable_type,
            ctx.propagated_error_variant_index,
            ctx.ok_payload_type,
            ctx.error_payload_type,
            ctx.propagated_error_payload_type,
            ctx.line,
            ctx.column,
            ctx.source_file,
            ctx.source_line,
        );
    }

    fn genErrorPropagationImpl(
        self: *CodeGenerator,
        errable_node: *const sem.SGNode,
        context_node: ?*const sem.SGNode,
        cleanup_nodes: []const *sem.SGNode,
        ok_variant_index: u32,
        ok_value_field_index: ?u32,
        error_variant_index: u32,
        propagated_errable_type: sem.Type,
        propagated_error_variant_index: u32,
        ok_payload_type: sem.Type,
        error_payload_type: sem.Type,
        propagated_error_payload_type: sem.Type,
        line: u32,
        column: u32,
        source_file: []const u8,
        source_line: []const u8,
    ) !TypedValue {
        const errable_tv = (try self.visitNode(errable_node)) orelse return CodegenError.ValueNotFound;
        const tag_val = c.LLVMBuildExtractValue(self.builder, errable_tv.value_ref, 0, "errable.tag");
        const error_tag = c.LLVMConstInt(c.LLVMInt32Type(), error_variant_index, 0);
        const is_error = c.LLVMBuildICmp(self.builder, c.LLVMIntEQ, tag_val, error_tag, "errable.is_error");

        const current_bb = c.LLVMGetInsertBlock(self.builder);
        const current_fn = c.LLVMGetBasicBlockParent(current_bb);
        const error_bb = c.LLVMAppendBasicBlock(current_fn, "errable.error");
        const ok_bb = c.LLVMAppendBasicBlock(current_fn, "errable.ok");
        _ = c.LLVMBuildCondBr(self.builder, is_error, error_bb, ok_bb);

        c.LLVMPositionBuilderAtEnd(self.builder, error_bb);
        const error_payload = c.LLVMBuildExtractValue(self.builder, errable_tv.value_ref, error_variant_index + 1, "errable.error.payload");
        const source_file_z = try self.dupZ(source_file);
        const source_file_ptr = c.LLVMBuildGlobalStringPtr(self.builder, source_file_z.ptr, "trace_source_file");
        const resolved_source_line = if (source_line.len == 0) try self.readSourceLine(source_file, line) else source_line;
        const source_line_z = try self.dupZ(resolved_source_line);
        const source_line_ptr = c.LLVMBuildGlobalStringPtr(self.builder, source_line_z.ptr, "trace_source_line");
        const context_ptr = if (context_node) |ctx_node|
            try self.genErrorContextPointer(ctx_node)
        else
            c.LLVMConstNull(c.LLVMPointerType(c.LLVMInt8Type(), 0));
        const traced_error_payload = try self.appendTraceEntry(error_payload, error_payload_type, source_file_ptr, line, column, context_ptr, source_line_ptr);
        const updated_error_payload = try self.coerceErrorPayload(traced_error_payload, error_payload_type, propagated_error_payload_type);
        var updated_errable = c.LLVMGetUndef(try self.toLLVMType(propagated_errable_type));
        updated_errable = c.LLVMBuildInsertValue(
            self.builder,
            updated_errable,
            c.LLVMConstInt(c.LLVMInt32Type(), propagated_error_variant_index, 0),
            0,
            "errable.error.tag",
        );
        updated_errable = c.LLVMBuildInsertValue(
            self.builder,
            updated_errable,
            updated_error_payload,
            propagated_error_variant_index + 1,
            "errable.error.updated",
        );
        try self.buildCurrentFunctionErrableReturn(updated_errable, cleanup_nodes);

        c.LLVMPositionBuilderAtEnd(self.builder, ok_bb);
        const ok_payload = c.LLVMBuildExtractValue(self.builder, errable_tv.value_ref, ok_variant_index + 1, "errable.ok.payload");
        const ok_value = if (ok_value_field_index) |field_index| c.LLVMBuildExtractValue(self.builder, ok_payload, field_index, "errable.ok.value") else ok_payload;
        const ok_ty = try self.toLLVMType(ok_payload_type);
        return .{ .value_ref = ok_value, .type_ref = ok_ty, .sem_type = ok_payload_type };
    }

    fn genErrorContextPointer(self: *CodeGenerator, ctx_node: *const sem.SGNode) !llvm.c.LLVMValueRef {
        const ctx_tv = (try self.visitNode(ctx_node)) orelse return CodegenError.ValueNotFound;
        if (ctx_tv.sem_type) |sem_ty| {
            if (isStringViewType(sem_ty)) {
                const native_uint_ty = try self.toLLVMType(.{ .builtin = .UIntNative });
                const data_index = fieldIndexByName(sem_ty.struct_type, "data") orelse return CodegenError.InvalidType;
                const data_addr = c.LLVMBuildExtractValue(self.builder, ctx_tv.value_ref, @intCast(data_index), "ctx.data");
                if (c.LLVMTypeOf(data_addr) != native_uint_ty)
                    return CodegenError.InvalidType;
                return c.LLVMBuildIntToPtr(self.builder, data_addr, c.LLVMPointerType(c.LLVMInt8Type(), 0), "ctx.ptr");
            }
        }
        return ctx_tv.value_ref;
    }

    fn buildCurrentFunctionErrableReturn(self: *CodeGenerator, errable_value: llvm.c.LLVMValueRef, cleanup_nodes: []const *sem.SGNode) !void {
        const ret_ty = self.current_return_type orelse return CodegenError.InvalidType;
        const fn_decl = self.current_fn_decl orelse return CodegenError.InvalidType;
        if (fn_decl.output.fields.len != 1) return CodegenError.InvalidType;

        try self.genCleanupNodes(cleanup_nodes);

        var agg = c.LLVMGetUndef(ret_ty);
        agg = c.LLVMBuildInsertValue(self.builder, agg, errable_value, 0, "errable.return");
        _ = c.LLVMBuildRet(self.builder, agg);
    }

    fn coerceErrorPayload(
        self: *CodeGenerator,
        value: llvm.c.LLVMValueRef,
        source_ty: sem.Type,
        target_ty: sem.Type,
    ) !llvm.c.LLVMValueRef {
        if (sem_types.typesExactlyEqual(source_ty, target_ty)) return value;

        const source_struct = switch (source_ty) {
            .struct_type => |st| st,
            else => return CodegenError.InvalidType,
        };
        const target_struct = switch (target_ty) {
            .struct_type => |st| st,
            else => return CodegenError.InvalidType,
        };

        const source_reason_index = fieldIndexByName(source_struct, "reason") orelse return CodegenError.InvalidType;
        const source_trace_index = fieldIndexByName(source_struct, "trace") orelse return CodegenError.InvalidType;
        const target_reason_index = fieldIndexByName(target_struct, "reason") orelse return CodegenError.InvalidType;
        const target_trace_index = fieldIndexByName(target_struct, "trace") orelse return CodegenError.InvalidType;
        const source_reason_ty = source_struct.fields[source_reason_index].ty;
        const target_reason_ty = target_struct.fields[target_reason_index].ty;
        if (source_reason_ty != .choice_type or target_reason_ty != .choice_type) return CodegenError.InvalidType;

        const source_reason = c.LLVMBuildExtractValue(self.builder, value, source_reason_index, "error.reason");
        const coerced_reason = try self.coerceChoiceValue(source_reason, source_reason_ty.choice_type, target_reason_ty.choice_type);
        const trace_value = c.LLVMBuildExtractValue(self.builder, value, source_trace_index, "error.trace");

        var result = c.LLVMGetUndef(try self.toLLVMType(target_ty));
        result = c.LLVMBuildInsertValue(self.builder, result, coerced_reason, target_reason_index, "error.reason.coerced");
        result = c.LLVMBuildInsertValue(self.builder, result, trace_value, target_trace_index, "error.trace.coerced");
        return result;
    }

    fn coerceChoiceValue(
        self: *CodeGenerator,
        value: llvm.c.LLVMValueRef,
        source_ty: *const sem.ChoiceType,
        target_ty: *const sem.ChoiceType,
    ) !llvm.c.LLVMValueRef {
        if (source_ty == target_ty or sem_types.typesExactlyEqual(.{ .choice_type = source_ty }, .{ .choice_type = target_ty })) {
            return value;
        }

        const target_llvm_ty = try self.toLLVMType(.{ .choice_type = target_ty });
        const tag_val = c.LLVMBuildExtractValue(self.builder, value, 0, "choice.coerce.tag");
        var remapped_tag = c.LLVMConstInt(c.LLVMInt32Type(), 0, 0);
        var first = true;
        for (source_ty.variants, 0..) |variant, idx| {
            if (variant.payload_type != null) return CodegenError.InvalidType;
            const target_idx = sem_types.choiceTypeContainsVariant(target_ty, variant) orelse return CodegenError.InvalidType;
            const is_match = c.LLVMBuildICmp(
                self.builder,
                c.LLVMIntEQ,
                tag_val,
                c.LLVMConstInt(c.LLVMInt32Type(), @intCast(idx), 0),
                "choice.coerce.is_match",
            );
            const mapped = c.LLVMConstInt(c.LLVMInt32Type(), target_idx, 0);
            remapped_tag = if (first)
                c.LLVMBuildSelect(self.builder, is_match, mapped, remapped_tag, "choice.coerce.select")
            else
                c.LLVMBuildSelect(self.builder, is_match, mapped, remapped_tag, "choice.coerce.select");
            first = false;
        }

        var result = c.LLVMGetUndef(target_llvm_ty);
        result = c.LLVMBuildInsertValue(self.builder, result, remapped_tag, 0, "choice.coerce.tag");
        return result;
    }

    fn genCleanupNodes(self: *CodeGenerator, nodes: []const *sem.SGNode) !void {
        for (nodes) |node| {
            _ = try self.visitNode(node);
        }
    }

    fn appendTraceEntry(
        self: *CodeGenerator,
        error_payload_value: llvm.c.LLVMValueRef,
        error_payload_type: sem.Type,
        source_file_ptr: llvm.c.LLVMValueRef,
        line: u32,
        column: u32,
        context_ptr: llvm.c.LLVMValueRef,
        source_line_ptr: llvm.c.LLVMValueRef,
    ) !llvm.c.LLVMValueRef {
        const error_struct = switch (error_payload_type) {
            .struct_type => |st| st,
            else => return CodegenError.InvalidType,
        };

        const reason_index = fieldIndexByName(error_struct, "reason") orelse return CodegenError.InvalidType;
        const trace_index = fieldIndexByName(error_struct, "trace") orelse return CodegenError.InvalidType;

        const trace_ty = error_struct.fields[trace_index].ty;
        const trace_struct = switch (trace_ty) {
            .struct_type => |st| st,
            else => return CodegenError.InvalidType,
        };
        const entries_index = fieldIndexByName(trace_struct, "entries") orelse return CodegenError.InvalidType;
        const entries_ty = trace_struct.fields[entries_index].ty;
        const entries_struct = switch (entries_ty) {
            .struct_type => |st| st,
            else => return CodegenError.InvalidType,
        };

        const allocation_index = fieldIndexByName(entries_struct, "allocation") orelse return CodegenError.InvalidType;
        const length_index = fieldIndexByName(entries_struct, "length") orelse return CodegenError.InvalidType;
        const capacity_index = fieldIndexByName(entries_struct, "capacity") orelse return CodegenError.InvalidType;

        const allocation_ty = entries_struct.fields[allocation_index].ty;
        const allocation_struct = switch (allocation_ty) {
            .struct_type => |st| st,
            else => return CodegenError.InvalidType,
        };
        const data_index = fieldIndexByName(allocation_struct, "data") orelse return CodegenError.InvalidType;
        const size_index = fieldIndexByName(allocation_struct, "size") orelse return CodegenError.InvalidType;

        const entries_identity = sem_types.genericIdentityOf(entries_ty) orelse return CodegenError.InvalidType;
        const entry_ty = sem_types.genericIdentityArgByName(entries_identity, "t") orelse return CodegenError.InvalidType;
        const trace_entry_ty = switch (entry_ty) {
            .type => |ty| ty,
            else => return CodegenError.InvalidType,
        };
        const trace_entry_struct = switch (trace_entry_ty) {
            .struct_type => |st| st,
            else => return CodegenError.InvalidType,
        };
        const source_file_index = fieldIndexByName(trace_entry_struct, "source_file") orelse return CodegenError.InvalidType;
        const line_index = fieldIndexByName(trace_entry_struct, "line") orelse return CodegenError.InvalidType;
        const column_index = fieldIndexByName(trace_entry_struct, "column") orelse return CodegenError.InvalidType;
        const context_index = fieldIndexByName(trace_entry_struct, "context") orelse return CodegenError.InvalidType;
        const source_line_index = fieldIndexByName(trace_entry_struct, "source_line") orelse return CodegenError.InvalidType;

        const error_llvm_ty = try self.toLLVMType(error_payload_type);
        const trace_llvm_ty = try self.toLLVMType(trace_ty);
        const entries_llvm_ty = try self.toLLVMType(entries_ty);
        const allocation_llvm_ty = try self.toLLVMType(allocation_ty);
        const trace_entry_llvm_ty = try self.toLLVMType(trace_entry_ty);
        const native_uint_ty = try self.toLLVMType(.{ .builtin = .UIntNative });
        const entry_ptr_ty = c.LLVMPointerType(trace_entry_llvm_ty, 0);
        const elem_size: u64 = sem_types.computeTypeSize(trace_entry_ty);
        const elem_size_val = c.LLVMConstInt(native_uint_ty, elem_size, 0);

        const reason_value = c.LLVMBuildExtractValue(self.builder, error_payload_value, reason_index, "error.reason");
        const trace_value = c.LLVMBuildExtractValue(self.builder, error_payload_value, trace_index, "error.trace");
        const entries_value = c.LLVMBuildExtractValue(self.builder, trace_value, entries_index, "error.trace.entries");
        const allocation_value = c.LLVMBuildExtractValue(self.builder, entries_value, allocation_index, "trace.entries.allocation");
        const old_data = c.LLVMBuildExtractValue(self.builder, allocation_value, data_index, "trace.entries.data");
        const old_length = c.LLVMBuildExtractValue(self.builder, entries_value, length_index, "trace.entries.length");
        const old_capacity = c.LLVMBuildExtractValue(self.builder, entries_value, capacity_index, "trace.entries.capacity");

        const is_full = c.LLVMBuildICmp(self.builder, c.LLVMIntEQ, old_length, old_capacity, "trace.is_full");
        const error_bb = c.LLVMGetInsertBlock(self.builder);
        const parent_fn = c.LLVMGetBasicBlockParent(error_bb);
        const grow_bb = c.LLVMAppendBasicBlock(parent_fn, "trace.grow");
        const reuse_bb = c.LLVMAppendBasicBlock(parent_fn, "trace.reuse");
        const merge_bb = c.LLVMAppendBasicBlock(parent_fn, "trace.merge");
        _ = c.LLVMBuildCondBr(self.builder, is_full, grow_bb, reuse_bb);

        c.LLVMPositionBuilderAtEnd(self.builder, grow_bb);
        const zero = c.LLVMConstInt(native_uint_ty, 0, 0);
        const one = c.LLVMConstInt(native_uint_ty, 1, 0);
        const is_zero_capacity = c.LLVMBuildICmp(self.builder, c.LLVMIntEQ, old_capacity, zero, "trace.capacity.zero");
        const doubled_capacity = c.LLVMBuildMul(self.builder, old_capacity, c.LLVMConstInt(native_uint_ty, 2, 0), "trace.capacity.doubled");
        const new_capacity = c.LLVMBuildSelect(self.builder, is_zero_capacity, one, doubled_capacity, "trace.capacity");
        const new_size = c.LLVMBuildMul(self.builder, new_capacity, elem_size_val, "trace.bytes");
        const new_data = try self.buildMalloc(new_size);
        const bytes_to_copy = c.LLVMBuildMul(self.builder, old_length, elem_size_val, "trace.copy_bytes");
        try self.buildMemcpy(new_data, old_data, bytes_to_copy);
        try self.buildFree(old_data);

        var grown_allocation = c.LLVMGetUndef(allocation_llvm_ty);
        grown_allocation = c.LLVMBuildInsertValue(self.builder, grown_allocation, new_data, data_index, "trace.alloc.data");
        grown_allocation = c.LLVMBuildInsertValue(self.builder, grown_allocation, new_size, size_index, "trace.alloc.size");

        var grown_entries = c.LLVMGetUndef(entries_llvm_ty);
        grown_entries = c.LLVMBuildInsertValue(self.builder, grown_entries, grown_allocation, allocation_index, "trace.entries.alloc");
        grown_entries = c.LLVMBuildInsertValue(self.builder, grown_entries, old_length, length_index, "trace.entries.length");
        grown_entries = c.LLVMBuildInsertValue(self.builder, grown_entries, new_capacity, capacity_index, "trace.entries.capacity");
        _ = c.LLVMBuildBr(self.builder, merge_bb);
        const grow_end_bb = c.LLVMGetInsertBlock(self.builder);

        c.LLVMPositionBuilderAtEnd(self.builder, reuse_bb);
        _ = c.LLVMBuildBr(self.builder, merge_bb);
        const reuse_end_bb = c.LLVMGetInsertBlock(self.builder);

        c.LLVMPositionBuilderAtEnd(self.builder, merge_bb);
        const entries_phi = c.LLVMBuildPhi(self.builder, entries_llvm_ty, "trace.entries.current");
        var incoming_entries = [_]llvm.c.LLVMValueRef{ grown_entries, entries_value };
        var incoming_blocks = [_]llvm.c.LLVMBasicBlockRef{ grow_end_bb, reuse_end_bb };
        c.LLVMAddIncoming(entries_phi, &incoming_entries, &incoming_blocks, 2);

        const current_allocation = c.LLVMBuildExtractValue(self.builder, entries_phi, allocation_index, "trace.alloc.current");
        const current_data = c.LLVMBuildExtractValue(self.builder, current_allocation, data_index, "trace.data.current");
        const data_addr = c.LLVMBuildPtrToInt(self.builder, current_data, native_uint_ty, "trace.data.addr");
        const offset = c.LLVMBuildMul(self.builder, old_length, elem_size_val, "trace.offset");
        const entry_addr = c.LLVMBuildAdd(self.builder, data_addr, offset, "trace.entry.addr");
        const entry_ptr = c.LLVMBuildIntToPtr(self.builder, entry_addr, entry_ptr_ty, "trace.entry.ptr");

        var entry_value = c.LLVMGetUndef(trace_entry_llvm_ty);
        entry_value = c.LLVMBuildInsertValue(self.builder, entry_value, source_file_ptr, source_file_index, "trace.entry.source_file");
        entry_value = c.LLVMBuildInsertValue(self.builder, entry_value, c.LLVMConstInt(try self.toLLVMType(trace_entry_struct.fields[line_index].ty), line, 0), line_index, "trace.entry.line");
        entry_value = c.LLVMBuildInsertValue(self.builder, entry_value, c.LLVMConstInt(try self.toLLVMType(trace_entry_struct.fields[column_index].ty), column, 0), column_index, "trace.entry.column");
        entry_value = c.LLVMBuildInsertValue(self.builder, entry_value, context_ptr, context_index, "trace.entry.context");
        entry_value = c.LLVMBuildInsertValue(self.builder, entry_value, source_line_ptr, source_line_index, "trace.entry.source_line");
        _ = c.LLVMBuildStore(self.builder, entry_value, entry_ptr);

        const new_length = c.LLVMBuildAdd(self.builder, old_length, one, "trace.length.next");
        var final_entries = entries_phi;
        final_entries = c.LLVMBuildInsertValue(self.builder, final_entries, new_length, length_index, "trace.entries.final_length");

        var final_trace = c.LLVMGetUndef(trace_llvm_ty);
        final_trace = c.LLVMBuildInsertValue(self.builder, final_trace, final_entries, entries_index, "trace.final.entries");

        var final_error = c.LLVMGetUndef(error_llvm_ty);
        final_error = c.LLVMBuildInsertValue(self.builder, final_error, reason_value, reason_index, "error.final.reason");
        final_error = c.LLVMBuildInsertValue(self.builder, final_error, final_trace, trace_index, "error.final.trace");
        return final_error;
    }

    fn buildMalloc(self: *CodeGenerator, size: llvm.c.LLVMValueRef) !llvm.c.LLVMValueRef {
        const sym = self.global_scope.lookup("malloc") orelse return CodegenError.SymbolNotFound;
        var argv = [_]llvm.c.LLVMValueRef{size};
        return c.LLVMBuildCall2(self.builder, sym.type_ref, sym.ref, &argv, 1, "malloc.call");
    }

    fn buildFree(self: *CodeGenerator, ptr: llvm.c.LLVMValueRef) !void {
        const sym = self.global_scope.lookup("free") orelse return CodegenError.SymbolNotFound;
        var argv = [_]llvm.c.LLVMValueRef{ptr};
        _ = c.LLVMBuildCall2(self.builder, sym.type_ref, sym.ref, &argv, 1, "");
    }

    fn buildMemcpy(self: *CodeGenerator, dst: llvm.c.LLVMValueRef, src: llvm.c.LLVMValueRef, n: llvm.c.LLVMValueRef) !void {
        const sym = self.global_scope.lookup("memcpy") orelse return CodegenError.SymbolNotFound;
        var argv = [_]llvm.c.LLVMValueRef{ dst, src, n };
        _ = c.LLVMBuildCall2(self.builder, sym.type_ref, sym.ref, &argv, 3, "");
    }

    fn fieldIndexByName(st: *const sem.StructType, name: []const u8) ?u32 {
        for (st.fields, 0..) |field, idx| {
            if (std.mem.eql(u8, field.name, name)) return @intCast(idx);
        }
        return null;
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

        if (sf.value.content == .type_initializer) {
            const ti = sf.value.content.type_initializer;
            const field_ty_ref = try self.toLLVMType(sf.field_type);
            const init_ty_ref = try self.toLLVMType(ti.type_decl.ty);
            if (field_ty_ref != init_ty_ref)
                return CodegenError.InvalidType;
            try self.genTypeInitializerInto(&ti, field_ptr);
            return;
        }

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
                if (self.current_scope.lookup(bu.name)) |sym| {
                    break :blk sym.sem_type orelse return CodegenError.InvalidType;
                }
                const storage = self.binding_storage.get(bu) orelse self.binding_storage_by_name.get(bu.name) orelse return CodegenError.SymbolNotFound;
                break :blk storage.sem_type orelse return CodegenError.InvalidType;
            },
            .struct_field_access => |sfa| blk: {
                const base_ty = try self.addressableValueType(sfa.struct_value);
                if (base_ty != .struct_type) return CodegenError.InvalidType;
                if (sfa.field_index >= base_ty.struct_type.fields.len) return CodegenError.InvalidType;
                break :blk base_ty.struct_type.fields[sfa.field_index].ty;
            },
            .choice_payload_access => |acc| acc.payload_type,
            .dereference => |d| d.ty,
            else => CodegenError.InvalidType,
        };
    }

    fn genAddressablePointer(self: *CodeGenerator, target: *const sem.SGNode) !TypedValue {
        return switch (target.content) {
            .binding_use => |bu| blk: {
                if (self.current_scope.lookup(bu.name)) |sym| {
                    const ptr_ty = c.LLVMPointerType(sym.type_ref, 0);
                    break :blk .{ .value_ref = sym.ref, .type_ref = ptr_ty, .sem_type = null };
                }
                const storage = self.binding_storage.get(bu) orelse self.binding_storage_by_name.get(bu.name) orelse return CodegenError.SymbolNotFound;
                const ptr_ty = c.LLVMPointerType(storage.type_ref, 0);
                break :blk .{ .value_ref = storage.ref, .type_ref = ptr_ty, .sem_type = null };
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
            .choice_payload_access => |acc| blk: {
                const base_ptr = try self.genAddressablePointer(acc.choice_value);
                const base_sem_ty = try self.addressableValueType(acc.choice_value);
                if (base_sem_ty != .choice_type) return CodegenError.InvalidType;
                const choice_ty_ref = try self.toLLVMType(.{ .choice_type = base_sem_ty.choice_type });
                const payload_ptr = c.LLVMBuildStructGEP2(
                    self.builder,
                    choice_ty_ref,
                    base_ptr.value_ref,
                    acc.variant_index + 1,
                    "choice.payload.addr",
                );
                const payload_ty_ref = try self.toLLVMType(acc.payload_type);
                break :blk .{ .value_ref = payload_ptr, .type_ref = c.LLVMPointerType(payload_ty_ref, 0), .sem_type = null };
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

        if (c.LLVMGetTypeKind(ptr_tv.type_ref) != c.LLVMPointerTypeKind)
            return CodegenError.InvalidType;

        if (pa.value.content == .type_initializer) {
            const ti = pa.value.content.type_initializer;
            try self.genTypeInitializerInto(&ti, ptr_tv.value_ref);
            return;
        }

        const rhs_tv = (try self.visitNode(pa.value)) orelse return CodegenError.ValueNotFound;
        _ = c.LLVMBuildStore(self.builder, rhs_tv.value_ref, ptr_tv.value_ref);
    }
    // ────────────────────────────────────────── misc helpers ──
    fn genCodeBlock(self: *CodeGenerator, cb: *const sem.CodeBlock) !?TypedValue {
        try self.pushScope();
        defer self.popScope();
        for (cb.nodes, 0..) |n, idx| {
            const current_bb = c.LLVMGetInsertBlock(self.builder);
            if (current_bb != null and c.LLVMGetBasicBlockTerminator(current_bb) != null) break;
            _ = self.visitNode(n) catch |err| {
                try self.diags.add(n.location, .codegen, "error generating code block node {d}: {s}", .{ idx, @errorName(err) });
                return err;
            };
        }
        if (cb.ret_val) |ret_val| {
            return self.visitNode(ret_val) catch |err| {
                try self.diags.add(ret_val.location, .codegen, "error generating code block return value: {s}", .{@errorName(err)});
                return err;
            };
        }
        return null;
    }

    fn dupZ(self: *CodeGenerator, s: []const u8) ![]u8 {
        const buf = try self.allocator.alloc(u8, s.len + 1);
        std.mem.copyForwards(u8, buf, s);
        buf[s.len] = 0;
        return buf;
    }

    fn readSourceLine(self: *CodeGenerator, file_path: []const u8, line_number: u32) ![]const u8 {
        const file_text = std.fs.cwd().readFileAlloc(self.allocator.*, file_path, 1 << 24) catch return "";
        var lines = std.mem.splitScalar(u8, file_text, '\n');
        var current_line: u32 = 1;
        while (lines.next()) |line| : (current_line += 1) {
            if (current_line != line_number) continue;
            return std.mem.trimRight(u8, line, "\r");
        }
        return "";
    }

    fn genAutoMaterializedValue(self: *CodeGenerator, ty: sem.Type) !TypedValue {
        const llvm_ty = try self.toLLVMType(ty);
        return switch (ty) {
            .builtin => |bt| switch (bt) {
                .Void => .{
                    .value_ref = c.LLVMConstNull(llvm_ty),
                    .type_ref = llvm_ty,
                    .sem_type = ty,
                },
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
        const fn_sym = self.global_scope.lookup(key_name) orelse return CodegenError.SymbolNotFound;

        var argv = try self.allocator.alloc(llvm.c.LLVMValueRef, 1);
        defer self.allocator.free(argv);
        argv[0] = agg;
        _ = c.LLVMBuildCall2(self.builder, fn_sym.type_ref, fn_sym.ref, argv.ptr, 1, "");

        const value = c.LLVMBuildLoad2(self.builder, result_ty_ref, storage, "main.ctor.load");
        return .{ .value_ref = value, .type_ref = result_ty_ref, .sem_type = ty };
    }

    fn genEntryInputFieldValue(self: *CodeGenerator, field: sem.StructTypeField) !TypedValue {
        if (field.default_value) |default_node| {
            const field_tv_opt = try self.visitNode(default_node);
            return field_tv_opt orelse return CodegenError.ValueNotFound;
        }

        if (std.mem.eql(u8, field.name, "system")) {
            return try self.genConstructedTypeValue(field.ty);
        }

        return CodegenError.ValueNotFound;
    }

    fn buildTestingExpectErrorMismatchContext(
        self: *CodeGenerator,
        reason_tag: llvm.c.LLVMValueRef,
        reason_choice: *const sem.ChoiceType,
        expected_reason_name: ?[]const u8,
    ) !llvm.c.LLVMValueRef {
        if (expected_reason_name == null) {
            const msg_z = try self.dupZ("expect_error failed: error reason mismatch");
            return c.LLVMBuildGlobalStringPtr(self.builder, msg_z.ptr, "test_expect_error_mismatch");
        }

        var result_ptr: ?llvm.c.LLVMValueRef = null;
        for (reason_choice.variants, 0..) |variant, idx| {
            const msg = try std.fmt.allocPrint(self.allocator.*, "expect_error failed: expected ..{s} but got ..{s}", .{
                expected_reason_name.?,
                variant.name,
            });
            const msg_z = try self.dupZ(msg);
            const msg_ptr = c.LLVMBuildGlobalStringPtr(self.builder, msg_z.ptr, "test_expect_error_reason");
            if (result_ptr == null) {
                result_ptr = msg_ptr;
                continue;
            }

            const is_match = c.LLVMBuildICmp(
                self.builder,
                c.LLVMIntEQ,
                reason_tag,
                c.LLVMConstInt(c.LLVMInt32Type(), @intCast(idx), 0),
                "test_expect_error_reason_match",
            );
            result_ptr = c.LLVMBuildSelect(self.builder, is_match, msg_ptr, result_ptr.?, "test_expect_error_reason_select");
        }

        return result_ptr.?;
    }

    fn buildTestingFailureErrable(
        self: *CodeGenerator,
        result_type: sem.Type,
        context_ptr: llvm.c.LLVMValueRef,
        line: u32,
        column: u32,
        source_file: []const u8,
        source_line: []const u8,
    ) !llvm.c.LLVMValueRef {
        const result_choice = switch (result_type) {
            .choice_type => |choice_ty| choice_ty,
            else => return CodegenError.InvalidType,
        };
        const error_variant_index = findChoiceVariantIndexByName(result_choice, "error") orelse return CodegenError.InvalidType;
        const error_payload_type = result_choice.variants[error_variant_index].payload_type orelse return CodegenError.InvalidType;
        const error_payload_struct = switch (error_payload_type) {
            .struct_type => |st| st,
            else => return CodegenError.InvalidType,
        };
        const reason_index = fieldIndexByName(error_payload_struct, "reason") orelse return CodegenError.InvalidType;
        const reason_choice = switch (error_payload_struct.fields[reason_index].ty) {
            .choice_type => |choice_ty| choice_ty,
            else => return CodegenError.InvalidType,
        };
        const test_failed_variant_index = findChoiceVariantIndexByName(reason_choice, "test_failed") orelse return CodegenError.InvalidType;

        var reason_value = c.LLVMGetUndef(try self.toLLVMType(.{ .choice_type = reason_choice }));
        reason_value = c.LLVMBuildInsertValue(
            self.builder,
            reason_value,
            c.LLVMConstInt(c.LLVMInt32Type(), test_failed_variant_index, 0),
            0,
            "test_expect_error.fail.reason.tag",
        );

        var error_payload = c.LLVMConstNull(try self.toLLVMType(error_payload_type));
        error_payload = c.LLVMBuildInsertValue(self.builder, error_payload, reason_value, reason_index, "test_expect_error.fail.reason");

        const source_file_z = try self.dupZ(source_file);
        const source_file_ptr = c.LLVMBuildGlobalStringPtr(self.builder, source_file_z.ptr, "test_expect_error_source_file");
        const source_line_z = try self.dupZ(source_line);
        const source_line_ptr = c.LLVMBuildGlobalStringPtr(self.builder, source_line_z.ptr, "test_expect_error_source_line");
        const traced_payload = try self.appendTraceEntry(error_payload, error_payload_type, source_file_ptr, line, column, context_ptr, source_line_ptr);

        var result = c.LLVMGetUndef(try self.toLLVMType(result_type));
        result = c.LLVMBuildInsertValue(self.builder, result, c.LLVMConstInt(c.LLVMInt32Type(), error_variant_index, 0), 0, "test_expect_error.fail.tag");
        result = c.LLVMBuildInsertValue(self.builder, result, traced_payload, error_variant_index + 1, "test_expect_error.fail.errable");
        return result;
    }

    fn buildErrableOkVoid(
        self: *CodeGenerator,
        result_type: sem.Type,
        ok_variant_index: u32,
    ) !llvm.c.LLVMValueRef {
        const result_choice = switch (result_type) {
            .choice_type => |choice_ty| choice_ty,
            else => return CodegenError.InvalidType,
        };
        const ok_payload_type = result_choice.variants[ok_variant_index].payload_type orelse return CodegenError.InvalidType;
        var ok_payload = c.LLVMConstNull(try self.toLLVMType(ok_payload_type));
        if (ok_payload_type == .struct_type) {
            const ok_payload_struct = ok_payload_type.struct_type;
            if (fieldIndexByName(ok_payload_struct, "value")) |value_index| {
                if (ok_payload_struct.fields.len == 1) {
                    ok_payload = c.LLVMBuildInsertValue(
                        self.builder,
                        ok_payload,
                        c.LLVMConstNull(try self.toLLVMType(ok_payload_struct.fields[value_index].ty)),
                        value_index,
                        "test_expect_error.ok.payload",
                    );
                }
            }
        }

        var result = c.LLVMConstNull(try self.toLLVMType(result_type));
        result = c.LLVMBuildInsertValue(self.builder, result, c.LLVMConstInt(c.LLVMInt32Type(), ok_variant_index, 0), 0, "test_expect_error.ok.tag");
        result = c.LLVMBuildInsertValue(self.builder, result, ok_payload, ok_variant_index + 1, "test_expect_error.ok.value");
        return result;
    }

    fn genTestingExpectError(self: *CodeGenerator, expect_err: *const sem.TestingExpectError) !TypedValue {
        const actual_tv = (try self.visitNode(expect_err.actual_result)) orelse return CodegenError.ValueNotFound;
        const actual_tag = c.LLVMBuildExtractValue(self.builder, actual_tv.value_ref, 0, "test_expect_error.actual.tag");
        const error_tag = c.LLVMConstInt(c.LLVMInt32Type(), expect_err.actual_error_variant_index, 0);
        const is_error = c.LLVMBuildICmp(self.builder, c.LLVMIntEQ, actual_tag, error_tag, "test_expect_error.is_error");

        const current_bb = c.LLVMGetInsertBlock(self.builder);
        const parent_fn = c.LLVMGetBasicBlockParent(current_bb);
        const actual_ok_bb = c.LLVMAppendBasicBlock(parent_fn, "test_expect_error.ok");
        const actual_error_bb = c.LLVMAppendBasicBlock(parent_fn, "test_expect_error.error");
        const reason_mismatch_bb = c.LLVMAppendBasicBlock(parent_fn, "test_expect_error.reason_mismatch");
        const success_bb = c.LLVMAppendBasicBlock(parent_fn, "test_expect_error.success");
        const merge_bb = c.LLVMAppendBasicBlock(parent_fn, "test_expect_error.merge");
        _ = c.LLVMBuildCondBr(self.builder, is_error, actual_error_bb, actual_ok_bb);

        c.LLVMPositionBuilderAtEnd(self.builder, actual_ok_bb);
        const unexpected_ok_context_z = try self.dupZ("expect_error failed: expression succeeded unexpectedly");
        const unexpected_ok_context_ptr = c.LLVMBuildGlobalStringPtr(self.builder, unexpected_ok_context_z.ptr, "test_expect_error_unexpected_ok");
        const unexpected_ok_result = try self.buildTestingFailureErrable(
            expect_err.result_type,
            unexpected_ok_context_ptr,
            expect_err.line,
            expect_err.column,
            expect_err.source_file,
            expect_err.source_line,
        );
        _ = c.LLVMBuildBr(self.builder, merge_bb);
        const actual_ok_end_bb = c.LLVMGetInsertBlock(self.builder);

        c.LLVMPositionBuilderAtEnd(self.builder, actual_error_bb);
        const actual_error_payload = c.LLVMBuildExtractValue(
            self.builder,
            actual_tv.value_ref,
            expect_err.actual_error_variant_index + 1,
            "test_expect_error.error.payload",
        );
        const actual_reason = c.LLVMBuildExtractValue(
            self.builder,
            actual_error_payload,
            expect_err.actual_reason_field_index,
            "test_expect_error.error.reason",
        );
        const actual_reason_tag = c.LLVMBuildExtractValue(self.builder, actual_reason, 0, "test_expect_error.error.reason.tag");
        const expected_reason_tv = (try self.visitNode(expect_err.expected_reason)) orelse return CodegenError.ValueNotFound;
        const expected_reason_tag = c.LLVMBuildExtractValue(self.builder, expected_reason_tv.value_ref, 0, "test_expect_error.expected.reason.tag");
        const reason_matches = c.LLVMBuildICmp(
            self.builder,
            c.LLVMIntEQ,
            actual_reason_tag,
            expected_reason_tag,
            "test_expect_error.reason_matches",
        );
        _ = c.LLVMBuildCondBr(self.builder, reason_matches, success_bb, reason_mismatch_bb);

        c.LLVMPositionBuilderAtEnd(self.builder, reason_mismatch_bb);
        const actual_reason_choice = switch (expect_err.actual_error_payload_type) {
            .struct_type => |payload_struct| switch (payload_struct.fields[expect_err.actual_reason_field_index].ty) {
                .choice_type => |choice_ty| choice_ty,
                else => return CodegenError.InvalidType,
            },
            else => return CodegenError.InvalidType,
        };
        const mismatch_context_ptr = try self.buildTestingExpectErrorMismatchContext(
            actual_reason_tag,
            actual_reason_choice,
            expect_err.expected_reason_name,
        );
        const mismatch_result = try self.buildTestingFailureErrable(
            expect_err.result_type,
            mismatch_context_ptr,
            expect_err.line,
            expect_err.column,
            expect_err.source_file,
            expect_err.source_line,
        );
        _ = c.LLVMBuildBr(self.builder, merge_bb);
        const reason_mismatch_end_bb = c.LLVMGetInsertBlock(self.builder);

        c.LLVMPositionBuilderAtEnd(self.builder, success_bb);
        const success_result = try self.buildErrableOkVoid(
            expect_err.result_type,
            expect_err.result_ok_variant_index,
        );
        _ = c.LLVMBuildBr(self.builder, merge_bb);
        const success_end_bb = c.LLVMGetInsertBlock(self.builder);

        c.LLVMPositionBuilderAtEnd(self.builder, merge_bb);
        const result_ty = try self.toLLVMType(expect_err.result_type);
        const phi = c.LLVMBuildPhi(self.builder, result_ty, "test_expect_error.result");
        var incoming_values = [_]llvm.c.LLVMValueRef{ unexpected_ok_result, mismatch_result, success_result };
        var incoming_blocks = [_]llvm.c.LLVMBasicBlockRef{ actual_ok_end_bb, reason_mismatch_end_bb, success_end_bb };
        c.LLVMAddIncoming(phi, &incoming_values, &incoming_blocks, incoming_values.len);
        return .{ .value_ref = phi, .type_ref = result_ty, .sem_type = expect_err.result_type };
    }

    fn findTopLevelFunctionByName(self: *CodeGenerator, name: []const u8) ?*const sem.FunctionDeclaration {
        for (self.ast) |node| {
            switch (node.content) {
                .function_declaration => |decl| {
                    if (std.mem.eql(u8, decl.name, name)) return decl;
                },
                else => {},
            }
        }
        return null;
    }

    fn findChoiceVariantIndexByName(choice_ty: *const sem.ChoiceType, name: []const u8) ?u32 {
        for (choice_ty.variants, 0..) |variant, idx| {
            if (std.mem.eql(u8, variant.name, name)) return @intCast(idx);
        }
        return null;
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
            const field_tv = try self.genEntryInputFieldValue(field);
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

    fn genCTestWrapper(self: *CodeGenerator, user_test: *const sem.FunctionDeclaration) !void {
        try self.ensureRuntimeArgGlobals();
        try self.ensureRuntimeArgFunctions();

        const user_key = try self.functionSymbolKey(user_test);
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

        var input_agg = c.LLVMGetUndef(try self.toLLVMType(.{ .struct_type = &user_test.input }));
        for (user_test.input.fields, 0..) |field, idx| {
            const field_tv = try self.genEntryInputFieldValue(field);
            input_agg = c.LLVMBuildInsertValue(self.builder, input_agg, field_tv.value_ref, @intCast(idx), "test.default");
        }

        var argv = try self.allocator.alloc(llvm.c.LLVMValueRef, 1);
        defer self.allocator.free(argv);
        argv[0] = input_agg;

        const call_result = c.LLVMBuildCall2(self.builder, user_sym.type_ref, user_sym.ref, argv.ptr, 1, "test.call");
        const result_ty = sem_types.functionReturnType(@constCast(user_test));
        const errable_choice = switch (result_ty) {
            .choice_type => |choice_ty| choice_ty,
            else => return CodegenError.InvalidType,
        };
        const result = if (c.LLVMGetTypeKind(c.LLVMTypeOf(call_result)) == c.LLVMStructTypeKind)
            c.LLVMBuildExtractValue(self.builder, call_result, 0, "test.result")
        else
            call_result;
        const error_variant_index = findChoiceVariantIndexByName(errable_choice, "error") orelse return CodegenError.InvalidType;
        const error_tag = c.LLVMConstInt(c.LLVMInt32Type(), error_variant_index, 0);
        const tag_val = c.LLVMBuildExtractValue(self.builder, result, 0, "test.tag");
        const is_error = c.LLVMBuildICmp(self.builder, c.LLVMIntEQ, tag_val, error_tag, "test.is_error");

        const error_bb = c.LLVMAppendBasicBlock(fn_ref, "test.error");
        const ok_bb = c.LLVMAppendBasicBlock(fn_ref, "test.ok");
        _ = c.LLVMBuildCondBr(self.builder, is_error, error_bb, ok_bb);

        c.LLVMPositionBuilderAtEnd(self.builder, ok_bb);
        _ = c.LLVMBuildRet(self.builder, c.LLVMConstInt(int32_ty, 0, 0));

        c.LLVMPositionBuilderAtEnd(self.builder, error_bb);
        const error_payload = c.LLVMBuildExtractValue(self.builder, result, error_variant_index + 1, "test.error.payload");
        const error_struct = switch (errable_choice.variants[error_variant_index].payload_type.?) {
            .struct_type => |struct_ty| struct_ty,
            else => return CodegenError.InvalidType,
        };
        const reason_index = fieldIndexByName(error_struct, "reason") orelse return CodegenError.InvalidType;
        const trace_index = fieldIndexByName(error_struct, "trace") orelse return CodegenError.InvalidType;
        const reason_value = c.LLVMBuildExtractValue(self.builder, error_payload, reason_index, "test.error.reason");
        const trace_value = c.LLVMBuildExtractValue(self.builder, error_payload, trace_index, "test.error.trace");

        if (self.findTopLevelFunctionByName("report_trace")) |report_trace_fn| {
            const report_key = try self.functionSymbolKey(report_trace_fn);
            if (self.global_scope.lookup(report_key)) |report_sym| {
                const trace_ty = error_struct.fields[trace_index].ty;
                const trace_alloca = c.LLVMBuildAlloca(self.builder, try self.toLLVMType(trace_ty), "test.trace.addr");
                _ = c.LLVMBuildStore(self.builder, trace_value, trace_alloca);

                var report_input = c.LLVMGetUndef(try self.toLLVMType(.{ .struct_type = &report_trace_fn.input }));
                report_input = c.LLVMBuildInsertValue(self.builder, report_input, trace_alloca, 0, "test.report.trace");

                var report_args = [_]llvm.c.LLVMValueRef{report_input};
                _ = c.LLVMBuildCall2(self.builder, report_sym.type_ref, report_sym.ref, &report_args, 1, "");
            }
        }

        const reason_choice = switch (error_struct.fields[reason_index].ty) {
            .choice_type => |choice_ty| choice_ty,
            else => return CodegenError.InvalidType,
        };
        const reason_tag = c.LLVMBuildExtractValue(self.builder, reason_value, 0, "test.error.reason.tag");
        const skip_code = c.LLVMConstInt(int32_ty, 77, 0);
        const fail_code = c.LLVMConstInt(int32_ty, 1, 0);
        if (findChoiceVariantIndexByName(reason_choice, "test_skipped")) |skipped_index| {
            const skipped_tag = c.LLVMConstInt(c.LLVMInt32Type(), skipped_index, 0);
            const is_skipped = c.LLVMBuildICmp(self.builder, c.LLVMIntEQ, reason_tag, skipped_tag, "test.is_skipped");
            const exit_code = c.LLVMBuildSelect(self.builder, is_skipped, skip_code, fail_code, "test.exit");
            _ = c.LLVMBuildRet(self.builder, exit_code);
            return;
        }

        _ = c.LLVMBuildRet(self.builder, fail_code);
    }
};
