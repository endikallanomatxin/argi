const std = @import("std");
const module_sg = @import("../module/graph.zig");
const module_entities = @import("../module/entities.zig");
const global_sg = @import("graph.zig");
const globalizer = @import("globalizer.zig");
const resolution = @import("resolution.zig");
const core_mod = @import("core.zig");
const global_types = @import("types.zig");
const primitives = @import("../primitives/schema.zig");

pub const Stats = struct {
    propagations: u32 = 0,
    contexts: u32 = 0,
};

pub const Resolver = struct {
    allocator: std.mem.Allocator,
    graph: *global_sg.GlobalSemanticGraph,
    modules: []const module_sg.ModuleSemanticGraph,
    offsets: []const globalizer.Offsets,
    core: *core_mod.Resolver,
    stats: Stats = .{},

    /// Compute effective reason summaries until recursive call chains stop
    /// changing. Open inferred signatures grow their declared reason choice;
    /// explicit signatures retain a separate subset summary.
    pub fn inferFunctionErrorReasons(self: *Resolver) !bool {
        var any_changed = false;
        var round: usize = 0;
        while (round <= self.graph.functions.items.len) : (round += 1) {
            var changed = false;
            for (0..self.graph.functions.items.len) |raw| {
                if (try self.inferOne(@enumFromInt(@as(u32, @intCast(raw))))) changed = true;
            }
            any_changed = any_changed or changed;
            if (!changed) break;
        }
        return any_changed;
    }

    fn inferOne(self: *Resolver, function_id: global_sg.GlobalFunctionId) !bool {
        const function = &self.graph.functions.items[@intFromEnum(function_id)];
        const declared = self.functionReasonType(function.*) orelse {
            function.inferred_error_reasons = null;
            return false;
        };
        const body = function.body orelse {
            if (function.inferred_error_reasons == null) function.inferred_error_reasons = declared;
            return false;
        };
        var collected: std.ArrayList(global_sg.GlobalVariantId) = .empty;
        defer collected.deinit(self.allocator);
        try self.collectBlock(function.*, body, &collected);

        if (function.flags.uses_inferred_error_reasons) {
            const changed = try self.replaceOpenReasons(declared, collected.items);
            function.inferred_error_reasons = declared;
            return changed;
        }
        if (self.sameReasonSet(function.inferred_error_reasons, collected.items)) return false;
        function.inferred_error_reasons = try self.makeReasonSubset(declared, collected.items);
        return true;
    }

    fn functionReasonType(self: *const Resolver, function: global_sg.Function) ?global_sg.GlobalTypeId {
        if (function.output.len != 1) return null;
        const errable = self.graph.fields.items[function.output.start].ty;
        const error_variant = global_types.findVariant(self.graph, errable, "error") orelse return null;
        const payload = error_variant.variant.payload_type orelse return null;
        return (global_types.findField(self.graph, payload, "reason") orelse return null).field.ty;
    }

    fn collectBlock(self: *Resolver, function: global_sg.Function, block_id: global_sg.GlobalBlockId, out: *std.ArrayList(global_sg.GlobalVariantId)) anyerror!void {
        const block = self.graph.blocks.items[@intFromEnum(block_id)];
        for (self.graph.node_refs.items[block.nodes.start..][0..block.nodes.len]) |node| try self.collectNode(function, node, out);
        if (block.ret_val) |node| try self.markErrableNode(node, out);
    }

    fn collectNode(self: *Resolver, function: global_sg.Function, node_id: global_sg.GlobalNodeId, out: *std.ArrayList(global_sg.GlobalVariantId)) anyerror!void {
        const node = self.graph.nodes.items[@intFromEnum(node_id)];
        switch (node.content) {
            .assignment => |value| {
                if (self.isOutputBinding(function, value.binding)) try self.markErrableNode(value.value, out);
                try self.collectNode(function, value.value, out);
            },
            .return_statement => |value| if (value.expression) |child| {
                try self.markErrableNode(child, out);
                try self.collectNode(function, child, out);
            },
            .error_propagation => |id| {
                const child = self.graph.error_propagations.items[@intFromEnum(id)].errable_value;
                try self.markErrableNode(child, out);
                try self.collectNode(function, child, out);
            },
            .error_context => |id| {
                const value = self.graph.error_contexts.items[@intFromEnum(id)];
                try self.markErrableNode(value.errable_value, out);
                try self.collectNode(function, value.errable_value, out);
                try self.collectNode(function, value.context, out);
            },
            .binding_declaration => |id| if (self.graph.binding(id).initialization) |child| try self.collectNode(function, child, out),
            .move_value, .address_of => |child| try self.collectNode(function, child, out),
            .function_call => |call| try self.collectNode(function, call.input, out),
            .virtualize => |id| try self.collectNode(function, self.graph.virtualizes.items[@intFromEnum(id)].value, out),
            .virtual_call => |id| {
                const call = self.graph.virtual_calls.items[@intFromEnum(id)];
                try self.collectNode(function, call.handle, out);
                try self.collectNode(function, call.input, out);
            },
            .code_block => |block| try self.collectBlock(function, block, out),
            .list_literal => |literal| {
                for (self.graph.node_refs.items[literal.elements.start..][0..literal.elements.len]) |child| try self.collectNode(function, child, out);
            },
            .array_literal => |literal| {
                for (self.graph.node_refs.items[literal.elements.start..][0..literal.elements.len]) |child| try self.collectNode(function, child, out);
            },
            .struct_value_literal => |literal| {
                for (self.graph.value_fields.items[literal.fields.start..][0..literal.fields.len]) |field| try self.collectNode(function, field.value, out);
            },
            .struct_field_access => |value| try self.collectNode(function, value.value, out),
            .choice_literal => |value| if (value.payload) |child| try self.collectNode(function, child, out),
            .choice_payload_access => |value| try self.collectNode(function, value.value, out),
            .nullable_unwrap_or => |id| {
                const value = self.graph.nullable_unwraps.items[@intFromEnum(id)];
                try self.collectNode(function, value.nullable_value, out);
                try self.collectNode(function, value.fallback_value, out);
            },
            .testing_expect_error => |id| try self.collectNode(function, self.graph.testing_expect_errors.items[@intFromEnum(id)].actual_result, out),
            .array_index => |value| {
                try self.collectNode(function, value.array_ptr, out);
                try self.collectNode(function, value.index, out);
            },
            .array_store => |value| {
                try self.collectNode(function, value.array_ptr, out);
                try self.collectNode(function, value.index, out);
                try self.collectNode(function, value.value, out);
            },
            .struct_field_store => |value| {
                try self.collectNode(function, value.struct_ptr, out);
                try self.collectNode(function, value.value, out);
            },
            .binary_operation => |value| {
                try self.collectNode(function, value.left, out);
                try self.collectNode(function, value.right, out);
            },
            .comparison => |value| {
                try self.collectNode(function, value.left, out);
                try self.collectNode(function, value.right, out);
            },
            .logical_operation => |value| {
                try self.collectNode(function, value.left, out);
                try self.collectNode(function, value.right, out);
            },
            .if_statement => |value| {
                try self.collectBlock(function, value.then_block, out);
                if (value.else_block) |block| try self.collectBlock(function, block, out);
            },
            .while_statement => |value| try self.collectBlock(function, value.body, out),
            .for_statement => |value| try self.collectBlock(function, value.body, out),
            .switch_statement => |id| {
                const value = self.graph.switches.items[@intFromEnum(id)];
                for (self.graph.switch_cases.items[value.cases.start..][0..value.cases.len]) |case| try self.collectBlock(function, case.body, out);
                if (value.default_block) |block| try self.collectBlock(function, block, out);
            },
            .dereference => |value| try self.collectNode(function, value.pointer, out),
            .pointer_assignment => |value| {
                try self.collectNode(function, value.pointer, out);
                try self.collectNode(function, value.value, out);
            },
            .type_initializer => |value| try self.collectNode(function, value.args, out),
            .denied_implicit_copy => |value| try self.collectNode(function, value, out),
            .explicit_cast => |value| try self.collectNode(function, value.value, out),
            else => {},
        }
    }

    fn isOutputBinding(self: *const Resolver, function: global_sg.Function, binding: global_sg.GlobalBindingId) bool {
        for (self.graph.binding_refs.items[function.output_bindings.start..][0..function.output_bindings.len]) |candidate|
            if (candidate == binding) return true;
        return false;
    }

    fn markErrableNode(self: *Resolver, node_id: global_sg.GlobalNodeId, out: *std.ArrayList(global_sg.GlobalVariantId)) !void {
        const node = self.graph.node(node_id);
        const reasons = switch (node.content) {
            .function_call => |call| self.graph.function(call.callee).inferred_error_reasons orelse self.reasonTypeFromErrable(node.ty orelse return),
            else => self.reasonTypeFromErrable(node.ty orelse return),
        } orelse return;
        const variants = global_types.variants(self.graph, reasons) orelse return;
        for (0..variants.len) |offset| {
            const id: global_sg.GlobalVariantId = @enumFromInt(variants.start + @as(u32, @intCast(offset)));
            if (!containsVariant(self.graph, out.items, id)) try out.append(self.allocator, id);
        }
    }

    fn reasonTypeFromErrable(self: *const Resolver, ty: global_sg.GlobalTypeId) ?global_sg.GlobalTypeId {
        const error_variant = global_types.findVariant(self.graph, ty, "error") orelse return null;
        const payload = error_variant.variant.payload_type orelse return null;
        return (global_types.findField(self.graph, payload, "reason") orelse return null).field.ty;
    }

    fn sameReasonSet(self: *const Resolver, current: ?global_sg.GlobalTypeId, wanted: []const global_sg.GlobalVariantId) bool {
        const ty = current orelse return false;
        const range = global_types.variants(self.graph, ty) orelse return false;
        if (range.len != wanted.len) return false;
        for (0..range.len) |offset| {
            const id: global_sg.GlobalVariantId = @enumFromInt(range.start + @as(u32, @intCast(offset)));
            if (!containsVariant(self.graph, wanted, id)) return false;
        }
        return true;
    }

    fn replaceOpenReasons(self: *Resolver, ty: global_sg.GlobalTypeId, wanted: []const global_sg.GlobalVariantId) !bool {
        if (self.sameReasonSet(ty, wanted)) return false;
        const start: u32 = @intCast(self.graph.variants.items.len);
        for (wanted) |id| try self.graph.variants.append(self.allocator, self.graph.variants.items[@intFromEnum(id)]);
        self.graph.types.items[@intFromEnum(ty)].inferred_choice.variants = .{ .start = start, .len = @intCast(wanted.len) };
        return true;
    }

    fn makeReasonSubset(self: *Resolver, declared: global_sg.GlobalTypeId, collected: []const global_sg.GlobalVariantId) !global_sg.GlobalTypeId {
        const start: u32 = @intCast(self.graph.variants.items.len);
        const declared_range = global_types.variants(self.graph, declared) orelse return declared;
        for (0..declared_range.len) |offset| {
            const id: global_sg.GlobalVariantId = @enumFromInt(declared_range.start + @as(u32, @intCast(offset)));
            if (containsVariant(self.graph, collected, id)) try self.graph.variants.append(self.allocator, self.graph.variants.items[@intFromEnum(id)]);
        }
        const result: global_sg.GlobalTypeId = @enumFromInt(@as(u32, @intCast(self.graph.types.items.len)));
        try self.graph.types.append(self.allocator, .{ .structural_choice = .{ .variants = .{ .start = start, .len = @intCast(self.graph.variants.items.len - start) } } });
        return result;
    }

    pub fn tryResolve(
        self: *Resolver,
        module_index: usize,
        module: *const module_sg.ModuleSemanticGraph,
        o: globalizer.Offsets,
        operation: module_entities.PendingOperation,
    ) !resolution.Result {
        _ = module_index;
        _ = module;
        return switch (operation) {
            .resolve_error_propagation => |value| resolution.Result.fromBool(try self.resolve(o, value)),
            else => .not_applicable,
        };
    }

    pub fn tryResolveCall(
        self: *Resolver,
        module_index: usize,
        module: *const module_sg.ModuleSemanticGraph,
        o: globalizer.Offsets,
        operation: module_entities.PendingOperation,
    ) !resolution.Result {
        const value = switch (operation) {
            .resolve_call => |call| call,
            else => return .not_applicable,
        };
        const reference = module.semantic.external_refs.items[@intFromEnum(value.callee)];
        if (!std.mem.eql(u8, module.text(reference.name), "expect_error")) return .not_applicable;
        const qualifier = reference.module_path orelse return .not_applicable;
        if (!std.mem.eql(u8, module.text(qualifier), "testing")) return .not_applicable;

        const input = globalizer.globalNode(o, value.input);
        const literal = switch (self.graph.node(input).content) {
            .struct_value_literal => |item| item,
            else => return .deferred,
        };
        var expected_reason: ?global_sg.GlobalNodeId = null;
        var actual_result: ?global_sg.GlobalNodeId = null;
        for (self.graph.value_fields.items[literal.fields.start..][0..literal.fields.len]) |field| {
            if (std.mem.eql(u8, self.graph.text(field.name), "expected_reason")) expected_reason = field.value;
            if (std.mem.eql(u8, self.graph.text(field.name), "actual_result")) actual_result = field.value;
        }
        const expected = expected_reason orelse return error.InvalidTestingExpectErrorArguments;
        const actual = actual_result orelse return error.InvalidTestingExpectErrorArguments;
        const actual_ty = self.graph.node(actual).ty orelse return .deferred;
        const error_variant = global_types.findVariant(self.graph, actual_ty, "error") orelse return error.TestingExpectErrorRequiresErrable;
        const error_payload = error_variant.variant.payload_type orelse return error.TestingExpectErrorRequiresErrable;
        const reason = global_types.findField(self.graph, error_payload, "reason") orelse return error.TestingExpectErrorRequiresReason;
        if (self.graph.node(expected).ty == null) {
            self.graph.nodes.items[@intFromEnum(expected)].ty = reason.field.ty;
            return .deferred;
        }
        const expected_literal = switch (self.graph.node(expected).content) {
            .choice_literal => |choice| choice,
            else => return .deferred,
        };
        if (!global_types.equal(self.graph, expected_literal.choice_type, reason.field.ty)) return error.IncompatibleExpectedErrorReason;

        const fail_function = self.findTestingFailFunction(module_index) orelse return .deferred;
        const fail = self.graph.functions.items[@intFromEnum(fail_function)];
        if (fail.output.len != 1) return error.InvalidTestingFailFunction;
        const result_ty = self.graph.fields.items[fail.output.start].ty;
        const result_ok = global_types.findVariant(self.graph, result_ty, "ok") orelse return error.InvalidTestingFailFunction;
        const id: global_sg.GlobalTestingExpectErrorId = @enumFromInt(@as(u32, @intCast(self.graph.testing_expect_errors.items.len)));
        const empty = try self.graph.addString(self.allocator, "");
        try self.graph.testing_expect_errors.append(self.allocator, .{
            .expected_reason = expected,
            .actual_result = actual,
            .actual_error_variant = error_variant.id,
            .actual_error_payload_type = error_payload,
            .actual_reason_field_index = reason.index,
            .result_type = result_ty,
            .result_ok_variant = result_ok.id,
            .test_fail_function = fail_function,
            .expected_reason_name = expectedLiteralVariantName(self.graph, expected_literal),
            .diagnostic_line = 0,
            .diagnostic_column = 0,
            .diagnostic_source_line = empty,
        });
        const target = globalizer.globalNode(o, value.node);
        self.graph.nodes.items[@intFromEnum(target)] = .{
            .source = .{ .file_index = o.file_base + reference.source.file_index, .offset = reference.source.offset },
            .ty = result_ty,
            .content = .{ .testing_expect_error = id },
        };
        return .resolved;
    }

    fn findTestingFailFunction(self: *const Resolver, current_module: usize) ?global_sg.GlobalFunctionId {
        for (self.graph.functions.items, 0..) |function, raw| {
            const declaration = self.graph.declaration(function.declaration);
            if (!std.mem.eql(u8, self.graph.text(declaration.name), "test_fail_impl")) continue;
            if (!self.core.declarationVisible(current_module, function.declaration, null)) continue;
            return @enumFromInt(@as(u32, @intCast(raw)));
        }
        return null;
    }

    fn resolve(self: *Resolver, o: globalizer.Offsets, value: anytype) !bool {
        const errable = globalizer.globalNode(o, value.errable_value);
        const errable_ty = self.graph.nodes.items[@intFromEnum(errable)].ty orelse return false;
        const ok = global_types.findVariant(self.graph, errable_ty, "ok") orelse return false;
        const err = global_types.findVariant(self.graph, errable_ty, "error") orelse return false;
        const ok_payload = ok.variant.payload_type orelse try self.builtin(.Void);
        const error_payload = err.variant.payload_type orelse try self.builtin(.Void);
        const result_ty = unwrapSingleField(self.graph, ok_payload) orelse ok_payload;

        const target = globalizer.globalNode(o, value.node);
        const propagated_ty = if (value.owner_function) |local_owner|
            (try self.functionErrableType(globalizer.globalFunction(o, local_owner))) orelse return false
        else
            (try self.enclosingErrableType(target)) orelse return false;
        const propagated_error = global_types.findVariant(self.graph, propagated_ty, "error") orelse err;
        const propagated_error_payload = propagated_error.variant.payload_type orelse error_payload;
        if (!self.errorPayloadCanPropagate(error_payload, propagated_error_payload))
            return error.IncompatibleErrorPayload;
        try self.absorbErrorPayloadReasons(error_payload, propagated_error_payload);
        const source: primitives.SourceRef = .{
            .file_index = o.file_base + value.source.file_index,
            .offset = value.source.offset,
        };
        const empty = try self.graph.addString(self.allocator, "");
        const cleanup: primitives.Range(global_sg.GlobalNodeId) = .{ .start = @intCast(self.graph.node_refs.items.len), .len = 0 };

        if (value.context) |local_context| {
            const context = globalizer.globalNode(o, local_context);
            const context_ty = self.graph.nodes.items[@intFromEnum(context)].ty orelse return false;
            if (!self.validContextType(context_ty)) return error.InvalidErrorContextType;
            const id: global_sg.GlobalErrorContextId = @enumFromInt(@as(u32, @intCast(self.graph.error_contexts.items.len)));
            try self.graph.error_contexts.append(self.allocator, .{
                .errable_value = errable,
                .context = context,
                .cleanup_nodes = cleanup,
                .ok_variant = ok.id,
                .ok_value_field_index = singleFieldIndex(self.graph, ok_payload),
                .error_variant = err.id,
                .propagated_errable_type = propagated_ty,
                .propagated_error_variant = propagated_error.id,
                .ok_payload_type = ok_payload,
                .error_payload_type = error_payload,
                .propagated_error_payload_type = propagated_error_payload,
                .diagnostic_line = 0,
                .diagnostic_column = 0,
                .diagnostic_source_line = empty,
            });
            self.graph.nodes.items[@intFromEnum(target)] = .{
                .source = source,
                .ty = result_ty,
                .content = .{ .error_context = id },
            };
            self.stats.contexts += 1;
        } else {
            const id: global_sg.GlobalErrorPropagationId = @enumFromInt(@as(u32, @intCast(self.graph.error_propagations.items.len)));
            try self.graph.error_propagations.append(self.allocator, .{
                .errable_value = errable,
                .cleanup_nodes = cleanup,
                .ok_variant = ok.id,
                .ok_value_field_index = singleFieldIndex(self.graph, ok_payload),
                .error_variant = err.id,
                .propagated_errable_type = propagated_ty,
                .propagated_error_variant = propagated_error.id,
                .ok_payload_type = ok_payload,
                .error_payload_type = error_payload,
                .propagated_error_payload_type = propagated_error_payload,
                .diagnostic_line = 0,
                .diagnostic_column = 0,
                .diagnostic_source_line = empty,
            });
            self.graph.nodes.items[@intFromEnum(target)] = .{
                .source = source,
                .ty = result_ty,
                .content = .{ .error_propagation = id },
            };
            self.stats.propagations += 1;
        }
        return true;
    }

    fn enclosingErrableType(self: *Resolver, target: global_sg.GlobalNodeId) !?global_sg.GlobalTypeId {
        for (self.graph.functions.items, 0..) |function, raw| {
            const body = function.body orelse continue;
            if (!self.blockContains(body, target)) continue;
            return self.functionErrableType(@enumFromInt(@as(u32, @intCast(raw))));
        }
        return null;
    }

    fn functionErrableType(
        self: *Resolver,
        function_id: global_sg.GlobalFunctionId,
    ) !?global_sg.GlobalTypeId {
        if (@intFromEnum(function_id) >= self.graph.functions.items.len) return null;
        const function = self.graph.functions.items[@intFromEnum(function_id)];
        if (function.output.len == 0) return error.ErrorPropagationRequiresErrableReturn;
        if (function.output.len == 1) {
            const ty = self.graph.fields.items[function.output.start].ty;
            if (global_types.findVariant(self.graph, ty, "error") != null) return ty;
        }
        return error.ErrorPropagationRequiresErrableReturn;
    }

    fn errorPayloadCanPropagate(self: *const Resolver, source: global_sg.GlobalTypeId, target: global_sg.GlobalTypeId) bool {
        if (global_types.equal(self.graph, source, target)) return true;
        const source_reason = global_types.findField(self.graph, source, "reason") orelse return false;
        const target_reason = global_types.findField(self.graph, target, "reason") orelse return false;
        const source_trace = global_types.findField(self.graph, source, "trace") orelse return false;
        const target_trace = global_types.findField(self.graph, target, "trace") orelse return false;
        if (!global_types.equal(self.graph, source_trace.field.ty, target_trace.field.ty)) return false;
        const source_variants = global_types.variants(self.graph, source_reason.field.ty) orelse return false;
        const open_reasons = if (self.graph.resolvedSemanticType(target_reason.field.ty)) |ty| switch (ty) {
            .inferred_choice => |choice| choice.kind == .reasons,
            else => false,
        } else false;
        for (self.graph.variants.items[source_variants.start..][0..source_variants.len]) |variant| {
            const matching = global_types.findVariant(self.graph, target_reason.field.ty, self.graph.text(variant.name)) orelse {
                if (open_reasons) continue;
                return false;
            };
            if (variant.payload_type) |payload| {
                const target_payload = matching.variant.payload_type orelse return false;
                if (!global_types.equal(self.graph, payload, target_payload)) return false;
            } else if (matching.variant.payload_type != null) return false;
        }
        return true;
    }

    fn absorbErrorPayloadReasons(self: *Resolver, source: global_sg.GlobalTypeId, target: global_sg.GlobalTypeId) !void {
        const source_reason = global_types.findField(self.graph, source, "reason") orelse return;
        const target_reason = global_types.findField(self.graph, target, "reason") orelse return;
        const target_id = target_reason.field.ty;
        const target_choice = switch (self.graph.types.items[@intFromEnum(target_id)]) {
            .inferred_choice => |choice| if (choice.kind == .reasons) choice else return,
            else => return,
        };
        const source_range = global_types.variants(self.graph, source_reason.field.ty) orelse return;
        var additions: std.ArrayList(global_sg.ChoiceVariant) = .empty;
        defer additions.deinit(self.allocator);
        for (self.graph.variants.items[source_range.start..][0..source_range.len]) |variant| {
            if (global_types.findVariant(self.graph, target_id, self.graph.text(variant.name)) != null) continue;
            try additions.append(self.allocator, variant);
        }
        if (additions.items.len == 0) return;

        // Variant ranges are immutable slices of the indexed pool. Extend an
        // open choice by publishing a new contiguous range, leaving any old
        // range available to readers that already captured it.
        const new_start: u32 = @intCast(self.graph.variants.items.len);
        for (0..target_choice.variants.len) |offset|
            try self.graph.variants.append(self.allocator, self.graph.variants.items[target_choice.variants.start + @as(u32, @intCast(offset))]);
        try self.graph.variants.appendSlice(self.allocator, additions.items);
        self.graph.types.items[@intFromEnum(target_id)].inferred_choice.variants = .{
            .start = new_start,
            .len = target_choice.variants.len + @as(u32, @intCast(additions.items.len)),
        };
    }

    fn validContextType(self: *const Resolver, ty: global_sg.GlobalTypeId) bool {
        const semantic = self.graph.resolvedSemanticType(ty) orelse return false;
        return switch (semantic) {
            .pointer => |pointer| pointer.mutability == .read_only and global_types.isBuiltin(self.graph, pointer.child, .Char),
            .declared => |declaration| std.mem.eql(u8, self.graph.text(self.graph.declarations.items[@intFromEnum(declaration)].name), "StringView"),
            else => false,
        };
    }

    fn blockContains(self: *Resolver, block_id: global_sg.GlobalBlockId, target: global_sg.GlobalNodeId) bool {
        const block = self.graph.blocks.items[@intFromEnum(block_id)];
        for (self.graph.node_refs.items[block.nodes.start..][0..block.nodes.len]) |node_id| {
            if (self.nodeContains(node_id, target)) return true;
        }
        return false;
    }

    // A propagation can be nested in any expression, not just in a block's
    // top-level node list. Follow graph edges so its enclosing return type is
    // found without relying on source positions or allocation order.
    fn nodeContains(self: *Resolver, node_id: global_sg.GlobalNodeId, target: global_sg.GlobalNodeId) bool {
        if (node_id == target) return true;
        const node = self.graph.nodes.items[@intFromEnum(node_id)];
        return switch (node.content) {
            .binding_declaration => |binding| if (self.graph.bindings.items[@intFromEnum(binding)].initialization) |child| self.nodeContains(child, target) else false,
            .move_value, .address_of => |child| self.nodeContains(child, target),
            .assignment => |value| self.nodeContains(value.value, target),
            .function_call => |call| self.nodeContains(call.input, target),
            .virtual_call => |id| blk: {
                const call = self.graph.virtual_calls.items[@intFromEnum(id)];
                break :blk self.nodeContains(call.handle, target) or self.nodeContains(call.input, target);
            },
            .virtualize => |id| self.nodeContains(self.graph.virtualizes.items[@intFromEnum(id)].value, target),
            .code_block => |child| self.blockContains(child, target),
            .list_literal => |literal| self.nodeRangeContains(literal.elements, target),
            .array_literal => |literal| self.nodeRangeContains(literal.elements, target),
            .struct_value_literal => |literal| blk: {
                for (self.graph.value_fields.items[literal.fields.start..][0..literal.fields.len]) |field|
                    if (self.nodeContains(field.value, target)) break :blk true;
                break :blk false;
            },
            .struct_field_access => |access| self.nodeContains(access.value, target),
            .choice_literal => |literal| if (literal.payload) |child| self.nodeContains(child, target) else false,
            .choice_payload_access => |access| self.nodeContains(access.value, target),
            .nullable_unwrap_or => |id| blk: {
                const unwrap = self.graph.nullable_unwraps.items[@intFromEnum(id)];
                break :blk self.nodeContains(unwrap.nullable_value, target) or self.nodeContains(unwrap.fallback_value, target);
            },
            .testing_expect_error => |id| blk: {
                const value = self.graph.testing_expect_errors.items[@intFromEnum(id)];
                break :blk self.nodeContains(value.actual_result, target) or self.nodeContains(value.expected_reason, target);
            },
            .error_propagation => |id| self.nodeContains(self.graph.error_propagations.items[@intFromEnum(id)].errable_value, target),
            .error_context => |id| blk: {
                const value = self.graph.error_contexts.items[@intFromEnum(id)];
                break :blk self.nodeContains(value.errable_value, target) or self.nodeContains(value.context, target);
            },
            .array_index => |access| self.nodeContains(access.array_ptr, target) or self.nodeContains(access.index, target),
            .array_store => |store| self.nodeContains(store.array_ptr, target) or self.nodeContains(store.index, target) or self.nodeContains(store.value, target),
            .struct_field_store => |store| self.nodeContains(store.struct_ptr, target) or self.nodeContains(store.value, target),
            .binary_operation => |operation| self.nodeContains(operation.left, target) or self.nodeContains(operation.right, target),
            .comparison => |operation| self.nodeContains(operation.left, target) or self.nodeContains(operation.right, target),
            .logical_operation => |operation| self.nodeContains(operation.left, target) or self.nodeContains(operation.right, target),
            .return_statement => |statement| if (statement.expression) |child| self.nodeContains(child, target) else false,
            .if_statement => |statement| self.nodeContains(statement.condition, target) or self.blockContains(statement.then_block, target) or
                (if (statement.else_block) |child| self.blockContains(child, target) else false),
            .while_statement => |statement| self.nodeContains(statement.condition, target) or self.blockContains(statement.body, target),
            .for_statement => |statement| (if (statement.init) |child| self.nodeContains(child, target) else false) or
                self.nodeContains(statement.condition, target) or
                (if (statement.increment) |child| self.nodeContains(child, target) else false) or self.blockContains(statement.body, target),
            .switch_statement => |id| blk: {
                const sw = self.graph.switches.items[@intFromEnum(id)];
                if (self.nodeContains(sw.expression, target)) break :blk true;
                for (self.graph.switch_cases.items[sw.cases.start..][0..sw.cases.len]) |case|
                    if (self.blockContains(case.body, target)) break :blk true;
                break :blk if (sw.default_block) |child| self.blockContains(child, target) else false;
            },
            .dereference => |value| self.nodeContains(value.pointer, target),
            .pointer_assignment => |value| self.nodeContains(value.pointer, target) or self.nodeContains(value.value, target),
            .type_initializer => |value| self.nodeContains(value.args, target),
            .denied_implicit_copy => |value| self.nodeContains(value, target),
            .explicit_cast => |value| self.nodeContains(value.value, target),
            else => false,
        };
    }

    fn nodeRangeContains(self: *Resolver, range: primitives.Range(global_sg.GlobalNodeId), target: global_sg.GlobalNodeId) bool {
        for (self.graph.node_refs.items[range.start..][0..range.len]) |child|
            if (self.nodeContains(child, target)) return true;
        return false;
    }

    fn builtin(self: *Resolver, wanted: primitives.BuiltinType) !global_sg.GlobalTypeId {
        for (self.graph.types.items, 0..) |ty, raw| switch (ty) {
            .builtin => |value| if (value == wanted) return @enumFromInt(@as(u32, @intCast(raw))),
            else => {},
        };
        const id: global_sg.GlobalTypeId = @enumFromInt(@as(u32, @intCast(self.graph.types.items.len)));
        try self.graph.types.append(self.allocator, .{ .builtin = wanted });
        return id;
    }
};

