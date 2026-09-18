from pathlib import Path
import re
import subprocess

def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected 1 anchor, found {count}")
    return text.replace(old, new, 1)

def replace_count(text: str, old: str, new: str, expected: int, label: str) -> str:
    count = text.count(old)
    if count != expected:
        raise RuntimeError(f"{label}: expected {expected} anchors, found {count}")
    return text.replace(old, new)

# Shared lexical reach context. Module-origin calls and already-globalized
# compiler-synthesized calls must resolve #reach through one abstraction.
reach = Path("src/4_semantics/global/reach_context.zig")
reach.write_text(r'''const module_sg = @import("../module/graph.zig");
const module_entities = @import("../module/entities.zig");
const global_sg = @import("graph.zig");
const globalizer = @import("globalizer.zig");

pub const Context = union(enum) {
    module: Module,
    global: Global,

    pub const Module = struct {
        module: *const module_sg.ModuleSemanticGraph,
        offsets: globalizer.Offsets,
        visible_bindings: module_entities.BindingRange,
        owner_function: ?module_entities.ModuleFunctionId = null,
    };

    pub const Global = struct {
        visible_bindings: []const global_sg.GlobalBindingId,
        owner_function: ?global_sg.GlobalFunctionId = null,
    };

    pub fn fromModule(
        module: *const module_sg.ModuleSemanticGraph,
        offsets: globalizer.Offsets,
        visible_bindings: module_entities.BindingRange,
        owner_function: ?module_entities.ModuleFunctionId,
    ) Context {
        return .{ .module = .{
            .module = module,
            .offsets = offsets,
            .visible_bindings = visible_bindings,
            .owner_function = owner_function,
        } };
    }

    pub fn fromGlobal(
        visible_bindings: []const global_sg.GlobalBindingId,
        owner_function: ?global_sg.GlobalFunctionId,
    ) Context {
        return .{ .global = .{
            .visible_bindings = visible_bindings,
            .owner_function = owner_function,
        } };
    }

    pub fn bindingCount(self: Context) usize {
        return switch (self) {
            .module => |value| @intCast(value.visible_bindings.len),
            .global => |value| value.visible_bindings.len,
        };
    }

    pub fn bindingAt(self: Context, index: usize) global_sg.GlobalBindingId {
        return switch (self) {
            .module => |value| blk: {
                const start: usize = @intCast(value.visible_bindings.start);
                const local = value.module.semantic.binding_refs.items[start + index];
                break :blk globalizer.globalBinding(value.offsets, local);
            },
            .global => |value| value.visible_bindings[index],
        };
    }

    pub fn ownerFunction(self: Context) ?global_sg.GlobalFunctionId {
        return switch (self) {
            .module => |value| if (value.owner_function) |owner|
                globalizer.globalFunction(value.offsets, owner)
            else
                null,
            .global => |value| value.owner_function,
        };
    }
};

test "reach context preserves globalized lexical binding identity" {
    const std = @import("std");
    const binding: global_sg.GlobalBindingId = @enumFromInt(7);
    const context = Context.fromGlobal(&.{binding}, null);
    try std.testing.expectEqual(@as(usize, 1), context.bindingCount());
    try std.testing.expectEqual(binding, context.bindingAt(0));
    try std.testing.expect(context.ownerFunction() == null);
}
''')

# Core: make reach completion consume the shared context rather than a module-
# local tuple. This is the canonical implementation for both source and
# compiler-synthesized calls.
path = Path("src/4_semantics/global/core.zig")
text = path.read_text()
text = replace_once(
    text,
    'const globalizer = @import("globalizer.zig");\n',
    'const globalizer = @import("globalizer.zig");\nconst reach_context = @import("reach_context.zig");\n',
    "core reach import",
)
text = replace_once(
    text,
    '        if (!try self.completeCallInputWithReach(function, input, module, o, value.visible_bindings, value.owner_function)) return .deferred;\n',
    '        const reach = reach_context.Context.fromModule(module, o, value.visible_bindings, value.owner_function);\n'
    '        if (!try self.completeCallInputWithReach(function, input, reach)) return .deferred;\n',
    "core source-call reach",
)
old = '''    fn completeCallInputWithReach(self: *Resolver, function_id: global_sg.GlobalFunctionId, input_node: global_sg.GlobalNodeId, module: *const module_sg.ModuleSemanticGraph, o: globalizer.Offsets, visible: module_entities.BindingRange, owner: ?module_entities.ModuleFunctionId) !bool {
        return self.completeCallInputFieldsWithReach(self.graph.functions.items[@intFromEnum(function_id)].input, input_node, module, o, visible, owner);
    }
'''
new = '''    fn completeCallInputWithReach(
        self: *Resolver,
        function_id: global_sg.GlobalFunctionId,
        input_node: global_sg.GlobalNodeId,
        context: reach_context.Context,
    ) !bool {
        return self.completeCallInputFieldsWithReach(
            self.graph.functions.items[@intFromEnum(function_id)].input,
            input_node,
            context,
        );
    }
'''
text = replace_once(text, old, new, "core reach wrapper")
pattern = re.compile(
    r'    pub fn completeCallInputFieldsWithReach\(.*?\n    fn resolveReachedDefault\(',
    re.S,
)
replacement = r'''    pub fn completeCallInputFieldsWithReach(
        self: *Resolver,
        expected_fields: global_sg.FieldRange,
        input_node: global_sg.GlobalNodeId,
        context: reach_context.Context,
    ) !bool {
        const literal = switch (self.graph.nodes.items[@intFromEnum(input_node)].content) {
            .struct_value_literal => |value| value,
            else => return false,
        };
        const node_mark = self.graph.nodes.items.len;
        const field_mark = self.graph.value_fields.items.len;
        var published = false;
        defer if (!published) {
            self.graph.nodes.shrinkRetainingCapacity(node_mark);
            self.graph.value_fields.shrinkRetainingCapacity(field_mark);
        };
        const start: u32 = @intCast(field_mark);
        for (0..expected_fields.len) |offset| {
            const expected = self.graph.fields.items[expected_fields.start + @as(u32, @intCast(offset))];
            var node = self.callArgument(literal, offset, expected.name);
            if (node == null) {
                const fallback = expected.default_value orelse return false;
                node = if (self.graph.nodes.items[@intFromEnum(fallback)].content == .reach_directive)
                    try self.resolveReachedDefault(context, fallback, expected.ty)
                else
                    fallback;
                if (node == null and self.graph.nodes.items[@intFromEnum(fallback)].content == .reach_directive)
                    node = try self.propagateReachedDefault(context.ownerFunction(), expected, fallback);
            }
            const value = node orelse return false;
            _ = self.coerceContextualLiteral(value, expected.ty);
            try self.graph.value_fields.append(self.allocator, .{ .name = expected.name, .value = value });
        }
        const ty = try self.structType(expected_fields);
        self.graph.nodes.items[@intFromEnum(input_node)].ty = ty;
        self.graph.nodes.items[@intFromEnum(input_node)].content.struct_value_literal = .{
            .fields = .{ .start = start, .len = expected_fields.len },
        };
        published = true;
        return true;
    }

    fn resolveReachedDefault('''
