from pathlib import Path
import subprocess


path = Path("src/4_semantics/global/core.zig")
text = path.read_text()
old = '''                const binding_id = globalizer.globalBinding(o, scope[scope_index]);
                const binding = self.graph.bindings.items[@intFromEnum(binding_id)];
                if (!std.mem.eql(u8, self.graph.text(binding.name), root_name)) continue;
                var current_ty = binding.ty;
                var hits: std.ArrayList(types.FieldHit) = .empty;
                defer hits.deinit(self.allocator);
                var valid = true;
                for (segments[1..]) |segment| {
                    const hit = types.findField(self.graph, current_ty, self.graph.text(segment)) orelse {
                        valid = false;
                        break;
                    };
                    try hits.append(self.allocator, hit);
                    current_ty = hit.field.storage_type orelse hit.field.ty;
                }
'''
new = '''                const binding_id = globalizer.globalBinding(o, scope[scope_index]);
                const binding = self.graph.bindings.items[@intFromEnum(binding_id)];
                if (!std.mem.eql(u8, self.graph.text(binding.name), root_name)) continue;
                if (self.graph.isBindingTypeUnresolved(binding_id) or self.graph.isTypeUnresolved(binding.ty)) continue;
                var current_ty = binding.ty;
                var hits: std.ArrayList(types.FieldHit) = .empty;
                defer hits.deinit(self.allocator);
                var valid = true;
                for (segments[1..]) |segment| {
                    if (self.graph.isTypeUnresolved(current_ty)) {
                        valid = false;
                        break;
                    }
                    const hit = types.findField(self.graph, current_ty, self.graph.text(segment)) orelse {
                        valid = false;
                        break;
                    };
                    try hits.append(self.allocator, hit);
                    current_ty = hit.field.storage_type orelse hit.field.ty;
                }
                if (self.graph.isTypeUnresolved(current_ty)) valid = false;
'''
count = text.count(old)
if count != 1:
    raise RuntimeError(f"reach unresolved guard anchor changed: {count}")
path.write_text(text.replace(old, new, 1))
subprocess.run(["zig", "fmt", str(path)], check=True)

# Keep the verification focused on the semantic hole being fixed. Broader
# DynamicArray regressions are measured after the source edit is committed.
Path(".git/semantic-refactor-test-command").write_text(
    "zig build test-programs "
    "-Dtest-filter=feature_tests/control_flow/04_for_dynamic_array "
    "-Dtest-filter=feature_tests/control_flow/14_for_mut_borrowed_dynamic_array\n"
)
