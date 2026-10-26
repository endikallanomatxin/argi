const std = @import("std");
const graph_mod = @import("graph.zig");
const entities = @import("entities.zig");

pub fn typeCount(graph: *const graph_mod.ModuleSemanticGraph) usize {
    return graph.semantic.types.items.len;
}

pub fn fieldCount(graph: *const graph_mod.ModuleSemanticGraph) usize {
    return graph.semantic.fields.items.len;
}

pub fn variantCount(graph: *const graph_mod.ModuleSemanticGraph) usize {
    return graph.semantic.variants.items.len;
}

pub fn genericArgumentCount(graph: *const graph_mod.ModuleSemanticGraph) usize {
    return graph.semantic.generic_arguments.items.len;
}

pub fn bindingTypeUnresolved(graph: *const graph_mod.ModuleSemanticGraph, id: entities.ModuleBindingId) bool {
    for (graph.semantic.unresolved_binding_types.items) |candidate|
        if (candidate == id) return true;
    return false;
}

pub fn declarationView(graph: *const graph_mod.ModuleSemanticGraph, id: entities.ModuleDeclId) !entities.Declaration {
    const raw: usize = @intFromEnum(id);
    if (raw >= graph.declarations.items.len) return error.InvalidModuleDeclarationId;
    const declaration = graph.declarations.items[raw];
    if (declaration.module_file_index >= graph.file_offsets.items.len) return error.InvalidModuleFileIndex;
    return .{
        .kind = declaration.kind,
        .name = declaration.name,
        .source = .{ .file_index = declaration.module_file_index, .offset = declaration.source_offset },
        .type_id = declaration.type_id,
        .function_id = declaration.function_id,
        .family_definition = declaration.family_definition,
    };
}

pub fn typeView(graph: *const graph_mod.ModuleSemanticGraph, id: entities.ModuleTypeId) !entities.ModuleType {
    const raw: usize = @intFromEnum(id);
    if (raw >= graph.semantic.types.items.len) return error.InvalidModuleTypeId;
    return graph.semantic.types.items[raw];
}

pub fn fieldView(graph: *const graph_mod.ModuleSemanticGraph, id: entities.ModuleFieldId) !entities.Field {
    const raw: usize = @intFromEnum(id);
    if (raw >= graph.semantic.fields.items.len) return error.InvalidModuleFieldId;
    return graph.semantic.fields.items[raw];
}

pub fn variantView(graph: *const graph_mod.ModuleSemanticGraph, id: entities.ModuleVariantId) !entities.ChoiceVariant {
    const raw: usize = @intFromEnum(id);
    if (raw >= graph.semantic.variants.items.len) return error.InvalidModuleVariantId;
    return graph.semantic.variants.items[raw];
}

pub fn genericArgumentView(graph: *const graph_mod.ModuleSemanticGraph, id: entities.ModuleGenericArgId) !entities.GenericArgument {
    const raw: usize = @intFromEnum(id);
    if (raw < graph.semantic.generic_arguments.items.len) return graph.semantic.generic_arguments.items[raw];
    return error.InvalidModuleGenericArgumentId;
}

pub fn recordFields(graph: *const graph_mod.ModuleSemanticGraph, ty: entities.ModuleTypeId) ?entities.FieldRange {
    const value = typeView(graph, ty) catch return null;
    if (value != .resolved) return null;
    return switch (value.resolved) {
        .structural => |shape| shape.fields,
        .nominal => |id| graph.semantic.type_definitions.items[@intFromEnum(id)].struct_fields,
        else => null,
    };
}

pub fn functionSignatureDeferred(graph: *const graph_mod.ModuleSemanticGraph, id: entities.ModuleFunctionId) bool {
    const function = graph.functions.items[@intFromEnum(id)];
    if (function.input_type) |ty| if (recordFields(graph, ty) == null) return true;
    if (function.output_type) |ty| if (recordFields(graph, ty) == null) return true;
    return false;
}

pub fn functionView(graph: *const graph_mod.ModuleSemanticGraph, id: entities.ModuleFunctionId) !entities.Function {
    const raw: usize = @intFromEnum(id);
    if (raw >= graph.functions.items.len) return error.InvalidModuleFunctionId;
    return graph.functions.items[raw];
}

