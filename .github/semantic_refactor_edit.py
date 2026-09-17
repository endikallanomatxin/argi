from pathlib import Path
import re
import subprocess


def replace_exact_count(text: str, old: str, new: str, expected: int, label: str) -> str:
    count = text.count(old)
    if count != expected:
        raise RuntimeError(f"{label} anchor changed: {count}")
    return text.replace(old, new)


# Generic constructor initializer fixes.
path = Path("src/4_semantics/global/constructors.zig")
text = path.read_text()
text = replace_exact_count(
    text,
    "parameterized.input, context, &bindings",
    "parameterized.input, input, context, &bindings",
    2,
    "initializer reach call with local bindings",
)
text = replace_exact_count(
    text,
    "parameterized.input, context, bindings",
    "parameterized.input, input, context, bindings",
    1,
    "initializer reach call with forwarded bindings",
)
pattern = re.compile(
    r"    fn inferInitializerReachBindings\(.*?\n    fn parameterizedReachType\(",
    re.S,
)
replacement = '''    fn inferInitializerReachBindings(
        self: *Resolver,
        generic_functions: *generic_functions_mod.Resolver,
        candidate_index: usize,
        pattern: @import("../module/parameterized/ir.zig").ParameterizedTypeId,
        input: global_sg.GlobalNodeId,
        context: CallerContext,
        bindings: *generic_mod.Resolver.Bindings,
    ) !bool {
        const literal = switch (self.graph.nodes.items[@intFromEnum(input)].content) {
            .struct_value_literal => |value| value,
            else => return false,
        };
        const module = &self.modules[candidate_index];
        const storage = &module.semantic.parameterized_storage.ir;
        const shape = switch (storage.types.items[@intFromEnum(pattern)]) {
            .resolved => |ty| switch (ty) {
                .structural => |value| value,
                else => return false,
            },
            else => return false,
        };
        if (shape.fields.len == 0) return false;
        for (storage.fields.items[shape.fields.start + 1 ..][0 .. shape.fields.len - 1], 0..) |field, expected_position| {
            var supplied = false;
            for (self.graph.value_fields.items[literal.fields.start..][0..literal.fields.len], 0..) |value, supplied_position| {
                const positional = supplied_position < literal.dispatch_prefix_positional_count or self.graph.text(value.name).len == 0;
                if (if (positional)
                    expected_position == supplied_position
                else
                    std.mem.eql(u8, module.text(field.name), self.graph.text(value.name)))
                {
                    supplied = true;
                    break;
                }
            }
            if (supplied) continue;

            const default = field.default_value orelse continue;
            const actual = self.parameterizedReachType(candidate_index, default, context) orelse continue;
            if (!try generic_functions.inferInputType(candidate_index, field.ty, actual, bindings)) return false;
        }
        return true;
    }

    fn parameterizedReachType('''
text, count = pattern.subn(lambda _: replacement, text, count=1)
if count != 1:
    raise RuntimeError(f"initializer reach function anchor changed: {count}")

# Temporary generic resolvers used by constructor specialization need the same
# nested dispatch facilities as the top-level generic resolver.
text = replace_exact_count(
    text,
    ".nested_call_context = self.abstracts,\n",
    ".nested_call_context = self.abstracts,\n"
    "            .nested_call_resolver = abstract_mod.Resolver.resolveNestedCall,\n"
    "            .nested_constructor_context = self,\n"
    "            .nested_constructor_resolver = Resolver.resolveNestedCall,\n",
    2,
    "existing temporary resolver context",
)
old = '''        var generic_functions = generic_functions_mod.Resolver{
            .allocator = self.core.allocator,
            .graph = self.graph,
            .modules = self.modules,
            .offsets = self.offsets,
            .core = self.core,
            .generics = &generics,
        };
        const input = globalizer.globalNode(o, value.input);
'''
new = '''        var generic_functions = generic_functions_mod.Resolver{
            .allocator = self.core.allocator,
            .graph = self.graph,
            .modules = self.modules,
            .offsets = self.offsets,
            .core = self.core,
            .generics = &generics,
            .nested_call_context = self.abstracts,
            .nested_call_resolver = abstract_mod.Resolver.resolveNestedCall,
            .nested_constructor_context = self,
            .nested_constructor_resolver = Resolver.resolveNestedCall,
        };
        const input = globalizer.globalNode(o, value.input);
'''
text = replace_exact_count(text, old, new, 1, "explicit generic constructor resolver")
path.write_text(text)


