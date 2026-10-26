const std = @import("std");
const diagnostic = @import("../../1_base/diagnostic.zig");
const source_db = @import("../../1_base/source_db.zig");
const source_files = @import("../../1_base/source_files.zig");
const syn = @import("../../3_syntax/syntax_tree.zig");
const syntaxer = @import("../../3_syntax/syntaxer.zig");
const tokenizer = @import("../../2_tokens/tokenizer.zig");
const module_graph = @import("graph.zig");
const module_semantizer = @import("semantizer.zig");
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
    _ = try initializer_lowerer.lower(allocator, &graph, &inputs, null);

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
    _ = try initializer_lowerer.lower(allocator, &graph, &inputs, null);

    const function = graph.functions.items[@intFromEnum(graph.declarations.items[0].function_id.?)];
    try std.testing.expectEqual(@as(u32, 1), function.input.len);
    const field = try @import("views.zig").fieldView(&graph, @enumFromInt(function.input.start));
    try std.testing.expect((try @import("views.zig").typeView(&graph, field.ty)) == .external);
}

test "constrained generic parameters remain type parameters" {
    const allocator = std.testing.allocator;
    const source =
        "Capability#(.Participant: Type): Contract = ()\n" ++
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
    defer resolver.deinit();
    var substitutions = try generics.Resolver.Bindings.init(allocator, parameterized_storage.comptime_parameters.items.len);
    defer substitutions.deinit(allocator);
    const int_type: global_sg.GlobalTypeId = @enumFromInt(@as(u32, @intCast(relocation.graph.types.items.len)));
    try relocation.graph.types.append(allocator, .{ .builtin = .Int32 });
    substitutions.types[parameterized_storage.parameterized_types.items[1].parameters.start] = int_type;
    const instantiated = try resolver.instantiateParameterizedType(0, body, &substitutions);
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
    var graph = try buildInterfaces(allocator, "geometry", &.{
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
    const point_field = graph.semantic.fields.items[distance_interface.input.start];
    try std.testing.expectEqualStrings("point", graph.text(point_field.name));
    try std.testing.expectEqual(@import("entities.zig").ModuleType{ .resolved = .{ .declared = @enumFromInt(0) } }, graph.semantic.types.items[@intFromEnum(point_field.ty)]);
    const point_fields = graph.declarations.items[0].struct_fields.?;
    try std.testing.expectEqual(@as(u32, 1), point_fields.len);
    try std.testing.expectEqualStrings("x", graph.text(graph.semantic.fields.items[point_fields.start].name));
}

test "module symbol index retains duplicate declarations for diagnostics" {
    const allocator = std.testing.allocator;
    const first_source = "convert(.value: Int32) -> () := {}\n";
    const second_source = "convert(.value: Bool) -> () := {}\n";
    var first = try parseSource(allocator, first_source, @enumFromInt(0));
    defer first.deinit(allocator);
    var second = try parseSource(allocator, second_source, @enumFromInt(1));
    defer second.deinit(allocator);
    var graph = try buildInterfaces(allocator, "conversion", &.{
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
    var graph = try buildInterfaces(allocator, "arrays", &.{.{ .path = "arrays/main.rg", .tree = &tree, .source = source }});
    defer graph.deinit(allocator);

    const interface = graph.functions.items[0];
    const first = graph.semantic.fields.items[interface.input.start];
    const second = graph.semantic.fields.items[interface.input.start + 1];
    try std.testing.expectEqual(first.ty, second.ty);
    const array = graph.semantic.types.items[@intFromEnum(first.ty)].resolved.array;
    try std.testing.expectEqual(@as(u64, 2), array.length);
    const pointer = graph.semantic.types.items[@intFromEnum(array.element)].resolved.pointer;
    try std.testing.expectEqual(.read_only, pointer.mutability);
    try std.testing.expectEqual(module_graph.BuiltinType.Int32, graph.semantic.types.items[@intFromEnum(pointer.child)].resolved.builtin);
}

test "module callable interfaces lower literal Array generic types" {
    const allocator = std.testing.allocator;
    const source = "consume(.values: Array#(.n = 3, .t: Int32)) -> () := {}\n";
    var tree = try parseSource(allocator, source, @enumFromInt(0));
    defer tree.deinit(allocator);
    var graph = try buildInterfaces(allocator, "generic_arrays", &.{.{ .path = "generic_arrays/main.rg", .tree = &tree, .source = source }});
    defer graph.deinit(allocator);

    const interface = graph.functions.items[0];
    const array = graph.semantic.types.items[@intFromEnum(graph.semantic.fields.items[interface.input.start].ty)].resolved.array;
    try std.testing.expectEqual(@as(u64, 3), array.length);
    try std.testing.expectEqual(module_graph.BuiltinType.Int32, graph.semantic.types.items[@intFromEnum(array.element)].resolved.builtin);
}

test "module callable interfaces preserve nullable types" {
    const allocator = std.testing.allocator;
    const source = "find(.fallback: ?Int32) -> (.result: ?Int32) := { result = fallback }\n";
    var tree = try parseSource(allocator, source, @enumFromInt(0));
    defer tree.deinit(allocator);
    var graph = try buildInterfaces(allocator, "nullable", &.{.{ .path = "nullable/main.rg", .tree = &tree, .source = source }});
    defer graph.deinit(allocator);

    const interface = graph.functions.items[0];
    const input = graph.semantic.fields.items[interface.input.start];
    const output = graph.semantic.fields.items[interface.output.start];
    try std.testing.expectEqual(input.ty, output.ty);
    const child = graph.semantic.types.items[@intFromEnum(input.ty)].resolved.nullable;
    try std.testing.expectEqual(module_graph.BuiltinType.Int32, graph.semantic.types.items[@intFromEnum(child)].resolved.builtin);
}

test "module callable interfaces preserve inferred errable types" {
    const allocator = std.testing.allocator;
    const source = "run() -> !Int32 := { return 1 }\n";
    var tree = try parseSource(allocator, source, @enumFromInt(0));
    defer tree.deinit(allocator);
    var graph = try buildInterfaces(allocator, "errable", &.{.{ .path = "errable/main.rg", .tree = &tree, .source = source }});
    defer graph.deinit(allocator);

    const interface = graph.functions.items[0];
    const output = graph.semantic.fields.items[interface.output.start];
    const child = graph.semantic.types.items[@intFromEnum(output.ty)].resolved.inferred_errable;
    try std.testing.expectEqual(module_graph.BuiltinType.Int32, graph.semantic.types.items[@intFromEnum(child)].resolved.builtin);
}

test "module semantizing marks inferred error signatures" {
    const allocator = std.testing.allocator;
    const source = "run() -> !Int32 := { return 1 }\n";
    var tree = try parseSource(allocator, source, @enumFromInt(0));
    defer tree.deinit(allocator);
    var result = try module_semantizer.build(allocator, "errable", &.{.{ .path = "errable/main.rg", .tree = &tree, .source = source }});
    defer result.graph.deinit(allocator);
    try std.testing.expect((try @import("views.zig").functionView(&result.graph, @enumFromInt(0))).flags.uses_inferred_error_reasons);
}

test "module callable interfaces preserve anonymous structural types" {
    const allocator = std.testing.allocator;
    const source = "read(.value: (.nested: (.number: Int32))) -> (.result: (.nested: (.number: Int32))) := { result = value }\n";
    var tree = try parseSource(allocator, source, @enumFromInt(0));
    defer tree.deinit(allocator);
    var graph = try buildInterfaces(allocator, "structural", &.{.{ .path = "structural/main.rg", .tree = &tree, .source = source }});
    defer graph.deinit(allocator);

    const interface = graph.functions.items[0];
    for ([_]@import("entities.zig").Field{ graph.semantic.fields.items[interface.input.start], graph.semantic.fields.items[interface.output.start] }) |field| {
        const shape = graph.semantic.types.items[@intFromEnum(field.ty)].resolved.structural.fields;
        try std.testing.expectEqual(@as(u32, 1), shape.len);
        const nested = graph.semantic.fields.items[shape.start];
        try std.testing.expectEqualStrings("nested", graph.text(nested.name));
        const nested_shape = graph.semantic.types.items[@intFromEnum(nested.ty)].resolved.structural.fields;
        try std.testing.expectEqual(@as(u32, 1), nested_shape.len);
        const number = graph.semantic.fields.items[nested_shape.start];
        try std.testing.expectEqualStrings("number", graph.text(number.name));
        try std.testing.expectEqual(module_graph.BuiltinType.Int32, graph.semantic.types.items[@intFromEnum(number.ty)].resolved.builtin);
    }
}

test "anonymous structural types retain module-local default provenance" {
    const allocator = std.testing.allocator;
    const source = "read(.value: (.number: Int32 = 4)) -> () := {}\n";
    var tree = try parseSource(allocator, source, @enumFromInt(0));
    defer tree.deinit(allocator);
    var graph = try buildInterfaces(allocator, "structural_defaults", &.{.{ .path = "structural_defaults/main.rg", .tree = &tree, .source = source }});
    defer graph.deinit(allocator);

    const interface = graph.functions.items[0];
    const input = graph.semantic.fields.items[interface.input.start];
    const external = graph.semantic.types.items[@intFromEnum(input.ty)].external;
    const reference = graph.semantic.external_refs.items[@intFromEnum(external)];
    const recipe = graph.semantic.parameterized_storage.ir.types.items[@intFromEnum(reference.computed_type.?)].resolved.structural;
    const number = graph.semantic.parameterized_storage.ir.fields.items[recipe.fields.start];
    try std.testing.expect(number.default_value != null);
    try std.testing.expectEqual(@as(u32, @intCast(std.mem.indexOf(u8, source, "number").?)), number.source.offset);
    try std.testing.expectEqual(@as(u32, 0), number.source.file_index);
}

test "module callable interfaces preserve anonymous choice types" {
    const allocator = std.testing.allocator;
    const source = "inspect(.value: (..some Int32, ..none)) -> () := {}\n";
    var tree = try parseSource(allocator, source, @enumFromInt(0));
    defer tree.deinit(allocator);
    var graph = try buildInterfaces(allocator, "choices", &.{.{ .path = "choices/main.rg", .tree = &tree, .source = source }});
    defer graph.deinit(allocator);

    const interface = graph.functions.items[0];
    const input = graph.semantic.fields.items[interface.input.start];
    const shape = graph.semantic.types.items[@intFromEnum(input.ty)].resolved.structural_choice.variants;
    try std.testing.expectEqual(@as(u32, 2), shape.len);
    const some = graph.semantic.variants.items[shape.start];
    try std.testing.expectEqualStrings("some", graph.text(some.name));
    try std.testing.expectEqual(module_graph.BuiltinType.Int32, graph.semantic.types.items[@intFromEnum(some.payload_type.?)].resolved.builtin);
    try std.testing.expectEqualStrings("none", graph.text(graph.semantic.variants.items[shape.start + 1].name));
}

test "module callable interfaces retain choice union evaluation recipes" {
    const allocator = std.testing.allocator;
    const source = "Left : Type = (..first, ..shared)\nRight : Type = (..shared, ..second)\nmerge() -> (.result: choice_union#(.a: Left, .b: Right)) := { result = ..shared }\n";
    var tree = try parseSource(allocator, source, @enumFromInt(0));
    defer tree.deinit(allocator);
    var graph = try buildInterfaces(allocator, "choice_unions", &.{.{ .path = "choice_unions/main.rg", .tree = &tree, .source = source }});
    defer graph.deinit(allocator);

    const interface = graph.functions.items[0];
    const output = graph.semantic.fields.items[interface.output.start];
    const external = graph.semantic.types.items[@intFromEnum(output.ty)].external;
    const reference = graph.semantic.external_refs.items[@intFromEnum(external)];
    const union_recipe = graph.semantic.parameterized_storage.ir.types.items[@intFromEnum(reference.computed_type.?)].choice_union;
    try std.testing.expect(union_recipe.left != union_recipe.right);
}

test "module callable interfaces preserve type-only generic instantiations" {
    const allocator = std.testing.allocator;
    const type_source = "Box#(.t: Type) : Type = (.value: t)\n";
    const function_source = "read(.box: Box#(.t: Int32)) -> () := {}\n";
    var type_tree = try parseSource(allocator, type_source, @enumFromInt(0));
    defer type_tree.deinit(allocator);
    var function_tree = try parseSource(allocator, function_source, @enumFromInt(1));
    defer function_tree.deinit(allocator);
    var graph = try buildInterfaces(allocator, "generics", &.{
        .{ .path = "generics/type.rg", .tree = &type_tree, .source = type_source },
        .{ .path = "generics/function.rg", .tree = &function_tree, .source = function_source },
    });
    defer graph.deinit(allocator);

    const interface = graph.functions.items[0];
    const input = graph.semantic.fields.items[interface.input.start];
    const generic = graph.semantic.types.items[@intFromEnum(input.ty)].resolved.generic;
    try std.testing.expectEqual(@as(u32, 0), @intFromEnum(generic.base));
    try std.testing.expectEqual(@as(u32, 1), generic.arguments.len);
    const argument = graph.semantic.generic_arguments.items[generic.arguments.start];
    try std.testing.expectEqualStrings("t", graph.text(argument.name));
    try std.testing.expectEqual(module_graph.BuiltinType.Int32, graph.semantic.types.items[@intFromEnum(argument.value.type)].resolved.builtin);
}

test "discovery and lowering share nested generic arguments across construction contexts" {
    const allocator = std.testing.allocator;
    const source = "Box#(.t: Type): Type = (.value: t)\nread(.box: Box#(.t: Box#(.t: Int32))) -> () := {}\n";
    var tree = try parseSource(allocator, source, @enumFromInt(0));
    defer tree.deinit(allocator);
    var graph = try buildInterfaces(allocator, "generics", &.{
        .{ .path = "generics/main.rg", .tree = &tree, .source = source },
    });
    defer graph.deinit(allocator);

    const views = @import("views.zig");
    const input = graph.semantic.fields.items[graph.functions.items[0].input.start];
    const outer = graph.semantic.types.items[@intFromEnum(input.ty)].resolved.generic;
    const outer_argument = try views.genericArgumentView(&graph, @enumFromInt(outer.arguments.start));
    const inner = graph.semantic.types.items[@intFromEnum(outer_argument.value.type)].resolved.generic;
    const inner_argument = try views.genericArgumentView(&graph, @enumFromInt(inner.arguments.start));
    try std.testing.expectEqual(module_graph.BuiltinType.Int32, graph.semantic.types.items[@intFromEnum(inner_argument.value.type)].resolved.builtin);

    const discovered_count = views.genericArgumentCount(&graph);
    var writer = @import("writer.zig").Writer.init(allocator, &graph);
    const appended = try writer.addGenericArgument(.{
        .name = outer_argument.name,
        .value = .{ .comptime_int = 42 },
    });
    try std.testing.expectEqual(discovered_count, @intFromEnum(appended));
    const backing = graph.semantic.generic_arguments.items.ptr;
    try std.testing.expectEqual(backing, graph.semantic.generic_arguments.items.ptr);
    try std.testing.expectEqual(outer_argument.value.type, (try views.genericArgumentView(&graph, @enumFromInt(outer.arguments.start))).value.type);
    const canonical_outer = (try views.typeView(&graph, input.ty)).resolved.generic;
    try std.testing.expectEqual(outer.arguments.start, canonical_outer.arguments.start);
    try std.testing.expectEqual(@as(i64, 42), (try views.genericArgumentView(&graph, appended)).value.comptime_int);
    writer = @import("writer.zig").Writer.init(allocator, &graph);
    const next = try writer.addGenericArgument(inner_argument);
    try std.testing.expectEqual(discovered_count + 1, @intFromEnum(next));
}

test "module graph builds nominal choice variants" {
    const allocator = std.testing.allocator;
    const source = "Result : Type = (\n    ..ok Int32\n    ..done\n)\n";
    var tree = try parseSource(allocator, source, @enumFromInt(0));
    defer tree.deinit(allocator);
    var graph = try buildInterfaces(allocator, "results", &.{.{ .path = "results/main.rg", .tree = &tree, .source = source }});
    defer graph.deinit(allocator);

    const range = graph.declarations.items[0].choice_variants.?;
    try std.testing.expectEqual(@as(u32, 2), range.len);
    const ok = graph.semantic.variants.items[range.start];
    try std.testing.expectEqualStrings("ok", graph.text(ok.name));
    try std.testing.expectEqual(module_graph.BuiltinType.Int32, graph.semantic.types.items[@intFromEnum(ok.payload_type.?)].resolved.builtin);
    const done = graph.semantic.variants.items[range.start + 1];
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
        "empty_with_required#(.t: Type)(.storage: $&t, .required: Int32) -> () := { absent() }\n" ++
        "empty#(.t: Type)(.storage: $&t) -> () := {}\n" ++
        "release#(.t: Type)(.self: $&t) -> () := { local ::= self empty(.storage = local) }\n" ++
        "main() -> () := { value :: Int32 = 0 release(.self = $&value) }\n";
    var tree = try parseSource(allocator, source, @enumFromInt(0));
    defer tree.deinit(allocator);
    const inputs = [_]module_graph.FileInput{.{ .path = "inference/main.rg", .tree = &tree, .source = source }};
    var module = try @import("semantizer.zig").build(allocator, "inference", &inputs);
    defer module.graph.deinit(allocator);
    var result = try @import("../global/semantizer.zig").semantize(allocator, &.{module.graph});
    defer result.deinit(allocator);
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
    try std.testing.expectError(error.ConflictingGenericArgument, @import("../global/semantizer.zig").semantize(allocator, &.{module.graph}));
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
    defer generics.deinit();
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

test "explicit contract bounds specialize one body per concrete participant" {
    const allocator = std.testing.allocator;
    const source =
        "Capability#(.Value: Type): Contract = ()\n" ++
        "implement Capability#(Int32) ()\n" ++
        "implement Capability#(UInt8) ()\n" ++
        "use#(.Value: Type: Capability)(.value: Value) -> (.result: Int32) := { result = 1 }\n" ++
        "main() -> (.result: Int32) := { byte :: UInt8 = 65\n result = use(.value = 7).result + use(.value = byte).result }\n";
    var tree = try parseSource(allocator, source, @enumFromInt(0));
    defer tree.deinit(allocator);
    const inputs = [_]module_graph.FileInput{.{ .path = "contract/main.rg", .tree = &tree, .source = source }};
    var module = try @import("semantizer.zig").build(allocator, "contract", &inputs);
    defer module.graph.deinit(allocator);
    const template = module.graph.semantic.parameterized_storage.parameterized_functions.items[0];
    try std.testing.expectEqual(@as(u32, 1), template.parameters.len);
    const parameter = module.graph.semantic.parameterized_storage.comptime_parameters.items[template.parameters.start];
    try std.testing.expect(parameter.constraint != null);
    var arithmetic_core = try buildArithmeticTestCore(allocator);
    defer arithmetic_core.graph.deinit(allocator);
    var result = try @import("../global/semantizer.zig").semantize(allocator, &.{ module.graph, arithmetic_core.graph });
    defer result.deinit(allocator);
    var instances: usize = 0;
    for (result.graph.generic_function_instances.items) |instance| {
        const declaration = result.graph.declaration(instance.parameterized_declaration);
        if (std.mem.eql(u8, result.graph.text(declaration.name), "use")) instances += 1;
    }
    try std.testing.expectEqual(@as(usize, 2), instances);
}

test "explicit contract bound participates in a nested generic input" {
    const allocator = std.testing.allocator;
    const source =
        "Capability#(.Value: Type): Contract = ()\n" ++
        "Box#(.t: Type) : Type = (.value: t)\n" ++
        "read#(.Value: Type: Capability)(.box: Box#(.t: Value)) -> () := {}\n";
    var tree = try parseSource(allocator, source, @enumFromInt(0));
    defer tree.deinit(allocator);
    const files = [_]module_graph.FileInput{.{ .path = "nested_contract/main.rg", .tree = &tree, .source = source }};
    var module = try module_graph.build(allocator, "nested_contract", &files);
    defer module.deinit(allocator);
    _ = try @import("parameterized/lowerer.zig").lower(allocator, &module, &files);
    const storage = &module.semantic.parameterized_storage;
    try std.testing.expectEqual(@as(usize, 1), storage.parameterized_functions.items.len);
    const template = storage.parameterized_functions.items[0];
    try std.testing.expectEqual(@as(u32, 1), template.parameters.len);
    try std.testing.expect(storage.comptime_parameters.items[template.parameters.start].constraint != null);
}

test "virtual type arguments remain runtime contracts in parameterized IR" {
    const allocator = std.testing.allocator;
    const source =
        "Capability#(.Value: Type): Contract = ()\n" ++
        "take#(.t: Type)(.value: Virtual#(.contract: Capability)) -> () := {}\n";
    var tree = try parseSource(allocator, source, @enumFromInt(0));
    defer tree.deinit(allocator);
    const files = [_]module_graph.FileInput{.{ .path = "runtime_contract/main.rg", .tree = &tree, .source = source }};
    var module = try module_graph.build(allocator, "runtime_contract", &files);
    defer module.deinit(allocator);
    _ = try @import("parameterized/lowerer.zig").lower(allocator, &module, &files);
    const storage = &module.semantic.parameterized_storage;
    const template = storage.parameterized_functions.items[0];
    try std.testing.expectEqual(@as(u32, 1), template.parameters.len);
    const input = storage.ir.types.items[@intFromEnum(template.input)].resolved.structural;
    const field = storage.ir.fields.items[input.fields.start];
    try std.testing.expect(storage.ir.types.items[@intFromEnum(field.ty)] == .resolved);
    try std.testing.expect(storage.ir.types.items[@intFromEnum(field.ty)].resolved == .virtual);
}

test "parameterized call defaults preserve reach alternatives" {
    const allocator = std.testing.allocator;
    const source = "consume#(.t: Type)(.value: t = reach value, context.value) -> () := {}\n";
    var tree = try parseSource(allocator, source, @enumFromInt(0));
    defer tree.deinit(allocator);
    const files = [_]module_graph.FileInput{.{ .path = "reach_template/main.rg", .tree = &tree, .source = source }};
    var module = try module_graph.build(allocator, "reach_template", &files);
    defer module.deinit(allocator);
    _ = try @import("parameterized/lowerer.zig").lower(allocator, &module, &files);
    const storage = &module.semantic.parameterized_storage.ir;
    const input = storage.types.items[@intFromEnum(module.semantic.parameterized_storage.parameterized_functions.items[0].input)].resolved.structural;
    const field = storage.fields.items[input.fields.start];
    const default_node = storage.nodes.items[@intFromEnum(field.default_value.?)].resolved;
    const reach = storage.reaches.items[@intFromEnum(default_node.content.reach_directive)];
    try std.testing.expectEqual(@as(u32, 2), reach.alternatives.len);
    const first = storage.reach_alternatives.items[reach.alternatives.start];
    const second = storage.reach_alternatives.items[reach.alternatives.start + 1];
    try std.testing.expectEqualStrings("value", module.text(storage.reach_segments.items[first.segments.start]));
    try std.testing.expectEqualStrings("context", module.text(storage.reach_segments.items[second.segments.start]));
    try std.testing.expectEqualStrings("value", module.text(storage.reach_segments.items[second.segments.start + 1]));
    const input_binding = storage.bindings.items[module.semantic.parameterized_storage.parameterized_functions.items[0].input_bindings.start];
    try std.testing.expect(input_binding.initialization != null);
}

test "explicit imported contract bounds become constrained templates" {
    const allocator = std.testing.allocator;
    const source = "dep := import(\"../dep\")\nwrite#(.t: Type, .Provider: Type: dep.Writer)(.value: t, .writer: $&Provider) -> () := {}\n";
    var tree = try parseSource(allocator, source, @enumFromInt(0));
    defer tree.deinit(allocator);
    var module = try @import("semantizer.zig").build(allocator, "consumer", &.{.{
        .path = "consumer/main.rg",
        .tree = &tree,
        .source = source,
    }});
    defer module.graph.deinit(allocator);

    const templates = module.graph.semantic.parameterized_storage.parameterized_functions.items;
    try std.testing.expectEqual(@as(usize, 1), templates.len);
    try std.testing.expectEqual(@as(u32, 2), templates[0].parameters.len);
    const parameter = module.graph.semantic.parameterized_storage.comptime_parameters.items[templates[0].parameters.start + 1];
    try std.testing.expect(parameter.constraint != null);
    const constraint = module.graph.semantic.parameterized_storage.contract_constraints.items[@intFromEnum(parameter.constraint.?)];
    try std.testing.expect(constraint.contract_ref == .external);
    const reference = module.graph.semantic.external_refs.items[@intFromEnum(constraint.contract_ref.external)];
    try std.testing.expectEqual(@import("entities.zig").ExternalKind.contract, reference.kind);
    try std.testing.expectEqualStrings("Writer", module.graph.text(reference.name));
}

test "local concrete type shadows unqualified prelude contract" {
    const allocator = std.testing.allocator;
    const source =
        "Shadowed : Type = ()\n" ++
        "consume(.value: Shadowed) -> () := {}\n";
    var tree = try parseSource(allocator, source, @enumFromInt(0));
    defer tree.deinit(allocator);
    var module = try @import("semantizer.zig").build(allocator, "shadowing", &.{.{
        .path = "shadowing/main.rg",
        .tree = &tree,
        .source = source,
    }});
    defer module.graph.deinit(allocator);

    try std.testing.expectEqual(
        @as(usize, 0),
        module.graph.semantic.parameterized_storage.parameterized_functions.items.len,
    );
}

test "parameterized call defaults reach caller bindings after instantiation" {
    const allocator = std.testing.allocator;
    const source =
        "consume#(.t: Type)(.item: t = reach value) -> () := {}\n" ++
        "main(.value: Int32) -> () := { consume#(.t: Int32)() }\n";
    var tree = try parseSource(allocator, source, @enumFromInt(0));
    defer tree.deinit(allocator);
    var module = try @import("semantizer.zig").build(allocator, "generic_reach", &.{.{
        .path = "generic_reach/main.rg",
        .tree = &tree,
        .source = source,
    }});
    defer module.graph.deinit(allocator);
    var result = try @import("../global/semantizer.zig").semantize(allocator, &.{module.graph});
    defer result.deinit(allocator);
    try std.testing.expectEqual(@as(u32, 0), result.stats.remaining);
}

test "ordinary calls retain caller bindings for reached defaults" {
    const allocator = std.testing.allocator;
    const source =
        "consume(.value: Int32) -> () := {}\n" ++
        "main() -> () := {\n" ++
        "    local :: Int32 = 7\n" ++
        "    consume(.value = local)\n" ++
        "}\n";
    var tree = try parseSource(allocator, source, @enumFromInt(0));
    defer tree.deinit(allocator);
    var module = try @import("semantizer.zig").build(allocator, "reach_caller", &.{.{ .path = "reach_caller/main.rg", .tree = &tree, .source = source }});
    defer module.graph.deinit(allocator);
    var found = false;
    for (module.graph.semantic.pending_operations.items, 0..) |operation, operation_index| {
        if (operation != .resolve_call) continue;
        const call = operation.resolve_call;
        const callee = module.graph.semantic.external_refs.items[@intFromEnum(call.callee)];
        if (!std.mem.eql(u8, module.graph.text(callee.name), "consume")) continue;
        const owner = module.graph.functions.items[@intFromEnum(call.owner_function.?)];
        try std.testing.expectEqual(call.owner_function, module.graph.semantic.pending_owner_functions.items[operation_index]);
        try std.testing.expectEqualStrings("main", module.graph.text(module.graph.declarations.items[@intFromEnum(owner.declaration)].name));
        const refs = module.graph.semantic.binding_refs.items[call.visible_bindings.start..][0..call.visible_bindings.len];
        for (refs) |binding| {
            if (std.mem.eql(u8, module.graph.text(module.graph.semantic.bindings.items[@intFromEnum(binding)].name), "local")) found = true;
        }
    }
    try std.testing.expect(found);
}

test "named call inputs reject unrelated default-only operation identities" {
    const allocator = std.testing.allocator;
    const source =
        "StdoutFill#(.Value: Type): Contract = (.fill: (.stdout: Value = 1) -> (.result: Int32))\n" ++
        "ReceiverFill#(.Value: Type): Contract = (.fill: (.self: Value) -> (.result: Int32))\n" ++
        "_fill_stdout := (.stdout: Int32 = 1) -> (.result: Int32) { result = stdout }\n" ++
        "_fill_self := (.self: Int32) -> (.result: Int32) { result = self }\n" ++
        "implement StdoutFill#(Int32) (.fill = _fill_stdout)\n" ++
        "implement ReceiverFill#(Int32) (.fill = _fill_self)\n" ++
        "main() -> (.result: Int32) := { result = fill(.self = 2).result }\n";
    var tree = try parseSource(allocator, source, @enumFromInt(0));
    defer tree.deinit(allocator);
    var module = try @import("semantizer.zig").build(allocator, "named_operations", &.{.{ .path = "named_operations/main.rg", .tree = &tree, .source = source }});
    defer module.graph.deinit(allocator);
    var result = try @import("../global/semantizer.zig").semantize(allocator, &.{module.graph});
    defer result.deinit(allocator);
    try std.testing.expectEqual(@as(u32, 0), result.stats.remaining);
    var matched = false;
    for (result.graph.nodes.items) |node| {
        if (node.content != .function_call) continue;
        const function = result.graph.functions.items[@intFromEnum(node.content.function_call.callee)];
        if (!std.mem.eql(u8, result.graph.text(result.graph.declaration(function.declaration).name), "_fill_self")) continue;
        try std.testing.expectEqualStrings("self", result.graph.text(result.graph.fields.items[function.input.start].name));
        matched = true;
    }
    try std.testing.expect(matched);
}

test "ordinary reached default selects a caller binding" {
    const allocator = std.testing.allocator;
    const source =
        "consume(.value: Int32 = reach value) -> (.result: Int32) := { result = value }\n" ++
        "main() -> (.result: Int32) := {\n" ++
        "    value :: Int32 = 7\n" ++
        "    result = consume().result\n" ++
        "}\n";
    var tree = try parseSource(allocator, source, @enumFromInt(0));
    defer tree.deinit(allocator);
    var module = try @import("semantizer.zig").build(allocator, "reach_local", &.{.{ .path = "reach_local/main.rg", .tree = &tree, .source = source }});
    defer module.graph.deinit(allocator);
    var result = try @import("../global/semantizer.zig").semantize(allocator, &.{module.graph});
    defer result.deinit(allocator);
    try std.testing.expectEqual(@as(u32, 0), result.stats.remaining);
    var reached = false;
    for (result.graph.nodes.items) |node| {
        if (node.content != .function_call) continue;
        const function = result.graph.functions.items[@intFromEnum(node.content.function_call.callee)];
        const declaration = result.graph.declaration(function.declaration);
        if (!std.mem.eql(u8, result.graph.text(declaration.name), "consume")) continue;
        const input = result.graph.nodes.items[@intFromEnum(node.content.function_call.input)].content.struct_value_literal;
        const argument = result.graph.value_fields.items[input.fields.start];
        const value = result.graph.nodes.items[@intFromEnum(argument.value)];
        try std.testing.expect(value.content == .binding_use);
        try std.testing.expectEqualStrings("value", result.graph.text(result.graph.bindings.items[@intFromEnum(value.content.binding_use)].name));
        reached = true;
    }
    try std.testing.expect(reached);
}

test "reached defaults propagate through an intermediate function" {
    const allocator = std.testing.allocator;
    const source =
        "consume(.value: Int32 = reach value) -> (.result: Int32) := { result = value }\n" ++
        "forward() -> (.result: Int32) := { result = consume().result }\n" ++
        "main() -> (.result: Int32) := {\n" ++
        "    value :: Int32 = 7\n" ++
        "    result = forward().result\n" ++
        "}\n";
    var tree = try parseSource(allocator, source, @enumFromInt(0));
    defer tree.deinit(allocator);
    var module = try @import("semantizer.zig").build(allocator, "reach_propagation", &.{.{ .path = "reach_propagation/main.rg", .tree = &tree, .source = source }});
    defer module.graph.deinit(allocator);
    var result = try @import("../global/semantizer.zig").semantize(allocator, &.{module.graph});
    defer result.deinit(allocator);
    try std.testing.expectEqual(@as(u32, 0), result.stats.remaining);
    var found = false;
    for (result.graph.functions.items) |function| {
        const declaration = result.graph.declaration(function.declaration);
        if (!std.mem.eql(u8, result.graph.text(declaration.name), "forward")) continue;
        try std.testing.expectEqual(@as(u32, 1), function.input.len);
        try std.testing.expectEqual(@as(u32, 1), function.input_bindings.len);
        try std.testing.expectEqualStrings("value", result.graph.text(result.graph.fields.items[function.input.start].name));
        found = true;
    }
    try std.testing.expect(found);
}

test "callback invocation preserves binding and field editor targets" {
    const allocator = std.testing.allocator;
    const source =
        "Callback() -> (.result: Int32) : CFunctionPointer\n" ++
        "Holder : Type = (.callback: Callback)\n" ++
        "main(.callback: Callback, .entry: Holder) -> (.result: Int32) := {\n" ++
        "    result = callback() + entry.callback()\n" ++
        "}\n";
    var tree = try parseSource(allocator, source, @enumFromInt(0));
    defer tree.deinit(allocator);
    var module = try module_semantizer.build(allocator, "callback_editor", &.{.{ .path = "callback_editor/main.rg", .tree = &tree, .source = source }});
    defer module.graph.deinit(allocator);
    var arithmetic_core = try buildArithmeticTestCore(allocator);
    defer arithmetic_core.graph.deinit(allocator);
    var result = try @import("../global/semantizer.zig").semantize(allocator, &.{ module.graph, arithmetic_core.graph });
    defer result.deinit(allocator);
    var index = try @import("../../0_commands/lsp_index.zig").Index.build(allocator, &result.graph);
    defer index.deinit(allocator);
    const callback_offset = std.mem.indexOf(u8, source, "callback()").?;
    const entry_offset = std.mem.indexOf(u8, source, "entry.callback()").?;
    var found_callback = false;
    var found_entry = false;
    var found_field = false;
    for (index.occurrences.items) |occurrence| {
        if (occurrence.source.offset == callback_offset) {
            try std.testing.expect(occurrence.target == .binding);
            try std.testing.expectEqualStrings("callback", result.graph.text(result.graph.binding(occurrence.target.binding).name));
            found_callback = true;
        }
        if (occurrence.source.offset == entry_offset) {
            try std.testing.expect(occurrence.target == .binding);
            try std.testing.expectEqualStrings("entry", result.graph.text(result.graph.binding(occurrence.target.binding).name));
            found_entry = true;
        }
        if (occurrence.source.offset == entry_offset + "entry.".len) {
            try std.testing.expect(occurrence.target == .field);
            found_field = true;
        }
    }
    try std.testing.expect(found_callback and found_entry and found_field);
}

test "unary and tuple contracts retain explicit symbolic participants" {
    const allocator = std.testing.allocator;
    const source =
        \\First#(.Participant: Type): Contract = (.Other: Type, .borrow: (.other: &Other, .source: &Participant) -> (.value: &Participant))
        \\Modern#(.Participant: Type): Contract = (
        \\    .Other: Type
        \\    .borrow: (.other: &Other, .source: &Participant) -> (.value: &Participant))
        \\Pair#(.Left: Type, .Right: Type): Contract = (
        \\    .combine: (.left: &Left, .right: &Right) -> (.value: Result)
        \\    .Result: Type
        \\    .Count: Int
        \\)
        \\
    ;
    var tree = try parseSource(allocator, source, @enumFromInt(0));
    defer tree.deinit(allocator);
    const inputs = [_]module_graph.FileInput{.{ .path = "contracts/main.rg", .tree = &tree, .source = source }};
    var graph = try module_graph.build(allocator, "contracts", &inputs);
    defer graph.deinit(allocator);
    _ = try parameterized_lowerer.lower(allocator, &graph, &inputs);
    const storage = &graph.semantic.parameterized_storage;
    try std.testing.expectEqual(@as(usize, 3), storage.contract_definitions.items.len);
    for (storage.contract_definitions.items[0..2]) |definition| {
        try std.testing.expect(definition.hasExplicitParticipants());
        const participant: @import("parameterized/storage.zig").ComptimeParameterId = @enumFromInt(definition.participants.start);
        try std.testing.expectEqual(@as(u32, 1), definition.participants.len);
        try std.testing.expectEqual(@intFromEnum(participant), definition.participants.start);
        try std.testing.expect(participant != @as(@import("parameterized/storage.zig").ComptimeParameterId, @enumFromInt(definition.parameters.start)));
        const requirement = storage.contract_requirements.items[definition.requirements.start];
        const fields = storage.ir.types.items[@intFromEnum(requirement.input)].resolved.structural.fields;
        const other = storage.ir.types.items[@intFromEnum(storage.ir.fields.items[fields.start].ty)].resolved.pointer.child;
        const receiver = storage.ir.types.items[@intFromEnum(storage.ir.fields.items[fields.start + 1].ty)].resolved.pointer.child;
        try std.testing.expectEqual(participant, storage.ir.types.items[@intFromEnum(receiver)].parameter);
        try std.testing.expect(storage.ir.types.items[@intFromEnum(other)].parameter != participant);
        const output = storage.ir.types.items[@intFromEnum(requirement.output)].resolved.structural.fields;
        const returned = storage.ir.types.items[@intFromEnum(storage.ir.fields.items[output.start].ty)].resolved.pointer.child;
        try std.testing.expectEqual(participant, storage.ir.types.items[@intFromEnum(returned)].parameter);
    }
    const pair = storage.contract_definitions.items[2];
    try std.testing.expect(pair.hasExplicitParticipants());
    try std.testing.expectEqual(@as(u32, 2), pair.participants.len);
    try std.testing.expectEqual(@as(u32, 2), pair.parameters.len);
    try std.testing.expect(pair.parameters.start + pair.parameters.len <= pair.participants.start);
    try std.testing.expectEqualStrings("Result", graph.text(storage.comptime_parameters.items[pair.parameters.start].name));
    try std.testing.expectEqualStrings("Count", graph.text(storage.comptime_parameters.items[pair.parameters.start + 1].name));
    try std.testing.expectEqual(.comptime_int, storage.comptime_parameters.items[pair.parameters.start + 1].kind);
    const pair_requirement = storage.contract_requirements.items[pair.requirements.start];
    const pair_output = storage.ir.types.items[@intFromEnum(pair_requirement.output)].resolved.structural.fields;
    const result_type = storage.ir.fields.items[pair_output.start].ty;
    try std.testing.expectEqual(pair.parameters.start, @intFromEnum(storage.ir.types.items[@intFromEnum(result_type)].parameter));
    const pair_input = storage.ir.types.items[@intFromEnum(pair_requirement.input)].resolved.structural.fields;
    const left = storage.ir.types.items[@intFromEnum(storage.ir.fields.items[pair_input.start].ty)].resolved.pointer.child;
    try std.testing.expectEqual(pair.participants.start, @intFromEnum(storage.ir.types.items[@intFromEnum(left)].parameter));
}

test "contract participants require ordinary bindings in generic evaluation" {
    const allocator = std.testing.allocator;
    const source = "First#(.Input: Type): Contract = (.read: (.source: &Input) -> ())\nExplicit#(.Input: Type): Contract = (.read: (.source: &Input) -> ())\n";
    var tree = try parseSource(allocator, source, @enumFromInt(0));
    defer tree.deinit(allocator);
    const inputs = [_]module_graph.FileInput{.{ .path = "contracts/main.rg", .tree = &tree, .source = source }};
    var graph = try module_graph.build(allocator, "contracts", &inputs);
    defer graph.deinit(allocator);
    _ = try parameterized_lowerer.lower(allocator, &graph, &inputs);
    const storage = &graph.semantic.parameterized_storage;
    const globalizer = @import("../global/globalizer.zig");
    const core = @import("../global/core.zig");
    const generics = @import("../global/generics.zig");
    const global_sg = @import("../global/graph.zig");
    var relocation = try globalizer.relocate(allocator, &.{graph}, .allow_holes);
    defer relocation.deinit(allocator);
    var core_resolver: core.Resolver = .{ .allocator = allocator, .graph = &relocation.graph, .modules = &.{graph}, .offsets = relocation.offsets.items };
    var resolver: generics.Resolver = .{ .allocator = allocator, .graph = &relocation.graph, .modules = &.{graph}, .offsets = relocation.offsets.items, .core = &core_resolver };
    defer resolver.deinit();
    const int_type: global_sg.GlobalTypeId = @enumFromInt(@as(u32, @intCast(relocation.graph.types.items.len)));
    try relocation.graph.types.append(allocator, .{ .builtin = .Int32 });
    for (storage.contract_definitions.items) |definition| {
        var bindings = try generics.Resolver.Bindings.init(allocator, storage.comptime_parameters.items.len);
        defer bindings.deinit(allocator);
        const requirement = storage.contract_requirements.items[definition.requirements.start];
        const fields = storage.ir.types.items[@intFromEnum(requirement.input)].resolved.structural.fields;
        const parameter_type = storage.ir.types.items[@intFromEnum(storage.ir.fields.items[fields.start].ty)].resolved.pointer.child;
        try std.testing.expectError(error.UnboundGenericTypeParameter, resolver.instantiateParameterizedType(0, parameter_type, &bindings));
        bindings.types[definition.participants.start] = int_type;
        try std.testing.expectEqual(int_type, try resolver.instantiateParameterizedType(0, parameter_type, &bindings));
    }
}

test "unary and tuple conformances publish canonical static evidence" {
    const allocator = std.testing.allocator;
    const source =
        "Readable#(.Value: Type): Contract = (\n.Result: Type\n.Count: Int\n.read: (.source: &Value) -> (.value: Result)\n)\n" ++
        "Product#(.Left: Type, .Right: Type): Contract = (\n.Result: Type\n.multiply: (.left: &Left, .right: &Right) -> (.value: Result)\n)\n" ++
        "Cell: Type = (.value: Int32)\n" ++
        "implement Readable#(Cell) (.Count: Int = 2, .Result: Type = Int32, .read = read)\n" ++
        "implement Product#(Cell, Cell) (.Result: Type = Int32, .multiply = multiply)\n" ++
        "read(.source: &Cell) -> (.value: Int32) := { value = source&.value }\n" ++
        "multiply(.left: &Cell, .right: &Cell) -> (.value: Int32) := { value = left&.value * right&.value }\n";
    var tree = try parseSource(allocator, source, @enumFromInt(0));
    defer tree.deinit(allocator);
    var module = try @import("semantizer.zig").build(allocator, "evidence", &.{.{ .path = "evidence/main.rg", .tree = &tree, .source = source }});
    defer module.graph.deinit(allocator);
    var arithmetic_core = try buildArithmeticTestCore(allocator);
    defer arithmetic_core.graph.deinit(allocator);
    var result = try @import("../global/semantizer.zig").semantize(allocator, &.{ module.graph, arithmetic_core.graph });
    defer result.deinit(allocator);
    var evidence: usize = 0;
    for (result.graph.contract_conformances.items) |conformance| {
        if (result.graph.modules.items[@intFromEnum(result.graph.moduleForDeclaration(conformance.declaration).?)].is_bundled_core) continue;
        evidence += 1;
        const name = result.graph.text(result.graph.declaration(conformance.declaration).name);
        const unary = std.mem.eql(u8, name, "Readable");
        try std.testing.expectEqual(@as(u32, if (unary) 1 else 2), conformance.participants.len);
        try std.testing.expectEqual(@as(u32, if (unary) 2 else 1), conformance.associated_arguments.len);
        try std.testing.expectEqual(@as(u32, 1), conformance.operations.len);
        const associated = result.graph.generic_arguments.items[conformance.associated_arguments.start..][0..conformance.associated_arguments.len];
        try std.testing.expectEqualStrings("Result", result.graph.text(associated[0].name));
        if (unary) {
            try std.testing.expectEqualStrings("Count", result.graph.text(associated[1].name));
            try std.testing.expectEqual(@as(i64, 2), associated[1].value.comptime_int);
        }
        const method = result.graph.function_refs.items[conformance.operations.start];
        try std.testing.expectEqualStrings(if (unary) "read" else "multiply", result.graph.text(result.graph.declaration(result.graph.function(method).declaration).name));
    }
    try std.testing.expectEqual(@as(usize, 2), evidence);
}

test "qualified operation statements preserve contract identity" {
    const allocator = std.testing.allocator;
    const source = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "tests/feature_tests/contracts/125X_qualified_operation_argument_mismatch/main.rg", allocator, .limited(64 * 1024));
    defer allocator.free(source);
    var tree = try parseSource(allocator, source, @enumFromInt(0));
    defer tree.deinit(allocator);
    var calls: usize = 0;
    for (tree.nodes.items(.tag), 0..) |tag, raw| {
        if (tag != .function_call) continue;
        const call = tree.functionCall(@enumFromInt(@as(u32, @intCast(raw)))).?;
        try std.testing.expect(call.contract_type != null);
        calls += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), calls);
    var module = try @import("semantizer.zig").build(allocator, "scoped", &.{.{ .path = "scoped/main.rg", .tree = &tree, .source = source }});
    defer module.graph.deinit(allocator);
    var pending: usize = 0;
    for (module.graph.semantic.pending_operations.items) |operation| {
        if (operation != .resolve_call) continue;
        try std.testing.expect(operation.resolve_call.contract_type != null);
        pending += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), pending);
}

