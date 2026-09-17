from pathlib import Path
import subprocess


def replace_once(path: Path, old: str, new: str, label: str) -> None:
    text = path.read_text()
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label} anchor changed: {count}")
    path.write_text(text.replace(old, new, 1))


# Constructors need the generic unifier as an internal cross-resolver helper.
generic_functions = Path("src/4_semantics/global/generic_functions.zig")
replace_once(
    generic_functions,
    "    fn inferInputType(\n",
    "    pub fn inferInputType(\n",
    "inferInputType visibility",
)

# Generic binding inference must be able to ask the ordinary call matcher
# whether a fully-instantiated expected type accepts a contextual literal.
core = Path("src/4_semantics/global/core.zig")
replace_once(
    core,
    "    fn contextualLiteralFits(self: *const Resolver, node: global_sg.GlobalNodeId, target: global_sg.GlobalTypeId) bool {\n",
    "    pub fn contextualLiteralFits(self: *const Resolver, node: global_sg.GlobalNodeId, target: global_sg.GlobalTypeId) bool {\n",
    "contextual literal predicate visibility",
)

path = Path("src/4_semantics/global/constructors.zig")
text = path.read_text()

# User arguments are a source of generic bindings, but concrete/contextually
# typed fields are validation constraints, not inference failures. Give this
# helper access to the generic resolver so it can instantiate the expected
# field type before falling back to structural inference.
old = "self.inferInitializerUserBindings(generic_functions, candidate_index, parameterized.input, input,"
new = "self.inferInitializerUserBindings(generics, generic_functions, candidate_index, parameterized.input, input,"
if text.count(old) != 3:
    raise RuntimeError(f"initializer user binding call anchors changed: {text.count(old)}")
text = text.replace(old, new)

old = '''    fn inferInitializerUserBindings(\n        self: *Resolver,\n        generic_functions: *generic_functions_mod.Resolver,\n'''
new = '''    fn inferInitializerUserBindings(\n        self: *Resolver,\n        generics: *generic_mod.Resolver,\n        generic_functions: *generic_functions_mod.Resolver,\n'''
if text.count(old) != 1:
    raise RuntimeError(f"initializer user binding signature anchor changed: {text.count(old)}")
text = text.replace(old, new, 1)

old = '''                const actual = self.graph.nodes.items[@intFromEnum(value.value)].ty orelse break;\n                if (!try generic_functions.inferInputType(candidate_index, field.ty, actual, bindings)) return false;\n                break;\n'''
new = '''                // If the expected field type is already fully determined by\n                // bindings inferred elsewhere (notably the constructor destination),\n                // this argument contributes no new generic information. Validate\n                // contextual literals later with the normal matcher instead of\n                // rejecting e.g. `2` against `UIntNative` during inference.\n                if (generics.instantiateParameterizedType(candidate_index, field.ty, bindings, null)) |expected| {\n                    if (self.core.contextualLiteralFits(value.value, expected)) break;\n                } else |_| {}\n                const actual = self.graph.nodes.items[@intFromEnum(value.value)].ty orelse break;\n                if (!try generic_functions.inferInputType(candidate_index, field.ty, actual, bindings)) return false;\n                break;\n'''
if text.count(old) != 1:
    raise RuntimeError(f"initializer user binding body anchor changed: {text.count(old)}")
text = text.replace(old, new, 1)

# Generic index operators are selected after specialization. Their non-self
# operands must therefore follow the same contextual-literal rules as ordinary
# calls; exact type equality rejects e.g. `dyn[0]` when the index is UIntNative.
generic_text = generic_functions.read_text()
old = '''                for (1..count) |i| {\n                    const expected = self.graph.fields.items[candidate.input.start + @as(u32, @intCast(i))].ty;\n                    if (!global_types.equal(self.graph, expected, operand_types[i])) {\n                        matches = false;\n                        break;\n                    }\n                }\n'''
new = '''                for (1..count) |i| {\n                    const expected = self.graph.fields.items[candidate.input.start + @as(u32, @intCast(i))].ty;\n                    if (!global_types.equal(self.graph, expected, operand_types[i]) and\n                        !self.core.contextualLiteralFits(operands[i], expected))\n                    {\n                        matches = false;\n                        break;\n                    }\n                }\n'''
if generic_text.count(old) != 1:
    raise RuntimeError(f"generic index contextual match anchor changed: {generic_text.count(old)}")
