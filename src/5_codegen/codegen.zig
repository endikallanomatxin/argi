const std = @import("std");
const llvm = @import("llvm.zig");
const c = llvm.c;
const graph_mod = @import("../4_semantics/global/graph.zig");
const types = @import("../4_semantics/global/types.zig");
const initializer_contract = @import("../4_semantics/global/initializer_contract.zig");
const primitives = @import("../4_semantics/primitives/schema.zig");
const diagnostic = @import("../1_base/diagnostic.zig");
const tok = @import("../2_tokens/token.zig");
const syn = @import("../3_syntax/syntax_tree.zig");
const type_codegen = @import("type_codegen.zig");

pub const CodegenError = error{
    ModuleCreationFailed,
    SymbolNotFound,
    SymbolAlreadyDefined,
    OutOfMemory,
    UnknownNode,
    ValueNotFound,
    ConstantReassignment,
    CompilationFailed,
    ExpressionNotFound,
    InvalidType,
    NonConstantGlobalInitializer,
    Reported,
};

const TypedValue = struct {
    value_ref: llvm.c.LLVMValueRef,
    type_ref: llvm.c.LLVMTypeRef,
    ty: ?graph_mod.GlobalTypeId = null,
};

const DropState = struct {
    flag_ref: llvm.c.LLVMValueRef,
    fields: []DropState = &.{},
};

const BindingStorage = struct {
    ref: llvm.c.LLVMValueRef,
    type_ref: llvm.c.LLVMTypeRef,
    ty: graph_mod.GlobalTypeId,
    initialized: bool = false,
    drop_state: ?*DropState = null,
};

const FunctionSymbol = struct {
    ref: llvm.c.LLVMValueRef,
    type_ref: llvm.c.LLVMTypeRef,
    return_type: llvm.c.LLVMTypeRef,
    is_extern: bool,
    is_c_abi: bool = false,
    uses_sret: bool = false,
};

const GlobalInitState = enum { uninitialized, in_progress, done };
const LoopContext = struct { break_block: llvm.c.LLVMBasicBlockRef, continue_block: llvm.c.LLVMBasicBlockRef };

