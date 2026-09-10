const std = @import("std");
const diagnostic = @import("../../1_base/diagnostic.zig");
const source_db = @import("../../1_base/source_db.zig");
const source_files = @import("../../1_base/source_files.zig");
const syn = @import("../../3_syntax/syntax_tree.zig");
const syntaxer = @import("../../3_syntax/syntaxer.zig");
const tokenizer = @import("../../2_tokens/tokenizer.zig");
const module_graph = @import("graph.zig");
const initializer_lowerer = @import("initializer_lowerer.zig");
const parameterized_lowerer = @import("parameterized/lowerer.zig");

test "deferred struct definitions retain fields with external generic types" {
    const allocator = std.testing.allocator;
    const source = "Holder : Type = (.value: ExternalBox#(.t: Int32))\n";
    var tree = try parseSource(allocator, source, @enumFromInt(0));
    defer tree.deinit(allocator);
    const inputs = [_]module_graph.FileInput{.{ .path = "holder/main.rg", .tree = &tree, .source = source }};
    var graph = try module_graph.build(allocator, "holder", &inputs);
    defer graph.deinit(allocator);

    try std.testing.expectEqual(@as(?module_graph.FieldRange, null), graph.declarations.items[0].struct_fields);
    _ = try initializer_lowerer.lower(allocator, &graph, &inputs);

    const fields = graph.declarations.items[0].struct_fields.?;
    try std.testing.expectEqual(@as(u32, 1), fields.len);
    const field = try @import("views.zig").fieldView(&graph, @enumFromInt(fields.start));
    try std.testing.expectEqualStrings("value", graph.text(field.name));
    try std.testing.expect((try @import("views.zig").typeView(&graph, field.ty)) == .external);
}

test "deferred function interfaces retain external parameter types" {
    const allocator = std.testing.allocator;
    const source = "consume(.value: ExternalValue) -> () := {}\n";
    var tree = try parseSource(allocator, source, @enumFromInt(0));
    defer tree.deinit(allocator);
    const inputs = [_]module_graph.FileInput{.{ .path = "consumer/main.rg", .tree = &tree, .source = source }};
    var graph = try module_graph.build(allocator, "consumer", &inputs);
    defer graph.deinit(allocator);

    try std.testing.expectEqual(@as(?module_graph.ModuleFunctionId, null), graph.declarations.items[0].function_id);
    _ = try initializer_lowerer.lower(allocator, &graph, &inputs);

    const function = graph.functions.items[@intFromEnum(graph.declarations.items[0].function_id.?)];
    try std.testing.expectEqual(@as(u32, 1), function.input.len);
    const field = try @import("views.zig").fieldView(&graph, @enumFromInt(function.input.start));
    try std.testing.expect((try @import("views.zig").typeView(&graph, field.ty)) == .external);
}

test "constrained generic parameters remain type parameters" {
    const allocator = std.testing.allocator;
    const source =
        "Capability : Abstract = ()\n" ++
        "Box#(.t: Type: Capability) : Type = (.value: t)\n";
    var tree = try parseSource(allocator, source, @enumFromInt(0));
    defer tree.deinit(allocator);
    const inputs = [_]module_graph.FileInput{.{ .path = "box/main.rg", .tree = &tree, .source = source }};
    var graph = try module_graph.build(allocator, "box", &inputs);
    defer graph.deinit(allocator);

    _ = try parameterized_lowerer.lower(allocator, &graph, &inputs);
    const parameterized = graph.semantic.parameterized_storage.parameterized_types.items[0];
    try std.testing.expectEqual(.type, graph.semantic.parameterized_storage.comptime_parameters.items[parameterized.parameters.start].kind);
}

