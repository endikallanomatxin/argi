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
replacements = [
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
for old, new, label in replacements:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label} anchor changed: {count}")
    text = text.replace(old, new, 1)

old = "if (!try self.core.completeCallInputFields(user_fields, input)) return .deferred;"
new = "if (!try self.core.completeCallInputFieldsWithReach(user_fields, input, module, o, value.visible_bindings, value.owner_function)) return .deferred;"
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
Path(".git/semantic-refactor-message").write_text("Infer generic initializers through reached defaults\n")
