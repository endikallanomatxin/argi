from pathlib import Path
import subprocess

def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label} anchor changed: {count}")
    return text.replace(old, new, 1)

core_path = Path("src/4_semantics/global/core.zig")
core = core_path.read_text()

ordinary_anchor = '''    fn matchFunctionNamed(
'''
reach_matcher = '''    pub fn matchUnqualifiedFunctionByNameWithReach(
        self: *Resolver,
        current_module: usize,
        name: []const u8,
        input_node: global_sg.GlobalNodeId,
        context: reach_context.Context,
    ) !FunctionMatch {
        var best: ?global_sg.GlobalFunctionId = null;
        var best_score: u32 = 0;
        var tied = false;
        var saw_deferred = false;
        for (self.graph.functions.items, 0..) |function, raw| {
            if (function.flags.is_abstract_dispatch) continue;
            const decl = self.graph.declarations.items[@intFromEnum(function.declaration)];
            if (!std.mem.eql(u8, self.graph.text(decl.name), name)) continue;
            if (!self.declarationVisible(current_module, function.declaration, null)) continue;
            const score = switch (try self.matchCallInputWithReach(function.input, input_node, context)) {
                .no_match => continue,
                .deferred => {
                    saw_deferred = true;
                    continue;
                },
                .score => |score| score,
            };
            if (best == null or score > best_score) {
                best = @enumFromInt(@as(u32, @intCast(raw)));
                best_score = score;
                tied = false;
            } else if (score == best_score) tied = true;
        }
        if (best) |function| {
            if (tied) return .ambiguous;
            return .{ .function = function };
        }
        if (saw_deferred) return .deferred;
        return .no_match;
    }

'''
if ordinary_anchor not in core:
    raise RuntimeError("reach-aware ordinary matcher insertion anchor missing")
core = core.replace(ordinary_anchor, reach_matcher + ordinary_anchor, 1)

input_anchor = '''    pub fn callInputNamesMatch(self: *const Resolver, expected_fields: global_sg.FieldRange, literal: anytype) bool {
'''
input_helpers = '''    pub fn matchCallInputWithReach(
        self: *Resolver,
        expected_fields: global_sg.FieldRange,
        input_node: global_sg.GlobalNodeId,
        context: reach_context.Context,
    ) !CallInputMatch {
        const base = self.matchCallInput(expected_fields, input_node);
        if (base != .score) return base;
        const literal = switch (self.graph.nodes.items[@intFromEnum(input_node)].content) {
            .struct_value_literal => |value| value,
            else => return .no_match,
        };
        for (0..expected_fields.len) |offset| {
            const expected = self.graph.fields.items[expected_fields.start + @as(u32, @intCast(offset))];
            if (self.callArgument(literal, offset, expected.name) != null) continue;
            const fallback = expected.default_value orelse return .no_match;
            if (self.graph.nodes.items[@intFromEnum(fallback)].content != .reach_directive) continue;
            switch (try self.probeReachedDefault(context, expected, fallback)) {
                .available => {},
                .deferred => return .deferred,
                .unavailable => return .no_match,
            }
        }
        return base;
    }

    const ReachedDefaultProbe = enum { unavailable, deferred, available };

    fn probeReachedDefault(
        self: *Resolver,
        context: reach_context.Context,
        expected_field: global_sg.Field,
        default_node: global_sg.GlobalNodeId,
    ) !ReachedDefaultProbe {
        const reach_id = self.graph.nodes.items[@intFromEnum(default_node)].content.reach_directive;
        const reach = self.graph.reaches.items[@intFromEnum(reach_id)];
        var saw_deferred = false;

        for (self.graph.reach_alternatives.items[reach.alternatives.start..][0..reach.alternatives.len]) |alternative| {
            if (alternative.segments.len == 0) continue;
            const segments = self.graph.reach_segments.items[alternative.segments.start..][0..alternative.segments.len];
            const root_name = self.graph.text(segments[0]);
            var scope_index = context.bindingCount();
            while (scope_index > 0) {
                scope_index -= 1;
                const binding_id = context.bindingAt(scope_index);
                const binding = self.graph.bindings.items[@intFromEnum(binding_id)];
                if (!std.mem.eql(u8, self.graph.text(binding.name), root_name)) continue;
                if (self.graph.isBindingTypeUnresolved(binding_id) or self.graph.isTypeUnresolved(binding.ty)) {
                    saw_deferred = true;
                    continue;
                }

                var current_ty = binding.ty;
                var valid = true;
                for (segments[1..]) |segment| {
                    if (self.graph.isTypeUnresolved(current_ty)) {
                        saw_deferred = true;
                        valid = false;
                        break;
                    }
                    const hit = types.findField(self.graph, current_ty, self.graph.text(segment)) orelse {
                        valid = false;
                        break;
                    };
                    current_ty = hit.field.storage_type orelse hit.field.ty;
                }
                if (!valid) continue;
                if (self.graph.isTypeUnresolved(current_ty)) {
                    saw_deferred = true;
                    continue;
                }
                if (types.equal(self.graph, current_ty, expected_field.ty) or
                    self.callTypesCompatible(current_ty, expected_field.ty))
                    return .available;
            }
        }

        const owner_id = context.ownerFunction() orelse
            return if (saw_deferred) .deferred else .unavailable;
        const owner = self.graph.functions.items[@intFromEnum(owner_id)];
        const owner_name = self.graph.text(self.graph.declarations.items[@intFromEnum(owner.declaration)].name);
        if (std.mem.eql(u8, owner_name, "main"))
            return if (saw_deferred) .deferred else .unavailable;

        for (self.graph.fields.items[owner.input.start..][0..owner.input.len]) |field| {
            if (!std.mem.eql(u8, self.graph.text(field.name), self.graph.text(expected_field.name))) continue;
            if (self.graph.isTypeUnresolved(field.ty) or self.graph.isTypeUnresolved(expected_field.ty))
                return .deferred;
            return if (types.equal(self.graph, field.ty, expected_field.ty) or
                self.callTypesCompatible(field.ty, expected_field.ty) or
                self.callTypesCompatible(expected_field.ty, field.ty))
                .available
            else
                .unavailable;
        }

        // completeCallInputFieldsWithReach can propagate a missing reach
        // parameter into a non-main caller. Ranking may acknowledge that
        // possibility, but must not mutate the caller while probing overloads.
        return .available;
    }

'''
core = replace_once(core, input_anchor, input_helpers + input_anchor, "reach-aware input matcher")
core_path.write_text(core)

