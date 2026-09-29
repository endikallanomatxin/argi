const std = @import("std");
const graph_mod = @import("graph.zig");
const types = @import("types.zig");
const generics_mod = @import("generics.zig");

/// The result of `init` reports completion of its destination. A constructed
/// value never appears as a second, independent function result.
pub const Result = union(enum) {
    infallible,
    fallible: struct {
        errable_type: graph_mod.GlobalTypeId,
        reasons_type: graph_mod.GlobalTypeId,
    },
    invalid,
};

pub fn classify(graph: *const graph_mod.GlobalSemanticGraph, function_id: graph_mod.GlobalFunctionId) Result {
    const function = graph.function(function_id);
    if (function.output.len == 0) return .infallible;
    if (function.output.len != 1) return .invalid;
    const result_type = graph.fields.items[function.output.start].ty;
    const semantic = graph.resolvedSemanticType(result_type) orelse return .invalid;
    const is_errable = switch (semantic) {
        .generic => |identity| blk: {
            const declaration = graph.declaration(identity.base);
            const owner = graph.moduleForDeclaration(identity.base) orelse break :blk false;
            break :blk graph.modules.items[@intFromEnum(owner)].is_bundled_core and
                std.mem.eql(u8, graph.text(declaration.name), "Errable");
        },
        .inferred_choice => |choice| choice.kind == .errable,
        else => false,
    };
    if (!is_errable) return .invalid;
    const ok = types.findVariant(graph, result_type, "ok") orelse return .invalid;
    if (ok.variant.payload_type == null or !types.isBuiltin(graph, ok.variant.payload_type.?, .Void)) return .invalid;
    const err = types.findVariant(graph, result_type, "error") orelse return .invalid;
    const payload = err.variant.payload_type orelse return .invalid;
    const reason = types.findField(graph, payload, "reason") orelse return .invalid;
    return .{ .fallible = .{ .errable_type = result_type, .reasons_type = reason.field.ty } };
}

pub fn constructedType(
    allocator: std.mem.Allocator,
    graph: *graph_mod.GlobalSemanticGraph,
    generics: *generics_mod.Resolver,
    target: graph_mod.GlobalTypeId,
    result: Result,
) !graph_mod.GlobalTypeId {
    const fallible = switch (result) {
        .infallible => return target,
        .fallible => |value| value,
        .invalid => return error.InvalidInitializerResult,
    };
    const source = graph.semanticType(fallible.errable_type);
    const base = switch (source) {
        .generic => |identity| identity.base,
        .inferred_choice => blk: {
            for (graph.declarations.items, 0..) |declaration, raw| {
                if (declaration.kind != .type or !std.mem.eql(u8, graph.text(declaration.name), "Errable")) continue;
                const id: graph_mod.GlobalDeclId = @enumFromInt(@as(u32, @intCast(raw)));
                const owner = graph.moduleForDeclaration(id) orelse continue;
                if (graph.modules.items[@intFromEnum(owner)].is_bundled_core) break :blk id;
            }
            return error.MissingErrableType;
        },
        else => unreachable,
    };
    const start: u32 = @intCast(graph.generic_arguments.items.len);
    try graph.generic_arguments.append(allocator, .{
        .name = try graph.addString(allocator, "t"),
        .value = .{ .type = target },
    });
    try graph.generic_arguments.append(allocator, .{
        .name = try graph.addString(allocator, "reasons"),
        .value = .{ .type = fallible.reasons_type },
    });
    const ty = try generics.internType(.{ .generic = .{
        .base = base,
        .arguments = .{ .start = start, .len = 2 },
    } });
    _ = try generics.ensureGenericInstance(ty);
    return ty;
}
