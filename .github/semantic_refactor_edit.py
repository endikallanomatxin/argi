from pathlib import Path
import re
import subprocess

def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label} anchor changed: {count}")
    return text.replace(old, new, 1)

# Remove the temporary overload tracing that was intentionally landed by the
# diagnostic workflow. Candidate selection must remain side-effect free.
cpath = Path("src/4_semantics/global/core.zig")
ctext = cpath.read_text()
trace = '''            if (std.mem.eql(u8, name, "deinit")) {
                std.debug.print("[deinit-candidate] fn={} decl={} score={} generic={} input-len={}\\n", .{
                    raw,
                    @intFromEnum(function.declaration),
                    score,
                    function.flags.is_generic_instantiation,
                    function.input.len,
                });
                for (self.graph.fields.items[function.input.start..][0..function.input.len], 0..) |field, index| {
                    std.debug.print("  field[{}]={s} ty={}\\n", .{ index, self.graph.text(field.name), @intFromEnum(field.ty) });
                }
            }
'''
ctext = replace_once(ctext, trace, "", "temporary deinit trace")
cpath.write_text(ctext)

# A generic function instance is identified by its declaration and the bound
# parameter values, not by how the caller spelled or ordered its arguments.
fpath = Path("src/4_semantics/global/generic_functions.zig")
ftext = fpath.read_text()
pattern = re.compile(
    r'''    pub fn instantiate\(
        self: \*Resolver,
        declaration: global_sg\.GlobalDeclId,
        arguments: primitives\.Range\(global_sg\.GlobalGenericArgId\),
    \) !global_sg\.GlobalFunctionId \{.*?
    \}

    const LocatedParameterized = struct \{''',
    re.S,
)
replacement = '''    pub fn instantiate(
        self: *Resolver,
        declaration: global_sg.GlobalDeclId,
        arguments: primitives.Range(global_sg.GlobalGenericArgId),
    ) !global_sg.GlobalFunctionId {
        const located = self.findParameterized(declaration) orelse return error.GenericFunctionParameterizedNotFound;
        const module = &self.modules[located.module_index];
        const storage = &module.semantic.parameterized_storage;

        var substitutions = try generic_mod.Resolver.Bindings.init(self.allocator, storage.comptime_parameters.items.len);
        defer substitutions.deinit(self.allocator);
        try self.generics.bindGlobalArguments(located.module_index, located.parameterized.parameters, arguments, &substitutions);

        if (self.findExisting(
            declaration,
            located.module_index,
            located.parameterized.parameters,
            &substitutions,
        )) |id| return id;

        const pools = @typeInfo(global_sg.GlobalSemanticGraph).@"struct".fields;
        var lengths: [pools.len]usize = undefined;
        inline for (pools, 0..) |pool, index| lengths[index] = @field(self.graph, pool.name).items.len;
        const saved_stats = self.stats;
        const saved_generic_stats = self.generics.stats;
        errdefer {
            inline for (pools, 0..) |pool, index| @field(self.graph, pool.name).shrinkRetainingCapacity(lengths[index]);
            self.stats = saved_stats;
            self.generics.stats = saved_generic_stats;
        }

        // Persist a canonical argument vector in declaration-parameter order.
        // Call-site argument names/order are syntax, not monomorphization identity.
        const canonical_arguments = try self.appendBoundArguments(
            located.module_index,
            located.parameterized.parameters,
            &substitutions,
        );

        const input_ty = try self.generics.instantiateParameterizedType(located.module_index, located.parameterized.input, &substitutions, null);
        const output_ty = try self.generics.instantiateParameterizedType(located.module_index, located.parameterized.output, &substitutions, null);
        const input_shape = try self.interfaceFields(input_ty);
        const output_shape = try self.interfaceFields(output_ty);

        var context = try InstanceContext.init(self, located.module_index, located.parameterized, &substitutions);
        defer context.deinit();
        const input_bindings = try context.instantiateBindingRange(located.parameterized.input_bindings);
        const output_bindings = try context.instantiateBindingRange(located.parameterized.output_bindings);
        const input_fields = try self.materializeInterfaceDefaults(input_shape, input_bindings);
        const output_fields = try self.materializeInterfaceDefaults(output_shape, output_bindings);

        const function_id: global_sg.GlobalFunctionId = @enumFromInt(@as(u32, @intCast(self.graph.functions.items.len)));
        try self.graph.functions.append(self.allocator, .{
            .declaration = declaration,
            .input = input_fields,
            .output = output_fields,
            .body = null,
            .input_bindings = input_bindings,
            .output_bindings = output_bindings,
            .safety_primitive = located.parameterized.safety_primitive,
            .flags = .{
                .is_deinit = located.parameterized.is_deinit,
                .has_declared_body = located.parameterized.body != null,
                .is_generic_instantiation = true,
                .is_abstract_dispatch = false,
            },
        });
        try self.graph.function_operators.append(self.allocator, located.parameterized.operator);
        try self.graph.generic_function_instances.append(self.allocator, .{
            .function = function_id,
            .parameterized_declaration = declaration,
            .arguments = canonical_arguments,
        });

        context.function = function_id;
        if (located.parameterized.body) |body| {
            const instantiated_body = try context.instantiateBlock(body);
            self.graph.functions.items[@intFromEnum(function_id)].body = instantiated_body;
        }
        self.stats.instances += 1;
        return function_id;
    }

    const LocatedParameterized = struct {'''