test "scoped implementation evidence retains call and source identities" {
    const allocator = std.testing.allocator;
    const source = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "tests/feature_tests/contracts/115_inline_operation_bodies/main.rg", allocator, .limited(64 * 1024));
    defer allocator.free(source);
    var tree = try parseSource(allocator, source, @enumFromInt(0));
    defer tree.deinit(allocator);
    var module = try @import("semantizer.zig").build(allocator, "scoped", &.{.{ .path = "scoped/main.rg", .tree = &tree, .source = source }});
    defer module.graph.deinit(allocator);
    const storage = &module.graph.semantic.parameterized_storage;
    try std.testing.expectEqual(@as(usize, 2), storage.contract_conformances.items.len);
    for (storage.contract_conformances.items) |conformance| {
        try std.testing.expectEqual(@as(u32, 2), conformance.participants.len);
        for (storage.ir.generic_arguments.items[conformance.participants.start..][0..conformance.participants.len]) |argument| {
            try std.testing.expect(argument.value == .type);
            try std.testing.expect(storage.ir.types.items[@intFromEnum(argument.value.type)] == .concrete);
        }
    }
    var arithmetic_core = try buildArithmeticTestCore(allocator);
    defer arithmetic_core.graph.deinit(allocator);
    var result = try @import("../global/semantizer.zig").semantize(allocator, &.{ module.graph, arithmetic_core.graph });
    defer result.deinit(allocator);
    try @import("../global/verify.zig").verifyGlobal(&result.graph);
    var evidence: usize = 0;
    var operation_bindings: usize = 0;
    for (result.graph.contract_conformances.items) |conformance| {
        if (result.graph.modules.items[@intFromEnum(result.graph.moduleForDeclaration(conformance.declaration).?)].is_bundled_core) continue;
        evidence += 1;
        operation_bindings += conformance.operation_bindings.len;
        try std.testing.expectEqual(@as(u32, 1), conformance.operations.len);
        try std.testing.expectEqual(@as(u32, 1), conformance.operation_bindings.len);
        const method = result.graph.function_refs.items[conformance.operations.start];
        try std.testing.expectEqualStrings("multiply", result.graph.text(result.graph.declarationSourceName(result.graph.function(method).declaration)));
    }
    try std.testing.expectEqual(@as(usize, 2), evidence);
    try std.testing.expectEqual(@as(usize, 2), operation_bindings);
    var calls: usize = 0;
    for (result.graph.nodes.items) |node| {
        if (node.content != .function_call) continue;
        const call = node.content.function_call;
        const identity = result.graph.callOperation(call) orelse continue;
        const contract = result.graph.contract_conformances.items[identity.conformance].declaration;
        if (result.graph.modules.items[@intFromEnum(result.graph.moduleForDeclaration(contract).?)].is_bundled_core) continue;
        try std.testing.expectEqualStrings("multiply", result.graph.text(result.graph.callSourceName(call)));
        calls += 1;
    }
    try std.testing.expect(calls >= 3);
    const saved_bindings = result.graph.contract_operation_bindings.items.len;
    const saved = result.graph.checkpoint();
    _ = try result.graph.contract_operation_bindings.addOne(allocator);
    result.graph.rollback(allocator, saved);
    try std.testing.expectEqual(saved_bindings, result.graph.contract_operation_bindings.items.len);
}