text, count = pattern.subn(lambda _: replacement, text, count=1)
if count != 1:
    raise RuntimeError(f"core reach completion block: {count}")

pattern = re.compile(
    r'    fn resolveReachedDefault\(.*?\n    fn propagateReachedDefault\(',
    re.S,
)
replacement = r'''    fn resolveReachedDefault(
        self: *Resolver,
        context: reach_context.Context,
        default_node: global_sg.GlobalNodeId,
        expected: global_sg.GlobalTypeId,
    ) !?global_sg.GlobalNodeId {
        const reach_id = self.graph.nodes.items[@intFromEnum(default_node)].content.reach_directive;
        const reach = self.graph.reaches.items[@intFromEnum(reach_id)];
        const source = self.graph.nodes.items[@intFromEnum(default_node)].source;
        for (self.graph.reach_alternatives.items[reach.alternatives.start..][0..reach.alternatives.len]) |alternative| {
            if (alternative.segments.len == 0) continue;
            const segments = self.graph.reach_segments.items[alternative.segments.start..][0..alternative.segments.len];
            const root_name = self.graph.text(segments[0]);
            var scope_index = context.bindingCount();
            while (scope_index > 0) {
                scope_index -= 1;
                const binding_id = context.bindingAt(scope_index);
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
                if (!valid or (!types.equal(self.graph, current_ty, expected) and !self.callTypesCompatible(current_ty, expected))) continue;
                var node: global_sg.GlobalNodeId = @enumFromInt(@as(u32, @intCast(self.graph.nodes.items.len)));
                try self.graph.nodes.append(self.allocator, .{
                    .source = source,
                    .ty = binding.ty,
                    .content = .{ .binding_use = binding_id },
                });
                for (hits.items) |hit| {
                    const next: global_sg.GlobalNodeId = @enumFromInt(@as(u32, @intCast(self.graph.nodes.items.len)));
                    try self.graph.nodes.append(self.allocator, .{
                        .source = source,
                        .ty = hit.field.storage_type orelse hit.field.ty,
                        .content = .{ .struct_field_access = .{
                            .value = node,
                            .field_name = hit.field.name,
                            .field_index = hit.index,
                        } },
                    });
                    node = next;
                }
                return node;
            }
        }
        return null;
    }

    fn propagateReachedDefault('''
text, count = pattern.subn(lambda _: replacement, text, count=1)
if count != 1:
    raise RuntimeError(f"core reached default block: {count}")

old = '    fn propagateReachedDefault(self: *Resolver, owner_local: ?module_entities.ModuleFunctionId, o: globalizer.Offsets, reached_field: global_sg.Field, default_node: global_sg.GlobalNodeId) !?global_sg.GlobalNodeId {\n        const owner_id = globalizer.globalFunction(o, owner_local orelse return null);\n'
new = '    fn propagateReachedDefault(self: *Resolver, owner_id: ?global_sg.GlobalFunctionId, reached_field: global_sg.Field, default_node: global_sg.GlobalNodeId) !?global_sg.GlobalNodeId {\n        const resolved_owner = owner_id orelse return null;\n'
text = replace_once(text, old, new, "core reach propagation signature")
text = replace_once(
    text,
    '        const owner = &self.graph.functions.items[@intFromEnum(owner_id)];\n',
    '        const owner = &self.graph.functions.items[@intFromEnum(resolved_owner)];\n',
    "core reach propagation owner",
)
text = replace_once(text, '    fn pointerType(self: *Resolver, child:', '    pub fn pointerType(self: *Resolver, child:', "core pointer interner visibility")
path.write_text(text)

