from pathlib import Path
import subprocess


def replace_once(path: Path, old: str, new: str, label: str) -> None:
    text = path.read_text()
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label} anchor changed: {count}")
    path.write_text(text.replace(old, new, 1))


Path(".github/semantic_refactor_post_edit.py").write_text("# no-op trace run\n")
path = Path("src/4_semantics/global/generic_functions.zig")
replace_once(
    path,
    '''        if (!try self.core.completeCallInputFieldsWithReach(self.graph.functions.items[@intFromEnum(function)].input, input, module, o, value.visible_bindings, value.owner_function)) return .deferred;\n        const output_ty = try self.core.functionOutputType(function);\n''',
    '''        const completed = try self.core.completeCallInputFieldsWithReach(self.graph.functions.items[@intFromEnum(function)].input, input, module, o, value.visible_bindings, value.owner_function);\n        if (std.mem.eql(u8, name, "copy")) {\n            const selected = self.graph.functions.items[@intFromEnum(function)];\n            std.debug.print("[copy-complete] function={} completed={} input-fields={}+{} visible={}+{}\\n", .{ @intFromEnum(function), completed, selected.input.start, selected.input.len, value.visible_bindings.start, value.visible_bindings.len });\n            for (self.graph.fields.items[selected.input.start..][0..selected.input.len]) |field|\n                std.debug.print("[copy-complete-field] name={s} ty={} default={any}\\n", .{ self.graph.text(field.name), @intFromEnum(field.ty), if (field.default_value) |id| @intFromEnum(id) else null });\n            const scope = module.semantic.binding_refs.items[value.visible_bindings.start..][0..value.visible_bindings.len];\n            for (scope) |local_binding| {\n                const global_binding = globalizer.globalBinding(o, local_binding);\n                const binding = self.graph.bindings.items[@intFromEnum(global_binding)];\n                std.debug.print("[copy-visible] name={s} ty={} unresolved={}\\n", .{ self.graph.text(binding.name), @intFromEnum(binding.ty), self.graph.isBindingTypeUnresolved(global_binding) or self.graph.isTypeUnresolved(binding.ty) });\n            }\n        }\n        if (!completed) return .deferred;\n        const output_ty = try self.core.functionOutputType(function);\n''',
    "generic source call completion trace",
)
subprocess.run(["zig", "fmt", str(path)], check=True)
Path(".git/semantic-refactor-message").write_text("Trace generic copy call completion")
Path(".git/semantic-refactor-test-command").write_text(
    "zig build test-programs -Dtest-filter=feature_tests/collections/18_dynamic_array_copy\n"
)
