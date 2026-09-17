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
old = "return self.resolveExplicitGenericCall(module_index, o, value, reference, arguments);"
new = "return self.resolveExplicitGenericCall(module_index, module, o, value, reference, arguments);"
if text.count(old) != 1:
    raise RuntimeError(f"explicit constructor dispatch anchor changed: {text.count(old)}")
text = text.replace(old, new, 1)

old = "return self.resolveImplicitGenericCall(module_index, o, value, reference, declaration_id, input);"
new = "return self.resolveImplicitGenericCall(module_index, module, o, value, reference, declaration_id, input);"
if text.count(old) != 1:
    raise RuntimeError(f"implicit constructor dispatch anchor changed: {text.count(old)}")
text = text.replace(old, new, 1)

old = '''    fn resolveImplicitGenericCall(
        self: *Resolver,
        module_index: usize,
        o: globalizer.Offsets,
'''
new = '''    fn resolveImplicitGenericCall(
        self: *Resolver,
        module_index: usize,
        module: *const module_sg.ModuleSemanticGraph,
        o: globalizer.Offsets,
'''
if text.count(old) != 1:
    raise RuntimeError(f"implicit constructor signature anchor changed: {text.count(old)}")
text = text.replace(old, new, 1)

old = '''    fn resolveExplicitGenericCall(
        self: *Resolver,
        module_index: usize,
        o: globalizer.Offsets,
'''
new = '''    fn resolveExplicitGenericCall(
        self: *Resolver,
        module_index: usize,
        module: *const module_sg.ModuleSemanticGraph,
        o: globalizer.Offsets,
'''
if text.count(old) != 1:
    raise RuntimeError(f"explicit constructor signature anchor changed: {text.count(old)}")
text = text.replace(old, new, 1)

old = "if (!try self.core.completeCallInputFields(user_fields, input)) return .deferred;"
new = "if (!try self.core.completeCallInputFieldsWithReach(user_fields, input, module, o, value.visible_bindings, value.owner_function)) return .deferred;"
if text.count(old) != 4:
    raise RuntimeError(f"constructor completion anchors changed: {text.count(old)}")
text = text.replace(old, new)

# Focused trace for the explicit generic constructor path. This is intentionally
# transient: the workflow only commits if the focused test passes.
old = '''        const declaration_id = self.core.resolveDeclaration(module_index, reference, &.{.type}) catch |err| switch (err) {
            error.UnknownGlobalDeclaration => return .not_applicable,
            else => return err,
        };
'''
new = '''        const trace = std.mem.eql(u8, module.text(reference.name), "DynamicArray");
        const declaration_id = self.core.resolveDeclaration(module_index, reference, &.{.type}) catch |err| switch (err) {
            error.UnknownGlobalDeclaration => {
                if (trace) std.debug.print("[constructor-stage] declaration=unknown\\n", .{});
                return .not_applicable;
            },
            else => return err,
        };
        if (trace) std.debug.print("[constructor-stage] declaration={}\\n", .{@intFromEnum(declaration_id)});
'''
count = text.count(old)
if count != 2:
    raise RuntimeError(f"constructor declaration trace anchor changed: {count}")
first = text.find(old)
second = text.find(old, first + len(old))
if second < 0:
    raise RuntimeError("explicit constructor declaration trace anchor not found")
text = text[:second] + new + text[second + len(old):]

old = '''        _ = generics.ensureGenericInstance(ty) catch return .deferred;
'''
new = '''        _ = generics.ensureGenericInstance(ty) catch |err| {
            if (trace) std.debug.print("[constructor-stage] ensureGenericInstance={s}\\n", .{@errorName(err)});
            return .deferred;
        };
        if (trace) std.debug.print("[constructor-stage] generic-instance=ok type={}\\n", .{@intFromEnum(ty)});
'''
if text.count(old) != 1:
    raise RuntimeError(f"constructor generic instance trace anchor changed: {text.count(old)}")
text = text.replace(old, new, 1)

marker = '''        const initializer = try self.findGenericInitializer(
            &generics,
            &generic_functions,
            module_index,
            ty,
            arguments,
            input,
        );
'''
if text.count(marker) != 1:
    raise RuntimeError(f"explicit generic initializer trace anchor changed: {text.count(marker)}")
text = text.replace(marker, marker + '''        if (trace) std.debug.print("[constructor-stage] initializer function={} visible={}\\n", .{ initializer.function != null, initializer.has_visible_initializer });
''', 1)

old = '''            if (!try self.core.completeCallInputFieldsWithReach(user_fields, input, module, o, value.visible_bindings, value.owner_function)) return .deferred;
            self.writeInitializer(o, value, reference, declaration_id, ty, function_id, input);
            committed = true;
            return .resolved;
        }
        if (initializer.has_visible_initializer) return .deferred;

        const result = try self.writeStructuralConstruction(o, value, reference, ty, input);
'''
new = '''            const completed = try self.core.completeCallInputFieldsWithReach(user_fields, input, module, o, value.visible_bindings, value.owner_function);
            if (trace) std.debug.print("[constructor-stage] complete-input={} fields={}\\n", .{ completed, user_fields.len });
            if (!completed) return .deferred;
            self.writeInitializer(o, value, reference, declaration_id, ty, function_id, input);
            committed = true;
            return .resolved;
        }
        if (initializer.has_visible_initializer) {
            if (trace) std.debug.print("[constructor-stage] visible-init-without-selection\\n", .{});
            return .deferred;
        }

        const result = try self.writeStructuralConstruction(o, value, reference, ty, input);
        if (trace) std.debug.print("[constructor-stage] structural={s}\\n", .{@tagName(result)});
'''
if text.count(old) != 1:
    raise RuntimeError(f"explicit generic completion trace anchor changed: {text.count(old)}")
text = text.replace(old, new, 1)
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
Path(".git/semantic-refactor-message").write_text("Resolve reach defaults in generic calls\n")
