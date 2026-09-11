const std = @import("std");
const module_sg = @import("../module/graph.zig");
const module_entities = @import("../module/entities.zig");
const global_sg = @import("graph.zig");
const globalizer = @import("globalizer.zig");
const name_lookup = @import("name_lookup.zig");

pub const Stats = struct {
    binding_uses: u32 = 0,
    binding_assignments: u32 = 0,
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
            .resolve_name_use => |value| @as(?bool, self.resolveNameUse(module_index, o, value)),
            .resolve_name_assignment => |value| @as(?bool, self.resolveNameAssignment(module_index, o, value)),
            // Module values need a first-class representation before imports can
            // be materialized. The operation is nevertheless explicit now, so
            // no unrelated resolver can accidentally reinterpret it as a name.
            .resolve_import => @as(?bool, false),
            else => null,
        };
    }

    fn resolveNameUse(self: *Resolver, module_index: usize, o: globalizer.Offsets, value: anytype) bool {
        const name = self.modules[module_index].text(value.name);
        if (name_lookup.binding(self.modules, self.offsets, module_index, name)) |binding|
            return self.patchNameUse(o, value.node, binding);
        return self.patchTypeExpression(module_index, o, value.node, name);
    }

    fn resolveNameAssignment(self: *Resolver, module_index: usize, o: globalizer.Offsets, value: anytype) bool {
        const name = self.modules[module_index].text(value.name);
        const binding = name_lookup.binding(self.modules, self.offsets, module_index, name) orelse return false;
        const target = globalizer.globalNode(o, value.node);
        const source = self.graph.nodes.items[@intFromEnum(target)].source;
        const ty = self.graph.bindings.items[@intFromEnum(binding)].ty;
        self.graph.nodes.items[@intFromEnum(target)] = .{
            .source = source,
            .ty = ty,
            .content = .{ .assignment = .{
                .binding = binding,
                .value = globalizer.globalNode(o, value.value),
            } },
        };
        self.stats.binding_assignments += 1;
        return true;
    }

    fn patchNameUse(
        self: *Resolver,
        o: globalizer.Offsets,
        node: module_entities.ModuleNodeId,
        binding: global_sg.GlobalBindingId,
    ) bool {
        const target = globalizer.globalNode(o, node);
        const source = self.graph.nodes.items[@intFromEnum(target)].source;
        const ty = self.graph.bindings.items[@intFromEnum(binding)].ty;
        self.graph.nodes.items[@intFromEnum(target)] = .{
            .source = source,
            .ty = ty,
            .content = .{ .binding_use = binding },
        };
        self.stats.binding_uses += 1;
        return true;
    }

    fn patchTypeExpression(self: *Resolver, module_index: usize, o: globalizer.Offsets, node: module_entities.ModuleNodeId, name: []const u8) bool {
        var found: ?global_sg.GlobalTypeId = null;
        for (self.graph.types.items, 0..) |item, raw| switch (item) {
            .builtin => |builtin| if (std.mem.eql(u8, name, @tagName(builtin))) {
                // Globalization preserves module-local type identities, so the
                // same language builtin can legitimately occupy several global
                // slots. Those slots are semantically identical and must not be
                // mistaken for an ambiguous source-level type declaration.
                if (found == null) found = @enumFromInt(@as(u32, @intCast(raw)));
            },
            else => {},
        };
        for (self.graph.declarations.items, 0..) |declaration, raw| {
            if (declaration.kind != .type or !std.mem.eql(u8, self.graph.text(declaration.name), name)) continue;
            const id: global_sg.GlobalDeclId = @enumFromInt(@as(u32, @intCast(raw)));
            const owner = self.graph.moduleForDeclaration(id) orelse continue;
            if (@intFromEnum(owner) != module_index and !self.graph.modules.items[@intFromEnum(owner)].is_bundled_core) continue;
            if (found != null) return false;
            found = declaration.type_id orelse continue;
        }
        const ty = found orelse return false;
        var meta: ?global_sg.GlobalTypeId = null;
        for (self.graph.types.items, 0..) |item, raw| switch (item) {
            .builtin => |builtin| {
                if (builtin == .Type) meta = @enumFromInt(@as(u32, @intCast(raw)));
            },
            else => {},
        };
        const target = globalizer.globalNode(o, node);
        self.graph.nodes.items[@intFromEnum(target)] = .{
            .source = self.graph.nodes.items[@intFromEnum(target)].source,
            .ty = meta orelse return false,
            .content = .{ .type_literal = ty },
        };
        return true;
    }
};

