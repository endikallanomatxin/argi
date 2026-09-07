const std = @import("std");
const diagnostic = @import("../1_base/diagnostic.zig");
const source_db = @import("../1_base/source_db.zig");
const source_files = @import("../1_base/source_files.zig");
const syn = @import("../3_syntax/syntax_tree.zig");
const syntaxer = @import("../3_syntax/syntaxer.zig");
const tokenizer = @import("../2_tokens/tokenizer.zig");
const module_graph = @import("module_semantic_graph.zig");
const global_builder = @import("global_semantic_graph_builder.zig");

fn parseSource(allocator: std.mem.Allocator, source: []const u8, file_id: source_db.FileId) !syn.FileSyntaxTree {
    const files = [_]source_files.SourceFile{ .{ .path = "a.rg", .code = source }, .{ .path = "b.rg", .code = source } };
    var diagnostics = diagnostic.Diagnostics.init(&allocator, &files);
    defer diagnostics.deinit();
    var tokenizer_context = tokenizer.Tokenizer.init(allocator, &diagnostics, source, file_id);
    defer tokenizer_context.deinit();
    _ = try tokenizer_context.tokenize();
    var context = syntaxer.Syntaxer.initFile(allocator, syn.FileSyntaxTree.initOwnedTokens(file_id, tokenizer_context.takeTokens()), source, &diagnostics);
    defer context.deinit();
    return try context.parse();
}

test "module semantic graph owns declarations from all direct files" {
    const allocator = std.testing.allocator;
    const first_source = "Point : Type = (\n .x: Int32\n)\n";
    const second_source = "distance(.point: Point) -> () := {}\n";
    var first = try parseSource(allocator, first_source, @enumFromInt(0));
    defer first.deinit(allocator);
    var second = try parseSource(allocator, second_source, @enumFromInt(1));
    defer second.deinit(allocator);
    var graph = try module_graph.build(allocator, "geometry", &.{
        .{ .path = "geometry/a.rg", .tree = &first, .source = first_source },
        .{ .path = "geometry/b.rg", .tree = &second, .source = second_source },
    });
    defer graph.deinit(allocator);

    try std.testing.expectEqualStrings("geometry", graph.module_dir);
    try std.testing.expectEqual(@as(usize, 2), graph.file_offsets.items.len);
    try std.testing.expectEqual(@as(usize, 2), graph.declarations.items.len);
    try std.testing.expectEqualStrings("Point", graph.text(graph.declarations.items[0].name));
    try std.testing.expectEqualStrings("distance", graph.text(graph.declarations.items[1].name));
    try std.testing.expectEqual(@as(u32, 0), graph.declarations.items[0].module_file_index);
    try std.testing.expectEqual(@as(u32, 1), graph.declarations.items[1].module_file_index);
    const point_declarations = graph.declarationsNamed("Point");
    try std.testing.expectEqual(@as(usize, 1), point_declarations.len);
    try std.testing.expectEqual(@as(u32, 0), @intFromEnum(point_declarations[0]));
    var resolved_point = false;
    for (graph.type_references.items) |reference| {
        if (std.mem.eql(u8, graph.text(reference.name), "Point")) {
            try std.testing.expectEqual(point_declarations[0], reference.resolution.module);
            resolved_point = true;
        }
    }
    try std.testing.expect(resolved_point);
    try std.testing.expectEqual(@as(usize, 1), graph.functions.items.len);
    const distance_interface = graph.functions.items[0];
    try std.testing.expectEqual(@as(u32, 1), @intFromEnum(distance_interface.declaration));
    try std.testing.expectEqual(@as(u32, 1), distance_interface.input.len);
    try std.testing.expectEqual(@as(u32, 0), distance_interface.output.len);
    const point_field = graph.fields.items[distance_interface.input.start];
    try std.testing.expectEqualStrings("point", graph.text(point_field.name));
    try std.testing.expectEqual(module_graph.ModuleType{ .declared = @enumFromInt(0) }, graph.types.items[@intFromEnum(point_field.ty)]);
    const point_fields = graph.declarations.items[0].struct_fields.?;
    try std.testing.expectEqual(@as(u32, 1), point_fields.len);
    try std.testing.expectEqualStrings("x", graph.text(graph.fields.items[point_fields.start].name));

    const sources = [_]source_files.SourceFile{ .{ .path = "geometry/a.rg", .code = first_source }, .{ .path = "geometry/b.rg", .code = second_source } };
    var db = try source_db.SourceDb.init(allocator, &sources);
    defer db.deinit(allocator);
    var merged = try global_builder.mergeModuleGraphs(allocator, &.{graph}, &db);
    defer merged.deinit(allocator);
    for (merged.type_references.items) |reference| {
        if (std.mem.eql(u8, merged.text(reference.name), "Point")) {
            try std.testing.expectEqual(@as(u32, 0), @intFromEnum(reference.resolution.module));
        }
    }
}

