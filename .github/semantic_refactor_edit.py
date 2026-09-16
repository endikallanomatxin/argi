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
# All four initializer paths need the caller's reach context. Structural field-wise
# construction uses completeCallInputFields(fields, input) and remains unchanged.
if text.count(old) != 4:
    raise RuntimeError(f"constructor completion anchors changed: {text.count(old)}")
text = text.replace(old, new)
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
