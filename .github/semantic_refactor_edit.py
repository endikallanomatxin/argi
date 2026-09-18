from pathlib import Path
import subprocess

path = Path("src/4_semantics/global/core.zig")
text = path.read_text()
trace = '''            if (std.mem.eql(u8, name, "deinit")) {
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
if text.count(trace) != 1:
    raise RuntimeError(f"temporary deinit trace anchor changed: {text.count(trace)}")
path.write_text(text.replace(trace, "", 1))
subprocess.run(["zig", "fmt", str(path)], check=True)

Path(".git/semantic-refactor-test-command").write_text(
    "zig build test-programs -Dtest-filter=feature_tests/collections/23_dynamic_array_owning_push_fixed\n"
)
Path(".git/semantic-refactor-message").write_text(
    "Remove temporary deinit tracing\n"
)