# Generic functions: use the same reach context for inference and completion,
# including compiler-synthesized implicit calls.
path = Path("src/4_semantics/global/generic_functions.zig")
text = path.read_text()
text = replace_once(
    text,
    'const globalizer = @import("globalizer.zig");\n',
    'const globalizer = @import("globalizer.zig");\nconst reach_context_mod = @import("reach_context.zig");\n',
    "generic reach import",
)
old = '''const ReachInferenceContext = struct {
    module: *const module_sg.ModuleSemanticGraph,
    offsets: globalizer.Offsets,
    visible_bindings: module_entities.BindingRange,
};
'''
text = replace_once(text, old, 'const ReachInferenceContext = reach_context_mod.Context;\n', "generic reach context alias")
text = replace_once(
    text,
    '        const reach_context: ReachInferenceContext = .{ .module = module, .offsets = o, .visible_bindings = value.visible_bindings };\n',
    '        const reach: ReachInferenceContext = ReachInferenceContext.fromModule(module, o, value.visible_bindings, value.owner_function);\n',
    "generic source reach context",
)
text = replace_once(
    text,
    'self.resolveExplicitGenericFunction(module_index, module, reference, try self.generics.relocateModuleArguments(module_index, args), input, reach_context)',
    'self.resolveExplicitGenericFunction(module_index, module, reference, try self.generics.relocateModuleArguments(module_index, args), input, reach)',
    "generic explicit source inference context",
)
text = replace_once(
    text,
    'self.resolveImplicitGenericFunction(module_index, module, reference, input, reach_context)',
    'self.resolveImplicitGenericFunction(module_index, module, reference, input, reach)',
    "generic implicit source inference context",
)
text = replace_once(
    text,
    '        if (!try self.core.completeCallInputFieldsWithReach(self.graph.functions.items[@intFromEnum(function)].input, input, module, o, value.visible_bindings, value.owner_function)) return .deferred;\n',
    '        if (!try self.core.completeCallInputFieldsWithReach(self.graph.functions.items[@intFromEnum(function)].input, input, reach)) return .deferred;\n',
    "generic call completion reach",
)
old = '''            const reach = storage.reaches.items[@intFromEnum(reach_id)];
            const scope = context.module.semantic.binding_refs.items[context.visible_bindings.start..][0..context.visible_bindings.len];

            var inferred = false;
'''
new = '''            const reach = storage.reaches.items[@intFromEnum(reach_id)];

            var inferred = false;
'''
text = replace_once(text, old, new, "generic reach local scope removal")
text = replace_once(text, '                var scope_index = scope.len;\n', '                var scope_index = context.bindingCount();\n', "generic reach scope count")
text = replace_once(
    text,
    '                    const binding_id = globalizer.globalBinding(context.offsets, scope[scope_index]);\n',
    '                    const binding_id = context.bindingAt(scope_index);\n',
    "generic reach binding lookup",
)
old = '''    pub fn resolveImplicitGenericFunctionByName(
        self: *Resolver,
        current_module: usize,
        name: []const u8,
        input: global_sg.GlobalNodeId,
    ) !global_sg.GlobalFunctionId {
        return self.resolveImplicitGenericFunctionFiltered(current_module, name, null, input, null, null);
    }
'''
new = '''    pub fn resolveImplicitGenericFunctionByName(
        self: *Resolver,
        current_module: usize,
        name: []const u8,
        input: global_sg.GlobalNodeId,
        reach: ?ReachInferenceContext,
    ) !global_sg.GlobalFunctionId {
        return self.resolveImplicitGenericFunctionFiltered(current_module, name, null, input, reach, null);
    }
'''
text = replace_once(text, old, new, "generic synthesized call reach")
path.write_text(text)

# Control sugar has no lexical reach payload today; make that absence explicit.
path = Path("src/4_semantics/global/control.zig")
text = path.read_text()
text = replace_once(
    text,
    'generic_functions.resolveImplicitGenericFunctionByName(module_index, name, input)',
    'generic_functions.resolveImplicitGenericFunctionByName(module_index, name, input, null)',
    "control implicit generic call",
)
path.write_text(text)

# Constructors use the same source reach context as ordinary/generic calls.
path = Path("src/4_semantics/global/constructors.zig")
text = path.read_text()
text = replace_once(
    text,
    'const globalizer = @import("globalizer.zig");\n',
    'const globalizer = @import("globalizer.zig");\nconst reach_context = @import("reach_context.zig");\n',
    "constructor reach import",
)
old = 'self.core.completeCallInputFieldsWithReach(user_fields, input, module, o, value.visible_bindings, value.owner_function)'
new = 'self.core.completeCallInputFieldsWithReach(user_fields, input, reach_context.Context.fromModule(module, o, value.visible_bindings, value.owner_function))'
text = replace_count(text, old, new, 4, "constructor reach completion")
path.write_text(text)