dispatch_path = Path("src/4_semantics/global/dispatch.zig")
dispatch = dispatch_path.read_text()
dispatch = replace_once(
    dispatch,
    "        const ordinary = try self.core.matchUnqualifiedFunctionByName(module_index, name, input);\n",
    "        const ordinary = try self.core.matchUnqualifiedFunctionByNameWithReach(module_index, name, input, reach);\n",
    "implicit ordinary reach ranking",
)
dispatch_path.write_text(dispatch)

parameterized_lowerer_path = Path("src/4_semantics/module/parameterized/lowerer.zig")
parameterized_lowerer = parameterized_lowerer_path.read_text()

lower_params_old = '''    fn lowerParameters(self: *Context, params: []const syn.NodeIndex, params_struct: ?syn.NodeIndex) !primitives.Range(ir.ComptimeParameterId) {
        const start: u32 = @intCast(self.graph.semantic.parameterized_storage.comptime_parameters.items.len);
        if (params_struct) |struct_node| {
            const literal = self.tree.structTypeLiteral(struct_node) orelse return error.InvalidGenericParameters;
            for (literal.fields) |field_node| {
                const field = self.tree.structTypeField(field_node) orelse return error.InvalidGenericParameter;
                const name_text = self.tree.tokenTextFromSource(self.source, field.name_token);
                const value_type_node = field.type_node orelse return error.InvalidGenericParameter;
                const kind: parameterized_storage.ComptimeParameterKind = if (isTypeParameter(self.tree, self.source, field)) .type else .comptime_int;
                const id: ir.ComptimeParameterId = @enumFromInt(@as(u32, @intCast(self.graph.semantic.parameterized_storage.comptime_parameters.items.len)));
                try self.graph.semantic.parameterized_storage.comptime_parameters.append(self.allocator, .{
                    .name = try self.writer.addString(name_text),
                    .kind = kind,
                    .value_type = if (kind == .comptime_int) try self.lowerType(value_type_node, false) else null,
                });
                try self.parameters.append(.{ .name = name_text, .id = id, .kind = kind });
            }
        } else {
            for (params) |param_node| {
                const name_text = self.tree.tokenTextFromSource(self.source, self.tree.mainToken(param_node));
                const id: ir.ComptimeParameterId = @enumFromInt(@as(u32, @intCast(self.graph.semantic.parameterized_storage.comptime_parameters.items.len)));
                try self.graph.semantic.parameterized_storage.comptime_parameters.append(self.allocator, .{
                    .name = try self.writer.addString(name_text),
                    .kind = .type,
                });
                try self.parameters.append(.{ .name = name_text, .id = id, .kind = .type });
            }
        }
        return .{ .start = start, .len = @intCast(self.graph.semantic.parameterized_storage.comptime_parameters.items.len - start) };
    }

'''
lower_params_new = '''    fn lowerParameters(self: *Context, params: []const syn.NodeIndex, params_struct: ?syn.NodeIndex) !primitives.Range(ir.ComptimeParameterId) {
        const start: u32 = @intCast(self.graph.semantic.parameterized_storage.comptime_parameters.items.len);
        if (params_struct) |struct_node| {
            const literal = self.tree.structTypeLiteral(struct_node) orelse return error.InvalidGenericParameters;

            // Register every parameter before lowering bounds. Bounds may refer
            // to associated parameters declared later in the same generic list,
            // e.g. t: Type: FalliblyCopyable#(.reasons: element_reasons).
            for (literal.fields) |field_node| {
                const field = self.tree.structTypeField(field_node) orelse return error.InvalidGenericParameter;
                const name_text = self.tree.tokenTextFromSource(self.source, field.name_token);
                _ = field.type_node orelse return error.InvalidGenericParameter;
                const kind: parameterized_storage.ComptimeParameterKind =
                    if (isTypeParameter(self.tree, self.source, field)) .type else .comptime_int;
                const id: ir.ComptimeParameterId = @enumFromInt(@as(u32, @intCast(self.graph.semantic.parameterized_storage.comptime_parameters.items.len)));
                try self.graph.semantic.parameterized_storage.comptime_parameters.append(self.allocator, .{
                    .name = try self.writer.addString(name_text),
                    .kind = kind,
                });
                try self.parameters.append(.{ .name = name_text, .id = id, .kind = kind });
            }

            for (literal.fields, 0..) |field_node, offset| {
                const field = self.tree.structTypeField(field_node) orelse return error.InvalidGenericParameter;
                const value_type_node = field.type_node orelse return error.InvalidGenericParameter;
                const parameter_record = &self.graph.semantic.parameterized_storage.comptime_parameters.items[
                    start + @as(u32, @intCast(offset))
                ];
                switch (parameter_record.kind) {
                    .comptime_int => parameter_record.value_type = try self.lowerType(value_type_node, false),
                    .type => {
                        if (!isTypeBuiltin(self.tree, self.source, value_type_node))
                            parameter_record.constraint = try self.lowerAbstractConstraint(value_type_node);
                    },
                }
            }
        } else {
            for (params) |param_node| {
                const name_text = self.tree.tokenTextFromSource(self.source, self.tree.mainToken(param_node));
                const id: ir.ComptimeParameterId = @enumFromInt(@as(u32, @intCast(self.graph.semantic.parameterized_storage.comptime_parameters.items.len)));
                try self.graph.semantic.parameterized_storage.comptime_parameters.append(self.allocator, .{
                    .name = try self.writer.addString(name_text),
                    .kind = .type,
                });
                try self.parameters.append(.{ .name = name_text, .id = id, .kind = .type });
            }
        }
        return .{ .start = start, .len = @intCast(self.graph.semantic.parameterized_storage.comptime_parameters.items.len - start) };
    }

    fn lowerAbstractConstraint(self: *Context, node: syn.NodeIndex) !parameterized_storage.AbstractConstraintId {
        const syntax_type = self.tree.syntaxType(node) orelse return error.ExpectedAbstractType;
        var base_node = node;
        var arguments_node: ?syn.NodeIndex = null;
        switch (syntax_type) {
            .name => {},
            .generic => |generic| {
                base_node = generic.base;
                arguments_node = generic.arguments;
            },
            else => return error.ExpectedAbstractType,
        }

        const base = self.tree.syntaxType(base_node) orelse return error.ExpectedAbstractType;
        if (base != .name) return error.ExpectedAbstractType;
        const name = self.tree.tokenTextFromSource(self.source, base.name.name_token);
        const local_declaration =
            if (base.name.qualifier_token == null) self.localAbstractType(name) else null;
        const abstract_ref: ir.DeclarationRef = if (local_declaration) |declaration|
            .{ .module = declaration }
        else
            .{ .external = try self.writer.addExternalRef(.{
                .kind = .abstract,
                .module_path = if (base.name.qualifier_token) |qualifier|
                    try self.writer.addString(self.tree.tokenTextFromSource(self.source, qualifier))
                else
                    null,
                .name = try self.writer.addString(name),
                .source = self.sourceRef(base_node),
            }) };

        var arguments: std.ArrayList(ir.GenericArgument) = .empty;
        defer arguments.deinit(self.allocator);
        if (arguments_node) |args_node| {
            const literal = self.tree.structTypeLiteral(args_node) orelse return error.InvalidAbstractArguments;
            for (literal.fields) |field_node| {
                const field = self.tree.structTypeField(field_node) orelse return error.InvalidAbstractArgument;
                const value: ir.GenericArgument.Value = if (field.type_node) |type_node|
                    .{ .type = try self.lowerType(type_node, false) }
                else if (field.default_value) |value_node|
                    try self.lowerGenericValue(value_node, false)
                else
                    return error.InvalidAbstractArgument;
                try arguments.append(self.allocator, .{
                    .name = try self.writer.addString(self.tree.tokenTextFromSource(self.source, field.name_token)),
                    .value = value,
                });
            }
        }

        const argument_start: u32 = @intCast(self.graph.semantic.parameterized_storage.ir.generic_arguments.items.len);
        try self.graph.semantic.parameterized_storage.ir.generic_arguments.appendSlice(self.allocator, arguments.items);
        const id: parameterized_storage.AbstractConstraintId =
            @enumFromInt(@as(u32, @intCast(self.graph.semantic.parameterized_storage.abstract_constraints.items.len)));
        try self.graph.semantic.parameterized_storage.abstract_constraints.append(self.allocator, .{
            .abstract_ref = abstract_ref,
            .arguments = .{ .start = argument_start, .len = @intCast(arguments.items.len) },
            .source = self.sourceRef(node),
        });
        return id;
    }

'''
parameterized_lowerer = replace_once(
    parameterized_lowerer,
    lower_params_old,
    lower_params_new,
    "explicit generic parameter constraint lowering",
)
parameterized_lowerer_path.write_text(parameterized_lowerer)
subprocess.run(["zig", "fmt", str(parameterized_lowerer_path)], check=True)

