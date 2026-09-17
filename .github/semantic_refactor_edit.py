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
            // A supplied argument owns inference for its field. In particular,
            // do not also infer the hidden abstract parameter from a #reach
            // fallback such as `system.allocator`: an explicit concrete
            // allocator must remain the dispatch type selected by the caller.
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
            if (supplied) continue;

            const default = field.default_value orelse continue;
            const actual = self.parameterizedReachType(candidate_index, default, context) orelse continue;
            if (!try generic_functions.inferInputType(candidate_index, field.ty, actual, bindings)) return false;
        }
        return true;
    }

    fn parameterizedReachType('''
text, count = pattern.subn(replacement, text, count=1)
if count != 1:
    raise RuntimeError(f"initializer reach function anchor changed: {count}")
path.write_text(text)
subprocess.run(["zig", "fmt", str(path)], check=True)
Path(".git/semantic-refactor-message").write_text("Preserve explicit initializer arguments over reach defaults")
Path(".git/semantic-refactor-test-command").write_text(
    "status=0\n"
    "zig build test-programs -Dtest-filter=feature_tests/collections/23_dynamic_array_owning_push_fixed || status=1\n"
    "zig build test-programs -Dtest-filter=feature_tests/collections/24_dynamic_array_owning_assume_capacity || status=1\n"
    "zig build test-programs -Dtest-filter=feature_tests/collections/30_dynamic_array_owning_growth_failure_atomic || status=1\n"
    "exit $status\n"
)
