from pathlib import Path
import subprocess


def replace_once(path: Path, old: str, new: str, label: str) -> None:
    text = path.read_text()
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label} anchor changed: {count}")
    path.write_text(text.replace(old, new, 1))


# Construction-time poison IDs may be observed while generic input inference is
# running. They are not indexable semantic types; leave the candidate unmatched
# until the fixed-point pass has materialized the binding type.
generic_functions = Path("src/4_semantics/global/generic_functions.zig")
replace_once(
    generic_functions,
    '''    ) anyerror!bool {\n        const module = &self.modules[module_index];\n        const storage = &module.semantic.parameterized_storage.ir;\n''',
    '''    ) anyerror!bool {\n        const actual_raw: usize = @intFromEnum(actual);\n        if (actual_raw >= self.graph.types.items.len or self.graph.isTypeUnresolved(actual)) return false;\n        const module = &self.modules[module_index];\n        const storage = &module.semantic.parameterized_storage.ir;\n''',
    "unresolved generic input guard",
)

# Source calls can infer implicit abstract generic parameters from omitted
# #reach defaults. Probe only the caller-visible type path here; the concrete
# default node is still materialized later by completeCallInputFieldsWithReach.
replace_once(
    generic_functions,
    '''pub const Stats = struct {\n    instances: u32 = 0,\n    calls: u32 = 0,\n    nodes: u32 = 0,\n};\n\n''',
    '''pub const Stats = struct {\n    instances: u32 = 0,\n    calls: u32 = 0,\n    nodes: u32 = 0,\n};\n\nconst ReachInferenceContext = struct {\n    module: *const module_sg.ModuleSemanticGraph,\n    offsets: globalizer.Offsets,\n    visible_bindings: module_entities.BindingRange,\n};\n\n''',
    "reach inference context",
)

replace_once(
    generic_functions,
    '''        const function = if (local_args) |args|\n            self.resolveExplicitGenericFunction(module_index, module, reference, try self.generics.relocateModuleArguments(module_index, args), input) catch |err| switch (err) {\n''',
    '''        const reach_context: ReachInferenceContext = .{ .module = module, .offsets = o, .visible_bindings = value.visible_bindings };\n        const function = if (local_args) |args|\n            self.resolveExplicitGenericFunction(module_index, module, reference, try self.generics.relocateModuleArguments(module_index, args), input, reach_context) catch |err| switch (err) {\n''',
    "explicit source reach context",
)
replace_once(
    generic_functions,
    '''            self.resolveImplicitGenericFunction(module_index, module, reference, input) catch |err| switch (err) {\n''',
    '''            self.resolveImplicitGenericFunction(module_index, module, reference, input, reach_context) catch |err| switch (err) {\n''',
    "implicit source reach context",
)

replace_once(
    generic_functions,
    '''        arguments: primitives.Range(global_sg.GlobalGenericArgId),\n        input: global_sg.GlobalNodeId,\n    ) !global_sg.GlobalFunctionId {\n''',
    '''        arguments: primitives.Range(global_sg.GlobalGenericArgId),\n        input: global_sg.GlobalNodeId,\n        reach_context: ?ReachInferenceContext,\n    ) !global_sg.GlobalFunctionId {\n''',
    "explicit resolver context parameter",
)
replace_once(
    generic_functions,
    '''                if (!try self.inferBindingsFromInput(candidate_index, parameterized.input, input, &bindings)) continue;\n                const complete_arguments = try self.appendBoundArguments(candidate_index, parameterized.parameters, &bindings);\n''',
    '''                if (!try self.inferBindingsFromInput(candidate_index, parameterized.input, input, &bindings)) continue;\n                if (reach_context) |context|\n                    if (!try self.inferBindingsFromReachDefaults(candidate_index, parameterized.input, input, &bindings, context)) continue;\n                const complete_arguments = self.appendBoundArguments(candidate_index, parameterized.parameters, &bindings) catch |err| switch (err) {\n                    error.MissingGenericArgument => continue,\n                    else => return err,\n                };\n''',
    "explicit reach default inference",
)

