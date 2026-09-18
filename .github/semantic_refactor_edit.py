from pathlib import Path
import re
import subprocess

def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label} anchor changed: {count}")
    return text.replace(old, new, 1)

# Generic function inference owns all parameter binding for calls and
# initializers. Initializers differ only because field 0 (the destination
# pointer) is compiler-supplied rather than present in the source call.
gpath = Path("src/4_semantics/global/generic_functions.zig")
gtext = gpath.read_text()

old_input = '''    pub fn inferBindingsFromInput(
        self: *Resolver,
        module_index: usize,
        pattern: ir.ParameterizedTypeId,
        input: global_sg.GlobalNodeId,
        bindings: *generic_mod.Resolver.Bindings,
    ) !bool {
        const literal = switch (self.graph.nodes.items[@intFromEnum(input)].content) {
            .struct_value_literal => |literal| literal,
            else => return false,
        };
        const storage = &self.modules[module_index].semantic.parameterized_storage.ir;
        const shape = switch (storage.types.items[@intFromEnum(pattern)]) {
            .resolved => |ty| switch (ty) {
                .structural => |shape| shape,
                else => return false,
            },
            else => return false,
        };
        for (storage.fields.items[shape.fields.start..][0..shape.fields.len], 0..) |field, position| {
            for (self.graph.value_fields.items[literal.fields.start..][0..literal.fields.len], 0..) |value, supplied_position| {
                const positional = supplied_position < literal.dispatch_prefix_positional_count or self.graph.text(value.name).len == 0;
                if (if (positional) position != supplied_position else !std.mem.eql(u8, self.modules[module_index].text(field.name), self.graph.text(value.name))) continue;
                const actual = self.graph.nodes.items[@intFromEnum(value.value)].ty orelse return false;
                if (!try self.inferInputType(module_index, field.ty, actual, bindings)) return false;
                break;
            }
        }
        return true;
    }

    fn inferBindingsFromReachDefaults(
        self: *Resolver,
        module_index: usize,
        pattern: ir.ParameterizedTypeId,
        input: global_sg.GlobalNodeId,
        bindings: *generic_mod.Resolver.Bindings,
        context: ReachInferenceContext,
    ) !bool {
        const literal = switch (self.graph.nodes.items[@intFromEnum(input)].content) {
            .struct_value_literal => |value| value,
            else => return true,
        };
        const candidate_module = &self.modules[module_index];
        const storage = &candidate_module.semantic.parameterized_storage.ir;
        const shape = switch (storage.types.items[@intFromEnum(pattern)]) {
            .resolved => |resolved| switch (resolved) {
                .structural => |value| value,
                else => return true,
            },
            else => return true,
        };

        for (storage.fields.items[shape.fields.start..][0..shape.fields.len], 0..) |field, position| {
            var supplied = false;
            for (self.graph.value_fields.items[literal.fields.start..][0..literal.fields.len], 0..) |value, supplied_position| {
                const positional = supplied_position < literal.dispatch_prefix_positional_count or self.graph.text(value.name).len == 0;
                if (if (positional) position == supplied_position else std.mem.eql(u8, candidate_module.text(field.name), self.graph.text(value.name))) {
                    supplied = true;
                    break;
                }
            }
            if (supplied) continue;
            const default_id = field.default_value orelse continue;
            const default_node = switch (storage.nodes.items[@intFromEnum(default_id)]) {
                .resolved => |node| node,
                .pending => continue,
            };
            const reach_id = switch (default_node.content) {
                .reach_directive => |reach| reach,
                else => continue,
            };
            const reach = storage.reaches.items[@intFromEnum(reach_id)];

            var inferred = false;
            for (storage.reach_alternatives.items[reach.alternatives.start..][0..reach.alternatives.len]) |alternative| {
                if (alternative.segments.len == 0) continue;
                const segments = storage.reach_segments.items[alternative.segments.start..][0..alternative.segments.len];
                const root_name = candidate_module.text(segments[0]);
                var scope_index = context.bindingCount();
                while (scope_index > 0) {
                    scope_index -= 1;
                    const binding_id = context.bindingAt(scope_index);
                    if (self.graph.isBindingTypeUnresolved(binding_id)) continue;
                    const binding = self.graph.bindings.items[@intFromEnum(binding_id)];
                    if (!std.mem.eql(u8, self.graph.text(binding.name), root_name)) continue;
                    var current_ty = binding.ty;
                    var valid = !self.graph.isTypeUnresolved(current_ty);
                    for (segments[1..]) |segment| {
                        if (!valid) break;
                        const hit = global_types.findField(self.graph, current_ty, candidate_module.text(segment)) orelse {
                            valid = false;
                            break;
                        };
                        current_ty = hit.field.storage_type orelse hit.field.ty;
                        if (self.graph.isTypeUnresolved(current_ty)) valid = false;
                    }
                    if (!valid) continue;
                    const matched = self.inferInputType(module_index, field.ty, current_ty, bindings) catch |err| switch (err) {
                        error.ConflictingGenericArgument => return false,
                        else => continue,
                    };
                    if (matched) {
                        inferred = true;
                        break;
                    }
                }
                if (inferred) break;
            }
        }
        return true;
    }
'''
new_input = '''    pub fn inferBindingsFromInput(
        self: *Resolver,
        module_index: usize,
        pattern: ir.ParameterizedTypeId,
        input: global_sg.GlobalNodeId,
        bindings: *generic_mod.Resolver.Bindings,
    ) !bool {
        return self.inferBindingsFromInputFields(module_index, pattern, input, bindings, 0, false);
    }

    fn inferBindingsFromInputFields(
        self: *Resolver,
        module_index: usize,
        pattern: ir.ParameterizedTypeId,
        input: global_sg.GlobalNodeId,
        bindings: *generic_mod.Resolver.Bindings,
        field_offset: u32,
        allow_contextual_concrete: bool,
    ) !bool {
        const literal = switch (self.graph.nodes.items[@intFromEnum(input)].content) {
            .struct_value_literal => |value| value,
            else => return false,
        };
        const module = &self.modules[module_index];
        const storage = &module.semantic.parameterized_storage.ir;
        const shape = switch (storage.types.items[@intFromEnum(pattern)]) {
            .resolved => |ty| switch (ty) {
                .structural => |value| value,
                else => return false,
            },
            else => return false,
        };
        if (field_offset > shape.fields.len) return false;

        const fields = storage.fields.items[
            shape.fields.start + field_offset ..
        ][0 .. shape.fields.len - field_offset];
        for (fields, 0..) |field, expected_position| {
            for (self.graph.value_fields.items[literal.fields.start..][0..literal.fields.len], 0..) |value, supplied_position| {
                const positional = supplied_position < literal.dispatch_prefix_positional_count or self.graph.text(value.name).len == 0;
                if (if (positional)
                    expected_position != supplied_position
                else
                    !std.mem.eql(u8, module.text(field.name), self.graph.text(value.name))) continue;

                if (allow_contextual_concrete) {
                    if (self.generics.instantiateParameterizedType(module_index, field.ty, bindings, null)) |expected| {
                        if (self.core.contextualLiteralFits(value.value, expected)) break;
                    } else |_| {}
                }

                const actual = self.graph.nodes.items[@intFromEnum(value.value)].ty orelse return false;
                if (!try self.inferInputType(module_index, field.ty, actual, bindings)) return false;
                break;
            }
        }
        return true;
    }

    fn inferBindingsFromReachDefaults(
        self: *Resolver,
        module_index: usize,
        pattern: ir.ParameterizedTypeId,
        input: global_sg.GlobalNodeId,
        bindings: *generic_mod.Resolver.Bindings,
        context: ReachInferenceContext,
    ) !bool {
        return self.inferBindingsFromReachDefaultFields(module_index, pattern, input, bindings, context, 0);
    }

    fn inferBindingsFromReachDefaultFields(
        self: *Resolver,
        module_index: usize,
        pattern: ir.ParameterizedTypeId,
        input: global_sg.GlobalNodeId,
        bindings: *generic_mod.Resolver.Bindings,
        context: ReachInferenceContext,
        field_offset: u32,
    ) !bool {
        const literal = switch (self.graph.nodes.items[@intFromEnum(input)].content) {
            .struct_value_literal => |value| value,
            else => return true,
        };
        const candidate_module = &self.modules[module_index];
        const storage = &candidate_module.semantic.parameterized_storage.ir;
        const shape = switch (storage.types.items[@intFromEnum(pattern)]) {
            .resolved => |resolved| switch (resolved) {
                .structural => |value| value,
                else => return true,
            },
            else => return true,
        };
        if (field_offset > shape.fields.len) return false;

        const fields = storage.fields.items[
            shape.fields.start + field_offset ..
        ][0 .. shape.fields.len - field_offset];
        for (fields, 0..) |field, expected_position| {
            var supplied = false;
            for (self.graph.value_fields.items[literal.fields.start..][0..literal.fields.len], 0..) |value, supplied_position| {
                const positional = supplied_position < literal.dispatch_prefix_positional_count or self.graph.text(value.name).len == 0;
                if (if (positional)
                    expected_position == supplied_position
                else
                    std.mem.eql(u8, candidate_module.text(field.name), self.graph.text(value.name)))
                {
                    supplied = true;
                    break;
                }
            }
            if (supplied) continue;

            const default_id = field.default_value orelse continue;
            const default_node = switch (storage.nodes.items[@intFromEnum(default_id)]) {
                .resolved => |node| node,
                .pending => continue,
            };
            const reach_id = switch (default_node.content) {
                .reach_directive => |reach| reach,
                else => continue,
            };
            const reach = storage.reaches.items[@intFromEnum(reach_id)];

            var inferred = false;
            for (storage.reach_alternatives.items[reach.alternatives.start..][0..reach.alternatives.len]) |alternative| {
                if (alternative.segments.len == 0) continue;
                const segments = storage.reach_segments.items[alternative.segments.start..][0..alternative.segments.len];
                const root_name = candidate_module.text(segments[0]);
                var scope_index = context.bindingCount();
                while (scope_index > 0) {
                    scope_index -= 1;
                    const binding_id = context.bindingAt(scope_index);
                    if (self.graph.isBindingTypeUnresolved(binding_id)) continue;
                    const binding = self.graph.bindings.items[@intFromEnum(binding_id)];
                    if (!std.mem.eql(u8, self.graph.text(binding.name), root_name)) continue;
                    var current_ty = binding.ty;
                    var valid = !self.graph.isTypeUnresolved(current_ty);
                    for (segments[1..]) |segment| {
                        if (!valid) break;
                        const hit = global_types.findField(self.graph, current_ty, candidate_module.text(segment)) orelse {
                            valid = false;
                            break;
                        };
                        current_ty = hit.field.storage_type orelse hit.field.ty;
                        if (self.graph.isTypeUnresolved(current_ty)) valid = false;
                    }
                    if (!valid) continue;
                    const matched = self.inferInputType(module_index, field.ty, current_ty, bindings) catch |err| switch (err) {
                        error.ConflictingGenericArgument => return false,
                        else => continue,
                    };
                    if (matched) {
                        inferred = true;
                        break;
                    }
                }
                if (inferred) break;
            }
        }
        return true;
    }

    pub fn inferInitializerBindings(
        self: *Resolver,
        module_index: usize,
        pattern: ir.ParameterizedTypeId,
        destination_type: global_sg.GlobalTypeId,
        input: global_sg.GlobalNodeId,
        context: ReachInferenceContext,
        bindings: *generic_mod.Resolver.Bindings,
    ) !bool {
        const storage = &self.modules[module_index].semantic.parameterized_storage.ir;
        const shape = switch (storage.types.items[@intFromEnum(pattern)]) {
            .resolved => |resolved| switch (resolved) {
                .structural => |value| value,
                else => return false,
            },
            else => return false,
        };
        if (shape.fields.len == 0) return false;

        const destination_pointer = try self.generics.internType(.{ .pointer = .{
            .child = destination_type,
            .mutability = .read_write,
        } });
        if (!try self.inferInputType(
            module_index,
            storage.fields.items[shape.fields.start].ty,
            destination_pointer,
            bindings,
        )) return false;

        if (!try self.inferBindingsFromInputFields(
            module_index,
            pattern,
            input,
            bindings,
            1,
            true,
        )) return false;

        return self.inferBindingsFromReachDefaultFields(
            module_index,
            pattern,
            input,
            bindings,
            context,
            1,
        );
    }
'''
gtext = replace_once(gtext, old_input, new_input, "shared generic inference")