test "global builder consumes module graphs and preserves file provenance" {
    const allocator = std.testing.allocator;
    const source = "value := 1\n";
    var first = try parseSource(allocator, source, @enumFromInt(0));
    defer first.deinit(allocator);
    var second = try parseSource(allocator, source, @enumFromInt(1));
    defer second.deinit(allocator);
    var modules = [_]module_graph.ModuleSemanticGraph{
        try module_graph.build(allocator, "one", &.{.{ .path = "one/main.rg", .tree = &first, .source = source }}),
        try module_graph.build(allocator, "two", &.{.{ .path = "two/main.rg", .tree = &second, .source = source }}),
    };
    defer for (&modules) |*module| module.deinit(allocator);
    const sources = [_]source_files.SourceFile{ .{ .path = "one/main.rg", .code = source }, .{ .path = "two/main.rg", .code = source } };
    var db = try source_db.SourceDb.init(allocator, &sources);
    defer db.deinit(allocator);
    var merged = try global_builder.mergeModuleGraphs(allocator, &modules, &db);
    defer merged.deinit(allocator);

    const second_id = merged.globalDeclId(1, @enumFromInt(0));
    try std.testing.expectEqualStrings("value", merged.text(merged.declaration(second_id).name));
    try std.testing.expectEqual(@as(u32, 1), merged.declaration(second_id).file_index);
    try std.testing.expectEqual(@as(u32, 1), merged.file_offsets.items[1].declaration_base);
}

test "module symbol index retains overload candidates" {
    const allocator = std.testing.allocator;
    const first_source = "convert(.value: Int32) -> () := {}\n";
    const second_source = "convert(.value: Bool) -> () := {}\n";
    var first = try parseSource(allocator, first_source, @enumFromInt(0));
    defer first.deinit(allocator);
    var second = try parseSource(allocator, second_source, @enumFromInt(1));
    defer second.deinit(allocator);
    var graph = try module_graph.build(allocator, "conversion", &.{
        .{ .path = "conversion/a.rg", .tree = &first, .source = first_source },
        .{ .path = "conversion/b.rg", .tree = &second, .source = second_source },
    });
    defer graph.deinit(allocator);

    const declarations = graph.declarationsNamed("convert");
    try std.testing.expectEqual(@as(usize, 2), declarations.len);
    try std.testing.expectEqual(.function, graph.declaration(declarations[0]).kind);
    try std.testing.expectEqual(.function, graph.declaration(declarations[1]).kind);
}

test "module callable interfaces intern pointer and array types" {
    const allocator = std.testing.allocator;
    const source = "consume(.first: [2]&Int32, .second: [2]&Int32) -> () := {}\n";
    var tree = try parseSource(allocator, source, @enumFromInt(0));
    defer tree.deinit(allocator);
    var graph = try module_graph.build(allocator, "arrays", &.{.{ .path = "arrays/main.rg", .tree = &tree, .source = source }});
    defer graph.deinit(allocator);

    const interface = graph.functions.items[0];
    const first = graph.fields.items[interface.input.start];
    const second = graph.fields.items[interface.input.start + 1];
    try std.testing.expectEqual(first.ty, second.ty);
    const array = graph.types.items[@intFromEnum(first.ty)].array;
    try std.testing.expectEqual(@as(u64, 2), array.length);
    const pointer = graph.types.items[@intFromEnum(array.element)].pointer;
    try std.testing.expectEqual(.read_only, pointer.mutability);
    try std.testing.expectEqual(module_graph.BuiltinType.Int32, graph.types.items[@intFromEnum(pointer.child)].builtin);
}

test "module callable interfaces lower literal Array generic types" {
    const allocator = std.testing.allocator;
    const source = "consume(.values: Array#(.n = 3, .t: Int32)) -> () := {}\n";
    var tree = try parseSource(allocator, source, @enumFromInt(0));
    defer tree.deinit(allocator);
    var graph = try module_graph.build(allocator, "generic_arrays", &.{.{ .path = "generic_arrays/main.rg", .tree = &tree, .source = source }});
    defer graph.deinit(allocator);

    const interface = graph.functions.items[0];
    const array = graph.types.items[@intFromEnum(graph.fields.items[interface.input.start].ty)].array;
    try std.testing.expectEqual(@as(u64, 3), array.length);
    try std.testing.expectEqual(module_graph.BuiltinType.Int32, graph.types.items[@intFromEnum(array.element)].builtin);
}

