const std = @import("std");
const module_sg = @import("../module/graph.zig");
const module_entities = @import("../module/entities.zig");
const global_sg = @import("graph.zig");
const globalizer = @import("globalizer.zig");
const reachability = @import("reachability.zig");
const call_context = @import("call_context.zig");
const resolution = @import("resolution.zig");
const core_mod = @import("core.zig");
const global_types = @import("types.zig");
const primitives = @import("../primitives/schema.zig");

pub const Stats = struct {
    propagations: u32 = 0,
};

pub const Resolver = struct {
    const ReasonCandidate = struct { function: global_sg.GlobalFunctionId, declared: global_sg.GlobalTypeId };
    allocator: std.mem.Allocator,
    graph: *global_sg.GlobalSemanticGraph,
    modules: []const module_sg.ModuleSemanticGraph,
    offsets: []const globalizer.Offsets,
    core: *core_mod.Resolver,
    diagnostics: ?*@import("../../1_base/diagnostic.zig").Diagnostics = null,
    stats: Stats = .{},
    reason_candidates: std.ArrayList(ReasonCandidate) = .empty,
    collected_reasons: std.ArrayList(global_sg.GlobalVariantId) = .empty,

    pub fn deinit(self: *Resolver) void {
        self.reason_candidates.deinit(self.allocator);
        self.collected_reasons.deinit(self.allocator);
    }

    /// Compute effective reason summaries until recursive call chains stop
    /// changing. Open inferred signatures grow their declared reason choice;
    /// explicit signatures retain a separate subset summary.
    pub fn inferFunctionErrorReasons(self: *Resolver, reachable: ?*const reachability.FunctionSet) !bool {
        // Signatures can change between global rounds. Rebuild this list on
        // every invocation, but resolve each signature only once while its
        // reason summaries converge. Only scratch capacity survives the pass.
        const measurement = if (self.core.scan_profile) |profile| profile.begin(.error_candidates) else null;
        var profile_changed = false;
        defer if (measurement) |m| m.finish(profile_changed);
        self.reason_candidates.clearRetainingCapacity();
        for (self.graph.functions.items, 0..) |function, raw| {
            if (measurement) |m| m.visit(1);
            const id: global_sg.GlobalFunctionId = @enumFromInt(raw);
            // A newly specialized open signature may be inspected before its
            // call joins the execution graph. Preserve those signature roots.
            if (reachable) |set| if (!set.contains(id) and !function.flags.uses_inferred_error_reasons) continue;
            const declared = self.functionReasonType(function) orelse {
                try self.graph.setInferredErrorReasons(self.allocator, id, null);
                continue;
            };
            if (function.body == null) {
                if (function.inferred_error_reasons == null) try self.graph.setInferredErrorReasons(self.allocator, id, declared);
                continue;
            }
            try self.reason_candidates.append(self.allocator, .{ .function = id, .declared = declared });
        }
        var any_changed = false;
        var round: usize = 0;
        while (round <= self.graph.functions.items.len) : (round += 1) {
            var changed = false;
            for (self.reason_candidates.items) |candidate| {
                if (try self.inferOne(candidate.function, candidate.declared)) changed = true;
            }
            any_changed = any_changed or changed;
            if (!changed) break;
        }
        profile_changed = any_changed;
        return any_changed;
    }

    fn inferOne(self: *Resolver, function_id: global_sg.GlobalFunctionId, declared: global_sg.GlobalTypeId) !bool {
        const function = self.graph.function(function_id);
        const body = function.body.?;
        const collected = &self.collected_reasons;
        collected.clearRetainingCapacity();
        // Output defaults execute before the body and can supply its result
        // unchanged. Include their reasons just like explicit assignments.
        for (self.graph.binding_refs.items[function.output_bindings.start..][0..function.output_bindings.len]) |binding| {
            if (self.graph.binding(binding).initialization) |value| {
                try self.markErrableNode(value, collected);
                try self.collectNode(function, value, collected);
            }
        }
        try self.collectBlock(function, body, collected);

        if (function.flags.uses_inferred_error_reasons) {
            const changed = try self.replaceOpenReasons(declared, collected.items);
            try self.graph.setInferredErrorReasons(self.allocator, function_id, declared);
            return changed;
        }
        // Explicit contracts expose only their declared reasons. Nested
        // Errable expressions can contribute broader provisional sets; compare
        // the projected summary, not those discarded reasons, or each fixed
        // point round republishes an identical subset forever.
        const declared_range = global_types.variants(self.graph, declared) orelse return false;
        var retained: usize = 0;
        for (collected.items) |id| {
            var present = false;
            for (0..declared_range.len) |offset| {
                const candidate: global_sg.GlobalVariantId = @enumFromInt(declared_range.start + @as(u32, @intCast(offset)));
                if (containsVariant(self.graph, &.{candidate}, id)) {
                    present = true;
                    break;
                }
            }
            if (present) {
                collected.items[retained] = id;
                retained += 1;
            }
        }
        collected.shrinkRetainingCapacity(retained);
        if (self.sameReasonSet(function.inferred_error_reasons, collected.items)) return false;
        try self.graph.setInferredErrorReasons(self.allocator, function_id, try self.makeReasonSubset(declared, collected.items));
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
        if (block.ret_val) |node| {
            try self.markErrableNode(node, out);
            // A value block can return an expression that is not among its
            // statements. Its nested propagations still execute in this function.
            var listed = false;
            for (self.graph.node_refs.items[block.nodes.start..][0..block.nodes.len]) |statement| {
                if (statement == node) {
                    listed = true;
                    break;
                }
            }
            if (!listed) try self.collectNode(function, node, out);
        }
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
            .binding_declaration => |id| if (self.graph.binding(id).initialization) |child| try self.collectNode(function, child, out),
            .move_value, .address_of => |child| try self.collectNode(function, child, out),
            .function_call => |call| {
                if (call.callee_value) |value| try self.collectNode(function, value, out);
                try self.collectNode(function, call.input, out);
            },
            .virtualize => |id| try self.collectNode(function, self.graph.virtualizes.items[@intFromEnum(id)].value, out),
            .virtual_call => |id| {
                const call = self.graph.virtual_calls.items[@intFromEnum(id)];
                try self.collectNode(function, call.handle, out);
                try self.collectNode(function, call.input, out);
            },
            .code_block, .value_sequence, .replacement => |block| try self.collectBlock(function, block, out),
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
                try self.collectNode(function, value.condition, out);
                try self.collectBlock(function, value.then_block, out);
                if (value.else_block) |block| try self.collectBlock(function, block, out);
            },
            .while_statement => |value| {
                try self.collectNode(function, value.condition, out);
                try self.collectBlock(function, value.body, out);
            },
            .for_statement => |value| {
                if (value.init) |child| try self.collectNode(function, child, out);
                try self.collectNode(function, value.condition, out);
                if (value.increment) |child| try self.collectNode(function, child, out);
                try self.collectBlock(function, value.body, out);
            },
            .switch_statement => |id| {
                const value = self.graph.switches.items[@intFromEnum(id)];
                try self.collectNode(function, value.expression, out);
                for (self.graph.switch_cases.items[value.cases.start..][0..value.cases.len]) |case| try self.collectBlock(function, case.body, out);
                if (value.default_block) |block| try self.collectBlock(function, block, out);
            },
            .dereference => |value| try self.collectNode(function, value.pointer, out),
            .pointer_assignment => |value| {
                try self.collectNode(function, value.pointer, out);
                try self.collectNode(function, value.value, out);
            },

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

    // TODO: Keep reason literals contextual when inferred outputs combine
    // local errors with propagated imported errors. Explicit reason sets avoid
    // stale provisional reason identities in package wrappers.
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
        var completed = self.graph.semanticType(ty);
        completed.inferred_choice.variants = .{ .start = start, .len = @intCast(wanted.len) };
        try self.graph.resolveType(self.allocator, ty, completed);
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
        _ = module_index;
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
            try self.graph.setNodeType(self.allocator, expected, reason.field.ty);
            return .deferred;
        }
        const expected_literal = switch (self.graph.node(expected).content) {
            .choice_literal => |choice| choice,
            else => return .deferred,
        };
        if (!global_types.equal(self.graph, expected_literal.choice_type, reason.field.ty)) return error.IncompatibleExpectedErrorReason;

        // Supply the expected literal's context, then let the ordinary core
        // function perform matching, diagnostics, tracing and cleanup. Neither
        // backend needs a testing-specific execution operation.
        return .not_applicable;
    }

    /// Contextual literal typing can finish a nominal payload after propagation
    /// first resolves. Keep transparent result unwrapping tied to the final
    /// payload identity rather than retaining its provisional structural shape.
    pub fn refreshPropagationResults(self: *Resolver) !bool {
        if (self.graph.error_propagations.items.len == 0) return false;
        var changed = false;
        const measurement = if (self.core.scan_profile) |profile| profile.begin(.error_results) else null;
        defer if (measurement) |m| m.finish(changed);
        for (self.graph.nodes.items, 0..) |node, raw| {
            switch (node.content) {
                .error_propagation => |id| {
                    const propagation = self.graph.error_propagations.items[@intFromEnum(id)];
                    const field_type = unwrapSingleField(self.graph, propagation.ok_payload_type);
                    const index: ?u32 = if (field_type != null) 0 else null;
                    if (index != propagation.ok_value_field_index) {
                        var updated = propagation;
                        updated.ok_value_field_index = index;
                        try self.graph.setErrorPropagation(self.allocator, id, updated);
                        changed = true;
                    }
                    const result_type = field_type orelse propagation.ok_payload_type;
                    if (node.ty != result_type) {
                        try self.graph.setNodeType(self.allocator, @enumFromInt(raw), result_type);
                        changed = true;
                    }
                },
                else => {},
            }
        }
        return changed;
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
        const source: primitives.SourceRef = .{
            .file_index = o.file_base + value.source.file_index,
            .offset = value.source.offset,
        };
        try self.requireCompatibleErrorPayload(error_payload, propagated_error_payload, source);
        try self.absorbErrorPayloadReasons(error_payload, propagated_error_payload);
        const empty = try self.graph.addString(self.allocator, "");
        const cleanup: primitives.Range(global_sg.GlobalNodeId) = .{ .start = @intCast(self.graph.node_refs.items.len), .len = 0 };

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
        try self.graph.setNode(self.allocator, target, .{
            .source = source,
            .ty = result_ty,
            .content = .{ .error_propagation = id },
        });
        self.stats.propagations += 1;

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

    pub fn requireCompatibleErrorPayload(self: *const Resolver, source: global_sg.GlobalTypeId, target: global_sg.GlobalTypeId, location: primitives.SourceRef) !void {
        if (self.errorPayloadCanPropagate(source, target)) return;
        if (self.diagnostics) |diagnostics| {
            const from_trace = global_types.findField(self.graph, source, "tracer") != null;
            const to_trace = global_types.findField(self.graph, target, "tracer") != null;
            const message = if (from_trace and !to_trace)
                "cannot discard an error trace during propagation; return a traced result"
            else if (!from_trace and to_trace)
                "propagating a plain error into a traced result requires '!! context'"
            else
                "propagated error reasons are not supported by the function result";
            try diagnostics.add(@import("source_location.zig").location(self.graph, diagnostics, location), .semantic, "{s}", .{message});
            return error.Reported;
        }
        return error.IncompatibleErrorPayload;
    }

    pub fn errorPayloadCanPropagate(self: *const Resolver, source: global_sg.GlobalTypeId, target: global_sg.GlobalTypeId) bool {
        if (global_types.equal(self.graph, source, target)) return true;
        const source_reason = global_types.findField(self.graph, source, "reason") orelse return false;
        const target_reason = global_types.findField(self.graph, target, "reason") orelse return false;
        const source_trace = global_types.findField(self.graph, source, "tracer");
        const target_trace = global_types.findField(self.graph, target, "tracer");
        if (source_trace) |trace| {
            const target_field = target_trace orelse return false;
            if (!global_types.equal(self.graph, trace.field.ty, target_field.field.ty)) return false;
        } else if (target_trace != null) return false;
        // Widening transports exactly the error protocol fields. Unrelated
        // user fields cannot be silently discarded or left uninitialized.
        const source_fields = global_types.fields(self.graph, source) orelse return false;
        const target_fields = global_types.fields(self.graph, target) orelse return false;
        const expected_fields: u32 = if (source_trace != null) 2 else 1;
        if (source_fields.len != expected_fields or target_fields.len != expected_fields) return false;
        const source_variants = global_types.variants(self.graph, source_reason.field.ty) orelse return false;
        const open_reasons = if (self.graph.resolvedSemanticType(target_reason.field.ty)) |ty| switch (ty) {
            .inferred_choice => |choice| choice.kind == .reasons,
            else => false,
        } else false;
        for (self.graph.variants.items[source_variants.start..][0..source_variants.len]) |variant| {
            if (variant.payload_type != null) return false;
            const matching = global_types.findVariant(self.graph, target_reason.field.ty, self.graph.text(variant.name)) orelse {
                if (open_reasons) continue;
                return false;
            };
            if (matching.variant.payload_type != null) return false;
        }
        return true;
    }

    pub fn absorbErrorPayloadReasons(self: *Resolver, source: global_sg.GlobalTypeId, target: global_sg.GlobalTypeId) !void {
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
        var completed = self.graph.semanticType(target_id);
        completed.inferred_choice.variants = .{
            .start = new_start,
            .len = target_choice.variants.len + @as(u32, @intCast(additions.items.len)),
        };
        try self.graph.resolveType(self.allocator, target_id, completed);
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
            .function_call => |call| (if (call.callee_value) |value| self.nodeContains(value, target) else false) or self.nodeContains(call.input, target),
            .virtual_call => |id| blk: {
                const call = self.graph.virtual_calls.items[@intFromEnum(id)];
                break :blk self.nodeContains(call.handle, target) or self.nodeContains(call.input, target);
            },
            .virtualize => |id| self.nodeContains(self.graph.virtualizes.items[@intFromEnum(id)].value, target),
            .code_block, .value_sequence, .replacement => |child| self.blockContains(child, target),
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
            .error_propagation => |id| self.nodeContains(self.graph.error_propagations.items[@intFromEnum(id)].errable_value, target),
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
    // Only the anonymous one-field result shape is transparent. A named
    // one-field struct is still a distinct value when propagated from Errable.
    const semantic = graph.resolvedSemanticType(ty) orelse return null;
    if (semantic != .structural) return null;
    const fields = global_types.fields(graph, ty) orelse return null;
    if (fields.len != 1) return null;
    return graph.fields.items[fields.start].ty;
}

fn singleFieldIndex(graph: *const global_sg.GlobalSemanticGraph, ty: global_sg.GlobalTypeId) ?u32 {
    const semantic = graph.resolvedSemanticType(ty) orelse return null;
    if (semantic != .structural) return null;
    const fields = global_types.fields(graph, ty) orelse return null;
    return if (fields.len == 1) 0 else null;
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
}

test "error result types refresh when transparent payload fields change without changing their index" {
    const a = std.testing.allocator;
    var graph: global_sg.GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    const source: primitives.SourceRef = .{ .file_index = 0, .offset = 0 };
    const integer: global_sg.GlobalTypeId = @enumFromInt(0);
    const boolean: global_sg.GlobalTypeId = @enumFromInt(1);
    const payload: global_sg.GlobalTypeId = @enumFromInt(2);
    try graph.types.appendSlice(a, &.{
        .{ .builtin = .Int32 },
        .{ .builtin = .Bool },
        .{ .structural = .{ .fields = .{ .start = 0, .len = 1 } } },
    });
    for ([_]global_sg.GlobalTypeId{ integer, boolean }) |ty|
        try graph.fields.append(a, .{ .name = .{ .start = 0, .len = 0 }, .source = source, .ty = ty });
    var propagation = std.mem.zeroes(global_sg.ErrorPropagation);
    propagation.ok_payload_type = payload;
    propagation.ok_value_field_index = 0;
    try graph.error_propagations.append(a, propagation);
    try graph.nodes.appendSlice(a, &.{
        .{ .source = source, .ty = integer, .content = .{ .error_propagation = @enumFromInt(0) } },
    });
    var core: core_mod.Resolver = .{ .allocator = a, .graph = &graph, .modules = &.{}, .offsets = &.{} };
    defer core.deinit();
    var resolver: Resolver = .{ .allocator = a, .graph = &graph, .modules = &.{}, .offsets = &.{}, .core = &core };
    defer resolver.deinit();
    try std.testing.expect(!try resolver.refreshPropagationResults());
    var transaction = graph.beginTransaction(a);
    defer transaction.deinit();
    try graph.resolveType(a, payload, .{ .structural = .{ .fields = .{ .start = 1, .len = 1 } } });
    try std.testing.expect(try resolver.refreshPropagationResults());
    for (graph.nodes.items) |node| try std.testing.expectEqual(boolean, node.ty.?);
    try std.testing.expectEqual(@as(?u32, 0), graph.error_propagations.items[0].ok_value_field_index);
    try std.testing.expect(!try resolver.refreshPropagationResults());
    transaction.rollback();
    for (graph.nodes.items) |node| try std.testing.expectEqual(integer, node.ty.?);
    try std.testing.expect(!try resolver.refreshPropagationResults());
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
    try graph.fields.append(allocator, .{ .name = try graph.addString(allocator, "tracer"), .ty = @enumFromInt(0), .source = source });
    try graph.fields.append(allocator, .{ .name = try graph.addString(allocator, "reason"), .ty = @enumFromInt(2), .source = source });
    try graph.fields.append(allocator, .{ .name = try graph.addString(allocator, "tracer"), .ty = @enumFromInt(0), .source = source });
    try graph.types.append(allocator, .{ .structural = .{ .fields = .{ .start = 0, .len = 2 } } });
    try graph.types.append(allocator, .{ .structural = .{ .fields = .{ .start = 2, .len = 2 } } });
    const resolver: Resolver = .{ .allocator = allocator, .graph = &graph, .modules = &.{}, .offsets = &.{}, .core = undefined };
    try std.testing.expect(resolver.errorPayloadCanPropagate(@enumFromInt(3), @enumFromInt(4)));
    try std.testing.expect(!resolver.errorPayloadCanPropagate(@enumFromInt(4), @enumFromInt(3)));

    const open_reasons: global_sg.GlobalTypeId = @enumFromInt(@as(u32, @intCast(graph.types.items.len)));
    try graph.types.append(allocator, .{ .inferred_choice = .{ .identity = 99, .kind = .reasons, .variants = .{ .start = @intCast(graph.variants.items.len), .len = 0 } } });
    const field_start: u32 = @intCast(graph.fields.items.len);
    try graph.fields.append(allocator, .{ .name = try graph.addString(allocator, "reason"), .ty = open_reasons, .source = source });
    try graph.fields.append(allocator, .{ .name = try graph.addString(allocator, "tracer"), .ty = @enumFromInt(0), .source = source });
    const open_payload: global_sg.GlobalTypeId = @enumFromInt(@as(u32, @intCast(graph.types.items.len)));
    try graph.types.append(allocator, .{ .structural = .{ .fields = .{ .start = field_start, .len = 2 } } });
    var mutable_resolver = resolver;
    try std.testing.expect(mutable_resolver.errorPayloadCanPropagate(@enumFromInt(3), open_payload));
    try mutable_resolver.absorbErrorPayloadReasons(@enumFromInt(3), open_payload);
    try mutable_resolver.absorbErrorPayloadReasons(@enumFromInt(4), open_payload);
    try std.testing.expectEqual(@as(u32, 2), global_types.variants(&graph, open_reasons).?.len);
    try std.testing.expect(global_types.findVariant(&graph, open_reasons, "second") != null);

    // Remapping cannot silently drop custom fields or a reason payload.
    try graph.fields.append(allocator, .{ .name = try graph.addString(allocator, "extra"), .ty = @enumFromInt(0), .source = source });
    const extended_payload: global_sg.GlobalTypeId = @enumFromInt(@as(u32, @intCast(graph.types.items.len)));
    try graph.types.append(allocator, .{ .structural = .{ .fields = .{ .start = field_start, .len = 3 } } });
    try std.testing.expect(!mutable_resolver.errorPayloadCanPropagate(extended_payload, open_payload));
    try std.testing.expect(!mutable_resolver.errorPayloadCanPropagate(open_payload, extended_payload));
    graph.variants.items[0].payload_type = @enumFromInt(0);
    try std.testing.expect(!mutable_resolver.errorPayloadCanPropagate(@enumFromInt(3), open_payload));
    // Identical payload types need no remapping and retain every field.
    try std.testing.expect(mutable_resolver.errorPayloadCanPropagate(extended_payload, extended_payload));
}

test "error inference reuses scratch storage without retaining prior reasons" {
    const allocator = std.testing.allocator;
    var graph: global_sg.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);
    const source: primitives.SourceRef = .{ .file_index = 0, .offset = 0 };
    try graph.variants.append(allocator, .{ .name = try graph.addString(allocator, "first"), .payload_type = null, .source = source, .value = 0 });
    try graph.variants.append(allocator, .{ .name = try graph.addString(allocator, "second"), .payload_type = null, .source = source, .value = 0 });
    for ([_]primitives.Range(global_sg.GlobalVariantId){ .{ .start = 0, .len = 2 }, .{ .start = 0, .len = 1 }, .{ .start = 1, .len = 1 } }) |variants|
        try graph.types.append(allocator, .{ .structural_choice = .{ .variants = variants } });
    const Helper = struct {
        fn errable(g: *global_sg.GlobalSemanticGraph, a: std.mem.Allocator, reason: global_sg.GlobalTypeId) !global_sg.GlobalTypeId {
            const fields: u32 = @intCast(g.fields.items.len);
            try g.fields.append(a, .{ .name = try g.addString(a, "reason"), .ty = reason, .source = source });
            const payload: global_sg.GlobalTypeId = @enumFromInt(g.types.items.len);
            try g.types.append(a, .{ .structural = .{ .fields = .{ .start = fields, .len = 1 } } });
            const variants: u32 = @intCast(g.variants.items.len);
            try g.variants.append(a, .{ .name = try g.addString(a, "error"), .payload_type = payload, .source = source, .value = 0 });
            const result: global_sg.GlobalTypeId = @enumFromInt(g.types.items.len);
            try g.types.append(a, .{ .structural_choice = .{ .variants = .{ .start = variants, .len = 1 } } });
            return result;
        }
    };
    const declared = try Helper.errable(&graph, allocator, @enumFromInt(0));
    const output: u32 = @intCast(graph.fields.items.len);
    try graph.fields.append(allocator, .{ .name = try graph.addString(allocator, "result"), .ty = declared, .source = source });
    for ([_]global_sg.GlobalTypeId{ @enumFromInt(1), @enumFromInt(2) }, 0..) |reason, index| {
        const ty = try Helper.errable(&graph, allocator, reason);
        try graph.nodes.append(allocator, .{ .source = source, .ty = ty, .content = .{ .choice_literal = .{ .choice_type = ty, .variant = global_types.findVariant(&graph, ty, "error").?.id, .payload = null } } });
        try graph.blocks.append(allocator, .{ .nodes = .{ .start = 0, .len = 0 }, .ret_val = @enumFromInt(index) });
        try graph.functions.append(allocator, .{ .declaration = @enumFromInt(index), .input = .{ .start = 0, .len = 0 }, .output = .{ .start = output, .len = 1 }, .body = @enumFromInt(index), .inferred_error_reasons = reason });
    }
    var failing = std.testing.FailingAllocator.init(allocator, .{});
    var core: core_mod.Resolver = .{ .allocator = failing.allocator(), .graph = &graph, .modules = &.{}, .offsets = &.{} };
    defer core.deinit();
    var resolver: Resolver = .{ .allocator = failing.allocator(), .graph = &graph, .modules = &.{}, .offsets = &.{}, .core = &core };
    defer resolver.deinit();
    var reachable = reachability.FunctionSet.init(allocator);
    defer reachable.deinit();
    failing.fail_index = 0;
    try std.testing.expect(!try resolver.inferFunctionErrorReasons(&reachable));
    failing.fail_index = std.math.maxInt(usize);
    // Open signatures can be needed before a newly specialized call is reached.
    graph.functions.items[0].flags.uses_inferred_error_reasons = true;
    graph.functions.items[0].inferred_error_reasons = null;
    graph.types.items[0] = .{ .inferred_choice = .{ .identity = 0, .kind = .reasons, .variants = .{ .start = 0, .len = 1 } } };
    try std.testing.expect(!try resolver.inferFunctionErrorReasons(&reachable));
    try std.testing.expectEqual(@as(?global_sg.GlobalTypeId, @enumFromInt(0)), graph.functions.items[0].inferred_error_reasons);
    graph.functions.items[0].flags.uses_inferred_error_reasons = false;
    graph.functions.items[0].inferred_error_reasons = @enumFromInt(1);
    graph.types.items[0] = .{ .structural_choice = .{ .variants = .{ .start = 0, .len = 2 } } };
    try std.testing.expect(!try resolver.inferFunctionErrorReasons(null));
    failing.fail_index = failing.alloc_index;
    try std.testing.expect(!try resolver.inferFunctionErrorReasons(null));
    failing.fail_index = std.math.maxInt(usize);
    graph.blocks.items[0].ret_val = @enumFromInt(1);
    try std.testing.expect(try resolver.inferFunctionErrorReasons(null));
    const inferred = graph.functions.items[0].inferred_error_reasons.?;
    try std.testing.expect(global_types.findVariant(&graph, inferred, "second") != null);
    try std.testing.expect(global_types.findVariant(&graph, inferred, "first") == null);
    // A later global round can finish or change a signature in place.
    graph.fields.items[output].ty = graph.nodes.items[0].ty.?;
    try std.testing.expect(try resolver.inferFunctionErrorReasons(null));
    for (graph.functions.items) |function|
        try std.testing.expectEqual(@as(u32, 0), global_types.variants(&graph, function.inferred_error_reasons.?).?.len);
}

