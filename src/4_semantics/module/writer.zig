const std = @import("std");
const graph_mod = @import("graph.zig");
const entities = @import("entities.zig");
const strings = @import("../primitives/strings.zig");
const primitives = @import("../primitives/schema.zig");

/// Canonical append API for module-owned semantic identities.
pub const Writer = struct {
    allocator: std.mem.Allocator,
    graph: *graph_mod.ModuleSemanticGraph,
    pending_owner_function: ?entities.ModuleFunctionId = null,

    pub fn init(allocator: std.mem.Allocator, graph: *graph_mod.ModuleSemanticGraph) Writer {
        return .{ .allocator = allocator, .graph = graph };
    }

    pub fn addString(self: *Writer, text: []const u8) !graph_mod.StringRange {
        return strings.append(&self.graph.strings, self.allocator, text);
    }

    pub fn addType(self: *Writer, ty: entities.ModuleType) !entities.ModuleTypeId {
        const id = try directId(
            entities.ModuleTypeId,
            self.graph.semantic.types.items.len,
        );
        try self.graph.semantic.types.append(self.allocator, ty);
        return id;
    }

    pub fn addResolvedType(self: *Writer, ty: entities.ResolvedType) !entities.ModuleTypeId {
        return self.addType(.{ .resolved = ty });
    }

    pub fn addExternalRef(self: *Writer, reference: entities.ExternalRef) !entities.ExternalRefId {
        const id = try directId(entities.ExternalRefId, self.graph.semantic.external_refs.items.len);
        try self.graph.semantic.external_refs.append(self.allocator, reference);
        return id;
    }

    pub fn addExternalType(self: *Writer, reference: entities.ExternalRefId) !entities.ModuleTypeId {
        const destination = try self.addType(.{ .external = reference });
        _ = try self.addPendingOperation(.{ .resolve_type = .{ .destination = destination, .external = reference } });
        return destination;
    }

    pub fn addField(self: *Writer, field: entities.Field) !entities.ModuleFieldId {
        const id = try directId(
            entities.ModuleFieldId,
            self.graph.semantic.fields.items.len,
        );
        try self.graph.semantic.fields.append(self.allocator, field);
        return id;
    }

    pub fn addVariant(self: *Writer, variant: entities.ChoiceVariant) !entities.ModuleVariantId {
        const id = try directId(
            entities.ModuleVariantId,
            self.graph.semantic.variants.items.len,
        );
        try self.graph.semantic.variants.append(self.allocator, variant);
        return id;
    }

    pub fn addGenericArgument(self: *Writer, argument: entities.GenericArgument) !entities.ModuleGenericArgId {
        const id = try directId(entities.ModuleGenericArgId, self.graph.semantic.generic_arguments.items.len);
        try self.graph.semantic.generic_arguments.append(self.allocator, argument);
        return id;
    }

    pub fn addBinding(self: *Writer, binding: entities.Binding) !entities.ModuleBindingId {
        const id = try directId(entities.ModuleBindingId, self.graph.semantic.bindings.items.len);
        try self.graph.semantic.bindings.append(self.allocator, binding);
        return id;
    }

    pub fn addUnresolvedBinding(
        self: *Writer,
        name: primitives.StringRange,
        source: primitives.SourceRef,
        initialization: ?entities.ModuleNodeId,
        mutability: primitives.Mutability,
    ) !entities.ModuleBindingId {
        const id = try directId(entities.ModuleBindingId, self.graph.semantic.bindings.items.len);
        const old_len = self.graph.semantic.bindings.items.len;
        errdefer self.graph.semantic.bindings.shrinkRetainingCapacity(old_len);
        try self.graph.semantic.bindings.append(self.allocator, .{
            .name = name,
            .source = source,
            .ty = entities.unresolved_binding_type_poison,
            .initialization = initialization,
            .mutability = mutability,
        });
        try self.graph.semantic.unresolved_binding_types.append(self.allocator, id);
        return id;
    }

    pub fn addNode(self: *Writer, node: entities.ModuleNode) !entities.ModuleNodeId {
        const id = try directId(entities.ModuleNodeId, self.graph.semantic.nodes.items.len);
        try self.graph.semantic.nodes.append(self.allocator, node);
        return id;
    }

    pub fn addResolvedNode(self: *Writer, node: entities.ResolvedNode) !entities.ModuleNodeId {
        return self.addNode(.{ .resolved = node });
    }

    pub fn addPendingOperation(self: *Writer, operation: entities.PendingOperation) !entities.PendingOperationId {
        const id = try directId(entities.PendingOperationId, self.graph.semantic.pending_operations.items.len);
        try self.graph.semantic.pending_operations.append(self.allocator, operation);
        errdefer self.graph.semantic.pending_operations.shrinkRetainingCapacity(@intFromEnum(id));
        try self.graph.semantic.pending_owner_functions.append(self.allocator, self.pending_owner_function);
        return id;
    }

    pub fn addPendingNode(self: *Writer, operation: entities.PendingOperation) !entities.ModuleNodeId {
        const pending = try self.addPendingOperation(operation);
        return self.addNode(.{ .pending = pending });
    }

    pub fn addBlock(self: *Writer, block: entities.Block) !entities.ModuleBlockId {
        const id = try directId(entities.ModuleBlockId, self.graph.semantic.blocks.items.len);
        try self.graph.semantic.blocks.append(self.allocator, block);
        return id;
    }

    pub fn appendNodeRefs(self: *Writer, values: []const entities.ModuleNodeId) !entities.NodeRange {
        const start = try index32(self.graph.semantic.node_refs.items.len);
        try self.graph.semantic.node_refs.appendSlice(self.allocator, values);
        return .{ .start = start, .len = try index32(values.len) };
    }

    pub fn appendBindingRefs(self: *Writer, values: []const entities.ModuleBindingId) !entities.BindingRange {
        const start = try index32(self.graph.semantic.binding_refs.items.len);
        try self.graph.semantic.binding_refs.appendSlice(self.allocator, values);
        return .{ .start = start, .len = try index32(values.len) };
    }

    pub fn appendTypeRefs(self: *Writer, values: []const entities.ModuleTypeId) !entities.TypeRange {
        const start = try index32(self.graph.semantic.type_refs.items.len);
        try self.graph.semantic.type_refs.appendSlice(self.allocator, values);
        return .{ .start = start, .len = try index32(values.len) };
    }

    pub fn addRoot(self: *Writer, node: entities.ModuleNodeId) !void {
        try self.graph.semantic.roots.append(self.allocator, node);
    }

    pub fn markLocalSemanticsComplete(self: *Writer) void {
        self.graph.semantic.local_semantics_complete = true;
    }
};