old_init = '''    /// Infer the implicit abstract arguments of a constructor's `init` from
    /// its destination and supplied fields, then materialize its runtime body.
    pub fn instantiateInitializer(
        self: *Resolver,
        declaration: global_sg.GlobalDeclId,
        destination_type: global_sg.GlobalTypeId,
        input: global_sg.GlobalNodeId,
    ) !?global_sg.GlobalFunctionId {
        const located = self.findParameterized(declaration) orelse return null;
        const module = &self.modules[located.module_index];
        const storage = &module.semantic.parameterized_storage.ir;
        const shape = switch (storage.types.items[@intFromEnum(located.parameterized.input)]) {
            .resolved => |ty| switch (ty) {
                .structural => |value| value,
                else => return null,
            },
            else => return null,
        };
        if (shape.fields.len == 0) return null;
        const supplied = switch (self.graph.node(input).content) {
            .struct_value_literal => |value| value,
            else => return null,
        };
        var bindings = try generic_mod.Resolver.Bindings.init(self.allocator, module.semantic.parameterized_storage.comptime_parameters.items.len);
        defer bindings.deinit(self.allocator);
        const destination_pointer = try self.generics.internType(.{ .pointer = .{ .child = destination_type, .mutability = .read_write } });
        if (!try self.inferInputType(located.module_index, storage.fields.items[shape.fields.start].ty, destination_pointer, &bindings)) return null;
        for (storage.fields.items[shape.fields.start + 1 ..][0 .. shape.fields.len - 1]) |field| {
            for (self.graph.value_fields.items[supplied.fields.start..][0..supplied.fields.len]) |value| {
                if (!std.mem.eql(u8, module.text(field.name), self.graph.text(value.name))) continue;
                const actual = self.graph.node(value.value).ty orelse return null;
                // Concrete fields are checked by the contextual matcher after
                // instantiation; their literal types need not match yet.
                _ = self.inferInputType(located.module_index, field.ty, actual, &bindings) catch return null;
                break;
            }
        }
        const arguments = self.appendBoundArguments(located.module_index, located.parameterized.parameters, &bindings) catch return null;
        return try self.instantiate(declaration, arguments);
    }
'''
new_init = '''    /// Materialize a constructor initializer through the same generic
    /// inference used by every other generic call. Field 0 is the compiler
    /// supplied destination; source arguments and #reach defaults start at 1.
    pub fn instantiateInitializer(
        self: *Resolver,
        declaration: global_sg.GlobalDeclId,
        destination_type: global_sg.GlobalTypeId,
        input: global_sg.GlobalNodeId,
        context: ReachInferenceContext,
    ) !?global_sg.GlobalFunctionId {
        const located = self.findParameterized(declaration) orelse return null;
        const module = &self.modules[located.module_index];
        var bindings = try generic_mod.Resolver.Bindings.init(
            self.allocator,
            module.semantic.parameterized_storage.comptime_parameters.items.len,
        );
        defer bindings.deinit(self.allocator);
        if (!try self.inferInitializerBindings(
            located.module_index,
            located.parameterized.input,
            destination_type,
            input,
            context,
            &bindings,
        )) return null;
        const arguments = self.appendBoundArguments(
            located.module_index,
            located.parameterized.parameters,
            &bindings,
        ) catch return null;
        return try self.instantiate(declaration, arguments);
    }
'''
gtext = replace_once(gtext, old_init, new_init, "initializer instantiation")
gpath.write_text(gtext)

