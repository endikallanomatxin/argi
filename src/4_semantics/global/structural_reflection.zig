const std = @import("std");
const graph_mod = @import("graph.zig");
const functions = @import("generic_functions.zig");
const entities = @import("../module/entities.zig");
const primitives = @import("../primitives/schema.zig");
const types = @import("types.zig");
const Context = @import("call_context.zig").Context;

/// Expand structural callbacks into ordinary checked calls. Context storage is
/// evaluated once before any callback, and choice payloads execute only in the
/// selected branch. These operations never grant private-field access.
pub fn resolve(r: *functions.Resolver, module: usize, reference: entities.ExternalRef, arguments: primitives.Range(graph_mod.GlobalGenericArgId), input: graph_mod.GlobalNodeId, context: Context, source: primitives.SourceRef, name: []const u8) !graph_mod.Node {
    const args = r.graph.generic_arguments.items[arguments.start..][0..arguments.len];
    const collect = std.mem.eql(u8, name, "collect_fields") or std.mem.eql(u8, name, "collect_variants");
    const choice_builder = std.mem.eql(u8, name, "construct_choice");
    if (args.len < 2 or args.len > 3 or (choice_builder and args.len != 3) or (!collect and !choice_builder and args.len != 2) or args[0].value != .type or args[1].value != .definition)
        return fail(r, source, "structural reflection expects a type and a callback function");
    for (args, 0..) |argument, index| {
        const actual = r.graph.text(argument.name);
        const expected = if (index == 0) "T" else if (index == 1) "F" else if (choice_builder) "Select" else "Result";
        if (actual.len != 0 and !std.mem.eql(u8, actual, expected))
            return fail(r, source, "unknown structural reflection argument; use T, F, Result or Select");
    }
    const target = args[0].value.type;
    const callback = args[1].value.definition;
    const select = if (choice_builder) if (args[2].value == .definition) args[2].value.definition else return fail(r, source, "choice construction requires a selector function") else null;
    var collected_type: ?graph_mod.GlobalTypeId = if (collect and args.len == 3) if (args[2].value == .type) args[2].value.type else return fail(r, source, "collection result must be a type") else null;
    _ = try r.generics.ensureGenericInstance(target);
    const literal = r.graph.node(input).content;
    if (literal != .struct_value_literal or literal.struct_value_literal.fields.len != 1)
        return fail(r, source, "structural reflection requires one '.context' input");
    const supplied = r.core.recordFieldValue(literal.struct_value_literal, 0, "context") orelse return fail(r, source, "structural reflection requires '.context'");
    const context_ty = r.graph.node(supplied).ty orelse return error.DeferredGenericFunction;
    const ownership: *@import("ownership.zig").Resolver = @ptrCast(@alignCast(r.ownership_context orelse return error.DeferredGenericFunction));
    if (!try ownership.canImplicitlyCopy(context_ty))
        return fail(r, source, "structural reflection context must be implicitly copyable; pass a reference to an owner");
    var lexical_context = context;
    if (literal.struct_value_literal.assumed_fields.len != 0) lexical_context.assumed_fields = literal.struct_value_literal.assumed_fields;
    var b = Builder{ .r = r, .module = module, .reference = reference, .context = lexical_context, .source = source };
    var statements: std.ArrayList(graph_mod.GlobalNodeId) = .empty;
    defer statements.deinit(r.allocator);
    const stored = try b.binding(context_ty, supplied);
    try statements.appendSlice(r.allocator, &.{ stored.declaration, stored.assignment.? });
    const is_choice = std.mem.eql(u8, name, "visit_variants") or std.mem.eql(u8, name, "collect_variants") or select != null;
    const construct = std.mem.eql(u8, name, "construct_record") or select != null;
    const void_ty = try r.core.builtin(.Void);
    var result: ?graph_mod.GlobalNodeId = null;
    if (is_choice) {
        const range = types.variants(r.graph, target) orelse return fail(r, source, "variant reflection requires a choice type");
        const variants = try r.allocator.dupe(@TypeOf(r.graph.variants.items[0]), r.graph.variants.items[range.start..][0..range.len]);
        defer r.allocator.free(variants);
        for (variants) |variant| if (std.mem.startsWith(u8, r.graph.text(variant.name), "_"))
            return fail(r, source, "structural reflection cannot access private alternatives");
        if (select) |predicate| {
            const output = try b.binding(target, null);
            try statements.append(r.allocator, output.declaration);
            const abort_node = try b.node(void_ty, .abort_statement);
            var next_block = try b.block(&.{abort_node}, null);
            var reverse: usize = variants.len;
            while (reverse != 0) {
                reverse -= 1;
                const variant = variants[reverse];
                const payload_ty = variant.payload_type orelse void_ty;
                const condition = try b.call(predicate, payload_ty, variant.name, stored.use);
                if (!types.isBuiltin(r.graph, r.graph.node(condition).ty orelse return error.DeferredGenericFunction, .Bool))
                    return fail(r, source, "choice selector must return Bool");
                const payload = try b.call(callback, payload_ty, variant.name, stored.use);
                if (!types.equal(r.graph, r.graph.node(payload).ty orelse return error.DeferredGenericFunction, payload_ty))
                    return fail(r, source, "choice builder must return the selected payload type");
                const choice = try b.node(target, .{ .choice_literal = .{ .choice_type = target, .variant = @enumFromInt(range.start + reverse), .payload = if (variant.payload_type != null) payload else null } });
                const assignment = try b.node(target, .{ .assignment = .{ .binding = output.id, .value = choice } });
                const branch = try b.block(if (variant.payload_type == null) &.{ payload, assignment } else &.{assignment}, null);
                const conditional = try b.node(void_ty, .{ .if_statement = .{ .condition = condition, .then_block = branch, .else_block = next_block } });
                next_block = try b.block(&.{conditional}, null);
            }
            try statements.append(r.allocator, try b.node(void_ty, .{ .code_block = next_block }));
            result = try b.node(target, .{ .move_value = output.use });
        } else if (collect) {
            var nodes: std.ArrayList(graph_mod.GlobalNodeId) = .empty;
            defer nodes.deinit(r.allocator);
            for (variants) |variant| {
                const call = try b.call(callback, variant.payload_type orelse void_ty, variant.name, stored.use);
                const actual = r.graph.node(call).ty orelse return error.DeferredGenericFunction;
                if (collected_type) |previous| {
                    if (!types.equal(r.graph, previous, actual)) return fail(r, source, "collected variants must return one common type");
                } else collected_type = actual;
                try nodes.append(r.allocator, call);
            }
            const item_type = collected_type orelse return fail(r, source, "collect_variants requires a nonempty choice");
            const array_type = try r.generics.internType(.{ .array = .{ .element = item_type, .length = nodes.items.len } });
            const start: u32 = @intCast(r.graph.node_refs.items.len);
            try r.graph.node_refs.appendSlice(r.allocator, nodes.items);
            result = try b.node(array_type, .{ .array_literal = .{ .element_type = item_type, .length = @intCast(nodes.items.len), .elements = .{ .start = start, .len = @intCast(nodes.items.len) } } });
        } else for (variants) |variant| {
            const call = try b.call(callback, variant.payload_type orelse void_ty, variant.name, stored.use);
            if (!types.isBuiltin(r.graph, r.graph.node(call).ty orelse return error.DeferredGenericFunction, .Void))
                return fail(r, source, "structural visitor must return Void");
            try statements.append(r.allocator, call);
        }
    } else {
        if (types.isCUnion(r.graph, types.representationType(r.graph, target) orelse return error.DeferredGenericFunction)) return fail(r, source, "field reflection does not support overlapping CUnion storage");
        const range = types.fields(r.graph, target) orelse return fail(r, source, "field reflection requires a record type");
        const fields = try r.allocator.dupe(graph_mod.Field, r.graph.fields.items[range.start..][0..range.len]);
        defer r.allocator.free(fields);
        var values: std.ArrayList(graph_mod.ValueField) = .empty;
        defer values.deinit(r.allocator);
        for (fields) |field| {
            if (std.mem.startsWith(u8, r.graph.text(field.name), "_"))
                return fail(r, source, "structural reflection cannot access private fields");
            const call = try b.call(callback, field.ty, field.name, stored.use);
            const actual = r.graph.node(call).ty orelse return error.DeferredGenericFunction;
            if (collect) {
                if (collected_type) |previous| {
                    if (!types.equal(r.graph, previous, actual)) return fail(r, source, "collected fields must return one common type");
                } else collected_type = actual;
                try values.append(r.allocator, .{ .name = field.name, .value = call });
            } else if (construct) {
                if (!types.equal(r.graph, actual, field.ty)) return fail(r, source, "record builder must return the declared field type");
                try values.append(r.allocator, .{ .name = field.name, .value = call });
            } else {
                if (!types.isBuiltin(r.graph, actual, .Void)) return fail(r, source, "structural visitor must return Void");
                try statements.append(r.allocator, call);
            }
        }
        if (collect) {
            const item_type = collected_type orelse return fail(r, source, "collect_fields currently requires a nonempty record");
            const array_type = try r.generics.internType(.{ .array = .{ .element = item_type, .length = values.items.len } });
            const start: u32 = @intCast(r.graph.node_refs.items.len);
            for (values.items) |value| try r.graph.node_refs.append(r.allocator, value.value);
            result = try b.node(array_type, .{ .array_literal = .{ .element_type = item_type, .length = @intCast(values.items.len), .elements = .{ .start = start, .len = @intCast(values.items.len) } } });
        } else if (construct) {
            const start: u32 = @intCast(r.graph.value_fields.items.len);
            try r.graph.value_fields.appendSlice(r.allocator, values.items);
            result = try b.node(target, .{ .struct_value_literal = .{ .fields = .{ .start = start, .len = @intCast(values.items.len) } } });
        }
    }
    const block = try b.block(statements.items, result);
    return .{ .source = source, .ty = if (collect) r.graph.node(result.?).ty else if (construct) target else void_ty, .content = .{ .value_sequence = block } };
}

