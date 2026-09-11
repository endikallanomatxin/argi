const std = @import("std");
const module_sg = @import("module/graph.zig");
const module_entities = @import("module/entities.zig");
const module_verify = @import("module/complete_verify.zig");
const global_verify = @import("global/verify.zig");
const globalizer = @import("global/globalizer.zig");
const primitives = @import("primitives/schema.zig");
const strings = @import("primitives/strings.zig");

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
    });
    try module.declarations.append(allocator, .{
        .kind = .type,
        .name = type_name,
        .source_offset = 1,
        .module_file_index = 0,
        .syntax_node = @enumFromInt(0),
        .type_id = @enumFromInt(0),
    });
    try module.semantic.types.append(allocator, .{ .resolved = .{ .declared = @enumFromInt(0) } });
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
    try module.semantic.types.append(allocator, .{ .resolved = .{ .inferred_choice = .{
        .identity = 17,
        .kind = .reasons,
        .variants = .{ .start = 0, .len = 1 },
    } } });
    try module.symbol_declarations.append(allocator, @enumFromInt(0));
    try module.symbols.append(allocator, .{ .name = type_name, .declarations = .{ .start = 0, .len = 1 } });
    module.semantic.local_semantics_complete = true;
    return module;
}

fn makeGenericArrayModule(allocator: std.mem.Allocator) !module_sg.ModuleSemanticGraph {
    var module: module_sg.ModuleSemanticGraph = .{ .module_dir = try allocator.dupe(u8, "generic") };
    errdefer module.deinit(allocator);

    const path = try strings.append(&module.strings, allocator, "generic.rg");
    const type_name = try strings.append(&module.strings, allocator, "Vector");
    const argument_name = try strings.append(&module.strings, allocator, "t");

    try module.file_offsets.append(allocator, .{
        .path = path,
        .declaration_base = 0,
        .declaration_count = 1,
        .type_reference_base = 0,
        .type_reference_count = 0,
    });
    try module.declarations.append(allocator, .{
        .kind = .type,
        .name = type_name,
        .source_offset = 1,
        .module_file_index = 0,
        .syntax_node = @enumFromInt(0),
        .type_id = @enumFromInt(1),
        .generic_parameter_count = 1,
    });
    try module.symbol_declarations.append(allocator, @enumFromInt(0));
    try module.symbols.append(allocator, .{ .name = type_name, .declarations = .{ .start = 0, .len = 1 } });

    try module.semantic.types.append(allocator, .{ .resolved = .{ .builtin = .Int32 } });
    try module.semantic.generic_arguments.append(allocator, .{
        .name = argument_name,
        .value = .{ .type = @enumFromInt(0) },
    });
    try module.semantic.types.append(allocator, .{ .resolved = .{ .generic = .{
        .base = @enumFromInt(0),
        .arguments = .{ .start = 0, .len = 1 },
    } } });
    try module.semantic.generic_instances.append(allocator, .{
        .type_id = @enumFromInt(1),
        .shape = .{ .array = .{
            .length = 4,
            .element = @enumFromInt(0),
        } },
    });
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
    try std.testing.expectEqual(@as(u32, 0), @intFromEnum((try @import("module/views.zig").typeView(&right, @enumFromInt(0))).resolved.declared));
}

test "generic identities and materialized shapes relocate together" {
    const allocator = std.testing.allocator;
    var scalar = try makeScalarModule(allocator, "prefix", "Prefix", 1);
    defer scalar.deinit(allocator);
    var generic = try makeGenericArrayModule(allocator);
    defer generic.deinit(allocator);

    try module_verify.verifyModule(&generic);
    var global = try globalizer.globalize(allocator, &.{ scalar, generic });
    defer global.deinit(allocator);
    try global_verify.verifyGlobal(&global);

    // The prefix module contributes one type, so generic-local type 0/1 become
    // global type 1/2. Its declaration is global declaration 1.
    const identity = global.types.items[2].generic;
    try std.testing.expectEqual(@as(u32, 1), @intFromEnum(identity.base));
    try std.testing.expectEqual(@as(u32, 0), identity.arguments.start);
    try std.testing.expectEqual(@as(u32, 1), identity.arguments.len);
    try std.testing.expectEqual(@as(u32, 1), @intFromEnum(global.generic_arguments.items[0].value.type));

    try std.testing.expectEqual(@as(usize, 1), global.generic_instances.items.len);
    const instance = global.generic_instances.items[0];
    try std.testing.expectEqual(@as(u32, 2), @intFromEnum(instance.type_id));
    try std.testing.expectEqual(@as(u64, 4), instance.shape.array.length);
    try std.testing.expectEqual(@as(u32, 1), @intFromEnum(instance.shape.array.element));
}

test "equal symbol names remain owned by different modules" {
    const allocator = std.testing.allocator;
    var left = try makeScalarModule(allocator, "left", "Shared", 1);
    defer left.deinit(allocator);
    var right = try makeScalarModule(allocator, "right", "Shared", 2);
    defer right.deinit(allocator);

    var global = try globalizer.globalize(allocator, &.{ left, right });
    defer global.deinit(allocator);
    try global_verify.verifyGlobal(&global);

    try std.testing.expectEqual(@as(usize, 2), global.symbols.items.len);
    try std.testing.expectEqualStrings("Shared", global.text(global.symbols.items[0].name));
    try std.testing.expectEqualStrings("Shared", global.text(global.symbols.items[1].name));
    try std.testing.expectEqual(@as(u32, 0), @intFromEnum(global.moduleForSymbol(global.symbols.items[0]).?));
    try std.testing.expectEqual(@as(u32, 1), @intFromEnum(global.moduleForSymbol(global.symbols.items[1]).?));
}
