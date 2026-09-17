from pathlib import Path
import subprocess


def replace_once(path: Path, old: str, new: str, label: str) -> None:
    text = path.read_text()
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label} anchor changed: {count}")
    path.write_text(text.replace(old, new, 1))


# Generic inference can see construction-time poison IDs while GlobalSema is
# still inferring binding types. They are deferred inputs, never indexable types.
generic_functions = Path("src/4_semantics/global/generic_functions.zig")
replace_once(
    generic_functions,
    '''    ) anyerror!bool {\n        const module = &self.modules[module_index];\n        const storage = &module.semantic.parameterized_storage.ir;\n''',
    '''    ) anyerror!bool {\n        const actual_raw: usize = @intFromEnum(actual);\n        if (actual_raw >= self.graph.types.items.len or self.graph.isTypeUnresolved(actual)) return false;\n        const module = &self.modules[module_index];\n        const storage = &module.semantic.parameterized_storage.ir;\n''',
    "unresolved generic input guard",
)

# Focused trace for the next parity hole: generic DynamicArray deinit is not
# selected. Record each parameterized deinit candidate, inference result and
# final input match without changing dispatch semantics yet.
replace_once(
    generic_functions,
    '''                const shape = switch (storage.types.items[@intFromEnum(parameterized.input)]) {\n                    .resolved => |ty| switch (ty) {\n                        .structural => |shape| shape,\n                        else => continue,\n                    },\n                    else => continue,\n                };\n                var matches = true;\n''',
    '''                const shape = switch (storage.types.items[@intFromEnum(parameterized.input)]) {\n                    .resolved => |ty| switch (ty) {\n                        .structural => |shape| shape,\n                        else => continue,\n                    },\n                    else => continue,\n                };\n                if (std.mem.eql(u8, name, "deinit")) {\n                    std.debug.print(\n                        "[deinit-candidate] module={} decl={} params={}+{} fields={}\\n",\n                        .{ candidate_index, @intFromEnum(declaration), parameterized.parameters.start, parameterized.parameters.len, shape.fields.len },\n                    );\n                    for (storage.fields.items[shape.fields.start..][0..shape.fields.len]) |trace_field|\n                        std.debug.print("[deinit-field] module={} decl={} name={s} pattern={} default={}\\n", .{ candidate_index, @intFromEnum(declaration), candidate_module.text(trace_field.name), @intFromEnum(trace_field.ty), trace_field.default_value != null });\n                }\n                var matches = true;\n''',
    "deinit candidate trace",
)
replace_once(
    generic_functions,
    '''                        _ = self.inferInputType(candidate_index, field.ty, actual, &bindings) catch |err| {\n                            if (err == error.ConflictingGenericArgument) {\n                                conflicting_candidates += 1;\n                                matches = false;\n                                break;\n                            }\n                            candidate_deferred = true;\n                            matches = false;\n                            break;\n                        };\n                        break;\n''',
    '''                        const inferred = self.inferInputType(candidate_index, field.ty, actual, &bindings) catch |err| {\n                            if (err == error.ConflictingGenericArgument) {\n                                conflicting_candidates += 1;\n                                matches = false;\n                                break;\n                            }\n                            candidate_deferred = true;\n                            matches = false;\n                            break;\n                        };\n                        if (std.mem.eql(u8, name, "deinit"))\n                            std.debug.print(\n                                "[deinit-infer] module={} decl={} field={s} actual={} unresolved={} inferred={}\\n",\n                                .{ candidate_index, @intFromEnum(declaration), candidate_module.text(field.name), @intFromEnum(actual), self.graph.isTypeUnresolved(actual), inferred },\n                            );\n                        break;\n''',
    "deinit inference trace",
)
replace_once(
    generic_functions,
    '''                if (arguments.items.len != parameterized.parameters.len) continue;\n                const range: primitives.Range(global_sg.GlobalGenericArgId) = .{ .start = @intCast(self.graph.generic_arguments.items.len), .len = @intCast(arguments.items.len) };\n                try self.graph.generic_arguments.appendSlice(self.allocator, arguments.items);\n                const score = switch (self.matchParameterizedInput(candidate_index, parameterized.input, &bindings, input)) {\n''',
    '''                if (std.mem.eql(u8, name, "deinit"))\n                    std.debug.print("[deinit-bindings] module={} decl={} bound={}/{}\\n", .{ candidate_index, @intFromEnum(declaration), arguments.items.len, parameterized.parameters.len });\n                if (arguments.items.len != parameterized.parameters.len) continue;\n                const range: primitives.Range(global_sg.GlobalGenericArgId) = .{ .start = @intCast(self.graph.generic_arguments.items.len), .len = @intCast(arguments.items.len) };\n                try self.graph.generic_arguments.appendSlice(self.allocator, arguments.items);\n                const input_match = self.matchParameterizedInput(candidate_index, parameterized.input, &bindings, input);\n                if (std.mem.eql(u8, name, "deinit"))\n                    std.debug.print("[deinit-match] module={} decl={} result={s}\\n", .{ candidate_index, @intFromEnum(declaration), @tagName(input_match) });\n                const score = switch (input_match) {\n''',
    "deinit binding and match trace",
)

# Constrained type parameters such as `.t: Type: ImplicitlyCopyable` are stored
# by syntaxing with the bound as field.type_node. Reuse the canonical classifier
# in abstract implementation/default lowering instead of treating those as ints.
lowerer = Path("src/4_semantics/module/parameterized/lowerer.zig")
replace_once(
    lowerer,
    '''fn isTypeParameter(tree: *const syn.FileSyntaxTree, source: []const u8, field: syn.StructTypeField) bool {\n''',
    '''pub fn isTypeParameter(tree: *const syn.FileSyntaxTree, source: []const u8, field: syn.StructTypeField) bool {\n''',
    "export type parameter classifier",
)

relations = Path("src/4_semantics/module/abstract_relation_lowerer.zig")
replace_once(
    relations,
    '''                const kind: parameterized_storage.ComptimeParameterKind = if (field.type_node) |type_node|\n                    if (isTypeName(self.tree, self.source, type_node, "Type")) .type else .comptime_int\n                else\n                    .type;\n''',
    '''                const kind: parameterized_storage.ComptimeParameterKind = if (parameterized_lowerer.isTypeParameter(self.tree, self.source, field)) .type else .comptime_int;\n''',
    "abstract relation generic parameter classifier",
)

subprocess.run([
    "zig", "fmt",
    "src/4_semantics/global/generic_functions.zig",
    "src/4_semantics/module/parameterized/lowerer.zig",
    "src/4_semantics/module/abstract_relation_lowerer.zig",
], check=True)

Path(".git/semantic-refactor-message").write_text("Unify constrained generic parameter classification")
Path(".git/semantic-refactor-test-command").write_text(
    "zig build test-programs "
    "-Dtest-filter=feature_tests/control_flow/04_for_dynamic_array "
    "-Dtest-filter=feature_tests/control_flow/14_for_mut_borrowed_dynamic_array\n"
)