test "error inference visits propagation in a value block result" {
    const a = std.testing.allocator;
    var graph: global_sg.GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    const source: primitives.SourceRef = .{ .file_index = 0, .offset = 0 };
    try graph.variants.append(a, .{ .name = try graph.addString(a, "failure"), .source = source, .value = 0 });
    try graph.types.append(a, .{ .structural_choice = .{ .variants = .{ .start = 0, .len = 1 } } });
    try graph.fields.append(a, .{ .name = try graph.addString(a, "reason"), .source = source, .ty = @enumFromInt(0) });
    try graph.types.append(a, .{ .structural = .{ .fields = .{ .start = 0, .len = 1 } } });
    try graph.variants.append(a, .{ .name = try graph.addString(a, "error"), .source = source, .value = 0, .payload_type = @enumFromInt(1) });
    try graph.types.append(a, .{ .structural_choice = .{ .variants = .{ .start = 1, .len = 1 } } });
    try graph.nodes.append(a, .{ .source = source, .ty = @enumFromInt(2), .content = .{ .bool_literal = true } });
    var propagation = std.mem.zeroes(global_sg.ErrorPropagation);
    propagation.errable_value = @enumFromInt(0);
    try graph.error_propagations.append(a, propagation);
    try graph.nodes.append(a, .{ .source = source, .ty = null, .content = .{ .error_propagation = @enumFromInt(0) } });
    try graph.blocks.append(a, .{ .nodes = .{ .start = 0, .len = 0 }, .ret_val = @enumFromInt(1) });
    var resolver: Resolver = .{ .allocator = a, .graph = &graph, .modules = &.{}, .offsets = &.{}, .core = undefined };
    defer resolver.deinit();
    var reasons: std.ArrayList(global_sg.GlobalVariantId) = .empty;
    defer reasons.deinit(a);
    const function: global_sg.Function = .{ .declaration = @enumFromInt(0), .input = .{ .start = 0, .len = 0 }, .output = .{ .start = 0, .len = 0 }, .body = @enumFromInt(0) };
    try resolver.collectBlock(function, @enumFromInt(0), &reasons);
    try std.testing.expectEqualSlices(global_sg.GlobalVariantId, &.{@enumFromInt(0)}, reasons.items);
}
