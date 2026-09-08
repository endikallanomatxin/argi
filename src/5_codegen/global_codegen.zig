const std = @import("std");
const llvm = @import("llvm.zig");
const c = llvm.c;
const graph_mod = @import("../4_semantics/global_semantic_graph.zig");
const types = @import("../4_semantics/global_semantic_types.zig");
const primitives = @import("../4_semantics/semantic_primitives.zig");
const diagnostic = @import("../1_base/diagnostic.zig");
const tok = @import("../2_tokens/token.zig");
const syn = @import("../3_syntax/syntax_tree.zig");
const type_codegen = @import("global_codegen_types.zig");

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
    runtime_argc_global: ?llvm.c.LLVMValueRef = null,
    runtime_argv_global: ?llvm.c.LLVMValueRef = null,

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
            if (function.body == null) continue;
            const id: graph_mod.GlobalFunctionId = @enumFromInt(@as(u32, @intCast(raw)));
            try self.generateFunctionBody(id);
        }

        if (self.options.selected_test_name != null) {
            if (self.selected_test_candidate) |id| try self.generateCTestWrapper(id);
        } else if (self.main_candidate) |id| {
            try self.generateCMainWrapper(id);
        }

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
        for (self.graph.functions.items, 0..) |_, raw| {
            const id: graph_mod.GlobalFunctionId = @enumFromInt(@as(u32, @intCast(raw)));
            _ = try self.declareFunction(id);
        }
    }

    fn declareFunction(self: *CodeGenerator, id: graph_mod.GlobalFunctionId) !FunctionSymbol {
        if (self.functions.get(id)) |existing| return existing;
        const function = self.graph.functions.items[@intFromEnum(id)];
        const declaration = self.graph.declarations.items[@intFromEnum(function.declaration)];
        const name = self.graph.text(declaration.name);
        const is_extern = function.body == null and !function.flags.has_declared_body;
        var symbol: FunctionSymbol = undefined;

        if (is_extern) {
            const signature = try self.externSignature(function, name);
            const name_z = try self.dupZ(name);
            const ref = c.LLVMAddFunction(self.module, name_z.ptr, signature.fn_type);
            if (signature.uses_sret) {
                const kind = c.LLVMGetEnumAttributeKindForName("sret", 4);
                const attr = c.LLVMCreateEnumAttribute(c.LLVMGetGlobalContext(), kind, 0);
                c.LLVMAddAttributeAtIndex(ref, 1, attr);
            }
            symbol = .{ .ref = ref, .type_ref = signature.fn_type, .return_type = signature.return_type, .is_extern = true, .uses_sret = signature.uses_sret };
        } else {
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

        if (self.options.selected_test_name) |wanted| {
            if (function.flags.is_test and std.mem.eql(u8, name, wanted)) self.selected_test_candidate = id;
        } else if (self.isWrappableMain(id)) {
            self.main_candidate = id;
        }
        return symbol;
    }

    const ExternSignature = struct { fn_type: llvm.c.LLVMTypeRef, return_type: llvm.c.LLVMTypeRef, uses_sret: bool };

    fn externSignature(self: *CodeGenerator, function: graph_mod.Function, name: []const u8) !ExternSignature {
        const uses_sret = function.output.len > 1;
        const total: usize = function.input.len + @as(usize, if (uses_sret) 1 else 0);
        const params = try self.allocator.alloc(llvm.c.LLVMTypeRef, total);
        defer self.allocator.free(params);
        var cursor: usize = 0;
        if (uses_sret) {
            params[0] = c.LLVMPointerType(try self.fieldsLLVMType(function.output), 0);
            cursor = 1;
        }
        for (self.graph.fields.items[function.input.start..][0..function.input.len], 0..) |field, index|
            params[cursor + index] = try self.toLLVMType(field.ty);
        if (std.mem.eql(u8, name, "free") and function.input.len == 1)
            params[cursor] = c.LLVMPointerType(c.LLVMInt8Type(), 0);

        var ret = c.LLVMVoidType();
        if (function.output.len == 1) ret = try self.toLLVMType(self.graph.fields.items[function.output.start].ty);
        if (function.safety_primitive == .raw_allocated_storage) ret = c.LLVMPointerType(c.LLVMInt8Type(), 0);
        return .{ .fn_type = c.LLVMFunctionType(ret, if (total == 0) null else params.ptr, @intCast(total), 0), .return_type = ret, .uses_sret = uses_sret };
    }

    fn predeclareGlobalBindings(self: *CodeGenerator) !void {
        for (self.graph.roots.items) |node_id| {
            const node = self.graph.nodes.items[@intFromEnum(node_id)];
            const binding = switch (node.content) { .binding_declaration => |id| id, else => continue };
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

    fn ensureGlobalInitialized(self: *CodeGenerator, binding: graph_mod.GlobalBindingId) !void {
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
            const value = try self.globalConstant(initialization);
            if (value.type_ref != storage.type_ref) return CodegenError.InvalidType;
            c.LLVMSetInitializer(storage.ref, value.value_ref);
        }
        try self.global_bindings.put(binding, .done);
    }

    fn globalConstant(self: *CodeGenerator, node_id: graph_mod.GlobalNodeId) !TypedValue {
        const node = self.graph.nodes.items[@intFromEnum(node_id)];
        return switch (node.content) {
            .int_literal, .float_literal, .char_literal, .bool_literal, .string_literal => self.emitLiteral(node_id),
            .binding_use => |binding| blk: {
                try self.ensureGlobalInitialized(binding);
                const storage = self.bindings.get(binding) orelse return CodegenError.SymbolNotFound;
                const initializer = c.LLVMGetInitializer(storage.ref) orelse return CodegenError.InvalidType;
                break :blk .{ .value_ref = initializer, .type_ref = storage.type_ref, .ty = storage.ty };
            },
            .address_of => |target| blk: {
                const target_node = self.graph.nodes.items[@intFromEnum(target)];
                const binding = switch (target_node.content) { .binding_use => |id| id, else => return CodegenError.InvalidType };
                try self.ensureGlobalInitialized(binding);
                const storage = self.bindings.get(binding) orelse return CodegenError.SymbolNotFound;
                break :blk .{ .value_ref = storage.ref, .type_ref = c.LLVMPointerType(storage.type_ref, 0), .ty = node.ty };
            },
            else => CodegenError.InvalidType,
        };
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
        const input_value = c.LLVMGetParam(symbol.ref, 0);
        for (self.graph.binding_refs.items[function.input_bindings.start..][0..function.input_bindings.len], 0..) |binding, index| {
            try self.allocateLocalBinding(binding, null);
            const storage = self.bindings.getPtr(binding).?;
            const value = c.LLVMBuildExtractValue(self.builder, input_value, @intCast(index), "arg");
            _ = c.LLVMBuildStore(self.builder, value, storage.ref);
            storage.initialized = true;
            if (storage.drop_state) |drop| self.storeDropState(drop, true);
        }
        for (self.graph.binding_refs.items[function.output_bindings.start..][0..function.output_bindings.len]) |binding| {
            const record = self.graph.bindings.items[@intFromEnum(binding)];
            try self.allocateLocalBinding(binding, record.initialization);
        }

        _ = try self.genBlock(body);
        const current = c.LLVMGetInsertBlock(self.builder);
        if (current != null and c.LLVMGetBasicBlockTerminator(current) == null)
            try self.emitImplicitReturn(function);
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
        for (self.graph.node_refs.items[block.nodes.start..][0..block.nodes.len]) |node| {
            const current = c.LLVMGetInsertBlock(self.builder);
            if (current != null and c.LLVMGetBasicBlockTerminator(current) != null) break;
            _ = try self.visitNode(node);
        }
        return if (block.ret_val) |node| self.visitNode(node) else null;
    }

    fn visitNode(self: *CodeGenerator, node_id: graph_mod.GlobalNodeId) anyerror!?TypedValue {
        const node = self.graph.nodes.items[@intFromEnum(node_id)];
        return switch (node.content) {
            .declaration, .reach_directive, .type_literal => null,
            .binding_declaration => |binding| blk: {
                if (self.global_bindings.contains(binding)) {
                    try self.ensureGlobalInitialized(binding);
                } else {
                    const record = self.graph.bindings.items[@intFromEnum(binding)];
                    try self.allocateLocalBinding(binding, record.initialization);
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
            .auto_deinit_binding => |auto| blk: { try self.genAutoDeinit(auto); break :blk null; },
            .function_call => |call| try self.genFunctionCall(call),
            .virtualize, .virtual_call => CodegenError.NotYetImplemented,
            .code_block => |block| try self.genBlock(block),
            .int_literal, .float_literal, .char_literal, .string_literal, .bool_literal => try self.emitLiteral(node_id),
            .list_literal => |literal| try self.listLiteral(literal, node.ty),
            .struct_value_literal => |literal| try self.structLiteral(literal),
            .struct_field_access => |access| try self.fieldAccess(node_id, access),
            .choice_literal => |literal| try self.choiceLiteral(literal),
            .choice_payload_access => |access| try self.choicePayload(node_id, access),
            .nullable_unwrap_or => |unwrap| try self.nullableUnwrap(unwrap),
            .testing_expect_error, .error_propagation, .error_context => CodegenError.NotYetImplemented,
            .array_literal => |literal| try self.arrayLiteral(literal),
            .array_index => |access| try self.arrayIndex(access),
            .array_store => |store| blk: { try self.arrayStore(store); break :blk null; },
            .struct_field_store => |store| blk: { try self.structFieldStore(store); break :blk null; },
            .binary_operation => |operation| try self.binary(operation),
            .comparison => |comparison| try self.emitComparison(comparison),
            .logical_operation => |operation| try self.logical(operation),
            .return_statement => |ret| blk: { try self.genReturn(ret); break :blk null; },
            .if_statement => |statement| blk: { try self.genIf(statement); break :blk null; },
            .while_statement => |statement| blk: { try self.genWhile(statement); break :blk null; },
            .for_statement => |statement| blk: { try self.genFor(statement); break :blk null; },
            .switch_statement => |switch_id| blk: { try self.genSwitch(switch_id); break :blk null; },
            .break_statement => blk: { try self.genBreak(node.source); break :blk null; },
            .continue_statement => blk: { try self.genContinue(node.source); break :blk null; },
            .address_of => |target| try self.addressOf(node_id, target),
            .dereference => |deref| try self.dereference(deref),
            .pointer_assignment => |assignment| blk: { try self.pointerAssignment(assignment); break :blk null; },
            .type_initializer => |initializer| try self.typeInitializer(initializer),
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
                break :blk .{ .value_ref = c.LLVMConstInt(type_ref, @bitCast(value), if (value < 0) 1 else 0), .type_ref = type_ref, .ty = node.ty };
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
        const element_types = self.graph.type_refs.items[literal.element_types.start..][0..literal.element_types.len];
        const llvm_fields = try self.allocator.alloc(llvm.c.LLVMTypeRef, element_types.len);
        defer self.allocator.free(llvm_fields);
        for (element_types, 0..) |element, index| llvm_fields[index] = try self.toLLVMType(element);
        const type_ref = c.LLVMStructType(if (llvm_fields.len == 0) null else llvm_fields.ptr, @intCast(llvm_fields.len), 0);
        var aggregate = c.LLVMGetUndef(type_ref);
        for (self.graph.node_refs.items[literal.elements.start..][0..literal.elements.len], 0..) |node, index| {
            const value = (try self.visitNode(node)) orelse return CodegenError.ValueNotFound;
            aggregate = c.LLVMBuildInsertValue(self.builder, aggregate, value.value_ref, @intCast(index), "list.elem");
        }
        return .{ .value_ref = aggregate, .type_ref = type_ref, .ty = ty };
    }

    fn structLiteral(self: *CodeGenerator, literal: anytype) !TypedValue {
        const type_ref = try self.toLLVMType(literal.ty);
        const range = types.fields(self.graph, literal.ty) orelse return CodegenError.InvalidType;
        if (self.isCUnion(literal.ty)) {
            const temp = c.LLVMBuildAlloca(self.builder, type_ref, "union.literal");
            for (self.graph.value_fields.items[literal.fields.start..][0..literal.fields.len]) |value_field| {
                const name = self.graph.text(value_field.name);
                const hit = types.findField(self.graph, literal.ty, name) orelse return CodegenError.InvalidType;
                const value = (try self.visitNode(value_field.value)) orelse return CodegenError.ValueNotFound;
                var lowerer = self.typeLowerer();
                const pointer = try lowerer.buildUnionFieldPointer(self.builder, temp, types.effectiveFieldType(hit.field), "union.literal.field");
                _ = c.LLVMBuildStore(self.builder, value.value_ref, pointer);
            }
            return .{ .value_ref = c.LLVMBuildLoad2(self.builder, type_ref, temp, "union.literal.value"), .type_ref = type_ref, .ty = literal.ty };
        }
        var aggregate = c.LLVMGetUndef(type_ref);
        for (self.graph.value_fields.items[literal.fields.start..][0..literal.fields.len]) |value_field| {
            const name = self.graph.text(value_field.name);
            const hit = types.findField(self.graph, literal.ty, name) orelse return CodegenError.InvalidType;
            const value = (try self.visitNode(value_field.value)) orelse return CodegenError.ValueNotFound;
            aggregate = c.LLVMBuildInsertValue(self.builder, aggregate, value.value_ref, hit.index, "struct.field");
        }
        _ = range;
        return .{ .value_ref = aggregate, .type_ref = type_ref, .ty = literal.ty };
    }

    fn fieldAccess(self: *CodeGenerator, node_id: graph_mod.GlobalNodeId, access: anytype) !TypedValue {
        const node = self.graph.nodes.items[@intFromEnum(node_id)];
        const field_ty = node.ty orelse return CodegenError.InvalidType;
        if (self.addressablePointer(node_id)) |pointer_result| {
            const pointer = pointer_result catch return CodegenError.InvalidType;
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
        var aggregate = c.LLVMGetUndef(type_ref);
        for (self.graph.node_refs.items[literal.elements.start..][0..literal.elements.len], 0..) |node, index| {
            const value = (try self.visitNode(node)) orelse return CodegenError.ValueNotFound;
            aggregate = c.LLVMBuildInsertValue(self.builder, aggregate, value.value_ref, @intCast(index), "array.elem");
        }
        return .{ .value_ref = aggregate, .type_ref = type_ref, .ty = null };
    }

    fn arrayIndex(self: *CodeGenerator, access: anytype) !TypedValue {
        const pointer = (try self.visitNode(access.array_ptr)) orelse return CodegenError.ValueNotFound;
        const index = (try self.visitNode(access.index)) orelse return CodegenError.ValueNotFound;
        const array_type = try self.toLLVMType(access.array_type);
        const element_type = try self.toLLVMType(access.element_type);
        const element_ptr = try self.arrayElementPointer(pointer.value_ref, array_type, index.value_ref);
        return .{ .value_ref = c.LLVMBuildLoad2(self.builder, element_type, element_ptr, "array.elem"), .type_ref = element_type, .ty = access.element_type };
    }

    fn arrayStore(self: *CodeGenerator, store: anytype) !void {
        const pointer = (try self.visitNode(store.array_ptr)) orelse return CodegenError.ValueNotFound;
        const index = (try self.visitNode(store.index)) orelse return CodegenError.ValueNotFound;
        const value = (try self.visitNode(store.value)) orelse return CodegenError.ValueNotFound;
        const array_type = try self.toLLVMType(store.array_type);
        const element_ptr = try self.arrayElementPointer(pointer.value_ref, array_type, index.value_ref);
        _ = c.LLVMBuildStore(self.builder, value.value_ref, element_ptr);
    }

    fn arrayElementPointer(self: *CodeGenerator, pointer: llvm.c.LLVMValueRef, array_type: llvm.c.LLVMTypeRef, index: llvm.c.LLVMValueRef) !llvm.c.LLVMValueRef {
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
        if (self.graph.nodes.items[@intFromEnum(store.value)].content == .type_initializer) {
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
        const float = if (left.ty) |ty| self.isFloat(ty) else false;
        const unsigned = if (left.ty) |ty| self.isUnsigned(ty) else false;
        const value = switch (comparison.operator) {
            .equal => if (float) c.LLVMBuildFCmp(self.builder, c.LLVMRealOEQ, left.value_ref, right.value_ref, "eq") else c.LLVMBuildICmp(self.builder, c.LLVMIntEQ, left.value_ref, right.value_ref, "eq"),
            .not_equal => if (float) c.LLVMBuildFCmp(self.builder, c.LLVMRealONE, left.value_ref, right.value_ref, "ne") else c.LLVMBuildICmp(self.builder, c.LLVMIntNE, left.value_ref, right.value_ref, "ne"),
            .less_than => if (float) c.LLVMBuildFCmp(self.builder, c.LLVMRealOLT, left.value_ref, right.value_ref, "lt") else c.LLVMBuildICmp(self.builder, if (unsigned) c.LLVMIntULT else c.LLVMIntSLT, left.value_ref, right.value_ref, "lt"),
            .greater_than => if (float) c.LLVMBuildFCmp(self.builder, c.LLVMRealOGT, left.value_ref, right.value_ref, "gt") else c.LLVMBuildICmp(self.builder, if (unsigned) c.LLVMIntUGT else c.LLVMIntSGT, left.value_ref, right.value_ref, "gt"),
            .less_than_or_equal => if (float) c.LLVMBuildFCmp(self.builder, c.LLVMRealOLE, left.value_ref, right.value_ref, "le") else c.LLVMBuildICmp(self.builder, if (unsigned) c.LLVMIntULE else c.LLVMIntSLE, left.value_ref, right.value_ref, "le"),
            .greater_than_or_equal => if (float) c.LLVMBuildFCmp(self.builder, c.LLVMRealOGE, left.value_ref, right.value_ref, "ge") else c.LLVMBuildICmp(self.builder, if (unsigned) c.LLVMIntUGE else c.LLVMIntSGE, left.value_ref, right.value_ref, "ge"),
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
        const pointer = try self.addressablePointer(target);
        pointer.ty = self.graph.nodes.items[@intFromEnum(node_id)].ty;
        return pointer;
    }

    fn addressablePointer(self: *CodeGenerator, node_id: graph_mod.GlobalNodeId) !TypedValue {
        const node = self.graph.nodes.items[@intFromEnum(node_id)];
        return switch (node.content) {
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
        if (self.graph.nodes.items[@intFromEnum(assignment.value)].content == .type_initializer) {
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

    fn genFunctionCall(self: *CodeGenerator, call: anytype) !?TypedValue {
        const callee = self.graph.functions.items[@intFromEnum(call.callee)];
        const symbol = self.functions.get(call.callee) orelse return CodegenError.SymbolNotFound;
        if (callee.safety_primitive == .trusted_opaque_move or callee.safety_primitive == .trusted_opaque_move_in) return self.opaqueStore(call.input);
        if (callee.safety_primitive == .trusted_opaque_move_out) return self.opaqueTake(call.input);
        const input = (try self.visitNode(call.input)) orelse return CodegenError.ValueNotFound;

        if (!symbol.is_extern) {
            var args = [_]llvm.c.LLVMValueRef{input.value_ref};
            const result = c.LLVMBuildCall2(self.builder, symbol.type_ref, symbol.ref, &args, 1, "call");
            self.markCallDropState(call);
            if (callee.output.len == 0) return null;
            if (callee.output.len == 1) {
                const field = self.graph.fields.items[callee.output.start];
                return .{ .value_ref = c.LLVMBuildExtractValue(self.builder, result, 0, "call.out"), .type_ref = try self.toLLVMType(field.ty), .ty = field.ty };
            }
            return .{ .value_ref = result, .type_ref = symbol.return_type, .ty = self.graph.nodes.items[@intFromEnum(call.input)].ty };
        }

        const total: usize = callee.input.len + @as(usize, if (symbol.uses_sret) 1 else 0);
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
        for (self.graph.fields.items[callee.input.start..][0..callee.input.len], 0..) |field, index| {
            const raw = c.LLVMBuildExtractValue(self.builder, input.value_ref, @intCast(index), "extern.arg");
            if (std.mem.eql(u8, name, "free") and callee.input.len == 1)
                args[cursor + index] = c.LLVMBuildIntToPtr(self.builder, raw, c.LLVMPointerType(c.LLVMInt8Type(), 0), "free.address")
            else
                args[cursor + index] = raw;
            _ = field;
        }
        const call_value = c.LLVMBuildCall2(self.builder, symbol.type_ref, symbol.ref, if (total == 0) null else args.ptr, @intCast(total), if (symbol.return_type == c.LLVMVoidType()) "" else "call");
        self.markCallDropState(call);
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
        const input = switch (self.graph.nodes.items[@intFromEnum(input_id)].content) { .struct_value_literal => |literal| literal, else => return CodegenError.InvalidType };
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
        const input = switch (self.graph.nodes.items[@intFromEnum(input_id)].content) { .struct_value_literal => |literal| literal, else => return CodegenError.InvalidType };
        const fields = self.graph.value_fields.items[input.fields.start..][0..input.fields.len];
        if (fields.len != 2) return CodegenError.InvalidType;
        _ = try self.visitNode(fields[0].value);
        const slot = (try self.visitNode(fields[1].value)) orelse return CodegenError.ValueNotFound;
        const pointer_ty = self.graph.nodes.items[@intFromEnum(fields[1].value)].ty orelse return CodegenError.InvalidType;
        const child = switch (self.graph.types.items[@intFromEnum(pointer_ty)]) { .pointer => |pointer| pointer.child, else => return CodegenError.InvalidType };
        const type_ref = try self.toLLVMType(child);
        return .{ .value_ref = c.LLVMBuildLoad2(self.builder, type_ref, slot.value_ref, "opaque.take"), .type_ref = type_ref, .ty = child };
    }

    fn typeInitializer(self: *CodeGenerator, initializer: anytype) !TypedValue {
        const declaration = self.graph.declarations.items[@intFromEnum(initializer.type_decl)];
        const ty = declaration.type_id orelse return CodegenError.InvalidType;
        const type_ref = try self.toLLVMType(ty);
        const storage = c.LLVMBuildAlloca(self.builder, type_ref, "type.init.tmp");
        try self.typeInitializerInto(initializer, storage);
        return .{ .value_ref = c.LLVMBuildLoad2(self.builder, type_ref, storage, "type.init"), .type_ref = type_ref, .ty = ty };
    }

    fn typeInitializerInto(self: *CodeGenerator, initializer: anytype, storage: llvm.c.LLVMValueRef) !void {
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
        _ = c.LLVMBuildCall2(self.builder, symbol.type_ref, symbol.ref, &call_args, 1, "");
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
        _ = c.LLVMBuildStore(self.builder, c.LLVMConstInt(c.LLVMInt1Type(), if (enabled) 1 else 0, 0), state.flag_ref);
        for (state.fields) |*field| self.storeDropState(field, enabled);
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

    fn markCallDropState(self: *CodeGenerator, call: anytype) void {
        if (call.consumes_auto_deinit) |node| if (self.dropStateForNode(node)) |drop| self.storeDropState(drop, false);
        if (call.initializes_auto_deinit) |node| if (self.dropStateForNode(node)) |drop| self.storeDropState(drop, true);
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
        fields: graph_mod.GlobalSemanticGraph.AutoDeinitFieldRange,
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
            .generic => if (types.genericInstance(self.graph, ty)) |instance| switch (instance.shape) { .choice => |shape| shape.layout == .c_enum, else => false } else false,
            else => false,
        };
    }

    fn isCUnion(self: *CodeGenerator, ty: graph_mod.GlobalTypeId) bool {
        return switch (self.graph.types.items[@intFromEnum(ty)]) {
            .declared => |decl| self.graph.declarations.items[@intFromEnum(decl)].struct_layout == .c_union,
            .structural => |shape| shape.layout == .c_union,
            .generic => if (types.genericInstance(self.graph, ty)) |instance| switch (instance.shape) { .structure => |shape| shape.layout == .c_union, else => false } else false,
            else => false,
        };
    }

    fn isPointer(self: *CodeGenerator, ty: graph_mod.GlobalTypeId) bool {
        return self.graph.types.items[@intFromEnum(ty)] == .pointer;
    }

    fn isFloat(self: *CodeGenerator, ty: graph_mod.GlobalTypeId) bool {
        return switch (self.graph.types.items[@intFromEnum(ty)]) { .builtin => |builtin| builtin == .Float16 or builtin == .Float32 or builtin == .Float64, else => false };
    }

    fn isUnsigned(self: *CodeGenerator, ty: graph_mod.GlobalTypeId) bool {
        return switch (self.graph.types.items[@intFromEnum(ty)]) { .builtin => |builtin| switch (builtin) { .UIntNative, .UInt8, .UInt16, .UInt32, .UInt64 => true, else => false }, else => false };
    }

    fn isStringView(self: *CodeGenerator, ty: graph_mod.GlobalTypeId) bool {
        const range = types.fields(self.graph, ty) orelse return false;
        if (range.len != 2) return false;
        const data = self.graph.fields.items[range.start];
        const length = self.graph.fields.items[range.start + 1];
        if (!std.mem.eql(u8, self.graph.text(data.name), "data") or !std.mem.eql(u8, self.graph.text(length.name), "length")) return false;
        const pointer = switch (self.graph.types.items[@intFromEnum(data.ty)]) { .pointer => |value| value, else => return false };
        return types.isBuiltin(self.graph, pointer.child, .UInt8) and types.isBuiltin(self.graph, length.ty, .UIntNative);
    }

    fn nativeUIntType(self: *CodeGenerator) !llvm.c.LLVMTypeRef {
        for (self.graph.types.items, 0..) |ty, raw| switch (ty) {
            .builtin => |builtin| if (builtin == .UIntNative) return self.toLLVMType(@enumFromInt(@as(u32, @intCast(raw)))),
            else => {},
        };
        return switch (types.pointer_size_bytes) { 4 => c.LLVMInt32Type(), 8 => c.LLVMInt64Type(), else => CodegenError.InvalidType };
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

    fn isWrappableMain(self: *CodeGenerator, id: graph_mod.GlobalFunctionId) bool {
        const function = self.graph.functions.items[@intFromEnum(id)];
        const declaration = self.graph.declarations.items[@intFromEnum(function.declaration)];
        if (!std.mem.eql(u8, self.graph.text(declaration.name), "main") or function.output.len != 1) return false;
        const field = self.graph.fields.items[function.output.start];
        return std.mem.eql(u8, self.graph.text(field.name), "status_code") and types.isBuiltin(self.graph, field.ty, .Int32);
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
        _ = c.LLVMBuildStore(self.builder, c.LLVMGetParam(wrapper, 0), self.runtime_argc_global.?);
        _ = c.LLVMBuildStore(self.builder, c.LLVMGetParam(wrapper, 1), self.runtime_argv_global.?);
        const function = self.graph.functions.items[@intFromEnum(main)];
        const input_type = try self.fieldsLLVMType(function.input);
        const empty = c.LLVMGetUndef(input_type);
        var args = [_]llvm.c.LLVMValueRef{empty};
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
        const function = self.graph.functions.items[@intFromEnum(test_function)];
        const input_type = try self.fieldsLLVMType(function.input);
        var args = [_]llvm.c.LLVMValueRef{c.LLVMGetUndef(input_type)};
        _ = c.LLVMBuildCall2(self.builder, symbol.type_ref, symbol.ref, &args, 1, "test");
        _ = c.LLVMBuildRet(self.builder, c.LLVMConstInt(i32_ty, 0, 0));
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

    pub fn collectStats(self: *const CodeGenerator) !Stats {
        var stats = Stats{ .semantic_functions = self.graph.functions.items.len };
        var function = c.LLVMGetFirstFunction(self.module);
        while (function != null) : (function = c.LLVMGetNextFunction(function)) {
            if (c.LLVMGetFirstBasicBlock(function) == null) continue;
            stats.llvm_functions_with_body += 1;
            stats.reachable_llvm_functions_with_body += 1;
            var block = c.LLVMGetFirstBasicBlock(function);
            while (block != null) : (block = c.LLVMGetNextBasicBlock(block)) {
                stats.basic_blocks += 1;
                var instruction = c.LLVMGetFirstInstruction(block);
                while (instruction != null) : (instruction = c.LLVMGetNextInstruction(instruction)) stats.instructions += 1;
            }
        }
        const text = c.LLVMPrintModuleToString(self.module);
        if (text != null) {
            stats.ir_bytes = std.mem.span(text).len;
            c.LLVMDisposeMessage(text);
        }
        return stats;
    }

    fn firstLocation(self: *CodeGenerator) tok.Location {
        if (self.graph.nodes.items.len != 0) return self.location(self.graph.nodes.items[0].source);
        return .{ .file = @enumFromInt(0), .offset = 0 };
    }

    fn location(self: *CodeGenerator, source: primitives.SourceRef) tok.Location {
        _ = self;
        return .{ .file = @enumFromInt(source.file_index), .offset = source.offset };
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