pub const CodeGenerator = struct {
    pub const Options = struct { selected_test_name: ?[]const u8 = null };
    pub const Stats = struct {
        semantic_functions: usize = 0,
        llvm_functions_with_body: usize = 0,
        reachable_llvm_functions_with_body: usize = 0,
        pruned_llvm_function_bodies: usize = 0,
        basic_blocks: usize = 0,
        instructions: usize = 0,
        ir_bytes: usize = 0,
    };

    allocator: std.mem.Allocator,
    io: std.Io,
    graph: *const graph_mod.GlobalSemanticGraph,
    diags: *diagnostic.Diagnostics,
    options: Options,
    module: llvm.c.LLVMModuleRef,
    builder: llvm.c.LLVMBuilderRef,
    functions: std.AutoHashMap(graph_mod.GlobalFunctionId, FunctionSymbol),
    bindings: std.AutoHashMap(graph_mod.GlobalBindingId, BindingStorage),
    global_bindings: std.AutoHashMap(graph_mod.GlobalBindingId, GlobalInitState),
    loop_stack: std.array_list.Managed(LoopContext),
    current_function: ?graph_mod.GlobalFunctionId = null,
    current_return_type: ?llvm.c.LLVMTypeRef = null,
    main_candidate: ?graph_mod.GlobalFunctionId = null,
    selected_test_candidate: ?graph_mod.GlobalFunctionId = null,
    string_literal_counter: u32 = 0,
    virtual_table_counter: u32 = 0,
    trace_locations: std.ArrayList(primitives.SourceRef) = .empty,
    default_location_source: ?primitives.SourceRef = null,
    runtime_argc_global: ?llvm.c.LLVMValueRef = null,
    runtime_argv_global: ?llvm.c.LLVMValueRef = null,
    pruned_function_bodies: usize = 0,

    pub fn init(
        allocator: std.mem.Allocator,
        io: std.Io,
        graph: *const graph_mod.GlobalSemanticGraph,
        diags: *diagnostic.Diagnostics,
        options: Options,
    ) !CodeGenerator {
        const module = c.LLVMModuleCreateWithName("argi_module") orelse return CodegenError.ModuleCreationFailed;
        errdefer c.LLVMDisposeModule(module);
        const builder = c.LLVMCreateBuilder() orelse return CodegenError.ModuleCreationFailed;
        errdefer c.LLVMDisposeBuilder(builder);
        return .{
            .allocator = allocator,
            .io = io,
            .graph = graph,
            .diags = diags,
            .options = options,
            .module = module,
            .builder = builder,
            .functions = std.AutoHashMap(graph_mod.GlobalFunctionId, FunctionSymbol).init(allocator),
            .bindings = std.AutoHashMap(graph_mod.GlobalBindingId, BindingStorage).init(allocator),
            .global_bindings = std.AutoHashMap(graph_mod.GlobalBindingId, GlobalInitState).init(allocator),
            .loop_stack = std.array_list.Managed(LoopContext).init(allocator),
        };
    }

    pub fn deinit(self: *CodeGenerator) void {
        if (self.builder) |builder| c.LLVMDisposeBuilder(builder);
        if (self.module) |module| c.LLVMDisposeModule(module);
        self.functions.deinit();
        self.bindings.deinit();
        self.global_bindings.deinit();
        self.loop_stack.deinit();
        self.trace_locations.deinit(self.allocator);
    }

    fn typeLowerer(self: *CodeGenerator) type_codegen.Lowerer {
        return .{ .allocator = self.allocator, .graph = self.graph };
    }

    fn toLLVMType(self: *CodeGenerator, ty: graph_mod.GlobalTypeId) !llvm.c.LLVMTypeRef {
        var lowerer = self.typeLowerer();
        return lowerer.toLLVMType(ty) catch return CodegenError.InvalidType;
    }

    fn fieldsLLVMType(self: *CodeGenerator, range: graph_mod.FieldRange) !llvm.c.LLVMTypeRef {
        if (range.len == 0) return c.LLVMStructType(null, 0, 0);
        const fields = try self.allocator.alloc(llvm.c.LLVMTypeRef, range.len);
        defer self.allocator.free(fields);
        for (self.graph.fields.items[range.start..][0..range.len], 0..) |field, index|
            fields[index] = try self.toLLVMType(types.effectiveFieldType(field));
        return c.LLVMStructType(fields.ptr, @intCast(range.len), 0);
    }

    pub fn generate(self: *CodeGenerator) !llvm.c.LLVMModuleRef {
        try self.predeclareFunctions();
        try self.predeclareGlobalBindings();
        try self.initializeGlobalBindings();

        for (self.graph.functions.items, 0..) |function, raw| {
            if (function.body == null or function.flags.is_abstract_dispatch) continue;
            if (self.isCoreFunction(@enumFromInt(@as(u32, @intCast(raw))), "source_location")) continue;
            const id: graph_mod.GlobalFunctionId = @enumFromInt(@as(u32, @intCast(raw)));
            self.generateFunctionBody(id) catch |err| {
                if (err == CodegenError.Reported or err == error.OutOfMemory) return err;
                const declaration = self.graph.declaration(function.declaration);
                try self.report(declaration.source, "cannot generate function '{s}': {s}", .{ self.graph.text(declaration.name), @errorName(err) });
                return CodegenError.Reported;
            };
        }

        for (self.graph.functions.items, 0..) |_, raw| {
            const id: graph_mod.GlobalFunctionId = @enumFromInt(@as(u32, @intCast(raw)));
            if (self.isCoreFunction(id, "source_location")) try self.generateTraceLocationResolver(id);
        }

        if (self.options.selected_test_name != null) {
            if (self.selected_test_candidate) |id| try self.generateCTestWrapper(id);
        } else if (self.main_candidate) |id| {
            try self.generateCMainWrapper(id);
        }

        try self.pruneUnreachableFunctionBodies();

        var message: [*c]u8 = null;
        if (c.LLVMVerifyModule(self.module, c.LLVMReturnStatusAction, &message) != 0) {
            if (message != null) {
                const text = std.mem.span(message);
                try self.diags.add(self.firstLocation(), .codegen, "LLVM verification failed: {s}", .{text});
                c.LLVMDisposeMessage(message);
            }
            return CodegenError.ModuleCreationFailed;
        }
        return self.module;
    }

    fn predeclareFunctions(self: *CodeGenerator) !void {
        for (self.graph.functions.items, 0..) |function, raw| {
            // Abstract contract instances are compile-time dispatch metadata.
            // Runtime calls and vtables reference their selected concrete
            // implementations, so an abstract Self type must not enter ABI
            // lowering as though it were a material runtime type.
            if (function.flags.is_abstract_dispatch) continue;
            // Declarations that promised a body but have no global body are
            // semantic contracts/templates, not runtime ABI symbols.
            if (function.body == null and function.flags.has_declared_body) continue;
            const id: graph_mod.GlobalFunctionId = @enumFromInt(@as(u32, @intCast(raw)));
            _ = self.declareFunction(id) catch |err| {
                if (err == CodegenError.Reported or err == error.OutOfMemory) return err;
                const declaration = self.graph.declaration(function.declaration);
                try self.report(declaration.source, "cannot lower function signature '{s}': {s}", .{ self.graph.text(declaration.name), @errorName(err) });
                return CodegenError.Reported;
            };
        }
    }

    fn declareFunction(self: *CodeGenerator, id: graph_mod.GlobalFunctionId) !FunctionSymbol {
        if (self.functions.get(id)) |existing| return existing;
        const function = self.graph.functions.items[@intFromEnum(id)];
        const declaration = self.graph.declarations.items[@intFromEnum(function.declaration)];
        const name = self.graph.text(declaration.name);
        const is_extern = function.body == null and !function.flags.has_declared_body;
        var symbol: FunctionSymbol = undefined;

        if (is_extern or function.flags.is_c_abi) {
            const signature = try self.externSignature(function, name);
            // Bundled memory bindings remain module-private in Argi while
            // resolving the platform's public C symbols at link time.
            var lowerer = self.typeLowerer();
            const private_name = if (!is_extern and !function.flags.is_c_export and function.foreign_symbol == null)
                try lowerer.mangledFunctionName(id)
            else
                null;
            defer if (private_name) |allocated| self.allocator.free(allocated);
            const external_name = private_name orelse self.externSymbolName(function, name);
            if (function.flags.is_c_export and std.mem.eql(u8, external_name, "main")) {
                try self.report(declaration.source, "C export symbol 'main' is reserved for the generated program entrypoint", .{});
                return CodegenError.Reported;
            }
            const name_z = try self.dupZ(external_name);
            const existing = c.LLVMGetNamedFunction(self.module, name_z.ptr);
            if (existing != null and c.LLVMGlobalGetValueType(existing) != signature.fn_type) {
                try self.report(declaration.source, "C symbol '{s}' is declared with incompatible signatures", .{external_name});
                return CodegenError.Reported;
            }
            if (!is_extern and existing != null) {
                if (!function.flags.is_c_export) {
                    try self.report(declaration.source, "private C symbol '{s}' conflicts with another declaration", .{external_name});
                    return CodegenError.Reported;
                }
                var symbols = self.functions.valueIterator();
                while (symbols.next()) |previous| {
                    if (previous.ref == existing and !previous.is_extern) {
                        try self.report(declaration.source, "C symbol '{s}' has multiple definitions", .{external_name});
                        return CodegenError.Reported;
                    }
                }
            }
            const ref = if (existing != null) existing else c.LLVMAddFunction(self.module, name_z.ptr, signature.fn_type);
            if (!is_extern and !function.flags.is_c_export)
                c.LLVMSetLinkage(ref, c.LLVMInternalLinkage);
            if (signature.uses_sret) {
                const kind = c.LLVMGetEnumAttributeKindForName("sret", 4);
                const attr = c.LLVMCreateEnumAttribute(c.LLVMGetGlobalContext(), kind, 0);
                c.LLVMAddAttributeAtIndex(ref, 1, attr);
            }
            symbol = .{ .ref = ref, .type_ref = signature.fn_type, .return_type = signature.return_type, .is_extern = is_extern, .is_c_abi = true, .uses_sret = signature.uses_sret };
        } else {
            // TODO: pass large aggregate outputs through caller-owned storage
            // instead of direct LLVM returns; see the codegen task in plan/0.3.md.
            const input_ty = try self.fieldsLLVMType(function.input);
            const output_ty = try self.fieldsLLVMType(function.output);
            var parameters = [_]llvm.c.LLVMTypeRef{input_ty};
            const fn_ty = c.LLVMFunctionType(output_ty, &parameters, 1, 0);
            var lowerer = self.typeLowerer();
            const mangled = try lowerer.mangledFunctionName(id);
            defer self.allocator.free(mangled);
            const name_z = try self.dupZ(mangled);
            const ref = c.LLVMAddFunction(self.module, name_z.ptr, fn_ty);
            symbol = .{ .ref = ref, .type_ref = fn_ty, .return_type = output_ty, .is_extern = false };
        }
        try self.functions.put(id, symbol);

        if (function.flags.is_entry) {
            if (self.options.selected_test_name != null) {
                self.selected_test_candidate = id;
            } else {
                self.main_candidate = id;
            }
        }
        return symbol;
    }

    const ExternSignature = struct { fn_type: llvm.c.LLVMTypeRef, return_type: llvm.c.LLVMTypeRef, uses_sret: bool };

    fn externSymbolName(self: *CodeGenerator, function: graph_mod.Function, name: []const u8) []const u8 {
        if (function.foreign_symbol) |symbol| return self.graph.text(symbol);
        const source = self.graph.declaration(function.declaration).source;
        if (source.file_index >= self.graph.files.items.len) return name;
        const file = self.graph.files.items[source.file_index];
        if (!self.graph.modules.items[@intFromEnum(file.module)].is_bundled_core) return name;
        const aliases = .{
            .{ "_memory_mmap", "mmap" },
            .{ "_memory_munmap", "munmap" },
            .{ "_memory_getpagesize", "getpagesize" },
            .{ "_malloc", "malloc" },
            .{ "_aligned_alloc", "aligned_alloc" },
            .{ "_free", "free" },
        };
        inline for (aliases) |alias| if (std.mem.eql(u8, name, alias[0])) return alias[1];
        return name;
    }

    fn externSignature(self: *CodeGenerator, function: graph_mod.Function, name: []const u8) !ExternSignature {
        const uses_sret = function.output.len > 1;
        const physical_inputs = @import("../4_semantics/global/c_abi.zig").physicalInputCount(function);
        const total: usize = physical_inputs + @as(usize, if (uses_sret) 1 else 0);
        const params = try self.allocator.alloc(llvm.c.LLVMTypeRef, total);
        defer self.allocator.free(params);
        var cursor: usize = 0;
        if (uses_sret) {
            params[0] = c.LLVMPointerType(try self.fieldsLLVMType(function.output), 0);
            cursor = 1;
        }
        for (self.graph.fields.items[function.input.start..][0..physical_inputs], 0..) |field, index|
            params[cursor + index] = try self.toLLVMType(field.ty);
        if (std.mem.eql(u8, self.externSymbolName(function, name), "free") and physical_inputs == 1)
            params[cursor] = c.LLVMPointerType(c.LLVMInt8Type(), 0);

        var ret = c.LLVMVoidType();
        if (function.output.len == 1) ret = try self.toLLVMType(self.graph.fields.items[function.output.start].ty);
        if (function.safety_primitive == .raw_allocated_storage) ret = c.LLVMPointerType(c.LLVMInt8Type(), 0);
        return .{ .fn_type = c.LLVMFunctionType(ret, if (total == 0) null else params.ptr, @intCast(total), 0), .return_type = ret, .uses_sret = uses_sret };
    }

    fn predeclareGlobalBindings(self: *CodeGenerator) !void {
        for (self.graph.roots.items) |node_id| {
            const node = self.graph.nodes.items[@intFromEnum(node_id)];
            const binding = switch (node.content) {
                .binding_declaration => |id| id,
                else => continue,
            };
            if (self.global_bindings.contains(binding)) continue;
            const record = self.graph.bindings.items[@intFromEnum(binding)];
            const type_ref = try self.toLLVMType(record.ty);
            const name_z = try self.dupZ(self.graph.text(record.name));
            const storage = c.LLVMAddGlobal(self.module, type_ref, name_z.ptr);
            c.LLVMSetInitializer(storage, c.LLVMConstNull(type_ref));
            try self.bindings.put(binding, .{ .ref = storage, .type_ref = type_ref, .ty = record.ty });
            try self.global_bindings.put(binding, .uninitialized);
        }
    }

    fn initializeGlobalBindings(self: *CodeGenerator) !void {
        for (self.graph.roots.items) |node_id| switch (self.graph.nodes.items[@intFromEnum(node_id)].content) {
            .binding_declaration => |binding| try self.ensureGlobalInitialized(binding),
            else => {},
        };
    }

    fn ensureGlobalInitialized(self: *CodeGenerator, binding: graph_mod.GlobalBindingId) CodegenError!void {
        const state = self.global_bindings.get(binding) orelse return;
        if (state == .done) return;
        const record = self.graph.bindings.items[@intFromEnum(binding)];
        if (state == .in_progress) {
            try self.report(record.source, "module-level binding '{s}' participates in a cyclic initializer dependency", .{self.graph.text(record.name)});
            return CodegenError.Reported;
        }
        try self.global_bindings.put(binding, .in_progress);
        const storage = self.bindings.get(binding) orelse return CodegenError.SymbolNotFound;
        if (record.initialization) |initialization| {
            const value = self.globalConstant(initialization) catch |err| switch (err) {
                error.NonConstantGlobalInitializer => {
                    try self.report(record.source, "module-level binding '{s}' must use a constant initializer for now", .{self.graph.text(record.name)});
                    return CodegenError.Reported;
                },
                else => return err,
            };
            if (value.type_ref != storage.type_ref) return CodegenError.InvalidType;
            c.LLVMSetInitializer(storage.ref, value.value_ref);
        }
        try self.global_bindings.put(binding, .done);
    }

    fn globalConstant(self: *CodeGenerator, node_id: graph_mod.GlobalNodeId) CodegenError!TypedValue {
        const node = self.graph.nodes.items[@intFromEnum(node_id)];
        return switch (node.content) {
            .int_literal, .float_literal, .char_literal, .bool_literal, .string_literal => self.emitLiteral(node_id),
            .binary_operation => |operation| self.globalBinaryConstant(operation),
            .binding_use => |binding| blk: {
                try self.ensureGlobalInitialized(binding);
                const storage = self.bindings.get(binding) orelse return CodegenError.SymbolNotFound;
                const initializer = c.LLVMGetInitializer(storage.ref) orelse return CodegenError.InvalidType;
                break :blk .{ .value_ref = initializer, .type_ref = storage.type_ref, .ty = storage.ty };
            },
            .address_of => |target| blk: {
                const target_node = self.graph.nodes.items[@intFromEnum(target)];
                const binding = switch (target_node.content) {
                    .binding_use => |id| id,
                    else => return CodegenError.InvalidType,
                };
                try self.ensureGlobalInitialized(binding);
                const storage = self.bindings.get(binding) orelse return CodegenError.SymbolNotFound;
                break :blk .{ .value_ref = storage.ref, .type_ref = c.LLVMPointerType(storage.type_ref, 0), .ty = node.ty };
            },
            .struct_value_literal => |literal| blk: {
                const ty = node.ty orelse return CodegenError.InvalidType;
                const type_ref = try self.toLLVMType(ty);
                const range = types.fields(self.graph, ty) orelse return CodegenError.InvalidType;
                const values = try self.allocator.alloc(c.LLVMValueRef, range.len);
                defer self.allocator.free(values);
                for (self.graph.fields.items[range.start..][0..range.len], 0..) |field, index| {
                    var value_node = field.default_value;
                    for (self.graph.value_fields.items[literal.fields.start..][0..literal.fields.len]) |supplied| {
                        if (std.mem.eql(u8, self.graph.text(field.name), self.graph.text(supplied.name))) value_node = supplied.value;
                    }
                    values[index] = if (value_node) |value| (try self.globalConstant(value)).value_ref else c.LLVMConstNull(try self.toLLVMType(field.ty));
                }
                break :blk .{ .value_ref = c.LLVMConstNamedStruct(type_ref, values.ptr, @intCast(values.len)), .type_ref = type_ref, .ty = ty };
            },
            .virtualize => |virtualize_id| blk: {
                const virtualize = self.graph.virtualizes.items[@intFromEnum(virtualize_id)];
                const receiver = try self.globalConstant(virtualize.value);
                const table = try self.virtualTable(virtualize.methods);
                const type_ref = try self.toLLVMType(virtualize.virtual_type);
                var values = [_]c.LLVMValueRef{ receiver.value_ref, table };
                break :blk .{ .value_ref = c.LLVMConstNamedStruct(type_ref, &values, 2), .type_ref = type_ref, .ty = virtualize.virtual_type };
            },
            else => CodegenError.NonConstantGlobalInitializer,
        };
    }

    fn globalBinaryConstant(self: *CodeGenerator, operation: anytype) CodegenError!TypedValue {
        const left = try self.globalConstant(operation.left);
        const right = try self.globalConstant(operation.right);
        if (left.type_ref != right.type_ref) return CodegenError.InvalidType;
        const ty = left.ty orelse return CodegenError.InvalidType;
        if (self.isFloat(ty)) {
            var loses_info: c.LLVMBool = 0;
            const a = c.LLVMConstRealGetDouble(left.value_ref, &loses_info);
            const b = c.LLVMConstRealGetDouble(right.value_ref, &loses_info);
            const result = switch (operation.operator) {
                .addition => a + b,
                .subtraction => a - b,
                .multiplication => a * b,
                .division => a / b,
                .modulo => @rem(a, b),
            };
            return .{ .value_ref = c.LLVMConstReal(left.type_ref, result), .type_ref = left.type_ref, .ty = ty };
        }
        if (c.LLVMGetTypeKind(left.type_ref) != c.LLVMIntegerTypeKind or c.LLVMGetIntTypeWidth(left.type_ref) > 64)
            return CodegenError.InvalidType;
        const unsigned = self.isUnsigned(ty);
        const a = c.LLVMConstIntGetZExtValue(left.value_ref);
        const b = c.LLVMConstIntGetZExtValue(right.value_ref);
        const result: u64 = if (unsigned) switch (operation.operator) {
            .addition => a +% b,
            .subtraction => a -% b,
            .multiplication => a *% b,
            .division => if (b != 0) a / b else return CodegenError.InvalidType,
            .modulo => if (b != 0) a % b else return CodegenError.InvalidType,
        } else blk: {
            const signed_a = c.LLVMConstIntGetSExtValue(left.value_ref);
            const signed_b = c.LLVMConstIntGetSExtValue(right.value_ref);
            const signed_result: i64 = switch (operation.operator) {
                .addition => signed_a +% signed_b,
                .subtraction => signed_a -% signed_b,
                .multiplication => signed_a *% signed_b,
                .division => if (signed_b != 0 and !(signed_a == std.math.minInt(i64) and signed_b == -1)) @divTrunc(signed_a, signed_b) else return CodegenError.InvalidType,
                .modulo => if (signed_b != 0 and !(signed_a == std.math.minInt(i64) and signed_b == -1)) @rem(signed_a, signed_b) else return CodegenError.InvalidType,
            };
            break :blk @bitCast(signed_result);
        };
        return .{ .value_ref = c.LLVMConstInt(left.type_ref, result, 0), .type_ref = left.type_ref, .ty = ty };
    }

    fn generateFunctionBody(self: *CodeGenerator, id: graph_mod.GlobalFunctionId) !void {
        const function = self.graph.functions.items[@intFromEnum(id)];
        const body = function.body orelse return;
        const symbol = self.functions.get(id) orelse return CodegenError.SymbolNotFound;
        if (symbol.is_extern) return;

        const previous_function = self.current_function;
        const previous_return = self.current_return_type;
        self.current_function = id;
        self.current_return_type = symbol.return_type;
        defer {
            self.current_function = previous_function;
            self.current_return_type = previous_return;
        }

        const entry = c.LLVMAppendBasicBlock(symbol.ref, "entry");
        c.LLVMPositionBuilderAtEnd(self.builder, entry);
        const input_value = if (!symbol.is_c_abi) c.LLVMGetParam(symbol.ref, 0) else null;
        for (self.graph.binding_refs.items[function.input_bindings.start..][0..function.input_bindings.len], 0..) |binding, index| {
            try self.allocateLocalBinding(binding, null);
            const storage = self.bindings.getPtr(binding).?;
            const value = if (symbol.is_c_abi) c.LLVMGetParam(symbol.ref, @intCast(index)) else c.LLVMBuildExtractValue(self.builder, input_value, @intCast(index), "arg");
            _ = c.LLVMBuildStore(self.builder, value, storage.ref);
            storage.initialized = true;
            if (storage.drop_state) |drop| self.storeDropState(drop, true);
        }
        for (self.graph.binding_refs.items[function.output_bindings.start..][0..function.output_bindings.len]) |binding| {
            const record = self.graph.bindings.items[@intFromEnum(binding)];
            try self.allocateLocalBinding(binding, record.initialization);
            // Tests returning !() succeed when execution reaches the end of
            // the body. Materialize that success before statements can
            // propagate an error into the result binding.
            if (function.flags.is_test and record.initialization == null)
                try self.initializeTestResult(binding);
        }

        _ = try self.genBlock(body);
        const current = c.LLVMGetInsertBlock(self.builder);
        if (current != null and c.LLVMGetBasicBlockTerminator(current) == null)
            try self.emitImplicitReturn(function);
    }

    fn initializeTestResult(self: *CodeGenerator, binding: graph_mod.GlobalBindingId) !void {
        const storage = self.bindings.getPtr(binding) orelse return CodegenError.SymbolNotFound;
        const ok = types.findVariant(self.graph, storage.ty, "ok") orelse return CodegenError.InvalidType;
        const payload_ty = ok.variant.payload_type orelse return CodegenError.InvalidType;
        var result = c.LLVMGetUndef(storage.type_ref);
        result = c.LLVMBuildInsertValue(
            self.builder,
            result,
            c.LLVMConstInt(c.LLVMInt32Type(), ok.index, 0),
            0,
            "test.initial.ok.tag",
        );
        result = c.LLVMBuildInsertValue(
            self.builder,
            result,
            c.LLVMConstNull(try self.toLLVMType(payload_ty)),
            ok.index + 1,
            "test.initial.ok.payload",
        );
        _ = c.LLVMBuildStore(self.builder, result, storage.ref);
        storage.initialized = true;
        if (storage.drop_state) |drop| self.storeDropState(drop, true);
    }

    fn allocateLocalBinding(self: *CodeGenerator, binding: graph_mod.GlobalBindingId, initialization: ?graph_mod.GlobalNodeId) !void {
        if (self.bindings.contains(binding)) return;
        const record = self.graph.bindings.items[@intFromEnum(binding)];
        const type_ref = try self.toLLVMType(record.ty);
        const current_block = c.LLVMGetInsertBlock(self.builder) orelse return CodegenError.InvalidType;
        const function = c.LLVMGetBasicBlockParent(current_block);
        const entry = c.LLVMGetEntryBasicBlock(function);
        const entry_builder = c.LLVMCreateBuilder() orelse return CodegenError.ModuleCreationFailed;
        defer c.LLVMDisposeBuilder(entry_builder);
        if (c.LLVMGetFirstInstruction(entry)) |first| c.LLVMPositionBuilderBefore(entry_builder, first) else c.LLVMPositionBuilderAtEnd(entry_builder, entry);
        const name_z = try self.dupZ(self.graph.text(record.name));
        const storage = c.LLVMBuildAlloca(entry_builder, type_ref, name_z.ptr);
        const drop = try self.buildDropState(record.ty, entry_builder);
        try self.bindings.put(binding, .{ .ref = storage, .type_ref = type_ref, .ty = record.ty, .drop_state = drop });
        self.storeDropState(drop, false);
        if (initialization) |node| {
            const value = (try self.visitNode(node)) orelse return CodegenError.ValueNotFound;
            if (value.type_ref != type_ref) return CodegenError.InvalidType;
            _ = c.LLVMBuildStore(self.builder, value.value_ref, storage);
            const stored = self.bindings.getPtr(binding).?;
            stored.initialized = true;
            self.storeDropState(drop, true);
        }
    }

    fn genBlock(self: *CodeGenerator, block_id: graph_mod.GlobalBlockId) !?TypedValue {
        const block = self.graph.blocks.items[@intFromEnum(block_id)];
        var result: ?TypedValue = null;
        for (self.graph.node_refs.items[block.nodes.start..][0..block.nodes.len]) |node| {
            const current = c.LLVMGetInsertBlock(self.builder);
            if (current != null and c.LLVMGetBasicBlockTerminator(current) != null) break;
            const value = try self.visitNode(node);
            if (block.ret_val != null and node == block.ret_val.?) result = value;
        }
        return result;
    }

    fn visitNode(self: *CodeGenerator, node_id: graph_mod.GlobalNodeId) anyerror!?TypedValue {
        return self.visitNodeInner(node_id) catch |err| {
            if (err == CodegenError.Reported or err == error.OutOfMemory) return err;
            const node = self.graph.node(node_id);
            try self.report(node.source, "cannot generate {s}: {s}", .{ @tagName(node.content), @errorName(err) });
            return CodegenError.Reported;
        };
    }

    fn visitNodeInner(self: *CodeGenerator, node_id: graph_mod.GlobalNodeId) anyerror!?TypedValue {
        const node = self.graph.nodes.items[@intFromEnum(node_id)];
        return switch (node.content) {
            .declaration, .reach_directive, .type_literal => null,
            .binding_declaration => |binding| blk: {
                if (self.global_bindings.contains(binding)) {
                    try self.ensureGlobalInitialized(binding);
                } else {
                    const record = self.graph.bindings.items[@intFromEnum(binding)];
                    try self.allocateLocalBinding(binding, if (record.deferred_initialization) null else record.initialization);
                }
                break :blk null;
            },
            .binding_use => |binding| try self.bindingValue(binding),
            .assignment => |assignment| blk: {
                const storage = self.bindings.getPtr(assignment.binding) orelse return CodegenError.SymbolNotFound;
                if (self.graph.bindings.items[@intFromEnum(assignment.binding)].mutability == .constant and storage.initialized)
                    return CodegenError.ConstantReassignment;
                const value = (try self.visitNode(assignment.value)) orelse return CodegenError.ValueNotFound;
                if (value.type_ref != storage.type_ref) return CodegenError.InvalidType;
                _ = c.LLVMBuildStore(self.builder, value.value_ref, storage.ref);
                storage.initialized = true;
                if (storage.drop_state) |drop| self.storeDropState(drop, true);
                break :blk value;
            },
            .move_value => |value| blk: {
                const result = (try self.visitNode(value)) orelse return CodegenError.ValueNotFound;
                if (self.dropStateForNode(value)) |drop| self.storeDropState(drop, false);
                break :blk result;
            },
            .denied_implicit_copy => return CodegenError.InvalidType,
            .auto_deinit_binding => |auto| blk: {
                try self.genAutoDeinit(auto);
                break :blk null;
            },
            .function_call => |call| try self.genFunctionCall(call, node.source),
            .virtualize => |virtualize| try self.genVirtualize(virtualize),
            .virtual_call => |virtual_call| try self.genVirtualCall(virtual_call),
            .code_block => |block| try self.genBlock(block),
            .int_literal, .float_literal, .char_literal, .string_literal, .bool_literal => try self.emitLiteral(node_id),
            .list_literal => |literal| try self.listLiteral(literal, node.ty),
            .struct_value_literal => |literal| try self.structLiteral(literal, node.ty),
            .struct_field_access => |access| try self.fieldAccess(node_id, access),
            .choice_literal => |literal| try self.choiceLiteral(literal),
            .choice_payload_access => |access| try self.choicePayload(node_id, access),
            .nullable_unwrap_or => |unwrap| try self.nullableUnwrap(unwrap),
            .testing_expect_error => |id| try self.genTestingExpectError(self.graph.testing_expect_errors.items[@intFromEnum(id)], node.source),
            .error_propagation => |id| try self.genErrorPropagation(self.graph.error_propagations.items[@intFromEnum(id)], null, node.source),
            .error_context => |id| try self.genErrorPropagation(self.graph.error_contexts.items[@intFromEnum(id)], self.graph.error_contexts.items[@intFromEnum(id)].context, node.source),
            .array_literal => |literal| try self.arrayLiteral(literal),
            .array_index => |access| try self.arrayIndex(access),
            .array_store => |store| blk: {
                try self.arrayStore(store);
                break :blk null;
            },
            .struct_field_store => |store| blk: {
                try self.structFieldStore(store);
                break :blk null;
            },
            .binary_operation => |operation| try self.binary(operation),
            .comparison => |comparison| try self.emitComparison(comparison),
            .logical_operation => |operation| try self.logical(operation),
            .return_statement => |ret| blk: {
                try self.genReturn(ret);
                break :blk null;
            },
            .if_statement => |statement| blk: {
                try self.genIf(statement);
                break :blk null;
            },
            .while_statement => |statement| blk: {
                try self.genWhile(statement);
                break :blk null;
            },
            .for_statement => |statement| blk: {
                try self.genFor(statement);
                break :blk null;
            },
            .switch_statement => |switch_id| blk: {
                try self.genSwitch(switch_id);
                break :blk null;
            },
            .break_statement => blk: {
                try self.genBreak(node.source);
                break :blk null;
            },
            .continue_statement => blk: {
                try self.genContinue(node.source);
                break :blk null;
            },
            .abort_statement => blk: {
                const trap_type = c.LLVMFunctionType(c.LLVMVoidType(), null, 0, 0);
                const trap = c.LLVMGetNamedFunction(self.module, "llvm.trap") orelse c.LLVMAddFunction(self.module, "llvm.trap", trap_type);
                _ = c.LLVMBuildCall2(self.builder, trap_type, trap, null, 0, "");
                _ = c.LLVMBuildUnreachable(self.builder);
                break :blk null;
            },
            .address_of => |target| try self.addressOf(node_id, target),
            .dereference => |deref| try self.dereference(deref),
            .pointer_assignment => |assignment| blk: {
                try self.pointerAssignment(assignment);
                break :blk null;
            },
            .type_initializer => |initializer| try self.typeInitializer(initializer, node.ty),
            .explicit_cast => |cast| try self.explicitCast(cast),
        };
    }

    fn bindingValue(self: *CodeGenerator, binding: graph_mod.GlobalBindingId) !TypedValue {
        if (self.global_bindings.contains(binding)) try self.ensureGlobalInitialized(binding);
        const storage = self.bindings.get(binding) orelse return CodegenError.SymbolNotFound;
        return .{ .value_ref = c.LLVMBuildLoad2(self.builder, storage.type_ref, storage.ref, "binding"), .type_ref = storage.type_ref, .ty = storage.ty };
    }

    fn emitLiteral(self: *CodeGenerator, node_id: graph_mod.GlobalNodeId) !TypedValue {
        const node = self.graph.nodes.items[@intFromEnum(node_id)];
        return switch (node.content) {
            .bool_literal => |value| .{ .value_ref = c.LLVMConstInt(c.LLVMInt1Type(), if (value) 1 else 0, 0), .type_ref = c.LLVMInt1Type(), .ty = node.ty },
            .int_literal => |value| blk: {
                const type_ref = if (node.ty) |ty| try self.toLLVMType(ty) else c.LLVMInt32Type();
                break :blk .{ .value_ref = c.LLVMConstInt(type_ref, @as(u64, @truncate(@as(u128, @bitCast(value)))), if (value < 0) 1 else 0), .type_ref = type_ref, .ty = node.ty };
            },
            .float_literal => |value| blk: {
                const type_ref = if (node.ty) |ty| try self.toLLVMType(ty) else c.LLVMFloatType();
                break :blk .{ .value_ref = c.LLVMConstReal(type_ref, value), .type_ref = type_ref, .ty = node.ty };
            },
            .char_literal => |value| .{ .value_ref = c.LLVMConstInt(c.LLVMInt8Type(), value, 0), .type_ref = c.LLVMInt8Type(), .ty = node.ty },
            .string_literal => |range| blk: {
                const text = self.graph.text(range);
                const data = try self.emitStringLiteralPointer(text);
                if (node.ty) |ty| if (self.isStringView(ty)) {
                    const type_ref = try self.toLLVMType(ty);
                    const native = try self.nativeUIntType();
                    var fields = [_]llvm.c.LLVMValueRef{ data, c.LLVMConstInt(native, text.len, 0) };
                    break :blk .{ .value_ref = c.LLVMConstNamedStruct(type_ref, &fields, fields.len), .type_ref = type_ref, .ty = ty };
                };
                break :blk .{ .value_ref = data, .type_ref = c.LLVMPointerType(c.LLVMInt8Type(), 0), .ty = node.ty };
            },
            else => CodegenError.InvalidType,
        };
    }

    fn listLiteral(self: *CodeGenerator, literal: anytype, ty: ?graph_mod.GlobalTypeId) !TypedValue {
        const elements = self.graph.node_refs.items[literal.elements.start..][0..literal.elements.len];
        const values = try self.allocator.alloc(TypedValue, elements.len);
        defer self.allocator.free(values);
        const llvm_fields = try self.allocator.alloc(llvm.c.LLVMTypeRef, elements.len);
        defer self.allocator.free(llvm_fields);
        for (elements, 0..) |node, index| {
            values[index] = (try self.visitNode(node)) orelse return CodegenError.ValueNotFound;
            llvm_fields[index] = values[index].type_ref;
        }
        const type_ref = if (ty) |resolved_ty|
            if (types.arrayLength(self.graph, resolved_ty) != null)
                try self.toLLVMType(resolved_ty)
            else
                c.LLVMStructType(if (llvm_fields.len == 0) null else llvm_fields.ptr, @intCast(llvm_fields.len), 0)
        else
            c.LLVMStructType(if (llvm_fields.len == 0) null else llvm_fields.ptr, @intCast(llvm_fields.len), 0);
        var aggregate = c.LLVMGetUndef(type_ref);
        for (values, 0..) |value, index|
            aggregate = c.LLVMBuildInsertValue(self.builder, aggregate, value.value_ref, @intCast(index), "list.elem");
        return .{ .value_ref = aggregate, .type_ref = type_ref, .ty = ty };
    }

    fn structLiteral(self: *CodeGenerator, literal: anytype, maybe_ty: ?graph_mod.GlobalTypeId) !TypedValue {
        const ty = maybe_ty orelse return CodegenError.InvalidType;
        const type_ref = try self.toLLVMType(ty);
        if (types.isBuiltin(self.graph, ty, .Void) and literal.fields.len == 0)
            return .{ .value_ref = c.LLVMGetUndef(type_ref), .type_ref = type_ref, .ty = ty };
        const range = types.fields(self.graph, ty) orelse return CodegenError.InvalidType;
        if (self.isCUnion(ty)) {
            const temp = c.LLVMBuildAlloca(self.builder, type_ref, "union.literal");
            for (self.graph.value_fields.items[literal.fields.start..][0..literal.fields.len]) |value_field| {
                const name = self.graph.text(value_field.name);
                const hit = types.findField(self.graph, ty, name) orelse return CodegenError.InvalidType;
                const value = (try self.visitNode(value_field.value)) orelse return CodegenError.ValueNotFound;
                var lowerer = self.typeLowerer();
                const pointer = try lowerer.buildUnionFieldPointer(self.builder, temp, types.effectiveFieldType(hit.field), "union.literal.field");
                _ = c.LLVMBuildStore(self.builder, value.value_ref, pointer);
            }
            return .{ .value_ref = c.LLVMBuildLoad2(self.builder, type_ref, temp, "union.literal.value"), .type_ref = type_ref, .ty = ty };
        }
        if (literal.fields.len > range.len) return CodegenError.InvalidType;
        var aggregate = c.LLVMConstNull(type_ref);
        for (self.graph.value_fields.items[literal.fields.start..][0..literal.fields.len], 0..) |value_field, position| {
            const value = (try self.visitNode(value_field.value)) orelse return CodegenError.ValueNotFound;
            // Ordinary struct storage is positional. Source labels are useful
            // for semantic matching, but once a literal has a concrete storage
            // type its LLVM layout follows the field order. C unions remain
            // name-selected above because only one member is active.
            aggregate = c.LLVMBuildInsertValue(self.builder, aggregate, value.value_ref, @intCast(position), "struct.field");
        }
        return .{ .value_ref = aggregate, .type_ref = type_ref, .ty = ty };
    }

    fn fieldAccess(self: *CodeGenerator, node_id: graph_mod.GlobalNodeId, access: anytype) !TypedValue {
        const node = self.graph.nodes.items[@intFromEnum(node_id)];
        const field_ty = node.ty orelse return CodegenError.InvalidType;
        const maybe_pointer: ?TypedValue = self.addressablePointer(node_id) catch |err| switch (err) {
            error.InvalidType => null,
            else => return err,
        };
        if (maybe_pointer) |pointer| {
            const type_ref = try self.toLLVMType(field_ty);
            return .{ .value_ref = c.LLVMBuildLoad2(self.builder, type_ref, pointer.value_ref, "field"), .type_ref = type_ref, .ty = field_ty };
        }
        const aggregate = (try self.visitNode(access.value)) orelse return CodegenError.ValueNotFound;
        const type_ref = try self.toLLVMType(field_ty);
        return .{ .value_ref = c.LLVMBuildExtractValue(self.builder, aggregate.value_ref, access.field_index, "field"), .type_ref = type_ref, .ty = field_ty };
    }

    fn choiceLiteral(self: *CodeGenerator, literal: anytype) !TypedValue {
        const type_ref = try self.toLLVMType(literal.choice_type);
        const tag = try self.variantTag(literal.choice_type, literal.variant);
        if (self.isCEnum(literal.choice_type))
            return .{ .value_ref = c.LLVMConstInt(type_ref, @bitCast(@as(i64, tag)), 1), .type_ref = type_ref, .ty = literal.choice_type };
        var aggregate = c.LLVMGetUndef(type_ref);
        aggregate = c.LLVMBuildInsertValue(self.builder, aggregate, c.LLVMConstInt(c.LLVMInt32Type(), @bitCast(@as(i64, tag)), 1), 0, "choice.tag");
        if (literal.payload) |payload| {
            const value = (try self.visitNode(payload)) orelse return CodegenError.ValueNotFound;
            const index = try self.variantIndex(literal.choice_type, literal.variant);
            aggregate = c.LLVMBuildInsertValue(self.builder, aggregate, value.value_ref, index + 1, "choice.payload");
        }
        return .{ .value_ref = aggregate, .type_ref = type_ref, .ty = literal.choice_type };
    }

    fn choicePayload(self: *CodeGenerator, node_id: graph_mod.GlobalNodeId, access: anytype) !TypedValue {
        const payload_ty = access.payload_type;
        const pointer = self.addressablePointer(node_id) catch null;
        if (pointer) |ptr| {
            const type_ref = try self.toLLVMType(payload_ty);
            return .{ .value_ref = c.LLVMBuildLoad2(self.builder, type_ref, ptr.value_ref, "choice.payload"), .type_ref = type_ref, .ty = payload_ty };
        }
        const value = (try self.visitNode(access.value)) orelse return CodegenError.ValueNotFound;
        const choice_ty = self.graph.nodes.items[@intFromEnum(access.value)].ty orelse return CodegenError.InvalidType;
        const index = try self.variantIndex(choice_ty, access.variant);
        const payload = c.LLVMBuildExtractValue(self.builder, value.value_ref, index + 1, "choice.payload");
        return .{ .value_ref = payload, .type_ref = try self.toLLVMType(payload_ty), .ty = payload_ty };
    }

    fn arrayLiteral(self: *CodeGenerator, literal: anytype) !TypedValue {
        const element_ref = try self.toLLVMType(literal.element_type);
        const type_ref = c.LLVMArrayType(element_ref, literal.length);
        const values = try self.allocator.alloc(c.LLVMValueRef, literal.elements.len);
        defer self.allocator.free(values);
        var all_constant = true;
        for (self.graph.node_refs.items[literal.elements.start..][0..literal.elements.len], 0..) |node, index| {
            const value = (try self.visitNode(node)) orelse return CodegenError.ValueNotFound;
            values[index] = value.value_ref;
            all_constant = all_constant and c.LLVMIsConstant(value.value_ref) != 0;
        }
        // Build constants together: repeated constant insertions retain a
        // full intermediate aggregate per element, using quadratic storage.
        if (all_constant) return .{
            .value_ref = c.LLVMConstArray2(element_ref, values.ptr, values.len),
            .type_ref = type_ref,
            .ty = null,
        };
        var aggregate = c.LLVMGetUndef(type_ref);
        for (values, 0..) |value, index| {
            aggregate = c.LLVMBuildInsertValue(self.builder, aggregate, value, @intCast(index), "array.elem");
        }
        return .{ .value_ref = aggregate, .type_ref = type_ref, .ty = null };
    }

    fn arrayIndex(self: *CodeGenerator, access: anytype) !TypedValue {
        const pointer = try self.addressablePointer(access.array_ptr);
        const index = (try self.visitNode(access.index)) orelse return CodegenError.ValueNotFound;
        const array_type = try self.toLLVMType(access.array_type);
        const element_type = try self.toLLVMType(access.element_type);
        const element_ptr = try self.arrayElementPointer(pointer.value_ref, array_type, index.value_ref, access.array_type);
        return .{ .value_ref = c.LLVMBuildLoad2(self.builder, element_type, element_ptr, "array.elem"), .type_ref = element_type, .ty = access.element_type };
    }

    fn arrayStore(self: *CodeGenerator, store: anytype) !void {
        const pointer = try self.addressablePointer(store.array_ptr);
        const index = (try self.visitNode(store.index)) orelse return CodegenError.ValueNotFound;
        const value = (try self.visitNode(store.value)) orelse return CodegenError.ValueNotFound;
        const array_type = try self.toLLVMType(store.array_type);
        const element_ptr = try self.arrayElementPointer(pointer.value_ref, array_type, index.value_ref, store.array_type);
        _ = c.LLVMBuildStore(self.builder, value.value_ref, element_ptr);
    }

    fn arrayElementPointer(self: *CodeGenerator, pointer: llvm.c.LLVMValueRef, array_type: llvm.c.LLVMTypeRef, index: llvm.c.LLVMValueRef, semantic_type: graph_mod.GlobalTypeId) !llvm.c.LLVMValueRef {
        const length = types.arrayLength(self.graph, semantic_type) orelse return CodegenError.InvalidType;
        const limit = c.LLVMConstInt(c.LLVMTypeOf(index), length, 0);
        const inside = c.LLVMBuildICmp(self.builder, c.LLVMIntULT, index, limit, "array.index.inside");
        const function = c.LLVMGetBasicBlockParent(c.LLVMGetInsertBlock(self.builder));
        const valid_block = c.LLVMAppendBasicBlock(function, "array.index.valid");
        const invalid_block = c.LLVMAppendBasicBlock(function, "array.index.invalid");
        _ = c.LLVMBuildCondBr(self.builder, inside, valid_block, invalid_block);
        c.LLVMPositionBuilderAtEnd(self.builder, invalid_block);
        const trap_type = c.LLVMFunctionType(c.LLVMVoidType(), null, 0, 0);
        const trap = c.LLVMGetNamedFunction(self.module, "llvm.trap") orelse c.LLVMAddFunction(self.module, "llvm.trap", trap_type);
        _ = c.LLVMBuildCall2(self.builder, trap_type, trap, null, 0, "");
        _ = c.LLVMBuildUnreachable(self.builder);
        c.LLVMPositionBuilderAtEnd(self.builder, valid_block);
        const native = try self.nativeUIntType();
        const zero = c.LLVMConstInt(native, 0, 0);
        var indices = [_]llvm.c.LLVMValueRef{ zero, index };
        return c.LLVMBuildGEP2(self.builder, array_type, pointer, &indices, 2, "array.elem.ptr");
    }

    fn structFieldStore(self: *CodeGenerator, store: anytype) !void {
        const pointer = (try self.visitNode(store.struct_ptr)) orelse return CodegenError.ValueNotFound;
        const field_ptr = if (self.isCUnion(store.struct_type)) blk: {
            var lowerer = self.typeLowerer();
            break :blk try lowerer.buildUnionFieldPointer(self.builder, pointer.value_ref, store.field_type, "union.field.ptr");
        } else c.LLVMBuildStructGEP2(self.builder, try self.toLLVMType(store.struct_type), pointer.value_ref, store.field_index, "field.ptr");
        if (self.graph.nodes.items[@intFromEnum(store.value)].content == .type_initializer and
            self.graph.function(self.graph.nodes.items[@intFromEnum(store.value)].content.type_initializer.init_fn).output.len == 0)
        {
            try self.typeInitializerInto(self.graph.nodes.items[@intFromEnum(store.value)].content.type_initializer, field_ptr);
        } else {
            const value = (try self.visitNode(store.value)) orelse return CodegenError.ValueNotFound;
            _ = c.LLVMBuildStore(self.builder, value.value_ref, field_ptr);
        }
        if (self.dropStateForNode(store.struct_ptr)) |parent| if (store.field_index < parent.fields.len) self.storeDropState(&parent.fields[store.field_index], true);
    }

    fn binary(self: *CodeGenerator, operation: anytype) !TypedValue {
        const left = (try self.visitNode(operation.left)) orelse return CodegenError.ValueNotFound;
        const right = (try self.visitNode(operation.right)) orelse return CodegenError.ValueNotFound;
        if (left.type_ref != right.type_ref) return CodegenError.InvalidType;
        const float = if (left.ty) |ty| self.isFloat(ty) else false;
        const result = switch (operation.operator) {
            .addition => if (float) c.LLVMBuildFAdd(self.builder, left.value_ref, right.value_ref, "fadd") else c.LLVMBuildAdd(self.builder, left.value_ref, right.value_ref, "add"),
            .subtraction => if (float) c.LLVMBuildFSub(self.builder, left.value_ref, right.value_ref, "fsub") else c.LLVMBuildSub(self.builder, left.value_ref, right.value_ref, "sub"),
            .multiplication => if (float) c.LLVMBuildFMul(self.builder, left.value_ref, right.value_ref, "fmul") else c.LLVMBuildMul(self.builder, left.value_ref, right.value_ref, "mul"),
            .division => if (float) c.LLVMBuildFDiv(self.builder, left.value_ref, right.value_ref, "fdiv") else if (left.ty != null and self.isUnsigned(left.ty.?)) c.LLVMBuildUDiv(self.builder, left.value_ref, right.value_ref, "udiv") else c.LLVMBuildSDiv(self.builder, left.value_ref, right.value_ref, "sdiv"),
            .modulo => if (float) c.LLVMBuildFRem(self.builder, left.value_ref, right.value_ref, "frem") else if (left.ty != null and self.isUnsigned(left.ty.?)) c.LLVMBuildURem(self.builder, left.value_ref, right.value_ref, "urem") else c.LLVMBuildSRem(self.builder, left.value_ref, right.value_ref, "srem"),
        };
        return .{ .value_ref = result, .type_ref = left.type_ref, .ty = left.ty };
    }

    fn emitComparison(self: *CodeGenerator, comparison: anytype) !TypedValue {
        const left = (try self.visitNode(comparison.left)) orelse return CodegenError.ValueNotFound;
        const right = (try self.visitNode(comparison.right)) orelse return CodegenError.ValueNotFound;
        var left_value = left.value_ref;
        var right_value = right.value_ref;
        if (left.ty) |ty| {
            if (types.variants(self.graph, ty) != null and !self.isCEnum(ty)) {
                left_value = c.LLVMBuildExtractValue(self.builder, left_value, 0, "choice.lhs.tag");
                if (right.ty) |right_ty| {
                    if (types.variants(self.graph, right_ty) != null and !self.isCEnum(right_ty))
                        right_value = c.LLVMBuildExtractValue(self.builder, right_value, 0, "choice.rhs.tag");
                }
            }
        }
        if (c.LLVMTypeOf(left_value) != c.LLVMTypeOf(right_value)) {
            const right_node = self.graph.node(comparison.right);
            if (right_node.content != .int_literal or c.LLVMGetTypeKind(c.LLVMTypeOf(left_value)) != c.LLVMIntegerTypeKind)
                return CodegenError.InvalidType;
            right_value = c.LLVMConstInt(c.LLVMTypeOf(left_value), @as(u64, @truncate(@as(u128, @bitCast(right_node.content.int_literal)))), 1);
        }
        const float = if (left.ty) |ty| self.isFloat(ty) else false;
        const unsigned = if (left.ty) |ty| self.isUnsigned(ty) else false;
        const value = switch (comparison.operator) {
            .equal => if (float) c.LLVMBuildFCmp(self.builder, c.LLVMRealOEQ, left_value, right_value, "eq") else c.LLVMBuildICmp(self.builder, c.LLVMIntEQ, left_value, right_value, "eq"),
            .not_equal => if (float) c.LLVMBuildFCmp(self.builder, c.LLVMRealONE, left_value, right_value, "ne") else c.LLVMBuildICmp(self.builder, c.LLVMIntNE, left_value, right_value, "ne"),
            .less_than => if (float) c.LLVMBuildFCmp(self.builder, c.LLVMRealOLT, left_value, right_value, "lt") else c.LLVMBuildICmp(self.builder, if (unsigned) c.LLVMIntULT else c.LLVMIntSLT, left_value, right_value, "lt"),
            .greater_than => if (float) c.LLVMBuildFCmp(self.builder, c.LLVMRealOGT, left_value, right_value, "gt") else c.LLVMBuildICmp(self.builder, if (unsigned) c.LLVMIntUGT else c.LLVMIntSGT, left_value, right_value, "gt"),
            .less_than_or_equal => if (float) c.LLVMBuildFCmp(self.builder, c.LLVMRealOLE, left_value, right_value, "le") else c.LLVMBuildICmp(self.builder, if (unsigned) c.LLVMIntULE else c.LLVMIntSLE, left_value, right_value, "le"),
            .greater_than_or_equal => if (float) c.LLVMBuildFCmp(self.builder, c.LLVMRealOGE, left_value, right_value, "ge") else c.LLVMBuildICmp(self.builder, if (unsigned) c.LLVMIntUGE else c.LLVMIntSGE, left_value, right_value, "ge"),
        };
        return .{ .value_ref = value, .type_ref = c.LLVMInt1Type(), .ty = null };
    }

    fn logical(self: *CodeGenerator, operation: anytype) !TypedValue {
        const left = (try self.visitNode(operation.left)) orelse return CodegenError.ValueNotFound;
        const start = c.LLVMGetInsertBlock(self.builder);
        const function = c.LLVMGetBasicBlockParent(start);
        const rhs_block = c.LLVMAppendBasicBlock(function, "logic.rhs");
        const merge = c.LLVMAppendBasicBlock(function, "logic.merge");
        const short = c.LLVMConstInt(c.LLVMInt1Type(), if (operation.operator == .and_) 0 else 1, 0);
        if (operation.operator == .and_) _ = c.LLVMBuildCondBr(self.builder, left.value_ref, rhs_block, merge) else _ = c.LLVMBuildCondBr(self.builder, left.value_ref, merge, rhs_block);
        c.LLVMPositionBuilderAtEnd(self.builder, rhs_block);
        const right = (try self.visitNode(operation.right)) orelse return CodegenError.ValueNotFound;
        _ = c.LLVMBuildBr(self.builder, merge);
        const rhs_end = c.LLVMGetInsertBlock(self.builder);
        c.LLVMPositionBuilderAtEnd(self.builder, merge);
        const phi = c.LLVMBuildPhi(self.builder, c.LLVMInt1Type(), "logic");
        var values = [_]llvm.c.LLVMValueRef{ short, right.value_ref };
        var blocks = [_]llvm.c.LLVMBasicBlockRef{ start, rhs_end };
        c.LLVMAddIncoming(phi, &values, &blocks, 2);
        return .{ .value_ref = phi, .type_ref = c.LLVMInt1Type(), .ty = null };
    }

    fn genIf(self: *CodeGenerator, statement: anytype) !void {
        const condition = (try self.visitNode(statement.condition)) orelse return CodegenError.ValueNotFound;
        const current = c.LLVMGetInsertBlock(self.builder);
        const function = c.LLVMGetBasicBlockParent(current);
        const then_block = c.LLVMAppendBasicBlock(function, "then");
        const merge = c.LLVMAppendBasicBlock(function, "ifend");
        const else_block = if (statement.else_block != null) c.LLVMAppendBasicBlock(function, "else") else null;
        _ = c.LLVMBuildCondBr(self.builder, condition.value_ref, then_block, else_block orelse merge);
        c.LLVMPositionBuilderAtEnd(self.builder, then_block);
        _ = try self.genBlock(statement.then_block);
        if (c.LLVMGetBasicBlockTerminator(c.LLVMGetInsertBlock(self.builder)) == null) _ = c.LLVMBuildBr(self.builder, merge);
        if (statement.else_block) |child| {
            c.LLVMPositionBuilderAtEnd(self.builder, else_block.?);
            _ = try self.genBlock(child);
            if (c.LLVMGetBasicBlockTerminator(c.LLVMGetInsertBlock(self.builder)) == null) _ = c.LLVMBuildBr(self.builder, merge);
        }
        c.LLVMPositionBuilderAtEnd(self.builder, merge);
    }

    fn genWhile(self: *CodeGenerator, statement: anytype) !void {
        const current = c.LLVMGetInsertBlock(self.builder);
        const function = c.LLVMGetBasicBlockParent(current);
        const condition_block = c.LLVMAppendBasicBlock(function, "while.cond");
        const body_block = c.LLVMAppendBasicBlock(function, "while.body");
        const end_block = c.LLVMAppendBasicBlock(function, "while.end");
        _ = c.LLVMBuildBr(self.builder, condition_block);
        c.LLVMPositionBuilderAtEnd(self.builder, condition_block);
        const condition = (try self.visitNode(statement.condition)) orelse return CodegenError.ValueNotFound;
        _ = c.LLVMBuildCondBr(self.builder, condition.value_ref, body_block, end_block);
        c.LLVMPositionBuilderAtEnd(self.builder, body_block);
        try self.loop_stack.append(.{ .break_block = end_block, .continue_block = condition_block });
        defer _ = self.loop_stack.pop();
        _ = try self.genBlock(statement.body);
        if (c.LLVMGetBasicBlockTerminator(c.LLVMGetInsertBlock(self.builder)) == null) _ = c.LLVMBuildBr(self.builder, condition_block);
        c.LLVMPositionBuilderAtEnd(self.builder, end_block);
    }

    fn genFor(self: *CodeGenerator, statement: anytype) !void {
        if (statement.init) |initialization| _ = try self.visitNode(initialization);
        const current = c.LLVMGetInsertBlock(self.builder);
        const function = c.LLVMGetBasicBlockParent(current);
        const condition_block = c.LLVMAppendBasicBlock(function, "for.cond");
        const body_block = c.LLVMAppendBasicBlock(function, "for.body");
        const increment_block = c.LLVMAppendBasicBlock(function, "for.increment");
        const end_block = c.LLVMAppendBasicBlock(function, "for.end");
        _ = c.LLVMBuildBr(self.builder, condition_block);
        c.LLVMPositionBuilderAtEnd(self.builder, condition_block);
        const condition = (try self.visitNode(statement.condition)) orelse return CodegenError.ValueNotFound;
        _ = c.LLVMBuildCondBr(self.builder, condition.value_ref, body_block, end_block);
        c.LLVMPositionBuilderAtEnd(self.builder, body_block);
        try self.loop_stack.append(.{ .break_block = end_block, .continue_block = increment_block });
        defer _ = self.loop_stack.pop();
        _ = try self.genBlock(statement.body);
        if (c.LLVMGetBasicBlockTerminator(c.LLVMGetInsertBlock(self.builder)) == null) _ = c.LLVMBuildBr(self.builder, increment_block);
        c.LLVMPositionBuilderAtEnd(self.builder, increment_block);
        if (statement.increment) |increment| _ = try self.visitNode(increment);
        _ = c.LLVMBuildBr(self.builder, condition_block);
        c.LLVMPositionBuilderAtEnd(self.builder, end_block);
    }

    fn genSwitch(self: *CodeGenerator, switch_id: graph_mod.GlobalSwitchId) !void {
        const sw = self.graph.switches.items[@intFromEnum(switch_id)];
        const expression = (try self.visitNode(sw.expression)) orelse return CodegenError.ValueNotFound;
        const choice_ty = self.graph.nodes.items[@intFromEnum(sw.expression)].ty orelse return CodegenError.InvalidType;
        const tag = if (self.isCEnum(choice_ty)) expression.value_ref else c.LLVMBuildExtractValue(self.builder, expression.value_ref, 0, "match.tag");
        const current = c.LLVMGetInsertBlock(self.builder);
        const function = c.LLVMGetBasicBlockParent(current);
        const end_block = c.LLVMAppendBasicBlock(function, "match.end");
        const default_block = if (sw.default_block != null) c.LLVMAppendBasicBlock(function, "match.default") else end_block;
        const instruction = c.LLVMBuildSwitch(self.builder, tag, default_block, sw.cases.len);
        const blocks = try self.allocator.alloc(c.LLVMBasicBlockRef, sw.cases.len);
        defer self.allocator.free(blocks);
        for (self.graph.switch_cases.items[sw.cases.start..][0..sw.cases.len], 0..) |case, index| {
            blocks[index] = c.LLVMAppendBasicBlock(function, "match.case");
            const runtime_tag = try self.variantTag(choice_ty, case.variant);
            c.LLVMAddCase(instruction, c.LLVMConstInt(c.LLVMInt32Type(), @bitCast(@as(i64, runtime_tag)), 1), blocks[index]);
        }
        for (self.graph.switch_cases.items[sw.cases.start..][0..sw.cases.len], 0..) |case, index| {
            c.LLVMPositionBuilderAtEnd(self.builder, blocks[index]);
            if (case.payload_binding) |binding| {
                const variant = self.graph.variants.items[@intFromEnum(case.variant)];
                const payload_ty = variant.payload_type orelse return CodegenError.InvalidType;
                const payload_index = try self.variantIndex(choice_ty, case.variant);
                const payload = switch (case.payload_mode) {
                    .borrow, .mut_borrow => blk: {
                        const choice_pointer = try self.addressablePointer(sw.expression);
                        break :blk c.LLVMBuildStructGEP2(self.builder, try self.toLLVMType(choice_ty), choice_pointer.value_ref, payload_index + 1, "match.payload.addr");
                    },
                    .value, .move => c.LLVMBuildExtractValue(self.builder, expression.value_ref, payload_index + 1, "match.payload"),
                };
                try self.allocateLocalBinding(binding, null);
                const storage = self.bindings.getPtr(binding) orelse return CodegenError.SymbolNotFound;
                const expected_type = switch (case.payload_mode) {
                    .borrow, .mut_borrow => c.LLVMPointerType(try self.toLLVMType(payload_ty), 0),
                    .value, .move => try self.toLLVMType(payload_ty),
                };
                if (storage.type_ref != expected_type) return CodegenError.InvalidType;
                _ = c.LLVMBuildStore(self.builder, payload, storage.ref);
                storage.initialized = true;
                if (storage.drop_state) |drop| self.storeDropState(drop, true);
            }
            _ = try self.genBlock(case.body);
            if (c.LLVMGetBasicBlockTerminator(c.LLVMGetInsertBlock(self.builder)) == null) _ = c.LLVMBuildBr(self.builder, end_block);
        }
        if (sw.default_block) |block| {
            c.LLVMPositionBuilderAtEnd(self.builder, default_block);
            _ = try self.genBlock(block);
            if (c.LLVMGetBasicBlockTerminator(c.LLVMGetInsertBlock(self.builder)) == null) _ = c.LLVMBuildBr(self.builder, end_block);
        }
        c.LLVMPositionBuilderAtEnd(self.builder, end_block);
    }

    fn genReturn(self: *CodeGenerator, ret: anytype) !void {
        if (ret.expression) |expression| {
            const value = (try self.visitNode(expression)) orelse return CodegenError.ValueNotFound;
            for (self.graph.node_refs.items[ret.cleanup.start..][0..ret.cleanup.len]) |cleanup| _ = try self.visitNode(cleanup);
            const return_type = self.current_return_type orelse return CodegenError.InvalidType;
            if (return_type == value.type_ref) {
                _ = c.LLVMBuildRet(self.builder, value.value_ref);
                return;
            }
            if (c.LLVMGetTypeKind(return_type) == c.LLVMStructTypeKind and c.LLVMCountStructElementTypes(return_type) == 1 and c.LLVMStructGetTypeAtIndex(return_type, 0) == value.type_ref) {
                var aggregate = c.LLVMGetUndef(return_type);
                aggregate = c.LLVMBuildInsertValue(self.builder, aggregate, value.value_ref, 0, "ret.pack");
                _ = c.LLVMBuildRet(self.builder, aggregate);
                return;
            }
            return CodegenError.InvalidType;
        }
        for (self.graph.node_refs.items[ret.cleanup.start..][0..ret.cleanup.len]) |cleanup| _ = try self.visitNode(cleanup);
        const function = self.graph.functions.items[@intFromEnum(self.current_function orelse return CodegenError.InvalidType)];
        try self.emitOutputBindings(function);
    }

    fn emitImplicitReturn(self: *CodeGenerator, function: graph_mod.Function) !void {
        try self.emitOutputBindings(function);
    }

    fn emitOutputBindings(self: *CodeGenerator, function: graph_mod.Function) !void {
        if (function.flags.is_c_abi) {
            if (function.output_bindings.len == 0) {
                _ = c.LLVMBuildRetVoid(self.builder);
            } else {
                const binding = self.graph.binding_refs.items[function.output_bindings.start];
                const storage = self.bindings.get(binding) orelse return CodegenError.SymbolNotFound;
                const value = c.LLVMBuildLoad2(self.builder, storage.type_ref, storage.ref, "return.c");
                _ = c.LLVMBuildRet(self.builder, value);
            }
            return;
        }
        const return_type = self.current_return_type orelse return CodegenError.InvalidType;
        var aggregate = c.LLVMGetUndef(return_type);
        for (self.graph.binding_refs.items[function.output_bindings.start..][0..function.output_bindings.len], 0..) |binding, index| {
            const storage = self.bindings.get(binding) orelse return CodegenError.SymbolNotFound;
            const value = c.LLVMBuildLoad2(self.builder, storage.type_ref, storage.ref, "return.field");
            aggregate = c.LLVMBuildInsertValue(self.builder, aggregate, value, @intCast(index), "return.aggregate");
        }
        _ = c.LLVMBuildRet(self.builder, aggregate);
    }

    fn genBreak(self: *CodeGenerator, source: primitives.SourceRef) !void {
        if (self.loop_stack.items.len == 0) {
            try self.report(source, "break used outside of a loop", .{});
            return CodegenError.Reported;
        }
        const loop = self.loop_stack.items[self.loop_stack.items.len - 1];
        _ = c.LLVMBuildBr(self.builder, loop.break_block);
        const function = c.LLVMGetBasicBlockParent(c.LLVMGetInsertBlock(self.builder));
        c.LLVMPositionBuilderAtEnd(self.builder, c.LLVMAppendBasicBlock(function, "after.break"));
    }

    fn genContinue(self: *CodeGenerator, source: primitives.SourceRef) !void {
        if (self.loop_stack.items.len == 0) {
            try self.report(source, "continue used outside of a loop", .{});
            return CodegenError.Reported;
        }
        const loop = self.loop_stack.items[self.loop_stack.items.len - 1];
        _ = c.LLVMBuildBr(self.builder, loop.continue_block);
        const function = c.LLVMGetBasicBlockParent(c.LLVMGetInsertBlock(self.builder));
        c.LLVMPositionBuilderAtEnd(self.builder, c.LLVMAppendBasicBlock(function, "after.continue"));
    }

    fn addressOf(self: *CodeGenerator, node_id: graph_mod.GlobalNodeId, target: graph_mod.GlobalNodeId) !TypedValue {
        var pointer = try self.addressablePointer(target);
        pointer.ty = self.graph.nodes.items[@intFromEnum(node_id)].ty;
        return pointer;
    }

    fn addressablePointer(self: *CodeGenerator, node_id: graph_mod.GlobalNodeId) anyerror!TypedValue {
        const node = self.graph.nodes.items[@intFromEnum(node_id)];
        return switch (node.content) {
            .assignment => |assignment| blk: {
                const record = self.graph.binding(assignment.binding);
                if (!record.deferred_initialization) return CodegenError.InvalidType;
                if (record.reinitialize_cleanup) |cleanup| _ = try self.visitNode(cleanup);
                _ = try self.visitNode(node_id);
                const storage = self.bindings.get(assignment.binding) orelse return CodegenError.SymbolNotFound;
                break :blk .{ .value_ref = storage.ref, .type_ref = c.LLVMPointerType(storage.type_ref, 0), .ty = node.ty };
            },
            .binding_use => |binding| blk: {
                if (self.global_bindings.contains(binding)) try self.ensureGlobalInitialized(binding);
                const storage = self.bindings.get(binding) orelse return CodegenError.SymbolNotFound;
                break :blk .{ .value_ref = storage.ref, .type_ref = c.LLVMPointerType(storage.type_ref, 0), .ty = node.ty };
            },
            .struct_field_access => |access| blk: {
                const base = try self.addressablePointer(access.value);
                const base_ty = self.graph.nodes.items[@intFromEnum(access.value)].ty orelse return CodegenError.InvalidType;
                const hit_range = types.fields(self.graph, base_ty) orelse return CodegenError.InvalidType;
                const field = self.graph.fields.items[hit_range.start + access.field_index];
                if (self.isCUnion(base_ty)) {
                    var lowerer = self.typeLowerer();
                    const pointer = try lowerer.buildUnionFieldPointer(self.builder, base.value_ref, types.effectiveFieldType(field), "union.field.addr");
                    break :blk .{ .value_ref = pointer, .type_ref = c.LLVMPointerType(try self.toLLVMType(types.effectiveFieldType(field)), 0), .ty = field.ty };
                }
                const struct_type = try self.toLLVMType(base_ty);
                const pointer = c.LLVMBuildStructGEP2(self.builder, struct_type, base.value_ref, access.field_index, "field.addr");
                break :blk .{ .value_ref = pointer, .type_ref = c.LLVMPointerType(try self.toLLVMType(types.effectiveFieldType(field)), 0), .ty = field.ty };
            },
            .choice_payload_access => |access| blk: {
                const base = try self.addressablePointer(access.value);
                const choice_ty = self.graph.nodes.items[@intFromEnum(access.value)].ty orelse return CodegenError.InvalidType;
                const index = try self.variantIndex(choice_ty, access.variant);
                const pointer = c.LLVMBuildStructGEP2(self.builder, try self.toLLVMType(choice_ty), base.value_ref, index + 1, "choice.payload.addr");
                break :blk .{ .value_ref = pointer, .type_ref = c.LLVMPointerType(try self.toLLVMType(access.payload_type), 0), .ty = access.payload_type };
            },
            .array_index => |access| blk: {
                const base = try self.addressablePointer(access.array_ptr);
                const index = (try self.visitNode(access.index)) orelse return CodegenError.ValueNotFound;
                const array_type = try self.toLLVMType(access.array_type);
                const element_type = try self.toLLVMType(access.element_type);
                const pointer = try self.arrayElementPointer(base.value_ref, array_type, index.value_ref, access.array_type);
                break :blk .{ .value_ref = pointer, .type_ref = c.LLVMPointerType(element_type, 0), .ty = access.element_type };
            },
            .dereference => |deref| (try self.visitNode(deref.pointer)) orelse return CodegenError.ValueNotFound,
            else => CodegenError.InvalidType,
        };
    }

    fn dereference(self: *CodeGenerator, deref: anytype) !TypedValue {
        const pointer = (try self.visitNode(deref.pointer)) orelse return CodegenError.ValueNotFound;
        const type_ref = try self.toLLVMType(deref.ty);
        return .{ .value_ref = c.LLVMBuildLoad2(self.builder, type_ref, pointer.value_ref, "deref"), .type_ref = type_ref, .ty = deref.ty };
    }

    fn pointerAssignment(self: *CodeGenerator, assignment: anytype) !void {
        const pointer = (try self.visitNode(assignment.pointer)) orelse return CodegenError.ValueNotFound;
        if (self.graph.nodes.items[@intFromEnum(assignment.value)].content == .type_initializer and
            self.graph.function(self.graph.nodes.items[@intFromEnum(assignment.value)].content.type_initializer.init_fn).output.len == 0)
        {
            try self.typeInitializerInto(self.graph.nodes.items[@intFromEnum(assignment.value)].content.type_initializer, pointer.value_ref);
            return;
        }
        const value = (try self.visitNode(assignment.value)) orelse return CodegenError.ValueNotFound;
        _ = c.LLVMBuildStore(self.builder, value.value_ref, pointer.value_ref);
    }

    fn explicitCast(self: *CodeGenerator, cast: anytype) !TypedValue {
        const value = (try self.visitNode(cast.value)) orelse return CodegenError.ValueNotFound;
        const source = self.graph.nodes.items[@intFromEnum(cast.value)].ty orelse return CodegenError.InvalidType;
        const target = cast.target_type;
        const target_ref = try self.toLLVMType(target);
        if (types.equal(self.graph, source, target)) {
            if (value.type_ref != target_ref) return CodegenError.InvalidType;
            return .{ .value_ref = value.value_ref, .type_ref = target_ref, .ty = target };
        }
        const source_ptr = self.isPointer(source);
        const target_ptr = self.isPointer(target);
        const source_native = types.isBuiltin(self.graph, source, .UIntNative);
        const target_native = types.isBuiltin(self.graph, target, .UIntNative);
        if (source_ptr and target_native) return .{ .value_ref = c.LLVMBuildPtrToInt(self.builder, value.value_ref, target_ref, "ptr.to.int"), .type_ref = target_ref, .ty = target };
        if (source_native and target_ptr) return .{ .value_ref = c.LLVMBuildIntToPtr(self.builder, value.value_ref, target_ref, "int.to.ptr"), .type_ref = target_ref, .ty = target };
        if (source_ptr and target_ptr) return .{ .value_ref = c.LLVMBuildBitCast(self.builder, value.value_ref, target_ref, "ptr.cast"), .type_ref = target_ref, .ty = target };
        return CodegenError.InvalidType;
    }

    fn nullableUnwrap(self: *CodeGenerator, unwrap_id: graph_mod.GlobalNullableUnwrapId) !TypedValue {
        const unwrap = self.graph.nullable_unwraps.items[@intFromEnum(unwrap_id)];
        const nullable = (try self.visitNode(unwrap.nullable_value)) orelse return CodegenError.ValueNotFound;
        const result_type = try self.toLLVMType(unwrap.result_type);
        const choice_ty = self.graph.nodes.items[@intFromEnum(unwrap.nullable_value)].ty orelse return CodegenError.InvalidType;
        const some_index = try self.variantIndex(choice_ty, unwrap.some_variant);
        const tag = c.LLVMBuildExtractValue(self.builder, nullable.value_ref, 0, "nullable.tag");
        const current = c.LLVMGetInsertBlock(self.builder);
        const function = c.LLVMGetBasicBlockParent(current);
        const some_block = c.LLVMAppendBasicBlock(function, "nullable.some");
        const none_block = c.LLVMAppendBasicBlock(function, "nullable.none");
        const merge = c.LLVMAppendBasicBlock(function, "nullable.merge");
        const runtime_tag = try self.variantTag(choice_ty, unwrap.some_variant);
        const condition = c.LLVMBuildICmp(self.builder, c.LLVMIntEQ, tag, c.LLVMConstInt(c.LLVMInt32Type(), @bitCast(@as(i64, runtime_tag)), 1), "nullable.is_some");
        _ = c.LLVMBuildCondBr(self.builder, condition, some_block, none_block);
        c.LLVMPositionBuilderAtEnd(self.builder, some_block);
        const payload = c.LLVMBuildExtractValue(self.builder, nullable.value_ref, some_index + 1, "nullable.payload");
        const some_value = c.LLVMBuildExtractValue(self.builder, payload, unwrap.some_value_field_index, "nullable.value");
        _ = c.LLVMBuildBr(self.builder, merge);
        const some_end = c.LLVMGetInsertBlock(self.builder);
        c.LLVMPositionBuilderAtEnd(self.builder, none_block);
        const fallback = (try self.visitNode(unwrap.fallback_value)) orelse return CodegenError.ValueNotFound;
        _ = c.LLVMBuildBr(self.builder, merge);
        const none_end = c.LLVMGetInsertBlock(self.builder);
        c.LLVMPositionBuilderAtEnd(self.builder, merge);
        const phi = c.LLVMBuildPhi(self.builder, result_type, "nullable.unwrap");
        var values = [_]llvm.c.LLVMValueRef{ some_value, fallback.value_ref };
        var blocks = [_]llvm.c.LLVMBasicBlockRef{ some_end, none_end };
        c.LLVMAddIncoming(phi, &values, &blocks, 2);
        return .{ .value_ref = phi, .type_ref = result_type, .ty = unwrap.result_type };
    }

    // Propagation is a control-flow operation: evaluate the errable once,
    // return its error variant through the current function after cleanup, and
    // continue with the unwrapped success payload. Trace enrichment is kept in
    // a separate helper so the indexed graph semantics do not depend on a
    // particular error payload layout.
    fn genErrorPropagation(self: *CodeGenerator, propagation: anytype, context: ?graph_mod.GlobalNodeId, source: primitives.SourceRef) !TypedValue {
        const value = (try self.visitNode(propagation.errable_value)) orelse return CodegenError.ValueNotFound;
        const source_errable_type = self.graph.node(propagation.errable_value).ty orelse return CodegenError.InvalidType;
        const tag = c.LLVMBuildExtractValue(self.builder, value.value_ref, 0, "error.tag");
        const source_error_tag = c.LLVMConstInt(c.LLVMInt32Type(), @intCast(try self.variantTag(source_errable_type, propagation.error_variant)), 0);
        const propagated_error_tag = c.LLVMConstInt(c.LLVMInt32Type(), @intCast(try self.variantTag(propagation.propagated_errable_type, propagation.propagated_error_variant)), 0);
        const current = c.LLVMGetInsertBlock(self.builder) orelse return CodegenError.InvalidType;
        const function = c.LLVMGetBasicBlockParent(current);
        const error_block = c.LLVMAppendBasicBlock(function, "error.propagate");
        const ok_block = c.LLVMAppendBasicBlock(function, "error.ok");
        _ = c.LLVMBuildCondBr(self.builder, c.LLVMBuildICmp(self.builder, c.LLVMIntEQ, tag, source_error_tag, "error.is_error"), error_block, ok_block);

        c.LLVMPositionBuilderAtEnd(self.builder, error_block);
        var propagated = c.LLVMGetUndef(try self.toLLVMType(propagation.propagated_errable_type));
        const source_error_index = try self.variantIndex(source_errable_type, propagation.error_variant);
        const propagated_error_index = try self.variantIndex(propagation.propagated_errable_type, propagation.propagated_error_variant);
        const payload = c.LLVMBuildExtractValue(self.builder, value.value_ref, source_error_index + 1, "error.payload");
        const traced_payload = try self.appendErrorTrace(payload, propagation.error_payload_type, source, context, null);
        const converted_payload = try self.coerceErrorPayload(traced_payload, propagation.error_payload_type, propagation.propagated_error_payload_type);
        propagated = c.LLVMBuildInsertValue(self.builder, propagated, propagated_error_tag, 0, "error.return.tag");
        propagated = c.LLVMBuildInsertValue(self.builder, propagated, converted_payload, propagated_error_index + 1, "error.return.payload");
        for (self.graph.node_refs.items[propagation.cleanup_nodes.start..][0..propagation.cleanup_nodes.len]) |cleanup|
            _ = try self.visitNode(cleanup);
        const return_type = self.current_return_type orelse return CodegenError.InvalidType;
        var return_value = c.LLVMGetUndef(return_type);
        return_value = c.LLVMBuildInsertValue(self.builder, return_value, propagated, 0, "error.return");
        _ = c.LLVMBuildRet(self.builder, return_value);

        c.LLVMPositionBuilderAtEnd(self.builder, ok_block);
        const ok_payload = c.LLVMBuildExtractValue(self.builder, value.value_ref, (try self.variantIndex(source_errable_type, propagation.ok_variant)) + 1, "error.ok.payload");
        const result_ty = if (propagation.ok_value_field_index) |index| blk: {
            const fields = types.fields(self.graph, propagation.ok_payload_type) orelse return CodegenError.InvalidType;
            if (index >= fields.len) return CodegenError.InvalidType;
            break :blk self.graph.fields.items[fields.start + index].ty;
        } else propagation.ok_payload_type;
        const result = if (propagation.ok_value_field_index) |index|
            c.LLVMBuildExtractValue(self.builder, ok_payload, index, "error.ok.value")
        else
            ok_payload;
        return .{ .value_ref = result, .type_ref = try self.toLLVMType(result_ty), .ty = result_ty };
    }

    fn appendErrorTrace(
        self: *CodeGenerator,
        error_value: llvm.c.LLVMValueRef,
        error_ty: graph_mod.GlobalTypeId,
        source: primitives.SourceRef,
        context_node: ?graph_mod.GlobalNodeId,
        context_pointer: ?llvm.c.LLVMValueRef,
    ) !llvm.c.LLVMValueRef {
        const trace = types.findField(self.graph, error_ty, "trace") orelse return CodegenError.InvalidType;
        const trace_value = c.LLVMBuildExtractValue(self.builder, error_value, trace.index, "error.trace");
        const context_value = if (context_node) |node| try self.visitNode(node) else null;
        const is_view = if (context_value) |value| if (value.ty) |ty| types.findField(self.graph, ty, "length") != null else false else false;
        const helper = try self.runtimeFunction(if (is_view) "_add_error_context" else "_add_error_context_text");
        const function_id = try self.coreFunctionId(if (is_view) "_add_error_context" else "_add_error_context_text");
        const function = self.graph.function(function_id);
        const location_ty = self.graph.fields.items[function.input.start + 1].ty;
        var location_value = c.LLVMGetUndef(try self.toLLVMType(location_ty));
        location_value = c.LLVMBuildInsertValue(self.builder, location_value, c.LLVMConstInt(c.LLVMInt32Type(), try self.sourceLocationId(source), 0), 0, "trace.location_value.id");
        const context = if (context_value) |value| value.value_ref else if (context_pointer) |pointer| pointer else try self.stringPointer("", "trace.empty.context");
        var input = c.LLVMGetUndef(try self.fieldsLLVMType(function.input));
        input = c.LLVMBuildInsertValue(self.builder, input, trace_value, 0, "trace.input.receiver");
        input = c.LLVMBuildInsertValue(self.builder, input, location_value, 1, "trace.input.location_value");
        input = c.LLVMBuildInsertValue(self.builder, input, context, 2, "trace.input.context");
        var args = [_]c.LLVMValueRef{input};
        _ = c.LLVMBuildCall2(self.builder, helper.type_ref, helper.ref, &args, 1, "");
        return error_value;
    }

    fn isCoreFunction(self: *CodeGenerator, id: graph_mod.GlobalFunctionId, name: []const u8) bool {
        const declaration = self.graph.function(id).declaration;
        const owner = self.graph.moduleForDeclaration(declaration) orelse return false;
        return self.graph.modules.items[@intFromEnum(owner)].is_bundled_core and
            std.mem.eql(u8, self.graph.text(self.graph.declaration(declaration).name), name);
    }

    fn coreFunctionId(self: *CodeGenerator, name: []const u8) !graph_mod.GlobalFunctionId {
        for (self.graph.functions.items, 0..) |_, raw| {
            const id: graph_mod.GlobalFunctionId = @enumFromInt(@as(u32, @intCast(raw)));
            if (self.isCoreFunction(id, name)) return id;
        }
        return CodegenError.SymbolNotFound;
    }

    fn sourceLocationId(self: *CodeGenerator, source: primitives.SourceRef) !u32 {
        for (self.trace_locations.items, 0..) |previous, index| {
            if (previous.file_index == source.file_index and previous.offset == source.offset) return @intCast(index);
        }
        const id: u32 = @intCast(self.trace_locations.items.len);
        try self.trace_locations.append(self.allocator, source);
        return id;
    }

    // Metadata is emitted once per location_value and resolved only when reporting.
    // Source IDs carry no references into a tracer's resettable storage.
    fn generateTraceLocationResolver(self: *CodeGenerator, id: graph_mod.GlobalFunctionId) !void {
        const symbol = self.functions.get(id) orelse return;
        const function = self.graph.function(id);
        const location_ty = self.graph.fields.items[function.output.start].ty;
        const fields = types.fields(self.graph, location_ty) orelse return CodegenError.InvalidType;
        const entry = c.LLVMAppendBasicBlock(symbol.ref, "entry");
        c.LLVMPositionBuilderAtEnd(self.builder, entry);
        const input = c.LLVMGetParam(symbol.ref, 0);
        const location_value = c.LLVMBuildExtractValue(self.builder, c.LLVMBuildExtractValue(self.builder, input, 0, "location_value"), 0, "location_value.id");
        const invalid = c.LLVMAppendBasicBlock(symbol.ref, "location_value.invalid");
        const instruction = c.LLVMBuildSwitch(self.builder, location_value, invalid, @intCast(self.trace_locations.items.len));
        for (self.trace_locations.items, 0..) |source, index| {
            const block = c.LLVMAppendBasicBlock(symbol.ref, "location_value.metadata");
            c.LLVMAddCase(instruction, c.LLVMConstInt(c.LLVMInt32Type(), index, 0), block);
            c.LLVMPositionBuilderAtEnd(self.builder, block);
            const metadata = try self.traceMetadata(source);
            var result = c.LLVMGetUndef(try self.toLLVMType(location_ty));
            for (self.graph.fields.items[fields.start..][0..fields.len], 0..) |field, field_index| {
                const name = self.graph.text(field.name);
                const value = if (std.mem.eql(u8, name, "source_file")) metadata.source_file else if (std.mem.eql(u8, name, "source_line")) metadata.source_line else c.LLVMConstInt(try self.toLLVMType(field.ty), if (std.mem.eql(u8, name, "line")) metadata.line else metadata.column, 0);
                result = c.LLVMBuildInsertValue(self.builder, result, value, @intCast(field_index), "location_value.field");
            }
            var output = c.LLVMGetUndef(symbol.return_type);
            output = c.LLVMBuildInsertValue(self.builder, output, result, 0, "location_value.output");
            _ = c.LLVMBuildRet(self.builder, output);
        }
        c.LLVMPositionBuilderAtEnd(self.builder, invalid);
        const trap_type = c.LLVMFunctionType(c.LLVMVoidType(), null, 0, 0);
        const trap = c.LLVMGetNamedFunction(self.module, "llvm.trap") orelse c.LLVMAddFunction(self.module, "llvm.trap", trap_type);
        _ = c.LLVMBuildCall2(self.builder, trap_type, trap, null, 0, "");
        _ = c.LLVMBuildUnreachable(self.builder);
    }

    const TraceMetadata = struct { source_file: c.LLVMValueRef, source_line: c.LLVMValueRef, line: u32, column: u32 };

    fn traceMetadata(self: *CodeGenerator, source: primitives.SourceRef) !TraceMetadata {
        if (source.file_index >= self.graph.files.items.len) return CodegenError.InvalidType;
        const graph_file = self.graph.files.items[source.file_index];
        const name = self.graph.text(graph_file.path);
        const module_dir = self.graph.text(self.graph.modules.items[@intFromEnum(graph_file.module)].dir);
        const file_id = blk: {
            for (self.diags.source_files, 0..) |file, index| {
                if (std.mem.eql(u8, std.fs.path.basename(file.path), name) and
                    std.mem.eql(u8, std.fs.path.dirname(file.path) orelse ".", module_dir)) break :blk self.diags.source_db.fileId(index);
            }
            return CodegenError.InvalidType;
        };
        const position = self.diags.source_db.lineColumn(file_id, source.offset);
        const file = self.diags.source_db.get(file_id);
        const remaining = file.source[file.line_starts[position.line - 1]..];
        const line_end = std.mem.indexOfScalar(u8, remaining, '\n') orelse remaining.len;
        const path_z = try self.dupZ(self.diags.source_db.path(file_id));
        defer self.allocator.free(path_z);
        const line_z = try self.dupZ(remaining[0..line_end]);
        defer self.allocator.free(line_z);
        return .{
            .source_file = c.LLVMBuildGlobalStringPtr(self.builder, path_z.ptr, "trace.source_file"),
            .source_line = c.LLVMBuildGlobalStringPtr(self.builder, line_z.ptr, "trace.source_line"),
            .line = position.line,
            .column = position.column,
        };
    }

    fn runtimeFunction(self: *CodeGenerator, name: []const u8) !FunctionSymbol {
        return self.functions.get(try self.coreFunctionId(name)) orelse return CodegenError.SymbolNotFound;
    }

    fn genTestingExpectError(self: *CodeGenerator, expect: graph_mod.TestingExpectError, source: primitives.SourceRef) !TypedValue {
        const actual = (try self.visitNode(expect.actual_result)) orelse return CodegenError.ValueNotFound;
        const actual_ty = self.graph.node(expect.actual_result).ty orelse return CodegenError.InvalidType;
        const actual_tag = c.LLVMBuildExtractValue(self.builder, actual.value_ref, 0, "expect_error.actual.tag");
        const error_tag = c.LLVMConstInt(c.LLVMInt32Type(), @intCast(try self.variantTag(actual_ty, expect.actual_error_variant)), 0);
        const current = c.LLVMGetInsertBlock(self.builder) orelse return CodegenError.InvalidType;
        const function = c.LLVMGetBasicBlockParent(current);
        const unexpected_ok_block = c.LLVMAppendBasicBlock(function, "expect_error.unexpected_ok");
        const actual_error_block = c.LLVMAppendBasicBlock(function, "expect_error.actual_error");
        const mismatch_block = c.LLVMAppendBasicBlock(function, "expect_error.mismatch");
        const success_block = c.LLVMAppendBasicBlock(function, "expect_error.success");
        const merge_block = c.LLVMAppendBasicBlock(function, "expect_error.merge");
        const is_error = c.LLVMBuildICmp(self.builder, c.LLVMIntEQ, actual_tag, error_tag, "expect_error.is_error");
        _ = c.LLVMBuildCondBr(self.builder, is_error, actual_error_block, unexpected_ok_block);

        c.LLVMPositionBuilderAtEnd(self.builder, unexpected_ok_block);
        const unexpected_ok_context = try self.stringPointer("expect_error failed: expression succeeded unexpectedly", "expect_error.unexpected_ok.context");
        const unexpected_ok = try self.buildTestingFailure(expect, source, unexpected_ok_context);
        _ = c.LLVMBuildBr(self.builder, merge_block);
        const unexpected_ok_end = c.LLVMGetInsertBlock(self.builder);

        c.LLVMPositionBuilderAtEnd(self.builder, actual_error_block);
        const error_index = try self.variantIndex(actual_ty, expect.actual_error_variant);
        const error_payload = c.LLVMBuildExtractValue(self.builder, actual.value_ref, error_index + 1, "expect_error.payload");
        const actual_reason = c.LLVMBuildExtractValue(self.builder, error_payload, expect.actual_reason_field_index, "expect_error.actual.reason");
        const expected_reason = (try self.visitNode(expect.expected_reason)) orelse return CodegenError.ValueNotFound;
        const actual_reason_tag = c.LLVMBuildExtractValue(self.builder, actual_reason, 0, "expect_error.actual.reason.tag");
        const expected_reason_tag = c.LLVMBuildExtractValue(self.builder, expected_reason.value_ref, 0, "expect_error.expected.reason.tag");
        const reason_matches = c.LLVMBuildICmp(self.builder, c.LLVMIntEQ, actual_reason_tag, expected_reason_tag, "expect_error.reason_matches");
        _ = c.LLVMBuildCondBr(self.builder, reason_matches, success_block, mismatch_block);

        c.LLVMPositionBuilderAtEnd(self.builder, mismatch_block);
        const mismatch_context = try self.testingMismatchContext(expect, actual_reason_tag);
        const mismatch = try self.buildTestingFailure(expect, source, mismatch_context);
        _ = c.LLVMBuildBr(self.builder, merge_block);
        const mismatch_end = c.LLVMGetInsertBlock(self.builder);

        c.LLVMPositionBuilderAtEnd(self.builder, success_block);
        const success = try self.buildErrableOk(expect.result_type, expect.result_ok_variant);
        _ = c.LLVMBuildBr(self.builder, merge_block);
        const success_end = c.LLVMGetInsertBlock(self.builder);

        c.LLVMPositionBuilderAtEnd(self.builder, merge_block);
        const result_type = try self.toLLVMType(expect.result_type);
        const phi = c.LLVMBuildPhi(self.builder, result_type, "expect_error.result");
        var values = [_]llvm.c.LLVMValueRef{ unexpected_ok, mismatch, success };
        var blocks = [_]llvm.c.LLVMBasicBlockRef{ unexpected_ok_end, mismatch_end, success_end };
        c.LLVMAddIncoming(phi, &values, &blocks, values.len);
        return .{ .value_ref = phi, .type_ref = result_type, .ty = expect.result_type };
    }

    fn callTestingFailure(self: *CodeGenerator, function_id: graph_mod.GlobalFunctionId, result_ty: graph_mod.GlobalTypeId, input_node: ?graph_mod.GlobalNodeId) !llvm.c.LLVMValueRef {
        const function = self.graph.functions.items[@intFromEnum(function_id)];
        if (function.output.len != 1) return CodegenError.InvalidType;
        const symbol = self.functions.get(function_id) orelse return CodegenError.SymbolNotFound;
        const input = if (input_node) |node| ((try self.visitNode(node)) orelse return CodegenError.ValueNotFound).value_ref else c.LLVMConstNull(try self.fieldsLLVMType(function.input));
        var arguments = [_]llvm.c.LLVMValueRef{input};
        const output = c.LLVMBuildCall2(self.builder, symbol.type_ref, symbol.ref, &arguments, 1, "expect_error.failure");
        const field = self.graph.fields.items[function.output.start];
        if (!types.equal(self.graph, types.effectiveFieldType(field), result_ty)) return CodegenError.InvalidType;
        return c.LLVMBuildExtractValue(self.builder, output, 0, "expect_error.failure.result");
    }

    fn buildTestingFailure(self: *CodeGenerator, expect: graph_mod.TestingExpectError, source: primitives.SourceRef, context: llvm.c.LLVMValueRef) !llvm.c.LLVMValueRef {
        var result = try self.callTestingFailure(expect.test_fail_function, expect.result_type, expect.test_fail_input);
        const error_variant = types.findVariant(self.graph, expect.result_type, "error") orelse return CodegenError.InvalidType;
        const payload_ty = error_variant.variant.payload_type orelse return CodegenError.InvalidType;
        const payload = c.LLVMBuildExtractValue(self.builder, result, error_variant.index + 1, "expect_error.failure.payload");
        const traced = try self.appendErrorTrace(payload, payload_ty, source, null, context);
        result = c.LLVMBuildInsertValue(self.builder, result, traced, error_variant.index + 1, "expect_error.failure.trace");
        return result;
    }

    fn testingMismatchContext(self: *CodeGenerator, expect: graph_mod.TestingExpectError, actual_tag: llvm.c.LLVMValueRef) !llvm.c.LLVMValueRef {
        const expected_name = if (expect.expected_reason_name) |name| self.graph.text(name) else return self.stringPointer("expect_error failed: error reason mismatch", "expect_error.mismatch.context");
        const reason_field = types.findField(self.graph, expect.actual_error_payload_type, "reason") orelse return CodegenError.InvalidType;
        const variants = types.variants(self.graph, reason_field.field.ty) orelse return CodegenError.InvalidType;
        var selected = try self.stringPointer("expect_error failed: error reason mismatch", "expect_error.mismatch.default");
        for (0..variants.len) |offset| {
            const variant_id: graph_mod.GlobalVariantId = @enumFromInt(variants.start + @as(u32, @intCast(offset)));
            const variant = self.graph.variants.items[@intFromEnum(variant_id)];
            const message = try std.fmt.allocPrint(self.allocator, "expect_error failed: expected ..{s} but got ..{s}", .{ expected_name, self.graph.text(variant.name) });
            defer self.allocator.free(message);
            const pointer = try self.stringPointer(message, "expect_error.mismatch.reason");
            const matches = c.LLVMBuildICmp(self.builder, c.LLVMIntEQ, actual_tag, c.LLVMConstInt(c.LLVMInt32Type(), @intCast(try self.variantTag(reason_field.field.ty, variant_id)), 0), "expect_error.mismatch.tag");
            selected = c.LLVMBuildSelect(self.builder, matches, pointer, selected, "expect_error.mismatch.select");
        }
        return selected;
    }

    fn stringPointer(self: *CodeGenerator, value: []const u8, name: [*:0]const u8) !llvm.c.LLVMValueRef {
        const bytes = try self.dupZ(value);
        defer self.allocator.free(bytes);
        return c.LLVMBuildGlobalStringPtr(self.builder, bytes.ptr, name);
    }

    fn buildErrableOk(self: *CodeGenerator, result_ty: graph_mod.GlobalTypeId, ok_variant: graph_mod.GlobalVariantId) !llvm.c.LLVMValueRef {
        const result_type = try self.toLLVMType(result_ty);
        const variant = self.graph.variants.items[@intFromEnum(ok_variant)];
        const payload_ty = variant.payload_type orelse return CodegenError.InvalidType;
        const index = try self.variantIndex(result_ty, ok_variant);
        var result = c.LLVMGetUndef(result_type);
        result = c.LLVMBuildInsertValue(self.builder, result, c.LLVMConstInt(c.LLVMInt32Type(), @intCast(try self.variantTag(result_ty, ok_variant)), 0), 0, "expect_error.ok.tag");
        result = c.LLVMBuildInsertValue(self.builder, result, c.LLVMConstNull(try self.toLLVMType(payload_ty)), index + 1, "expect_error.ok.payload");
        return result;
    }

    fn coerceErrorPayload(self: *CodeGenerator, value: llvm.c.LLVMValueRef, source_ty: graph_mod.GlobalTypeId, target_ty: graph_mod.GlobalTypeId) !llvm.c.LLVMValueRef {
        if (types.equal(self.graph, source_ty, target_ty)) return value;
        const source_reason = types.findField(self.graph, source_ty, "reason") orelse return CodegenError.InvalidType;
        const source_trace = types.findField(self.graph, source_ty, "trace") orelse return CodegenError.InvalidType;
        const target_reason = types.findField(self.graph, target_ty, "reason") orelse return CodegenError.InvalidType;
        const target_trace = types.findField(self.graph, target_ty, "trace") orelse return CodegenError.InvalidType;
        const reason = c.LLVMBuildExtractValue(self.builder, value, source_reason.index, "error.reason");
        const trace = c.LLVMBuildExtractValue(self.builder, value, source_trace.index, "error.trace");
        const converted_reason = try self.coerceReasonChoice(reason, source_reason.field.ty, target_reason.field.ty);
        var result = c.LLVMGetUndef(try self.toLLVMType(target_ty));
        result = c.LLVMBuildInsertValue(self.builder, result, converted_reason, target_reason.index, "error.reason.converted");
        result = c.LLVMBuildInsertValue(self.builder, result, trace, target_trace.index, "error.trace.converted");
        return result;
    }

    fn coerceReasonChoice(self: *CodeGenerator, value: llvm.c.LLVMValueRef, source_ty: graph_mod.GlobalTypeId, target_ty: graph_mod.GlobalTypeId) !llvm.c.LLVMValueRef {
        if (types.equal(self.graph, source_ty, target_ty)) return value;
        const source_variants = types.variants(self.graph, source_ty) orelse return CodegenError.InvalidType;
        const source_tag = c.LLVMBuildExtractValue(self.builder, value, 0, "error.reason.tag");
        var mapped = c.LLVMConstInt(c.LLVMInt32Type(), 0, 0);
        for (0..source_variants.len) |offset| {
            const variant_id: graph_mod.GlobalVariantId = @enumFromInt(source_variants.start + @as(u32, @intCast(offset)));
            const variant = self.graph.variants.items[@intFromEnum(variant_id)];
            if (variant.payload_type != null) return CodegenError.InvalidType;
            const target = types.findVariant(self.graph, target_ty, self.graph.text(variant.name)) orelse return CodegenError.InvalidType;
            const condition = c.LLVMBuildICmp(self.builder, c.LLVMIntEQ, source_tag, c.LLVMConstInt(c.LLVMInt32Type(), @intCast(try self.variantTag(source_ty, variant_id)), 0), "error.reason.matches");
            mapped = c.LLVMBuildSelect(self.builder, condition, c.LLVMConstInt(c.LLVMInt32Type(), @intCast(try self.variantTag(target_ty, target.id)), 0), mapped, "error.reason.remap");
        }
        const result = c.LLVMGetUndef(try self.toLLVMType(target_ty));
        return c.LLVMBuildInsertValue(self.builder, result, mapped, 0, "error.reason.converted");
    }

    fn genVirtualize(self: *CodeGenerator, virtualize_id: graph_mod.GlobalVirtualizeId) !TypedValue {
        const virtualize = self.graph.virtualizes.items[@intFromEnum(virtualize_id)];
        const concrete_ptr = (try self.visitNode(virtualize.value)) orelse return CodegenError.ValueNotFound;
        const vtable_ptr = try self.virtualTable(virtualize.methods);

        const virtual_type = try self.toLLVMType(virtualize.virtual_type);
        var value = c.LLVMGetUndef(virtual_type);
        value = c.LLVMBuildInsertValue(self.builder, value, concrete_ptr.value_ref, 0, "virtual.data");
        value = c.LLVMBuildInsertValue(self.builder, value, vtable_ptr, 1, "virtual.vtable");
        return .{ .value_ref = value, .type_ref = virtual_type, .ty = virtualize.virtual_type };
    }

    fn virtualTable(self: *CodeGenerator, methods_range: primitives.Range(graph_mod.GlobalFunctionId)) CodegenError!c.LLVMValueRef {
        const ptr_type = c.LLVMPointerType(c.LLVMInt8Type(), 0);

        var vtable_ptr = c.LLVMConstNull(ptr_type);
        const methods = self.graph.function_refs.items[methods_range.start..][0..methods_range.len];
        if (methods.len != 0) {
            const table_type = c.LLVMArrayType2(ptr_type, methods.len);
            const table_name = try std.fmt.allocPrint(self.allocator, "argi.vtable.{d}", .{self.virtual_table_counter});
            defer self.allocator.free(table_name);
            const table_name_z = try self.dupZ(table_name);
            defer self.allocator.free(table_name_z);
            self.virtual_table_counter += 1;

            const table_global = c.LLVMAddGlobal(self.module, table_type, table_name_z.ptr);
            c.LLVMSetLinkage(table_global, c.LLVMPrivateLinkage);
            c.LLVMSetGlobalConstant(table_global, 1);
            c.LLVMSetUnnamedAddress(table_global, c.LLVMGlobalUnnamedAddr);

            const method_values = try self.allocator.alloc(llvm.c.LLVMValueRef, methods.len);
            defer self.allocator.free(method_values);
            for (methods, 0..) |method, index| {
                const symbol = self.functions.get(method) orelse return CodegenError.SymbolNotFound;
                method_values[index] = symbol.ref;
            }
            c.LLVMSetInitializer(table_global, c.LLVMConstArray2(ptr_type, method_values.ptr, methods.len));
            vtable_ptr = table_global;
        }

        return vtable_ptr;
    }

    fn genVirtualCall(self: *CodeGenerator, call_id: graph_mod.GlobalVirtualCallId) !?TypedValue {
        const call = self.graph.virtual_calls.items[@intFromEnum(call_id)];
        const handle_ptr = (try self.visitNode(call.handle)) orelse return CodegenError.ValueNotFound;
        const handle_ty = self.graph.nodes.items[@intFromEnum(call.handle)].ty orelse return CodegenError.InvalidType;
        const virtual_ty = switch (self.graph.types.items[@intFromEnum(handle_ty)]) {
            .pointer => |pointer| pointer.child,
            else => return CodegenError.InvalidType,
        };
        const virtual_type = try self.toLLVMType(virtual_ty);
        const virtual_value = c.LLVMBuildLoad2(self.builder, virtual_type, handle_ptr.value_ref, "virtual.handle");
        const concrete_ptr = c.LLVMBuildExtractValue(self.builder, virtual_value, 0, "virtual.data");
        const vtable_ptr = c.LLVMBuildExtractValue(self.builder, virtual_value, 1, "virtual.vtable");

        const ptr_type = c.LLVMPointerType(c.LLVMInt8Type(), 0);
        var method_indices = [_]llvm.c.LLVMValueRef{c.LLVMConstInt(try self.nativeUIntType(), call.method_index, 0)};
        const method_ptr = c.LLVMBuildInBoundsGEP2(self.builder, ptr_type, vtable_ptr, &method_indices, 1, "virtual.method.ptr");
        const method = c.LLVMBuildLoad2(self.builder, ptr_type, method_ptr, "virtual.method");

        const input_node = self.graph.nodes.items[@intFromEnum(call.input)];
        const literal = switch (input_node.content) {
            .struct_value_literal => |value| value,
            else => return CodegenError.InvalidType,
        };
        const fields = self.graph.value_fields.items[literal.fields.start..][0..literal.fields.len];
        // The abstract receiver has no standalone runtime layout. The vtable
        // ABI replaces it with the concrete data pointer; LLVM opaque pointers
        // give every implementation the same slot type.
        const semantic_input = types.fields(self.graph, call.input_type) orelse return CodegenError.InvalidType;
        if (semantic_input.len != fields.len) return CodegenError.InvalidType;
        const abi_fields = try self.allocator.alloc(llvm.c.LLVMTypeRef, fields.len);
        defer self.allocator.free(abi_fields);
        for (0..fields.len) |index| {
            abi_fields[index] = if (index == call.self_input_index)
                c.LLVMPointerType(c.LLVMInt8Type(), 0)
            else
                try self.toLLVMType(types.effectiveFieldType(self.graph.fields.items[semantic_input.start + @as(u32, @intCast(index))]));
        }
        const input_type = c.LLVMStructType(if (abi_fields.len == 0) null else abi_fields.ptr, @intCast(abi_fields.len), 0);
        var patched_input = c.LLVMGetUndef(input_type);
        for (fields, 0..) |field, index| {
            const argument = if (index == call.self_input_index)
                concrete_ptr
            else
                ((try self.visitNode(field.value)) orelse return CodegenError.ValueNotFound).value_ref;
            patched_input = c.LLVMBuildInsertValue(self.builder, patched_input, argument, @intCast(index), "virtual.input");
        }

        const output_type = try self.toLLVMType(call.output_type);
        var parameter_types = [_]llvm.c.LLVMTypeRef{input_type};
        const fn_type = c.LLVMFunctionType(output_type, &parameter_types, 1, 0);
        var arguments = [_]llvm.c.LLVMValueRef{patched_input};
        const result = c.LLVMBuildCall2(self.builder, fn_type, method, &arguments, 1, "virtual.call");

        const output_fields = types.fields(self.graph, call.output_type) orelse return CodegenError.InvalidType;
        if (output_fields.len == 0) return null;
        if (output_fields.len == 1) {
            const field = self.graph.fields.items[output_fields.start];
            const field_ty = types.effectiveFieldType(field);
            return .{
                .value_ref = c.LLVMBuildExtractValue(self.builder, result, 0, "virtual.call.out"),
                .type_ref = try self.toLLVMType(field_ty),
                .ty = field_ty,
            };
        }
        return .{ .value_ref = result, .type_ref = output_type, .ty = call.output_type };
    }

    fn genFunctionCall(self: *CodeGenerator, call: anytype, source: primitives.SourceRef) !?TypedValue {
        if (self.isCoreFunction(call.callee, "error_location_id")) {
            const function = self.graph.function(call.callee);
            const ty = self.graph.fields.items[function.output.start].ty;
            const type_ref = try self.toLLVMType(ty);
            var value = c.LLVMGetUndef(type_ref);
            const owner = self.graph.files.items[source.file_index].module;
            const call_source = if (self.graph.modules.items[@intFromEnum(owner)].is_bundled_core) self.default_location_source orelse source else source;
            value = c.LLVMBuildInsertValue(self.builder, value, c.LLVMConstInt(c.LLVMInt32Type(), try self.sourceLocationId(call_source), 0), 0, "trace.location.id");
            return .{ .value_ref = value, .type_ref = type_ref, .ty = ty };
        }
        const callee = self.graph.functions.items[@intFromEnum(call.callee)];
        if (callee.safety_primitive == .relocate) {
            const result = try self.opaqueRelocate(call.input);
            self.markRelocationDropState(call.input);
            return result;
        }
        if (callee.safety_primitive == .trusted_opaque_move or callee.safety_primitive == .trusted_opaque_move_in) return self.opaqueStore(call.input);
        if (callee.safety_primitive == .trusted_opaque_move_out) return self.opaqueTake(call.input);
        if (callee.safety_primitive == .trusted_opaque_relocate) return self.opaqueRelocate(call.input);
        if (callee.safety_primitive == .trusted_opaque_drop) return self.opaqueDrop(call.input, callee);
        const symbol = self.functions.get(call.callee) orelse return CodegenError.SymbolNotFound;
        const previous_source = self.default_location_source;
        self.default_location_source = source;
        defer self.default_location_source = previous_source;
        const input = (try self.visitNode(call.input)) orelse return CodegenError.ValueNotFound;

        if (!symbol.is_c_abi) {
            var args = [_]llvm.c.LLVMValueRef{input.value_ref};
            const result = c.LLVMBuildCall2(self.builder, symbol.type_ref, symbol.ref, &args, 1, "call");
            try self.markCallDropState(call, result, false);
            if (callee.output.len == 0) return null;
            if (callee.output.len == 1) {
                const field = self.graph.fields.items[callee.output.start];
                return .{ .value_ref = c.LLVMBuildExtractValue(self.builder, result, 0, "call.out"), .type_ref = try self.toLLVMType(field.ty), .ty = field.ty };
            }
            return .{ .value_ref = result, .type_ref = symbol.return_type, .ty = self.graph.nodes.items[@intFromEnum(call.input)].ty };
        }

        const physical_inputs = @import("../4_semantics/global/c_abi.zig").physicalInputCount(callee);
        const total: usize = physical_inputs + @as(usize, if (symbol.uses_sret) 1 else 0);
        const args = try self.allocator.alloc(llvm.c.LLVMValueRef, total);
        defer self.allocator.free(args);
        var cursor: usize = 0;
        var sret_storage: llvm.c.LLVMValueRef = null;
        var sret_type: llvm.c.LLVMTypeRef = c.LLVMVoidType();
        if (symbol.uses_sret) {
            sret_type = try self.fieldsLLVMType(callee.output);
            sret_storage = c.LLVMBuildAlloca(self.builder, sret_type, "sret");
            args[0] = sret_storage;
            cursor = 1;
        }
        const declaration = self.graph.declarations.items[@intFromEnum(callee.declaration)];
        const name = self.graph.text(declaration.name);
        for (self.graph.fields.items[callee.input.start..][0..physical_inputs], 0..) |field, index| {
            const raw = c.LLVMBuildExtractValue(self.builder, input.value_ref, @intCast(index), "extern.arg");
            if (std.mem.eql(u8, self.externSymbolName(callee, name), "free") and physical_inputs == 1)
                args[cursor + index] = c.LLVMBuildIntToPtr(self.builder, raw, c.LLVMPointerType(c.LLVMInt8Type(), 0), "free.address")
            else
                args[cursor + index] = raw;
            _ = field;
        }
        const call_value = c.LLVMBuildCall2(self.builder, symbol.type_ref, symbol.ref, if (total == 0) null else args.ptr, @intCast(total), if (symbol.return_type == c.LLVMVoidType()) "" else "call");
        try self.markCallDropState(call, call_value, true);
        if (callee.output.len == 0) return null;
        if (callee.output.len == 1) {
            const field = self.graph.fields.items[callee.output.start];
            if (callee.safety_primitive == .raw_allocated_storage) {
                const address_type = try self.toLLVMType(field.ty);
                return .{ .value_ref = c.LLVMBuildPtrToInt(self.builder, call_value, address_type, "raw.address"), .type_ref = address_type, .ty = field.ty };
            }
            return .{ .value_ref = call_value, .type_ref = symbol.return_type, .ty = field.ty };
        }
        return .{ .value_ref = c.LLVMBuildLoad2(self.builder, sret_type, sret_storage, "sret.value"), .type_ref = sret_type, .ty = null };
    }

    fn opaqueStore(self: *CodeGenerator, input_id: graph_mod.GlobalNodeId) !?TypedValue {
        const input = switch (self.graph.nodes.items[@intFromEnum(input_id)].content) {
            .struct_value_literal => |literal| literal,
            else => return CodegenError.InvalidType,
        };
        const fields = self.graph.value_fields.items[input.fields.start..][0..input.fields.len];
        if (fields.len != 2 and fields.len != 3) return CodegenError.InvalidType;
        const destination_index: usize = if (fields.len == 3) 1 else 0;
        const source_index: usize = if (fields.len == 3) 2 else 1;
        const destination = (try self.visitNode(fields[destination_index].value)) orelse return CodegenError.ValueNotFound;
        const source = (try self.visitNode(fields[source_index].value)) orelse return CodegenError.ValueNotFound;
        _ = c.LLVMBuildStore(self.builder, source.value_ref, destination.value_ref);
        return null;
    }

    fn opaqueTake(self: *CodeGenerator, input_id: graph_mod.GlobalNodeId) !?TypedValue {
        const input = switch (self.graph.nodes.items[@intFromEnum(input_id)].content) {
            .struct_value_literal => |literal| literal,
            else => return CodegenError.InvalidType,
        };
        const fields = self.graph.value_fields.items[input.fields.start..][0..input.fields.len];
        if (fields.len != 2) return CodegenError.InvalidType;
        _ = try self.visitNode(fields[0].value);
        const slot = (try self.visitNode(fields[1].value)) orelse return CodegenError.ValueNotFound;
        const pointer_ty = self.graph.nodes.items[@intFromEnum(fields[1].value)].ty orelse return CodegenError.InvalidType;
        const child = switch (self.graph.types.items[@intFromEnum(pointer_ty)]) {
            .pointer => |pointer| pointer.child,
            else => return CodegenError.InvalidType,
        };
        const type_ref = try self.toLLVMType(child);
        return .{ .value_ref = c.LLVMBuildLoad2(self.builder, type_ref, slot.value_ref, "opaque.take"), .type_ref = type_ref, .ty = child };
    }

    fn opaqueRelocate(self: *CodeGenerator, input_id: graph_mod.GlobalNodeId) !?TypedValue {
        const input = switch (self.graph.nodes.items[@intFromEnum(input_id)].content) {
            .struct_value_literal => |literal| literal,
            else => return CodegenError.InvalidType,
        };
        const fields = self.graph.value_fields.items[input.fields.start..][0..input.fields.len];
        if (fields.len != 2) return CodegenError.InvalidType;

        const source_node = fields[0].value;
        const destination_node = fields[1].value;
        const source = (try self.visitNode(source_node)) orelse return CodegenError.ValueNotFound;
        const destination = (try self.visitNode(destination_node)) orelse return CodegenError.ValueNotFound;
        const source_pointer_ty = self.graph.nodes.items[@intFromEnum(source_node)].ty orelse return CodegenError.InvalidType;
        const destination_pointer_ty = self.graph.nodes.items[@intFromEnum(destination_node)].ty orelse return CodegenError.InvalidType;
        const source_child = switch (self.graph.semanticType(source_pointer_ty)) {
            .pointer => |pointer| pointer.child,
            else => return CodegenError.InvalidType,
        };
        const destination_child = switch (self.graph.semanticType(destination_pointer_ty)) {
            .pointer => |pointer| pointer.child,
            else => return CodegenError.InvalidType,
        };
        if (!types.equal(self.graph, source_child, destination_child)) return CodegenError.InvalidType;

        const type_ref = try self.toLLVMType(source_child);
        const value = c.LLVMBuildLoad2(self.builder, type_ref, source.value_ref, "opaque.relocate");
        _ = c.LLVMBuildStore(self.builder, value, destination.value_ref);
        return null;
    }

    fn markRelocationDropState(self: *CodeGenerator, input_id: graph_mod.GlobalNodeId) void {
        const input = switch (self.graph.nodes.items[@intFromEnum(input_id)].content) {
            .struct_value_literal => |literal| literal,
            else => return,
        };
        const fields = self.graph.value_fields.items[input.fields.start..][0..input.fields.len];
        if (fields.len != 2) return;
        if (self.dropStateForNode(fields[0].value)) |source| self.storeDropState(source, false);
        if (self.dropStateForNode(fields[1].value)) |destination| self.storeDropState(destination, true);
    }

    fn opaqueDrop(self: *CodeGenerator, input_id: graph_mod.GlobalNodeId, primitive: graph_mod.Function) !?TypedValue {
        const input = switch (self.graph.nodes.items[@intFromEnum(input_id)].content) {
            .struct_value_literal => |literal| literal,
            else => return CodegenError.InvalidType,
        };
        const slot_ty = self.graph.fields.items[primitive.input.start].ty;
        const child = switch (self.graph.semanticType(slot_ty)) {
            .pointer => |pointer| pointer.child,
            else => return CodegenError.InvalidType,
        };
        const destructor = (try types.deinitFunctionForInput(self.graph, child, primitive.input)) orelse return null;
        const self_field = self.graph.functions.items[@intFromEnum(destructor)].input;
        var self_index: u32 = 0;
        for (self.graph.fields.items[self_field.start..][0..self_field.len], 0..) |field, index| {
            if (std.mem.eql(u8, self.graph.text(field.name), "self")) {
                self_index = @intCast(index);
                break;
            }
        }
        for (self.graph.value_fields.items[input.fields.start..][0..input.fields.len]) |field| {
            if (!std.mem.eql(u8, self.graph.text(field.name), "slot")) continue;
            const slot = (try self.visitNode(field.value)) orelse return CodegenError.ValueNotFound;
            try self.callDeinit(destructor, input_id, self_index, slot.value_ref);
            return null;
        }
        return CodegenError.InvalidType;
    }

    fn typeInitializer(self: *CodeGenerator, initializer: anytype, maybe_ty: ?graph_mod.GlobalTypeId) !TypedValue {
        const ty = maybe_ty orelse return CodegenError.InvalidType;
        const function = self.graph.function(initializer.init_fn);
        if (function.input.len == 0) return CodegenError.InvalidType;
        const destination_type = self.graph.semanticType(self.graph.fields.items[function.input.start].ty);
        if (destination_type != .pointer) return CodegenError.InvalidType;
        const value_ty = destination_type.pointer.child;
        if (function.output.len != 0) return self.fallibleTypeInitializer(initializer, ty, value_ty);
        const type_ref = try self.toLLVMType(ty);
        const storage = c.LLVMBuildAlloca(self.builder, type_ref, "type.init.tmp");
        try self.typeInitializerInto(initializer, storage);
        return .{ .value_ref = c.LLVMBuildLoad2(self.builder, type_ref, storage, "type.init"), .type_ref = type_ref, .ty = ty };
    }

    fn fallibleTypeInitializer(self: *CodeGenerator, initializer: anytype, result_ty: graph_mod.GlobalTypeId, value_ty: graph_mod.GlobalTypeId) !TypedValue {
        const function = self.graph.function(initializer.init_fn);
        if (function.output.len != 1) return CodegenError.InvalidType;
        const status_ty = self.graph.fields.items[function.output.start].ty;
        const status_ok = types.findVariant(self.graph, status_ty, "ok") orelse return CodegenError.InvalidType;
        const status_error = types.findVariant(self.graph, status_ty, "error") orelse return CodegenError.InvalidType;
        const result_ok = types.findVariant(self.graph, result_ty, "ok") orelse return CodegenError.InvalidType;
        const result_error = types.findVariant(self.graph, result_ty, "error") orelse return CodegenError.InvalidType;
        if (!types.equal(self.graph, result_ok.variant.payload_type orelse return CodegenError.InvalidType, value_ty) or
            !types.equal(self.graph, status_error.variant.payload_type orelse return CodegenError.InvalidType, result_error.variant.payload_type orelse return CodegenError.InvalidType)) return CodegenError.InvalidType;

        const value_type_ref = try self.toLLVMType(value_ty);
        const result_type_ref = try self.toLLVMType(result_ty);
        const storage = c.LLVMBuildAlloca(self.builder, value_type_ref, "type.init.tmp");
        const raw_status = try self.callTypeInitializer(initializer, storage);
        const status = c.LLVMBuildExtractValue(self.builder, raw_status, 0, "type.init.status");
        const tag = c.LLVMBuildExtractValue(self.builder, status, 0, "type.init.status.tag");
        const succeeded = c.LLVMBuildICmp(self.builder, c.LLVMIntEQ, tag, c.LLVMConstInt(c.LLVMInt32Type(), @intCast(try self.variantTag(status_ty, status_ok.id)), 0), "type.init.succeeded");
        const current = c.LLVMGetInsertBlock(self.builder) orelse return CodegenError.InvalidType;
        const parent = c.LLVMGetBasicBlockParent(current);
        const ok_block = c.LLVMAppendBasicBlock(parent, "type.init.ok");
        const error_block = c.LLVMAppendBasicBlock(parent, "type.init.error");
        const merge_block = c.LLVMAppendBasicBlock(parent, "type.init.merge");
        _ = c.LLVMBuildCondBr(self.builder, succeeded, ok_block, error_block);

        c.LLVMPositionBuilderAtEnd(self.builder, ok_block);
        var ok_value = c.LLVMGetUndef(result_type_ref);
        ok_value = c.LLVMBuildInsertValue(self.builder, ok_value, c.LLVMConstInt(c.LLVMInt32Type(), @intCast(try self.variantTag(result_ty, result_ok.id)), 0), 0, "type.init.ok.tag");
        ok_value = c.LLVMBuildInsertValue(self.builder, ok_value, c.LLVMBuildLoad2(self.builder, value_type_ref, storage, "type.init.value"), result_ok.index + 1, "type.init.ok.payload");
        _ = c.LLVMBuildBr(self.builder, merge_block);
        const ok_end = c.LLVMGetInsertBlock(self.builder);

        c.LLVMPositionBuilderAtEnd(self.builder, error_block);
        var error_value = c.LLVMGetUndef(result_type_ref);
        error_value = c.LLVMBuildInsertValue(self.builder, error_value, c.LLVMConstInt(c.LLVMInt32Type(), @intCast(try self.variantTag(result_ty, result_error.id)), 0), 0, "type.init.error.tag");
        error_value = c.LLVMBuildInsertValue(self.builder, error_value, c.LLVMBuildExtractValue(self.builder, status, status_error.index + 1, "type.init.error.payload"), result_error.index + 1, "type.init.error.value");
        _ = c.LLVMBuildBr(self.builder, merge_block);
        const error_end = c.LLVMGetInsertBlock(self.builder);

        c.LLVMPositionBuilderAtEnd(self.builder, merge_block);
        const phi = c.LLVMBuildPhi(self.builder, result_type_ref, "type.init.result");
        var values = [_]llvm.c.LLVMValueRef{ ok_value, error_value };
        var blocks = [_]llvm.c.LLVMBasicBlockRef{ ok_end, error_end };
        c.LLVMAddIncoming(phi, &values, &blocks, 2);
        return .{ .value_ref = phi, .type_ref = result_type_ref, .ty = result_ty };
    }

    fn typeInitializerInto(self: *CodeGenerator, initializer: anytype, storage: llvm.c.LLVMValueRef) !void {
        _ = try self.callTypeInitializer(initializer, storage);
    }

    fn callTypeInitializer(self: *CodeGenerator, initializer: anytype, storage: llvm.c.LLVMValueRef) !llvm.c.LLVMValueRef {
        const function = self.graph.functions.items[@intFromEnum(initializer.init_fn)];
        if (function.input.len == 0) return CodegenError.InvalidType;
        const input_type = try self.fieldsLLVMType(function.input);
        var aggregate = c.LLVMGetUndef(input_type);
        aggregate = c.LLVMBuildInsertValue(self.builder, aggregate, storage, 0, "ctor.self");
        if (function.input.len > 1) {
            const args = (try self.visitNode(initializer.args)) orelse return CodegenError.ValueNotFound;
            var index: u32 = 1;
            while (index < function.input.len) : (index += 1) {
                const value = c.LLVMBuildExtractValue(self.builder, args.value_ref, index - 1, "ctor.arg");
                aggregate = c.LLVMBuildInsertValue(self.builder, aggregate, value, index, "ctor.arg.insert");
            }
        }
        const symbol = self.functions.get(initializer.init_fn) orelse return CodegenError.SymbolNotFound;
        var call_args = [_]llvm.c.LLVMValueRef{aggregate};
        return c.LLVMBuildCall2(self.builder, symbol.type_ref, symbol.ref, &call_args, 1, "type.init.call");
    }

    fn buildDropState(self: *CodeGenerator, ty: graph_mod.GlobalTypeId, entry_builder: llvm.c.LLVMBuilderRef) !*DropState {
        const state = try self.allocator.create(DropState);
        state.* = .{ .flag_ref = c.LLVMBuildAlloca(entry_builder, c.LLVMInt1Type(), "needs.deinit") };
        if (types.fields(self.graph, ty)) |range| {
            const child_states = try self.allocator.alloc(DropState, range.len);
            for (self.graph.fields.items[range.start..][0..range.len], 0..) |field, index| {
                const child = try self.buildDropState(field.ty, entry_builder);
                child_states[index] = child.*;
            }
            state.fields = child_states;
        }
        return state;
    }

    fn storeDropState(self: *CodeGenerator, state: *const DropState, enabled: bool) void {
        self.storeDropStateValue(state, c.LLVMConstInt(c.LLVMInt1Type(), if (enabled) 1 else 0, 0));
    }

    fn storeDropStateValue(self: *CodeGenerator, state: *const DropState, enabled: llvm.c.LLVMValueRef) void {
        _ = c.LLVMBuildStore(self.builder, enabled, state.flag_ref);
        for (state.fields) |*field| self.storeDropStateValue(field, enabled);
    }

    fn dropStateForNode(self: *CodeGenerator, node_id: graph_mod.GlobalNodeId) ?*DropState {
        return switch (self.graph.nodes.items[@intFromEnum(node_id)].content) {
            .binding_use => |binding| if (self.bindings.getPtr(binding)) |storage| storage.drop_state else null,
            .address_of => |child| self.dropStateForNode(child),
            .dereference => |deref| self.dropStateForNode(deref.pointer),
            .struct_field_access => |access| blk: {
                const parent = self.dropStateForNode(access.value) orelse break :blk null;
                if (access.field_index >= parent.fields.len) break :blk null;
                break :blk &parent.fields[access.field_index];
            },
            else => null,
        };
    }

    fn markCallDropState(self: *CodeGenerator, call: anytype, result: llvm.c.LLVMValueRef, is_extern: bool) !void {
        if (call.consumes_auto_deinit) |node| if (self.dropStateForNode(node)) |drop| self.storeDropState(drop, false);
        if (call.initializes_auto_deinit) |node| if (self.dropStateForNode(node)) |drop| {
            const function = self.graph.function(call.callee);
            if (initializer_contract.classify(self.graph, call.callee) == .fallible and
                function.input.len != 0 and
                std.mem.eql(u8, self.graph.text(self.graph.declaration(function.declaration).name), "init"))
            {
                const status_ty = self.graph.fields.items[function.output.start].ty;
                const ok = types.findVariant(self.graph, status_ty, "ok") orelse return CodegenError.InvalidType;
                const status = if (is_extern) result else c.LLVMBuildExtractValue(self.builder, result, 0, "init.status");
                const tag = c.LLVMBuildExtractValue(self.builder, status, 0, "init.status.tag");
                const succeeded = c.LLVMBuildICmp(self.builder, c.LLVMIntEQ, tag, c.LLVMConstInt(c.LLVMInt32Type(), @intCast(try self.variantTag(status_ty, ok.id)), 0), "init.status.ok");
                self.storeDropStateValue(drop, succeeded);
            } else self.storeDropState(drop, true);
        };
    }

    fn genAutoDeinit(self: *CodeGenerator, auto_id: graph_mod.GlobalAutoDeinitId) !void {
        const auto = self.graph.auto_deinits.items[@intFromEnum(auto_id)];
        const storage = self.bindings.get(auto.binding) orelse return;
        const drop = storage.drop_state orelse return;
        try self.genAutoDeinitStorage(auto.deinit_fn, auto.input, auto.self_field_index, auto.fields, storage.ref, storage.ty, drop);
    }

    fn genAutoDeinitStorage(
        self: *CodeGenerator,
        deinit_fn: ?graph_mod.GlobalFunctionId,
        input: ?graph_mod.GlobalNodeId,
        self_field_index: u32,
        fields: primitives.Range(graph_mod.GlobalAutoDeinitFieldId),
        storage: llvm.c.LLVMValueRef,
        ty: graph_mod.GlobalTypeId,
        drop: *DropState,
    ) !void {
        const current = c.LLVMGetInsertBlock(self.builder);
        const function = c.LLVMGetBasicBlockParent(current);
        const run = c.LLVMAppendBasicBlock(function, "deinit.run");
        const done = c.LLVMAppendBasicBlock(function, "deinit.done");
        const enabled = c.LLVMBuildLoad2(self.builder, c.LLVMInt1Type(), drop.flag_ref, "needs.deinit");
        _ = c.LLVMBuildCondBr(self.builder, enabled, run, done);
        c.LLVMPositionBuilderAtEnd(self.builder, run);
        if (deinit_fn) |callee| {
            try self.callDeinit(callee, input, self_field_index, storage);
        } else {
            const type_fields = types.fields(self.graph, ty);
            for (self.graph.auto_deinit_fields.items[fields.start..][0..fields.len]) |field| {
                const range = type_fields orelse continue;
                if (field.field_index >= range.len or field.field_index >= drop.fields.len) continue;
                const semantic_field = self.graph.fields.items[range.start + field.field_index];
                const base_type = try self.toLLVMType(ty);
                const pointer = c.LLVMBuildStructGEP2(self.builder, base_type, storage, field.field_index, "deinit.field");
                try self.genAutoDeinitStorage(field.deinit_fn, field.input, field.self_field_index, field.fields, pointer, semantic_field.ty, &drop.fields[field.field_index]);
            }
        }
        self.storeDropState(drop, false);
        if (c.LLVMGetBasicBlockTerminator(c.LLVMGetInsertBlock(self.builder)) == null) _ = c.LLVMBuildBr(self.builder, done);
        c.LLVMPositionBuilderAtEnd(self.builder, done);
    }

    fn callDeinit(self: *CodeGenerator, callee: graph_mod.GlobalFunctionId, input_override: ?graph_mod.GlobalNodeId, self_index: u32, storage: llvm.c.LLVMValueRef) !void {
        const function = self.graph.functions.items[@intFromEnum(callee)];
        const symbol = self.functions.get(callee) orelse return CodegenError.SymbolNotFound;
        const input_type = try self.fieldsLLVMType(function.input);
        var aggregate = c.LLVMGetUndef(input_type);
        for (self.graph.fields.items[function.input.start..][0..function.input.len], 0..) |field, index| {
            const value = if (index == self_index)
                storage
            else blk: {
                if (input_override) |node| {
                    if (self.graph.nodes.items[@intFromEnum(node)].content == .struct_value_literal) {
                        const literal = self.graph.nodes.items[@intFromEnum(node)].content.struct_value_literal;
                        for (self.graph.value_fields.items[literal.fields.start..][0..literal.fields.len]) |value_field| {
                            if (!std.mem.eql(u8, self.graph.text(value_field.name), self.graph.text(field.name))) continue;
                            break :blk ((try self.visitNode(value_field.value)) orelse return CodegenError.ValueNotFound).value_ref;
                        }
                    }
                }
                const default = field.default_value orelse return CodegenError.InvalidType;
                break :blk ((try self.visitNode(default)) orelse return CodegenError.ValueNotFound).value_ref;
            };
            aggregate = c.LLVMBuildInsertValue(self.builder, aggregate, value, @intCast(index), "deinit.arg");
        }
        var args = [_]llvm.c.LLVMValueRef{aggregate};
        _ = c.LLVMBuildCall2(self.builder, symbol.type_ref, symbol.ref, &args, 1, "");
    }

    fn variantIndex(self: *CodeGenerator, ty: graph_mod.GlobalTypeId, variant: graph_mod.GlobalVariantId) !u32 {
        const range = types.variants(self.graph, ty) orelse return CodegenError.InvalidType;
        const raw = @intFromEnum(variant);
        if (raw < range.start or raw >= range.start + range.len) return CodegenError.InvalidType;
        return raw - range.start;
    }

    fn variantTag(self: *CodeGenerator, ty: graph_mod.GlobalTypeId, variant: graph_mod.GlobalVariantId) !i32 {
        if (self.isCEnum(ty)) return self.graph.variants.items[@intFromEnum(variant)].value;
        return @intCast(try self.variantIndex(ty, variant));
    }

    fn isCEnum(self: *CodeGenerator, ty: graph_mod.GlobalTypeId) bool {
        return switch (self.graph.types.items[@intFromEnum(ty)]) {
            .declared => |decl| self.graph.declarations.items[@intFromEnum(decl)].choice_layout == .c_enum,
            .structural_choice => |shape| shape.layout == .c_enum,
            .generic => if (types.genericInstance(self.graph, ty)) |instance| switch (instance.shape) {
                .choice => |shape| shape.layout == .c_enum,
                else => false,
            } else false,
            else => false,
        };
    }

    fn isCUnion(self: *CodeGenerator, ty: graph_mod.GlobalTypeId) bool {
        return switch (self.graph.types.items[@intFromEnum(ty)]) {
            .declared => |decl| self.graph.declarations.items[@intFromEnum(decl)].struct_layout == .c_union,
            .structural => |shape| shape.layout == .c_union,
            .generic => if (types.genericInstance(self.graph, ty)) |instance| switch (instance.shape) {
                .structure => |shape| shape.layout == .c_union,
                else => false,
            } else false,
            else => false,
        };
    }

    fn isPointer(self: *CodeGenerator, ty: graph_mod.GlobalTypeId) bool {
        return self.graph.types.items[@intFromEnum(ty)] == .pointer;
    }

    fn isFloat(self: *CodeGenerator, ty: graph_mod.GlobalTypeId) bool {
        return switch (self.graph.types.items[@intFromEnum(ty)]) {
            .builtin => |builtin| builtin == .Float16 or builtin == .Float32 or builtin == .Float64,
            else => false,
        };
    }

    fn isUnsigned(self: *CodeGenerator, ty: graph_mod.GlobalTypeId) bool {
        return switch (self.graph.types.items[@intFromEnum(ty)]) {
            .builtin => |builtin| switch (builtin) {
                .UIntNative, .UInt8, .UInt16, .UInt32, .UInt64 => true,
                else => false,
            },
            else => false,
        };
    }

    fn isStringView(self: *CodeGenerator, ty: graph_mod.GlobalTypeId) bool {
        const range = types.fields(self.graph, ty) orelse return false;
        if (range.len != 2) return false;
        const data = self.graph.fields.items[range.start];
        const length = self.graph.fields.items[range.start + 1];
        if (!std.mem.eql(u8, self.graph.text(data.name), "data") or !std.mem.eql(u8, self.graph.text(length.name), "length")) return false;
        const pointer = switch (self.graph.types.items[@intFromEnum(data.ty)]) {
            .pointer => |value| value,
            else => return false,
        };
        return types.isBuiltin(self.graph, pointer.child, .UInt8) and types.isBuiltin(self.graph, length.ty, .UIntNative);
    }

    fn nativeUIntType(self: *CodeGenerator) !llvm.c.LLVMTypeRef {
        for (self.graph.types.items, 0..) |ty, raw| switch (ty) {
            .builtin => |builtin| if (builtin == .UIntNative) return self.toLLVMType(@enumFromInt(@as(u32, @intCast(raw)))),
            else => {},
        };
        return switch (types.pointer_size_bytes) {
            4 => c.LLVMInt32Type(),
            8 => c.LLVMInt64Type(),
            else => CodegenError.InvalidType,
        };
    }

    fn emitStringLiteralPointer(self: *CodeGenerator, text: []const u8) !llvm.c.LLVMValueRef {
        const name = try std.fmt.allocPrint(self.allocator, "argi.strlit.{d}", .{self.string_literal_counter});
        defer self.allocator.free(name);
        self.string_literal_counter += 1;
        const name_z = try self.dupZ(name);
        const constant = c.LLVMConstStringInContext(c.LLVMGetModuleContext(self.module), text.ptr, @intCast(text.len), 0);
        const global = c.LLVMAddGlobal(self.module, c.LLVMTypeOf(constant), name_z.ptr);
        c.LLVMSetLinkage(global, c.LLVMPrivateLinkage);
        c.LLVMSetGlobalConstant(global, 1);
        c.LLVMSetInitializer(global, constant);
        var indices = [_]llvm.c.LLVMValueRef{ c.LLVMConstInt(c.LLVMInt32Type(), 0, 0), c.LLVMConstInt(c.LLVMInt32Type(), 0, 0) };
        return c.LLVMConstInBoundsGEP2(c.LLVMTypeOf(constant), global, &indices, 2);
    }

    fn generateCMainWrapper(self: *CodeGenerator, main: graph_mod.GlobalFunctionId) !void {
        const symbol = self.functions.get(main) orelse return CodegenError.SymbolNotFound;
        const i32_ty = c.LLVMInt32Type();
        const i8ptr = c.LLVMPointerType(c.LLVMInt8Type(), 0);
        const argv_ty = c.LLVMPointerType(i8ptr, 0);
        var params = [_]llvm.c.LLVMTypeRef{ i32_ty, argv_ty };
        const fn_type = c.LLVMFunctionType(i32_ty, &params, 2, 0);
        const wrapper = c.LLVMAddFunction(self.module, "main", fn_type);
        const entry = c.LLVMAppendBasicBlock(wrapper, "entry");
        c.LLVMPositionBuilderAtEnd(self.builder, entry);
        try self.ensureRuntimeArgGlobals();
        try self.ensureRuntimeArgFunctions();
        _ = c.LLVMBuildStore(self.builder, c.LLVMGetParam(wrapper, 0), self.runtime_argc_global.?);
        _ = c.LLVMBuildStore(self.builder, c.LLVMGetParam(wrapper, 1), self.runtime_argv_global.?);
        const function = self.graph.functions.items[@intFromEnum(main)];
        const input_type = try self.fieldsLLVMType(function.input);
        if (function.input.len != 0) return CodegenError.InvalidType;
        const input = c.LLVMConstNull(input_type);
        var args = [_]llvm.c.LLVMValueRef{input};
        const result = c.LLVMBuildCall2(self.builder, symbol.type_ref, symbol.ref, &args, 1, "argi.main");
        const status = c.LLVMBuildExtractValue(self.builder, result, 0, "status");
        _ = c.LLVMBuildRet(self.builder, status);
    }

    fn generateCTestWrapper(self: *CodeGenerator, test_function: graph_mod.GlobalFunctionId) !void {
        const symbol = self.functions.get(test_function) orelse return CodegenError.SymbolNotFound;
        const i32_ty = c.LLVMInt32Type();
        const fn_type = c.LLVMFunctionType(i32_ty, null, 0, 0);
        const wrapper = c.LLVMAddFunction(self.module, "main", fn_type);
        const entry = c.LLVMAppendBasicBlock(wrapper, "entry");
        c.LLVMPositionBuilderAtEnd(self.builder, entry);
        try self.ensureRuntimeArgGlobals();
        try self.ensureRuntimeArgFunctions();
        const function = self.graph.functions.items[@intFromEnum(test_function)];
        const input_type = try self.fieldsLLVMType(function.input);
        if (function.input.len != 0) return CodegenError.InvalidType;
        var args = [_]llvm.c.LLVMValueRef{c.LLVMConstNull(input_type)};
        const output = c.LLVMBuildCall2(self.builder, symbol.type_ref, symbol.ref, &args, 1, "test");
        if (function.output.len != 1) return CodegenError.InvalidType;
        const result_ty = types.effectiveFieldType(self.graph.fields.items[function.output.start]);
        const error_variant = types.findVariant(self.graph, result_ty, "error") orelse return CodegenError.InvalidType;
        const error_payload_ty = error_variant.variant.payload_type orelse return CodegenError.InvalidType;
        const reason_field = types.findField(self.graph, error_payload_ty, "reason") orelse return CodegenError.InvalidType;
        const result = c.LLVMBuildExtractValue(self.builder, output, 0, "test.result");
        const tag = c.LLVMBuildExtractValue(self.builder, result, 0, "test.tag");
        const is_error = c.LLVMBuildICmp(self.builder, c.LLVMIntEQ, tag, c.LLVMConstInt(c.LLVMInt32Type(), error_variant.index, 0), "test.is_error");
        const error_block = c.LLVMAppendBasicBlock(wrapper, "test.error");
        const ok_block = c.LLVMAppendBasicBlock(wrapper, "test.ok");
        _ = c.LLVMBuildCondBr(self.builder, is_error, error_block, ok_block);
        c.LLVMPositionBuilderAtEnd(self.builder, ok_block);
        _ = c.LLVMBuildRet(self.builder, c.LLVMConstInt(i32_ty, 0, 0));
        c.LLVMPositionBuilderAtEnd(self.builder, error_block);
        const error_payload = c.LLVMBuildExtractValue(self.builder, result, error_variant.index + 1, "test.error.payload");
        const reason = c.LLVMBuildExtractValue(self.builder, error_payload, reason_field.index, "test.error.reason");
        const skipped = types.findVariant(self.graph, reason_field.field.ty, "test_skipped") orelse {
            _ = c.LLVMBuildRet(self.builder, c.LLVMConstInt(i32_ty, 1, 0));
            return;
        };
        const reason_tag = c.LLVMBuildExtractValue(self.builder, reason, 0, "test.error.reason.tag");
        const is_skipped = c.LLVMBuildICmp(self.builder, c.LLVMIntEQ, reason_tag, c.LLVMConstInt(c.LLVMInt32Type(), skipped.index, 0), "test.is_skipped");
        const exit_code = c.LLVMBuildSelect(self.builder, is_skipped, c.LLVMConstInt(i32_ty, 77, 0), c.LLVMConstInt(i32_ty, 1, 0), "test.exit");
        _ = c.LLVMBuildRet(self.builder, exit_code);
    }

    fn ensureRuntimeArgGlobals(self: *CodeGenerator) !void {
        if (self.runtime_argc_global == null) {
            self.runtime_argc_global = c.LLVMAddGlobal(self.module, c.LLVMInt32Type(), "argi.runtime.argc");
            c.LLVMSetInitializer(self.runtime_argc_global.?, c.LLVMConstInt(c.LLVMInt32Type(), 0, 0));
        }
        if (self.runtime_argv_global == null) {
            const argv_type = c.LLVMPointerType(c.LLVMPointerType(c.LLVMInt8Type(), 0), 0);
            self.runtime_argv_global = c.LLVMAddGlobal(self.module, argv_type, "argi.runtime.argv");
            c.LLVMSetInitializer(self.runtime_argv_global.?, c.LLVMConstNull(argv_type));
        }
    }

    fn ensureRuntimeArgFunctions(self: *CodeGenerator) !void {
        const insertion_block = c.LLVMGetInsertBlock(self.builder) orelse return CodegenError.InvalidType;
        const native_ty = try self.nativeUIntType();
        const fn_type = c.LLVMFunctionType(native_ty, null, 0, 0);
        const argc = c.LLVMGetNamedFunction(self.module, "argi_runtime_argc") orelse
            c.LLVMAddFunction(self.module, "argi_runtime_argc", fn_type);
        if (c.LLVMGetFirstBasicBlock(argc) == null) {
            const entry = c.LLVMAppendBasicBlock(argc, "entry");
            c.LLVMPositionBuilderAtEnd(self.builder, entry);
            const count = c.LLVMBuildLoad2(self.builder, c.LLVMInt32Type(), self.runtime_argc_global.?, "runtime.argc");
            _ = c.LLVMBuildRet(self.builder, c.LLVMBuildZExt(self.builder, count, native_ty, "runtime.argc.native"));
        }
        const argv = c.LLVMGetNamedFunction(self.module, "argi_runtime_argv") orelse
            c.LLVMAddFunction(self.module, "argi_runtime_argv", fn_type);
        if (c.LLVMGetFirstBasicBlock(argv) == null) {
            const entry = c.LLVMAppendBasicBlock(argv, "entry");
            c.LLVMPositionBuilderAtEnd(self.builder, entry);
            const argv_type = c.LLVMPointerType(c.LLVMPointerType(c.LLVMInt8Type(), 0), 0);
            const address = c.LLVMBuildLoad2(self.builder, argv_type, self.runtime_argv_global.?, "runtime.argv");
            _ = c.LLVMBuildRet(self.builder, c.LLVMBuildPtrToInt(self.builder, address, native_ty, "runtime.argv.address"));
        }
        c.LLVMPositionBuilderAtEnd(self.builder, insertion_block);
    }

    pub fn collectStats(self: *const CodeGenerator) !Stats {
        var stats = Stats{ .semantic_functions = self.graph.functions.items.len };
        var function = c.LLVMGetFirstFunction(self.module);
        while (function != null) : (function = c.LLVMGetNextFunction(function)) {
            if (c.LLVMGetFirstBasicBlock(function) == null) continue;
            stats.llvm_functions_with_body += 1;
            var block = c.LLVMGetFirstBasicBlock(function);
            while (block != null) : (block = c.LLVMGetNextBasicBlock(block)) {
                stats.basic_blocks += 1;
                var instruction = c.LLVMGetFirstInstruction(block);
                while (instruction != null) : (instruction = c.LLVMGetNextInstruction(instruction)) stats.instructions += 1;
            }
        }
        var reachable = try self.computeReachableFunctionBodies();
        defer reachable.deinit();
        stats.reachable_llvm_functions_with_body = reachable.count();
        stats.pruned_llvm_function_bodies = self.pruned_function_bodies;
        const text = c.LLVMPrintModuleToString(self.module);
        if (text != null) {
            stats.ir_bytes = std.mem.span(text).len;
            c.LLVMDisposeMessage(text);
        }
        return stats;
    }

    fn computeReachableFunctionBodies(self: *const CodeGenerator) !std.AutoHashMap(llvm.c.LLVMValueRef, void) {
        var defined = std.AutoHashMap(llvm.c.LLVMValueRef, void).init(self.allocator);
        defer defined.deinit();
        var function = c.LLVMGetFirstFunction(self.module);
        while (function != null) : (function = c.LLVMGetNextFunction(function))
            if (c.LLVMGetFirstBasicBlock(function) != null) try defined.put(function, {});

        var reachable = std.AutoHashMap(llvm.c.LLVMValueRef, void).init(self.allocator);
        errdefer reachable.deinit();
        var worklist = std.ArrayList(llvm.c.LLVMValueRef).empty;
        defer worklist.deinit(self.allocator);

        // The generated C wrapper and explicit exports are roots. Native
        // callers are outside this module's call graph. Address escapes also
        // preserve runtime dispatch, including generated virtual tables.
        for (self.graph.functions.items, 0..) |record, raw| {
            if (!record.flags.is_c_export) continue;
            const symbol = self.functions.get(@enumFromInt(@as(u32, @intCast(raw)))) orelse continue;
            if (defined.contains(symbol.ref) and !reachable.contains(symbol.ref)) {
                try reachable.put(symbol.ref, {});
                try worklist.append(self.allocator, symbol.ref);
            }
        }
        if (c.LLVMGetNamedFunction(self.module, "main")) |main_function| {
            if (defined.contains(main_function)) {
                try reachable.put(main_function, {});
                try worklist.append(self.allocator, main_function);
            }
        }
        function = c.LLVMGetFirstFunction(self.module);
        while (function != null) : (function = c.LLVMGetNextFunction(function)) {
            if (!defined.contains(function)) continue;
            var use = c.LLVMGetFirstUse(function);
            var address_taken = false;
            while (use != null) : (use = c.LLVMGetNextUse(use)) {
                const user = c.LLVMGetUser(use);
                const instruction = c.LLVMIsAInstruction(user);
                if (instruction == null or
                    c.LLVMGetInstructionOpcode(instruction) != c.LLVMCall or
                    c.LLVMGetCalledValue(instruction) != function)
                {
                    address_taken = true;
                    break;
                }
            }
            if (address_taken and !reachable.contains(function)) {
                try reachable.put(function, {});
                try worklist.append(self.allocator, function);
            }
        }

        var next: usize = 0;
        while (next < worklist.items.len) : (next += 1) {
            const caller = worklist.items[next];
            var block = c.LLVMGetFirstBasicBlock(caller);
            while (block != null) : (block = c.LLVMGetNextBasicBlock(block)) {
                var instruction = c.LLVMGetFirstInstruction(block);
                while (instruction != null) : (instruction = c.LLVMGetNextInstruction(instruction)) {
                    if (c.LLVMGetInstructionOpcode(instruction) != c.LLVMCall) continue;
                    const callee = c.LLVMGetCalledValue(instruction);
                    if (!defined.contains(callee) or reachable.contains(callee)) continue;
                    try reachable.put(callee, {});
                    try worklist.append(self.allocator, callee);
                }
            }
        }
        return reachable;
    }

    fn pruneUnreachableFunctionBodies(self: *CodeGenerator) !void {
        if (c.LLVMGetNamedFunction(self.module, "main") == null) return;
        var reachable = try self.computeReachableFunctionBodies();
        defer reachable.deinit();

        var function = c.LLVMGetFirstFunction(self.module);
        while (function != null) : (function = c.LLVMGetNextFunction(function)) {
            if (c.LLVMGetFirstBasicBlock(function) == null or reachable.contains(function)) continue;
            while (c.LLVMGetFirstBasicBlock(function)) |block| c.LLVMDeleteBasicBlock(block);
            self.pruned_function_bodies += 1;
        }
    }

    fn firstLocation(self: *CodeGenerator) tok.Location {
        if (self.graph.nodes.items.len != 0) return self.location(self.graph.nodes.items[0].source);
        return .{ .file = @enumFromInt(0), .offset = 0 };
    }

    fn location(self: *CodeGenerator, source: primitives.SourceRef) tok.Location {
        // Global files are grouped by module; generated entry sources need
        // not occupy the same ordinal in the diagnostics source database.
        if (source.file_index < self.graph.files.items.len) {
            const file = self.graph.files.items[source.file_index];
            const basename = self.graph.text(file.path);
            const dir = self.graph.text(self.graph.modules.items[@intFromEnum(file.module)].dir);
            for (self.diags.source_db.files, 0..) |candidate, index| {
                if (std.mem.eql(u8, std.fs.path.basename(candidate.path), basename) and
                    std.mem.eql(u8, std.fs.path.dirname(candidate.path) orelse ".", dir))
                    return .{ .file = self.diags.source_db.fileId(index), .offset = source.offset };
            }
        }
        return .{ .file = @enumFromInt(0), .offset = source.offset };
    }

    fn report(self: *CodeGenerator, source: primitives.SourceRef, comptime format: []const u8, args: anytype) !void {
        try self.diags.add(self.location(source), .codegen, format, args);
    }

    fn dupZ(self: *CodeGenerator, text: []const u8) ![:0]u8 {
        return self.allocator.dupeZ(u8, text);
    }
};

