from pathlib import Path


def replace_once(path: Path, old: str, new: str, label: str) -> None:
    text = path.read_text()
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label} anchor changed: {count}")
    path.write_text(text.replace(old, new, 1))


core = Path("src/4_semantics/global/core.zig")
replace_once(
    core,
    "    fn completeCallInputFieldsWithReach(self: *Resolver, expected_fields: global_sg.FieldRange, input_node: global_sg.GlobalNodeId, module: *const module_sg.ModuleSemanticGraph, o: globalizer.Offsets, visible: module_entities.BindingRange, owner: ?module_entities.ModuleFunctionId) !bool {\n",
    "    pub fn completeCallInputFieldsWithReach(self: *Resolver, expected_fields: global_sg.FieldRange, input_node: global_sg.GlobalNodeId, module: *const module_sg.ModuleSemanticGraph, o: globalizer.Offsets, visible: module_entities.BindingRange, owner: ?module_entities.ModuleFunctionId) !bool {\n",
    "reach-aware call completion visibility",
)

constructors = Path("src/4_semantics/global/constructors.zig")
text = constructors.read_text()

simple_replacements = [
    (
        "return self.resolveExplicitGenericCall(module_index, o, value, reference, arguments);",
        "return self.resolveExplicitGenericCall(module_index, module, o, value, reference, arguments);",
        "explicit constructor dispatch",
    ),
    (
        "return self.resolveImplicitGenericCall(module_index, o, value, reference, declaration_id, input);",
        "return self.resolveImplicitGenericCall(module_index, module, o, value, reference, declaration_id, input);",
        "implicit constructor dispatch",
    ),
    (
        '''    fn resolveImplicitGenericCall(\n        self: *Resolver,\n        module_index: usize,\n        o: globalizer.Offsets,\n''',
        '''    fn resolveImplicitGenericCall(\n        self: *Resolver,\n        module_index: usize,\n        module: *const module_sg.ModuleSemanticGraph,\n        o: globalizer.Offsets,\n''',
        "implicit constructor signature",
    ),
    (
        '''    fn resolveExplicitGenericCall(\n        self: *Resolver,\n        module_index: usize,\n        o: globalizer.Offsets,\n''',
        '''    fn resolveExplicitGenericCall(\n        self: *Resolver,\n        module_index: usize,\n        module: *const module_sg.ModuleSemanticGraph,\n        o: globalizer.Offsets,\n''',
        "explicit constructor signature",
    ),
]
for old, new, label in simple_replacements:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label} anchor changed: {count}")
    text = text.replace(old, new, 1)

lookup_anchor = '''    const InferredInitializerLookup = struct {\n        function: ?global_sg.GlobalFunctionId = null,\n        constructed_type: ?global_sg.GlobalTypeId = null,\n        has_visible_initializer: bool = false,\n    };\n'''
lookup_replacement = lookup_anchor + '''\n    const CallerContext = struct {\n        module: *const module_sg.ModuleSemanticGraph,\n        offsets: globalizer.Offsets,\n        visible: module_entities.BindingRange,\n    };\n'''
if text.count(lookup_anchor) != 1:
    raise RuntimeError(f"caller context anchor changed: {text.count(lookup_anchor)}")
text = text.replace(lookup_anchor, lookup_replacement, 1)

old = "if (!try self.core.completeCallInputFields(user_fields, input)) return .deferred;"
new = "if (!try self.core.completeCallInputFieldsWithReach(user_fields, input, module, o, value.visible_bindings, value.owner_function)) return .deferred;"
if text.count(old) != 4:
    raise RuntimeError(f"constructor completion anchors changed: {text.count(old)}")
text = text.replace(old, new)

old = '''                    const initializer = try self.findGenericInitializer(\n                        &generics,\n                        &generic_functions,\n                        module_index,\n                        expected,\n                        identity.arguments,\n                        input,\n                    );\n'''
new = '''                    const initializer = try self.findGenericInitializer(\n                        &generics,\n                        &generic_functions,\n                        module_index,\n                        expected,\n                        input,\n                        .{ .module = module, .offsets = o, .visible = value.visible_bindings },\n                    );\n'''
if text.count(old) != 1:
    raise RuntimeError(f"expected generic initializer anchor changed: {text.count(old)}")
text = text.replace(old, new, 1)