test "parameterized pools retain immediate children across recursive lowering" {
    const allocator = std.testing.allocator;
    const source =
        "Box#(.t: Type): Type = (.value: t)\n" ++
        "Nested#(.t: Type): Type = (.first: (.inner: t), .second: Box#(.t: Box#(.t = t)), .third: (..outer (..inner t)))\n";
    var tree = try parseSource(allocator, source, @enumFromInt(0));
    defer tree.deinit(allocator);
    const inputs = [_]module_graph.FileInput{.{ .path = "parameterized_storage/main.rg", .tree = &tree, .source = source }};
    var graph = try module_graph.build(allocator, "parameterized_storage", &inputs);
    defer graph.deinit(allocator);
    _ = try parameterized_lowerer.lower(allocator, &graph, &inputs);
    const parameterized_storage = &graph.semantic.parameterized_storage;
    const ir = &parameterized_storage.ir;
    const body = parameterized_storage.parameterized_types.items[1].body;
    const fields = ir.types.items[@intFromEnum(body)].resolved.structural.fields;
    try std.testing.expectEqual(@as(u32, 3), fields.len);
    try std.testing.expectEqualStrings("first", graph.text(ir.fields.items[fields.start].name));
    try std.testing.expectEqualStrings("second", graph.text(ir.fields.items[fields.start + 1].name));
    try std.testing.expectEqualStrings("third", graph.text(ir.fields.items[fields.start + 2].name));
    const generic = ir.types.items[@intFromEnum(ir.fields.items[fields.start + 1].ty)].resolved.generic;
    const inner = ir.generic_arguments.items[generic.arguments.start].value.type;
    const inner_generic = ir.types.items[@intFromEnum(inner)].resolved.generic;
    const parameter = ir.generic_arguments.items[inner_generic.arguments.start].value.type;
    try std.testing.expect(ir.types.items[@intFromEnum(parameter)] == .parameter);
    const choice = ir.types.items[@intFromEnum(ir.fields.items[fields.start + 2].ty)].resolved.structural_choice;
    try std.testing.expectEqualStrings("outer", graph.text(ir.variants.items[choice.variants.start].semantic.name));

    const globalizer = @import("../global/globalizer.zig");
    const core = @import("../global/core.zig");
    const generics = @import("../global/generics.zig");
    const global_sg = @import("../global/graph.zig");
    var relocation = try globalizer.relocate(allocator, &.{graph}, .allow_holes);
    defer relocation.deinit(allocator);
    var core_resolver: core.Resolver = .{ .allocator = allocator, .graph = &relocation.graph, .modules = &.{graph}, .offsets = relocation.offsets.items };
    var resolver: generics.Resolver = .{ .allocator = allocator, .graph = &relocation.graph, .modules = &.{graph}, .offsets = relocation.offsets.items, .core = &core_resolver };
    var substitutions = try generics.Resolver.Bindings.init(allocator, parameterized_storage.comptime_parameters.items.len);
    defer substitutions.deinit(allocator);
    const int_type: global_sg.GlobalTypeId = @enumFromInt(@as(u32, @intCast(relocation.graph.types.items.len)));
    try relocation.graph.types.append(allocator, .{ .builtin = .Int32 });
    substitutions.types[parameterized_storage.parameterized_types.items[1].parameters.start] = int_type;
    const instantiated = try resolver.instantiateParameterizedType(0, body, &substitutions, null);
    const global_fields = relocation.graph.types.items[@intFromEnum(instantiated)].structural.fields;
    try std.testing.expectEqualStrings("first", relocation.graph.text(relocation.graph.fields.items[global_fields.start].name));
    try std.testing.expectEqualStrings("second", relocation.graph.text(relocation.graph.fields.items[global_fields.start + 1].name));
    const global_generic = relocation.graph.types.items[@intFromEnum(relocation.graph.fields.items[global_fields.start + 1].ty)].generic;
    const global_inner = relocation.graph.generic_arguments.items[global_generic.arguments.start].value.type;
    const global_inner_generic = relocation.graph.types.items[@intFromEnum(global_inner)].generic;
    try std.testing.expectEqual(int_type, relocation.graph.generic_arguments.items[global_inner_generic.arguments.start].value.type);
    const global_choice = relocation.graph.types.items[@intFromEnum(relocation.graph.fields.items[global_fields.start + 2].ty)].structural_choice;
    try std.testing.expectEqualStrings("outer", relocation.graph.text(relocation.graph.variants.items[global_choice.variants.start].name));
}

