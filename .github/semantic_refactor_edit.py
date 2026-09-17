from pathlib import Path
import subprocess


def replace_once(path: Path, old: str, new: str, label: str) -> None:
    text = path.read_text()
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label} anchor changed: {count}")
    path.write_text(text.replace(old, new, 1))


path = Path("src/4_semantics/global/generic_functions.zig")
replace_once(
    path,
    '''            const function = if (arguments.len != 0)\n                try self.resolver.resolveExplicitGenericFunction(self.module_index, module, reference, arguments, input, null)\n            else\n                self.resolver.core.resolveFunctionByName(self.module_index, reference, input) catch\n                    self.resolver.resolveImplicitGenericFunction(self.module_index, module, reference, input, null) catch |err| {\n                        if (self.resolver.nested_call_context) |context| {\n                            if (self.resolver.nested_call_resolver) |resolve| {\n                                if (try resolve(context, self.module_index, reference, input, self.resolver.sourceFor(self.module_index, source))) |node|\n                                    return node;\n                            }\n                        }\n                        if (module_path == null and std.mem.eql(u8, name, "deinit") and\n                            self.parameterized.safety_primitive == .trusted_opaque_drop)\n                            return self.emptyValue(try self.resolver.generics.internType(.{ .builtin = .Void }), source);\n                        return err;\n                    };\n''',
    '''            const function = if (arguments.len != 0)\n                try self.resolver.resolveExplicitGenericFunction(self.module_index, module, reference, arguments, input, null)\n            else blk: {\n                const ordinary = self.resolver.core.resolveFunctionByName(self.module_index, reference, input) catch |core_err| {\n                    std.debug.print("[generic-body-call] name={s} core={s}\\n", .{ name, @errorName(core_err) });\n                    const generic = self.resolver.resolveImplicitGenericFunction(self.module_index, module, reference, input, null) catch |err| {\n                        std.debug.print("[generic-body-call] name={s} generic={s}\\n", .{ name, @errorName(err) });\n                        if (self.resolver.nested_call_context) |context| {\n                            if (self.resolver.nested_call_resolver) |resolve| {\n                                if (try resolve(context, self.module_index, reference, input, self.resolver.sourceFor(self.module_index, source))) |node|\n                                    return node;\n                            }\n                        }\n                        if (module_path == null and std.mem.eql(u8, name, "deinit") and\n                            self.parameterized.safety_primitive == .trusted_opaque_drop)\n                            return self.emptyValue(try self.resolver.generics.internType(.{ .builtin = .Void }), source);\n                        return err;\n                    };\n                    break :blk generic;\n                };\n                break :blk ordinary;\n            };\n''',
    "trace nested generic body calls",
)
subprocess.run(["zig", "fmt", str(path)], check=True)
Path(".git/semantic-refactor-message").write_text("Trace nested generic body calls")
Path(".git/semantic-refactor-test-command").write_text(
    "zig build test-programs -Dtest-filter=feature_tests/collections/26_dynamic_array_owning_pop\n"
)
