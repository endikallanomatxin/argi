from pathlib import Path
import subprocess

path = Path("src/5_codegen/global_codegen.zig")
text = path.read_text()
old = '''        const source_ptr = self.isPointer(source);
        const target_ptr = self.isPointer(target);
        const source_native = types.isBuiltin(self.graph, source, .UIntNative);
        const target_native = types.isBuiltin(self.graph, target, .UIntNative);
'''
new = '''        const source_ptr = self.isPointer(source);
        const target_ptr = self.isPointer(target);
        const source_native = types.isBuiltin(self.graph, source, .UIntNative);
        const target_native = types.isBuiltin(self.graph, target, .UIntNative);
        std.debug.print(
            "[explicit-cast] source={} raw={any} semantic={any} target={} raw={any} semantic={any} source_ptr={} target_ptr={} source_native={} target_native={}\\n",
            .{
                @intFromEnum(source),
                self.graph.types.items[@intFromEnum(source)],
                self.graph.semanticType(source),
                @intFromEnum(target),
                self.graph.types.items[@intFromEnum(target)],
                self.graph.semanticType(target),
                source_ptr,
                target_ptr,
                source_native,
                target_native,
            },
        );
'''
if text.count(old) != 1:
    raise RuntimeError(f"explicit cast trace anchor changed: {text.count(old)}")
path.write_text(text.replace(old, new, 1))
subprocess.run(["zig", "fmt", str(path)], check=True)
Path(".git/semantic-refactor-test-command").write_text(
    "zig build test-programs -Dtest-filter=feature_tests/collections/23_dynamic_array_owning_push_fixed\n"
)
