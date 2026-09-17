from pathlib import Path
import subprocess


def replace_once(path: Path, old: str, new: str, label: str) -> None:
    text = path.read_text()
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label} anchor changed: {count}")
    path.write_text(text.replace(old, new, 1))


generic_functions = Path("src/4_semantics/global/generic_functions.zig")
replace_once(
    generic_functions,
    '''    nested_call_context: ?*abstract_mod.Resolver = null,\n    nested_call_resolver: ?*const fn (*abstract_mod.Resolver, usize, module_entities.ExternalRef, global_sg.GlobalNodeId, primitives.SourceRef) anyerror!?global_sg.Node = null,\n    stats: Stats = .{},\n''',
    '''    nested_call_context: ?*abstract_mod.Resolver = null,\n    nested_call_resolver: ?*const fn (*abstract_mod.Resolver, usize, module_entities.ExternalRef, global_sg.GlobalNodeId, primitives.SourceRef) anyerror!?global_sg.Node = null,\n    nested_constructor_context: ?*anyopaque = null,\n    nested_constructor_resolver: ?*const fn (*anyopaque, usize, module_entities.ExternalRef, primitives.Range(global_sg.GlobalGenericArgId), global_sg.GlobalNodeId, primitives.SourceRef) anyerror!?global_sg.Node = null,\n    stats: Stats = .{},\n''',
    "nested constructor callback fields",
)
replace_once(
    generic_functions,
    '''                self.resolver.core.resolveFunctionByName(self.module_index, reference, input) catch\n                    self.resolver.resolveImplicitGenericFunction(self.module_index, module, reference, input, null) catch |err| {\n                    if (self.resolver.nested_call_context) |context| {\n''',
    '''                self.resolver.core.resolveFunctionByName(self.module_index, reference, input) catch\n                    self.resolver.resolveImplicitGenericFunction(self.module_index, module, reference, input, null) catch |err| {\n                    if (self.resolver.nested_constructor_context) |context| {\n                        if (self.resolver.nested_constructor_resolver) |resolve| {\n                            if (try resolve(context, self.module_index, reference, arguments, input, self.resolver.sourceFor(self.module_index, source))) |node|\n                                return node;\n                        }\n                    }\n                    if (self.resolver.nested_call_context) |context| {\n''',
    "nested constructor fallback",
)

constructors = Path("src/4_semantics/global/constructors.zig")
replace_once(
    constructors,
    '''    pub fn tryResolve(\n        self: *Resolver,\n''',
    '''    /// Resolve a constructor encountered while materializing a generic\n    /// function body. Only non-parameterized declarations are handled here;\n    /// parameterized construction still needs the caller's generic/reach\n    /// context and remains on the normal constructor path. Structural\n    /// construction is never allowed to bypass a visible initializer.\n    pub fn resolveNestedCall(\n        context_ptr: *anyopaque,\n        module_index: usize,\n        reference: module_entities.ExternalRef,\n        arguments: primitives.Range(global_sg.GlobalGenericArgId),\n        input: global_sg.GlobalNodeId,\n        source: primitives.SourceRef,\n    ) anyerror!?global_sg.Node {\n        const self: *Resolver = @ptrCast(@alignCast(context_ptr));\n        if (arguments.len != 0) return null;\n\n        const declaration_id = self.core.resolveDeclaration(module_index, reference, &.{.type}) catch |err| switch (err) {\n            error.UnknownGlobalDeclaration => return null,\n            else => return err,\n        };\n        const declaration = self.graph.declarations.items[@intFromEnum(declaration_id)];\n        var generics = generic_mod.Resolver{\n            .allocator = self.core.allocator,\n            .graph = self.graph,\n            .modules = self.modules,\n            .offsets = self.offsets,\n            .core = self.core,\n        };\n        if (generics.isParameterizedTypeDeclaration(declaration_id)) return null;\n        const ty = declaration.type_id orelse return null;\n\n        const initializer = self.findInitializer(module_index, ty, input);\n        if (initializer.has_visible_initializer) return null;\n\n        const fields = types.fields(self.graph, ty) orelse return null;\n        switch (self.core.matchCallInput(fields, input)) {\n            .score => {},\n            .no_match, .deferred => return null,\n        }\n        if (!try self.core.completeCallInputFields(fields, input)) return null;\n        self.graph.nodes.items[@intFromEnum(input)].ty = ty;\n        var node = self.graph.nodes.items[@intFromEnum(input)];\n        node.source = source;\n        self.core.stats.calls += 1;\n        return node;\n    }\n\n    pub fn tryResolve(\n        self: *Resolver,\n''',
    "nested structural constructor resolver",
)

semantizer = Path("src/4_semantics/global/semantizer.zig")
replace_once(
    semantizer,
    '''    generic_functions.nested_call_context = &abstracts;\n    generic_functions.nested_call_resolver = abstract_mod.Resolver.resolveNestedCall;\n''',
    '''    generic_functions.nested_call_context = &abstracts;\n    generic_functions.nested_call_resolver = abstract_mod.Resolver.resolveNestedCall;\n    generic_functions.nested_constructor_context = &constructors;\n    generic_functions.nested_constructor_resolver = constructor_mod.Resolver.resolveNestedCall;\n''',
    "wire nested constructor resolver",
)

checker = Path("src/4_semantics/safety/checker.zig")
replace_once(
    checker,
    '''fn valueDependsOnDeadRoot(value: facts.ValueFacts, state: *const SafetyChecker.FunctionState) bool {\n    for (value.dependencies) |dependency| if (!state.tracker.isAlive(dependency.root)) return true;\n    for (value.fields) |field| if (valueDependsOnDeadRoot(field.value.*, state)) return true;\n    for (value.variants) |variant| if (valueDependsOnDeadRoot(variant.value.*, state)) return true;\n    return false;\n}\n''',
    '''fn valueDependsOnDeadRoot(value: facts.ValueFacts, state: *const SafetyChecker.FunctionState) bool {\n    for (value.dependencies) |dependency| {\n        if (!state.tracker.isAlive(dependency.root)) {\n            const root = state.tracker.roots.items[@intFromEnum(dependency.root)];\n            std.debug.print(\n                "[escape-root] root={} state={s} owned-resource={} owned-here={} deps={} fields={} variants={}\\n",\n                .{ @intFromEnum(dependency.root), @tagName(root.state), root.owned_resource, containsRoot(value.owned_roots, dependency.root), value.dependencies.len, value.fields.len, value.variants.len },\n            );\n            return true;\n        }\n    }\n    for (value.fields) |field| if (valueDependsOnDeadRoot(field.value.*, state)) return true;\n    for (value.variants) |variant| if (valueDependsOnDeadRoot(variant.value.*, state)) return true;\n    return false;\n}\n''',
    "trace escaping root state",
)

subprocess.run(["zig", "fmt", str(generic_functions), str(constructors), str(semantizer), str(checker)], check=True)
Path(".git/semantic-refactor-message").write_text("Resolve structural constructors in generic bodies")
Path(".git/semantic-refactor-test-command").write_text(
    "zig build test-programs -Dtest-filter=feature_tests/collections/26_dynamic_array_owning_pop\n"
)