ftext, count = pattern.subn(replacement, ftext, count=1)
if count != 1:
    raise RuntimeError(f"instantiate replacement changed: {count}")

old_find = '''    fn findExisting(
        self: *Resolver,
        declaration: global_sg.GlobalDeclId,
        arguments: primitives.Range(global_sg.GlobalGenericArgId),
    ) ?global_sg.GlobalFunctionId {
        for (self.graph.generic_function_instances.items) |instance| {
            if (instance.parameterized_declaration != declaration) continue;
            if (global_types.genericArgumentsEqual(self.graph, instance.arguments, arguments)) return instance.function;
        }
        return null;
    }
'''
new_find = '''    fn findExisting(
        self: *Resolver,
        declaration: global_sg.GlobalDeclId,
        module_index: usize,
        parameters: primitives.Range(ir.ComptimeParameterId),
        bindings: *const generic_mod.Resolver.Bindings,
    ) ?global_sg.GlobalFunctionId {
        for (self.graph.generic_function_instances.items) |instance| {
            if (instance.parameterized_declaration != declaration) continue;
            if (self.instanceArgumentsMatchBindings(module_index, parameters, instance.arguments, bindings))
                return instance.function;
        }
        return null;
    }

    fn instanceArgumentsMatchBindings(
        self: *const Resolver,
        module_index: usize,
        parameters: primitives.Range(ir.ComptimeParameterId),
        arguments: primitives.Range(global_sg.GlobalGenericArgId),
        bindings: *const generic_mod.Resolver.Bindings,
    ) bool {
        if (arguments.len != parameters.len) return false;
        const storage = &self.modules[module_index].semantic.parameterized_storage;
        for (0..parameters.len) |offset| {
            const parameter_raw = parameters.start + @as(u32, @intCast(offset));
            const parameter = storage.comptime_parameters.items[parameter_raw];
            const argument = self.graph.generic_arguments.items[arguments.start + @as(u32, @intCast(offset))];
            switch (parameter.kind) {
                .type => {
                    const expected = bindings.types[parameter_raw] orelse return false;
                    switch (argument.value) {
                        .type => |actual| if (!global_types.equal(self.graph, actual, expected)) return false,
                        else => return false,
                    }
                },
                .comptime_int => {
                    const expected = bindings.ints[parameter_raw] orelse return false;
                    switch (argument.value) {
                        .comptime_int => |actual| if (actual != expected) return false,
                        else => return false,
                    }
                },
            }
        }
        return true;
    }
'''
ftext = replace_once(ftext, old_find, new_find, "canonical generic function cache")
fpath.write_text(ftext)

