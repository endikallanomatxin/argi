from pathlib import Path
import subprocess


def replace_once(path: Path, old: str, new: str, label: str) -> None:
    text = path.read_text()
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label} anchor changed: {count}")
    path.write_text(text.replace(old, new, 1))


path = Path("src/4_semantics/global/call_compatibility.zig")
replace_once(
    path,
    '''    pub fn compatible(self: @This(), actual: global_sg.GlobalTypeId, expected: global_sg.GlobalTypeId) bool {\n        const actual_pointer = switch (self.core.graph.types.items[@intFromEnum(actual)]) {\n            .pointer => |pointer| pointer,\n            else => return false,\n        };\n        const expected_pointer = switch (self.core.graph.types.items[@intFromEnum(expected)]) {\n            .pointer => |pointer| pointer,\n            else => return false,\n        };\n        if (expected_pointer.mutability == .read_write and actual_pointer.mutability != .read_write) return false;\n        return self.abstracts.concreteImplements(actual_pointer.child, expected_pointer.child);\n    }\n''',
    '''    pub fn compatible(self: @This(), actual: global_sg.GlobalTypeId, expected: global_sg.GlobalTypeId) bool {\n        const actual_pointer = switch (self.core.graph.types.items[@intFromEnum(actual)]) {\n            .pointer => |pointer| pointer,\n            else => return false,\n        };\n        const expected_pointer = switch (self.core.graph.types.items[@intFromEnum(expected)]) {\n            .pointer => |pointer| pointer,\n            else => return false,\n        };\n        if (expected_pointer.mutability == .read_write and actual_pointer.mutability != .read_write) return false;\n        const result = self.abstracts.concreteImplements(actual_pointer.child, expected_pointer.child);\n        std.debug.print(\n            "[abstract-compat] actual={} expected={} actual-child={}({s}) expected-child={}({s}) result={}\\n",\n            .{\n                @intFromEnum(actual),\n                @intFromEnum(expected),\n                @intFromEnum(actual_pointer.child),\n                @tagName(self.core.graph.types.items[@intFromEnum(actual_pointer.child)]),\n                @intFromEnum(expected_pointer.child),\n                @tagName(self.core.graph.types.items[@intFromEnum(expected_pointer.child)]),\n                result,\n            },\n        );\n        return result;\n    }\n''',
    "trace abstract call compatibility",
)
subprocess.run(["zig", "fmt", str(path)], check=True)
Path(".git/semantic-refactor-message").write_text("Trace ordinary abstract call compatibility")
Path(".git/semantic-refactor-test-command").write_text(
    "zig build test-programs -Dtest-filter=feature_tests/collections/26_dynamic_array_owning_pop\n"
)
