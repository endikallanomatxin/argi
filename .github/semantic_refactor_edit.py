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

# Trace the syntax shape that classifies `t` generic parameters. DynamicArray's
# source spells `.t: Type`, yet its stored parameter is currently comptime_int.
lowerer = Path("src/4_semantics/module/parameterized/lowerer.zig")
replace_once(
    lowerer,
    '''                const kind: parameterized_storage.ComptimeParameterKind = if (isTypeParameter(self.tree, self.source, field)) .type else .comptime_int;\n                const id: ir.ComptimeParameterId = @enumFromInt(@as(u32, @intCast(self.graph.semantic.parameterized_storage.comptime_parameters.items.len)));\n''',
    '''                const kind: parameterized_storage.ComptimeParameterKind = if (isTypeParameter(self.tree, self.source, field)) .type else .comptime_int;\n                if (std.mem.eql(u8, name_text, "t")) {\n                    const first_line_end = std.mem.indexOfScalar(u8, self.source, '\\n') orelse self.source.len;\n                    const syntax_type = self.tree.syntaxType(value_type_node);\n                    std.debug.print(\n                        "[lower-param] file={} header={s} name={s} kind={s} builtin={} syntax={s}",\n                        .{ self.file_index, self.source[0..first_line_end], name_text, @tagName(kind), isTypeBuiltin(self.tree, self.source, value_type_node), if (syntax_type) |value| @tagName(value) else "none" },\n                    );\n                    if (syntax_type) |value| switch (value) {\n                        .name => |name| std.debug.print(" syntax-name={s}", .{self.tree.tokenTextFromSource(self.source, name.name_token)}),\n                        else => {},\n                    };\n                    std.debug.print("\\n", .{});\n                }\n                const id: ir.ComptimeParameterId = @enumFromInt(@as(u32, @intCast(self.graph.semantic.parameterized_storage.comptime_parameters.items.len)));\n''',
    "generic parameter lowering trace",
)

# Keep a concise failure trace so the lowering result can be correlated with
# the later generic argument bind.
generics = Path("src/4_semantics/global/generics.zig")
replace_once(
    generics,
    '''            switch (parameter.kind) {\n                .type => switch (argument.value) {\n                    .type => |value| bindings.types[param_raw] = value,\n                    else => return error.GenericArgumentKindMismatch,\n                },\n                .comptime_int => switch (argument.value) {\n                    .comptime_int => |value| bindings.ints[param_raw] = value,\n                    else => return error.GenericArgumentKindMismatch,\n                },\n            }\n''',
    '''            switch (parameter.kind) {\n                .type => switch (argument.value) {\n                    .type => |value| bindings.types[param_raw] = value,\n                    else => {\n                        std.debug.print("[generic-kind-mismatch] module={} parameter={s} expected=type actual={s}\\n", .{ module_index, module.text(parameter.name), @tagName(argument.value) });\n                        return error.GenericArgumentKindMismatch;\n                    },\n                },\n                .comptime_int => switch (argument.value) {\n                    .comptime_int => |value| bindings.ints[param_raw] = value,\n                    else => {\n                        std.debug.print("[generic-kind-mismatch] module={} parameter={s} expected=comptime_int actual={s}\\n", .{ module_index, module.text(parameter.name), @tagName(argument.value) });\n                        return error.GenericArgumentKindMismatch;\n                    },\n                },\n            }\n''',
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
