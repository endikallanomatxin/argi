const std = @import("std");
const module_sg = @import("../module/graph.zig");
const module_entities = @import("../module/entities.zig");
const global_sg = @import("graph.zig");
const globalizer = @import("globalizer.zig");
const reach_context = @import("reach_context.zig");
const resolution = @import("resolution.zig");
const types = @import("types.zig");
const core_mod = @import("core.zig");
const abstract_mod = @import("abstracts.zig");
const primitives = @import("../primitives/schema.zig");

/// Additional call compatibility owned above Core. Core handles structural
/// compatibility; this policy adds the language-level concrete-to-abstract
/// relation without making Core depend on the abstract resolver.
pub const Abstract = struct {
    core: *core_mod.Resolver,
    abstracts: *abstract_mod.Resolver,

    pub fn compatible(self: @This(), actual: global_sg.GlobalTypeId, expected: global_sg.GlobalTypeId) bool {
        const actual_pointer = switch (self.core.graph.types.items[@intFromEnum(actual)]) {
            .pointer => |pointer| pointer,
            else => return false,
        };
        const expected_pointer = switch (self.core.graph.types.items[@intFromEnum(expected)]) {
            .pointer => |pointer| pointer,
            else => return false,
        };
        if (expected_pointer.mutability == .read_write and actual_pointer.mutability != .read_write) return false;
        return self.abstracts.concreteImplements(actual_pointer.child, expected_pointer.child);
    }

    fn compatibleTypes(self: @This(), actual: global_sg.GlobalTypeId, expected: global_sg.GlobalTypeId) bool {
        if (self.compatible(actual, expected)) return true;
        return self.abstracts.concreteImplements(actual, expected);
    }

    fn compatibilityCallback(
        context: *const anyopaque,
        actual: global_sg.GlobalTypeId,
        expected: global_sg.GlobalTypeId,
    ) bool {
        const self: *const Abstract = @ptrCast(@alignCast(context));
        return self.compatibleTypes(actual, expected);
    }

    pub fn additionalTypeCompatibility(self: *const @This()) core_mod.Resolver.AdditionalTypeCompatibility {
        return .{
            .context = self,
            .compatible = compatibilityCallback,
        };
    }
};

/// Retry an ordinary non-generic call only for compatibility that Core does
/// not own. This strategy is intentionally placed after Core's structural
/// matcher and before generic/constructor/virtual strategies by dispatch.zig.
pub fn tryResolveOrdinaryCall(
    compatibility: Abstract,
    module_index: usize,
    module: *const module_sg.ModuleSemanticGraph,
    o: globalizer.Offsets,
    operation: module_entities.PendingOperation,
) !resolution.Result {
    const value = switch (operation) {
        .resolve_call => |value| value,
        else => return .not_applicable,
    };
    const reference = module.semantic.external_refs.items[@intFromEnum(value.callee)];
    if (reference.generic_arguments != null) return .not_applicable;
    const input = globalizer.globalNode(o, value.input);
    const reach = reach_context.Context.fromModule(module, o, value.visible_bindings, value.owner_function);
    const function = switch (try matchFunctionByName(
        compatibility,
        module_index,
        module,
        reference,
        input,
        reach,
    )) {
        .no_match => return .not_applicable,
        .deferred => return .deferred,
        .ambiguous => return .invalid,
        .function => |function| function,
    };
    if (!try compatibility.core.completeCallInputFieldsWithReachCompatibility(
        compatibility.core.graph.functions.items[@intFromEnum(function)].input,
        input,
        reach,
        compatibility.additionalTypeCompatibility(),
    )) return .deferred;
    const output = try compatibility.core.functionOutputType(function);
    const target = globalizer.globalNode(o, value.node);
    compatibility.core.graph.nodes.items[@intFromEnum(target)] = .{
        .source = .{ .file_index = o.file_base + reference.source.file_index, .offset = reference.source.offset },
        .ty = if (value.expected_type) |local| globalizer.globalType(o, local) else output,
        .content = .{ .function_call = .{ .callee = function, .input = input } },
    };
    compatibility.core.stats.calls += 1;
    return .resolved;
}

fn matchFunctionByName(
    compatibility: Abstract,
    current_module: usize,
    module: *const module_sg.ModuleSemanticGraph,
    reference: module_entities.ExternalRef,
    input_node: global_sg.GlobalNodeId,
    reach: reach_context.Context,
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
        reach,
    );
}

pub fn matchUnqualifiedFunctionByNameWithReach(
    compatibility: Abstract,
    current_module: usize,
    name: []const u8,
    input_node: global_sg.GlobalNodeId,
    reach: reach_context.Context,
) !core_mod.Resolver.FunctionMatch {
    return matchFunctionNamed(compatibility, current_module, name, null, input_node, reach);
}

