const std = @import("std");
const syn = @import("../3_syntax/syntax_tree.zig");
const module_sg = @import("module_semantic_graph.zig");
const module_entities = @import("module_semantic_entities.zig");
const global_sg = @import("global_semantic_graph.zig");
const globalizer = @import("semantic_globalizer.zig");
const core_mod = @import("global_semantic_core.zig");
const types = @import("global_semantic_types.zig");
const primitives = @import("semantic_primitives.zig");

pub const Stats = struct {
    choices: u32 = 0,
    nullable: u32 = 0,
    matches: u32 = 0,
    array_loops: u32 = 0,
};

pub const Resolver = struct {
    allocator: std.mem.Allocator,
    graph: *global_sg.GlobalSemanticGraph,
    modules: []const module_sg.ModuleSemanticGraph,
    offsets: []const globalizer.Offsets,
    core: ?*core_mod.Resolver = null,
    stats: Stats = .{},

    pub fn materializeSugarTypes(self: *Resolver) !void {
        // Work over the original length: materializing nullable payload structs
        // appends helper types but those helpers are already final.
        const original_len = self.graph.types.items.len;
        for (0..original_len) |raw| {
            const id: global_sg.GlobalTypeId = @enumFromInt(@as(u32, @intCast(raw)));
            switch (self.graph.types.items[raw]) {
                .nullable => |child| try self.materializeNullable(id, child),
                .inferred_errable => |child| try self.materializeInferredErrable(id, child),
                else => {},
            }
        }
    }

    pub fn tryResolve(
        self: *Resolver,
        module_index: usize,
        module: *const module_sg.ModuleSemanticGraph,
        o: globalizer.Offsets,
        operation: module_entities.PendingOperation,
    ) !?bool {
        return switch (operation) {
            .resolve_call => |value| @as(?bool, try self.resolveChoiceTest(module, o, value)),
            .resolve_choice_literal => |value| @as(?bool, try self.resolveChoiceLiteral(module, o, value)),
            .resolve_choice_payload => |value| @as(?bool, try self.resolveChoicePayload(module, o, value)),
            .resolve_nullable_unwrap => |value| @as(?bool, try self.resolveNullableUnwrap(o, value)),
            .resolve_nullable_test => |value| @as(?bool, try self.resolveNullableTest(o, value)),
            .resolve_match => |value| @as(?bool, try self.resolveMatch(module, o, value)),
            .resolve_match_case => |value| @as(?bool, self.matchCaseAlreadyResolved(o, value)),
            .resolve_for_each => |value| @as(?bool, try self.resolveForEach(module_index, o, value)),
            else => null,
        };
    }

    pub fn annotateChoiceTests(self: *Resolver) void {
        for (self.graph.nodes.items) |*node| switch (node.content) {
            .if_statement => |*statement| {
                const condition = self.graph.nodes.items[@intFromEnum(statement.condition)];
                const comparison = switch (condition.content) {
                    .comparison => |value| value,
                    else => continue,
                };
                if (comparison.operator != .equal and comparison.operator != .not_equal) continue;
                const left = self.graph.nodes.items[@intFromEnum(comparison.left)];
                const right = self.graph.nodes.items[@intFromEnum(comparison.right)];
                const choice_ty = left.ty orelse continue;
                const variants = types.variants(self.graph, choice_ty) orelse continue;
                const tag = switch (right.content) {
                    .int_literal => |value| value,
                    else => continue,
                };
                var variant_id: ?global_sg.GlobalVariantId = null;
                for (0..variants.len) |index| {
                    const raw = variants.start + @as(u32, @intCast(index));
                    if (self.graph.variants.items[raw].value == tag) {
                        variant_id = @enumFromInt(raw);
                        break;
                    }
                }
                if (variant_id) |variant| statement.choice_test = .{
                    .choice_value = comparison.left,
                    .choice_type = choice_ty,
                    .variant = variant,
                    .then_has_variant = comparison.operator == .equal,
                };
            },
            else => {},
        };
    }

    fn materializeNullable(self: *Resolver, id: global_sg.GlobalTypeId, child: global_sg.GlobalTypeId) !void {
        const value_name = try self.graph.addString(self.allocator, "value");
        const none_name = try self.graph.addString(self.allocator, "none");
        const some_name = try self.graph.addString(self.allocator, "some");
        const source = self.syntheticSource();

        const field_start: u32 = @intCast(self.graph.fields.items.len);
        try self.graph.fields.append(self.allocator, .{
            .name = value_name,
            .ty = child,
            .source = source,
        });
        const payload_ty: global_sg.GlobalTypeId = @enumFromInt(@as(u32, @intCast(self.graph.types.items.len)));
        try self.graph.types.append(self.allocator, .{ .structural = .{
            .fields = .{ .start = field_start, .len = 1 },
        } });

        const variant_start: u32 = @intCast(self.graph.variants.items.len);
        try self.graph.variants.append(self.allocator, .{
            .name = none_name,
            .source = source,
            .value = 0,
        });
        try self.graph.variants.append(self.allocator, .{
            .name = some_name,
            .payload_type = payload_ty,
            .source = source,
            .value = 1,
        });
        self.graph.types.items[@intFromEnum(id)] = .{ .structural_choice = .{
            .variants = .{ .start = variant_start, .len = 2 },
        } };
        self.stats.nullable += 1;
    }

    fn materializeInferredErrable(self: *Resolver, id: global_sg.GlobalTypeId, child: global_sg.GlobalTypeId) !void {
        const ok_name = try self.graph.addString(self.allocator, "ok");
        const error_name = try self.graph.addString(self.allocator, "error");
        const any = try self.builtin(.Any);
        const source = self.syntheticSource();
        const variant_start: u32 = @intCast(self.graph.variants.items.len);
        try self.graph.variants.append(self.allocator, .{
            .name = ok_name,
            .payload_type = child,
            .source = source,
            .value = 0,
        });
        try self.graph.variants.append(self.allocator, .{
            .name = error_name,
            .payload_type = any,
            .source = source,
            .value = 1,
        });
        self.graph.types.items[@intFromEnum(id)] = .{ .inferred_choice = .{
            .identity = @intFromEnum(id),
            .kind = .errable,
            .variants = .{ .start = variant_start, .len = 2 },
        } };
    }

    fn resolveChoiceLiteral(self: *Resolver, module: *const module_sg.ModuleSemanticGraph, o: globalizer.Offsets, value: anytype) !bool {
        const reference = module.semantic.external_refs.items[@intFromEnum(value.option)];
        const name = module.text(reference.name);
        const payload = if (value.payload) |id| globalizer.globalNode(o, id) else null;
        var payload_ty = if (payload) |id| self.graph.nodes.items[@intFromEnum(id)].ty else null;
        const target = globalizer.globalNode(o, value.node);
        if (self.graph.nodes.items[@intFromEnum(target)].content == .int_literal) return true;
        const expected = if (value.expected_type) |id| globalizer.globalType(o, id) else self.graph.nodes.items[@intFromEnum(target)].ty;
        const choice_ty = self.findChoiceType(expected, name, payload_ty) orelse return false;
        const variant = types.findVariant(self.graph, choice_ty, name) orelse return false;
        if (payload) |payload_node| if (variant.variant.payload_type) |expected_payload| {
            if (self.core) |core| _ = core.coerceContextualValue(payload_node, expected_payload);
            payload_ty = self.graph.nodes.items[@intFromEnum(payload_node)].ty;
        };
        if (!self.payloadCompatible(variant.variant.payload_type, payload_ty)) return false;
        self.graph.nodes.items[@intFromEnum(target)] = .{
            .source = self.sourceFor(reference.source, o),
            .ty = choice_ty,
            .content = .{ .choice_literal = .{
                .choice_type = choice_ty,
                .variant = variant.id,
                .payload = payload,
            } },
        };
        self.stats.choices += 1;
        return true;
    }

    fn resolveChoiceTest(self: *Resolver, module: *const module_sg.ModuleSemanticGraph, o: globalizer.Offsets, value: anytype) !bool {
        const reference = module.semantic.external_refs.items[@intFromEnum(value.callee)];
        if (reference.module_path != null or reference.generic_arguments != null or
            !std.mem.eql(u8, module.text(reference.name), "is")) return false;
        const input = globalizer.globalNode(o, value.input);
        const literal = switch (self.graph.nodes.items[@intFromEnum(input)].content) {
            .struct_value_literal => |item| item,
            else => return false,
        };
        var choice_value: ?global_sg.GlobalNodeId = null;
        var tag_node: ?global_sg.GlobalNodeId = null;
        for (self.graph.value_fields.items[literal.fields.start..][0..literal.fields.len]) |field| {
            if (std.mem.eql(u8, self.graph.text(field.name), "value")) choice_value = field.value;
            if (std.mem.eql(u8, self.graph.text(field.name), "variant")) tag_node = field.value;
        }
        const choice = choice_value orelse return false;
        const choice_ty = self.graph.nodes.items[@intFromEnum(choice)].ty orelse return false;
        const tag = tag_node orelse return false;
        var option_name: ?[]const u8 = null;
        var option_source: ?primitives.SourceRef = null;
        for (module.semantic.pending_operations.items) |pending| switch (pending) {
            .resolve_choice_literal => |candidate| if (globalizer.globalNode(o, candidate.node) == tag) {
                const option = module.semantic.external_refs.items[@intFromEnum(candidate.option)];
                option_name = module.text(option.name);
                option_source = self.sourceFor(option.source, o);
                break;
            },
            else => {},
        };
        const variant = types.findVariant(self.graph, choice_ty, option_name orelse return false) orelse return false;
        self.graph.nodes.items[@intFromEnum(tag)] = .{
            .source = option_source.?,
            .ty = try self.builtin(.Int32),
            .content = .{ .int_literal = variant.variant.value },
        };
        const target = globalizer.globalNode(o, value.node);
        self.graph.nodes.items[@intFromEnum(target)] = .{
            .source = self.sourceFor(reference.source, o),
            .ty = try self.builtin(.Bool),
            .content = .{ .comparison = .{ .operator = .equal, .left = choice, .right = tag } },
        };
        return true;
    }

    fn resolveChoicePayload(self: *Resolver, module: *const module_sg.ModuleSemanticGraph, o: globalizer.Offsets, value: anytype) !bool {
        const source = globalizer.globalNode(o, value.value);
        const choice_ty = self.graph.nodes.items[@intFromEnum(source)].ty orelse return false;
        const name = module.text(value.option_name);
        const hit = types.findVariant(self.graph, choice_ty, name) orelse return false;
        const payload_ty = hit.variant.payload_type orelse return false;
        const target = globalizer.globalNode(o, value.node);
        self.graph.nodes.items[@intFromEnum(target)] = .{
            .source = self.graph.nodes.items[@intFromEnum(source)].source,
            .ty = payload_ty,
            .content = .{ .choice_payload_access = .{
                .value = source,
                .variant = hit.id,
                .payload_type = payload_ty,
            } },
        };
        self.stats.choices += 1;
        return true;
    }

    fn resolveNullableUnwrap(self: *Resolver, o: globalizer.Offsets, value: anytype) !bool {
        const nullable = globalizer.globalNode(o, value.nullable_value);
        const fallback = globalizer.globalNode(o, value.fallback_value);
        const choice_ty = self.graph.nodes.items[@intFromEnum(nullable)].ty orelse return false;
        const some = types.findVariant(self.graph, choice_ty, "some") orelse return false;
        const payload_ty = some.variant.payload_type orelse return false;
        const payload_fields = types.fields(self.graph, payload_ty) orelse return false;
        if (payload_fields.len == 0) return false;
        const result_ty = self.graph.fields.items[payload_fields.start].ty;
        const fallback_ty = self.graph.nodes.items[@intFromEnum(fallback)].ty orelse return false;
        if (!types.equal(self.graph, result_ty, fallback_ty) and !types.isBuiltin(self.graph, fallback_ty, .Any)) return false;
        const unwrap_id: global_sg.GlobalNullableUnwrapId = @enumFromInt(@as(u32, @intCast(self.graph.nullable_unwraps.items.len)));
        try self.graph.nullable_unwraps.append(self.allocator, .{
            .nullable_value = nullable,
            .fallback_value = fallback,
            .some_variant = some.id,
            .some_value_field_index = 0,
            .result_type = result_ty,
        });
        const target = globalizer.globalNode(o, value.node);
        self.graph.nodes.items[@intFromEnum(target)] = .{
            .source = self.graph.nodes.items[@intFromEnum(nullable)].source,
            .ty = result_ty,
            .content = .{ .nullable_unwrap_or = unwrap_id },
        };
        self.stats.nullable += 1;
        return true;
    }

    fn resolveNullableTest(self: *Resolver, o: globalizer.Offsets, value: anytype) !bool {
        const source = globalizer.globalNode(o, value.value);
        const choice_ty = self.graph.nodes.items[@intFromEnum(source)].ty orelse return false;
        const some = types.findVariant(self.graph, choice_ty, "some") orelse return false;
        const int_ty = try self.builtin(.Int32);
        const bool_ty = try self.builtin(.Bool);
        const tag_node: global_sg.GlobalNodeId = @enumFromInt(@as(u32, @intCast(self.graph.nodes.items.len)));
        try self.graph.nodes.append(self.allocator, .{
            .source = self.graph.nodes.items[@intFromEnum(source)].source,
            .ty = int_ty,
            .content = .{ .int_literal = some.variant.value },
        });
        const target = globalizer.globalNode(o, value.node);
        self.graph.nodes.items[@intFromEnum(target)] = .{
            .source = self.graph.nodes.items[@intFromEnum(source)].source,
            .ty = bool_ty,
            // Final codegen treats choice-vs-tag comparison as a tag compare;
            // `annotateChoiceTests` supplies the same fact to Safety.
            .content = .{ .comparison = .{
                .operator = .equal,
                .left = source,
                .right = tag_node,
            } },
        };
        self.stats.nullable += 1;
        return true;
    }

    fn resolveMatch(self: *Resolver, module: *const module_sg.ModuleSemanticGraph, o: globalizer.Offsets, value: anytype) !bool {
        const expression = globalizer.globalNode(o, value.value);
        const choice_ty = self.graph.nodes.items[@intFromEnum(expression)].ty orelse return false;
        const variants = types.variants(self.graph, choice_ty) orelse return false;
        const local_cases = module.semantic.node_refs.items[value.cases.start..][0..value.cases.len];
        const case_start: u32 = @intCast(self.graph.switch_cases.items.len);
        var seen: std.ArrayList(global_sg.GlobalVariantId) = .empty;
        defer seen.deinit(self.allocator);

        for (local_cases) |local_case_node| {
            const local_node = module.semantic.nodes.items[@intFromEnum(local_case_node)];
            const pending_id = switch (local_node) {
                .pending => |id| id,
                else => return false,
            };
            const pending = module.semantic.pending_operations.items[@intFromEnum(pending_id)];
            const case = switch (pending) {
                .resolve_match_case => |item| item,
                else => return false,
            };
            const option_ref = module.semantic.external_refs.items[@intFromEnum(case.option)];
            const option_name = module.text(option_ref.name);
            const hit = types.findVariant(self.graph, choice_ty, option_name) orelse return false;
            for (seen.items) |previous| if (previous == hit.id) return error.DuplicateMatchCase;
            try seen.append(self.allocator, hit.id);

            if (case.payload_binding) |local_binding| {
                const payload_ty = hit.variant.payload_type orelse return error.MatchPayloadOnPayloadlessVariant;
                const binding = globalizer.globalBinding(o, local_binding);
                self.graph.bindings.items[@intFromEnum(binding)].ty = try self.matchBindingType(payload_ty, case.mode);
            }

            const tag = try self.appendIntNode(hit.variant.value, self.sourceFor(option_ref.source, o));
            try self.graph.switch_cases.append(self.allocator, .{
                .value = tag,
                .variant = hit.id,
                .body = globalizer.globalBlock(o, case.body),
            });
            const global_case_node = globalizer.globalNode(o, case.node);
            self.graph.nodes.items[@intFromEnum(global_case_node)] = .{
                .source = self.sourceFor(option_ref.source, o),
                .ty = try self.builtin(.Void),
                .content = .{ .code_block = globalizer.globalBlock(o, case.body) },
            };
        }

        const switch_id: global_sg.GlobalSwitchId = @enumFromInt(@as(u32, @intCast(self.graph.switches.items.len)));
        try self.graph.switches.append(self.allocator, .{
            .expression = expression,
            .cases = .{ .start = case_start, .len = @intCast(local_cases.len) },
            .default_block = null,
            .exhaustive = local_cases.len == variants.len,
        });
        const target = globalizer.globalNode(o, value.node);
        self.graph.nodes.items[@intFromEnum(target)] = .{
            .source = self.graph.nodes.items[@intFromEnum(expression)].source,
            .ty = try self.builtin(.Void),
            .content = .{ .switch_statement = switch_id },
        };
        self.stats.matches += 1;
        return true;
    }

    fn matchCaseAlreadyResolved(self: *Resolver, o: globalizer.Offsets, value: anytype) bool {
        const node = self.graph.nodes.items[@intFromEnum(globalizer.globalNode(o, value.node))];
        return switch (node.content) {
            .code_block => true,
            else => false,
        };
    }

    fn resolveForEach(self: *Resolver, module_index: usize, o: globalizer.Offsets, value: anytype) !bool {
        _ = module_index;
        const iterable = globalizer.globalNode(o, value.iterable);
        const iterable_ty = self.graph.nodes.items[@intFromEnum(iterable)].ty orelse return false;
        const element_ty = types.arrayElement(self.graph, iterable_ty) orelse return false;
        const length = types.arrayLength(self.graph, iterable_ty) orelse return false;
        const uint_ty = try self.builtin(.UIntNative);
        const bool_ty = try self.builtin(.Bool);
        const source = self.graph.nodes.items[@intFromEnum(iterable)].source;

        const index_binding: global_sg.GlobalBindingId = @enumFromInt(@as(u32, @intCast(self.graph.bindings.items.len)));
        const index_name = try self.graph.addString(self.allocator, "$for_index");
        const zero = try self.appendTypedIntNode(0, uint_ty, source);
        try self.graph.bindings.append(self.allocator, .{
            .name = index_name,
            .source = source,
            .ty = uint_ty,
            .initialization = zero,
            .mutability = .variable,
        });
        const init = try self.appendNode(source, uint_ty, .{ .binding_declaration = index_binding });
        const index_use_cond = try self.appendNode(source, uint_ty, .{ .binding_use = index_binding });
        const length_node = try self.appendTypedIntNode(@intCast(length), uint_ty, source);
        const condition = try self.appendNode(source, bool_ty, .{ .comparison = .{
            .operator = .less_than,
            .left = index_use_cond,
            .right = length_node,
        } });

        const index_use_body = try self.appendNode(source, uint_ty, .{ .binding_use = index_binding });
        const access = try self.appendNode(source, element_ty, .{ .array_index = .{
            .array_ptr = iterable,
            .index = index_use_body,
            .element_type = element_ty,
            .array_type = iterable_ty,
        } });
        const item_binding = globalizer.globalBinding(o, value.binding);
        const assigned_ty = try self.forBindingType(element_ty, value.mode);
        self.graph.bindings.items[@intFromEnum(item_binding)].ty = assigned_ty;
        const item_value = switch (value.mode) {
            .value => access,
            .borrow, .mut_borrow => try self.appendAddress(access, element_ty, value.mode == .mut_borrow, source),
        };
        const item_assignment = try self.appendNode(source, assigned_ty, .{ .assignment = .{
            .binding = item_binding,
            .value = item_value,
        } });

        const old_body = self.graph.blocks.items[@intFromEnum(globalizer.globalBlock(o, value.body))];
        const old_nodes = self.graph.node_refs.items[old_body.nodes.start..][0..old_body.nodes.len];
        const body_start: u32 = @intCast(self.graph.node_refs.items.len);
        try self.graph.node_refs.append(self.allocator, item_assignment);
        try self.graph.node_refs.appendSlice(self.allocator, old_nodes);
        const body_id: global_sg.GlobalBlockId = @enumFromInt(@as(u32, @intCast(self.graph.blocks.items.len)));
        try self.graph.blocks.append(self.allocator, .{
            .nodes = .{ .start = body_start, .len = @intCast(old_nodes.len + 1) },
            .ret_val = old_body.ret_val,
        });

        const index_use_inc = try self.appendNode(source, uint_ty, .{ .binding_use = index_binding });
        const one = try self.appendTypedIntNode(1, uint_ty, source);
        const add = try self.appendNode(source, uint_ty, .{ .binary_operation = .{
            .operator = .addition,
            .left = index_use_inc,
            .right = one,
        } });
        const increment = try self.appendNode(source, uint_ty, .{ .assignment = .{
            .binding = index_binding,
            .value = add,
        } });

        const target = globalizer.globalNode(o, value.node);
        self.graph.nodes.items[@intFromEnum(target)] = .{
            .source = source,
            .ty = try self.builtin(.Void),
            .content = .{ .for_statement = .{
                .init = init,
                .condition = condition,
                .increment = increment,
                .body = body_id,
            } },
        };
        self.stats.array_loops += 1;
        return true;
    }

    fn findChoiceType(self: *Resolver, expected: ?global_sg.GlobalTypeId, name: []const u8, payload_ty: ?global_sg.GlobalTypeId) ?global_sg.GlobalTypeId {
        if (expected) |ty| {
            if (!types.isBuiltin(self.graph, ty, .Any)) {
                if (types.findVariant(self.graph, ty, name)) |hit|
                    if (self.payloadCompatible(hit.variant.payload_type, payload_ty)) return ty;
            }
        }
        var found: ?global_sg.GlobalTypeId = null;
        for (self.graph.types.items, 0..) |_, raw| {
            const ty: global_sg.GlobalTypeId = @enumFromInt(@as(u32, @intCast(raw)));
            const hit = types.findVariant(self.graph, ty, name) orelse continue;
            if (!self.payloadCompatible(hit.variant.payload_type, payload_ty)) continue;
            if (found != null and !types.equal(self.graph, found.?, ty)) return null;
            found = ty;
        }
        return found;
    }

    fn payloadCompatible(self: *Resolver, expected: ?global_sg.GlobalTypeId, actual: ?global_sg.GlobalTypeId) bool {
        if (expected == null or actual == null) return expected == null and actual == null;
        if (types.isBuiltin(self.graph, actual.?, .Any) or types.isBuiltin(self.graph, expected.?, .Any)) return true;
        return types.equal(self.graph, expected.?, actual.?);
    }

    fn matchBindingType(self: *Resolver, payload: global_sg.GlobalTypeId, mode: syn.MatchCaseMode) !global_sg.GlobalTypeId {
        return switch (mode) {
            .value, .move => payload,
            .borrow => self.pointer(payload, .read_only),
            .mut_borrow => self.pointer(payload, .read_write),
        };
    }

    fn forBindingType(self: *Resolver, payload: global_sg.GlobalTypeId, mode: syn.ForMode) !global_sg.GlobalTypeId {
        return switch (mode) {
            .value => payload,
            .borrow => self.pointer(payload, .read_only),
            .mut_borrow => self.pointer(payload, .read_write),
        };
    }

    fn pointer(self: *Resolver, child: global_sg.GlobalTypeId, mutability: syn.PointerMutability) !global_sg.GlobalTypeId {
        for (self.graph.types.items, 0..) |ty, raw| switch (ty) {
            .pointer => |value| if (value.child == child and value.mutability == mutability)
                return @enumFromInt(@as(u32, @intCast(raw))),
            else => {},
        };
        const id: global_sg.GlobalTypeId = @enumFromInt(@as(u32, @intCast(self.graph.types.items.len)));
        try self.graph.types.append(self.allocator, .{ .pointer = .{ .child = child, .mutability = mutability } });
        return id;
    }

    fn appendAddress(self: *Resolver, value: global_sg.GlobalNodeId, child: global_sg.GlobalTypeId, mutable: bool, source: primitives.SourceRef) !global_sg.GlobalNodeId {
        const ty = try self.pointer(child, if (mutable) .read_write else .read_only);
        return self.appendNode(source, ty, .{ .address_of = value });
    }

    fn appendIntNode(self: *Resolver, value: i64, source: primitives.SourceRef) !global_sg.GlobalNodeId {
        return self.appendTypedIntNode(value, try self.builtin(.Int32), source);
    }

    fn appendTypedIntNode(self: *Resolver, value: i64, ty: global_sg.GlobalTypeId, source: primitives.SourceRef) !global_sg.GlobalNodeId {
        return self.appendNode(source, ty, .{ .int_literal = value });
    }

    fn appendNode(self: *Resolver, source: primitives.SourceRef, ty: global_sg.GlobalTypeId, content: global_sg.Node.Content) !global_sg.GlobalNodeId {
        const id: global_sg.GlobalNodeId = @enumFromInt(@as(u32, @intCast(self.graph.nodes.items.len)));
        try self.graph.nodes.append(self.allocator, .{ .source = source, .ty = ty, .content = content });
        return id;
    }

    fn builtin(self: *Resolver, builtin_type: primitives.BuiltinType) !global_sg.GlobalTypeId {
        for (self.graph.types.items, 0..) |ty, raw| switch (ty) {
            .builtin => |value| if (value == builtin_type) return @enumFromInt(@as(u32, @intCast(raw))),
            else => {},
        };
        const id: global_sg.GlobalTypeId = @enumFromInt(@as(u32, @intCast(self.graph.types.items.len)));
        try self.graph.types.append(self.allocator, .{ .builtin = builtin_type });
        return id;
    }

    fn sourceFor(self: *Resolver, source: primitives.SourceRef, o: globalizer.Offsets) primitives.SourceRef {
        _ = self;
        return .{ .file_index = o.file_base + source.file_index, .offset = source.offset };
    }

    fn syntheticSource(self: *Resolver) primitives.SourceRef {
        _ = self;
        return .{ .file_index = 0, .offset = 0 };
    }
};

test "global control resolver materializes nullable into an explicit choice shape" {
    const allocator = std.testing.allocator;
    var graph: global_sg.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);
    try graph.types.append(allocator, .{ .builtin = .Int32 });
    try graph.types.append(allocator, .{ .nullable = @enumFromInt(0) });
    var resolver = Resolver{ .allocator = allocator, .graph = &graph, .modules = &.{}, .offsets = &.{} };
    try resolver.materializeSugarTypes();
    const variants = types.variants(&graph, @enumFromInt(1)).?;
    try std.testing.expectEqual(@as(u32, 2), variants.len);
    try std.testing.expectEqualStrings("some", graph.text(graph.variants.items[variants.start + 1].name));
}
