from pathlib import Path
import subprocess


def replace_once(path: Path, old: str, new: str, label: str) -> None:
    text = path.read_text()
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label} anchor changed: {count}")
    path.write_text(text.replace(old, new, 1))


path = Path("src/4_semantics/global/generic_functions.zig")
replace_once(
    path,
    '''        const name = module.text(reference.name);\n        var best: ?global_sg.GlobalDeclId = null;\n''',
    '''        const name = module.text(reference.name);\n        std.debug.print("[explicit-generic] current_module={} name={s} args={}\\n", .{ current_module, name, arguments.len });\n        var best: ?global_sg.GlobalDeclId = null;\n''',
    "explicit generic call trace",
)
replace_once(
    path,
    '''                const actual = self.graph.nodes.items[@intFromEnum(value.value)].ty orelse return false;\n                if (!try self.inferInputType(module_index, field.ty, actual, bindings)) return false;\n''',
    '''                const actual = self.graph.nodes.items[@intFromEnum(value.value)].ty orelse return false;\n                std.debug.print(\n                    "[infer-input-field] candidate_module={} field={s} actual={} {any}\\n",\n                    .{ module_index, self.modules[module_index].text(field.name), @intFromEnum(actual), self.graph.types.items[@intFromEnum(actual)] },\n                );\n                if (!try self.inferInputType(module_index, field.ty, actual, bindings)) return false;\n''',
    "input field inference trace",
)
replace_once(
    path,
    '''                    const matched = self.inferInputType(module_index, field.ty, current_ty, bindings) catch |err| switch (err) {\n''',
    '''                    std.debug.print(\n                        "[infer-reach-field] candidate_module={} field={s} root={s} actual={} {any}\\n",\n                        .{ module_index, candidate_module.text(field.name), root_name, @intFromEnum(current_ty), self.graph.types.items[@intFromEnum(current_ty)] },\n                    );\n                    const matched = self.inferInputType(module_index, field.ty, current_ty, bindings) catch |err| switch (err) {\n''',
    "reach field inference trace",
)
replace_once(
    path,
    '''                const actual = self.resolver.graph.node(value.value).ty orelse return null;\n                // Concrete fields are checked by the contextual matcher after\n''',
    '''                const actual = self.resolver.graph.node(value.value).ty orelse return null;\n                std.debug.print(\n                    "[initializer-field] module={} field={s} actual={} {any}\\n",\n                    .{ located.module_index, module.text(field.name), @intFromEnum(actual), self.resolver.graph.types.items[@intFromEnum(actual)] },\n                );\n                // Concrete fields are checked by the contextual matcher after\n''',
    "initializer inference trace",
)
replace_once(
    path,
    '''                const slot = &bindings.types[@intFromEnum(parameter)];\n                if (slot.*) |previous| {\n                    if (!global_types.equal(self.graph, previous, actual)) return error.ConflictingGenericArgument;\n                    return true;\n                }\n''',
    '''                const slot = &bindings.types[@intFromEnum(parameter)];\n                if (slot.*) |previous| {\n                    if (!global_types.equal(self.graph, previous, actual)) {\n                        const parameter_info = self.modules[module_index].semantic.parameterized_storage.comptime_parameters.items[@intFromEnum(parameter)];\n                        std.debug.print(\n                            "[generic-type-conflict] module={} parameter={} name={s} previous={} {any} actual={} {any}\\n",\n                            .{ module_index, @intFromEnum(parameter), self.modules[module_index].text(parameter_info.name), @intFromEnum(previous), self.graph.types.items[@intFromEnum(previous)], @intFromEnum(actual), self.graph.types.items[@intFromEnum(actual)] },\n                        );\n                        switch (self.graph.types.items[@intFromEnum(previous)]) {\n                            .declared => |declaration| std.debug.print("  previous-decl={} name={s}\\n", .{ @intFromEnum(declaration), self.graph.text(self.graph.declarations.items[@intFromEnum(declaration)].name) }),\n                            else => {},\n                        }\n                        switch (self.graph.types.items[@intFromEnum(actual)]) {\n                            .declared => |declaration| std.debug.print("  actual-decl={} name={s}\\n", .{ @intFromEnum(declaration), self.graph.text(self.graph.declarations.items[@intFromEnum(declaration)].name) }),\n                            else => {},\n                        }\n                        return error.ConflictingGenericArgument;\n                    }\n                    return true;\n                }\n''',
    "named type parameter conflict trace",
)
subprocess.run(["zig", "fmt", str(path)], check=True)
Path(".git/semantic-refactor-test-command").write_text(
    "zig build test-programs -Dtest-filter=feature_tests/collections/23_dynamic_array_owning_push_fixed\n"
)