test "expression resolver preserves global binding reads and assignments" {
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
    try graph.nodes.append(allocator, .{ .source = .{ .file_index = 0, .offset = 8 }, .ty = int_ty, .content = .{ .int_literal = 4 } });

    const offsets = [_]globalizer.Offsets{
        emptyOffsets(0, 0),
        emptyOffsets(1, 2),
    };
    var resolver: Resolver = .{ .graph = &graph, .modules = &.{ app, core }, .offsets = &offsets };

    const read = module_entities.PendingOperation{ .resolve_name_use = .{
        .node = @enumFromInt(0),
        .name = name,
    } };
    try std.testing.expect((try resolver.tryResolve(0, &app, offsets[0], read)).?);
    try std.testing.expectEqual(@as(global_sg.GlobalBindingId, @enumFromInt(0)), graph.nodes.items[0].content.binding_use);

    graph.nodes.items[0] = .{ .source = .{ .file_index = 0, .offset = 9 }, .ty = null, .content = .{ .bool_literal = false } };
    const assignment = module_entities.PendingOperation{ .resolve_name_assignment = .{
        .node = @enumFromInt(0),
        .name = name,
        .value = @enumFromInt(1),
    } };
    try std.testing.expect((try resolver.tryResolve(0, &app, offsets[0], assignment)).?);
    try std.testing.expectEqual(@as(global_sg.GlobalBindingId, @enumFromInt(0)), graph.nodes.items[0].content.assignment.binding);
    try std.testing.expectEqual(@as(global_sg.GlobalNodeId, @enumFromInt(1)), graph.nodes.items[0].content.assignment.value);
}

test "expression resolver accepts duplicated global builtin storage" {
    const allocator = std.testing.allocator;
    var graph: global_sg.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);
    var module: module_sg.ModuleSemanticGraph = .{ .module_dir = try allocator.dupe(u8, "app") };
    defer module.deinit(allocator);

    try module.strings.appendSlice(allocator, "UIntNative");
    const name: module_sg.StringRange = .{ .start = 0, .len = 10 };
    try graph.types.append(allocator, .{ .builtin = .UIntNative });
    try graph.types.append(allocator, .{ .builtin = .UIntNative });
    try graph.types.append(allocator, .{ .builtin = .Type });
    try graph.types.append(allocator, .{ .builtin = .Type });
    try graph.nodes.append(allocator, .{ .source = .{ .file_index = 0, .offset = 3 }, .ty = null, .content = .{ .bool_literal = false } });

    const offsets = [_]globalizer.Offsets{emptyOffsets(0, 0)};
    var resolver: Resolver = .{ .graph = &graph, .modules = &.{module}, .offsets = &offsets };
    const operation = module_entities.PendingOperation{ .resolve_name_use = .{
        .node = @enumFromInt(0),
        .name = name,
    } };

    try std.testing.expect((try resolver.tryResolve(0, &module, offsets[0], operation)).?);
    try std.testing.expectEqual(@as(global_sg.GlobalTypeId, @enumFromInt(0)), graph.nodes.items[0].content.type_literal);
    try std.testing.expectEqual(@as(global_sg.GlobalTypeId, @enumFromInt(3)), graph.nodes.items[0].ty.?);
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
