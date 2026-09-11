const std = @import("std");
const module_sg = @import("../module/graph.zig");
const module_entities = @import("../module/entities.zig");
const global_sg = @import("graph.zig");
const globalizer = @import("globalizer.zig");
const core_mod = @import("core.zig");
const types = @import("types.zig");

/// Resolves call syntax whose callee is a declared struct type. Function and
/// generic-function dispatch run before this resolver, so construction is a
/// semantic fallback rather than a competing callable namespace.
pub const Resolver = struct {
    graph: *global_sg.GlobalSemanticGraph,
    modules: []const module_sg.ModuleSemanticGraph,
    offsets: []const globalizer.Offsets,
    core: *core_mod.Resolver,

    pub fn tryResolve(
        self: *Resolver,
        module_index: usize,
        module: *const module_sg.ModuleSemanticGraph,
        o: globalizer.Offsets,
        operation: module_entities.PendingOperation,
    ) !?bool {
        return switch (operation) {
            .resolve_call => |value| @as(?bool, try self.resolveCall(module_index, module, o, value)),
            else => null,
        };
    }

    fn resolveCall(
        self: *Resolver,
        module_index: usize,
        module: *const module_sg.ModuleSemanticGraph,
        o: globalizer.Offsets,
        value: anytype,
    ) !bool {
        const reference = module.semantic.external_refs.items[@intFromEnum(value.callee)];
        if (reference.generic_arguments != null) return false;

        const declaration_id = self.core.resolveDeclaration(module_index, reference, &.{.type}) catch return false;
        const declaration = self.graph.declarations.items[@intFromEnum(declaration_id)];
        const ty = declaration.type_id orelse return false;
        const fields = types.fields(self.graph, ty) orelse return false;
        const input = globalizer.globalNode(o, value.input);

        // completeCallInputFields fills defaults and canonicalizes argument
        // order, but dispatch compatibility must be checked first: construction
        // must not silently accept an incompatible field value.
        if (self.core.scoreCallInput(fields, input) == null) return false;
        if (!try self.core.completeCallInputFields(fields, input)) return false;

        self.graph.nodes.items[@intFromEnum(input)].ty = ty;
        self.graph.nodes.items[@intFromEnum(input)].content.struct_value_literal.ty = ty;

        const target = globalizer.globalNode(o, value.node);
        self.graph.nodes.items[@intFromEnum(target)] = self.graph.nodes.items[@intFromEnum(input)];
        self.graph.nodes.items[@intFromEnum(target)].source = .{
            .file_index = o.file_base + reference.source.file_index,
            .offset = reference.source.offset,
        };
        self.core.stats.calls += 1;
        return true;
    }
};

test "declared type call materializes a struct value" {
    const allocator = std.testing.allocator;
    var graph: global_sg.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);
    var module: module_sg.ModuleSemanticGraph = .{ .module_dir = try allocator.dupe(u8, "app") };
    defer module.deinit(allocator);

    try module.strings.appendSlice(allocator, "Packet");
    const module_name: module_sg.StringRange = .{ .start = 0, .len = 6 };
    try module.semantic.external_refs.append(allocator, .{
        .kind = .function,
        .module_path = null,
        .name = module_name,
        .source = .{ .file_index = 0, .offset = 17 },
    });

    const declaration_name = try graph.addString(allocator, "Packet");
    const module_dir = try graph.addString(allocator, "app");
    const declaration_id: global_sg.GlobalDeclId = @enumFromInt(0);
    const declared_type: global_sg.GlobalTypeId = @enumFromInt(0);
    const input_type: global_sg.GlobalTypeId = @enumFromInt(1);
    try graph.declarations.append(allocator, .{
        .kind = .type,
        .name = declaration_name,
        .source = .{ .file_index = 0, .offset = 0 },
        .type_id = declared_type,
        .struct_fields = .{ .start = 0, .len = 0 },
    });
    try graph.types.append(allocator, .{ .declared = declaration_id });
    try graph.types.append(allocator, .{ .structural = .{ .fields = .{ .start = 0, .len = 0 } } });
    try graph.modules.append(allocator, .{
        .dir = module_dir,
        .files = .{ .start = 0, .len = 0 },
        .declarations = .{ .start = 0, .len = 1 },
    });
    try graph.nodes.append(allocator, .{
        .source = .{ .file_index = 0, .offset = 18 },
        .ty = input_type,
        .content = .{ .struct_value_literal = .{
            .fields = .{ .start = 0, .len = 0 },
            .ty = input_type,
        } },
    });
    try graph.nodes.append(allocator, .{
        .source = .{ .file_index = 0, .offset = 19 },
        .ty = input_type,
        .content = .{ .bool_literal = false },
    });

    const offsets = [_]globalizer.Offsets{emptyOffsets()};
    var core = core_mod.Resolver{
        .allocator = allocator,
        .graph = &graph,
        .modules = &.{module},
        .offsets = &offsets,
    };
    var resolver: Resolver = .{
        .graph = &graph,
        .modules = &.{module},
        .offsets = &offsets,
        .core = &core,
    };
    const operation = module_entities.PendingOperation{ .resolve_call = .{
        .node = @enumFromInt(1),
        .callee = @enumFromInt(0),
        .input = @enumFromInt(0),
    } };

    try std.testing.expect((try resolver.tryResolve(0, &module, offsets[0], operation)).?);
    const result = graph.nodes.items[1];
    try std.testing.expectEqual(declared_type, result.ty.?);
    try std.testing.expectEqual(declared_type, result.content.struct_value_literal.ty);
    try std.testing.expectEqual(@as(u32, 0), result.content.struct_value_literal.fields.len);
}

fn emptyOffsets() globalizer.Offsets {
    return .{
        .file_base = 0,
        .declaration_base = 0,
        .type_base = 0,
        .function_base = 0,
        .field_base = 0,
        .variant_base = 0,
        .generic_argument_base = 0,
        .binding_base = 0,
        .node_base = 0,
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