fn fail(r: *functions.Resolver, source: primitives.SourceRef, message: []const u8) error{InvalidGenericCallArguments} {
    r.generics.comptime_failure = .{ .source = source, .reason = message };
    return error.InvalidGenericCallArguments;
}

const Builder = struct {
    r: *functions.Resolver,
    module: usize,
    reference: entities.ExternalRef,
    context: Context,
    source: primitives.SourceRef,

    fn node(b: Builder, ty: graph_mod.GlobalTypeId, content: graph_mod.Node.Content) !graph_mod.GlobalNodeId {
        return b.r.core.appendNode(b.source, ty, content);
    }
    fn block(b: Builder, nodes: []const graph_mod.GlobalNodeId, result: ?graph_mod.GlobalNodeId) !graph_mod.GlobalBlockId {
        const start: u32 = @intCast(b.r.graph.node_refs.items.len);
        try b.r.graph.node_refs.appendSlice(b.r.allocator, nodes);
        if (result) |value| try b.r.graph.node_refs.append(b.r.allocator, value);
        const id: graph_mod.GlobalBlockId = @enumFromInt(b.r.graph.blocks.items.len);
        try b.r.graph.blocks.append(b.r.allocator, .{ .nodes = .{ .start = start, .len = @intCast(nodes.len + @as(usize, if (result != null) 1 else 0)) }, .ret_val = result });
        return id;
    }
    const Storage = struct { id: graph_mod.GlobalBindingId, declaration: graph_mod.GlobalNodeId, assignment: ?graph_mod.GlobalNodeId, use: graph_mod.GlobalNodeId };
    fn binding(b: Builder, ty: graph_mod.GlobalTypeId, value: ?graph_mod.GlobalNodeId) !Storage {
        const id: graph_mod.GlobalBindingId = @enumFromInt(b.r.graph.bindings.items.len);
        try b.r.graph.bindings.append(b.r.allocator, .{ .name = try b.r.graph.addString(b.r.allocator, "#reflection"), .ty = ty, .source = b.source, .mutability = .variable, .initialization = value, .deferred_initialization = value != null });
        return .{ .id = id, .declaration = try b.node(try b.r.core.builtin(.Void), .{ .binding_declaration = id }), .assignment = if (value) |v| try b.node(ty, .{ .assignment = .{ .binding = id, .value = v } }) else null, .use = try b.node(ty, .{ .binding_use = id }) };
    }
    fn call(b: Builder, callback: graph_mod.DefinitionValue, member: graph_mod.GlobalTypeId, name: primitives.StringRange, ctx: graph_mod.GlobalNodeId) !graph_mod.GlobalNodeId {
        const r = b.r;
        const text = try b.node(r.core.defaultStringLiteralType() orelse return error.DeferredGenericFunction, .{ .string_literal = name });
        const start: u32 = @intCast(r.graph.value_fields.items.len);
        try r.graph.value_fields.appendSlice(r.allocator, &.{ .{ .name = try r.graph.addString(r.allocator, "name"), .value = text }, .{ .name = try r.graph.addString(r.allocator, "context"), .value = ctx } });
        const input = try b.node(try r.core.structType(.{ .start = 0, .len = 0 }), .{ .struct_value_literal = .{ .fields = .{ .start = start, .len = 2 }, .assumed_fields = b.context.assumed_fields } });
        // Call inputs receive their signature from ordinary checked resolution.
        var untyped_input = r.graph.node(input);
        untyped_input.ty = null;
        try r.graph.setNode(r.allocator, input, untyped_input);
        const arg_start: u32 = @intCast(r.graph.generic_arguments.items.len);
        try r.graph.generic_arguments.append(r.allocator, .{ .name = .{ .start = 0, .len = 0 }, .value = .{ .type = member } });
        const call_node = try r.makeDefinitionCall(b.module, b.reference, callback, .{ .start = arg_start, .len = 1 }, input, b.context, b.source);
        return b.node(call_node.ty orelse return error.DeferredGenericFunction, call_node.content);
    }
};