# Abstract-compatible ordinary calls must complete defaults through the same
# reach algorithm as Core. Expose the unqualified matcher for synthetic calls.
path = Path("src/4_semantics/global/call_compatibility.zig")
text = path.read_text()
text = replace_once(
    text,
    'const globalizer = @import("globalizer.zig");\n',
    'const globalizer = @import("globalizer.zig");\nconst reach_context = @import("reach_context.zig");\n',
    "compat reach import",
)
text = replace_once(
    text,
    '    if (!try compatibility.core.completeCallInputFields(compatibility.core.graph.functions.items[@intFromEnum(function)].input, input)) return .deferred;\n',
    '    const reach = reach_context.Context.fromModule(module, o, value.visible_bindings, value.owner_function);\n'
    '    if (!try compatibility.core.completeCallInputFieldsWithReach(compatibility.core.graph.functions.items[@intFromEnum(function)].input, input, reach)) return .deferred;\n',
    "compat reach completion",
)
pattern = re.compile(r'fn matchFunctionByName\(.*?\n\}\n\npub fn matchInput\(', re.S)
replacement = r'''fn matchFunctionByName(
    compatibility: Abstract,
    current_module: usize,
    module: *const module_sg.ModuleSemanticGraph,
    reference: module_entities.ExternalRef,
    input_node: global_sg.GlobalNodeId,
) !core_mod.Resolver.FunctionMatch {
    const module_filter = if (reference.module_path) |path|
        try compatibility.core.findModuleForQualifier(current_module, module.text(path))
    else
        null;
    return matchFunctionNamed(
        compatibility,
        current_module,
        module.text(reference.name),
        module_filter,
        input_node,
    );
}

pub fn matchUnqualifiedFunctionByName(
    compatibility: Abstract,
    current_module: usize,
    name: []const u8,
    input_node: global_sg.GlobalNodeId,
) !core_mod.Resolver.FunctionMatch {
    return matchFunctionNamed(compatibility, current_module, name, null, input_node);
}

fn matchFunctionNamed(
    compatibility: Abstract,
    current_module: usize,
    name: []const u8,
    module_filter: ?global_sg.GlobalModuleId,
    input_node: global_sg.GlobalNodeId,
) !core_mod.Resolver.FunctionMatch {
    var best: ?global_sg.GlobalFunctionId = null;
    var best_score: u32 = 0;
    var tied = false;
    var saw_deferred = false;
    for (compatibility.core.graph.functions.items, 0..) |function, raw| {
        if (function.flags.is_abstract_dispatch) continue;
        const declaration = compatibility.core.graph.declarations.items[@intFromEnum(function.declaration)];
        if (!std.mem.eql(u8, compatibility.core.graph.text(declaration.name), name)) continue;
        if (!compatibility.core.declarationVisible(current_module, function.declaration, module_filter)) continue;
        const score = switch (matchInput(compatibility, function.input, input_node)) {
            .no_match => continue,
            .deferred => {
                saw_deferred = true;
                continue;
            },
            .score => |score| score,
        };
        if (best == null or score > best_score) {
            best = @enumFromInt(@as(u32, @intCast(raw)));
            best_score = score;
            tied = false;
        } else if (score == best_score) tied = true;
    }
    if (best) |function| {
        if (tied) return .ambiguous;
        return .{ .function = function };
    }
    if (saw_deferred) return .deferred;
    return .no_match;
}

pub fn matchInput('''
text, count = pattern.subn(lambda _: replacement, text, count=1)
if count != 1:
    raise RuntimeError(f"compat matcher refactor: {count}")
path.write_text(text)

# Dispatcher API for compiler-synthesized function calls. It follows the same
# strategy order as source function dispatch, without pretending a synthetic
# call came from ModuleSG.
path = Path("src/4_semantics/global/dispatch.zig")
text = path.read_text()
text = replace_once(
    text,
    'const module_entities = @import("../module/entities.zig");\n',
    'const module_entities = @import("../module/entities.zig");\nconst global_sg = @import("graph.zig");\nconst reach_context = @import("reach_context.zig");\n',
    "dispatch synthetic imports",
)
anchor = '''    pub fn resolveIndex(
'''
addition = r'''    pub const ImplicitFunctionCall = struct {
        function: global_sg.GlobalFunctionId,
        input: global_sg.GlobalNodeId,
    };

    pub fn resolveImplicitFunction(
        self: *Resolver,
        module_index: usize,
        name: []const u8,
        input: global_sg.GlobalNodeId,
        reach: reach_context.Context,
    ) !?ImplicitFunctionCall {
        const ordinary = try self.core.matchUnqualifiedFunctionByName(module_index, name, input);
        switch (ordinary) {
            .function => |function| {
                if (!try self.core.completeCallInputFieldsWithReach(
                    self.core.graph.functions.items[@intFromEnum(function)].input,
                    input,
                    reach,
                )) return error.DeferredImplicitFunction;
                return .{ .function = function, .input = input };
            },
            .deferred => return error.DeferredImplicitFunction,
            .ambiguous => return error.AmbiguousImplicitFunction,
            .no_match => {},
        }

        const compatibility = call_compatibility.Abstract{ .core = self.core, .abstracts = self.abstracts };
        const abstract_ordinary = try call_compatibility.matchUnqualifiedFunctionByName(
            compatibility,
            module_index,
            name,
            input,
        );
        switch (abstract_ordinary) {
            .function => |function| {
                if (!try self.core.completeCallInputFieldsWithReach(
                    self.core.graph.functions.items[@intFromEnum(function)].input,
                    input,
                    reach,
                )) return error.DeferredImplicitFunction;
                return .{ .function = function, .input = input };
            },
            .deferred => return error.DeferredImplicitFunction,
            .ambiguous => return error.AmbiguousImplicitFunction,
            .no_match => {},
        }

        const function = self.generic_functions.resolveImplicitGenericFunctionByName(
            module_index,
            name,
            input,
            reach,
        ) catch |err| switch (err) {
            error.NoMatchingGenericFunction, error.ConflictingGenericArgument => return null,
            error.DeferredGenericFunction => return error.DeferredImplicitFunction,
            error.AmbiguousGenericFunction => return error.AmbiguousImplicitFunction,
            else => return err,
        };
        if (!try self.core.completeCallInputFieldsWithReach(
            self.core.graph.functions.items[@intFromEnum(function)].input,
            input,
            reach,
        )) return error.DeferredImplicitFunction;
        return .{ .function = function, .input = input };
    }

''' + anchor
text = replace_once(text, anchor, addition, "dispatch implicit function API")
path.write_text(text)

