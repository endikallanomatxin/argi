from pathlib import Path

# Synthetic semantic calls (used by desugaring) should share the same ordinary
# function selection as source calls, without inventing a syntax ExternalRef.
core = Path("src/4_semantics/global/core.zig")
text = core.read_text()
old = '''    pub fn matchFunctionByName(
        self: *Resolver,
        current_module: usize,
        reference: module_entities.ExternalRef,
        input_node: global_sg.GlobalNodeId,
    ) !FunctionMatch {
        const module_filter = if (reference.module_path) |path|
            try self.findModuleForQualifier(current_module, self.modules[current_module].text(path))
        else
            null;
        const name = self.modules[current_module].text(reference.name);
        var best: ?global_sg.GlobalFunctionId = null;
'''
new = '''    pub fn matchFunctionByName(
        self: *Resolver,
        current_module: usize,
        reference: module_entities.ExternalRef,
        input_node: global_sg.GlobalNodeId,
    ) !FunctionMatch {
        const module_filter = if (reference.module_path) |path|
            try self.findModuleForQualifier(current_module, self.modules[current_module].text(path))
        else
            null;
        return self.matchFunctionNamed(current_module, self.modules[current_module].text(reference.name), module_filter, input_node);
    }

    /// Resolve a compiler-synthesized, unqualified call using the same ordinary
    /// overload rules as a source call. Semantic sugar must not manufacture a
    /// module-local ExternalRef merely to enter dispatch.
    pub fn matchUnqualifiedFunctionByName(
        self: *Resolver,
        current_module: usize,
        name: []const u8,
        input_node: global_sg.GlobalNodeId,
    ) !FunctionMatch {
        return self.matchFunctionNamed(current_module, name, null, input_node);
    }

    fn matchFunctionNamed(
        self: *Resolver,
        current_module: usize,
        name: []const u8,
        module_filter: ?global_sg.GlobalModuleId,
        input_node: global_sg.GlobalNodeId,
    ) !FunctionMatch {
        var best: ?global_sg.GlobalFunctionId = null;
'''
if text.count(old) != 1:
    raise RuntimeError(f"ordinary synthetic dispatch anchor changed: {text.count(old)}")
core.write_text(text.replace(old, new, 1))

# Do the same for parameterized calls. The implementation below remains the
# single generic overload/inference engine; source calls and semantic sugar
# only differ in how they provide the name/module filter.
generic_functions = Path("src/4_semantics/global/generic_functions.zig")
text = generic_functions.read_text()
old = '''    fn resolveImplicitGenericFunction(
        self: *Resolver,
        current_module: usize,
        module: *const module_sg.ModuleSemanticGraph,
        reference: module_entities.ExternalRef,
        input: global_sg.GlobalNodeId,
    ) !global_sg.GlobalFunctionId {
        const literal = switch (self.graph.nodes.items[@intFromEnum(input)].content) {
            .struct_value_literal => |literal| literal,
            else => return error.MissingGenericInputType,
        };
        const module_filter = if (reference.module_path) |path|
            try self.core.findModuleForQualifier(current_module, module.text(path))
        else
            null;
        var best: ?global_sg.GlobalDeclId = null;
'''
new = '''    fn resolveImplicitGenericFunction(
        self: *Resolver,
        current_module: usize,
        module: *const module_sg.ModuleSemanticGraph,
        reference: module_entities.ExternalRef,
        input: global_sg.GlobalNodeId,
    ) !global_sg.GlobalFunctionId {
        const module_filter = if (reference.module_path) |path|
            try self.core.findModuleForQualifier(current_module, module.text(path))
        else
            null;
        return self.resolveImplicitGenericFunctionFiltered(
            current_module,
            module.text(reference.name),
            module_filter,
            input,
        );
    }

    /// Compiler-generated calls participate in exactly the same generic
    /// inference and declaration-specificity ordering as source calls.
    pub fn resolveImplicitGenericFunctionByName(
        self: *Resolver,
        current_module: usize,
        name: []const u8,
        input: global_sg.GlobalNodeId,
    ) !global_sg.GlobalFunctionId {
        return self.resolveImplicitGenericFunctionFiltered(current_module, name, null, input);
    }

    fn resolveImplicitGenericFunctionFiltered(
        self: *Resolver,
        current_module: usize,
        name: []const u8,
        module_filter: ?global_sg.GlobalModuleId,
        input: global_sg.GlobalNodeId,
    ) !global_sg.GlobalFunctionId {
        const literal = switch (self.graph.nodes.items[@intFromEnum(input)].content) {
            .struct_value_literal => |literal| literal,
            else => return error.MissingGenericInputType,
        };
        var best: ?global_sg.GlobalDeclId = null;
'''
if text.count(old) != 1:
    raise RuntimeError(f"generic synthetic dispatch anchor changed: {text.count(old)}")
