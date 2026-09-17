from pathlib import Path
import subprocess


def replace_once(path: Path, old: str, new: str, label: str) -> None:
    text = path.read_text()
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label} anchor changed: {count}")
    path.write_text(text.replace(old, new, 1))


# Generic inference can see construction-time poison IDs while GlobalSema is
# still inferring binding types. They are deferred inputs, never indexable types.
generic_functions = Path("src/4_semantics/global/generic_functions.zig")
replace_once(
    generic_functions,
    '''    ) anyerror!bool {\n        const module = &self.modules[module_index];\n        const storage = &module.semantic.parameterized_storage.ir;\n''',
    '''    ) anyerror!bool {\n        const actual_raw: usize = @intFromEnum(actual);\n        if (actual_raw >= self.graph.types.items.len or self.graph.isTypeUnresolved(actual)) return false;\n        const module = &self.modules[module_index];\n        const storage = &module.semantic.parameterized_storage.ir;\n''',
    "unresolved generic input guard",
)

# Constrained type parameters such as `.t: Type: ImplicitlyCopyable` are stored
# by syntaxing with the bound as field.type_node. Reuse the canonical classifier
# in abstract implementation/default lowering instead of treating those as ints.
lowerer = Path("src/4_semantics/module/parameterized/lowerer.zig")
replace_once(
    lowerer,
    '''fn isTypeParameter(tree: *const syn.FileSyntaxTree, source: []const u8, field: syn.StructTypeField) bool {\n''',
    '''pub fn isTypeParameter(tree: *const syn.FileSyntaxTree, source: []const u8, field: syn.StructTypeField) bool {\n''',
    "export type parameter classifier",
)

relations = Path("src/4_semantics/module/abstract_relation_lowerer.zig")
replace_once(
    relations,
    '''                const kind: parameterized_storage.ComptimeParameterKind = if (field.type_node) |type_node|\n                    if (isTypeName(self.tree, self.source, type_node, "Type")) .type else .comptime_int\n                else\n                    .type;\n''',
    '''                const kind: parameterized_storage.ComptimeParameterKind = if (parameterized_lowerer.isTypeParameter(self.tree, self.source, field)) .type else .comptime_int;\n''',
    "abstract relation generic parameter classifier",
)

subprocess.run([
    "zig", "fmt",
    "src/4_semantics/global/generic_functions.zig",
    "src/4_semantics/module/parameterized/lowerer.zig",
    "src/4_semantics/module/abstract_relation_lowerer.zig",
], check=True)

Path(".git/semantic-refactor-message").write_text("Unify constrained generic parameter classification")
Path(".git/semantic-refactor-test-command").write_text(
    "zig build test-programs "
    "-Dtest-filter=feature_tests/control_flow/04_for_dynamic_array "
    "-Dtest-filter=feature_tests/control_flow/14_for_mut_borrowed_dynamic_array\n"
)
