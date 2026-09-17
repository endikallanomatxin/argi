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

# Generic binding inference and generic operator dispatch must use the same
# contextual-literal compatibility rules as ordinary calls.
core = Path("src/4_semantics/global/core.zig")
replace_once(
    core,
    "    fn contextualLiteralFits(self: *const Resolver, node: global_sg.GlobalNodeId, target: global_sg.GlobalTypeId) bool {\n",
    "    pub fn contextualLiteralFits(self: *const Resolver, node: global_sg.GlobalNodeId, target: global_sg.GlobalTypeId) bool {\n",
    "contextual literal predicate visibility",
)

constructors = Path("src/4_semantics/global/constructors.zig")
text = constructors.read_text()

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
new = '''                // A concrete field that is already determined by bindings inferred\n                // elsewhere contributes no new generic information. Contextual\n                // literals must be accepted here exactly as they are by normal call\n                // matching (for example `2` for an expected `UIntNative`).\n                if (generics.instantiateParameterizedType(candidate_index, field.ty, bindings, null)) |expected| {\n                    if (self.core.contextualLiteralFits(value.value, expected)) break;\n                } else |_| {}\n                const actual = self.graph.nodes.items[@intFromEnum(value.value)].ty orelse break;\n                if (!try generic_functions.inferInputType(candidate_index, field.ty, actual, bindings)) return false;\n                break;\n'''
if text.count(old) != 1:
    raise RuntimeError(f"initializer user binding body anchor changed: {text.count(old)}")
constructors.write_text(text.replace(old, new, 1))

# Generic index operators are selected after specialization. Their non-self
# operands follow contextual-literal rules too; exact equality would reject
# `dyn[0]` when the specialized index type is UIntNative.
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

# A zero-projection required-live path means the argument value itself must be
# live. For a reference argument, replacing those facts with the pointee's full
# stored value incorrectly turns `&container` liveness into a requirement that
# every ownership root inside the container remain alive. Only projected paths
# intentionally walk into the referenced place.
checker = Path("src/4_semantics/safety/checker.zig")
replace_once(
    checker,
    '''            if (arguments[path.input_index].referenced_place) |base| {\n                var target = base;\n                for (path.projections) |projection| target = try self.project(target, projection);\n                if (self.valueAtPlace(state, target)) |stored| value = stored;\n            }\n''',
    '''            if (path.projections.len != 0) if (arguments[path.input_index].referenced_place) |base| {\n                var target = base;\n                for (path.projections) |projection| target = try self.project(target, projection);\n                if (self.valueAtPlace(state, target)) |stored| value = stored;\n            };\n''',
    "required-live pointer versus pointee distinction",
)

subprocess.run([
    "zig", "fmt",
    "src/4_semantics/global/core.zig",
    "src/4_semantics/global/constructors.zig",
    "src/4_semantics/global/generic_functions.zig",
    "src/4_semantics/safety/checker.zig",
], check=True)