replace_once(
    generic_functions,
    '''        reference: module_entities.ExternalRef,\n        input: global_sg.GlobalNodeId,\n    ) !global_sg.GlobalFunctionId {\n        const module_filter = if (reference.module_path) |path|\n''',
    '''        reference: module_entities.ExternalRef,\n        input: global_sg.GlobalNodeId,\n        reach_context: ?ReachInferenceContext,\n    ) !global_sg.GlobalFunctionId {\n        const module_filter = if (reference.module_path) |path|\n''',
    "implicit resolver context parameter",
)
replace_once(
    generic_functions,
    '''            module_filter,\n            input,\n            null,\n        );\n''',
    '''            module_filter,\n            input,\n            reach_context,\n            null,\n        );\n''',
    "implicit filtered context forwarding",
)
replace_once(
    generic_functions,
    '''        return self.resolveImplicitGenericFunctionFiltered(current_module, name, null, input, null);\n''',
    '''        return self.resolveImplicitGenericFunctionFiltered(current_module, name, null, input, null, null);\n''',
    "compiler generated implicit call",
)
replace_once(
    generic_functions,
    '''        module_filter: ?global_sg.GlobalModuleId,\n        input: global_sg.GlobalNodeId,\n        ambiguity_candidates: ?*std.ArrayList(global_sg.GlobalDeclId),\n''',
    '''        module_filter: ?global_sg.GlobalModuleId,\n        input: global_sg.GlobalNodeId,\n        reach_context: ?ReachInferenceContext,\n        ambiguity_candidates: ?*std.ArrayList(global_sg.GlobalDeclId),\n''',
    "filtered resolver context parameter",
)
replace_once(
    generic_functions,
    '''                if (!matches) {\n                    if (candidate_deferred) saw_deferred = true;\n                    continue;\n                }\n                var arguments: std.ArrayList(global_sg.GenericArgument) = .empty;\n''',
    '''                if (!matches) {\n                    if (candidate_deferred) saw_deferred = true;\n                    continue;\n                }\n                if (reach_context) |context|\n                    if (!try self.inferBindingsFromReachDefaults(candidate_index, parameterized.input, input, &bindings, context)) continue;\n                var arguments: std.ArrayList(global_sg.GenericArgument) = .empty;\n''',
    "implicit reach default inference",
)
replace_once(
    generic_functions,
    '''            module_filter,\n            input,\n            candidates,\n        ) catch |err| return switch (err) {\n''',
    '''            module_filter,\n            input,\n            null,\n            candidates,\n        ) catch |err| return switch (err) {\n''',
    "ambiguity resolver without caller context",
)

# Generic bodies synthesize calls outside a source PendingOperation, so they do
# not have a caller lexical binding range. Keep their existing behavior.
replace_once(
    generic_functions,
    '''                try self.resolver.resolveExplicitGenericFunction(self.module_index, module, reference, arguments, input)\n''',
    '''                try self.resolver.resolveExplicitGenericFunction(self.module_index, module, reference, arguments, input, null)\n''',
    "nested explicit call context",
)
replace_once(
    generic_functions,
    '''                    self.resolver.resolveImplicitGenericFunction(self.module_index, module, reference, input) catch |err| {\n''',
    '''                    self.resolver.resolveImplicitGenericFunction(self.module_index, module, reference, input, null) catch |err| {\n''',
    "nested implicit call context",
)