test "generic contract implementations preserve participant and associated binders" {
    const allocator = std.testing.allocator;
    const source =
        \\Copyable#(.Value: Type): Contract = (
        \\    .Result: Type
        \\    .copy: (.value: Value) -> (.result: Result)
        \\)
        \\implement#(.T: Type) Copyable#(T) (
        \\    .Result: Type = T
        \\    .copy = (.value: T) -> (.result: Result) { result = value }
        \\)
    ;
    var tree = try parseSource(allocator, source, @enumFromInt(0));
    defer tree.deinit(allocator);
    var module = try @import("semantizer.zig").build(allocator, "generic", &.{.{ .path = "generic/main.rg", .tree = &tree, .source = source }});
    defer module.graph.deinit(allocator);
    const storage = &module.graph.semantic.parameterized_storage;
    try std.testing.expectEqual(@as(usize, 1), storage.contract_conformances.items.len);
    const conformance = storage.contract_conformances.items[0];
    try std.testing.expectEqual(@as(u32, 1), conformance.parameters.len);
    const participant = storage.ir.generic_arguments.items[conformance.participants.start].value.type;
    const associated = storage.ir.generic_arguments.items[conformance.associated_arguments.start].value.type;
    try std.testing.expectEqual(conformance.parameters.start, @intFromEnum(storage.ir.types.items[@intFromEnum(participant)].parameter));
    try std.testing.expectEqual(conformance.parameters.start, @intFromEnum(storage.ir.types.items[@intFromEnum(associated)].parameter));
    const relation = tree.contractConformance(tree.roots[1]).?;
    const members = tree.structTypeLiteral(relation.implementation_members).?;
    const body = tree.functionDeclaration(tree.structTypeField(members.fields[1]).?.default_value.?).?;
    try std.testing.expectEqual(@as(usize, 2), body.generic_params.len);
}