text = text.replace(old, new, 1)
old = '''                if (!std.mem.eql(u8, self.graph.text(self.graph.declarations.items[@intFromEnum(declaration)].name), module.text(reference.name))) continue;
'''
new = '''                if (!std.mem.eql(u8, self.graph.text(self.graph.declarations.items[@intFromEnum(declaration)].name), name)) continue;
'''
if text.count(old) != 1:
    raise RuntimeError(f"generic dispatch name anchor changed: {text.count(old)}")
generic_functions.write_text(text.replace(old, new, 1))

control = Path("src/4_semantics/global/control.zig")
text = control.read_text()
old = '''const core_mod = @import("core.zig");
const types = @import("types.zig");
'''
new = '''const core_mod = @import("core.zig");
const generic_functions_mod = @import("generic_functions.zig");
const abstract_mod = @import("abstracts.zig");
const types = @import("types.zig");
'''
if text.count(old) != 1:
    raise RuntimeError(f"control import anchor changed: {text.count(old)}")
text = text.replace(old, new, 1)
old = '''    core: ?*core_mod.Resolver = null,
    stats: Stats = .{},
'''
new = '''    core: ?*core_mod.Resolver = null,
    generic_functions: ?*generic_functions_mod.Resolver = null,
    abstracts: ?*abstract_mod.Resolver = null,
    stats: Stats = .{},
'''
if text.count(old) != 1:
    raise RuntimeError(f"control resolver dependency anchor changed: {text.count(old)}")
text = text.replace(old, new, 1)
old = '''            .resolve_for_each => |value| resolution.Result.fromBool(try self.resolveForEach(module_index, o, value)),
'''
new = '''            .resolve_for_each => |value| try self.resolveForEach(module_index, o, value),
'''
if text.count(old) != 1:
    raise RuntimeError(f"for-each result anchor changed: {text.count(old)}")
text = text.replace(old, new, 1)