# Ownership: auto-deinit is resolved in lexical context at the binding
# declaration. Cleanup later consumes a fully-resolved semantic call descriptor.
path = Path("src/4_semantics/global/ownership.zig")
text = path.read_text()
text = replace_once(
    text,
    'const core_mod = @import("core.zig");\n',
    'const core_mod = @import("core.zig");\nconst dispatch_mod = @import("dispatch.zig");\nconst reach_context = @import("reach_context.zig");\n',
    "ownership dispatch imports",
)
text = replace_once(
    text,
    'const AutoNode = struct { binding: global_sg.GlobalBindingId, node: global_sg.GlobalNodeId };\n',
    'const AutoNode = struct { binding: global_sg.GlobalBindingId, node: ?global_sg.GlobalNodeId };\n'
    'const ResolvedDestructor = struct {\n'
    '    function: global_sg.GlobalFunctionId,\n'
    '    input: global_sg.GlobalNodeId,\n'
    '    self_field_index: u32,\n'
    '};\n',
    "ownership auto cache shape",
)
text = replace_once(
    text,
    '    core: *core_mod.Resolver,\n',
    '    core: *core_mod.Resolver,\n    dispatch: ?*dispatch_mod.Resolver = null,\n',
    "ownership dispatch field",
)
text = replace_once(
    text,
    '        _ = try self.autoDeinitNode(binding);\n',
    '        _ = self.autoDeinitNode(binding);\n',
    "legacy deinit cache lookup",
)
old = '''    pub fn finalize(self: *Resolver) !void {
        for (self.graph.functions.items) |function| if (function.body) |body|
            try self.finalizeFunctionBody(body);
    }

    pub fn finalizeFunctionBody(self: *Resolver, body: global_sg.GlobalBlockId) !void {
        var active: std.ArrayList(global_sg.GlobalBindingId) = .empty;
        defer active.deinit(self.allocator);
        var defers: std.ArrayList(global_sg.GlobalNodeId) = .empty;
        defer defers.deinit(self.allocator);
        try self.finalizeBlock(body, &active, &defers);
    }
'''
new = '''    pub fn finalize(self: *Resolver) !void {
        for (self.graph.functions.items, 0..) |function, raw| {
            if (function.body == null) continue;
            const id: global_sg.GlobalFunctionId = @enumFromInt(@as(u32, @intCast(raw)));
            try self.finalizeFunctionBody(id);
        }
    }

    pub fn finalizeFunctionBody(self: *Resolver, function_id: global_sg.GlobalFunctionId) !void {
        const function = self.graph.functions.items[@intFromEnum(function_id)];
        const body = function.body orelse return;
        var visible: std.ArrayList(global_sg.GlobalBindingId) = .empty;
        defer visible.deinit(self.allocator);
        try visible.appendSlice(
            self.allocator,
            self.graph.binding_refs.items[function.input_bindings.start..][0..function.input_bindings.len],
        );
        try visible.appendSlice(
            self.allocator,
            self.graph.binding_refs.items[function.output_bindings.start..][0..function.output_bindings.len],
        );

        var active: std.ArrayList(global_sg.GlobalBindingId) = .empty;
        defer active.deinit(self.allocator);
        var defers: std.ArrayList(global_sg.GlobalNodeId) = .empty;
        defer defers.deinit(self.allocator);
        const module = self.graph.moduleForDeclaration(function.declaration) orelse return error.MissingFunctionModule;
        try self.finalizeBlock(body, &active, &defers, &visible, function_id, @intCast(@intFromEnum(module)));
    }
'''
text = replace_once(text, old, new, "ownership function finalization context")