test "generic implementation selection binds associated results and operation bodies" {
    const allocator = std.testing.allocator;
    const source =
        \\Copyable#(.Value: Type): Contract = (.Result: Type, .copy: (.value: Value) -> (.result: Result))
        \\implement#(.T: Type) Copyable#(T) (
        \\    .Result: Type = T
        \\    .copy = (.value: T) -> (.result: Result) { result = value }
        \\)
        \\main := () -> (.status_code: Int32 = 0) {
        \\    first ::= Copyable#(Int32).copy(42).result
        \\    second ::= Copyable#(UInt8).copy(7).result
        \\    if first != 42 { abort }
        \\    if second != 7 { abort }
        \\}
    ;
    var tree = try parseSource(allocator, source, @enumFromInt(0));
    defer tree.deinit(allocator);
    var module = try @import("semantizer.zig").build(allocator, "generic", &.{.{ .path = "generic/main.rg", .tree = &tree, .source = source }});
    defer module.graph.deinit(allocator);
    var arithmetic_core = try buildArithmeticTestCore(allocator);
    defer arithmetic_core.graph.deinit(allocator);
    var result = try @import("../global/semantizer.zig").semantize(allocator, &.{ module.graph, arithmetic_core.graph });
    defer result.deinit(allocator);
    try @import("../global/verify.zig").verifyGlobal(&result.graph);
    var subject_count: usize = 0;
    for (result.graph.contract_conformances.items) |conformance| {
        if (@intFromEnum(result.graph.moduleForDeclaration(conformance.declaration).?) == 0) subject_count += 1;
    }
    try std.testing.expectEqual(@as(usize, 2), subject_count);
    for (result.graph.contract_conformances.items) |conformance| {
        if (@intFromEnum(result.graph.moduleForDeclaration(conformance.declaration).?) != 0) continue;
        try std.testing.expectEqual(@as(u32, 1), conformance.implementation_arguments.len);
        try std.testing.expectEqual(@as(u32, 1), conformance.operations.len);
    }
}