start = text.index("    fn resolveForEach(")
end = text.index("\n    fn findChoiceType(", start)
replacement = r'''    const SyntheticCallResult = union(enum) {
        no_match,
        deferred,
        call: global_sg.GlobalNodeId,
    };

    fn resolveForEach(self: *Resolver, module_index: usize, o: globalizer.Offsets, value: anytype) !resolution.Result {
        const core = self.core orelse return .deferred;
        const generic_functions = self.generic_functions orelse return .deferred;
        const abstracts = self.abstracts orelse return .deferred;
        const iterable = globalizer.globalNode(o, value.iterable);
        const iterable_ty = self.graph.nodes.items[@intFromEnum(iterable)].ty orelse return .deferred;
        if (self.graph.isTypeUnresolved(iterable_ty)) return .deferred;

        // Desugaring is speculative while downstream types/functions may still
        // be unresolved. Roll every append-only GlobalSG pool back unless the
        // complete iterator loop can be published atomically.
        const pools = @typeInfo(global_sg.GlobalSemanticGraph).@"struct".fields;
        var lengths: [pools.len]usize = undefined;
        inline for (pools, 0..) |pool, index| lengths[index] = @field(self.graph, pool.name).items.len;
        var committed = false;
        defer if (!committed) {
            inline for (pools, 0..) |pool, index| @field(self.graph, pool.name).shrinkRetainingCapacity(lengths[index]);
        };

        const iterable_contract_name, const conversion_name, const iterable_mutable = switch (value.mode) {
            .value => .{ "Iterable", "to_iterator", false },
            .borrow => .{ "ROPointerIterable", "to_ro_pointer_iterator", false },
            .mut_borrow => .{ "RWPointerIterable", "to_rw_pointer_iterator", true },
        };
        const iterable_contract = self.visibleAbstract(module_index, iterable_contract_name) orelse return .deferred;
        if (!try abstracts.implements(iterable_ty, iterable_contract)) return .invalid;

        const source = self.graph.nodes.items[@intFromEnum(iterable)].source;
        var iterable_declaration: ?global_sg.GlobalNodeId = null;
        var iterable_place = iterable;
        if (!self.addressable(iterable)) {
            const binding: global_sg.GlobalBindingId = @enumFromInt(@as(u32, @intCast(self.graph.bindings.items.len)));
            try self.graph.bindings.append(self.allocator, .{
                .name = try self.graph.addString(self.allocator, "$for_iterable"),
                .source = source,
                .ty = iterable_ty,
                .initialization = iterable,
                .mutability = if (iterable_mutable) .variable else .constant,
            });
            iterable_declaration = try self.appendNode(source, try self.builtin(.Void), .{ .binding_declaration = binding });
            iterable_place = try self.appendNode(source, iterable_ty, .{ .binding_use = binding });
        }

        const iterable_reference = try self.appendAddress(iterable_place, iterable_ty, iterable_mutable, source);
        const conversion = try self.syntheticCall(module_index, conversion_name, iterable_reference, source, core, generic_functions);
        const iterator_value = switch (conversion) {
            .call => |node| node,
            .deferred => return .deferred,
            .no_match => return .invalid,
        };
        const iterator_ty = self.graph.nodes.items[@intFromEnum(iterator_value)].ty orelse return .deferred;
        if (self.graph.isTypeUnresolved(iterator_ty)) return .deferred;
        const iterator_contract = self.visibleAbstract(module_index, "Iterator") orelse return .deferred;
        if (!try abstracts.implements(iterator_ty, iterator_contract)) return .invalid;

        const iterator_binding: global_sg.GlobalBindingId = @enumFromInt(@as(u32, @intCast(self.graph.bindings.items.len)));
        try self.graph.bindings.append(self.allocator, .{
            .name = try self.graph.addString(self.allocator, "$for_iterator"),
            .source = source,
            .ty = iterator_ty,
            .initialization = iterator_value,
            .mutability = .variable,
        });
        const iterator_declaration = try self.appendNode(source, try self.builtin(.Void), .{ .binding_declaration = iterator_binding });

        const condition_iterator = try self.appendNode(source, iterator_ty, .{ .binding_use = iterator_binding });
        const condition_self = try self.appendAddress(condition_iterator, iterator_ty, false, source);
        const condition_result = try self.syntheticCall(module_index, "has_next", condition_self, source, core, generic_functions);
        const condition = switch (condition_result) {
            .call => |node| node,
            .deferred => return .deferred,
            .no_match => return .invalid,
        };
        const bool_ty = try self.builtin(.Bool);
        const condition_ty = self.graph.nodes.items[@intFromEnum(condition)].ty orelse return .deferred;
        if (!types.equal(self.graph, condition_ty, bool_ty)) return .invalid;

        const next_iterator = try self.appendNode(source, iterator_ty, .{ .binding_use = iterator_binding });
        const next_self = try self.appendAddress(next_iterator, iterator_ty, true, source);
        const next_result = try self.syntheticCall(module_index, "next", next_self, source, core, generic_functions);
        const next_value = switch (next_result) {
            .call => |node| node,
            .deferred => return .deferred,
            .no_match => return .invalid,
        };
        const element_ty = self.graph.nodes.items[@intFromEnum(next_value)].ty orelse return .deferred;
        if (self.graph.isTypeUnresolved(element_ty)) return .deferred;

        const item_binding = globalizer.globalBinding(o, value.binding);
        const old_binding_ty = self.graph.bindings.items[@intFromEnum(item_binding)].ty;
        self.graph.bindings.items[@intFromEnum(item_binding)].ty = element_ty;
        errdefer self.graph.bindings.items[@intFromEnum(item_binding)].ty = old_binding_ty;
        const item_declaration = try self.appendNode(source, try self.builtin(.Void), .{ .binding_declaration = item_binding });
        const item_assignment = try self.appendNode(source, element_ty, .{ .assignment = .{
            .binding = item_binding,
            .value = next_value,
        } });

        const old_body = self.graph.blocks.items[@intFromEnum(globalizer.globalBlock(o, value.body))];
        const old_nodes = self.graph.node_refs.items[old_body.nodes.start..][0..old_body.nodes.len];
        const body_start: u32 = @intCast(self.graph.node_refs.items.len);
        try self.graph.node_refs.append(self.allocator, item_declaration);
        try self.graph.node_refs.append(self.allocator, item_assignment);
        try self.graph.node_refs.appendSlice(self.allocator, old_nodes);
        const body_id: global_sg.GlobalBlockId = @enumFromInt(@as(u32, @intCast(self.graph.blocks.items.len)));
        try self.graph.blocks.append(self.allocator, .{
            .nodes = .{ .start = body_start, .len = @intCast(old_nodes.len + 2) },
            .ret_val = old_body.ret_val,
        });

        var init = iterator_declaration;
        if (iterable_declaration) |iterable_decl| {
            const init_start: u32 = @intCast(self.graph.node_refs.items.len);
            try self.graph.node_refs.append(self.allocator, iterable_decl);
            try self.graph.node_refs.append(self.allocator, iterator_declaration);
            const init_block: global_sg.GlobalBlockId = @enumFromInt(@as(u32, @intCast(self.graph.blocks.items.len)));
            try self.graph.blocks.append(self.allocator, .{
                .nodes = .{ .start = init_start, .len = 2 },
                .ret_val = null,
            });
            init = try self.appendNode(source, try self.builtin(.Void), .{ .code_block = init_block });
        }

        const target = globalizer.globalNode(o, value.node);
        self.graph.nodes.items[@intFromEnum(target)] = .{
            .source = source,
            .ty = try self.builtin(.Void),
            .content = .{ .for_statement = .{
                .init = init,
                .condition = condition,
                .increment = null,
                .body = body_id,
            } },
        };
        self.stats.array_loops += 1;
        committed = true;
        return .resolved;
    }

    fn syntheticCall(
        self: *Resolver,
        module_index: usize,
        name: []const u8,
        argument: global_sg.GlobalNodeId,
        source: primitives.SourceRef,
        core: *core_mod.Resolver,
        generic_functions: *generic_functions_mod.Resolver,
    ) !SyntheticCallResult {
        const input = try self.positionalInput(argument, source);
        const function = switch (try core.matchUnqualifiedFunctionByName(module_index, name, input)) {
            .function => |function| function,
            .deferred => return .deferred,
            .no_match => generic_functions.resolveImplicitGenericFunctionByName(module_index, name, input) catch |err| switch (err) {
                error.NoMatchingGenericFunction => return .no_match,
                error.DeferredGenericFunction => return .deferred,
                error.ConflictingGenericArgument => return .no_match,
                else => return err,
            },
        };
        const fields = self.graph.functions.items[@intFromEnum(function)].input;
        if (!try core.completeCallInputFields(fields, input)) return .deferred;
        const output = try core.functionOutputType(function);
        const call = try self.appendNode(source, output, .{ .function_call = .{
            .callee = function,
            .input = input,
        } });
        return .{ .call = call };
    }

    fn positionalInput(self: *Resolver, argument: global_sg.GlobalNodeId, source: primitives.SourceRef) !global_sg.GlobalNodeId {
        const start: u32 = @intCast(self.graph.value_fields.items.len);
        try self.graph.value_fields.append(self.allocator, .{
            .name = try self.graph.addString(self.allocator, ""),
            .value = argument,
        });
        const input: global_sg.GlobalNodeId = @enumFromInt(@as(u32, @intCast(self.graph.nodes.items.len)));
        try self.graph.nodes.append(self.allocator, .{
            .source = source,
            .ty = null,
            .content = .{ .struct_value_literal = .{
                .fields = .{ .start = start, .len = 1 },
                .dispatch_prefix_positional_count = 1,
            } },
        });
        return input;
    }

    fn visibleAbstract(self: *Resolver, module_index: usize, name: []const u8) ?global_sg.GlobalDeclId {
        const core = self.core orelse return null;
        var found: ?global_sg.GlobalDeclId = null;
        for (self.graph.declarations.items, 0..) |declaration, raw| {
            if (declaration.kind != .abstract_type or !std.mem.eql(u8, self.graph.text(declaration.name), name)) continue;
            const id: global_sg.GlobalDeclId = @enumFromInt(@as(u32, @intCast(raw)));
            if (!core.declarationVisible(module_index, id, null)) continue;
            if (found != null) return null;
            found = id;
        }
        return found;
    }

    fn addressable(self: *Resolver, node: global_sg.GlobalNodeId) bool {
        return switch (self.graph.nodes.items[@intFromEnum(node)].content) {
            .binding_use, .struct_field_access, .choice_payload_access, .dereference => true,
            else => false,
        };
    }
'''
text = text[:start] + replacement + text[end:]
control.write_text(text)

semantizer = Path("src/4_semantics/global/semantizer.zig")
text = semantizer.read_text()
old = '''    constructors.abstracts = &abstracts;
    defer abstracts.deinit();
    generic_functions.nested_call_context = &abstracts;
'''
new = '''    constructors.abstracts = &abstracts;
    control.generic_functions = &generic_functions;
    control.abstracts = &abstracts;
    defer abstracts.deinit();
    generic_functions.nested_call_context = &abstracts;
'''
if text.count(old) != 1:
    raise RuntimeError(f"control dependency wiring anchor changed: {text.count(old)}")
semantizer.write_text(text.replace(old, new, 1))

Path(".github/semantic_refactor_test_command").write_text(
    "zig build test-programs "
    "-Dtest-filter=feature_tests/control_flow/06_range_for "
    "-Dtest-filter=feature_tests/control_flow/07_range_step "
    "-Dtest-filter=feature_tests/control_flow/09_range_int64 "
    "-Dtest-filter=feature_tests/control_flow/10_range_default_start "
    "-Dtest-filter=feature_tests/control_flow/11_range_default_start_with_step\n"
)
Path(".git/semantic-refactor-message").write_text("Lower for-each through iterator contracts\n")
