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

# Reached defaults only infer omitted fields. An explicit constructor argument
# already owns inference for that field and must not be overwritten by a
# fallback such as `system.allocator`.
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
            if (supplied) continue;

            const default = field.default_value orelse continue;
            const actual = self.parameterizedReachType(candidate_index, default, context) orelse continue;
            if (!try generic_functions.inferInputType(candidate_index, field.ty, actual, bindings)) return false;
        }
        return true;
    }

    fn parameterizedReachType('''
text, count = pattern.subn(lambda _: replacement, text, count=1)
if count != 1:
    raise RuntimeError(f"initializer reach function anchor changed: {count}")

# The first two temporary generic resolvers already retain the abstract context.
# Complete their callback wiring without duplicating that existing field.
text = replace_exact_count(
    text,
    ".nested_call_context = self.abstracts,\n",
    ".nested_call_context = self.abstracts,\n"
    "            .nested_call_resolver = abstract_mod.Resolver.resolveNestedCall,\n"
    "            .nested_constructor_context = self,\n"
    "            .nested_constructor_resolver = Resolver.resolveNestedCall,\n",
    2,
    "existing temporary resolver context",
)

# The explicit generic-constructor path did not carry any nested dispatch state.
old = '''        var generic_functions = generic_functions_mod.Resolver{
            .allocator = self.core.allocator,
            .graph = self.graph,
            .modules = self.modules,
            .offsets = self.offsets,
            .core = self.core,
            .generics = &generics,
        };
        const input = globalizer.globalNode(o, value.input);
'''
new = '''        var generic_functions = generic_functions_mod.Resolver{
            .allocator = self.core.allocator,
            .graph = self.graph,
            .modules = self.modules,
            .offsets = self.offsets,
            .core = self.core,
            .generics = &generics,
            .nested_call_context = self.abstracts,
            .nested_call_resolver = abstract_mod.Resolver.resolveNestedCall,
            .nested_constructor_context = self,
            .nested_constructor_resolver = Resolver.resolveNestedCall,
        };
        const input = globalizer.globalNode(o, value.input);
'''
text = replace_exact_count(text, old, new, 1, "explicit generic constructor resolver")

path.write_text(text)
subprocess.run(["zig", "fmt", str(path)], check=True)
Path(".git/semantic-refactor-test-command").write_text(
    "zig build test-programs -Dtest-filter=feature_tests/collections/23_dynamic_array_owning_push_fixed && "
    "zig build test-programs -Dtest-filter=feature_tests/collections/24_dynamic_array_owning_insert_fixed && "
    "zig build test-programs -Dtest-filter=feature_tests/collections/30_dynamic_array_custom_allocator && "
    "zig build test-programs -Dtest-filter=feature_tests/collections/26_dynamic_array_owning_pop && "
    "zig build test-programs -Dtest-filter=feature_tests/text/08_string_allocator_size\n"
)
