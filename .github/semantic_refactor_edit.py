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
    '''        const function = if (local_args) |args|\n            self.resolveExplicitGenericFunction(module_index, module, reference, try self.generics.relocateModuleArguments(module_index, args), input, reach_context) catch |err| switch (err) {\n                error.NoMatchingGenericFunction => return .not_applicable,\n                error.DeferredGenericFunction => return .deferred,\n                error.AmbiguousGenericFunction => return .invalid,\n                else => return .deferred,\n            }\n''',
    '''        const function = if (local_args) |args|\n            self.resolveExplicitGenericFunction(module_index, module, reference, try self.generics.relocateModuleArguments(module_index, args), input, reach_context) catch |err| {\n                if (std.mem.eql(u8, name, "copy"))\n                    std.debug.print("[copy-explicit-error] {s}\\n", .{@errorName(err)});\n                return switch (err) {\n                    error.NoMatchingGenericFunction => .not_applicable,\n                    error.DeferredGenericFunction => .deferred,\n                    error.AmbiguousGenericFunction => .invalid,\n                    else => .deferred,\n                };\n            }\n''',
    "explicit generic call-site error trace",
)
subprocess.run(["zig", "fmt", str(path)], check=True)
Path(".git/semantic-refactor-message").write_text("Trace explicit generic copy resolver errors")
Path(".git/semantic-refactor-test-command").write_text(
    "zig build test-programs -Dtest-filter=feature_tests/collections/18_dynamic_array_copy\n"
)
