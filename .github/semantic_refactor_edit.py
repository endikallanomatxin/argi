from pathlib import Path
import re
import subprocess


def replace_exact_count(text: str, old: str, new: str, expected: int, label: str) -> str:
    count = text.count(old)
    if count != expected:
        raise RuntimeError(f"{label} anchor changed: {count}")
    return text.replace(old, new)


path = Path("src/4_semantics/global/constructors.zig")
text = path.read_text()
text = replace_exact_count(
    text,
    "parameterized.input, context, &bindings",
    "parameterized.input, input, context, &bindings",
    2,
    "initializer reach call with local bindings",
)
text = replace_exact_count(
    text,
    "parameterized.input, context, bindings",
    "parameterized.input, input, context, bindings",
    1,
    "initializer reach call with forwarded bindings",
)

pattern = re.compile(
    r"    fn inferInitializerReachBindings\(.*?\n    fn parameterizedReachType\(",
    re.S,
)
replacement = '''    fn inferInitializerReachBindings(
        self: *Resolver,
        generic_functions: *generic_functions_mod.Resolver,
        candidate_index: usize,
        pattern: @import("../module/parameterized/ir.zig").ParameterizedTypeId,
        input: global_sg.GlobalNodeId,
        context: CallerContext,
        bindings: *generic_mod.Resolver.Bindings,
    ) !bool {
        const literal = switch (self.graph.nodes.items[@intFromEnum(input)].content) {
            .struct_value_literal => |value| value,
            else => return false,
        };
        const module = &self.modules[candidate_index];
        const storage = &module.semantic.parameterized_storage.ir;
        const shape = switch (storage.types.items[@intFromEnum(pattern)]) {
            .resolved => |ty| switch (ty) {
                .structural => |value| value,
                else => return false,
            },
            else => return false,
        };
        if (shape.fields.len == 0) return false;
        for (storage.fields.items[shape.fields.start + 1 ..][0 .. shape.fields.len - 1], 0..) |field, expected_position| {
            var supplied = false;
            for (self.graph.value_fields.items[literal.fields.start..][0..literal.fields.len], 0..) |value, supplied_position| {
                const positional = supplied_position < literal.dispatch_prefix_positional_count or self.graph.text(value.name).len == 0;
                if (if (positional)
                    expected_position == supplied_position
                else
                    std.mem.eql(u8, module.text(field.name), self.graph.text(value.name)))
                {
                    supplied = true;
                    break;
                }
            }
            if (supplied) {
                std.debug.print("[ctor-reach-skip] module={} field={s} supplied=true\\n", .{ candidate_index, module.text(field.name) });
                continue;
            }

            const default = field.default_value orelse continue;
            const actual = self.parameterizedReachType(candidate_index, default, context) orelse continue;
            std.debug.print("[ctor-reach-bind] module={} field={s} actual={} {any}\\n", .{ candidate_index, module.text(field.name), @intFromEnum(actual), self.graph.types.items[@intFromEnum(actual)] });
            if (!try generic_functions.inferInputType(candidate_index, field.ty, actual, bindings)) return false;
        }
        return true;
    }

    fn parameterizedReachType('''
text, count = pattern.subn(replacement, text, count=1)
if count != 1:
    raise RuntimeError(f"initializer reach function anchor changed: {count}")

text = replace_exact_count(
    text,
    '''        if (!try generic_functions.inferInputType(\n            candidate_index,\n            storage.fields.items[shape.fields.start].ty,\n            destination_pointer,\n            bindings,\n        )) return false;\n        if (!try self.inferInitializerUserBindings(generics, generic_functions, candidate_index, parameterized.input, input, bindings)) return false;\n        return self.inferInitializerReachBindings(generic_functions, candidate_index, parameterized.input, input, context, bindings);\n''',
    '''        const destination_ok = try generic_functions.inferInputType(\n            candidate_index,\n            storage.fields.items[shape.fields.start].ty,\n            destination_pointer,\n            bindings,\n        );\n        std.debug.print("[ctor-populate] module={} destination={} ok={}\\n", .{ candidate_index, @intFromEnum(destination_pointer), destination_ok });\n        if (!destination_ok) return false;\n        const user_ok = try self.inferInitializerUserBindings(generics, generic_functions, candidate_index, parameterized.input, input, bindings);\n        std.debug.print("[ctor-populate] module={} user-ok={}\\n", .{ candidate_index, user_ok });\n        if (!user_ok) return false;\n        const reach_ok = try self.inferInitializerReachBindings(generic_functions, candidate_index, parameterized.input, input, context, bindings);\n        std.debug.print("[ctor-populate] module={} reach-ok={}\\n", .{ candidate_index, reach_ok });\n        return reach_ok;\n''',
    1,
    "initializer populate trace",
)

text = replace_exact_count(
    text,
    '''                const actual = self.graph.nodes.items[@intFromEnum(value.value)].ty orelse break;\n                if (!try generic_functions.inferInputType(candidate_index, field.ty, actual, bindings)) return false;\n                break;\n''',
    '''                const actual = self.graph.nodes.items[@intFromEnum(value.value)].ty orelse break;\n                std.debug.print("[ctor-user-bind] module={} field={s} actual={} {any}\\n", .{ candidate_index, module.text(field.name), @intFromEnum(actual), self.graph.types.items[@intFromEnum(actual)] });\n                if (!try generic_functions.inferInputType(candidate_index, field.ty, actual, bindings)) return false;\n                break;\n''',
    1,
    "initializer user binding trace",
)

text = replace_exact_count(
    text,
    '''        const input_ty = generics.instantiateParameterizedType(candidate_index, parameterized.input, &bindings, null) catch return .{};\n        const fields = types.fields(self.graph, input_ty) orelse return .{};\n        if (fields.len == 0) return .{};\n        return .{\n            .owns_type = true,\n            .score = try self.scoreInitializerInput(candidate_index, parameterized.input, .{\n                .start = fields.start + 1,\n                .len = fields.len - 1,\n            }, input),\n        };\n''',
    '''        const input_ty = generics.instantiateParameterizedType(candidate_index, parameterized.input, &bindings, null) catch |err| {\n            std.debug.print("[ctor-probe] module={} instantiate-input error={s}\\n", .{ candidate_index, @errorName(err) });\n            return .{};\n        };\n        const fields = types.fields(self.graph, input_ty) orelse {\n            std.debug.print("[ctor-probe] module={} input-type={} has-no-fields\\n", .{ candidate_index, @intFromEnum(input_ty) });\n            return .{};\n        };\n        if (fields.len == 0) return .{};\n        const score = try self.scoreInitializerInput(candidate_index, parameterized.input, .{\n            .start = fields.start + 1,\n            .len = fields.len - 1,\n        }, input);\n        std.debug.print("[ctor-probe] module={} input-type={} score={any}\\n", .{ candidate_index, @intFromEnum(input_ty), score });\n        return .{\n            .owns_type = true,\n            .score = score,\n        };\n''',
    1,
    "generic initializer probe trace",
)

path.write_text(text)
subprocess.run(["zig", "fmt", str(path)], check=True)
Path(".git/semantic-refactor-test-command").write_text(
    "zig build test-programs -Dtest-filter=feature_tests/collections/23_dynamic_array_owning_push_fixed\n"
)
