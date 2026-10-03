const std = @import("std");
const graph_mod = @import("graph.zig");
const types = @import("types.zig");
const generics_mod = @import("generics.zig");

/// Constructors return their value directly; fallible construction places it
/// in the ordinary Errable success payload instead of refining an input place.
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
    if (!is_errable) return if (matchesAssociation(graph, function.declaration, result_type)) .infallible else .invalid;
    const ok = types.findVariant(graph, result_type, "ok") orelse return .invalid;
    if (ok.variant.payload_type == null or types.isBuiltin(graph, ok.variant.payload_type.?, .Void)) return .invalid;
    if (!matchesAssociation(graph, function.declaration, ok.variant.payload_type.?)) return .invalid;
    const err = types.findVariant(graph, result_type, "error") orelse return .invalid;
    const payload = err.variant.payload_type orelse return .invalid;
    const reason = types.findField(graph, payload, "reason") orelse return .invalid;
    return .{ .fallible = .{ .errable_type = result_type, .reasons_type = reason.field.ty } };
}

pub fn valueType(graph: *const graph_mod.GlobalSemanticGraph, function_id: graph_mod.GlobalFunctionId) ?graph_mod.GlobalTypeId {
    const function = graph.function(function_id);
    return switch (classify(graph, function_id)) {
        .infallible => graph.fields.items[function.output.start].ty,
        .fallible => |result| (types.findVariant(graph, result.errable_type, "ok") orelse return null).variant.payload_type,
        .invalid => null,
    };
}

pub fn constructedType(
    allocator: std.mem.Allocator,
    graph: *graph_mod.GlobalSemanticGraph,
    generics: *generics_mod.Resolver,
    target: graph_mod.GlobalTypeId,
    result: Result,
) !graph_mod.GlobalTypeId {
    _ = allocator;
    _ = generics;
    return switch (result) {
        .infallible => target,
        .fallible => |value| blk: {
            const ok = types.findVariant(graph, value.errable_type, "ok") orelse return error.InvalidInitializerResult;
            if (!types.equal(graph, ok.variant.payload_type orelse return error.InvalidInitializerResult, target)) return error.InvalidInitializerResult;
            break :blk value.errable_type;
        },
        .invalid => error.InvalidInitializerResult,
    };
}

fn matchesAssociation(graph: *const graph_mod.GlobalSemanticGraph, declaration: graph_mod.GlobalDeclId, ty: graph_mod.GlobalTypeId) bool {
    const associated = graph.declaration(declaration).constructor_type orelse return false;
    return switch (graph.resolvedSemanticType(ty) orelse return false) {
        .declared => |id| id == associated,
        .generic => |identity| identity.base == associated,
        else => false,
    };
}