generic_path = Path("src/4_semantics/global/generic_functions.zig")
generic = generic_path.read_text()
generic = replace_once(
    generic,
    '''            if (!try self.resolver.core.completeCallInputFields(self.resolver.graph.functions.items[@intFromEnum(function)].input, input)) return error.IncompleteParameterizedCallInput;
            return .{
''',
    '''            if (std.mem.eql(u8, name, "copy")) {
                const selected = self.resolver.graph.functions.items[@intFromEnum(function)];
                const decl = self.resolver.graph.declarations.items[@intFromEnum(selected.declaration)];
                const file = self.resolver.graph.files.items[decl.source.file_index];
                std.debug.print(
                    "[parameterized-copy] module={} fn={} decl={} source={s}:{} generic={}\\n",
                    .{
                        self.module_index,
                        @intFromEnum(function),
                        @intFromEnum(selected.declaration),
                        self.resolver.graph.text(file.path),
                        decl.source.offset,
                        selected.flags.is_generic_instantiation,
                    },
                );
                for (self.resolver.graph.generic_function_instances.items) |instance| {
                    if (instance.function != function) continue;
                    for (self.resolver.graph.generic_arguments.items[instance.arguments.start..][0..instance.arguments.len]) |arg| {
                        switch (arg.value) {
                            .type => |ty| std.debug.print(
                                "[parameterized-copy-arg] {s}=type:{}\\n",
                                .{ self.resolver.graph.text(arg.name), @intFromEnum(ty) },
                            ),
                            .comptime_int => |value| std.debug.print(
                                "[parameterized-copy-arg] {s}=int:{}\\n",
                                .{ self.resolver.graph.text(arg.name), value },
                            ),
                        }
                    }
                }
            }
            if (!try self.resolver.core.completeCallInputFields(self.resolver.graph.functions.items[@intFromEnum(function)].input, input)) return error.IncompleteParameterizedCallInput;
            return .{
''',
    "parameterized copy callee trace",
)
generic = replace_once(
    generic,
    '''            const function = if (arguments.len != 0)
                try self.resolver.resolveExplicitGenericFunction(self.module_index, module, reference, arguments, input, null)
            else
                self.resolver.core.resolveFunctionByName(self.module_index, reference, input) catch
                    self.resolver.resolveImplicitGenericFunction(self.module_index, module, reference, input, null) catch |err| {
                    if (self.resolver.nested_constructor_context) |context| {
                        if (self.resolver.nested_constructor_resolver) |resolve| {
                            if (try resolve(context, self.module_index, reference, arguments, input, self.resolver.sourceFor(self.module_index, source))) |node|
                                return node;
                        }
                    }
                    if (arguments.len == 0) {
                        if (try self.resolveConstrainedStaticCall(reference, input, source)) |node| return node;
                    }
                    if (self.resolver.nested_call_context) |context| {
                        if (self.resolver.nested_call_resolver) |resolve| {
                            if (try resolve(context, self.module_index, reference, input, self.resolver.sourceFor(self.module_index, source))) |node|
                                return node;
                        }
                    }
                    if (module_path == null and std.mem.eql(u8, name, "deinit") and
                        self.parameterized.safety_primitive == .trusted_opaque_drop)
                        return self.emptyValue(try self.resolver.generics.internType(.{ .builtin = .Void }), source);
                    return err;
                };
''',
    '''            const nested_reach = ReachInferenceContext.fromGlobal(&.{}, self.function);
            const function = if (arguments.len != 0)
                try self.resolver.resolveExplicitGenericFunction(self.module_index, module, reference, arguments, input, nested_reach)
            else blk: {
                const ordinary = if (module_path == null)
                    try self.resolver.core.matchUnqualifiedFunctionByNameWithReach(self.module_index, name, input, nested_reach)
                else
                    try self.resolver.core.matchFunctionByName(self.module_index, reference, input);
                if (ordinary == .function) break :blk ordinary.function;
                break :blk self.resolver.resolveImplicitGenericFunction(self.module_index, module, reference, input, nested_reach) catch |err| {
                    if (self.resolver.nested_constructor_context) |context| {
                        if (self.resolver.nested_constructor_resolver) |resolve| {
                            if (try resolve(context, self.module_index, reference, arguments, input, self.resolver.sourceFor(self.module_index, source))) |node|
                                return node;
                        }
                    }
                    if (arguments.len == 0) {
                        if (try self.resolveConstrainedStaticCall(reference, input, source)) |node| return node;
                    }
                    if (self.resolver.nested_call_context) |context| {
                        if (self.resolver.nested_call_resolver) |resolve| {
                            if (try resolve(context, self.module_index, reference, input, self.resolver.sourceFor(self.module_index, source))) |node|
                                return node;
                        }
                    }
                    if (module_path == null and std.mem.eql(u8, name, "deinit") and
                        self.parameterized.safety_primitive == .trusted_opaque_drop)
                        return self.emptyValue(try self.resolver.generics.internType(.{ .builtin = .Void }), source);
                    return err;
                };
            };
''',
    "nested generic reach resolution",
)
generic = replace_once(
    generic,
    '''            if (!try self.resolver.core.completeCallInputFields(self.resolver.graph.functions.items[@intFromEnum(function)].input, input)) return error.IncompleteParameterizedCallInput;
''',
    '''            if (!try self.resolver.core.completeCallInputFieldsWithReach(
                self.resolver.graph.functions.items[@intFromEnum(function)].input,
                input,
                nested_reach,
            )) return error.IncompleteParameterizedCallInput;
''',
    "nested generic reach completion",
)
constraint_method_anchor = '''    pub fn appendBoundArguments(
'''
constraint_method = '''    fn inferAndValidateConstraints(
        self: *Resolver,
        module_index: usize,
        parameters: primitives.Range(ir.ComptimeParameterId),
        bindings: *generic_mod.Resolver.Bindings,
    ) !bool {
        const abstracts = self.nested_call_context orelse return true;
        const storage = &self.modules[module_index].semantic.parameterized_storage;

        var made_progress = true;
        while (made_progress) {
            made_progress = false;
            var before: usize = 0;
            for (parameters.start..parameters.start + parameters.len) |raw| {
                const parameter = storage.comptime_parameters.items[raw];
                before += switch (parameter.kind) {
                    .type => @intFromBool(bindings.types[raw] != null),
                    .comptime_int => @intFromBool(bindings.ints[raw] != null),
                };
            }

            for (parameters.start..parameters.start + parameters.len) |raw| {
                const parameter = storage.comptime_parameters.items[raw];
                const constraint_id = parameter.constraint orelse continue;
                if (parameter.kind != .type) continue;
                const concrete = bindings.types[raw] orelse continue;
                if (!try abstracts.inferConstraintBindings(module_index, constraint_id, concrete, bindings))
                    return false;
            }

            var after: usize = 0;
            for (parameters.start..parameters.start + parameters.len) |raw| {
                const parameter = storage.comptime_parameters.items[raw];
                after += switch (parameter.kind) {
                    .type => @intFromBool(bindings.types[raw] != null),
                    .comptime_int => @intFromBool(bindings.ints[raw] != null),
                };
            }
            made_progress = after > before;
        }

        for (parameters.start..parameters.start + parameters.len) |raw| {
            const parameter = storage.comptime_parameters.items[raw];
            const constraint_id = parameter.constraint orelse continue;
            if (parameter.kind != .type) return false;
            const concrete = bindings.types[raw] orelse return false;
            if (!try abstracts.inferConstraintBindings(module_index, constraint_id, concrete, bindings))
                return false;
        }
        return true;
    }

'''
if constraint_method_anchor not in generic:
    raise RuntimeError("generic constraint method anchor missing")