test "repeated participant specificity is independent of declaration order" {
    const allocator = std.testing.allocator;
    const original = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "tests/feature_tests/contracts/137_repeated_participant_specialization/main.rg", allocator, .limited(64 * 1024));
    defer allocator.free(original);
    const first = std.mem.indexOf(u8, original, "implement#(.A").?;
    const second = std.mem.indexOf(u8, original, "implement#(.T").?;
    const main = std.mem.indexOf(u8, original, "main :=").?;
    const reversed = try std.fmt.allocPrint(allocator, "{s}{s}{s}{s}", .{ original[0..first], original[second..main], original[first..second], original[main..] });
    defer allocator.free(reversed);
    for ([_][]const u8{ original, reversed }) |source| {
        var tree = try parseSource(allocator, source, @enumFromInt(0));
        defer tree.deinit(allocator);
        var module = try @import("semantizer.zig").build(allocator, "specificity", &.{.{ .path = "specificity/main.rg", .tree = &tree, .source = source }});
        defer module.graph.deinit(allocator);
        var arithmetic_core = try buildArithmeticTestCore(allocator);
        defer arithmetic_core.graph.deinit(allocator);
        var result = try @import("../global/semantizer.zig").semantize(allocator, &.{ module.graph, arithmetic_core.graph });
        defer result.deinit(allocator);
        var subject_count: usize = 0;
        for (result.graph.contract_conformances.items) |conformance| {
            if (@intFromEnum(result.graph.moduleForDeclaration(conformance.declaration).?) == 0) subject_count += 1;
        }
        try std.testing.expectEqual(@as(usize, 2), subject_count);
        var specialized: usize = 0;
        for (result.graph.contract_conformances.items) |conformance| {
            if (@intFromEnum(result.graph.moduleForDeclaration(conformance.declaration).?) != 0) continue;
            const arguments = result.graph.generic_arguments.items[conformance.participants.start..][0..conformance.participants.len];
            if (@import("../global/types.zig").equal(&result.graph, arguments[0].value.type, arguments[1].value.type)) {
                try std.testing.expectEqual(@as(u32, 1), conformance.implementation_arguments.len);
                specialized += 1;
            } else try std.testing.expectEqual(@as(u32, 2), conformance.implementation_arguments.len);
        }
        try std.testing.expectEqual(@as(usize, 1), specialized);
    }
}

