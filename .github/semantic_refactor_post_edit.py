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
text = text.replace(old, new, 1)

old = '''        const auto = self.graph.auto_deinits.items[@intFromEnum(auto_id)];
        const storage = self.bindings.get(auto.binding) orelse return;
        const drop = storage.drop_state orelse return;
        try self.genAutoDeinitStorage(auto.deinit_fn, auto.input, auto.self_field_index, auto.fields, storage.ref, storage.ty, drop);
'''
new = '''        const auto = self.graph.auto_deinits.items[@intFromEnum(auto_id)];
        const storage = self.bindings.get(auto.binding) orelse return;
        const drop = storage.drop_state orelse return;
        std.debug.print("[auto-deinit] binding={} name={s} ty={} deinit={any} self-index={} fields={} input={any}\\n", .{
            @intFromEnum(auto.binding),
            self.graph.text(self.graph.bindings.items[@intFromEnum(auto.binding)].name),
            @intFromEnum(storage.ty),
            if (auto.deinit_fn) |id| @as(?u32, @intFromEnum(id)) else null,
            auto.self_field_index,
            auto.fields.len,
            if (auto.input) |id| @as(?u32, @intFromEnum(id)) else null,
        });
        if (auto.deinit_fn) |id| {
            const f = self.graph.functions.items[@intFromEnum(id)];
            std.debug.print("  function={s} input-len={}\\n", .{ self.graph.text(self.graph.declarations.items[@intFromEnum(f.declaration)].name), f.input.len });
            for (self.graph.fields.items[f.input.start..][0..f.input.len], 0..) |field, index| {
                std.debug.print("    field[{}]={s} ty={} default={any}\\n", .{ index, self.graph.text(field.name), @intFromEnum(field.ty), field.default_value });
            }
        }
        try self.genAutoDeinitStorage(auto.deinit_fn, auto.input, auto.self_field_index, auto.fields, storage.ref, storage.ty, drop);
'''
if text.count(old) != 1:
    raise RuntimeError(f"auto-deinit trace anchor changed: {text.count(old)}")
text = text.replace(old, new, 1)

path.write_text(text)
subprocess.run(["zig", "fmt", str(path)], check=True)
Path(".git/semantic-refactor-test-command").write_text(
    "zig build test-programs -Dtest-filter=feature_tests/collections/23_dynamic_array_owning_push_fixed\n"
)
