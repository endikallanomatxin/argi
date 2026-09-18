from pathlib import Path
import re
import subprocess

def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label} anchor changed: {count}")
    return text.replace(old, new, 1)

# Generic argument identity is a GlobalSG semantic relation. Keep one canonical
# implementation and make every generic cache/interner use it.
tpath = Path("src/4_semantics/global/types.zig")
text = tpath.read_text()
text = replace_once(
    text,
    "fn genericArgumentsEqual(graph: *const graph_mod.GlobalSemanticGraph, a: anytype, b: @TypeOf(a)) bool {",
    "pub fn genericArgumentsEqual(graph: *const graph_mod.GlobalSemanticGraph, a: anytype, b: @TypeOf(a)) bool {",
    "export generic argument equality",
)
test_anchor = '''test "global semantic types expose structural fields and variants" {
'''
test_code = '''test "generic argument identity uses semantic type equality" {
    const allocator = std.testing.allocator;
    var graph: graph_mod.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);

    // Globalization can leave distinct IDs for the same semantic type. Generic
    // identity must not depend on those construction-time IDs.
    try graph.types.append(allocator, .{ .builtin = .Int32 });
    try graph.types.append(allocator, .{ .builtin = .Int32 });
    const name = try graph.addString(allocator, "t");
    try graph.generic_arguments.append(allocator, .{ .name = name, .value = .{ .type = @enumFromInt(0) } });
    try graph.generic_arguments.append(allocator, .{ .name = name, .value = .{ .type = @enumFromInt(1) } });

    const first: primitives.Range(graph_mod.GlobalGenericArgId) = .{ .start = 0, .len = 1 };
    const second: primitives.Range(graph_mod.GlobalGenericArgId) = .{ .start = 1, .len = 1 };
    try std.testing.expect(genericArgumentsEqual(&graph, first, second));
}

''' + test_anchor
text = replace_once(text, test_anchor, test_code, "generic argument equality test")
tpath.write_text(text)

# Type interning must use the same semantic equality for child types too.
gpath = Path("src/4_semantics/global/generics.zig")
text = gpath.read_text()
old_switch = '''        .builtin => |value| value == b.builtin,
        .declared => |value| value == b.declared,
        .pointer => |value| value.child == b.pointer.child and value.mutability == b.pointer.mutability,
        .array => |value| value.length == b.array.length and value.element == b.array.element,
        .nullable => |value| value == b.nullable,
        .inferred_errable => |value| value == b.inferred_errable,
        .generic => |value| value.base == b.generic.base and genericArgumentsEqual(graph, value.arguments, b.generic.arguments),
        .virtual => |value| value == b.virtual,
'''
new_switch = '''        .builtin => |value| value == b.builtin,
        .declared => |value| value == b.declared,
        .pointer => |value| value.mutability == b.pointer.mutability and global_types.equal(graph, value.child, b.pointer.child),
        .array => |value| value.length == b.array.length and global_types.equal(graph, value.element, b.array.element),
        .nullable => |value| global_types.equal(graph, value, b.nullable),
        .inferred_errable => |value| global_types.equal(graph, value, b.inferred_errable),
        .generic => |value| value.base == b.generic.base and global_types.genericArgumentsEqual(graph, value.arguments, b.generic.arguments),
        .virtual => |value| global_types.equal(graph, value, b.virtual),
'''
text = replace_once(text, old_switch, new_switch, "semantic shallow type identity")
pattern = re.compile(
    r'''\nfn genericArgumentsEqual\(\n    graph: \*const global_sg\.GlobalSemanticGraph,\n    a: primitives\.Range\(global_sg\.GlobalGenericArgId\),\n    b: primitives\.Range\(global_sg\.GlobalGenericArgId\),\n\) bool \{.*?\n\}\n\ntest "generic type identity is independent of argument pool position"''',
    re.S,
)
text, count = pattern.subn(
    '\n\ntest "generic type identity is independent of argument pool position"',
    text,
    count=1,
)
if count != 1:
    raise RuntimeError(f"local generic argument equality removal changed: {count}")
gpath.write_text(text)

# Generic function monomorphization cache must use exactly the same identity.
fpath = Path("src/4_semantics/global/generic_functions.zig")
text = fpath.read_text()
text = replace_once(
    text,
    "if (argumentRangesEqual(self.graph, instance.arguments, arguments)) return instance.function;",
    "if (global_types.genericArgumentsEqual(self.graph, instance.arguments, arguments)) return instance.function;",
    "generic function cache equality",
)
pattern = re.compile(
    r'''\nfn argumentRangesEqual\(\n    graph: \*const global_sg\.GlobalSemanticGraph,\n    a: primitives\.Range\(global_sg\.GlobalGenericArgId\),\n    b: primitives\.Range\(global_sg\.GlobalGenericArgId\),\n\) bool \{.*?\n\}\n\ntest "generic function monomorphization uses stable GlobalFunctionId identity"''',
    re.S,
)
text, count = pattern.subn(
    '\n\ntest "generic function monomorphization uses stable GlobalFunctionId identity"',
    text,
    count=1,
)
if count != 1:
    raise RuntimeError(f"generic function raw-id helper removal changed: {count}")
fpath.write_text(text)

for path in (tpath, gpath, fpath):
    subprocess.run(["zig", "fmt", str(path)], check=True)


# Diagnostic only: identify any remaining ordinary deinit tie after semantic
# monomorphization identity is applied.
cpath = Path("src/4_semantics/global/core.zig")
ctext = cpath.read_text()
anchor = '''            const score = switch (self.matchCallInput(function.input, input_node)) {
                .no_match => continue,
                .deferred => {
                    saw_deferred = true;
                    continue;
                },
                .score => |score| score,
            };
'''
replacement = anchor + '''            if (std.mem.eql(u8, name, "deinit")) {
                std.debug.print("[deinit-candidate] fn={} decl={} score={} generic={} input-len={}\\n", .{
                    raw,
                    @intFromEnum(function.declaration),
                    score,
                    function.flags.is_generic_instantiation,
                    function.input.len,
                });
                for (self.graph.fields.items[function.input.start..][0..function.input.len], 0..) |field, index| {
                    std.debug.print("  field[{}]={s} ty={}\\n", .{ index, self.graph.text(field.name), @intFromEnum(field.ty) });
                }
            }
'''
if ctext.count(anchor) != 1:
    raise RuntimeError(f"ordinary matcher trace anchor changed: {ctext.count(anchor)}")
cpath.write_text(ctext.replace(anchor, replacement, 1))
subprocess.run(["zig", "fmt", str(cpath)], check=True)

Path(".git/semantic-refactor-test-command").write_text(
    "zig build test-programs -Dtest-filter=feature_tests/collections/35_dynamic_array_fallible_copy_cleanup\\n"
)
Path(".git/semantic-refactor-message").write_text(
    "Canonicalize generic identity by semantic type equality\n"
)