test "nested reference array specificity selects the element parameter" {
    const allocator = std.testing.allocator;
    const original = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "tests/feature_tests/contracts/140_nested_reference_array_patterns/main.rg", allocator, .limited(64 * 1024));
    defer allocator.free(original);
    const first = std.mem.indexOf(u8, original, "implement#").?;
    const second = std.mem.indexOfPos(u8, original, first + 1, "implement#").?;
    const third = std.mem.indexOfPos(u8, original, second + 1, "implement#").?;
    const main = std.mem.indexOf(u8, original, "main :=").?;
    const reversed = try std.fmt.allocPrint(allocator, "{s}{s}{s}{s}{s}", .{ original[0..first], original[third..main], original[second..third], original[first..second], original[main..] });
    defer allocator.free(reversed);
    for ([_][]const u8{ original, reversed }) |source| {
        var tree = try parseSource(allocator, source, @enumFromInt(0));
        defer tree.deinit(allocator);
        var module = try @import("semantizer.zig").build(allocator, "nested", &.{.{ .path = "nested/main.rg", .tree = &tree, .source = source }});
        defer module.graph.deinit(allocator);
        var arithmetic_core = try buildArithmeticTestCore(allocator);
        defer arithmetic_core.graph.deinit(allocator);
        var result = try @import("../global/semantizer.zig").semantize(allocator, &.{ module.graph, arithmetic_core.graph });
        defer result.deinit(allocator);
        var subject: ?@TypeOf(result.graph.contract_conformances.items[0]) = null;
        for (result.graph.contract_conformances.items) |conformance| {
            if (@intFromEnum(result.graph.moduleForDeclaration(conformance.declaration).?) != 0) continue;
            try std.testing.expect(subject == null);
            subject = conformance;
        }
        const conformance = subject.?;
        const element = result.graph.generic_arguments.items[conformance.implementation_arguments.start].value.type;
        const ty = result.graph.types.items[@intFromEnum(element)];
        try std.testing.expect(ty == .builtin);
        try std.testing.expectEqual(@import("../primitives/schema.zig").BuiltinType.Int32, ty.builtin);
    }
}