generic = generic.replace(constraint_method_anchor, constraint_method + constraint_method_anchor, 1)

generic = replace_once(
    generic,
    '''                if (reach_context) |context|
                    if (!try self.inferBindingsFromReachDefaults(candidate_index, parameterized.input, input, &bindings, context)) continue;
                const complete_arguments = self.appendBoundArguments(candidate_index, parameterized.parameters, &bindings) catch |err| switch (err) {
''',
    '''                if (reach_context) |context|
                    if (!try self.inferBindingsFromReachDefaults(candidate_index, parameterized.input, input, &bindings, context)) continue;
                if (!try self.inferAndValidateConstraints(candidate_index, parameterized.parameters, &bindings)) continue;
                const complete_arguments = self.appendBoundArguments(candidate_index, parameterized.parameters, &bindings) catch |err| switch (err) {
''',
    "explicit generic constraint selection",
)

generic = replace_once(
    generic,
    '''                if (reach_context) |context|
                    if (!try self.inferBindingsFromReachDefaults(candidate_index, parameterized.input, input, &bindings, context)) continue;
                var arguments: std.ArrayList(global_sg.GenericArgument) = .empty;
''',
    '''                if (reach_context) |context|
                    if (!try self.inferBindingsFromReachDefaults(candidate_index, parameterized.input, input, &bindings, context)) continue;
                if (!try self.inferAndValidateConstraints(candidate_index, parameterized.parameters, &bindings)) continue;
                var arguments: std.ArrayList(global_sg.GenericArgument) = .empty;
''',
    "implicit generic constraint selection",
)

