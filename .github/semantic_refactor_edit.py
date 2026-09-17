from pathlib import Path
import subprocess


def replace_once(path: Path, old: str, new: str, label: str) -> None:
    text = path.read_text()
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label} anchor changed: {count}")
    path.write_text(text.replace(old, new, 1))


# Unresolved binding types carry a poison GlobalTypeId while GlobalSema reaches
# its fixed point. Generic inference must defer rather than index that poison.
generic_functions = Path("src/4_semantics/global/generic_functions.zig")
replace_once(
    generic_functions,
    '''    ) anyerror!bool {\n        const module = &self.modules[module_index];\n        const storage = &module.semantic.parameterized_storage.ir;\n''',
    '''    ) anyerror!bool {\n        const actual_raw: usize = @intFromEnum(actual);\n        if (actual_raw >= self.graph.types.items.len or self.graph.isTypeUnresolved(actual)) return false;\n        const module = &self.modules[module_index];\n        const storage = &module.semantic.parameterized_storage.ir;\n''',
    "unresolved generic input guard",
)

# Temporary focused trace: when kinds disagree, identify every parameterized
# declaration whose parameter range owns the slot. This distinguishes type
# materialization from generic-function dispatch without guessing from nearby
# traces.
generics = Path("src/4_semantics/global/generics.zig")
old = '''            switch (parameter.kind) {\n                .type => switch (argument.value) {\n                    .type => |value| bindings.types[param_raw] = value,\n                    else => return error.GenericArgumentKindMismatch,\n                },\n                .comptime_int => switch (argument.value) {\n                    .comptime_int => |value| bindings.ints[param_raw] = value,\n                    else => return error.GenericArgumentKindMismatch,\n                },\n            }\n'''
new = '''            switch (parameter.kind) {\n                .type => switch (argument.value) {\n                    .type => |value| bindings.types[param_raw] = value,\n                    else => {\n                        self.traceGenericParameterOwner(module_index, param_raw, parameter, argument, arguments);\n                        return error.GenericArgumentKindMismatch;\n                    },\n                },\n                .comptime_int => switch (argument.value) {\n                    .comptime_int => |value| bindings.ints[param_raw] = value,\n                    else => {\n                        self.traceGenericParameterOwner(module_index, param_raw, parameter, argument, arguments);\n                        return error.GenericArgumentKindMismatch;\n                    },\n                },\n            }\n'''
replace_once(generics, old, new, "generic kind mismatch owner trace call")

anchor = '''    fn findGlobalArgument(\n        self: *Resolver,\n'''
helper = '''    fn traceGenericParameterOwner(\n        self: *Resolver,\n        module_index: usize,\n        param_raw: u32,\n        parameter: parameterized_storage.ComptimeParameter,\n        argument: global_sg.GenericArgument,\n        arguments: primitives.Range(global_sg.GlobalGenericArgId),\n    ) void {\n        const module = &self.modules[module_index];\n        std.debug.print(\n            "[generic-kind-mismatch] module={} slot={} parameter={s} expected={s} argument={s} actual={s} args={}+{}\\n",\n            .{ module_index, param_raw, module.text(parameter.name), @tagName(parameter.kind), self.graph.text(argument.name), @tagName(argument.value), arguments.start, arguments.len },\n        );\n        for (module.semantic.parameterized_storage.parameterized_types.items) |candidate| {\n            if (param_raw < candidate.parameters.start or param_raw >= candidate.parameters.start + candidate.parameters.len) continue;\n            const declaration = module.declarations.items[@intFromEnum(candidate.declaration)];\n            std.debug.print(\n                "[generic-kind-owner] type decl={} name={s} params={}+{}\\n",\n                .{ @intFromEnum(candidate.declaration), module.text(declaration.name), candidate.parameters.start, candidate.parameters.len },\n            );\n        }\n        for (module.semantic.parameterized_storage.parameterized_functions.items) |candidate| {\n            if (param_raw < candidate.parameters.start or param_raw >= candidate.parameters.start + candidate.parameters.len) continue;\n            const declaration = module.declarations.items[@intFromEnum(candidate.declaration)];\n            std.debug.print(\n                "[generic-kind-owner] function decl={} name={s} params={}+{}\\n",\n                .{ @intFromEnum(candidate.declaration), module.text(declaration.name), candidate.parameters.start, candidate.parameters.len },\n            );\n        }\n    }\n\n'''
replace_once(generics, anchor, helper + anchor, "generic parameter owner trace helper")

subprocess.run([
    "zig", "fmt",
    "src/4_semantics/global/generic_functions.zig",
    "src/4_semantics/global/generics.zig",
], check=True)

Path(".git/semantic-refactor-message").write_text("Guard unresolved generic inference")
Path(".git/semantic-refactor-test-command").write_text(
    "zig build test-programs -Dtest-filter=feature_tests/control_flow/04_for_dynamic_array\n"
)