generic_text = generic_text.replace(old, new, 1)

old = '''        const input = try self.core.makeCallInput(function.?, operands[0..count]);\n'''
new = '''        const selected = self.graph.functions.items[@intFromEnum(function.?)];\n        for (1..count) |i| {\n            const expected = self.graph.fields.items[selected.input.start + @as(u32, @intCast(i))].ty;\n            _ = self.core.coerceContextualValue(operands[i], expected);\n        }\n        const input = try self.core.makeCallInput(function.?, operands[0..count]);\n'''
if generic_text.count(old) != 1:
    raise RuntimeError(f"generic index contextual coercion anchor changed: {generic_text.count(old)}")
generic_functions.write_text(generic_text.replace(old, new, 1))

# Temporary focused diagnostics. The edit workflow only commits src/ when the
# focused semantic test succeeds, so these prints never land in a failing run.
old = '''                const arguments = generic_functions.appendBoundArguments(candidate_index, parameterized.parameters, &bindings) catch return null;\n                return generic_functions.instantiate(declaration, arguments) catch return null;\n'''
new = '''                const arguments = generic_functions.appendBoundArguments(candidate_index, parameterized.parameters, &bindings) catch |err| {\n                    std.debug.print("[generic-init-materialize] declaration={} append-args={s}\\n", .{ @intFromEnum(declaration), @errorName(err) });\n                    return null;\n                };\n                return generic_functions.instantiate(declaration, arguments) catch |err| {\n                    std.debug.print("[generic-init-materialize] declaration={} instantiate={s}\\n", .{ @intFromEnum(declaration), @errorName(err) });\n                    return null;\n                };\n'''
if text.count(old) != 1:
    raise RuntimeError(f"generic materialization trace anchor changed: {text.count(old)}")
text = text.replace(old, new, 1)

old = '''        if (!try generic_functions.inferInputType(\n            candidate_index,\n            storage.fields.items[shape.fields.start].ty,\n            destination_pointer,\n            bindings,\n        )) return false;\n        if (!try self.inferInitializerUserBindings(generics, generic_functions, candidate_index, parameterized.input, input, bindings)) return false;\n        return self.inferInitializerReachBindings(generic_functions, candidate_index, parameterized.input, context, bindings);\n'''
new = '''        if (!try generic_functions.inferInputType(\n            candidate_index,\n            storage.fields.items[shape.fields.start].ty,\n            destination_pointer,\n            bindings,\n        )) {\n            std.debug.print("[generic-init-bind] module={} destination=false\\n", .{candidate_index});\n            return false;\n        }\n        if (!try self.inferInitializerUserBindings(generics, generic_functions, candidate_index, parameterized.input, input, bindings)) {\n            std.debug.print("[generic-init-bind] module={} user=false\\n", .{candidate_index});\n            return false;\n        }\n        const reached = try self.inferInitializerReachBindings(generic_functions, candidate_index, parameterized.input, context, bindings);\n        if (!reached) std.debug.print("[generic-init-bind] module={} reach=false\\n", .{candidate_index});\n        return reached;\n'''
if text.count(old) != 1:
    raise RuntimeError(f"generic binding trace anchor changed: {text.count(old)}")
text = text.replace(old, new, 1)

old = '''                if (valid) return current_ty;\n'''
new = '''                if (valid) {\n                    std.debug.print("[generic-init-reach] candidate-module={} root={s} type={}\\n", .{ candidate_index, root_name, @intFromEnum(current_ty) });\n                    return current_ty;\n                }\n'''
if text.count(old) != 1:
    raise RuntimeError(f"generic reach trace anchor changed: {text.count(old)}")
text = text.replace(old, new, 1)

path.write_text(text)

subprocess.run([
    "zig", "fmt",
    "src/4_semantics/global/core.zig",
    "src/4_semantics/global/constructors.zig",
    "src/4_semantics/global/generic_functions.zig",
], check=True)