# Static dispatch through a proven abstract bound. This deliberately does not
# relax ordinary module visibility: only a concrete implementation of the
# exact requirement signature can be selected.
apath = Path("src/4_semantics/global/abstracts.zig")
atext = apath.read_text()
anchor = '''    pub fn resolveNestedCall(
        self: *Resolver,
        module_index: usize,
        reference: module_entities.ExternalRef,
        input: global_sg.GlobalNodeId,
        source: primitives.SourceRef,
    ) anyerror!?global_sg.Node {
        return self.makeVirtualCall(module_index, reference, input, source);
    }
'''
addition = '''    pub fn resolveStaticRequirementCall(
        self: *Resolver,
        module_index: usize,
        abstract_ref: ir.DeclarationRef,
        concrete: global_sg.GlobalTypeId,
        reference: module_entities.ExternalRef,
        input: global_sg.GlobalNodeId,
        source: primitives.SourceRef,
    ) !?global_sg.Node {
        if (reference.module_path != null or reference.generic_arguments != null) return null;
        const abstract_decl = try self.resolveDeclarationRef(module_index, abstract_ref, .abstract_type);
        if (!try self.implements(concrete, abstract_decl)) return null;
        const located = self.findAbstractDefinition(abstract_decl) orelse return null;
        // Parameterized abstract requirements need their own abstract argument
        // substitution. The current hidden local-abstract lowering only needs
        // non-parameterized contracts such as Allocator.
        if (located.definition.parameters.len != 0) return null;

        const method_name = self.modules[module_index].text(reference.name);
        const storage = &self.modules[located.module_index].semantic.parameterized_storage;
        for (storage.abstract_requirements.items[located.definition.requirements.start..][0..located.definition.requirements.len], 0..) |requirement, method_index| {
            if (!std.mem.eql(u8, self.modules[located.module_index].text(requirement.name), method_name)) continue;
            const instance = try self.requirementInstance(abstract_decl, concrete, located, requirement, @intCast(method_index));
            const implementation = self.findConcreteMethod(method_name, instance.input) orelse continue;
            const input_fields = global_types.fields(self.graph, instance.input) orelse continue;
            if (self.core.scoreCallInput(input_fields, input) == null) continue;
            if (!try self.core.completeCallInputFields(input_fields, input)) continue;
            return .{
                .source = source,
                .ty = try self.core.functionOutputType(implementation),
                .content = .{ .function_call = .{ .callee = implementation, .input = input } },
            };
        }
        return null;
    }

''' + anchor
atext = replace_exact_count(atext, anchor, addition, 1, "static abstract dispatch insertion")
apath.write_text(atext)


# During generic-body materialization, a hidden abstract type parameter has
# already been specialized to a concrete type. Let calls satisfying that
# parameter's requirement resolve statically to the concrete implementation.
gpath = Path("src/4_semantics/global/generic_functions.zig")
gtext = gpath.read_text()
make_call_anchor = '''        fn makeNamedCall(
            self: *InstanceContext,
            name_range: primitives.StringRange,
'''
helper = '''        fn resolveConstrainedStaticCall(
            self: *InstanceContext,
            reference: module_entities.ExternalRef,
            input: global_sg.GlobalNodeId,
            source: primitives.SourceRef,
        ) !?global_sg.Node {
            const abstracts = self.resolver.nested_call_context orelse return null;
            const storage = &self.resolver.modules[self.module_index].semantic.parameterized_storage;
            for (0..self.parameterized.parameters.len) |offset| {
                const raw = self.parameterized.parameters.start + @as(u32, @intCast(offset));
                const parameter = storage.comptime_parameters.items[raw];
                const constraint_id = parameter.constraint orelse continue;
                const concrete = self.substitutions.types[raw] orelse continue;
                const constraint = storage.abstract_constraints.items[@intFromEnum(constraint_id)];
                if (try abstracts.resolveStaticRequirementCall(
                    self.module_index,
                    constraint.abstract_ref,
                    concrete,
                    reference,
                    input,
                    self.resolver.sourceFor(self.module_index, source),
                )) |node| return node;
            }
            return null;
        }

''' + make_call_anchor
gtext = replace_exact_count(gtext, make_call_anchor, helper, 1, "constrained static call helper")
old = '''                    if (self.resolver.nested_call_context) |context| {
                        if (self.resolver.nested_call_resolver) |resolve| {
                            if (try resolve(context, self.module_index, reference, input, self.resolver.sourceFor(self.module_index, source))) |node|
                                return node;
                        }
                    }
'''
new = '''                    if (arguments.len == 0) {
                        if (try self.resolveConstrainedStaticCall(reference, input, source)) |node| return node;
                    }
                    if (self.resolver.nested_call_context) |context| {
                        if (self.resolver.nested_call_resolver) |resolve| {
                            if (try resolve(context, self.module_index, reference, input, self.resolver.sourceFor(self.module_index, source))) |node|
                                return node;
                        }
                    }
'''
gtext = replace_exact_count(gtext, old, new, 1, "static dispatch fallback")
gpath.write_text(gtext)

for p in (path, apath, gpath):
    subprocess.run(["zig", "fmt", str(p)], check=True)

Path(".git/semantic-refactor-test-command").write_text(
    "zig build test-programs -Dtest-filter=feature_tests/collections/23_dynamic_array_owning_push_fixed && "
    "zig build test-programs -Dtest-filter=feature_tests/collections/24_dynamic_array_owning_insert_fixed && "
    "zig build test-programs -Dtest-filter=feature_tests/collections/30_dynamic_array_custom_allocator && "
    "zig build test-programs -Dtest-filter=feature_tests/collections/26_dynamic_array_owning_pop && "
    "zig build test-programs -Dtest-filter=feature_tests/text/08_string_allocator_size && "
    "zig build test-programs -Dtest-filter=feature_tests/modules/24_imported_generic_abstract_dispatch_prefers_concrete\n"
)
