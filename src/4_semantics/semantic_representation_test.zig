const std = @import("std");
const module_sg = @import("module_semantic_graph.zig");
const module_entities = @import("module_semantic_entities.zig");
const module_verify = @import("module_semantic_complete_verify.zig");
const global_verify = @import("global_semantic_verify.zig");
const globalizer = @import("semantic_globalizer.zig");
const primitives = @import("semantic_primitives.zig");
const strings = @import("semantic_strings.zig");

fn makeScalarModule(allocator: std.mem.Allocator, dir: []const u8, type_name_text: []const u8, literal: i64) !module_sg.ModuleSemanticGraph {
    var module: module_sg.ModuleSemanticGraph = .{ .module_dir = try allocator.dupe(u8, dir) };
    errdefer module.deinit(allocator);

    const path = try strings.append(&module.strings, allocator, "main.rg");
    const type_name = try strings.append(&module.strings, allocator, type_name_text);
    const binding_name = try strings.append(&module.strings, allocator, "value");

    try module.file_offsets.append(allocator, .{
        .path = path,
        .declaration_base = 0,
        .declaration_count = 1,
        .type_reference_base = 0,
        .type_reference_count = 0,
        .import_reference_base = 0,
        .import_reference_count = 0,
    });
    try module.declarations.append(allocator, .{
        .kind = .type,
        .name = type_name,
        .source_offset = 1,
        .module_file_index = 0,
        .syntax_node = @enumFromInt(0),
        .type_id = @enumFromInt(0),
    });
    try module.semantic.resolved_types.append(allocator, .{ .declared = @enumFromInt(0) });
    try module.symbol_declarations.append(allocator, @enumFromInt(0));
    try module.symbols.append(allocator, .{
        .name = type_name,
        .declarations = .{ .start = 0, .len = 1 },
    });

    try module.semantic.bindings.append(allocator, .{
        .name = binding_name,
        .source = .{ .file_index = 0, .offset = 4 },
        .ty = @enumFromInt(0),
        .mutability = .constant,
    });
    try module.semantic.nodes.append(allocator, .{ .resolved = .{
        .source = .{ .file_index = 0, .offset = 8 },
        .ty = @enumFromInt(0),
        .content = .{ .int_literal = literal },
    } });
    try module.semantic.nodes.append(allocator, .{ .resolved = .{
        .source = .{ .file_index = 0, .offset = 9 },
        .ty = @enumFromInt(0),
        .content = .{ .binding_use = @enumFromInt(0) },
    } });
    try module.semantic.node_refs.appendSlice(allocator, &.{
        @as(module_entities.ModuleNodeId, @enumFromInt(0)),
        @as(module_entities.ModuleNodeId, @enumFromInt(1)),
    });
    try module.semantic.blocks.append(allocator, .{
        .nodes = .{ .start = 0, .len = 2 },
        .ret_val = @enumFromInt(1),
    });
    try module.semantic.roots.append(allocator, @enumFromInt(0));
    module.semantic.local_semantics_complete = true;

    return module;
}

fn makeInferredChoiceModule(allocator: std.mem.Allocator) !module_sg.ModuleSemanticGraph {
    var module: module_sg.ModuleSemanticGraph = .{ .module_dir = try allocator.dupe(u8, "errors") };
    errdefer module.deinit(allocator);

    const path = try strings.append(&module.strings, allocator, "errors.rg");
    const type_name = try strings.append(&module.strings, allocator, "Reasons");
    const variant_name = try strings.append(&module.strings, allocator, "bad_input");

    try module.file_offsets.append(allocator, .{
        .path = path,
        .declaration_base = 0,
        .declaration_count = 1,
        .type_reference_base = 0,
        .type_reference_count = 0,
        .import_reference_base = 0,
        .import_reference_count = 0,
    });
    try module.declarations.append(allocator, .{
        .kind = .type,
        .name = type_name,
        .source_offset = 2,
        .module_file_index = 0,
        .syntax_node = @enumFromInt(0),
        .type_id = @enumFromInt(0),
    });
    try module.semantic.variants.append(allocator, .{
        .name = variant_name,
        .payload_type = null,
        .source = .{ .file_index = 0, .offset = 6 },
        .value = 0,
    });
    try module.semantic.resolved_types.append(allocator, .{ .inferred_choice = .{
        .identity = 17,
        .kind = .reasons,
        .variants = .{ .start = 0, .len = 1 },
    } });
    try module.symbol_declarations.append(allocator, @enumFromInt(0));
    try module.symbols.append(allocator, .{ .name = type_name, .declarations = .{ .start = 0, .len = 1 } });
    module.semantic.local_semantics_complete = true;
    return module;
}

test "module semantic ids relocate independently into the global graph" {
    const allocator = std.testing.allocator;
    var left = try makeScalarModule(allocator, "left", "Left", 10);
    defer left.deinit(allocator);
    var right = try makeScalarModule(allocator, "right", "Right", 20);
    defer right.deinit(allocator);
    var reasons = try makeInferredChoiceModule(allocator);
    defer reasons.deinit(allocator);

    try module_verify.verifyModule(&left);
    try module_verify.verifyModule(&right);
    try module_verify.verifyModule(&reasons);

    var global = try globalizer.globalize(allocator, &.{ left, right, reasons });
    defer global.deinit(allocator);
    try global_verify.verifyGlobal(&global);

    try std.testing.expectEqual(@as(usize, 3), global.modules.items.len);
    try std.testing.expectEqual(@as(usize, 3), global.declarations.items.len);
    try std.testing.expectEqual(@as(usize, 3), global.types.items.len);
    try std.testing.expectEqual(@as(usize, 2), global.bindings.items.len);
    try std.testing.expectEqual(@as(usize, 4), global.nodes.items.len);

    // Every ModuleSG starts at local declaration/type/binding/node ID 0. The
    // second module must therefore be rebased to the first module's counts.
    try std.testing.expectEqual(@as(u32, 1), @intFromEnum(global.types.items[1].declared));
    try std.testing.expectEqual(@as(u32, 1), @intFromEnum(global.nodes.items[3].content.binding_use));
    try std.testing.expectEqualStrings("Right", global.text(global.declarations.items[1].name));

    const inferred = global.types.items[2].inferred_choice;
    try std.testing.expectEqual(@as(u32, 17), inferred.identity);
    try std.testing.expectEqual(primitives.InferredChoiceKind.reasons, inferred.kind);
    try std.testing.expectEqual(@as(u32, 0), inferred.variants.start);
    try std.testing.expectEqual(@as(u32, 1), inferred.variants.len);

    // Globalization copies and relocates; it does not mutate module-local IDs.
    try std.testing.expectEqual(@as(u32, 0), @intFromEnum((try @import("module_semantic_views.zig").typeView(&right, @enumFromInt(0))).resolved.declared));
}