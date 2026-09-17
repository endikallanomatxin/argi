from pathlib import Path
import subprocess


def replace_once(path: Path, old: str, new: str, label: str) -> None:
    text = path.read_text()
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label} anchor changed: {count}")
    path.write_text(text.replace(old, new, 1))


Path(".github/semantic_refactor_post_edit.py").write_text("# no-op verified edit run\n")

# Explicit generic overload inference must keep conflicts candidate-local.
generic_functions = Path("src/4_semantics/global/generic_functions.zig")
replace_once(
    generic_functions,
    '''                self.generics.bindGlobalArgumentsPartial(candidate_index, parameterized.parameters, arguments, &bindings) catch continue;\n                if (!try self.inferBindingsFromInput(candidate_index, parameterized.input, input, &bindings)) continue;\n                if (reach_context) |context|\n                    if (!try self.inferBindingsFromReachDefaults(candidate_index, parameterized.input, input, &bindings, context)) continue;\n''',
    '''                self.generics.bindGlobalArgumentsPartial(candidate_index, parameterized.parameters, arguments, &bindings) catch continue;\n                const input_inferred = self.inferBindingsFromInput(candidate_index, parameterized.input, input, &bindings) catch |err| switch (err) {\n                    error.ConflictingGenericArgument => continue,\n                    else => return err,\n                };\n                if (!input_inferred) continue;\n                if (reach_context) |context|\n                    if (!try self.inferBindingsFromReachDefaults(candidate_index, parameterized.input, input, &bindings, context)) continue;\n''',
    "explicit generic candidate-local input conflict",
)

# trusted_opaque_relocate has an intentionally empty Argi body: at runtime it
# is a bitwise move between opaque slots. Lower it directly instead of calling
# the empty function body.
codegen = Path("src/5_codegen/global_codegen.zig")
replace_once(
    codegen,
    '''        if (callee.safety_primitive == .trusted_opaque_move or callee.safety_primitive == .trusted_opaque_move_in) return self.opaqueStore(call.input);\n        if (callee.safety_primitive == .trusted_opaque_move_out) return self.opaqueTake(call.input);\n        if (callee.safety_primitive == .trusted_opaque_drop) return self.opaqueDrop(call.input, callee);\n''',
    '''        if (callee.safety_primitive == .trusted_opaque_move or callee.safety_primitive == .trusted_opaque_move_in) return self.opaqueStore(call.input);\n        if (callee.safety_primitive == .trusted_opaque_move_out) return self.opaqueTake(call.input);\n        if (callee.safety_primitive == .trusted_opaque_relocate) return self.opaqueRelocate(call.input);\n        if (callee.safety_primitive == .trusted_opaque_drop) return self.opaqueDrop(call.input, callee);\n''',
    "dispatch trusted opaque relocation",
)
replace_once(
    codegen,
    '''    fn opaqueDrop(self: *CodeGenerator, input_id: graph_mod.GlobalNodeId, primitive: graph_mod.Function) !?TypedValue {\n''',
    '''    fn opaqueRelocate(self: *CodeGenerator, input_id: graph_mod.GlobalNodeId) !?TypedValue {\n        const input = switch (self.graph.nodes.items[@intFromEnum(input_id)].content) {\n            .struct_value_literal => |literal| literal,\n            else => return CodegenError.InvalidType,\n        };\n        const fields = self.graph.value_fields.items[input.fields.start..][0..input.fields.len];\n        if (fields.len != 2) return CodegenError.InvalidType;\n\n        const source_node = fields[0].value;\n        const destination_node = fields[1].value;\n        const source = (try self.visitNode(source_node)) orelse return CodegenError.ValueNotFound;\n        const destination = (try self.visitNode(destination_node)) orelse return CodegenError.ValueNotFound;\n        const source_pointer_ty = self.graph.nodes.items[@intFromEnum(source_node)].ty orelse return CodegenError.InvalidType;\n        const destination_pointer_ty = self.graph.nodes.items[@intFromEnum(destination_node)].ty orelse return CodegenError.InvalidType;\n        const source_child = switch (self.graph.semanticType(source_pointer_ty)) {\n            .pointer => |pointer| pointer.child,\n            else => return CodegenError.InvalidType,\n        };\n        const destination_child = switch (self.graph.semanticType(destination_pointer_ty)) {\n            .pointer => |pointer| pointer.child,\n            else => return CodegenError.InvalidType,\n        };\n        if (!types.equal(self.graph, source_child, destination_child)) return CodegenError.InvalidType;\n\n        const type_ref = try self.toLLVMType(source_child);\n        const value = c.LLVMBuildLoad2(self.builder, type_ref, source.value_ref, "opaque.relocate");\n        _ = c.LLVMBuildStore(self.builder, value, destination.value_ref);\n        return null;\n    }\n\n    fn opaqueDrop(self: *CodeGenerator, input_id: graph_mod.GlobalNodeId, primitive: graph_mod.Function) !?TypedValue {\n''',
    "lower trusted opaque relocation",
)

subprocess.run([
    "zig", "fmt",
    "src/4_semantics/global/generic_functions.zig",
    "src/5_codegen/global_codegen.zig",
], check=True)

Path(".git/semantic-refactor-message").write_text("Fix explicit generic conflicts and opaque relocation")
Path(".git/semantic-refactor-test-command").write_text(
    "zig build test-programs "
    "-Dtest-filter=feature_tests/collections/09_dynamic_array_ergonomic "
    "-Dtest-filter=feature_tests/collections/18_dynamic_array_copy "
    "-Dtest-filter=feature_tests/control_flow/04_for_dynamic_array "
    "-Dtest-filter=feature_tests/control_flow/14_for_mut_borrowed_dynamic_array\n"
)
