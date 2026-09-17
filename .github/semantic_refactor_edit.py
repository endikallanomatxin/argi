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
    '''                const slot = &bindings.types[@intFromEnum(parameter)];\n                if (slot.*) |previous| {\n                    if (!global_types.equal(self.graph, previous, actual)) return error.ConflictingGenericArgument;\n                    return true;\n                }\n''',
    '''                const slot = &bindings.types[@intFromEnum(parameter)];\n                if (slot.*) |previous| {\n                    if (!global_types.equal(self.graph, previous, actual)) {\n                        const parameter_info = self.modules[module_index].semantic.parameterized_storage.comptime_parameters.items[@intFromEnum(parameter)];\n                        std.debug.print(\n                            "[generic-type-conflict] module={} parameter={} name={s} previous={} {any} actual={} {any}\\n",\n                            .{ module_index, @intFromEnum(parameter), self.modules[module_index].text(parameter_info.name), @intFromEnum(previous), self.graph.types.items[@intFromEnum(previous)], @intFromEnum(actual), self.graph.types.items[@intFromEnum(actual)] },\n                        );\n                        switch (self.graph.types.items[@intFromEnum(previous)]) {\n                            .declared => |declaration| std.debug.print("  previous-decl={} name={s}\\n", .{ @intFromEnum(declaration), self.graph.text(self.graph.declarations.items[@intFromEnum(declaration)].name) }),\n                            else => {},\n                        }\n                        switch (self.graph.types.items[@intFromEnum(actual)]) {\n                            .declared => |declaration| std.debug.print("  actual-decl={} name={s}\\n", .{ @intFromEnum(declaration), self.graph.text(self.graph.declarations.items[@intFromEnum(declaration)].name) }),\n                            else => {},\n                        }\n                        return error.ConflictingGenericArgument;\n                    }\n                    return true;\n                }\n''',
    "named type parameter conflict trace",
)
subprocess.run(["zig", "fmt", str(path)], check=True)
Path(".git/semantic-refactor-test-command").write_text(
    "zig build test-programs -Dtest-filter=feature_tests/collections/23_dynamic_array_owning_push_fixed\n"
)