generic = replace_once(
    generic,
    '''        )) return null;
        const arguments = self.appendBoundArguments(
            located.module_index,
            located.parameterized.parameters,
            &bindings,
        ) catch return null;
        return try self.instantiate(declaration, arguments);
''',
    '''        )) return null;
        if (!try self.inferAndValidateConstraints(located.module_index, located.parameterized.parameters, &bindings))
            return null;
        const arguments = self.appendBoundArguments(
            located.module_index,
            located.parameterized.parameters,
            &bindings,
        ) catch return null;
        return try self.instantiate(declaration, arguments);
''',
    "initializer generic constraint inference",
)

generic = replace_once(
    generic,
    '''        try self.generics.bindGlobalArguments(located.module_index, located.parameterized.parameters, arguments, &substitutions);

        const input_ty = try self.generics.instantiateParameterizedType(located.module_index, located.parameterized.input, &substitutions, null);
''',
    '''        try self.generics.bindGlobalArguments(located.module_index, located.parameterized.parameters, arguments, &substitutions);
        if (!try self.inferAndValidateConstraints(located.module_index, located.parameterized.parameters, &substitutions))
            return error.GenericAbstractConstraintNotSatisfied;

        const input_ty = try self.generics.instantiateParameterizedType(located.module_index, located.parameterized.input, &substitutions, null);
''',
    "generic instantiation constraint backstop",
)

generic = replace_once(
    generic,
    '''                const declaration = globalizer.globalDecl(self.offsets[candidate_index], parameterized.declaration);
                if (!std.mem.eql(u8, self.graph.text(self.graph.declarations.items[@intFromEnum(declaration)].name), name)) continue;
                if (!self.core.declarationVisible(current_module, declaration, module_filter)) continue;
                candidate_count += 1;
''',
    '''                const declaration = globalizer.globalDecl(self.offsets[candidate_index], parameterized.declaration);
                if (!std.mem.eql(u8, self.graph.text(self.graph.declarations.items[@intFromEnum(declaration)].name), name)) continue;
                if (std.mem.eql(u8, name, "copy")) {
                    const decl_record = self.graph.declarations.items[@intFromEnum(declaration)];
                    const file = self.graph.files.items[decl_record.source.file_index];
                    std.debug.print(
                        "[copy-candidate] decl={} source={s}:{} params={}\\n",
                        .{ @intFromEnum(declaration), self.graph.text(file.path), decl_record.source.offset, parameterized.parameters.len },
                    );
                    for (parameterized.parameters.start..parameterized.parameters.start + parameterized.parameters.len) |raw_param| {
                        const p = candidate_module.semantic.parameterized_storage.comptime_parameters.items[raw_param];
                        std.debug.print(
                            "[copy-candidate-param] {s} kind={s} constraint={?}\\n",
                            .{ candidate_module.text(p.name), @tagName(p.kind), if (p.constraint) |id| @intFromEnum(id) else null },
                        );
                    }
                }
                if (!self.core.declarationVisible(current_module, declaration, module_filter)) continue;
                candidate_count += 1;
''',
    "copy candidate constraint metadata trace",
)