fn directId(comptime Id: type, index: usize) !Id {
    return @enumFromInt(try index32(index));
}

fn index32(value: usize) !u32 {
    if (value > std.math.maxInt(u32)) return error.ModuleSemanticGraphTooLarge;
    return @intCast(value);
}

test "module semantic writers share canonical ids across construction contexts" {
    const allocator = std.testing.allocator;
    var graph: graph_mod.ModuleSemanticGraph = .{ .module_dir = try allocator.dupe(u8, "demo") };
    defer graph.deinit(allocator);

    try graph.semantic.types.append(allocator, .{ .resolved = .{ .builtin = .Int32 } });
    try graph.semantic.fields.append(allocator, .{
        .name = .{ .start = 0, .len = 0 },
        .ty = @enumFromInt(0),
        .source = .{ .file_index = 0, .offset = 0 },
    });

    var writer = Writer.init(allocator, &graph);
    const ty = try writer.addResolvedType(.{ .builtin = .Bool });
    try std.testing.expectEqual(@as(u32, 1), @intFromEnum(ty));

    const field = try writer.addField(.{
        .name = .{ .start = 0, .len = 0 },
        .ty = ty,
        .source = .{ .file_index = 0, .offset = 0 },
    });
    try std.testing.expectEqual(@as(u32, 1), @intFromEnum(field));
}

test "module semantic writer interleaves external and resolved canonical types" {
    const allocator = std.testing.allocator;
    var graph: graph_mod.ModuleSemanticGraph = .{ .module_dir = try allocator.dupe(u8, "demo") };
    defer graph.deinit(allocator);
    var writer = Writer.init(allocator, &graph);

    const name = try writer.addString("Other");
    const external = try writer.addExternalRef(.{
        .kind = .type,
        .module_path = null,
        .name = name,
        .source = .{ .file_index = 0, .offset = 0 },
    });
    const external_ty = try writer.addExternalType(external);
    const pointer_ty = try writer.addResolvedType(.{ .pointer = .{
        .child = external_ty,
        .mutability = .read_only,
    } });
    try std.testing.expectEqual(@as(u32, 0), @intFromEnum(external_ty));
    try std.testing.expectEqual(@as(u32, 1), @intFromEnum(pointer_ty));
}

test "external type values register deferred resolution in the current owner" {
    const a = std.testing.allocator;
    var graph: graph_mod.ModuleSemanticGraph = .{ .module_dir = try a.dupe(u8, "demo") };
    defer graph.deinit(a);
    var writer = Writer.init(a, &graph);
    const reference = try writer.addExternalRef(.{ .kind = .type, .module_path = null, .name = try writer.addString("Alias"), .source = .{ .file_index = 0, .offset = 0 } });
    const ty = try writer.addExternalType(reference);
    try std.testing.expectEqual(@as(usize, 1), graph.semantic.pending_operations.items.len);
    const operation = graph.semantic.pending_operations.items[0].resolve_type;
    try std.testing.expectEqual(ty, operation.destination);
    try std.testing.expectEqual(reference, operation.external);
    try std.testing.expectEqual(@as(?entities.ModuleFunctionId, null), graph.semantic.pending_owner_functions.items[0]);
    writer.pending_owner_function = @enumFromInt(3);
    _ = try writer.addExternalType(reference);
    try std.testing.expectEqual(@as(?entities.ModuleFunctionId, @enumFromInt(3)), graph.semantic.pending_owner_functions.items[1]);
}