test "module callable interfaces preserve nullable types" {
    const allocator = std.testing.allocator;
    const source = "find(.fallback: ?Int32) -> (.result: ?Int32) := { result = fallback }\n";
    var tree = try parseSource(allocator, source, @enumFromInt(0));
    defer tree.deinit(allocator);
    var graph = try module_graph.build(allocator, "nullable", &.{.{ .path = "nullable/main.rg", .tree = &tree, .source = source }});
    defer graph.deinit(allocator);

    const interface = graph.functions.items[0];
    const input = graph.fields.items[interface.input.start];
    const output = graph.fields.items[interface.output.start];
    try std.testing.expectEqual(input.ty, output.ty);
    const child = graph.types.items[@intFromEnum(input.ty)].nullable;
    try std.testing.expectEqual(module_graph.BuiltinType.Int32, graph.types.items[@intFromEnum(child)].builtin);
}

test "module callable interfaces preserve inferred errable types" {
    const allocator = std.testing.allocator;
    const source = "run() -> !Int32 := { return 1 }\n";
    var tree = try parseSource(allocator, source, @enumFromInt(0));
    defer tree.deinit(allocator);
    var graph = try module_graph.build(allocator, "errable", &.{.{ .path = "errable/main.rg", .tree = &tree, .source = source }});
    defer graph.deinit(allocator);

    const interface = graph.functions.items[0];
    const output = graph.fields.items[interface.output.start];
    const child = graph.types.items[@intFromEnum(output.ty)].inferred_errable;
    try std.testing.expectEqual(module_graph.BuiltinType.Int32, graph.types.items[@intFromEnum(child)].builtin);
}

test "module callable interfaces preserve anonymous structural types" {
    const allocator = std.testing.allocator;
    const source = "read(.value: (.nested: (.number: Int32))) -> (.result: (.nested: (.number: Int32))) := { result = value }\n";
    var tree = try parseSource(allocator, source, @enumFromInt(0));
    defer tree.deinit(allocator);
    var graph = try module_graph.build(allocator, "structural", &.{.{ .path = "structural/main.rg", .tree = &tree, .source = source }});
    defer graph.deinit(allocator);

    const interface = graph.functions.items[0];
    for ([_]module_graph.Field{ graph.fields.items[interface.input.start], graph.fields.items[interface.output.start] }) |field| {
        const shape = graph.types.items[@intFromEnum(field.ty)].structural;
        try std.testing.expectEqual(@as(u32, 1), shape.len);
        const nested = graph.structural_fields.items[shape.start];
        try std.testing.expectEqualStrings("nested", graph.text(nested.name));
        const nested_shape = graph.types.items[@intFromEnum(nested.ty)].structural;
        try std.testing.expectEqual(@as(u32, 1), nested_shape.len);
        const number = graph.structural_fields.items[nested_shape.start];
        try std.testing.expectEqualStrings("number", graph.text(number.name));
        try std.testing.expectEqual(module_graph.BuiltinType.Int32, graph.types.items[@intFromEnum(number.ty)].builtin);
    }
}

test "anonymous structural types retain default expression provenance" {
    const allocator = std.testing.allocator;
    const source = "read(.value: (.number: Int32 = 4)) -> () := {}\n";
    var tree = try parseSource(allocator, source, @enumFromInt(0));
    defer tree.deinit(allocator);
    var graph = try module_graph.build(allocator, "structural_defaults", &.{.{ .path = "structural_defaults/main.rg", .tree = &tree, .source = source }});
    defer graph.deinit(allocator);

    const interface = graph.functions.items[0];
    const input = graph.fields.items[interface.input.start];
    const shape = graph.types.items[@intFromEnum(input.ty)].structural;
    const number = graph.structural_fields.items[shape.start];
    try std.testing.expect(number.has_default);
    try std.testing.expect(number.default_value != null);
    try std.testing.expectEqual(@as(u32, 0), number.module_file_index);

    const sources = [_]source_files.SourceFile{.{ .path = "structural_defaults/main.rg", .code = source }};
    var db = try source_db.SourceDb.init(allocator, &sources);
    defer db.deinit(allocator);
    var merged = try global_builder.mergeModuleGraphs(allocator, &.{graph}, &db);
    defer merged.deinit(allocator);
    const global_input = merged.fields.items[merged.functions.items[0].input.start];
    const global_shape = merged.types.items[@intFromEnum(global_input.ty)].structural;
    const global_number = merged.structural_fields.items[global_shape.start];
    try std.testing.expect(global_number.default_value != null);
    try std.testing.expectEqual(@as(u32, 0), global_number.file_index);
}

