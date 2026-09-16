from pathlib import Path

# Reuse the generic-function unifier from constructor dispatch instead of
# growing a second inference implementation in constructors.zig.
generic_functions = Path("src/4_semantics/global/generic_functions.zig")
text = generic_functions.read_text()
for old, new in (
    ("    fn inferBindingsFromInput(\n", "    pub fn inferBindingsFromInput(\n"),
    ("    fn appendBoundArguments(\n", "    pub fn appendBoundArguments(\n"),
):
    if text.count(old) != 1:
        raise RuntimeError(f"generic inference anchor changed: {old!r} -> {text.count(old)}")
    text = text.replace(old, new, 1)
generic_functions.write_text(text)

# Parameterized-type identity belongs to the generic type resolver. Constructor
# dispatch asks this semantic query rather than interpreting declaration
# metadata such as generic_parameter_count.
generics_path = Path("src/4_semantics/global/generics.zig")
text = generics_path.read_text()
anchor = '''    fn findTypeParameterized(self: *Resolver, declaration: global_sg.GlobalDeclId) ?LocatedTypeParameterized {
'''
insert = '''    pub fn isParameterizedTypeDeclaration(self: *Resolver, declaration: global_sg.GlobalDeclId) bool {
        return self.findTypeParameterized(declaration) != null;
    }

'''
if text.count(anchor) != 1:
    raise RuntimeError(f"parameterized type query anchor changed: {text.count(anchor)}")
generics_path.write_text(text.replace(anchor, insert + anchor, 1))

constructors = Path("src/4_semantics/global/constructors.zig")
text = constructors.read_text()

old = '''    const InitializerProbe = struct {
        owns_type: bool = false,
        score: ?u32 = null,
    };
'''
new = '''    const InitializerProbe = struct {
        owns_type: bool = false,
        score: ?u32 = null,
    };

    const InferredInitializerLookup = struct {
        function: ?global_sg.GlobalFunctionId = null,
        constructed_type: ?global_sg.GlobalTypeId = null,
        has_visible_initializer: bool = false,
    };
'''
if text.count(old) != 1:
    raise RuntimeError(f"initializer probe anchor changed: {text.count(old)}")
text = text.replace(old, new, 1)

old = '''        const declaration = self.graph.declarations.items[@intFromEnum(declaration_id)];
        const ty = declaration.type_id orelse return .deferred;
        const input = globalizer.globalNode(o, value.input);

        const initializer = self.findInitializer(module_index, ty, input);
'''
new = '''        const declaration = self.graph.declarations.items[@intFromEnum(declaration_id)];
        const input = globalizer.globalNode(o, value.input);
        var generics = generic_mod.Resolver{
            .allocator = self.core.allocator,
            .graph = self.graph,
            .modules = self.modules,
            .offsets = self.offsets,
            .core = self.core,
        };
        if (generics.isParameterizedTypeDeclaration(declaration_id))
            return self.resolveImplicitGenericCall(module_index, o, value, reference, declaration_id, input);
        const ty = declaration.type_id orelse return .deferred;

        const initializer = self.findInitializer(module_index, ty, input);
'''
if text.count(old) != 1:
    raise RuntimeError(f"implicit constructor dispatch anchor changed: {text.count(old)}")
text = text.replace(old, new, 1)