# Ownership cleanup is a commit phase. If any binding owned by the function is
# still awaiting type inference, leave the function untouched and retry after
# the next GlobalSema fixed-point round.
opath = Path("src/4_semantics/global/ownership.zig")
otext = opath.read_text()
old_finalize = '''    pub fn finalize(self: *Resolver) !void {
        for (self.graph.functions.items, 0..) |function, raw| {
            if (function.body == null) continue;
            const id: global_sg.GlobalFunctionId = @enumFromInt(@as(u32, @intCast(raw)));
            try self.finalizeFunctionBody(id);
        }
    }

    pub fn finalizeFunctionBody(self: *Resolver, function_id: global_sg.GlobalFunctionId) !void {
        const function = self.graph.functions.items[@intFromEnum(function_id)];
        const body = function.body orelse return;
'''
new_finalize = '''    pub fn finalize(self: *Resolver) !void {
        const count = self.graph.functions.items.len;
        for (0..count) |raw| {
            const function = self.graph.functions.items[raw];
            if (function.body == null) continue;
            const id: global_sg.GlobalFunctionId = @enumFromInt(@as(u32, @intCast(raw)));
            _ = try self.finalizeFunctionBody(id);
        }
    }

    pub fn finalizeFunctionBody(self: *Resolver, function_id: global_sg.GlobalFunctionId) !bool {
        const function = self.graph.functions.items[@intFromEnum(function_id)];
        const body = function.body orelse return true;
        if (!self.functionReadyForCleanup(function, body)) return false;
'''
otext = replace_once(otext, old_finalize, new_finalize, "ownership finalization readiness")

old_end = '''        const module = self.graph.moduleForDeclaration(function.declaration) orelse return error.MissingFunctionModule;
        try self.finalizeBlock(body, &active, &defers, &visible, function_id, @intCast(@intFromEnum(module)));
    }

    fn resolveDefer'''
new_end = '''        const module = self.graph.moduleForDeclaration(function.declaration) orelse return error.MissingFunctionModule;
        try self.finalizeBlock(body, &active, &defers, &visible, function_id, @intCast(@intFromEnum(module)));
        return true;
    }

    fn functionReadyForCleanup(
        self: *const Resolver,
        function: global_sg.Function,
        body: global_sg.GlobalBlockId,
    ) bool {
        for (self.graph.binding_refs.items[function.input_bindings.start..][0..function.input_bindings.len]) |binding|
            if (self.graph.isBindingTypeUnresolved(binding)) return false;
        for (self.graph.binding_refs.items[function.output_bindings.start..][0..function.output_bindings.len]) |binding|
            if (self.graph.isBindingTypeUnresolved(binding)) return false;
        return self.blockReadyForCleanup(body);
    }

    fn blockReadyForCleanup(self: *const Resolver, block_id: global_sg.GlobalBlockId) bool {
        const block = self.graph.blocks.items[@intFromEnum(block_id)];
        for (self.graph.node_refs.items[block.nodes.start..][0..block.nodes.len]) |node_id| {
            const node = self.graph.nodes.items[@intFromEnum(node_id)];
            switch (node.content) {
                .binding_declaration => |binding| if (self.graph.isBindingTypeUnresolved(binding)) return false,
                .binding_use => |binding| if (self.graph.isBindingTypeUnresolved(binding)) return false,
                .assignment => |assignment| if (self.graph.isBindingTypeUnresolved(assignment.binding)) return false,
                .code_block => |child| if (!self.blockReadyForCleanup(child)) return false,
                .if_statement => |statement| {
                    if (!self.blockReadyForCleanup(statement.then_block)) return false;
                    if (statement.else_block) |child|
                        if (!self.blockReadyForCleanup(child)) return false;
                },
                .while_statement => |statement| if (!self.blockReadyForCleanup(statement.body)) return false,
                .for_statement => |statement| {
                    if (statement.init) |init| {
                        const init_node = self.graph.nodes.items[@intFromEnum(init)];
                        if (init_node.content == .code_block and !self.blockReadyForCleanup(init_node.content.code_block))
                            return false;
                    }
                    if (!self.blockReadyForCleanup(statement.body)) return false;
                },
                .switch_statement => |switch_id| {
                    const sw = self.graph.switches.items[@intFromEnum(switch_id)];
                    for (self.graph.switch_cases.items[sw.cases.start..][0..sw.cases.len]) |case| {
                        if (case.payload_binding) |binding|
                            if (self.graph.isBindingTypeUnresolved(binding)) return false;
                        if (!self.blockReadyForCleanup(case.body)) return false;
                    }
                    if (sw.default_block) |child|
                        if (!self.blockReadyForCleanup(child)) return false;
                },
                else => {},
            }
        }
        return true;
    }

    fn resolveDefer'''