fn unwrapSingleField(graph: *const global_sg.GlobalSemanticGraph, ty: global_sg.GlobalTypeId) ?global_sg.GlobalTypeId {
    const fields = global_types.fields(graph, ty) orelse return null;
    if (fields.len != 1) return null;
    return graph.fields.items[fields.start].ty;
}

fn singleFieldIndex(graph: *const global_sg.GlobalSemanticGraph, ty: global_sg.GlobalTypeId) ?u32 {
    const fields = global_types.fields(graph, ty) orelse return null;
    return if (fields.len == 1) 0 else null;
}

fn expectedLiteralVariantName(graph: *const global_sg.GlobalSemanticGraph, literal: anytype) ?primitives.StringRange {
    const raw = @intFromEnum(literal.variant);
    if (raw >= graph.variants.items.len) return null;
    return graph.variants.items[raw].name;
}

fn containsVariant(graph: *const global_sg.GlobalSemanticGraph, haystack: []const global_sg.GlobalVariantId, needle_id: global_sg.GlobalVariantId) bool {
    const needle = graph.variants.items[@intFromEnum(needle_id)];
    for (haystack) |candidate_id| {
        const candidate = graph.variants.items[@intFromEnum(candidate_id)];
        if (!std.mem.eql(u8, graph.text(candidate.name), graph.text(needle.name))) continue;
        if (candidate.payload_type == needle.payload_type) return true;
    }
    return false;
}