# Insert a mutation-free probe. It reads the parameterized reach path, follows
# it through caller-visible GlobalSG bindings/fields, and feeds only the reached
# type back into ordinary generic inference.
anchor = '''    pub fn appendBoundArguments(\n        self: *Resolver,\n'''
helper = '''    fn inferBindingsFromReachDefaults(\n        self: *Resolver,\n        module_index: usize,\n        pattern: ir.ParameterizedTypeId,\n        input: global_sg.GlobalNodeId,\n        bindings: *generic_mod.Resolver.Bindings,\n        context: ReachInferenceContext,\n    ) !bool {\n        const literal = switch (self.graph.nodes.items[@intFromEnum(input)].content) {\n            .struct_value_literal => |value| value,\n            else => return true,\n        };\n        const candidate_module = &self.modules[module_index];\n        const storage = &candidate_module.semantic.parameterized_storage.ir;\n        const shape = switch (storage.types.items[@intFromEnum(pattern)]) {\n            .resolved => |resolved| switch (resolved) {\n                .structural => |value| value,\n                else => return true,\n            },\n            else => return true,\n        };\n\n        for (storage.fields.items[shape.fields.start..][0..shape.fields.len], 0..) |field, position| {\n            var supplied = false;\n            for (self.graph.value_fields.items[literal.fields.start..][0..literal.fields.len], 0..) |value, supplied_position| {\n                const positional = supplied_position < literal.dispatch_prefix_positional_count or self.graph.text(value.name).len == 0;\n                if (if (positional) position == supplied_position else std.mem.eql(u8, candidate_module.text(field.name), self.graph.text(value.name))) {\n                    supplied = true;\n                    break;\n                }\n            }\n            if (supplied) continue;\n            const default_id = field.default_value orelse continue;\n            const default_node = switch (storage.nodes.items[@intFromEnum(default_id)]) {\n                .resolved => |node| node,\n                .pending => continue,\n            };\n            const reach_id = switch (default_node.content) {\n                .reach_directive => |reach| reach,\n                else => continue,\n            };\n            const reach = storage.reaches.items[@intFromEnum(reach_id)];\n            const scope = context.module.semantic.binding_refs.items[context.visible_bindings.start..][0..context.visible_bindings.len];\n\n            var inferred = false;\n            for (storage.reach_alternatives.items[reach.alternatives.start..][0..reach.alternatives.len]) |alternative| {\n                if (alternative.segments.len == 0) continue;\n                const segments = storage.reach_segments.items[alternative.segments.start..][0..alternative.segments.len];\n                const root_name = candidate_module.text(segments[0]);\n                var scope_index = scope.len;\n                while (scope_index > 0) {\n                    scope_index -= 1;\n                    const binding_id = globalizer.globalBinding(context.offsets, scope[scope_index]);\n                    if (self.graph.isBindingTypeUnresolved(binding_id)) continue;\n                    const binding = self.graph.bindings.items[@intFromEnum(binding_id)];\n                    if (!std.mem.eql(u8, self.graph.text(binding.name), root_name)) continue;\n                    var current_ty = binding.ty;\n                    var valid = !self.graph.isTypeUnresolved(current_ty);\n                    for (segments[1..]) |segment| {\n                        if (!valid) break;\n                        const hit = global_types.findField(self.graph, current_ty, candidate_module.text(segment)) orelse {\n                            valid = false;\n                            break;\n                        };\n                        current_ty = hit.field.storage_type orelse hit.field.ty;\n                        if (self.graph.isTypeUnresolved(current_ty)) valid = false;\n                    }\n                    if (!valid) continue;\n                    const matched = self.inferInputType(module_index, field.ty, current_ty, bindings) catch |err| switch (err) {\n                        error.ConflictingGenericArgument => return false,\n                        else => continue,\n                    };\n                    if (matched) {\n                        inferred = true;\n                        break;\n                    }\n                }\n                if (inferred) break;\n            }\n        }\n        return true;\n    }\n\n'''
replace_once(generic_functions, anchor, helper + anchor, "reach default type inference helper")

# Constrained type parameters such as `.t: Type: ImplicitlyCopyable` are stored
# by syntaxing with the bound as field.type_node. Reuse the canonical classifier
# for parameterized abstract relations too.
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

Path(".git/semantic-refactor-message").write_text("Infer generic bindings from reach defaults")
Path(".git/semantic-refactor-test-command").write_text(
    "zig build test-programs "
    "-Dtest-filter=feature_tests/control_flow/04_for_dynamic_array "
    "-Dtest-filter=feature_tests/control_flow/14_for_mut_borrowed_dynamic_array "
    "-Dtest-filter=feature_tests/collections/09_dynamic_array_ergonomic "
    "-Dtest-filter=feature_tests/collections/16_dynamic_array_iterator_manual\n"
)