# Constructors select candidates, but generic_functions owns parameter binding.
cpath = Path("src/4_semantics/global/constructors.zig")
ctext = cpath.read_text()
caller_context = '''    const CallerContext = struct {
        module: *const module_sg.ModuleSemanticGraph,
        offsets: globalizer.Offsets,
        visible: module_entities.BindingRange,
    };

'''
ctext = replace_once(ctext, caller_context, "", "legacy constructor caller context")

ctext = ctext.replace(
    ".{ .module = module, .offsets = o, .visible = value.visible_bindings }",
    "reach_context.Context.fromModule(module, o, value.visible_bindings, value.owner_function)",
)
if ".{ .module = module, .offsets = o, .visible = value.visible_bindings }" in ctext:
    raise RuntimeError("legacy constructor context literal remained")
ctext = ctext.replace("context: CallerContext", "context: reach_context.Context")

old_call = '''                selected = (try generic_functions.instantiateInitializer(self.graph.functions.items[@intFromEnum(selected)].declaration, ty, input)) orelse return .deferred;
'''
new_call = '''                selected = (try generic_functions.instantiateInitializer(
                    self.graph.functions.items[@intFromEnum(selected)].declaration,
                    ty,
                    input,
                    reach_context.Context.fromModule(module, o, value.visible_bindings, value.owner_function),
                )) orelse return .deferred;
'''
ctext = replace_once(ctext, old_call, new_call, "non-generic type initializer context")