test "error propagation resolver writes indexed payloads" {
    try std.testing.expect(@sizeOf(global_sg.GlobalErrorPropagationId) == 4);
    try std.testing.expect(@sizeOf(global_sg.GlobalErrorContextId) == 4);
}

test "enclosing error search follows nested call arguments" {
    const allocator = std.testing.allocator;
    var graph: global_sg.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);
    const source: primitives.SourceRef = .{ .file_index = 0, .offset = 0 };
    try graph.nodes.append(allocator, .{ .source = source, .ty = null, .content = .{ .bool_literal = true } });
    try graph.value_fields.append(allocator, .{ .name = try graph.addString(allocator, "value"), .value = @enumFromInt(0) });
    try graph.nodes.append(allocator, .{ .source = source, .ty = null, .content = .{ .struct_value_literal = .{ .fields = .{ .start = 0, .len = 1 } } } });
    try graph.nodes.append(allocator, .{ .source = source, .ty = null, .content = .{ .function_call = .{ .callee = @enumFromInt(0), .input = @enumFromInt(1) } } });
    try graph.node_refs.append(allocator, @enumFromInt(2));
    try graph.blocks.append(allocator, .{ .nodes = .{ .start = 0, .len = 1 }, .ret_val = null });
    var resolver: Resolver = .{
        .allocator = allocator,
        .graph = &graph,
        .modules = &.{},
        .offsets = &.{},
        .core = undefined,
    };
    try std.testing.expect(resolver.blockContains(@enumFromInt(0), @enumFromInt(0)));
    try graph.bindings.append(allocator, .{ .name = try graph.addString(allocator, "nested"), .source = source, .ty = @enumFromInt(0), .initialization = @enumFromInt(0), .mutability = .constant });
    try graph.nodes.append(allocator, .{ .source = source, .ty = null, .content = .{ .binding_declaration = @enumFromInt(0) } });
    try graph.node_refs.append(allocator, @enumFromInt(3));
    try graph.blocks.append(allocator, .{ .nodes = .{ .start = 1, .len = 1 }, .ret_val = null });
    try std.testing.expect(resolver.blockContains(@enumFromInt(1), @enumFromInt(0)));
    try graph.types.append(allocator, .{ .builtin = .Int32 });
    try graph.fields.append(allocator, .{ .name = try graph.addString(allocator, "result"), .ty = @enumFromInt(0), .source = source });
    try graph.functions.append(allocator, .{
        .declaration = @enumFromInt(0),
        .input = .{ .start = 0, .len = 0 },
        .output = .{ .start = 0, .len = 1 },
        .body = @enumFromInt(0),
    });
    try std.testing.expectError(error.ErrorPropagationRequiresErrableReturn, resolver.enclosingErrableType(@enumFromInt(0)));
}