old_sig = '''    fn finalizeBlock(
        self: *Resolver,
        block_id: global_sg.GlobalBlockId,
        inherited_active: *std.ArrayList(global_sg.GlobalBindingId),
        inherited_defers: *std.ArrayList(global_sg.GlobalNodeId),
    ) anyerror!void {
'''
new_sig = '''    fn finalizeBlock(
        self: *Resolver,
        block_id: global_sg.GlobalBlockId,
        inherited_active: *std.ArrayList(global_sg.GlobalBindingId),
        inherited_defers: *std.ArrayList(global_sg.GlobalNodeId),
        inherited_visible: *std.ArrayList(global_sg.GlobalBindingId),
        owner_function: global_sg.GlobalFunctionId,
        module_index: usize,
    ) anyerror!void {
'''
text = replace_once(text, old_sig, new_sig, "ownership block context signature")
text = replace_once(
    text,
    '        const defer_base = defers.items.len;\n\n        var rebuilt:',
    '        const defer_base = defers.items.len;\n'
    '        var visible: std.ArrayList(global_sg.GlobalBindingId) = .empty;\n'
    '        defer visible.deinit(self.allocator);\n'
    '        try visible.appendSlice(self.allocator, inherited_visible.items);\n\n'
    '        var rebuilt:',
    "ownership visible scope",
)
old_switch = '''            switch (node.content) {
                .binding_declaration => |binding| try active.append(self.allocator, binding),
                .return_statement => |*ret| ret.cleanup = try self.appendCleanup(active.items, defers.items),
                .code_block => |child| try self.finalizeBlock(child, &active, &defers),
                .if_statement => |statement| {
                    try self.finalizeBlock(statement.then_block, &active, &defers);
                    if (statement.else_block) |child| try self.finalizeBlock(child, &active, &defers);
                },
                .while_statement => |statement| try self.finalizeBlock(statement.body, &active, &defers),
                .for_statement => |statement| try self.finalizeBlock(statement.body, &active, &defers),
                .switch_statement => |switch_id| {
                    const sw = self.graph.switches.items[@intFromEnum(switch_id)];
                    for (self.graph.switch_cases.items[sw.cases.start..][0..sw.cases.len]) |case|
                        try self.finalizeBlock(case.body, &active, &defers);
                    if (sw.default_block) |child| try self.finalizeBlock(child, &active, &defers);
                },
                else => {},
            }
'''
new_switch = '''            switch (node.content) {
                .binding_declaration => |binding| {
                    try visible.append(self.allocator, binding);
                    try self.prepareAutoDeinit(
                        binding,
                        reach_context.Context.fromGlobal(visible.items, owner_function),
                        module_index,
                    );
                    try active.append(self.allocator, binding);
                },
                .return_statement => |*ret| ret.cleanup = try self.appendCleanup(active.items, defers.items),
                .code_block => |child| try self.finalizeBlock(child, &active, &defers, &visible, owner_function, module_index),
                .if_statement => |statement| {
                    try self.finalizeBlock(statement.then_block, &active, &defers, &visible, owner_function, module_index);
                    if (statement.else_block) |child|
                        try self.finalizeBlock(child, &active, &defers, &visible, owner_function, module_index);
                },
                .while_statement => |statement| try self.finalizeBlock(statement.body, &active, &defers, &visible, owner_function, module_index),
                .for_statement => |statement| try self.finalizeBlock(statement.body, &active, &defers, &visible, owner_function, module_index),
                .switch_statement => |switch_id| {
                    const sw = self.graph.switches.items[@intFromEnum(switch_id)];
                    for (self.graph.switch_cases.items[sw.cases.start..][0..sw.cases.len]) |case|
                        try self.finalizeBlock(case.body, &active, &defers, &visible, owner_function, module_index);
                    if (sw.default_block) |child|
                        try self.finalizeBlock(child, &active, &defers, &visible, owner_function, module_index);
                },
                else => {},
            }
'''
text = replace_once(text, old_switch, new_switch, "ownership lexical block traversal")
text = replace_count(text, 'if (try self.autoDeinitNode(', 'if (self.autoDeinitNode(', 2, "ownership cached cleanup lookup")