test "parameterized bodies own call metadata and binding ranges during lowering" {
    const allocator = std.testing.allocator;
    const source =
        "first#(.t: Type)(.value: t) -> (.result: t) := {\n" ++
        " local ::= value\n if true { result = local }\n result = second#(.t = t)(.value = local)\n}\n" ++
        "second#(.t: Type)(.value: t) -> (.result: t) := { result = value }\n";
    var tree = try parseSource(allocator, source, @enumFromInt(0));
    defer tree.deinit(allocator);
    const inputs = [_]module_graph.FileInput{.{ .path = "parameterized_storage/main.rg", .tree = &tree, .source = source }};
    var graph = try module_graph.build(allocator, "parameterized_storage", &inputs);
    defer graph.deinit(allocator);
    _ = try parameterized_lowerer.lower(allocator, &graph, &inputs);
    const parameterized_storage = &graph.semantic.parameterized_storage;
    const first = parameterized_storage.parameterized_functions.items[0];
    const second = parameterized_storage.parameterized_functions.items[1];
    try std.testing.expectEqual(@as(u32, 0), first.input_bindings.start);
    try std.testing.expectEqual(@as(u32, 1), first.output_bindings.start);
    try std.testing.expectEqual(@as(u32, 3), second.input_bindings.start);
    const body = parameterized_storage.ir.blocks.items[@intFromEnum(first.body.?)];
    try std.testing.expectEqual(@as(u32, 3), body.nodes.len);
    const statements = parameterized_storage.ir.node_refs.items[body.nodes.start..][0..body.nodes.len];
    try std.testing.expect(parameterized_storage.ir.nodes.items[@intFromEnum(statements[0])].resolved.content == .binding_declaration);
    const assignment = parameterized_storage.ir.nodes.items[@intFromEnum(statements[2])].resolved.content.assignment;
    const pending = parameterized_storage.ir.nodes.items[@intFromEnum(assignment.value)].pending;
    const call = parameterized_storage.ir.pending.items[@intFromEnum(pending)].resolve_expression;
    try std.testing.expectEqualStrings("second", graph.text(call.name.?));
    try std.testing.expectEqual(@as(u32, 1), call.generic_arguments.len);
    const argument = parameterized_storage.ir.generic_arguments.items[call.generic_arguments.start].value.type;
    try std.testing.expect(parameterized_storage.ir.types.items[@intFromEnum(argument)] == .parameter);
}

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
        if (!std.mem.eql(u8, graph.text(reference.name), "Point")) continue;
        try std.testing.expectEqual(point_declarations[0], reference.resolution.module);
        resolved_point = true;
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

test "anonymous structural types retain module-local default provenance" {
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
}

