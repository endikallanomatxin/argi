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
text, count = pattern.subn(lambda _: replacement, text, count=1)
if count != 1:
    raise RuntimeError(f"initializer reach function anchor changed: {count}")

old = '''        if (!try generic_functions.inferInputType(
            candidate_index,
            storage.fields.items[shape.fields.start].ty,
            destination_pointer,
            bindings,
        )) return false;
        if (!try self.inferInitializerUserBindings(generics, generic_functions, candidate_index, parameterized.input, input, bindings)) return false;
        return self.inferInitializerReachBindings(generic_functions, candidate_index, parameterized.input, input, context, bindings);
'''
new = '''        const destination_ok = try generic_functions.inferInputType(
            candidate_index,
            storage.fields.items[shape.fields.start].ty,
            destination_pointer,
            bindings,
        );
        std.debug.print("[ctor-populate] module={} destination={} ok={}\\n", .{ candidate_index, @intFromEnum(destination_pointer), destination_ok });
        if (!destination_ok) return false;
        const user_ok = try self.inferInitializerUserBindings(generics, generic_functions, candidate_index, parameterized.input, input, bindings);
        std.debug.print("[ctor-populate] module={} user-ok={}\\n", .{ candidate_index, user_ok });
        if (!user_ok) return false;
        const reach_ok = try self.inferInitializerReachBindings(generic_functions, candidate_index, parameterized.input, input, context, bindings);
        std.debug.print("[ctor-populate] module={} reach-ok={}\\n", .{ candidate_index, reach_ok });
        return reach_ok;
'''
text = replace_exact_count(text, old, new, 1, "initializer populate trace")

old = '''                const actual = self.graph.nodes.items[@intFromEnum(value.value)].ty orelse break;
                if (!try generic_functions.inferInputType(candidate_index, field.ty, actual, bindings)) return false;
                break;
'''
new = '''                const actual = self.graph.nodes.items[@intFromEnum(value.value)].ty orelse break;
                std.debug.print("[ctor-user-bind] module={} field={s} actual={} {any}\\n", .{ candidate_index, module.text(field.name), @intFromEnum(actual), self.graph.types.items[@intFromEnum(actual)] });
                if (!try generic_functions.inferInputType(candidate_index, field.ty, actual, bindings)) return false;
                break;
'''
text = replace_exact_count(text, old, new, 1, "initializer user binding trace")

old = '''        const input_ty = generics.instantiateParameterizedType(candidate_index, parameterized.input, &bindings, null) catch return .{};
        const fields = types.fields(self.graph, input_ty) orelse return .{};
        if (fields.len == 0) return .{};
        return .{
            .owns_type = true,
            .score = try self.scoreInitializerInput(candidate_index, parameterized.input, .{
                .start = fields.start + 1,
                .len = fields.len - 1,
            }, input),
        };
'''
new = '''        const input_ty = generics.instantiateParameterizedType(candidate_index, parameterized.input, &bindings, null) catch |err| {
            std.debug.print("[ctor-probe] module={} instantiate-input error={s}\\n", .{ candidate_index, @errorName(err) });
            return .{};
        };
        const fields = types.fields(self.graph, input_ty) orelse {
            std.debug.print("[ctor-probe] module={} input-type={} has-no-fields\\n", .{ candidate_index, @intFromEnum(input_ty) });
            return .{};
        };
        if (fields.len == 0) return .{};
        const score = try self.scoreInitializerInput(candidate_index, parameterized.input, .{
            .start = fields.start + 1,
            .len = fields.len - 1,
        }, input);
        std.debug.print("[ctor-probe] module={} input-type={} score={any}\\n", .{ candidate_index, @intFromEnum(input_ty), score });
        return .{
            .owns_type = true,
            .score = score,
        };
'''
text = replace_exact_count(text, old, new, 1, "generic initializer probe trace")

old = '''                const arguments = generic_functions.appendBoundArguments(candidate_index, parameterized.parameters, &bindings) catch return null;
                return generic_functions.instantiate(declaration, arguments) catch return null;
'''
new = '''                const arguments = generic_functions.appendBoundArguments(candidate_index, parameterized.parameters, &bindings) catch |err| {
                    std.debug.print("[ctor-materialize] append-args error={s}\\n", .{@errorName(err)});
                    return null;
                };
                return generic_functions.instantiate(declaration, arguments) catch |err| {
                    std.debug.print("[ctor-materialize] instantiate error={s}\\n", .{@errorName(err)});
                    return null;
                };
'''
text = replace_exact_count(text, old, new, 1, "generic initializer materialization trace")

path.write_text(text)
subprocess.run(["zig", "fmt", str(path)], check=True)
Path(".git/semantic-refactor-test-command").write_text(
    "zig build test-programs -Dtest-filter=feature_tests/collections/23_dynamic_array_owning_push_fixed\n"
)