test "error payload propagation requires a superset of reasons" {
    const allocator = std.testing.allocator;
    var graph: global_sg.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);
    const source: primitives.SourceRef = .{ .file_index = 0, .offset = 0 };
    try graph.variants.append(allocator, .{ .name = try graph.addString(allocator, "first"), .source = source, .value = 0 });
    try graph.variants.append(allocator, .{ .name = try graph.addString(allocator, "first"), .source = source, .value = 0 });
    try graph.variants.append(allocator, .{ .name = try graph.addString(allocator, "second"), .source = source, .value = 1 });
    try graph.types.append(allocator, .{ .builtin = .UInt8 });
    try graph.types.append(allocator, .{ .structural_choice = .{ .variants = .{ .start = 0, .len = 1 } } });
    try graph.types.append(allocator, .{ .structural_choice = .{ .variants = .{ .start = 1, .len = 2 } } });
    try graph.fields.append(allocator, .{ .name = try graph.addString(allocator, "reason"), .ty = @enumFromInt(1), .source = source });
    try graph.fields.append(allocator, .{ .name = try graph.addString(allocator, "trace"), .ty = @enumFromInt(0), .source = source });
    try graph.fields.append(allocator, .{ .name = try graph.addString(allocator, "reason"), .ty = @enumFromInt(2), .source = source });
    try graph.fields.append(allocator, .{ .name = try graph.addString(allocator, "trace"), .ty = @enumFromInt(0), .source = source });
    try graph.types.append(allocator, .{ .structural = .{ .fields = .{ .start = 0, .len = 2 } } });
    try graph.types.append(allocator, .{ .structural = .{ .fields = .{ .start = 2, .len = 2 } } });
    const resolver: Resolver = .{ .allocator = allocator, .graph = &graph, .modules = &.{}, .offsets = &.{}, .core = undefined };
    try std.testing.expect(resolver.errorPayloadCanPropagate(@enumFromInt(3), @enumFromInt(4)));
    try std.testing.expect(!resolver.errorPayloadCanPropagate(@enumFromInt(4), @enumFromInt(3)));

    const open_reasons: global_sg.GlobalTypeId = @enumFromInt(@as(u32, @intCast(graph.types.items.len)));
    try graph.types.append(allocator, .{ .inferred_choice = .{ .identity = 99, .kind = .reasons, .variants = .{ .start = @intCast(graph.variants.items.len), .len = 0 } } });
    const field_start: u32 = @intCast(graph.fields.items.len);
    try graph.fields.append(allocator, .{ .name = try graph.addString(allocator, "reason"), .ty = open_reasons, .source = source });
    try graph.fields.append(allocator, .{ .name = try graph.addString(allocator, "trace"), .ty = @enumFromInt(0), .source = source });
    const open_payload: global_sg.GlobalTypeId = @enumFromInt(@as(u32, @intCast(graph.types.items.len)));
    try graph.types.append(allocator, .{ .structural = .{ .fields = .{ .start = field_start, .len = 2 } } });
    var mutable_resolver = resolver;
    try std.testing.expect(mutable_resolver.errorPayloadCanPropagate(@enumFromInt(3), open_payload));
    try mutable_resolver.absorbErrorPayloadReasons(@enumFromInt(3), open_payload);
    try mutable_resolver.absorbErrorPayloadReasons(@enumFromInt(4), open_payload);
    try std.testing.expectEqual(@as(u32, 2), global_types.variants(&graph, open_reasons).?.len);
    try std.testing.expect(global_types.findVariant(&graph, open_reasons, "second") != null);
}

test "error context accepts only read-only character pointers" {
    const allocator = std.testing.allocator;
    var graph: global_sg.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);
    try graph.types.append(allocator, .{ .builtin = .Char });
    try graph.types.append(allocator, .{ .builtin = .UInt8 });
    try graph.types.append(allocator, .{ .pointer = .{ .child = @enumFromInt(0), .mutability = .read_only } });
    try graph.types.append(allocator, .{ .pointer = .{ .child = @enumFromInt(0), .mutability = .read_write } });
    try graph.types.append(allocator, .{ .pointer = .{ .child = @enumFromInt(1), .mutability = .read_only } });
    const resolver: Resolver = .{ .allocator = allocator, .graph = &graph, .modules = &.{}, .offsets = &.{}, .core = undefined };
    try std.testing.expect(resolver.validContextType(@enumFromInt(2)));
    try std.testing.expect(!resolver.validContextType(@enumFromInt(3)));
    try std.testing.expect(!resolver.validContextType(@enumFromInt(4)));
}