fn buildArithmeticTestCore(allocator: std.mem.Allocator) !module_semantizer.BuildResult {
    const source = @import("../../test_support.zig").arithmetic_core_source;
    var tree = try parseSource(allocator, source, @enumFromInt(0));
    defer tree.deinit(allocator);
    var result = try module_semantizer.build(allocator, "arithmetic_core", &.{.{ .path = "arithmetic_core/scalar_arithmetic.rg", .tree = &tree, .source = source }});
    result.graph.is_bundled_core = true;
    return result;
}

test "compile-time integer calls retain executable parameterized nodes" {
    const allocator = std.testing.allocator;
    const source =
        "compute(.value: Int32) -> (.result: Int32 = value) := {}\n" ++
        "repeat#(.n: Int32)(.value: Int32) -> (.result: Int32 = value) := {}\n" ++
        "Holder#(.n: Int32): Type = (.value: Int32)\n" ++
        "main() -> () := { repeat#(.n = #run () -> (.answer: Int32) { answer = compute(.value = 4) })(.value = 42) }\n" ++
        "use(.value: Holder#(.n = #run () -> (.answer: Int32) { answer = compute(.value = 3) })) -> () := {}\n";
    var tree = try parseSource(allocator, source, @enumFromInt(0));
    defer tree.deinit(allocator);
    var module = try @import("semantizer.zig").build(allocator, "staged", &.{.{ .path = "staged/main.rg", .tree = &tree, .source = source }});
    defer module.graph.deinit(allocator);
    var found = false;
    for (module.graph.semantic.external_refs.items) |reference| {
        if (!std.mem.eql(u8, module.graph.text(reference.name), "repeat")) continue;
        const arguments = reference.computed_arguments orelse continue;
        const storage = &module.graph.semantic.parameterized_storage.ir;
        const argument = storage.generic_arguments.items[arguments.start];
        const expression = storage.int_expressions.items[@intFromEnum(argument.value.comptime_int)];
        const node = storage.nodes.items[@intFromEnum(expression.execution)];
        const pending = storage.pending.items[@intFromEnum(node.pending)].resolve_expression;
        try std.testing.expect(pending.comptime_run);
        var retained_entry = false;
        for (module.graph.semantic.parameterized_storage.parameterized_functions.items) |function| {
            const declaration = module.graph.declarations.items[@intFromEnum(function.declaration)];
            if (!std.mem.eql(u8, module.graph.text(declaration.name), module.graph.text(pending.name.?))) continue;
            try std.testing.expect(@intFromEnum(function.declaration) >= module.graph.declarations.items.len - module.graph.generated_declaration_count);
            try std.testing.expect(function.body != null);
            try std.testing.expectEqual(@as(u32, 1), function.output_bindings.len);
            retained_entry = true;
        }
        try std.testing.expect(retained_entry);
        found = true;
    }
    try std.testing.expect(found);
    const codec = @import("../../0_commands/module_cache_codec.zig");
    const fingerprint: [32]u8 = @splat(0);
    const encoded = try codec.encode(allocator, &module.graph, fingerprint);
    defer allocator.free(encoded);
    var decoded = try codec.decode(allocator, encoded, fingerprint);
    defer decoded.deinit(allocator);
    var retained = false;
    for (decoded.semantic.parameterized_storage.ir.int_expressions.items) |expression| {
        if (expression != .execution) continue;
        const storage = &decoded.semantic.parameterized_storage.ir;
        const node = storage.nodes.items[@intFromEnum(expression.execution)];
        const pending = storage.pending.items[@intFromEnum(node.pending)].resolve_expression;
        try std.testing.expect(pending.comptime_run);
        var retained_entry = false;
        for (decoded.semantic.parameterized_storage.parameterized_functions.items) |function| {
            const declaration = decoded.declarations.items[@intFromEnum(function.declaration)];
            if (!std.mem.eql(u8, decoded.text(declaration.name), decoded.text(pending.name.?))) continue;
            try std.testing.expect(@intFromEnum(function.declaration) >= decoded.declarations.items.len - decoded.generated_declaration_count);
            try std.testing.expect(function.body != null);
            try std.testing.expectEqual(@as(u32, 1), function.output_bindings.len);
            retained_entry = true;
        }
        try std.testing.expect(retained_entry);
        retained = true;
    }
    try std.testing.expect(retained);
    var has_computed_type = false;
    for (decoded.semantic.external_refs.items) |reference|
        if (reference.computed_type != null) {
            has_computed_type = true;
        };
    try std.testing.expect(has_computed_type);
    const storage = &decoded.semantic.parameterized_storage.ir;
    for (storage.int_expressions.items) |*expression| {
        if (expression.* != .execution) continue;
        expression.execution = @enumFromInt(storage.nodes.items.len);
        break;
    }
    try std.testing.expectError(error.InvalidModuleParameterizedIR, @import("parameterized/ir_verify.zig").verifyIR(&decoded));
}