anchor = '''    fn resolveExplicitGenericCall(
'''
insert = '''    fn resolveImplicitGenericCall(
        self: *Resolver,
        module_index: usize,
        o: globalizer.Offsets,
        value: anytype,
        reference: module_entities.ExternalRef,
        declaration_id: global_sg.GlobalDeclId,
        input: global_sg.GlobalNodeId,
    ) !resolution.Result {
        // Candidate inference interns temporary types and generic identities.
        // Keep the whole attempt transactional: if some dependency is still
        // unresolved, a later fixed-point round must start from the same graph.
        const pools = @typeInfo(global_sg.GlobalSemanticGraph).@"struct".fields;
        var lengths: [pools.len]usize = undefined;
        inline for (pools, 0..) |pool, index| lengths[index] = @field(self.graph, pool.name).items.len;
        var committed = false;
        defer if (!committed) {
            inline for (pools, 0..) |pool, index| @field(self.graph, pool.name).shrinkRetainingCapacity(lengths[index]);
        };

        var generics = generic_mod.Resolver{
            .allocator = self.core.allocator,
            .graph = self.graph,
            .modules = self.modules,
            .offsets = self.offsets,
            .core = self.core,
        };
        var generic_functions = generic_functions_mod.Resolver{
            .allocator = self.core.allocator,
            .graph = self.graph,
            .modules = self.modules,
            .offsets = self.offsets,
            .core = self.core,
            .generics = &generics,
            .nested_call_context = self.abstracts,
        };

        // Context can fully determine a generic constructor even when none of
        // the runtime arguments mention its type parameter (for example an
        // owning container whose element type appears only in `$&Container#`).
        if (value.expected_type) |local_expected| {
            const expected = globalizer.globalType(o, local_expected);
            if (!self.graph.isTypeUnresolved(expected)) switch (self.graph.types.items[@intFromEnum(expected)]) {
                .generic => |identity| if (identity.base == declaration_id) {
                    _ = generics.ensureGenericInstance(expected) catch return .deferred;
                    const initializer = try self.findGenericInitializer(
                        &generics,
                        &generic_functions,
                        module_index,
                        expected,
                        identity.arguments,
                        input,
                    );
                    if (initializer.function) |function_id| {
                        const function = self.graph.functions.items[@intFromEnum(function_id)];
                        const user_fields = global_sg.FieldRange{
                            .start = function.input.start + 1,
                            .len = function.input.len - 1,
                        };
                        if (!try self.core.completeCallInputFields(user_fields, input)) return .deferred;
                        self.writeInitializer(o, value, reference, declaration_id, expected, function_id, input);
                        committed = true;
                        return .resolved;
                    }
                    if (initializer.has_visible_initializer) return .deferred;
                },
                else => {},
            };
        }

        const initializer = try self.findImplicitGenericInitializer(
            &generics,
            &generic_functions,
            module_index,
            declaration_id,
            input,
        );
        if (initializer.function) |function_id| {
            const ty = initializer.constructed_type.?;
            const function = self.graph.functions.items[@intFromEnum(function_id)];
            const user_fields = global_sg.FieldRange{
                .start = function.input.start + 1,
                .len = function.input.len - 1,
            };
            if (!try self.core.completeCallInputFields(user_fields, input)) return .deferred;
            self.writeInitializer(o, value, reference, declaration_id, ty, function_id, input);
            committed = true;
            return .resolved;
        }

        // Generic type construction without an initializer needs inference
        // from the parameterized type body itself. Do not guess that mapping
        // here; a visible initializer also owns construction even when the
        // supplied arguments are not yet sufficient to select an overload.
        if (initializer.has_visible_initializer) return .deferred;
        return .deferred;
    }

'''
if text.count(anchor) != 1:
    raise RuntimeError(f"explicit generic constructor anchor changed: {text.count(anchor)}")
text = text.replace(anchor, insert + anchor, 1)

anchor = '''    fn findGenericInitializer(
'''
insert = '''    fn findImplicitGenericInitializer(
        self: *Resolver,
        generics: *generic_mod.Resolver,
        generic_functions: *generic_functions_mod.Resolver,
        module_index: usize,
        constructed_declaration: global_sg.GlobalDeclId,
        input: global_sg.GlobalNodeId,
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
    ) !InitializerProbe {
        // Inference may instantiate nested generic types while probing. Roll
        // every graph pool and generic statistic back before considering the
        // next overload so dispatch is observationally pure.
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
        if (!try generic_functions.inferBindingsFromInput(candidate_index, parameterized.input, input, &bindings))
            return .{ .owns_type = true };
        const input_ty = generics.instantiateParameterizedType(candidate_index, parameterized.input, &bindings, null) catch
            return .{ .owns_type = true };
        const fields = types.fields(self.graph, input_ty) orelse return .{ .owns_type = true };
        if (fields.len == 0) return .{ .owns_type = true };
        const user_fields = global_sg.FieldRange{
            .start = fields.start + 1,
            .len = fields.len - 1,
        };
        const score_match = if (self.abstracts) |abstracts|
            call_compatibility.matchInput(.{ .core = self.core, .abstracts = abstracts }, user_fields, input)
        else
            self.core.matchCallInput(user_fields, input);
        return switch (score_match) {
            .score => |score| .{ .owns_type = true, .score = score },
            .no_match, .deferred => .{ .owns_type = true },
        };
    }

    fn materializeImplicitGenericInitializer(
        self: *Resolver,
        generics: *generic_mod.Resolver,
        generic_functions: *generic_functions_mod.Resolver,
        declaration: global_sg.GlobalDeclId,
        constructed_declaration: global_sg.GlobalDeclId,
        input: global_sg.GlobalNodeId,
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
                if (!try generic_functions.inferBindingsFromInput(candidate_index, parameterized.input, input, &bindings)) return null;
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

'''
if text.count(anchor) != 1:
    raise RuntimeError(f"generic initializer anchor changed: {text.count(anchor)}")
text = text.replace(anchor, insert + anchor, 1)
constructors.write_text(text)

Path(".github/semantic_refactor_test_command").write_text(
    "zig build test-programs "
    "-Dtest-filter=feature_tests/control_flow/06_range_for "
    "-Dtest-filter=feature_tests/control_flow/07_range_step "
    "-Dtest-filter=feature_tests/control_flow/09_range_int64 "
    "-Dtest-filter=feature_tests/control_flow/10_range_default_start "
    "-Dtest-filter=feature_tests/control_flow/11_range_default_start_with_step\n"
)
Path(".git/semantic-refactor-message").write_text("Infer generic type constructors from initializers\n")
