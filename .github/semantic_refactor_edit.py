from pathlib import Path
import subprocess


def replace_once(path: Path, old: str, new: str, label: str) -> None:
    text = path.read_text()
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label} anchor changed: {count}")
    path.write_text(text.replace(old, new, 1))


Path(".github/semantic_refactor_post_edit.py").write_text("# no-op diagnostic run\n")

# Real resolver fix under verification: a conflicting inferred binding rejects
# only that explicit-generic overload, just like implicit generic selection.
path = Path("src/4_semantics/global/generic_functions.zig")
replace_once(
    path,
    '''                self.generics.bindGlobalArgumentsPartial(candidate_index, parameterized.parameters, arguments, &bindings) catch continue;\n                if (!try self.inferBindingsFromInput(candidate_index, parameterized.input, input, &bindings)) continue;\n                if (reach_context) |context|\n                    if (!try self.inferBindingsFromReachDefaults(candidate_index, parameterized.input, input, &bindings, context)) continue;\n''',
    '''                self.generics.bindGlobalArgumentsPartial(candidate_index, parameterized.parameters, arguments, &bindings) catch continue;\n                const input_inferred = self.inferBindingsFromInput(candidate_index, parameterized.input, input, &bindings) catch |err| switch (err) {\n                    error.ConflictingGenericArgument => continue,\n                    else => return err,\n                };\n                if (!input_inferred) continue;\n                if (reach_context) |context|\n                    if (!try self.inferBindingsFromReachDefaults(candidate_index, parameterized.input, input, &bindings, context)) continue;\n''',
    "explicit generic candidate-local input conflict",
)
subprocess.run(["zig", "fmt", str(path)], check=True)

# Diagnostic only: stop the infallible DynamicArray copy after allocating its
# independent output. If the source array is still corrupted, the loop is not
# responsible.
dynamic = Path("core/lists/DynamicArray.rg")
text = dynamic.read_text()
copy_start = text.index("copy #(.t: Type: InfalliblyCopyable) (")
loop_start = text.index("    i :: UIntNative = 0\n", copy_start)
text = text[:loop_start] + "    result = ..ok ~out\n    return\n\n" + text[loop_start:]
dynamic.write_text(text)

# Diagnostic only: observe the source immediately after the shortened copy.
test = Path("tests/feature_tests/collections/18_dynamic_array_copy/main.rg")
text = test.read_text()
tail_start = text.index("    copied ::= ~copied_result..ok\n")
test.write_text(text[:tail_start] + '''    copied ::= ~copied_result..ok\n    #defer deinit(.self = $&copied, .allocator = system.allocator)\n\n    if arr[0] != 10 {\n        status_code = 11\n        return\n    }\n\n    status_code = 0\n}\n''')

Path(".git/semantic-refactor-message").write_text("Keep explicit generic conflicts candidate-local")
Path(".git/semantic-refactor-test-command").write_text(
    "zig build test-programs -Dtest-filter=feature_tests/collections/18_dynamic_array_copy\n"
)
