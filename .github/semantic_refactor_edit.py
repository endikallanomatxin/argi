from pathlib import Path
import subprocess

path = Path("src/4_semantics/global/dispatch.zig")
text = path.read_text()
text = text.replace(
'''            .ambiguous => return error.AmbiguousImplicitFunction,
            .no_match => {},
''',
'''            .ambiguous => {
                std.debug.print("[implicit-ambiguous] phase=ordinary module={} name={s} input={}\\n", .{ module_index, name, @intFromEnum(input) });
                return error.AmbiguousImplicitFunction;
            },
            .no_match => {},
''',
1,
)
text = text.replace(
'''            .ambiguous => return error.AmbiguousImplicitFunction,
            .no_match => {},
''',
'''            .ambiguous => {
                std.debug.print("[implicit-ambiguous] phase=abstract-ordinary module={} name={s} input={}\\n", .{ module_index, name, @intFromEnum(input) });
                return error.AmbiguousImplicitFunction;
            },
            .no_match => {},
''',
1,
)
text = text.replace(
'''            error.AmbiguousGenericFunction => return error.AmbiguousImplicitFunction,
''',
'''            error.AmbiguousGenericFunction => {
                std.debug.print("[implicit-ambiguous] phase=generic module={} name={s} input={}\\n", .{ module_index, name, @intFromEnum(input) });
                return error.AmbiguousImplicitFunction;
            },
''',
1,
)
if 'std.debug.print("[implicit-ambiguous]' not in text:
    raise RuntimeError("dispatch ambiguity trace anchors changed")
if not text.startswith('const std = @import("std");'):
    text = 'const std = @import("std");\n' + text
path.write_text(text)
subprocess.run(["zig", "fmt", str(path)], check=True)

opath = Path("src/4_semantics/global/ownership.zig")
otext = opath.read_text()
old = '''        while (names.next()) |name_ptr| {
            const input = try self.singleNamedInput(name_ptr.*, address, source);
            const call = dispatch.resolveImplicitFunction(
'''
new = '''        while (names.next()) |name_ptr| {
            const input = try self.singleNamedInput(name_ptr.*, address, source);
            std.debug.print("[destructor-probe] module={} target-ty={} receiver={s} input={}\\n", .{
                module_index,
                @intFromEnum(target_ty),
                name_ptr.*,
                @intFromEnum(input),
            });
            const call = dispatch.resolveImplicitFunction(
'''
if otext.count(old) != 1:
    raise RuntimeError(f"destructor probe anchor changed: {otext.count(old)}")
opath.write_text(otext.replace(old, new, 1))
subprocess.run(["zig", "fmt", str(opath)], check=True)

Path(".git/semantic-refactor-test-command").write_text(
    "status=0; "
    "zig build test-programs -Dtest-filter=feature_tests/collections/34_dynamic_array_string_copy || status=1; "
    "zig build test-programs -Dtest-filter=feature_tests/collections/35_dynamic_array_fallible_copy_cleanup || status=1; "
    "exit $status\n"
)
