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
text = path.read_text()
old = '''        const declaration = best orelse return if (saw_deferred) error.DeferredGenericFunction else error.NoMatchingGenericFunction;\n        return self.instantiate(declaration, best_arguments);\n    }\n\n    pub fn inferBindingsFromInput(\n'''
new = '''        const declaration = best orelse return if (saw_deferred) error.DeferredGenericFunction else error.NoMatchingGenericFunction;\n        return self.instantiate(declaration, best_arguments) catch |err| {\n            if (std.mem.eql(u8, name, "copy"))\n                std.debug.print("[copy-instantiate] decl={} args={}+{} failed={s}\\n", .{ @intFromEnum(declaration), best_arguments.start, best_arguments.len, @errorName(err) });\n            return err;\n        };\n    }\n\n    pub fn inferBindingsFromInput(\n'''
if text.count(old) != 1:
    raise RuntimeError(f"copy instantiate anchor changed: {text.count(old)}")
path.write_text(text.replace(old, new, 1))
subprocess.run(["zig", "fmt", str(path)], check=True)
Path(".git/semantic-refactor-message").write_text("Trace DynamicArray copy instantiation")
Path(".git/semantic-refactor-test-command").write_text(
    "zig build test-programs -Dtest-filter=feature_tests/collections/18_dynamic_array_copy\n"
)