ctext = ctext.replace(
'''        if (!try self.populateInitializerBindings(
            generics,
            generic_functions,
''',
'''        if (!try self.populateInitializerBindings(
            generic_functions,
''',
)
if "self.populateInitializerBindings(\n            generics,\n            generic_functions," in ctext:
    raise RuntimeError("populate initializer call still passes generics")

pattern = re.compile(
    r'''    fn populateInitializerBindings\(.*?\n    fn scoreInitializerInput\(''',
    re.S,
)
replacement = '''    fn populateInitializerBindings(
        self: *Resolver,
        generic_functions: *generic_functions_mod.Resolver,
        candidate_index: usize,
        parameterized: anytype,
        constructed_ty: global_sg.GlobalTypeId,
        input: global_sg.GlobalNodeId,
        context: reach_context.Context,
        bindings: *generic_mod.Resolver.Bindings,
    ) !bool {
        _ = self;
        return generic_functions.inferInitializerBindings(
            candidate_index,
            parameterized.input,
            constructed_ty,
            input,
            context,
            bindings,
        );
    }

    fn scoreInitializerInput('''
ctext, count = pattern.subn(replacement, ctext, count=1)
if count != 1:
    raise RuntimeError(f"constructor binding helper collapse changed: {count}")
cpath.write_text(ctext)

for path in (gpath, cpath):
    subprocess.run(["zig", "fmt", str(path)], check=True)

Path(".git/semantic-refactor-test-command").write_text(
    "status=0; "
    "zig build test-programs -Dtest-filter=feature_tests/collections/34_dynamic_array_string_copy || status=1; "
    "zig build test-programs -Dtest-filter=feature_tests/collections/23_dynamic_array_owning_push_fixed || status=1; "
    "zig build test-programs -Dtest-filter=feature_tests/collections/24_dynamic_array_owning_assume_capacity || status=1; "
    "zig build test-programs -Dtest-filter=feature_tests/collections/26_dynamic_array_owning_pop || status=1; "
    "exit $status\n"
)
Path(".git/semantic-refactor-message").write_text(
    "Unify initializer generic and reach inference\n"
)
