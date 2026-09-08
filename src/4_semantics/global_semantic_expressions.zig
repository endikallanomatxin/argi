const std = @import("std");
const module_sg = @import("module_semantic_graph.zig");
const module_entities = @import("module_semantic_entities.zig");
const global_sg = @import("global_semantic_graph.zig");
const globalizer = @import("semantic_globalizer.zig");

pub const Stats = struct {
    binding_uses: u32 = 0,
};

pub const Resolver = struct {
    graph: *global_sg.GlobalSemanticGraph,
    modules: []const module_sg.ModuleSemanticGraph,
    offsets: []const globalizer.Offsets,
    stats: Stats = .{},

    pub fn tryResolve(
        self: *Resolver,
        module_index: usize,
        module: *const module_sg.ModuleSemanticGraph,
        o: globalizer.Offsets,
        operation: module_entities.PendingOperation,
    ) !?bool {
        _ = module;
        return switch (operation) {
            .resolve_expression => |expression| switch (expression.kind) {
                .unknown_identifier => @as(?bool, self.resolveBindingUse(module_index, o, expression)),
                else => null,
            },
            else => null,
        };
    }

    fn resolveBindingUse(
        self: *Resolver,
        module_index: usize,
        o: globalizer.Offsets,
        expression: module_entities.PendingExpression,
    ) bool {
        const local_name = expression.name orelse return false;
        const name = self.modules[module_index].text(local_name);

        // The calling module always wins over implicit bundled-core lookup.
        if (self.bindingNamedInModule(module_index, name)) |binding| {
            self.patchBindingUse(o, expression.node, binding);
            self.stats.binding_uses += 1;
            return true;
        }

        var found: ?global_sg.GlobalBindingId = null;
        for (self.modules, 0..) |*candidate, candidate_index| {
            if (candidate_index == module_index or !candidate.is_bundled_core) continue;
            if (std.mem.startsWith(u8, name, "_")) continue;
            const binding = self.bindingNamedInModule(candidate_index, name) orelse continue;
            if (found != null) return false;
            found = binding;
        }
        const binding = found orelse return false;
        self.patchBindingUse(o, expression.node, binding);
        self.stats.binding_uses += 1;
        return true;
    }

    fn bindingNamedInModule(self: *const Resolver, module_index: usize, name: []const u8) ?global_sg.GlobalBindingId {
        const module = &self.modules[module_index];
        var found: ?global_sg.GlobalBindingId = null;
        for (module.semantic.declaration_bindings.items) |relation| {
            const declaration = module.declarations.items[@intFromEnum(relation.declaration)];
            if (!std.mem.eql(u8, module.text(declaration.name), name)) continue;
            if (found != null) return null;
            found = @enumFromInt(self.offsets[module_index].binding_base + @intFromEnum(relation.binding));
        }
        return found;
    }

    fn patchBindingUse(
        self: *Resolver,
        o: globalizer.Offsets,
        local_node: module_entities.ModuleNodeId,
        binding: global_sg.GlobalBindingId,
    ) void {
        const target: global_sg.GlobalNodeId = @enumFromInt(o.node_base + @intFromEnum(local_node));
        const source = self.graph.nodes.items[@intFromEnum(target)].source;
        const ty = self.graph.bindings.items[@intFromEnum(binding)].ty;
        self.graph.nodes.items[@intFromEnum(target)] = .{
            .source = source,
            .ty = ty,
            .content = .{ .binding_use = binding },
        };
    }
};

test "expression resolver prefers module bindings over bundled core" {
    const allocator = std.testing.allocator;
    var graph: global_sg.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);

    var app: module_sg.ModuleSemanticGraph = .{ .module_dir = try allocator.dupe(u8, "app") };
    defer app.deinit(allocator);
    var core: module_sg.ModuleSemanticGraph = .{ .module_dir = try allocator.dupe(u8, "core"), .is_bundled_core = true };
    defer core.deinit(allocator);

    try app.strings.appendSlice(allocator, "value");
    try core.strings.appendSlice(allocator, "value");
    const name: module_sg.StringRange = .{ .start = 0, .len = 5 };
    try app.declarations.append(allocator, .{ .kind = .binding, .name = name, .source_offset = 0, .module_file_index = 0, .syntax_node = @enumFromInt(0) });
    try core.declarations.append(allocator, .{ .kind = .binding, .name = name, .source_offset = 0, .module_file_index = 0, .syntax_node = @enumFromInt(0) });
    try app.semantic.declaration_bindings.append(allocator, .{ .declaration = @enumFromInt(0), .binding = @enumFromInt(0) });
    try core.semantic.declaration_bindings.append(allocator, .{ .declaration = @enumFromInt(0), .binding = @enumFromInt(0) });

    const int_ty: global_sg.GlobalTypeId = @enumFromInt(0);
    try graph.types.append(allocator, .{ .builtin = .Int32 });
    try graph.bindings.append(allocator, .{ .name = .{ .start = 0, .len = 0 }, .source = .{ .file_index = 0, .offset = 0 }, .ty = int_ty, .mutability = .constant });
    try graph.bindings.append(allocator, .{ .name = .{ .start = 0, .len = 0 }, .source = .{ .file_index = 0, .offset = 0 }, .ty = int_ty, .mutability = .constant });
    try graph.nodes.append(allocator, .{ .source = .{ .file_index = 0, .offset = 7 }, .ty = null, .content = .{ .bool_literal = false } });

    const offsets = [_]globalizer.Offsets{
        emptyOffsets(0, 0),
        emptyOffsets(1, 1),
    };
    var resolver: Resolver = .{ .graph = &graph, .modules = &.{ app, core }, .offsets = &offsets };
    const expression: module_entities.PendingExpression = .{ .node = @enumFromInt(0), .kind = .unknown_identifier, .name = name };
    try std.testing.expect(resolver.resolveBindingUse(0, offsets[0], expression));
    try std.testing.expectEqual(@as(global_sg.GlobalBindingId, @enumFromInt(0)), graph.nodes.items[0].content.binding_use);
}

fn emptyOffsets(binding_base: u32, node_base: u32) globalizer.Offsets {
    return .{
        .file_base = 0,
        .declaration_base = 0,
        .type_base = 0,
        .function_base = 0,
        .field_base = 0,
        .variant_base = 0,
        .generic_argument_base = 0,
        .binding_base = binding_base,
        .node_base = node_base,
        .block_base = 0,
        .value_field_base = 0,
        .switch_case_base = 0,
        .switch_base = 0,
        .auto_deinit_field_base = 0,
        .auto_deinit_base = 0,
        .virtual_registry_base = 0,
        .virtualize_base = 0,
        .virtual_call_base = 0,
        .reach_segment_base = 0,
        .reach_alternative_base = 0,
        .reach_base = 0,
        .nullable_unwrap_base = 0,
        .testing_expect_error_base = 0,
        .error_propagation_base = 0,
        .error_context_base = 0,
        .node_ref_base = 0,
        .type_ref_base = 0,
        .binding_ref_base = 0,
        .function_ref_base = 0,
        .virtual_registry_ref_base = 0,
        .symbol_declaration_base = 0,
        .string_base = 0,
    };
}