test "module views expose one canonical type pool" {
    const allocator = std.testing.allocator;
    var graph: graph_mod.ModuleSemanticGraph = .{ .module_dir = try allocator.dupe(u8, "demo") };
    defer graph.deinit(allocator);

    try graph.semantic.types.append(allocator, .{ .resolved = .{ .builtin = .Int32 } });
    try graph.semantic.external_refs.append(allocator, .{
        .kind = .type,
        .module_path = null,
        .name = .{ .start = 0, .len = 0 },
        .source = .{ .file_index = 0, .offset = 0 },
    });
    try graph.semantic.types.append(allocator, .{ .resolved = .{ .inferred_choice = .{
        .identity = 4,
        .kind = .reasons,
        .variants = .{ .start = 0, .len = 0 },
    } } });
    try graph.semantic.types.append(allocator, .{ .external = @enumFromInt(0) });
    try graph.semantic.types.append(allocator, .{ .resolved = .{ .pointer = .{
        .child = @enumFromInt(2),
        .mutability = .read_only,
    } } });

    try std.testing.expectEqual(@import("../primitives/schema.zig").BuiltinType.Int32, (try typeView(&graph, @enumFromInt(0))).resolved.builtin);
    try std.testing.expectEqual(@import("../primitives/schema.zig").InferredChoiceKind.reasons, (try typeView(&graph, @enumFromInt(1))).resolved.inferred_choice.kind);
    try std.testing.expectEqual(@as(u32, 0), @intFromEnum((try typeView(&graph, @enumFromInt(2))).external));
    try std.testing.expectEqual(@as(u32, 2), @intFromEnum((try typeView(&graph, @enumFromInt(3))).resolved.pointer.child));
    try std.testing.expectEqual(@as(usize, 4), typeCount(&graph));
}

/// A read-only signature view preserves the ID namespace of its fields. It
/// never copies a named record into the parameterized representation.
pub const SignatureFields = union(enum) {
    concrete: entities.FieldRange,
    parameterized: @import("../primitives/schema.zig").Range(@import("parameterized/ir.zig").ParameterizedFieldId),

    pub fn count(self: SignatureFields) u32 {
        return switch (self) {
            inline else => |range| range.len,
        };
    }

    pub const FieldType = union(enum) {
        concrete: entities.ModuleTypeId,
        parameterized: @import("parameterized/ir.zig").ParameterizedTypeId,
    };

    pub fn fieldType(self: SignatureFields, graph: *const graph_mod.ModuleSemanticGraph, index: u32) FieldType {
        return switch (self) {
            .concrete => |range| .{ .concrete = graph.semantic.fields.items[range.start + index].ty },
            .parameterized => |range| .{ .parameterized = graph.semantic.parameterized_storage.ir.fields.items[range.start + index].ty },
        };
    }

    pub fn name(self: SignatureFields, graph: *const graph_mod.ModuleSemanticGraph, index: u32) @import("../primitives/schema.zig").StringRange {
        return switch (self) {
            .concrete => |range| graph.semantic.fields.items[range.start + index].name,
            .parameterized => |range| graph.semantic.parameterized_storage.ir.fields.items[range.start + index].name,
        };
    }
};

pub fn signatureFields(graph: *const graph_mod.ModuleSemanticGraph, ty: @import("parameterized/ir.zig").ParameterizedTypeId) ?SignatureFields {
    const storage = &graph.semantic.parameterized_storage;
    var current = ty;
    for (0..storage.ir.types.items.len + 1) |_| {
        const value = storage.ir.representation(current);
        switch (value) {
            .concrete => |id| return if (recordFields(graph, id)) |fields| .{ .concrete = fields } else null,
            .resolved => |resolved| switch (resolved) {
                .structural => |shape| return .{ .parameterized = shape.fields },
                .nominal => |id| return if (graph.semantic.type_definitions.items[@intFromEnum(id)].struct_fields) |fields| .{ .concrete = fields } else null,
                .generic => |generic| {
                    const reference = storage.ir.declarations.items[@intFromEnum(generic.base)].target;
                    const declaration = switch (reference) {
                        .module => |id| graph.declaration(id),
                        .external => return null,
                    };
                    const family = graph.semantic.family_definitions.items[@intFromEnum(declaration.family_definition orelse return null)];
                    if (family.kind != .type) return null;
                    const index = family.template_index orelse return null;
                    if (index >= storage.parameterized_types.items.len) return null;
                    current = storage.parameterized_types.items[index].body;
                },
                else => return null,
            },
            else => return null,
        }
    }
    return null;
}