pattern = re.compile(r'    fn autoDeinitNode\(.*?\n    fn findUnaryFunction\(', re.S)
replacement = r'''    fn autoDeinitNode(self: *const Resolver, binding: global_sg.GlobalBindingId) ?global_sg.GlobalNodeId {
        for (self.auto_nodes.items) |entry| if (entry.binding == binding) return entry.node;
        return null;
    }

    fn prepareAutoDeinit(
        self: *Resolver,
        binding: global_sg.GlobalBindingId,
        context: reach_context.Context,
        module_index: usize,
    ) !void {
        for (self.auto_nodes.items) |entry| if (entry.binding == binding) return;
        if (self.graph.isBindingTypeUnresolved(binding)) return error.UnresolvedAutoDeinitBinding;
        const record = self.graph.bindings.items[@intFromEnum(binding)];
        const target = try self.appendNode(record.source, record.ty, .{ .binding_use = binding });
        const descriptor = try self.buildAutoDeinit(binding, target, record.ty, context, module_index);
        var cleanup_node: ?global_sg.GlobalNodeId = null;
        if (descriptor) |resolved| {
            const auto_id: global_sg.GlobalAutoDeinitId = @enumFromInt(@as(u32, @intCast(self.graph.auto_deinits.items.len)));
            try self.graph.auto_deinits.append(self.allocator, resolved);
            cleanup_node = try self.appendNode(record.source, try self.builtin(.Void), .{ .auto_deinit_binding = auto_id });
            self.stats.auto_deinits += 1;
        }
        try self.auto_nodes.append(self.allocator, .{ .binding = binding, .node = cleanup_node });
    }

    fn buildAutoDeinit(
        self: *Resolver,
        binding: global_sg.GlobalBindingId,
        target: global_sg.GlobalNodeId,
        ty: global_sg.GlobalTypeId,
        context: reach_context.Context,
        module_index: usize,
    ) !?global_sg.AutoDeinit {
        // References never own their pointee.
        if (self.graph.semanticType(ty) == .pointer) return null;
        if (try self.resolveDestructor(target, context, module_index)) |resolved| {
            return .{
                .binding = binding,
                .deinit_fn = resolved.function,
                .input = resolved.input,
                .self_field_index = resolved.self_field_index,
            };
        }

        const fields = global_types.fields(self.graph, ty) orelse return null;
        const start: u32 = @intCast(self.graph.auto_deinit_fields.items.len);
        var count: u32 = 0;
        for (0..fields.len) |index| {
            const field = self.graph.fields.items[fields.start + @as(u32, @intCast(index))];
            const projected = try self.appendNode(
                self.graph.nodes.items[@intFromEnum(target)].source,
                field.ty,
                .{ .struct_field_access = .{
                    .value = target,
                    .field_name = field.name,
                    .field_index = @intCast(index),
                } },
            );
            if (try self.appendAutoField(@intCast(index), projected, field.ty, context, module_index)) count += 1;
        }
        if (count == 0) return null;
        return .{
            .binding = binding,
            .deinit_fn = null,
            .fields = .{ .start = start, .len = count },
        };
    }

    fn appendAutoField(
        self: *Resolver,
        field_index: u32,
        target: global_sg.GlobalNodeId,
        ty: global_sg.GlobalTypeId,
        context: reach_context.Context,
        module_index: usize,
    ) !bool {
        if (self.graph.semanticType(ty) == .pointer) return false;
        if (try self.resolveDestructor(target, context, module_index)) |resolved| {
            try self.graph.auto_deinit_fields.append(self.allocator, .{
                .field_index = field_index,
                .deinit_fn = resolved.function,
                .input = resolved.input,
                .self_field_index = resolved.self_field_index,
            });
            return true;
        }

        const fields = global_types.fields(self.graph, ty) orelse return false;
        const child_start: u32 = @intCast(self.graph.auto_deinit_fields.items.len);
        var child_count: u32 = 0;
        for (0..fields.len) |index| {
            const field = self.graph.fields.items[fields.start + @as(u32, @intCast(index))];
            const projected = try self.appendNode(
                self.graph.nodes.items[@intFromEnum(target)].source,
                field.ty,
                .{ .struct_field_access = .{
                    .value = target,
                    .field_name = field.name,
                    .field_index = @intCast(index),
                } },
            );
            if (try self.appendAutoField(@intCast(index), projected, field.ty, context, module_index)) child_count += 1;
        }
        if (child_count == 0) return false;
        try self.graph.auto_deinit_fields.append(self.allocator, .{
            .field_index = field_index,
            .deinit_fn = null,
            .fields = .{ .start = child_start, .len = child_count },
        });
        return true;
    }

    fn resolveDestructor(
        self: *Resolver,
        target: global_sg.GlobalNodeId,
        context: reach_context.Context,
        module_index: usize,
    ) !?ResolvedDestructor {
        const target_ty = self.graph.nodes.items[@intFromEnum(target)].ty orelse return null;
        const dispatch = self.dispatch orelse return error.MissingOwnershipDispatch;
        const pointer_ty = try self.core.pointerType(target_ty, .read_write);
        const source = self.graph.nodes.items[@intFromEnum(target)].source;
        const address = try self.appendNode(source, pointer_ty, .{ .address_of = target });

        var receiver_names = std.StringHashMap(void).init(self.allocator);
        defer receiver_names.deinit();
        try self.collectDestructorReceiverNames(module_index, &receiver_names);

        var selected: ?ResolvedDestructor = null;
        var names = receiver_names.keyIterator();
        while (names.next()) |name_ptr| {
            const input = try self.singleNamedInput(name_ptr.*, address, source);
            const call = dispatch.resolveImplicitFunction(
                module_index,
                "deinit",
                input,
                context,
            ) catch |err| switch (err) {
                error.DeferredImplicitFunction => continue,
                error.AmbiguousImplicitFunction => return err,
                else => return err,
            } orelse continue;
            const self_index = self.findReceiverIndex(call.function, call.input, target) orelse continue;
            const candidate = ResolvedDestructor{
                .function = call.function,
                .input = call.input,
                .self_field_index = self_index,
            };
            if (selected) |previous| {
                if (previous.function != candidate.function or previous.self_field_index != candidate.self_field_index)
                    return error.AmbiguousImplicitDestructor;
            } else {
                selected = candidate;
            }
        }
        return selected;
    }

    fn collectDestructorReceiverNames(
        self: *Resolver,
        module_index: usize,
        names: *std.StringHashMap(void),
    ) !void {
        for (self.graph.functions.items) |function| {
            if (!function.flags.is_deinit) continue;
            if (!self.core.declarationVisible(module_index, function.declaration, null)) continue;
            for (self.graph.fields.items[function.input.start..][0..function.input.len]) |field| {
                const pointer = switch (self.graph.semanticType(field.ty)) {
                    .pointer => |value| value,
                    else => continue,
                };
                if (pointer.mutability != .read_write) continue;
                try names.put(self.graph.text(field.name), {});
            }
        }

        for (self.modules, 0..) |*candidate_module, candidate_index| {
            const storage = &candidate_module.semantic.parameterized_storage;
            for (storage.parameterized_functions.items) |function| {
                if (!function.is_deinit) continue;
                const declaration = globalizer.globalDecl(self.offsets[candidate_index], function.declaration);
                if (!self.core.declarationVisible(module_index, declaration, null)) continue;
                const shape = switch (storage.ir.types.items[@intFromEnum(function.input)]) {
                    .resolved => |ty| switch (ty) {
                        .structural => |value| value,
                        else => continue,
                    },
                    else => continue,
                };
                for (storage.ir.fields.items[shape.fields.start..][0..shape.fields.len]) |field| {
                    const pointer = switch (storage.ir.types.items[@intFromEnum(field.ty)]) {
                        .resolved => |ty| switch (ty) {
                            .pointer => |value| value,
                            else => continue,
                        },
                        else => continue,
                    };
                    if (pointer.mutability != .read_write) continue;
                    try names.put(candidate_module.text(field.name), {});
                }
            }
        }
    }

    fn singleNamedInput(
        self: *Resolver,
        name: []const u8,
        value: global_sg.GlobalNodeId,
        source: primitives.SourceRef,
    ) !global_sg.GlobalNodeId {
        const field_start: u32 = @intCast(self.graph.value_fields.items.len);
        try self.graph.value_fields.append(self.allocator, .{
            .name = try self.graph.addString(self.allocator, name),
            .value = value,
        });
        return self.appendNode(source, null, .{ .struct_value_literal = .{
            .fields = .{ .start = field_start, .len = 1 },
        } });
    }

    fn findReceiverIndex(
        self: *const Resolver,
        function_id: global_sg.GlobalFunctionId,
        input: global_sg.GlobalNodeId,
        target: global_sg.GlobalNodeId,
    ) ?u32 {
        const function = self.graph.functions.items[@intFromEnum(function_id)];
        const literal = switch (self.graph.nodes.items[@intFromEnum(input)].content) {
            .struct_value_literal => |value| value,
            else => return null,
        };
        if (literal.fields.len != function.input.len) return null;
        for (self.graph.value_fields.items[literal.fields.start..][0..literal.fields.len], 0..) |field, index| {
            const node = self.graph.nodes.items[@intFromEnum(field.value)];
            if (node.content != .address_of or node.content.address_of != target) continue;
            return @intCast(index);
        }
        return null;
    }

    fn appendNode(
        self: *Resolver,
        source: primitives.SourceRef,
        ty: ?global_sg.GlobalTypeId,
        content: global_sg.Node.Content,
    ) !global_sg.GlobalNodeId {
        const id: global_sg.GlobalNodeId = @enumFromInt(@as(u32, @intCast(self.graph.nodes.items.len)));
        try self.graph.nodes.append(self.allocator, .{ .source = source, .ty = ty, .content = content });
        return id;
    }

    fn findUnaryFunction('''
