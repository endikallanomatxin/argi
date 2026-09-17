from pathlib import Path
import subprocess


def replace_once(path: Path, old: str, new: str, label: str) -> None:
    text = path.read_text()
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label} anchor changed: {count}")
    path.write_text(text.replace(old, new, 1))


# Generic inference is called from several fixed-point dispatch paths, including
# constructor #reach probing. A binding whose type has not been inferred yet
# carries a deliberately invalid poison GlobalTypeId; that is a deferred input,
# not a type that may be indexed in graph.types.
generic_functions = Path("src/4_semantics/global/generic_functions.zig")
replace_once(
    generic_functions,
    '''    ) anyerror!bool {\n        const module = &self.modules[module_index];\n        const storage = &module.semantic.parameterized_storage.ir;\n''',
    '''    ) anyerror!bool {\n        const actual_raw: usize = @intFromEnum(actual);\n        if (actual_raw >= self.graph.types.items.len or self.graph.isTypeUnresolved(actual)) return false;\n        const module = &self.modules[module_index];\n        const storage = &module.semantic.parameterized_storage.ir;\n''',
    "unresolved generic input guard",
)

# Temporary focused traces: identify both the concrete generic identity being
# materialized and the parameter/argument pair whose kinds disagree.
generics = Path("src/4_semantics/global/generics.zig")
replace_once(
    generics,
    '''        const located = self.findTypeParameterized(identity.base) orelse return false;\n        var bindings = try Bindings.init(self.allocator, self.modules[located.module_index].semantic.parameterized_storage.comptime_parameters.items.len);\n''',
    '''        const located = self.findTypeParameterized(identity.base) orelse return false;\n        const base_decl = self.graph.declarations.items[@intFromEnum(identity.base)];\n        std.debug.print(\n            "[generic-instance] base={s} base_decl={} module={} parameters={}+{} arguments={}+{}\\n",\n            .{ self.graph.text(base_decl.name), @intFromEnum(identity.base), located.module_index, located.parameterized.parameters.start, located.parameterized.parameters.len, identity.arguments.start, identity.arguments.len },\n        );\n        var bindings = try Bindings.init(self.allocator, self.modules[located.module_index].semantic.parameterized_storage.comptime_parameters.items.len);\n''',
    "generic instance source trace",
)
replace_once(
    generics,
    '''            switch (parameter.kind) {\n                .type => switch (argument.value) {\n                    .type => |value| bindings.types[param_raw] = value,\n                    else => return error.GenericArgumentKindMismatch,\n                },\n                .comptime_int => switch (argument.value) {\n                    .comptime_int => |value| bindings.ints[param_raw] = value,\n                    else => return error.GenericArgumentKindMismatch,\n                },\n            }\n''',
    '''            switch (parameter.kind) {\n                .type => switch (argument.value) {\n                    .type => |value| bindings.types[param_raw] = value,\n                    else => {\n                        std.debug.print(\n                            "[generic-kind-mismatch] module={} parameter={s} expected=type argument={s} actual={s} position={} range={}+{}\\n",\n                            .{ module_index, module.text(parameter.name), self.graph.text(argument.name), @tagName(argument.value), position, arguments.start, arguments.len },\n                        );\n                        return error.GenericArgumentKindMismatch;\n                    },\n                },\n                .comptime_int => switch (argument.value) {\n                    .comptime_int => |value| bindings.ints[param_raw] = value,\n                    else => {\n                        std.debug.print(\n                            "[generic-kind-mismatch] module={} parameter={s} expected=comptime_int argument={s} actual={s} position={} range={}+{}\\n",\n                            .{ module_index, module.text(parameter.name), self.graph.text(argument.name), @tagName(argument.value), position, arguments.start, arguments.len },\n                        );\n                        return error.GenericArgumentKindMismatch;\n                    },\n                },\n            }\n''',
    "generic kind mismatch trace",
)

subprocess.run([
    "zig", "fmt",
    "src/4_semantics/global/generic_functions.zig",
    "src/4_semantics/global/generics.zig",
], check=True)

Path(".git/semantic-refactor-message").write_text("Guard unresolved generic inference")
Path(".git/semantic-refactor-test-command").write_text(
    "zig build test-programs -Dtest-filter=feature_tests/control_flow/04_for_dynamic_array\n"
)