old = '''        const initializer = try self.findImplicitGenericInitializer(\n            &generics,\n            &generic_functions,\n            module_index,\n            declaration_id,\n            input,\n        );\n'''
new = '''        const initializer = try self.findImplicitGenericInitializer(\n            &generics,\n            &generic_functions,\n            module_index,\n            declaration_id,\n            input,\n            .{ .module = module, .offsets = o, .visible = value.visible_bindings },\n        );\n'''
if text.count(old) != 1:
    raise RuntimeError(f"implicit generic initializer anchor changed: {text.count(old)}")
text = text.replace(old, new, 1)

old = '''        const initializer = try self.findGenericInitializer(\n            &generics,\n            &generic_functions,\n            module_index,\n            ty,\n            arguments,\n            input,\n        );\n'''
new = '''        const initializer = try self.findGenericInitializer(\n            &generics,\n            &generic_functions,\n            module_index,\n            ty,\n            input,\n            .{ .module = module, .offsets = o, .visible = value.visible_bindings },\n        );\n'''
if text.count(old) != 1:
    raise RuntimeError(f"explicit generic initializer anchor changed: {text.count(old)}")
text = text.replace(old, new, 1)

start = text.find("    fn findImplicitGenericInitializer(\n")
end_marker = '\n};\n\ntest "declared type call materializes a struct value without visible init"'
end = text.find(end_marker, start)
if start < 0 or end < 0:
    raise RuntimeError("generic initializer helper block anchors changed")

