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
    '''                const slot = &bindings.types[@intFromEnum(parameter)];\n                if (slot.*) |previous| {\n                    if (!global_types.equal(self.graph, previous, actual)) {\n                        std.debug.print(\n                            "[generic-type-conflict] module={} parameter={} previous={} {any} actual={} {any}\\n",\n                            .{ module_index, @intFromEnum(parameter), @intFromEnum(previous), self.graph.types.items[@intFromEnum(previous)], @intFromEnum(actual), self.graph.types.items[@intFromEnum(actual)] },\n                        );\n                        return error.ConflictingGenericArgument;\n                    }\n                    return true;\n                }\n''',
    "type parameter conflict trace",
)
replace_once(
    path,
    '''                            if (err == error.ConflictingGenericArgument) {\n                                conflicting_candidates += 1;\n                                matches = false;\n                                break;\n                            }\n''',
    '''                            if (err == error.ConflictingGenericArgument) {\n                                std.debug.print(\n                                    "[generic-call-conflict] name={s} candidate_module={} field={s} actual={}\\n",\n                                    .{ name, candidate_index, candidate_module.text(field.name), @intFromEnum(actual) },\n                                );\n                                conflicting_candidates += 1;\n                                matches = false;\n                                break;\n                            }\n''',
    "implicit generic conflict trace",
)
subprocess.run(["zig", "fmt", str(path)], check=True)
Path(".git/semantic-refactor-test-command").write_text(
    "zig build test-programs -Dtest-filter=feature_tests/collections/23_dynamic_array_owning_push_fixed\n"
)