test "module callable interfaces preserve anonymous choice types" {
    const allocator = std.testing.allocator;
    const source = "inspect(.value: (..some Int32, ..none)) -> () := {}\n";
    var tree = try parseSource(allocator, source, @enumFromInt(0));
    defer tree.deinit(allocator);
    var graph = try module_graph.build(allocator, "choices", &.{.{ .path = "choices/main.rg", .tree = &tree, .source = source }});
    defer graph.deinit(allocator);

    const interface = graph.functions.items[0];
    const input = graph.fields.items[interface.input.start];
    const shape = graph.types.items[@intFromEnum(input.ty)].structural_choice;
    try std.testing.expectEqual(@as(u32, 2), shape.len);
    const some = graph.structural_choice_variants.items[shape.start];
    try std.testing.expectEqualStrings("some", graph.text(some.name));
    try std.testing.expectEqual(module_graph.BuiltinType.Int32, graph.types.items[@intFromEnum(some.payload_type.?)].builtin);
    try std.testing.expectEqualStrings("none", graph.text(graph.structural_choice_variants.items[shape.start + 1].name));
}

test "module callable interfaces normalize choice unions" {
    const allocator = std.testing.allocator;
    const source = "Left : Type = (..first, ..shared)\nRight : Type = (..shared, ..second)\nmerge() -> (.result: choice_union#(.a: Left, .b: Right)) := { result = ..shared }\n";
    var tree = try parseSource(allocator, source, @enumFromInt(0));
    defer tree.deinit(allocator);
    var graph = try module_graph.build(allocator, "choice_unions", &.{.{ .path = "choice_unions/main.rg", .tree = &tree, .source = source }});
    defer graph.deinit(allocator);

    const interface = graph.functions.items[0];
    const output = graph.fields.items[interface.output.start];
    const shape = graph.types.items[@intFromEnum(output.ty)].structural_choice;
    try std.testing.expectEqual(@as(u32, 3), shape.len);
    const variants = graph.structural_choice_variants.items[shape.start..][0..shape.len];
    try std.testing.expectEqualStrings("first", graph.text(variants[0].name));
    try std.testing.expectEqualStrings("second", graph.text(variants[1].name));
    try std.testing.expectEqualStrings("shared", graph.text(variants[2].name));
}

test "module callable interfaces preserve type-only generic instantiations" {
    const allocator = std.testing.allocator;
    const type_source = "Box#(.t: Type) : Type = (.value: t)\n";
    const function_source = "read(.box: Box#(.t: Int32)) -> () := {}\n";
    var type_tree = try parseSource(allocator, type_source, @enumFromInt(0));
    defer type_tree.deinit(allocator);
    var function_tree = try parseSource(allocator, function_source, @enumFromInt(1));
    defer function_tree.deinit(allocator);
    var graph = try module_graph.build(allocator, "generics", &.{
        .{ .path = "generics/type.rg", .tree = &type_tree, .source = type_source },
        .{ .path = "generics/function.rg", .tree = &function_tree, .source = function_source },
    });
    defer graph.deinit(allocator);

    const interface = graph.functions.items[0];
    const input = graph.fields.items[interface.input.start];
    const generic = graph.types.items[@intFromEnum(input.ty)].generic;
    try std.testing.expectEqual(@as(u32, 0), @intFromEnum(generic.base));
    try std.testing.expectEqual(@as(u32, 1), generic.arguments.len);
    const argument = graph.generic_type_arguments.items[generic.arguments.start];
    try std.testing.expectEqualStrings("t", graph.text(argument.name));
    try std.testing.expectEqual(module_graph.BuiltinType.Int32, graph.types.items[@intFromEnum(argument.ty)].builtin);

    const other_source = "Box#(.t: Type) : Type = (.other: t)\n";
    var other_tree = try parseSource(allocator, other_source, @enumFromInt(2));
    defer other_tree.deinit(allocator);
    var other = try module_graph.build(allocator, "other", &.{.{ .path = "other/type.rg", .tree = &other_tree, .source = other_source }});
    defer other.deinit(allocator);
    const sources = [_]source_files.SourceFile{
        .{ .path = "generics/type.rg", .code = type_source },
        .{ .path = "generics/function.rg", .code = function_source },
        .{ .path = "other/type.rg", .code = other_source },
    };
    var db = try source_db.SourceDb.init(allocator, &sources);
    defer db.deinit(allocator);
    var merged = try global_builder.mergeModuleGraphs(allocator, &.{ graph, other }, &db);
    defer merged.deinit(allocator);
    const read = merged.declarations.items[1];
    const global_input = merged.fields.items[merged.functions.items[@intFromEnum(read.function_id.?)].input.start];
    try std.testing.expectEqual(@as(u32, 0), @intFromEnum(merged.types.items[@intFromEnum(global_input.ty)].generic.base));
}