text, count = pattern.subn(lambda _: replacement, text, count=1)
if count != 1:
    raise RuntimeError(f"ownership auto-deinit replacement: {count}")
path.write_text(text)

# Semantizer wires Dispatch before Ownership and finalizes by function identity,
# because lexical/module context belongs to the owning function.
path = Path("src/4_semantics/global/semantizer.zig")
text = path.read_text()
old = '''    var ownership = ownership_mod.Resolver{
        .allocator = allocator,
        .graph = &relocation.graph,
        .modules = modules,
        .offsets = relocation.offsets.items,
        .core = &core,
    };
    defer ownership.deinit();
    var dispatch = dispatch_mod.Resolver{
        .core = &core,
        .generic_functions = &generic_functions,
        .constructors = &constructors,
        .abstracts = &abstracts,
        .control = &control,
        .errors = &errors,
    };
'''
new = '''    var dispatch = dispatch_mod.Resolver{
        .core = &core,
        .generic_functions = &generic_functions,
        .constructors = &constructors,
        .abstracts = &abstracts,
        .control = &control,
        .errors = &errors,
    };
    var ownership = ownership_mod.Resolver{
        .allocator = allocator,
        .graph = &relocation.graph,
        .modules = modules,
        .offsets = relocation.offsets.items,
        .core = &core,
        .dispatch = &dispatch,
    };
    defer ownership.deinit();
'''
text = replace_once(text, old, new, "semantizer dispatch ownership wiring")
text = replace_once(
    text,
    '                try ownership.finalizeFunctionBody(body);\n',
    '                _ = body;\n                try ownership.finalizeFunctionBody(id);\n',
    "semantizer ownership finalize identity",
)
path.write_text(text)

# The old tracing/post-edit patch has already landed in source. All current
# source edits are owned by this script.
Path(".github/semantic_refactor_post_edit.py").write_text("")

for p in (
    reach,
    Path("src/4_semantics/global/core.zig"),
    Path("src/4_semantics/global/generic_functions.zig"),
    Path("src/4_semantics/global/control.zig"),
    Path("src/4_semantics/global/constructors.zig"),
    Path("src/4_semantics/global/call_compatibility.zig"),
    Path("src/4_semantics/global/dispatch.zig"),
    Path("src/4_semantics/global/ownership.zig"),
    Path("src/4_semantics/global/semantizer.zig"),
):
    subprocess.run(["zig", "fmt", str(p)], check=True)

Path(".git/semantic-refactor-test-command").write_text(
    "zig build test-programs -Dtest-filter=feature_tests/ownership/03_deinit && "
    "zig build test-programs -Dtest-filter=feature_tests/ownership/16_keep_cancels_auto_deinit && "
    "zig build test-programs -Dtest-filter=feature_tests/collections/23_dynamic_array_owning_push_fixed && "
    "zig build test-programs -Dtest-filter=feature_tests/collections/24_dynamic_array_owning_insert_fixed && "
    "zig build test-programs -Dtest-filter=feature_tests/collections/26_dynamic_array_owning_pop && "
    "zig build test-programs -Dtest-filter=feature_tests/collections/30_dynamic_array_custom_allocator && "
    "zig build test-programs -Dtest-filter=feature_tests/collections/31_dynamic_array_owning_pop_auto_deinit\n"
)
Path(".git/semantic-refactor-message").write_text(
    "Resolve auto-deinit through lexical call dispatch\n"
)