generic_path.write_text(generic)

for path in (core_path, dispatch_path, generic_path):
    subprocess.run(["zig", "fmt", str(path)], check=True)


constructors_path = Path("src/4_semantics/global/constructors.zig")
constructors = constructors_path.read_text()

constructors = replace_once(
    constructors,
    '''    fn findInitializer(self: *Resolver, module_index: usize, constructed_ty: global_sg.GlobalTypeId, input: global_sg.GlobalNodeId) InitializerLookup {
''',
    '''    fn findInitializer(
        self: *Resolver,
        module_index: usize,
        constructed_ty: global_sg.GlobalTypeId,
        input: global_sg.GlobalNodeId,
        context: ?reach_context.Context,
    ) InitializerLookup {
''',
    "initializer reach context",
)
nested_initializer_call = '''        const initializer = self.findInitializer(module_index, ty, input);
'''
if constructors.count(nested_initializer_call) != 2:
    raise RuntimeError(f"initializer caller count changed: {constructors.count(nested_initializer_call)}")
constructors = constructors.replace(
    nested_initializer_call,
    '''        const initializer = self.findInitializer(module_index, ty, input, null);
''',
    1,
)
constructors = constructors.replace(
    nested_initializer_call,
    '''        const initializer = self.findInitializer(
            module_index,
            ty,
            input,
            reach_context.Context.fromModule(module, o, value.visible_bindings, value.owner_function),
        );
''',
    1,
)
constructors = replace_once(
    constructors,
    '''            const score_match = if (self.abstracts) |abstracts|
                call_compatibility.matchInput(.{ .core = self.core, .abstracts = abstracts }, user_fields, input)
            else
                self.core.matchCallInput(user_fields, input);
''',
    '''            const score_match = if (!function.flags.is_abstract_dispatch and context != null)
                self.core.matchCallInputWithReach(user_fields, input, context.?) catch .deferred
            else if (self.abstracts) |abstracts|
                call_compatibility.matchInput(.{ .core = self.core, .abstracts = abstracts }, user_fields, input)
            else
                self.core.matchCallInput(user_fields, input);
''',
    "concrete initializer reach ranking",
)
constructors = replace_once(
    constructors,
    '''            } else if (score == best_score) {
                tied = true;
            }
''',
    '''            } else if (score == best_score) {
                const selected = self.graph.functions.items[@intFromEnum(result.function.?)];
                if (selected.declaration == function.declaration and
                    selected.flags.is_abstract_dispatch != function.flags.is_abstract_dispatch)
                {
                    if (selected.flags.is_abstract_dispatch and !function.flags.is_abstract_dispatch)
                        result.function = @enumFromInt(@as(u32, @intCast(raw)));
                    tied = false;
                } else {
                    tied = true;
                }
            }
''',
    "initializer template-instance tie",
)
trace_anchor = '''        const initializer = self.findInitializer(
            module_index,
            ty,
            input,
            reach_context.Context.fromModule(module, o, value.visible_bindings, value.owner_function),
        );
'''
if constructors.count(trace_anchor) < 1:
    raise RuntimeError("string constructor trace anchor missing")
constructors = constructors.replace(
    trace_anchor,
    trace_anchor + '''        if (std.mem.eql(u8, module.text(reference.name), "String")) {
            std.debug.print(
                "[string-constructor] target={} input={} initializer={?} visible={}\\n",
                .{
                    @intFromEnum(globalizer.globalNode(o, value.node)),
                    @intFromEnum(input),
                    if (initializer.function) |function| @intFromEnum(function) else null,
                    initializer.has_visible_initializer,
                },
            );
        }
''',
    1,
)
constructors_path.write_text(constructors)
subprocess.run(["zig", "fmt", str(constructors_path)], check=True)


abstracts_path = Path("src/4_semantics/global/abstracts.zig")
abstracts = abstracts_path.read_text()

