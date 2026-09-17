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

# Compare DynamicArray's parameter range at creation time with the descriptor
# later found by GlobalSema.
lowerer = Path("src/4_semantics/module/parameterized/lowerer.zig")
replace_once(
    lowerer,
    '''                    const params = try self.lowerParameters(payload.params, payload.params_struct);\n                    const body = try self.lowerType(payload.value, false);\n                    try self.graph.semantic.parameterized_storage.parameterized_types.append(self.allocator, .{\n''',
    '''                    const params = try self.lowerParameters(payload.params, payload.params_struct);\n                    const body = try self.lowerType(payload.value, false);\n                    if (std.mem.eql(u8, self.graph.text(declaration.name), "DynamicArray")) {\n                        std.debug.print("[dynamic-range-lower] params={}+{} total={}\\n", .{ params.start, params.len, self.graph.semantic.parameterized_storage.comptime_parameters.items.len });\n                        for (params.start..params.start + params.len) |param_raw| {\n                            const parameter = self.graph.semantic.parameterized_storage.comptime_parameters.items[param_raw];\n                            std.debug.print("[dynamic-range-lower] slot={} name={s} kind={s}\\n", .{ param_raw, self.graph.text(parameter.name), @tagName(parameter.kind) });\n                        }\n                    }\n                    try self.graph.semantic.parameterized_storage.parameterized_types.append(self.allocator, .{\n''',
    "DynamicArray parameter range creation trace",
)

generics = Path("src/4_semantics/global/generics.zig")
replace_once(
    generics,
    '''        const located = self.findTypeParameterized(identity.base) orelse return false;\n        var bindings = try Bindings.init(self.allocator, self.modules[located.module_index].semantic.parameterized_storage.comptime_parameters.items.len);\n''',
    '''        const located = self.findTypeParameterized(identity.base) orelse return false;\n        const base_decl = self.graph.declarations.items[@intFromEnum(identity.base)];\n        if (std.mem.eql(u8, self.graph.text(base_decl.name), "DynamicArray")) {\n            const module = &self.modules[located.module_index];\n            std.debug.print("[dynamic-range-global] params={}+{} total={} args={}+{}\\n", .{ located.parameterized.parameters.start, located.parameterized.parameters.len, module.semantic.parameterized_storage.comptime_parameters.items.len, identity.arguments.start, identity.arguments.len });\n            for (located.parameterized.parameters.start..located.parameterized.parameters.start + located.parameterized.parameters.len) |param_raw| {\n                const parameter = module.semantic.parameterized_storage.comptime_parameters.items[param_raw];\n                std.debug.print("[dynamic-range-global] slot={} name={s} kind={s}\\n", .{ param_raw, module.text(parameter.name), @tagName(parameter.kind) });\n            }\n        }\n        var bindings = try Bindings.init(self.allocator, self.modules[located.module_index].semantic.parameterized_storage.comptime_parameters.items.len);\n''',
    "DynamicArray parameter range global trace",
)
replace_once(
    generics,
    '''            switch (parameter.kind) {\n                .type => switch (argument.value) {\n                    .type => |value| bindings.types[param_raw] = value,\n                    else => return error.GenericArgumentKindMismatch,\n                },\n                .comptime_int => switch (argument.value) {\n                    .comptime_int => |value| bindings.ints[param_raw] = value,\n                    else => return error.GenericArgumentKindMismatch,\n                },\n            }\n''',
    '''            switch (parameter.kind) {\n                .type => switch (argument.value) {\n                    .type => |value| bindings.types[param_raw] = value,\n                    else => {\n                        std.debug.print("[generic-kind-mismatch] module={} slot={} parameter={s} expected=type actual={s}\\n", .{ module_index, param_raw, module.text(parameter.name), @tagName(argument.value) });\n                        return error.GenericArgumentKindMismatch;\n                    },\n                },\n                .comptime_int => switch (argument.value) {\n                    .comptime_int => |value| bindings.ints[param_raw] = value,\n                    else => {\n                        std.debug.print("[generic-kind-mismatch] module={} slot={} parameter={s} expected=comptime_int actual={s}\\n", .{ module_index, param_raw, module.text(parameter.name), @tagName(argument.value) });\n                        return error.GenericArgumentKindMismatch;\n                    },\n                },\n            }\n''',
    "generic kind mismatch trace",
)

subprocess.run([
    "zig", "fmt",
    "src/4_semantics/global/generic_functions.zig",
    "src/4_semantics/global/generics.zig",
    "src/4_semantics/module/parameterized/lowerer.zig",
], check=True)

Path(".git/semantic-refactor-message").write_text("Guard unresolved generic inference")
Path(".git/semantic-refactor-test-command").write_text(
    "zig build test-programs -Dtest-filter=feature_tests/control_flow/04_for_dynamic_array\n"
)