fn matchFunctionNamed(
    compatibility: Abstract,
    current_module: usize,
    name: []const u8,
    module_filter: ?global_sg.GlobalModuleId,
    input_node: global_sg.GlobalNodeId,
    reach: reach_context.Context,
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
        const score = switch (try matchInputWithReach(
            compatibility,
            function.input,
            input_node,
            reach,
        )) {
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

pub fn matchInput(
    compatibility: Abstract,
    expected_fields: global_sg.FieldRange,
    input_node: global_sg.GlobalNodeId,
) core_mod.Resolver.CallInputMatch {
    const graph = compatibility.core.graph;
    const literal = switch (graph.nodes.items[@intFromEnum(input_node)].content) {
        .struct_value_literal => |value| value,
        else => return .no_match,
    };
    if (!compatibility.core.callInputNamesMatch(expected_fields, literal)) return .no_match;
    var score: u32 = 0;
    for (0..expected_fields.len) |expected_offset| {
        const expected = graph.fields.items[expected_fields.start + @as(u32, @intCast(expected_offset))];
        const supplied = callArgument(graph, literal, expected_offset, expected.name);
        if (supplied) |node| {
            if (graph.isTypeUnresolved(expected.ty)) return .deferred;
            const supplied_node = graph.nodes.items[@intFromEnum(node)];
            if (supplied_node.ty) |actual| {
                if (graph.isTypeUnresolved(actual)) return .deferred;
                if (types.equal(graph, actual, expected.ty)) {
                    score += 4;
                } else if (compatibility.core.callTypesCompatible(actual, expected.ty) or compatibility.compatible(actual, expected.ty)) {
                    score += 3;
                } else if (types.isBuiltin(graph, expected.ty, .Any)) {
                    score += 1;
                } else if (contextualLiteralFits(compatibility, node, expected.ty)) {
                    score += 3;
                } else return .no_match;
            } else if (contextualLiteralFits(compatibility, node, expected.ty)) {
                score += 3;
            } else switch (supplied_node.content) {
                .string_literal, .struct_value_literal => return .no_match,
                else => return .deferred,
            }
        } else if (expected.default_value == null) return .no_match;
    }
    return .{ .score = score };
}

pub fn matchInputWithReach(
    compatibility: Abstract,
    expected_fields: global_sg.FieldRange,
    input_node: global_sg.GlobalNodeId,
    reach: reach_context.Context,
) !core_mod.Resolver.CallInputMatch {
    const base = matchInput(compatibility, expected_fields, input_node);
    if (base != .score) return base;
    const graph = compatibility.core.graph;
    const literal = switch (graph.nodes.items[@intFromEnum(input_node)].content) {
        .struct_value_literal => |value| value,
        else => return .no_match,
    };
    for (0..expected_fields.len) |offset| {
        const expected = graph.fields.items[expected_fields.start + @as(u32, @intCast(offset))];
        if (callArgument(graph, literal, offset, expected.name) != null) continue;
        const fallback = expected.default_value orelse return .no_match;
        if (graph.nodes.items[@intFromEnum(fallback)].content != .reach_directive) continue;
        switch (try compatibility.core.probeReachedDefaultWithCompatibility(
            reach,
            expected,
            fallback,
            compatibility.additionalTypeCompatibility(),
        )) {
            .available => {},
            .deferred => return .deferred,
            .unavailable => return .no_match,
        }
    }
    return base;
}

fn contextualLiteralFits(compatibility: Abstract, node: global_sg.GlobalNodeId, target: global_sg.GlobalTypeId) bool {
    const graph = compatibility.core.graph;
    if (integerLiteralFits(graph, node, target)) return true;
    switch (graph.nodes.items[@intFromEnum(node)].content) {
        .string_literal => return switch (graph.types.items[@intFromEnum(target)]) {
            .pointer => |pointer| pointer.mutability == .read_only and types.isBuiltin(graph, pointer.child, .Char),
            else => false,
        },
        .struct_value_literal => |literal| {
            const expected_fields = types.fields(graph, target) orelse return false;
            if (literal.fields.len > expected_fields.len) return false;
            for (0..expected_fields.len) |offset| {
                const expected = graph.fields.items[expected_fields.start + @as(u32, @intCast(offset))];
                const supplied = callArgument(graph, literal, offset, expected.name) orelse {
                    if (expected.default_value == null) return false;
                    continue;
                };
                const supplied_node = graph.nodes.items[@intFromEnum(supplied)];
                if (supplied_node.ty) |actual| {
                    if (types.equal(graph, actual, expected.ty) or
                        compatibility.core.callTypesCompatible(actual, expected.ty) or
                        compatibility.compatible(actual, expected.ty) or
                        contextualLiteralFits(compatibility, supplied, expected.ty)) continue;
                } else if (contextualLiteralFits(compatibility, supplied, expected.ty)) continue;
                return false;
            }
            return true;
        },
        else => return false,
    }
}

fn integerLiteralFits(
    graph: *const global_sg.GlobalSemanticGraph,
    node: global_sg.GlobalNodeId,
    target: global_sg.GlobalTypeId,
) bool {
    const value = switch (graph.nodes.items[@intFromEnum(node)].content) {
        .int_literal => |number| number,
        else => return false,
    };
    return switch (graph.types.items[@intFromEnum(target)]) {
        .builtin => |builtin_type| switch (builtin_type) {
            .Int8 => value >= std.math.minInt(i8) and value <= std.math.maxInt(i8),
            .Int16 => value >= std.math.minInt(i16) and value <= std.math.maxInt(i16),
            .Int32 => value >= std.math.minInt(i32) and value <= std.math.maxInt(i32),
            .Int64 => true,
            .UIntNative => value >= 0,
            .UInt8 => value >= 0 and value <= std.math.maxInt(u8),
            .UInt16 => value >= 0 and value <= std.math.maxInt(u16),
            .UInt32 => value >= 0 and value <= std.math.maxInt(u32),
            .UInt64 => value >= 0,
            else => false,
        },
        else => false,
    };
}

fn callArgument(
    graph: *const global_sg.GlobalSemanticGraph,
    literal: anytype,
    expected_offset: usize,
    expected_name: primitives.StringRange,
) ?global_sg.GlobalNodeId {
    for (0..literal.fields.len) |supplied_offset| {
        const supplied = graph.value_fields.items[literal.fields.start + @as(u32, @intCast(supplied_offset))];
        if (supplied_offset < literal.dispatch_prefix_positional_count or graph.text(supplied.name).len == 0) {
            if (supplied_offset == expected_offset) return supplied.value;
        } else if (std.mem.eql(u8, graph.text(supplied.name), graph.text(expected_name))) return supplied.value;
    }
    return null;
}
