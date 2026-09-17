from pathlib import Path
import subprocess


def replace_once(path: Path, old: str, new: str, label: str) -> None:
    text = path.read_text()
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label} anchor changed: {count}")
    path.write_text(text.replace(old, new, 1))


Path(".github/semantic_refactor_post_edit.py").write_text("# no-op trace run\n")

path = Path("src/4_semantics/global/generic_functions.zig")
replace_once(
    path,
    '''                var bindings = try generic_mod.Resolver.Bindings.init(self.allocator, candidate_module.semantic.parameterized_storage.comptime_parameters.items.len);\n                defer bindings.deinit(self.allocator);\n                self.generics.bindGlobalArgumentsPartial(candidate_index, parameterized.parameters, arguments, &bindings) catch continue;\n                if (!try self.inferBindingsFromInput(candidate_index, parameterized.input, input, &bindings)) continue;\n                if (reach_context) |context|\n                    if (!try self.inferBindingsFromReachDefaults(candidate_index, parameterized.input, input, &bindings, context)) continue;\n                const complete_arguments = self.appendBoundArguments(candidate_index, parameterized.parameters, &bindings) catch |err| switch (err) {\n                    error.MissingGenericArgument => continue,\n                    else => return err,\n                };\n''',
    '''                var bindings = try generic_mod.Resolver.Bindings.init(self.allocator, candidate_module.semantic.parameterized_storage.comptime_parameters.items.len);\n                defer bindings.deinit(self.allocator);\n                const trace_copy = std.mem.eql(u8, name, "copy");\n                if (trace_copy) std.debug.print("[copy-explicit] module={} decl={} params={}+{} args={}+{}\\n", .{ candidate_index, @intFromEnum(parameterized.declaration), parameterized.parameters.start, parameterized.parameters.len, arguments.start, arguments.len });\n                self.generics.bindGlobalArgumentsPartial(candidate_index, parameterized.parameters, arguments, &bindings) catch |err| {\n                    if (trace_copy) std.debug.print("[copy-explicit] bind-partial failed: {s}\\n", .{@errorName(err)});\n                    continue;\n                };\n                const input_inferred = try self.inferBindingsFromInput(candidate_index, parameterized.input, input, &bindings);\n                if (trace_copy) std.debug.print("[copy-explicit] input-inferred={}\\n", .{input_inferred});\n                if (!input_inferred) continue;\n                if (reach_context) |context| {\n                    const reach_inferred = try self.inferBindingsFromReachDefaults(candidate_index, parameterized.input, input, &bindings, context);\n                    if (trace_copy) std.debug.print("[copy-explicit] reach-inferred={}\\n", .{reach_inferred});\n                    if (!reach_inferred) continue;\n                }\n                const complete_arguments = self.appendBoundArguments(candidate_index, parameterized.parameters, &bindings) catch |err| {\n                    if (trace_copy) std.debug.print("[copy-explicit] append-bound failed: {s}\\n", .{@errorName(err)});\n                    switch (err) {\n                        error.MissingGenericArgument => continue,\n                        else => return err,\n                    }\n                };\n                if (trace_copy) std.debug.print("[copy-explicit] complete args={}+{}\\n", .{ complete_arguments.start, complete_arguments.len });\n''',
    "explicit copy trace",
)
old_match = '''                const score = switch (self.matchParameterizedInput(candidate_index, parameterized.input, &bindings, input)) {\n                    .no_match => continue,\n                    .deferred => {\n                        saw_deferred = true;\n                        continue;\n                    },\n                    .score => |score| score,\n                };\n'''
new_match = '''                const match = self.matchParameterizedInput(candidate_index, parameterized.input, &bindings, input);\n                if (trace_copy) std.debug.print("[copy-explicit] match={s}\\n", .{@tagName(match)});\n                const score = switch (match) {\n                    .no_match => continue,\n                    .deferred => {\n                        saw_deferred = true;\n                        continue;\n                    },\n                    .score => |score| score,\n                };\n'''
text = path.read_text()
if text.count(old_match) < 1:
    raise RuntimeError("explicit copy match trace anchor missing")
path.write_text(text.replace(old_match, new_match, 1))
subprocess.run(["zig", "fmt", str(path)], check=True)

Path(".git/semantic-refactor-message").write_text("Trace explicit DynamicArray copy resolution")
Path(".git/semantic-refactor-test-command").write_text(
    "zig build test-programs -Dtest-filter=feature_tests/collections/18_dynamic_array_copy\n"
)