otext = replace_once(otext, old_end, new_end, "ownership readiness helpers")
opath.write_text(otext)

# Finalize only a stable snapshot of functions. Cleanup may instantiate more
# functions; those belong to the next fixed-point round. Mark a function
# finalized only after its readiness scan and cleanup commit succeed.
spath = Path("src/4_semantics/global/semantizer.zig")
stext = spath.read_text()
old_loop = '''        var finalized_any = false;
        for (relocation.graph.functions.items, 0..) |function, raw| {
            const id: global_sg.GlobalFunctionId = @enumFromInt(@as(u32, @intCast(raw)));
            if (reachable) |set| {
                if (!set.contains(id)) continue;
            }
            if (function.body) |body| {
                if ((try finalized_functions.getOrPut(id)).found_existing) continue;
                _ = body;
                try ownership.finalizeFunctionBody(id);
                finalized_any = true;
            }
        }
'''
new_loop = '''        var finalized_any = false;
        const finalization_count = relocation.graph.functions.items.len;
        var raw: usize = 0;
        while (raw < finalization_count) : (raw += 1) {
            const id: global_sg.GlobalFunctionId = @enumFromInt(@as(u32, @intCast(raw)));
            if (finalized_functions.contains(id)) continue;
            if (reachable) |set| {
                if (!set.contains(id)) continue;
            }
            if (relocation.graph.functions.items[raw].body == null) continue;
            if (!try ownership.finalizeFunctionBody(id)) continue;
            try finalized_functions.put(id, {});
            finalized_any = true;
        }
'''
stext = replace_once(stext, old_loop, new_loop, "stable ownership finalization loop")
spath.write_text(stext)

for path in (cpath, fpath, opath, spath):
    subprocess.run(["zig", "fmt", str(path)], check=True)

Path(".git/semantic-refactor-test-command").write_text(
    "status=0; "
    "zig build test-programs -Dtest-filter=feature_tests/collections/34_dynamic_array_string_copy || status=1; "
    "zig build test-programs -Dtest-filter=feature_tests/collections/35_dynamic_array_fallible_copy_cleanup || status=1; "
    "zig build test-programs -Dtest-filter=feature_tests/collections/36_dynamic_array_owning_mutations || status=1; "
    "zig build test-programs -Dtest-filter=feature_tests/collections/23_dynamic_array_owning_push_fixed || status=1; "
    "zig build test-programs -Dtest-filter=feature_tests/collections/24_dynamic_array_owning_assume_capacity || status=1; "
    "zig build test-programs -Dtest-filter=feature_tests/collections/26_dynamic_array_owning_pop || status=1; "
    "exit $status\n"
)
Path(".git/semantic-refactor-message").write_text(
    "Canonicalize generic instances and stage ownership finalization\n"
)