test "module graph builds nominal choice variants" {
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

test "implicit generic calls infer pointer parameters through nested calls" {
    const allocator = std.testing.allocator;
    const source =
        "empty#(.t: Type)(.storage: $&t, .required: Int32) -> () := { absent() }\n" ++
        "empty#(.t: Type)(.storage: $&t) -> () := {}\n" ++
        "release#(.t: Type)(.self: $&t) -> () := { local ::= self empty(.storage = local) }\n" ++
        "main() -> () := { value :: Int32 = 0 release(.self = $&value) }\n";
    var tree = try parseSource(allocator, source, @enumFromInt(0));
    defer tree.deinit(allocator);
    const inputs = [_]module_graph.FileInput{.{ .path = "inference/main.rg", .tree = &tree, .source = source }};
    var module = try @import("semantizer.zig").build(allocator, "inference", &inputs);
    defer module.graph.deinit(allocator);
    var result = try @import("../global/semantizer.zig").semantize(allocator, &.{module.graph});
    defer result.graph.deinit(allocator);
    try std.testing.expectEqual(@as(u32, 0), result.stats.remaining);
    try std.testing.expectEqual(@as(usize, 2), result.graph.generic_function_instances.items.len);
    for (result.graph.generic_function_instances.items) |instance| {
        try std.testing.expect(result.graph.functions.items[@intFromEnum(instance.function)].body != null);
    }
}

test "implicit generic calls reject conflicting repeated parameters" {
    const allocator = std.testing.allocator;
    const source =
        "same#(.t: Type)(.left: $&t, .right: $&t) -> () := {}\n" ++
        "main() -> () := { left :: Int32 = 0 right :: Bool = false same(.left = $&left, .right = $&right) }\n";
    var tree = try parseSource(allocator, source, @enumFromInt(0));
    defer tree.deinit(allocator);
    const inputs = [_]module_graph.FileInput{.{ .path = "conflict/main.rg", .tree = &tree, .source = source }};
    var module = try @import("semantizer.zig").build(allocator, "conflict", &inputs);
    defer module.graph.deinit(allocator);
    try std.testing.expectError(error.UnsupportedGlobalSemantic, @import("../global/semantizer.zig").semantize(allocator, &.{module.graph}));
}

test "failed generic bodies do not publish reusable instances" {
    const allocator = std.testing.allocator;
    const source = "broken#(.t: Type)(.value: t) -> () := { absent(.value = value) }\n";
    var tree = try parseSource(allocator, source, @enumFromInt(0));
    defer tree.deinit(allocator);
    const inputs = [_]module_graph.FileInput{.{ .path = "retry/main.rg", .tree = &tree, .source = source }};
    var module = try @import("semantizer.zig").build(allocator, "retry", &inputs);
    defer module.graph.deinit(allocator);
    const modules = [_]module_graph.ModuleSemanticGraph{module.graph};
    var relocation = try @import("../global/globalizer.zig").relocate(allocator, &modules, .allow_holes);
    defer relocation.deinit(allocator);
    var core = @import("../global/core.zig").Resolver{ .allocator = allocator, .graph = &relocation.graph, .modules = &modules, .offsets = relocation.offsets.items };
    var generics = @import("../global/generics.zig").Resolver{ .allocator = allocator, .graph = &relocation.graph, .modules = &modules, .offsets = relocation.offsets.items, .core = &core };
    var functions = @import("../global/generic_functions.zig").Resolver{ .allocator = allocator, .graph = &relocation.graph, .modules = &modules, .offsets = relocation.offsets.items, .core = &core, .generics = &generics };
    const ty = try generics.internType(.{ .builtin = .Int32 });
    const name = try relocation.graph.addString(allocator, "t");
    const arguments = @import("../primitives/schema.zig").Range(@import("../global/graph.zig").GlobalGenericArgId){ .start = @intCast(relocation.graph.generic_arguments.items.len), .len = 1 };
    try relocation.graph.generic_arguments.append(allocator, .{ .name = name, .value = .{ .type = ty } });
    const declaration = @import("../global/globalizer.zig").globalDecl(relocation.offsets.items[0], module.graph.semantic.parameterized_storage.parameterized_functions.items[0].declaration);
    const function_count = relocation.graph.functions.items.len;
    const node_count = relocation.graph.nodes.items.len;
    for (0..2) |_| {
        try std.testing.expectError(error.NoMatchingGenericFunction, functions.instantiate(declaration, arguments));
        try std.testing.expectEqual(function_count, relocation.graph.functions.items.len);
        try std.testing.expectEqual(node_count, relocation.graph.nodes.items.len);
        try std.testing.expectEqual(@as(usize, 0), relocation.graph.generic_function_instances.items.len);
    }
}