test "module graph builds and relocates nominal choice variants" {
    const allocator = std.testing.allocator;
    const source = "Result : Type = (\n    ..ok Int32\n    ..done\n)\n";
    var tree = try parseSource(allocator, source, @enumFromInt(0));
    defer tree.deinit(allocator);
    var graph = try module_graph.build(allocator, "results", &.{.{ .path = "results/main.rg", .tree = &tree, .source = source }});
    defer graph.deinit(allocator);

    const range = graph.declarations.items[0].choice_variants.?;
    try std.testing.expectEqual(@as(u32, 2), range.len);
    const ok = graph.choice_variant_entries.items[range.start];
    try std.testing.expectEqualStrings("ok", graph.text(ok.name));
    try std.testing.expectEqual(module_graph.BuiltinType.Int32, graph.types.items[@intFromEnum(ok.payload_type.?)].builtin);
    const done = graph.choice_variant_entries.items[range.start + 1];
    try std.testing.expectEqualStrings("done", graph.text(done.name));
    try std.testing.expectEqual(@as(?module_graph.ModuleTypeId, null), done.payload_type);

    const sources = [_]source_files.SourceFile{.{ .path = "results/main.rg", .code = source }};
    var db = try source_db.SourceDb.init(allocator, &sources);
    defer db.deinit(allocator);
    var merged = try global_builder.mergeModuleGraphs(allocator, &.{graph}, &db);
    defer merged.deinit(allocator);
    const global_range = merged.declarations.items[0].choice_variants.?;
    try std.testing.expectEqualStrings("ok", merged.text(merged.choice_variant_entries.items[global_range.start].name));
    try std.testing.expectEqual(global_builder.GlobalType{ .builtin = .Int32 }, merged.types.items[@intFromEnum(merged.choice_variant_entries.items[global_range.start].payload_type.?)]);
}

test "module type references distinguish builtin and external requirements" {
    const allocator = std.testing.allocator;
    const source = "inspect(.local: Int32, .remote: dep.Value) -> () := {}\n";
    var tree = try parseSource(allocator, source, @enumFromInt(0));
    defer tree.deinit(allocator);
    var graph = try module_graph.build(allocator, "consumer", &.{.{ .path = "consumer/main.rg", .tree = &tree, .source = source }});
    defer graph.deinit(allocator);

    var found_builtin = false;
    var found_external = false;
    for (graph.type_references.items) |reference| {
        const name = graph.text(reference.name);
        if (std.mem.eql(u8, name, "Int32")) {
            try std.testing.expectEqual(module_graph.BuiltinType.Int32, reference.resolution.builtin);
            found_builtin = true;
        } else if (std.mem.eql(u8, name, "Value")) {
            try std.testing.expect(reference.resolution == .external);
            try std.testing.expectEqualStrings("dep", graph.text(reference.qualifier.?));
            found_external = true;
        }
    }
    try std.testing.expect(found_builtin and found_external);
    try std.testing.expectEqual(@as(usize, 0), graph.functions.items.len);
}

test "module semantic graph owns stable file provenance" {
    const allocator = std.testing.allocator;
    const source = "value := 1\n";
    const path = try allocator.dupe(u8, "owned/main.rg");
    var tree = try parseSource(allocator, source, @enumFromInt(0));
    defer tree.deinit(allocator);
    var graph = try module_graph.build(allocator, "owned", &.{.{ .path = path, .tree = &tree, .source = source }});
    allocator.free(path);
    defer graph.deinit(allocator);

    try std.testing.expectEqualStrings("owned", graph.module_dir);
    try std.testing.expectEqualStrings("main.rg", graph.text(graph.file_offsets.items[0].path));
}
