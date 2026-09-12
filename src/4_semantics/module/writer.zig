const std = @import("std");
const graph_mod = @import("graph.zig");
const entities = @import("entities.zig");
const storage = @import("storage.zig");
const strings = @import("../primitives/strings.zig");
const primitives = @import("../primitives/schema.zig");

/// Canonical mutation API for ModuleSema. New semantic lowering should use this
/// instead of appending to migration-era compatibility tables directly.
pub const Writer = struct {
    allocator: std.mem.Allocator,
    graph: *graph_mod.ModuleSemanticGraph,
    compatibility_bases: storage.CompatibilityBases,

    pub fn init(allocator: std.mem.Allocator, graph: *graph_mod.ModuleSemanticGraph) Writer {
        const bases = graph.semantic.compatibility_bases orelse blk: {
            const value = storage.CompatibilityBases{
                .types = @intCast(graph.types.items.len),
                .fields = @intCast(graph.fields.items.len + graph.structural_fields.items.len),
                .variants = @intCast(graph.choice_variant_entries.items.len + graph.structural_choice_variants.items.len),
                .generic_arguments = @intCast(graph.generic_type_arguments.items.len),
            };
            graph.semantic.compatibility_bases = value;
            break :blk value;
        };
        return .{ .allocator = allocator, .graph = graph, .compatibility_bases = bases };
    }

    pub fn addString(self: *Writer, text: []const u8) !graph_mod.StringRange {
        return strings.append(&self.graph.strings, self.allocator, text);
    }

    fn ensureCompatibilityPrefixesStable(self: *const Writer) !void {
        const bases = self.compatibility_bases;
        if (self.graph.types.items.len != @as(usize, bases.types) or
            self.graph.fields.items.len + self.graph.structural_fields.items.len != @as(usize, bases.fields) or
            self.graph.choice_variant_entries.items.len + self.graph.structural_choice_variants.items.len != @as(usize, bases.variants) or
            self.graph.generic_type_arguments.items.len != @as(usize, bases.generic_arguments))
        {
            return error.ModuleSemanticCompatibilityPrefixMutated;
        }
    }

    fn canonicalTypeBase(self: *const Writer) usize {
        return self.compatibility_bases.types;
    }

    pub fn addType(self: *Writer, ty: entities.ModuleType) !entities.ModuleTypeId {
        try self.ensureCompatibilityPrefixesStable();
        const id = try logicalId(
            entities.ModuleTypeId,
            self.canonicalTypeBase() + self.graph.semantic.types.items.len,
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
        return self.addType(.{ .external = reference });
    }

    pub fn addField(self: *Writer, field: entities.Field) !entities.ModuleFieldId {
        try self.ensureCompatibilityPrefixesStable();
        const id = try logicalId(
            entities.ModuleFieldId,
            @as(usize, self.compatibility_bases.fields) + self.graph.semantic.fields.items.len,
        );
        try self.graph.semantic.fields.append(self.allocator, field);
        return id;
    }

    pub fn addVariant(self: *Writer, variant: entities.ChoiceVariant) !entities.ModuleVariantId {
        try self.ensureCompatibilityPrefixesStable();
        const id = try logicalId(
            entities.ModuleVariantId,
            @as(usize, self.compatibility_bases.variants) + self.graph.semantic.variants.items.len,
        );
        try self.graph.semantic.variants.append(self.allocator, variant);
        return id;
    }

    pub fn addGenericArgument(self: *Writer, argument: entities.GenericArgument) !entities.ModuleGenericArgId {
        try self.ensureCompatibilityPrefixesStable();
        const id = try logicalId(
            entities.ModuleGenericArgId,
            @as(usize, self.compatibility_bases.generic_arguments) + self.graph.semantic.generic_arguments.items.len,
        );
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

fn logicalId(comptime Id: type, index: usize) !Id {
    return directId(Id, index);
}

fn index32(value: usize) !u32 {
    if (value > std.math.maxInt(u32)) return error.ModuleSemanticGraphTooLarge;
    return @intCast(value);
}

test "module semantic writer allocates canonical ids after compatibility prefixes" {
    const allocator = std.testing.allocator;
    var graph: graph_mod.ModuleSemanticGraph = .{ .module_dir = try allocator.dupe(u8, "demo") };
    defer graph.deinit(allocator);

    try graph.types.append(allocator, .{ .builtin = .Int32 });
    try graph.fields.append(allocator, .{
        .name = .{ .start = 0, .len = 0 },
        .ty = @enumFromInt(0),
        .source_offset = 0,
        .has_default = false,
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

test "module semantic writer rejects compatibility prefix growth after canonical ids exist" {
    const allocator = std.testing.allocator;
    var graph: graph_mod.ModuleSemanticGraph = .{ .module_dir = try allocator.dupe(u8, "demo") };
    defer graph.deinit(allocator);

    var writer = Writer.init(allocator, &graph);
    _ = try writer.addResolvedType(.{ .builtin = .Int32 });
    try graph.types.append(allocator, .{ .builtin = .Bool });

    try std.testing.expectError(
        error.ModuleSemanticCompatibilityPrefixMutated,
        writer.addResolvedType(.{ .builtin = .Float32 }),
    );
}