constraint_anchor = '''    pub fn implements(
'''
constraint_helpers = '''    fn implementsDepth(
        self: *Resolver,
        concrete: global_sg.GlobalTypeId,
        abstract_decl: global_sg.GlobalDeclId,
        depth: u8,
    ) !bool {
        if (depth >= 64) return false;
        for (self.modules, 0..) |*module, module_index| {
            for (module.semantic.parameterized_storage.abstract_implementations.items) |implementation| {
                const candidate_abstract = try self.resolveDeclarationRef(module_index, implementation.abstract_ref, .abstract_type);
                if (candidate_abstract != abstract_decl) continue;
                const candidate_type = globalizer.globalType(self.offsets[module_index], implementation.ty);
                if (global_types.equal(self.graph, concrete, candidate_type)) {
                    self.stats.concrete_hits += 1;
                    return true;
                }
                const inherited = switch (self.graph.types.items[@intFromEnum(candidate_type)]) {
                    .declared => |declaration| declaration,
                    else => continue,
                };
                if (inherited == abstract_decl or self.findAbstractDefinition(inherited) == null) continue;
                if (try self.implementsDepth(concrete, inherited, depth + 1)) {
                    self.stats.concrete_hits += 1;
                    return true;
                }
            }
            for (module.semantic.parameterized_storage.parameterized_abstract_implementations.items) |parameterized| {
                const candidate_abstract = try self.resolveDeclarationRef(module_index, parameterized.abstract_ref, .abstract_type);
                if (candidate_abstract != abstract_decl) continue;
                if (self.matchesImplementationParameterized(module_index, concrete, parameterized) catch false) {
                    self.stats.parameterized_hits += 1;
                    return true;
                }
            }
        }
        return false;
    }

    pub fn inferConstraintBindings(
        self: *Resolver,
        module_index: usize,
        constraint_id: parameterized_storage.AbstractConstraintId,
        concrete: global_sg.GlobalTypeId,
        bindings: *generic_mod.Resolver.Bindings,
    ) !bool {
        const module = &self.modules[module_index];
        const storage = &module.semantic.parameterized_storage;
        const constraint = storage.abstract_constraints.items[@intFromEnum(constraint_id)];
        const abstract_decl = try self.resolveDeclarationRef(module_index, constraint.abstract_ref, .abstract_type);
        if (!try self.implementsDepth(concrete, abstract_decl, 0)) return false;
        if (constraint.arguments.len == 0) return true;

        const located = self.findAbstractDefinition(abstract_decl) orelse return false;
        for (self.modules, 0..) |*implementation_module, implementation_module_index| {
            const implementation_storage = &implementation_module.semantic.parameterized_storage;
            for (implementation_storage.abstract_implementations.items) |implementation| {
                const candidate_abstract = try self.resolveDeclarationRef(
                    implementation_module_index,
                    implementation.abstract_ref,
                    .abstract_type,
                );
                if (candidate_abstract != abstract_decl) continue;
                const candidate_type = globalizer.globalType(self.offsets[implementation_module_index], implementation.ty);
                if (!global_types.equal(self.graph, concrete, candidate_type)) continue;
                return self.matchDirectConstraintArguments(
                    module_index,
                    constraint,
                    located,
                    implementation_module_index,
                    implementation,
                    bindings,
                );
            }
        }
        return false;
    }

    fn matchDirectConstraintArguments(
        self: *Resolver,
        constraint_module_index: usize,
        constraint: parameterized_storage.AbstractConstraint,
        located: LocatedAbstractDefinition,
        implementation_module_index: usize,
        implementation: parameterized_storage.AbstractImplementation,
        bindings: *generic_mod.Resolver.Bindings,
    ) !bool {
        if (implementation.arguments.len != located.definition.parameters.len) return false;
        const constraint_module = &self.modules[constraint_module_index];
        const constraint_ir = &constraint_module.semantic.parameterized_storage.ir;
        const target_module = &self.modules[located.module_index];
        const target_storage = &target_module.semantic.parameterized_storage;
        const implementation_storage = &self.modules[implementation_module_index].semantic.parameterized_storage;

        for (constraint_ir.generic_arguments.items[constraint.arguments.start..][0..constraint.arguments.len], 0..) |requested, requested_position| {
            const requested_name = constraint_module.text(requested.name);
            var target_offset: ?usize = null;
            if (requested_name.len == 0) {
                if (requested_position < located.definition.parameters.len) target_offset = requested_position;
            } else {
                for (0..located.definition.parameters.len) |offset| {
                    const raw = located.definition.parameters.start + @as(u32, @intCast(offset));
                    const parameter = target_storage.comptime_parameters.items[raw];
                    if (std.mem.eql(u8, target_module.text(parameter.name), requested_name)) {
                        target_offset = offset;
                        break;
                    }
                }
            }
            const offset = target_offset orelse return false;
            const associated = implementation_storage.abstract_arguments.items[
                implementation.arguments.start + @as(u32, @intCast(offset))
            ];
            switch (requested.value) {
                .type => |pattern| {
                    const actual = switch (associated) {
                        .type => |local| globalizer.globalType(self.offsets[implementation_module_index], local),
                        else => return false,
                    };
                    if (!try self.inferConstraintTypePattern(constraint_module_index, pattern, actual, bindings))
                        return false;
                },
                .comptime_int => |pattern| {
                    const actual = switch (associated) {
                        .comptime_int => |value| value,
                        else => return false,
                    };
                    if (!try self.inferConstraintIntPattern(constraint_module_index, pattern, actual, bindings))
                        return false;
                },
            }
        }
        return true;
    }

    fn inferConstraintTypePattern(
        self: *Resolver,
        module_index: usize,
        pattern: ir.ParameterizedTypeId,
        actual: global_sg.GlobalTypeId,
        bindings: *generic_mod.Resolver.Bindings,
    ) !bool {
        const ir_storage = &self.modules[module_index].semantic.parameterized_storage.ir;
        switch (ir_storage.types.items[@intFromEnum(pattern)]) {
            .parameter => |parameter| {
                const slot = &bindings.types[@intFromEnum(parameter)];
                if (slot.*) |previous|
                    return global_types.equal(self.graph, previous, actual);
                slot.* = actual;
                return true;
            },
            else => {},
        }
        const expected = self.generics.instantiateParameterizedType(module_index, pattern, bindings, null) catch return false;
        return global_types.equal(self.graph, expected, actual);
    }

    fn inferConstraintIntPattern(
        self: *Resolver,
        module_index: usize,
        pattern: ir.ParameterizedIntExprId,
        actual: i64,
        bindings: *generic_mod.Resolver.Bindings,
    ) !bool {
        const ir_storage = &self.modules[module_index].semantic.parameterized_storage.ir;
        return switch (ir_storage.int_expressions.items[@intFromEnum(pattern)]) {
            .literal => |value| value == actual,
            .parameter => |parameter| blk: {
                const slot = &bindings.ints[@intFromEnum(parameter)];
                if (slot.*) |previous| break :blk previous == actual;
                slot.* = actual;
                break :blk true;
            },
            .binary => (self.generics.evalInt(module_index, pattern, bindings) catch return false) == actual,
        };
    }

'''
if constraint_anchor not in abstracts:
    raise RuntimeError("constraint helper insertion anchor missing")
