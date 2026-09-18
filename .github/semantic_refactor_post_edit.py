from pathlib import Path
import subprocess

path = Path("src/5_codegen/global_codegen.zig")
text = path.read_text()
old = '''        const target = cast.target_type;
        const target_ref = try self.toLLVMType(target);
        const source_ptr = self.isPointer(source);
'''
new = '''        const target = cast.target_type;
        const target_ref = try self.toLLVMType(target);
        if (types.equal(self.graph, source, target)) {
            if (value.type_ref != target_ref) return CodegenError.InvalidType;
            return .{ .value_ref = value.value_ref, .type_ref = target_ref, .ty = target };
        }
        const source_ptr = self.isPointer(source);
'''
if text.count(old) != 1:
    raise RuntimeError(f"equivalent explicit cast anchor changed: {text.count(old)}")
path.write_text(text.replace(old, new, 1))
subprocess.run(["zig", "fmt", str(path)], check=True)

Path(".git/semantic-refactor-test-command").write_text(
    "zig build test-programs -Dtest-filter=feature_tests/collections/26_dynamic_array_owning_pop && "
    "zig build test-programs -Dtest-filter=feature_tests/modules/24_imported_generic_abstract_dispatch_prefers_concrete\n"
)
Path(".git/semantic-refactor-message").write_text(
    "Restore generic allocator dispatch and equivalent casts\n"
)
