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
    '''        if (tied) return error.AmbiguousGenericFunction;\n        const declaration = best orelse return if (saw_deferred) error.DeferredGenericFunction else if (candidate_count == 1 and conflicting_candidates == 1) error.ConflictingGenericArgument else error.NoMatchingGenericFunction;\n        return self.instantiate(declaration, best_arguments);\n    }\n\n    /// Re-run implicit generic selection transactionally for diagnostics and\n''',
    '''        if (std.mem.eql(u8, name, "make_tracked")) {\n            std.debug.print(\n                "[make-tracked-generic] candidates={} conflicts={} deferred={} tied={} best={any} args={}+{}\\n",\n                .{ candidate_count, conflicting_candidates, saw_deferred, tied, if (best) |value| @intFromEnum(value) else null, best_arguments.start, best_arguments.len },\n            );\n        }\n        if (tied) return error.AmbiguousGenericFunction;\n        const declaration = best orelse return if (saw_deferred) error.DeferredGenericFunction else if (candidate_count == 1 and conflicting_candidates == 1) error.ConflictingGenericArgument else error.NoMatchingGenericFunction;\n        const instantiated = self.instantiate(declaration, best_arguments) catch |err| {\n            if (std.mem.eql(u8, name, "make_tracked"))\n                std.debug.print("[make-tracked-instantiate] declaration={} error={s}\\n", .{ @intFromEnum(declaration), @errorName(err) });\n            return err;\n        };\n        if (std.mem.eql(u8, name, "make_tracked"))\n            std.debug.print("[make-tracked-instantiate] declaration={} function={} success\\n", .{ @intFromEnum(declaration), @intFromEnum(instantiated) });\n        return instantiated;\n    }\n\n    /// Re-run implicit generic selection transactionally for diagnostics and\n''',
    "trace make_tracked generic selection and instantiation",
)
subprocess.run(["zig", "fmt", str(path)], check=True)
Path(".git/semantic-refactor-message").write_text("Trace make_tracked generic instantiation")
Path(".git/semantic-refactor-test-command").write_text(
    "zig build test-programs -Dtest-filter=feature_tests/collections/26_dynamic_array_owning_pop\n"
)
