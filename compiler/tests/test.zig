const std = @import("std");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const allocator = std.heap.page_allocator;
// const allocator = std.testing.allocator;

fn clean() !void {
    // Borrar ./output y ./output.ll si existen
    const cwd = std.fs.cwd();
    cwd.deleteFile("output.ll") catch |err| {
        if (err != error.FileNotFound) return err; // Ignorar si no existe
    };
    cwd.deleteFile("output") catch |err| {
        if (err != error.FileNotFound) return err; // Ignorar si no existe
    };
}

fn build(name: []const u8) !void {
    // Ejecutar el comando de compilación
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "./zig-out/bin/argi", "build", name },
    });
    try expectEqual(std.process.Child.Term{ .Exited = 0 }, result.term);
}

fn buildExpectFail(name: []const u8, expected_stderr: []const u8) !void {
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "./zig-out/bin/argi", "build", name },
    });

    switch (result.term) {
        .Exited => |code| try expect(code != 0),
        else => return error.UnexpectedProcessTermination,
    }

    try expect(std.mem.indexOf(u8, result.stderr, expected_stderr) != null);
}

fn run() !void {
    // Ejecutar el comando de compilación
    _ = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{"./output"},
    });
}

test "00_minimal_main" {
    try clean();
    try build("tests/cases/00_minimal_main/main.rg");
    try run();
}

test "01_comments" {
    try clean();
    try build("tests/cases/01_comments/main.rg");
    try run();
}

test "02_constants_and_variables" {
    try clean();
    try build("tests/cases/02_constants_and_variables/main.rg");
    try run();
}

test "03_expressions_and_type_inference" {
    try clean();
    try build("tests/cases/03_expressions_and_type_inference/main.rg");
    try run();
}

test "04_literals" {
    try clean();
    try build("tests/cases/04_literals/main.rg");
    try run();
}

test "050_anonymous_structs" {
    try clean();
    try build("tests/cases/050_anonymous_structs/main.rg");
    try run();
}

test "051_struct_default_fields" {
    try clean();
    try build("tests/cases/051_struct_default_fields/main.rg");
    try run();
}

test "052_struct_field_store" {
    try clean();
    try build("tests/cases/052_struct_field_store/main.rg");
    try run();
}

test "11_function_calling" {
    try clean();
    try build("tests/cases/11_function_calling/main.rg");
    try run();
}

test "12_function_args" {
    try clean();
    try build("tests/cases/12_function_args/main.rg");
    try run();
}

test "130_multiple_dispatch" {
    try clean();
    try build("tests/cases/130_multiple_dispatch/main.rg");
    try run();
}

test "21_named_struct_types" {
    try clean();
    try build("tests/cases/21_named_struct_types/main.rg");
    try run();
}

test "221_pointers" {
    try clean();
    try build("tests/cases/221_pointers/main.rg");
    try run();
}

test "222_read-only_vs_read-and-write_pointers" {
    try clean();
    try build("tests/cases/222_read-only_vs_read-and-write_pointers/main.rg");
    try run();
}

test "30_core_and_libc" {
    try clean();
    try build("tests/cases/30_core_and_libc/main.rg");
    try run();
}

test "321_generic_functions" {
    try clean();
    try build("tests/cases/321_generic_functions/main.rg");
    try run();
}

test "322_generic_structs" {
    try clean();
    try build("tests/cases/322_generic_structs/main.rg");
    try run();
}

test "323_generic_functions_multi" {
    try clean();
    try build("tests/cases/323_generic_functions_multi/main.rg");
    try run();
}

test "324_generic_structs_multi" {
    try clean();
    try build("tests/cases/324_generic_structs_multi/main.rg");
    try run();
}

test "331_abstract" {
    try clean();
    try build("tests/cases/331_abstract/main.rg");
    try run();
}

test "334_abstract_instantiation" {
    try clean();
    try build("tests/cases/334_abstract_instantiation/main.rg");
    try run();
}

test "351_init" {
    try clean();
    try build("tests/cases/351_init/main.rg");
    try run();
}

test "352_defer" {
    try clean();
    try build("tests/cases/352_defer/main.rg");
    try run();
}

test "353_deinit" {
    try clean();
    try build("tests/cases/353_deinit/main.rg");
    try run();
}

test "36_get_and_set_index_operators" {
    try clean();
    try build("tests/cases/36_get_and_set_index_operators/main.rg");
    try run();
}

test "37_size_of_and_alignment_of_builtin_functions" {
    try clean();
    try build("tests/cases/37_size_of_and_alignment_of_builtin_functions/main.rg");
    try run();
}

test "411_list_literal_length" {
    try clean();
    try build("tests/cases/411_list_literal_length/main.rg");
    try run();
}

test "412_list_literal_access" {
    try clean();
    try build("tests/cases/412_list_literal_access/main.rg");
    try run();
}

test "413_arrays" {
    try clean();
    try build("tests/cases/413_arrays/main.rg");
    try run();
}

test "62_folder_module_namespace" {
    try clean();
    try build("tests/cases/62_folder_module_namespace/main.rg");
    try run();
}

test "63_import_relative" {
    try clean();
    try build("tests/cases/63_import_relative/main.rg");
    try run();
}

test "64_import_missing_module" {
    try clean();
    try buildExpectFail(
        "tests/cases/64_import_missing_module/main.rg",
        "failed to open module directory",
    );
}

test "65_import_missing_value" {
    try clean();
    try buildExpectFail(
        "tests/cases/65_import_missing_value/main.rg",
        "module has no value '.missing_value'",
    );
}

test "66_import_missing_overload" {
    try clean();
    try buildExpectFail(
        "tests/cases/66_import_missing_overload/main.rg",
        "module 'dep' has no function named 'missing_func'",
    );
}

test "67_private_module_value" {
    try clean();
    try buildExpectFail(
        "tests/cases/67_private_module_value/main.rg",
        "value '_hidden_value' is private to its module",
    );
}

test "68_private_module_type" {
    try clean();
    try buildExpectFail(
        "tests/cases/68_private_module_type/main.rg",
        "type '_HiddenStatus' is private to its module",
    );
}

test "69_private_module_function" {
    try clean();
    try buildExpectFail(
        "tests/cases/69_private_module_function/main.rg",
        "function '_hidden_status' is private to its module",
    );
}

test "70_import_more_module" {
    try clean();
    try build("tests/cases/70_import_more_module/main.rg");
    try run();
}

test "71_transitive_import" {
    try clean();
    try build("tests/cases/71_transitive_import/main.rg");
    try run();
}

test "72_import_cycle" {
    try clean();
    try buildExpectFail(
        "tests/cases/72_import_cycle/main.rg",
        "import cycle detected",
    );
}

test "73_import_statement_exports" {
    try clean();
    try build("tests/cases/73_import_statement_exports/main.rg");
    try run();
}

test "74_import_statement_private" {
    try clean();
    try buildExpectFail(
        "tests/cases/74_import_statement_private/main.rg",
        "value '_hidden_value' is private to its module",
    );
}

test "75_missing_function_name" {
    try clean();
    try buildExpectFail(
        "tests/cases/75_missing_function_name/main.rg",
        "no function named 'missing_func' exists",
    );
}