helper_block = r'''    fn findImplicitGenericInitializer(
        self: *Resolver,
        generics: *generic_mod.Resolver,
        generic_functions: *generic_functions_mod.Resolver,
        module_index: usize,
        constructed_declaration: global_sg.GlobalDeclId,
        input: global_sg.GlobalNodeId,
        context: CallerContext,
    ) !InferredInitializerLookup {
        var result: InferredInitializerLookup = .{};
        var best_declaration: ?global_sg.GlobalDeclId = null;
        var best_score: u32 = 0;
        var tied = false;

        for (self.modules, 0..) |*candidate_module, candidate_index| {
            for (candidate_module.semantic.parameterized_storage.parameterized_functions.items) |parameterized| {
                const declaration_id = globalizer.globalDecl(self.offsets[candidate_index], parameterized.declaration);
                const declaration = self.graph.declarations.items[@intFromEnum(declaration_id)];
                if (!std.mem.eql(u8, self.graph.text(declaration.name), "init")) continue;
                if (!self.core.declarationVisible(module_index, declaration_id, null)) continue;
                if (!self.parameterizedInitializerOwnsType(generics, candidate_index, parameterized, constructed_declaration)) continue;
                result.has_visible_initializer = true;

                const probe = try self.probeImplicitGenericInitializer(
                    generics,
                    generic_functions,
                    candidate_module,
                    candidate_index,
                    parameterized,
                    input,
                    context,
                );
                var score = probe.score orelse continue;
                const owner = self.graph.moduleForDeclaration(declaration_id) orelse continue;
                if (@intFromEnum(owner) == module_index) score += 1;
                if (best_declaration == null or score > best_score) {
                    best_declaration = declaration_id;
                    best_score = score;
                    tied = false;
                } else if (score == best_score and declaration_id != best_declaration.?) {
                    tied = true;
                }
            }
        }

        if (tied or best_declaration == null) return result;
        const materialized = try self.materializeImplicitGenericInitializer(
            generics,
            generic_functions,
            best_declaration.?,
            constructed_declaration,
            input,
            context,
        ) orelse return result;
        result.function = materialized.function;
        result.constructed_type = materialized.constructed_type;
        return result;
    }

    fn parameterizedInitializerOwnsType(
        self: *Resolver,
        generics: *generic_mod.Resolver,
        candidate_index: usize,
        parameterized: anytype,
        constructed_declaration: global_sg.GlobalDeclId,
    ) bool {
        const storage = &self.modules[candidate_index].semantic.parameterized_storage.ir;
        const shape = switch (storage.types.items[@intFromEnum(parameterized.input)]) {
            .resolved => |ty| switch (ty) {
                .structural => |value| value,
                else => return false,
            },
            else => return false,
        };
        if (shape.fields.len == 0) return false;
        const destination = storage.fields.items[shape.fields.start];
        const pointer = switch (storage.types.items[@intFromEnum(destination.ty)]) {
            .resolved => |ty| switch (ty) {
                .pointer => |value| value,
                else => return false,
            },
            else => return false,
        };
        const generic = switch (storage.types.items[@intFromEnum(pointer.child)]) {
            .resolved => |ty| switch (ty) {
                .generic => |value| value,
                else => return false,
            },
            else => return false,
        };
        const base = generics.resolveParameterizedDeclaration(candidate_index, generic.base) catch return false;
        return base == constructed_declaration;
    }

    fn probeImplicitGenericInitializer(
        self: *Resolver,
        generics: *generic_mod.Resolver,
        generic_functions: *generic_functions_mod.Resolver,
        candidate_module: *const module_sg.ModuleSemanticGraph,
        candidate_index: usize,
        parameterized: anytype,
        input: global_sg.GlobalNodeId,
        context: CallerContext,
    ) !InitializerProbe {
        const pools = @typeInfo(global_sg.GlobalSemanticGraph).@"struct".fields;
        var lengths: [pools.len]usize = undefined;
        inline for (pools, 0..) |pool, index| lengths[index] = @field(self.graph, pool.name).items.len;
        const saved_stats = generics.stats;
        defer {
            inline for (pools, 0..) |pool, index| @field(self.graph, pool.name).shrinkRetainingCapacity(lengths[index]);
            generics.stats = saved_stats;
        }

        var bindings = try generic_mod.Resolver.Bindings.init(
            self.core.allocator,
            candidate_module.semantic.parameterized_storage.comptime_parameters.items.len,
        );
        defer bindings.deinit(self.core.allocator);
        if (!try self.inferInitializerUserBindings(generic_functions, candidate_index, parameterized.input, input, &bindings))
            return .{ .owns_type = true };
        if (!try self.inferInitializerReachBindings(generic_functions, candidate_index, parameterized.input, context, &bindings))
            return .{ .owns_type = true };
        const input_ty = generics.instantiateParameterizedType(candidate_index, parameterized.input, &bindings, null) catch
            return .{ .owns_type = true };
        const fields = types.fields(self.graph, input_ty) orelse return .{ .owns_type = true };
        if (fields.len == 0) return .{ .owns_type = true };
        return .{
            .owns_type = true,
            .score = try self.scoreInitializerInput(candidate_index, parameterized.input, .{
                .start = fields.start + 1,
                .len = fields.len - 1,
            }, input),
        };
    }

    fn materializeImplicitGenericInitializer(
        self: *Resolver,
        generics: *generic_mod.Resolver,
        generic_functions: *generic_functions_mod.Resolver,
        declaration: global_sg.GlobalDeclId,
        constructed_declaration: global_sg.GlobalDeclId,
        input: global_sg.GlobalNodeId,
        context: CallerContext,
    ) !?InferredInitializerLookup {
        for (self.modules, 0..) |*candidate_module, candidate_index| {
            for (candidate_module.semantic.parameterized_storage.parameterized_functions.items) |parameterized| {
                const declaration_id = globalizer.globalDecl(self.offsets[candidate_index], parameterized.declaration);
                if (declaration_id != declaration) continue;
                if (!self.parameterizedInitializerOwnsType(generics, candidate_index, parameterized, constructed_declaration)) return null;

                var bindings = try generic_mod.Resolver.Bindings.init(
                    self.core.allocator,
                    candidate_module.semantic.parameterized_storage.comptime_parameters.items.len,
                );
                defer bindings.deinit(self.core.allocator);
                if (!try self.inferInitializerUserBindings(generic_functions, candidate_index, parameterized.input, input, &bindings)) return null;
                if (!try self.inferInitializerReachBindings(generic_functions, candidate_index, parameterized.input, context, &bindings)) return null;
                const input_ty = generics.instantiateParameterizedType(candidate_index, parameterized.input, &bindings, null) catch return null;
                const fields = types.fields(self.graph, input_ty) orelse return null;
                if (fields.len == 0) return null;
                const destination = self.graph.fields.items[fields.start];
                const pointer = switch (self.graph.types.items[@intFromEnum(destination.ty)]) {
                    .pointer => |value| value,
                    else => return null,
                };
                const identity = switch (self.graph.types.items[@intFromEnum(pointer.child)]) {
                    .generic => |value| value,
                    else => return null,
                };
                if (identity.base != constructed_declaration) return null;
                const arguments = generic_functions.appendBoundArguments(candidate_index, parameterized.parameters, &bindings) catch return null;
                const function = generic_functions.instantiate(declaration, arguments) catch return null;
                return .{
                    .function = function,
                    .constructed_type = pointer.child,
                    .has_visible_initializer = true,
                };
            }
        }
        return null;
    }

    fn findGenericInitializer(
        self: *Resolver,
        generics: *generic_mod.Resolver,
        generic_functions: *generic_functions_mod.Resolver,
        module_index: usize,
        constructed_ty: global_sg.GlobalTypeId,
        input: global_sg.GlobalNodeId,
        context: CallerContext,
    ) !InitializerLookup {
        var result: InitializerLookup = .{};
        var best_declaration: ?global_sg.GlobalDeclId = null;
        var best_score: u32 = 0;
        var tied = false;

        for (self.modules, 0..) |*candidate_module, candidate_index| {
            for (candidate_module.semantic.parameterized_storage.parameterized_functions.items) |parameterized| {
                const declaration_id = globalizer.globalDecl(self.offsets[candidate_index], parameterized.declaration);
                const declaration = self.graph.declarations.items[@intFromEnum(declaration_id)];
                if (!std.mem.eql(u8, self.graph.text(declaration.name), "init")) continue;
                if (!self.core.declarationVisible(module_index, declaration_id, null)) continue;

                const probe = try self.probeGenericInitializer(
                    generics,
                    generic_functions,
                    candidate_module,
                    candidate_index,
                    parameterized,
                    constructed_ty,
                    input,
                    context,
                );
                if (!probe.owns_type) continue;
                result.has_visible_initializer = true;
                var score = probe.score orelse continue;
                const owner = self.graph.moduleForDeclaration(declaration_id) orelse continue;
                if (@intFromEnum(owner) == module_index) score += 1;
                if (best_declaration == null or score > best_score) {
                    best_declaration = declaration_id;
                    best_score = score;
                    tied = false;
                } else if (score == best_score and declaration_id != best_declaration.?) {
                    tied = true;
                }
            }
        }

        if (tied or best_declaration == null) return result;
        result.function = try self.materializeGenericInitializer(
            generics,
            generic_functions,
            best_declaration.?,
            constructed_ty,
            input,
            context,
        );
        return result;
    }

    fn probeGenericInitializer(
        self: *Resolver,
        generics: *generic_mod.Resolver,
        generic_functions: *generic_functions_mod.Resolver,
        candidate_module: *const module_sg.ModuleSemanticGraph,
        candidate_index: usize,
        parameterized: anytype,
        constructed_ty: global_sg.GlobalTypeId,
        input: global_sg.GlobalNodeId,
        context: CallerContext,
    ) !InitializerProbe {
        const pools = @typeInfo(global_sg.GlobalSemanticGraph).@"struct".fields;
        var lengths: [pools.len]usize = undefined;
        inline for (pools, 0..) |pool, index| lengths[index] = @field(self.graph, pool.name).items.len;
        const saved_stats = generics.stats;
        defer {
            inline for (pools, 0..) |pool, index| @field(self.graph, pool.name).shrinkRetainingCapacity(lengths[index]);
            generics.stats = saved_stats;
        }

        var bindings = try generic_mod.Resolver.Bindings.init(
            self.core.allocator,
            candidate_module.semantic.parameterized_storage.comptime_parameters.items.len,
        );
        defer bindings.deinit(self.core.allocator);
        if (!try self.populateInitializerBindings(
            generics,
            generic_functions,
            candidate_index,
            parameterized,
            constructed_ty,
            input,
            context,
            &bindings,
        )) return .{};
        const input_ty = generics.instantiateParameterizedType(candidate_index, parameterized.input, &bindings, null) catch return .{};
        const fields = types.fields(self.graph, input_ty) orelse return .{};
        if (fields.len == 0) return .{};
        return .{
            .owns_type = true,
            .score = try self.scoreInitializerInput(candidate_index, parameterized.input, .{
                .start = fields.start + 1,
                .len = fields.len - 1,
            }, input),
        };
    }

    fn materializeGenericInitializer(
        self: *Resolver,
        generics: *generic_mod.Resolver,
        generic_functions: *generic_functions_mod.Resolver,
        declaration: global_sg.GlobalDeclId,
        constructed_ty: global_sg.GlobalTypeId,
        input: global_sg.GlobalNodeId,
        context: CallerContext,
    ) !?global_sg.GlobalFunctionId {
        for (self.modules, 0..) |*candidate_module, candidate_index| {
            for (candidate_module.semantic.parameterized_storage.parameterized_functions.items) |parameterized| {
                const declaration_id = globalizer.globalDecl(self.offsets[candidate_index], parameterized.declaration);
                if (declaration_id != declaration) continue;
                var bindings = try generic_mod.Resolver.Bindings.init(
                    self.core.allocator,
                    candidate_module.semantic.parameterized_storage.comptime_parameters.items.len,
                );
                defer bindings.deinit(self.core.allocator);
                if (!try self.populateInitializerBindings(
                    generics,
                    generic_functions,
                    candidate_index,
                    parameterized,
                    constructed_ty,
                    input,
                    context,
                    &bindings,
                )) return null;
                const arguments = generic_functions.appendBoundArguments(candidate_index, parameterized.parameters, &bindings) catch return null;
                return generic_functions.instantiate(declaration, arguments) catch return null;
            }
        }
        return null;
    }

    fn populateInitializerBindings(
        self: *Resolver,
        generics: *generic_mod.Resolver,
        generic_functions: *generic_functions_mod.Resolver,
        candidate_index: usize,
        parameterized: anytype,
        constructed_ty: global_sg.GlobalTypeId,
        input: global_sg.GlobalNodeId,
        context: CallerContext,
        bindings: *generic_mod.Resolver.Bindings,
    ) !bool {
        const storage = &self.modules[candidate_index].semantic.parameterized_storage.ir;
        const shape = switch (storage.types.items[@intFromEnum(parameterized.input)]) {
            .resolved => |ty| switch (ty) {
                .structural => |value| value,
                else => return false,
            },
            else => return false,
        };
        if (shape.fields.len == 0) return false;
        const destination_pointer = try generics.internType(.{ .pointer = .{
            .child = constructed_ty,
            .mutability = .read_write,
        } });
        if (!try generic_functions.inferInputType(
            candidate_index,
            storage.fields.items[shape.fields.start].ty,
            destination_pointer,
            bindings,
        )) return false;
        if (!try self.inferInitializerUserBindings(generic_functions, candidate_index, parameterized.input, input, bindings)) return false;
        return self.inferInitializerReachBindings(generic_functions, candidate_index, parameterized.input, context, bindings);
    }

    fn inferInitializerUserBindings(
        self: *Resolver,
        generic_functions: *generic_functions_mod.Resolver,
        candidate_index: usize,
        pattern: @import("../module/parameterized/ir.zig").ParameterizedTypeId,
        input: global_sg.GlobalNodeId,
        bindings: *generic_mod.Resolver.Bindings,
    ) !bool {
        const literal = switch (self.graph.nodes.items[@intFromEnum(input)].content) {
            .struct_value_literal => |value| value,
            else => return false,
        };
        const module = &self.modules[candidate_index];
        const storage = &module.semantic.parameterized_storage.ir;
        const shape = switch (storage.types.items[@intFromEnum(pattern)]) {
            .resolved => |ty| switch (ty) {
                .structural => |value| value,
                else => return false,
            },
            else => return false,
        };
        if (shape.fields.len == 0) return false;
        for (storage.fields.items[shape.fields.start + 1 ..][0 .. shape.fields.len - 1], 0..) |field, expected_position| {
            for (self.graph.value_fields.items[literal.fields.start..][0..literal.fields.len], 0..) |value, supplied_position| {
                const positional = supplied_position < literal.dispatch_prefix_positional_count or self.graph.text(value.name).len == 0;
                if (if (positional) expected_position != supplied_position else !std.mem.eql(u8, module.text(field.name), self.graph.text(value.name))) continue;
                const actual = self.graph.nodes.items[@intFromEnum(value.value)].ty orelse break;
                if (!try generic_functions.inferInputType(candidate_index, field.ty, actual, bindings)) return false;
                break;
            }
        }
        return true;
    }

    fn inferInitializerReachBindings(
        self: *Resolver,
        generic_functions: *generic_functions_mod.Resolver,
        candidate_index: usize,
        pattern: @import("../module/parameterized/ir.zig").ParameterizedTypeId,
        context: CallerContext,
        bindings: *generic_mod.Resolver.Bindings,
    ) !bool {
        const module = &self.modules[candidate_index];
        const storage = &module.semantic.parameterized_storage.ir;
        const shape = switch (storage.types.items[@intFromEnum(pattern)]) {
            .resolved => |ty| switch (ty) {
                .structural => |value| value,
                else => return false,
            },
            else => return false,
        };
        if (shape.fields.len == 0) return false;
        for (storage.fields.items[shape.fields.start + 1 ..][0 .. shape.fields.len - 1]) |field| {
            const default = field.default_value orelse continue;
            const actual = self.parameterizedReachType(candidate_index, default, context) orelse continue;
            if (!try generic_functions.inferInputType(candidate_index, field.ty, actual, bindings)) return false;
        }
        return true;
    }

    fn parameterizedReachType(
        self: *Resolver,
        candidate_index: usize,
        default_node: @import("../module/parameterized/ir.zig").ParameterizedNodeId,
        context: CallerContext,
    ) ?global_sg.GlobalTypeId {
        const candidate_module = &self.modules[candidate_index];
        const storage = &candidate_module.semantic.parameterized_storage.ir;
        const resolved = switch (storage.nodes.items[@intFromEnum(default_node)]) {
            .resolved => |value| value,
            .pending => return null,
        };
        const reach_id = switch (resolved.content) {
            .reach_directive => |value| value,
            else => return null,
        };
        const reach = storage.reaches.items[@intFromEnum(reach_id)];
        const scope = context.module.semantic.binding_refs.items[context.visible.start..][0..context.visible.len];
        for (storage.reach_alternatives.items[reach.alternatives.start..][0..reach.alternatives.len]) |alternative| {
            if (alternative.segments.len == 0) continue;
            const segments = storage.reach_segments.items[alternative.segments.start..][0..alternative.segments.len];
            const root_name = candidate_module.text(segments[0]);
            var scope_index = scope.len;
            while (scope_index > 0) {
                scope_index -= 1;
                const binding_id = globalizer.globalBinding(context.offsets, scope[scope_index]);
                const binding = self.graph.bindings.items[@intFromEnum(binding_id)];
                if (!std.mem.eql(u8, self.graph.text(binding.name), root_name)) continue;
                var current_ty = binding.ty;
                var valid = true;
                for (segments[1..]) |segment| {
                    const hit = types.findField(self.graph, current_ty, candidate_module.text(segment)) orelse {
                        valid = false;
                        break;
                    };
                    current_ty = hit.field.storage_type orelse hit.field.ty;
                }
                if (valid) return current_ty;
            }
        }
        return null;
    }

    fn scoreInitializerInput(
        self: *Resolver,
        candidate_index: usize,
        pattern: @import("../module/parameterized/ir.zig").ParameterizedTypeId,
        user_fields: global_sg.FieldRange,
        input: global_sg.GlobalNodeId,
    ) !?u32 {
        const storage = &self.modules[candidate_index].semantic.parameterized_storage.ir;
        const shape = switch (storage.types.items[@intFromEnum(pattern)]) {
            .resolved => |ty| switch (ty) {
                .structural => |value| value,
                else => return null,
            },
            else => return null,
        };
        if (shape.fields.len == 0 or user_fields.len != shape.fields.len - 1) return null;
        const copied = try self.core.allocator.dupe(global_sg.Field, self.graph.fields.items[user_fields.start..][0..user_fields.len]);
        defer self.core.allocator.free(copied);
        const start: u32 = @intCast(self.graph.fields.items.len);
        try self.graph.fields.appendSlice(self.core.allocator, copied);
        for (storage.fields.items[shape.fields.start + 1 ..][0 .. shape.fields.len - 1], 0..) |field, offset| {
            if (field.default_value != null)
                self.graph.fields.items[start + @as(u32, @intCast(offset))].default_value = @enumFromInt(0);
        }
        return self.core.scoreCallInput(.{ .start = start, .len = user_fields.len }, input);
    }
'''

text = text[:start] + helper_block + text[end:]
constructors.write_text(text)

generic_functions = Path("src/4_semantics/global/generic_functions.zig")
replace_once(
    generic_functions,
    "        if (!try self.core.completeCallInputFields(self.graph.functions.items[@intFromEnum(function)].input, input)) return .deferred;\n",
    "        if (!try self.core.completeCallInputFieldsWithReach(self.graph.functions.items[@intFromEnum(function)].input, input, module, o, value.visible_bindings, value.owner_function)) return .deferred;\n",
    "generic function call completion",
)

Path(".github/semantic_refactor_test_command").write_text(
    "zig build test-programs -Dtest-filter=feature_tests/control_flow/14_for_mut_borrowed_dynamic_array\n"
)
Path(".git/semantic-refactor-message").write_text("Infer constructor generics from reach defaults\n")