test "inferred module aggregates retain unresolved root types until global resolution" {
    const allocator = std.testing.allocator;
    const source = "record ::= (.inner = (.number = 9))\n";
    var tree = try parseSource(allocator, source, @enumFromInt(0));
    defer tree.deinit(allocator);
    var result = try module_semantizer.build(allocator, "aggregate", &.{.{ .path = "aggregate/main.rg", .tree = &tree, .source = source }});
    defer result.graph.deinit(allocator);
    const graph = &result.graph;
    const binding = graph.semantic.declaration_bindings.items[0].binding;
    try std.testing.expect(@import("views.zig").bindingTypeUnresolved(graph, binding));
    var found = false;
    for (graph.semantic.nodes.items) |node| {
        if (node != .resolved or node.resolved.content != .binding_declaration) continue;
        if (node.resolved.content.binding_declaration != binding) continue;
        found = true;
        try std.testing.expectEqual(@as(?module_graph.ModuleTypeId, null), node.resolved.ty);
    }
    try std.testing.expect(found);
}

fn buildInterfaces(allocator: std.mem.Allocator, directory: []const u8, files: []const module_graph.FileInput) !module_graph.ModuleSemanticGraph {
    var graph = try module_graph.build(allocator, directory, files);
    errdefer graph.deinit(allocator);
    _ = try initializer_lowerer.lower(allocator, &graph, files, null);
    return graph;
}

test "canonical choice construction keeps siblings contiguous across nested payloads" {
    const allocator = std.testing.allocator;
    const source = "Result := (..first (..inner Int32, ..empty), ..second UInt8)\ninspect := (.value: (..left (..nested Int32, ..none), ..right UInt8)) -> () {}\n";
    var tree = try parseSource(allocator, source, @enumFromInt(0));
    defer tree.deinit(allocator);
    var graph = try buildInterfaces(allocator, "nested_choices", &.{.{ .path = "nested_choices/main.rg", .tree = &tree, .source = source }});
    defer graph.deinit(allocator);
    const named = graph.declarations.items[0].choice_variants.?;
    try std.testing.expectEqualStrings("first", graph.text(graph.semantic.variants.items[named.start].name));
    try std.testing.expectEqualStrings("second", graph.text(graph.semantic.variants.items[named.start + 1].name));
    const nested = graph.semantic.types.items[@intFromEnum(graph.semantic.variants.items[named.start].payload_type.?)].resolved.structural_choice.variants;
    try std.testing.expectEqualStrings("inner", graph.text(graph.semantic.variants.items[nested.start].name));
    try std.testing.expectEqualStrings("empty", graph.text(graph.semantic.variants.items[nested.start + 1].name));
    try std.testing.expect(nested.start + nested.len <= named.start);
    const function = graph.functions.items[0];
    const input = graph.semantic.fields.items[function.input.start].ty;
    const anonymous = graph.semantic.types.items[@intFromEnum(input)].resolved.structural_choice.variants;
    try std.testing.expectEqualStrings("left", graph.text(graph.semantic.variants.items[anonymous.start].name));
    try std.testing.expectEqualStrings("right", graph.text(graph.semantic.variants.items[anonymous.start + 1].name));
}
