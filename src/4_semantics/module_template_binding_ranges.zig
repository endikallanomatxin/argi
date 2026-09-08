const std = @import("std");
const graph_mod = @import("module_semantic_graph.zig");
const ir = @import("module_semantic_template_ir.zig");

/// `module_template_lowerer` emits interface bindings in template declaration
/// order: all inputs followed by all outputs. Record those ranges explicitly so
/// GlobalSema never relies on global table position or FileST when instantiating.
pub fn attach(graph: *graph_mod.ModuleSemanticGraph) !void {
    var cursor: u32 = 0;
    for (graph.semantic.templates.generic_function_templates.items) |*template| {
        const input_count = try fieldCount(graph, template.input);
        const output_count = try fieldCount(graph, template.output);
        if (@as(usize, cursor) + input_count + output_count > graph.semantic.templates.ir.bindings.items.len)
            return error.InvalidTemplateBindingLayout;
        template.input_bindings = .{ .start = cursor, .len = @intCast(input_count) };
        cursor += @intCast(input_count);
        template.output_bindings = .{ .start = cursor, .len = @intCast(output_count) };
        cursor += @intCast(output_count);
    }
}

fn fieldCount(graph: *const graph_mod.ModuleSemanticGraph, id: ir.TemplateTypeId) !usize {
    const ty = graph.semantic.templates.ir.types.items[@intFromEnum(id)];
    return switch (ty) {
        .resolved => |resolved| switch (resolved) {
            .structural => |shape| shape.fields.len,
            else => 1,
        },
        else => 1,
    };
}

test "template binding ranges are explicit semantic state" {
    const allocator = std.testing.allocator;
    var graph: graph_mod.ModuleSemanticGraph = .{ .module_dir = try allocator.dupe(u8, "demo") };
    defer graph.deinit(allocator);
    const storage = &graph.semantic.templates;
    try storage.ir.fields.append(allocator, .{
        .name = .{ .start = 0, .len = 0 }, .ty = @enumFromInt(1),
        .source = .{ .file_index = 0, .offset = 0 },
    });
    try storage.ir.types.append(allocator, .{ .resolved = .{ .structural = .{ .fields = .{ .start = 0, .len = 1 } } } });
    try storage.ir.types.append(allocator, .{ .concrete = @enumFromInt(0) });
    try storage.ir.bindings.append(allocator, .{
        .name = .{ .start = 0, .len = 0 }, .source = .{ .file_index = 0, .offset = 0 },
        .ty = @enumFromInt(1), .mutability = .constant,
    });
    try storage.generic_function_templates.append(allocator, .{
        .declaration = @enumFromInt(0), .parameters = .{ .start = 0, .len = 0 },
        .input = @enumFromInt(0), .output = @enumFromInt(0), .body = null,
    });
    try attach(&graph);
    try std.testing.expectEqual(@as(u32, 1), storage.generic_function_templates.items[0].input_bindings.len);
}