abstracts = abstracts.replace(constraint_anchor, constraint_helpers + constraint_anchor, 1)
abstracts = replace_once(
    abstracts,
    '''        self.stats.checks += 1;
        for (self.modules, 0..) |*module, module_index| {
            for (module.semantic.parameterized_storage.abstract_implementations.items) |implementation| {
                const candidate_abstract = try self.resolveDeclarationRef(module_index, implementation.abstract_ref, .abstract_type);
                if (candidate_abstract != abstract_decl) continue;
                const candidate_type = globalizer.globalType(self.offsets[module_index], implementation.ty);
                if (global_types.equal(self.graph, concrete, candidate_type)) {
                    self.stats.concrete_hits += 1;
                    return true;
                }
            }
            for (module.semantic.parameterized_storage.parameterized_abstract_implementations.items) |parameterized| {
                const candidate_abstract = try self.resolveDeclarationRef(module_index, parameterized.abstract_ref, .abstract_type);
                if (candidate_abstract != abstract_decl) continue;
                if (try self.matchesImplementationParameterized(module_index, concrete, parameterized)) {
                    self.stats.parameterized_hits += 1;
                    return true;
                }
            }
        }
        return false;
''',
    '''        self.stats.checks += 1;
        return self.implementsDepth(concrete, abstract_decl, 0);
''',
    "transitive abstract implementation resolution",
)
abstracts = replace_once(
    abstracts,
    '''            const parameterized = self.findFunctionParameterized(module_index, instance.parameterized_declaration) orelse continue;
            const module = &self.modules[module_index];
''',
    '''            const parameterized = self.findFunctionParameterized(module_index, instance.parameterized_declaration) orelse {
                const decl = self.graph.declarations.items[@intFromEnum(instance.parameterized_declaration)];
                const file = self.graph.files.items[decl.source.file_index];
                std.debug.print(
                    "[generic-instance-unmatched] fn={} decl={} source={s}:{}\\n",
                    .{ @intFromEnum(instance.function), @intFromEnum(instance.parameterized_declaration), self.graph.text(file.path), decl.source.offset },
                );
                continue;
            };
            const module = &self.modules[module_index];
''',
    "generic instance parameterized lookup trace",
)

abstracts = replace_once(
    abstracts,
    '''                const concrete = bindings.types[param_raw] orelse return error.AbstractConstraintRequiresTypeParameter;
                if (!try self.implements(concrete, abstract_decl)) return error.GenericAbstractConstraintNotSatisfied;
''',
    '''                const concrete = bindings.types[param_raw] orelse return error.AbstractConstraintRequiresTypeParameter;
                const satisfied = try self.implements(concrete, abstract_decl);
                const abstract_name = self.graph.text(self.graph.declarations.items[@intFromEnum(abstract_decl)].name);
                std.debug.print(
                    "[generic-constraint] fn={} decl={} param={s} concrete={} abstract={s} satisfied={}\\n",
                    .{
                        @intFromEnum(instance.function),
                        @intFromEnum(instance.parameterized_declaration),
                        module.text(parameter.name),
                        @intFromEnum(concrete),
                        abstract_name,
                        satisfied,
                    },
                );
                if (!satisfied) return error.GenericAbstractConstraintNotSatisfied;
''',
    "generic constraint validation trace",
)
abstracts_path.write_text(abstracts)
subprocess.run(["zig", "fmt", str(abstracts_path)], check=True)

Path(".git/semantic-refactor-test-command").write_text(
    "status=0; "
    "timeout 60s ./zig-out/bin/argi build tests/feature_tests/collections/34_dynamic_array_string_copy || status=1; "
    "timeout 60s ./zig-out/bin/argi build tests/feature_tests/collections/35_dynamic_array_fallible_copy_cleanup || status=1; "
    "timeout 60s zig build test-programs -Dtest-filter=feature_tests/text/02_string_copy || status=1; "
    "timeout 60s zig build test-programs -Dtest-filter=feature_tests/collections/18_dynamic_array_copy || status=1; "
    "timeout 60s zig build test-programs -Dtest-filter=feature_tests/collections/34_dynamic_array_string_copy || status=1; "
    "timeout 60s zig build test-programs -Dtest-filter=feature_tests/collections/35_dynamic_array_fallible_copy_cleanup || status=1; "
    "exit 1;\n"
)
