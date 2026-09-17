from pathlib import Path
import subprocess


def replace_once(path: Path, old: str, new: str, label: str) -> None:
    text = path.read_text()
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label} anchor changed: {count}")
    path.write_text(text.replace(old, new, 1))


Path(".github/semantic_refactor_post_edit.py").write_text("# no-op diagnostic run\n")
path = Path("src/4_semantics/global/generic_functions.zig")
replace_once(
    path,
    '''                self.generics.bindGlobalArgumentsPartial(candidate_index, parameterized.parameters, arguments, &bindings) catch continue;\n                if (!try self.inferBindingsFromInput(candidate_index, parameterized.input, input, &bindings)) continue;\n                if (reach_context) |context|\n                    if (!try self.inferBindingsFromReachDefaults(candidate_index, parameterized.input, input, &bindings, context)) continue;\n''',
    '''                self.generics.bindGlobalArgumentsPartial(candidate_index, parameterized.parameters, arguments, &bindings) catch continue;\n                const input_inferred = self.inferBindingsFromInput(candidate_index, parameterized.input, input, &bindings) catch |err| switch (err) {\n                    error.ConflictingGenericArgument => continue,\n                    else => return err,\n                };\n                if (!input_inferred) continue;\n                if (reach_context) |context|\n                    if (!try self.inferBindingsFromReachDefaults(candidate_index, parameterized.input, input, &bindings, context)) continue;\n''',
    "explicit generic candidate-local input conflict",
)
subprocess.run(["zig", "fmt", str(path)], check=True)

test = Path("tests/feature_tests/collections/18_dynamic_array_copy/main.rg")
replace_once(
    test,
    '''    copied ::= ~copied_result..ok\n    #defer deinit(.self = $&copied, .allocator = system.allocator)\n\n    copied[0] = 99\n    push(.self = $&copied, .value = 30, .allocator = system.allocator)\n''',
    '''    copied ::= ~copied_result..ok\n    #defer deinit(.self = $&copied, .allocator = system.allocator)\n\n    if arr[0] != 10 {\n        status_code = 11\n        return\n    }\n    if copied[0] != 10 {\n        status_code = 12\n        return\n    }\n    if copied[1] != 20 {\n        status_code = 13\n        return\n    }\n    if arr.allocation.data == copied.allocation.data {\n        status_code = 14\n        return\n    }\n\n    copied[0] = 99\n    if arr[0] != 10 {\n        status_code = 21\n        return\n    }\n    if copied[0] != 99 {\n        status_code = 22\n        return\n    }\n\n    push(.self = $&copied, .value = 30, .allocator = system.allocator)\n    if arr[0] != 10 {\n        status_code = 31\n        return\n    }\n''',
    "dynamic array copy checkpoints",
)

Path(".git/semantic-refactor-message").write_text("Trace DynamicArray copy aliasing")
Path(".git/semantic-refactor-test-command").write_text(
    "zig build test-programs -Dtest-filter=feature_tests/collections/18_dynamic_array_copy\n"
)