test "global codegen identities are graph IDs rather than semantic pointers" {
    try std.testing.expect(@sizeOf(graph_mod.GlobalFunctionId) == 4);
    try std.testing.expect(@sizeOf(graph_mod.GlobalBindingId) == 4);
    try std.testing.expect(@sizeOf(graph_mod.GlobalNodeId) == 4);
}

test "global codegen prunes bodies outside the executable call graph" {
    const allocator = std.testing.allocator;
    var graph: graph_mod.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);
    var diagnostics = diagnostic.Diagnostics.init(&allocator, &.{});
    defer diagnostics.deinit();
    var generator = try CodeGenerator.init(allocator, std.testing.io, &graph, &diagnostics, .{});
    defer generator.deinit();

    const void_function_type = c.LLVMFunctionType(c.LLVMVoidType(), null, 0, 0);
    const main_function = c.LLVMAddFunction(generator.module, "main", void_function_type);
    const helper = c.LLVMAddFunction(generator.module, "reachable_helper", void_function_type);
    const unused = c.LLVMAddFunction(generator.module, "unused_helper", void_function_type);

    const main_entry = c.LLVMAppendBasicBlock(main_function, "entry");
    c.LLVMPositionBuilderAtEnd(generator.builder, main_entry);
    _ = c.LLVMBuildCall2(generator.builder, void_function_type, helper, null, 0, "");
    _ = c.LLVMBuildRetVoid(generator.builder);
    const helper_entry = c.LLVMAppendBasicBlock(helper, "entry");
    c.LLVMPositionBuilderAtEnd(generator.builder, helper_entry);
    _ = c.LLVMBuildRetVoid(generator.builder);
    const unused_entry = c.LLVMAppendBasicBlock(unused, "entry");
    c.LLVMPositionBuilderAtEnd(generator.builder, unused_entry);
    _ = c.LLVMBuildRetVoid(generator.builder);

    try generator.pruneUnreachableFunctionBodies();
    try std.testing.expect(c.LLVMGetFirstBasicBlock(main_function) != null);
    try std.testing.expect(c.LLVMGetFirstBasicBlock(helper) != null);
    try std.testing.expect(c.LLVMGetFirstBasicBlock(unused) == null);
    try std.testing.expectEqual(@as(usize, 1), generator.pruned_function_bodies);
}
