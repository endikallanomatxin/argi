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

fn runExpect(expected_code: u8) !void {
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{"./output"},
    });
    try expectEqual(std.process.Child.Term{ .Exited = expected_code }, result.term);
}

fn run() !void {
    try runExpect(0);
}

test "00_minimal_main" {
    try clean();
    try build("tests/00_minimal_main/main.rg");
    try run();
}

test "01_comments" {
    try clean();
    try build("tests/01_comments/main.rg");
    try run();
}

test "02_constants_and_variables" {
    try clean();
    try build("tests/02_constants_and_variables/main.rg");
    try run();
}

test "03_expressions_and_type_inference" {
    try clean();
    try build("tests/03_expressions_and_type_inference/main.rg");
    try runExpect(3);
}

test "04_literals" {
    try clean();
    try build("tests/04_literals/main.rg");
    try run();
}

test "06_if" {
    try clean();
    try build("tests/06_if/main.rg");
    try run();
}

test "050_anonymous_structs" {
    try clean();
    try build("tests/050_anonymous_structs/main.rg");
    try run();
}

test "051_struct_default_fields" {
    try clean();
    try build("tests/051_struct_default_fields/main.rg");
    try run();
}

test "052_struct_field_store" {
    try clean();
    try build("tests/052_struct_field_store/main.rg");
    try run();
}

test "053X_integer_literal_overflow" {
    try clean();
    try buildExpectFail(
        "tests/053X_integer_literal_overflow/main.rg",
        "integer literal 300 does not fit in 'UInt8' (max 255)",
    );
}

test "054X_signed_integer_literal_overflow" {
    try clean();
    try buildExpectFail(
        "tests/054X_signed_integer_literal_overflow/main.rg",
        "integer literal 128 does not fit in 'Int8' (min -128, max 127)",
    );
}

test "11_function_calling" {
    try clean();
    try build("tests/11_function_calling/main.rg");
    try runExpect(42);
}

test "12_function_args" {
    try clean();
    try build("tests/12_function_args/main.rg");
    try runExpect(42);
}

test "130_multiple_dispatch" {
    try clean();
    try build("tests/130_multiple_dispatch/main.rg");
    try runExpect(2);
}

test "131X_multiple_dispatch_ambiguous" {
    try clean();
    try buildExpectFail(
        "tests/131X_multiple_dispatch_ambiguous/main.rg",
        "ambiguous call to 'choose2'",
    );
}

test "21_named_struct_types" {
    try clean();
    try build("tests/21_named_struct_types/main.rg");
    try run();
}

test "221_pointers" {
    try clean();
    try build("tests/221_pointers/main.rg");
    try run();
}

test "222_read-only_vs_read-and-write_pointers" {
    try clean();
    try build("tests/222_read-only_vs_read-and-write_pointers/main.rg");
    try run();
}

test "223X_assign_through_readonly_pointer" {
    try clean();
    try buildExpectFail(
        "tests/223X_assign_through_readonly_pointer/main.rg",
        "cannot assign through pointer '&Int32' because it is read-only",
    );
}

test "224X_read-write_pointer_to_constant" {
    try clean();
    try buildExpectFail(
        "tests/224X_read-write_pointer_to_constant/main.rg",
        "binding 'value' is immutable",
    );
}

test "225X_pass_readonly_pointer_to_mutable_param" {
    try clean();
    try buildExpectFail(
        "tests/225X_pass_readonly_pointer_to_mutable_param/main.rg",
        "no overload of 'increment' accepts arguments (.ptr: &Int32)",
    );
}

test "226_explicit_pointer_casts" {
    try clean();
    try build("tests/226_explicit_pointer_casts/main.rg");
    try run();
}

test "227X_pointer_arithmetic_requires_cast" {
    try clean();
    try buildExpectFail(
        "tests/227X_pointer_arithmetic_requires_cast/main.rg",
        "pointer arithmetic is not allowed; cast explicitly to an integer, perform the arithmetic, and cast back",
    );
}

test "228X_array_index_requires_uint_native" {
    try clean();
    try buildExpectFail(
        "tests/228X_array_index_requires_uint_native/main.rg",
        "array index must be 'UIntNative'",
    );
}

test "30_core_and_libc" {
    try clean();
    try build("tests/30_core_and_libc/main.rg");
    try run();
}

test "321_generic_functions" {
    try clean();
    try build("tests/321_generic_functions/main.rg");
    try runExpect(42);
}

test "322_generic_structs" {
    try clean();
    try build("tests/322_generic_structs/main.rg");
    try runExpect(42);
}

test "323_generic_functions_multi" {
    try clean();
    try build("tests/323_generic_functions_multi/main.rg");
    try runExpect(42);
}

test "324_generic_structs_multi" {
    try clean();
    try build("tests/324_generic_structs_multi/main.rg");
    try runExpect(20);
}

test "331_abstract" {
    try clean();
    try build("tests/331_abstract/main.rg");
    try run();
}

test "332X_abstract_missing_requirement" {
    try clean();
    try buildExpectFail(
        "tests/332X_abstract_missing_requirement/main.rg",
        "type does not implement abstract 'Animal':\n  missing function: speak (.who: Dog)",
    );
}

test "333X_abstract_wrong_signature" {
    try clean();
    try buildExpectFail(
        "tests/333X_abstract_wrong_signature/main.rg",
        "type does not implement abstract 'Animal':\n  missing function: speak (.who: Dog)",
    );
}

test "334_abstract_instantiation" {
    try clean();
    try build("tests/334_abstract_instantiation/main.rg");
    try run();
}

test "336X_abstract_function_input_requires_default" {
    try clean();
    try buildExpectFail(
        "tests/336X_abstract_function_input_requires_default/main.rg",
        "abstract types without a default are not supported in this function signature position yet",
    );
}

test "338X_abstract_function_output_requires_default" {
    try clean();
    try buildExpectFail(
        "tests/338X_abstract_function_output_requires_default/main.rg",
        "abstract types without a default are not supported in this function signature position yet",
    );
}

test "351_init" {
    try clean();
    try build("tests/351_init/main.rg");
    try run();
}

test "352_defer" {
    try clean();
    try build("tests/352_defer/main.rg");
    try run();
}

test "353_deinit" {
    try clean();
    try build("tests/353_deinit/main.rg");
    try run();
}

test "36_get_and_set_index_operators" {
    try clean();
    try build("tests/36_get_and_set_index_operators/main.rg");
    try run();
}

test "37_size_of_and_alignment_of_builtin_functions" {
    try clean();
    try build("tests/37_size_of_and_alignment_of_builtin_functions/main.rg");
    try run();
}

test "411_list_literal_length" {
    try clean();
    try build("tests/411_list_literal_length/main.rg");
    try run();
}

test "412_list_literal_access" {
    try clean();
    try build("tests/412_list_literal_access/main.rg");
    try run();
}

test "413_arrays" {
    try clean();
    try build("tests/413_arrays/main.rg");
    try run();
}

test "417_array_index_uint_native" {
    try clean();
    try build("tests/417_array_index_uint_native/main.rg");
    try run();
}

test "62_folder_module_namespace" {
    try clean();
    try build("tests/62_folder_module_namespace/main.rg");
    try runExpect(1);
}

test "63_import_current_relative" {
    try clean();
    try build("tests/63_import_current_relative/main.rg");
    try run();
}

test "64X_import_missing_module" {
    try clean();
    try buildExpectFail(
        "tests/64X_import_missing_module/main.rg",
        "cannot resolve import './missing_dep'",
    );
}

test "65X_import_missing_value" {
    try clean();
    try buildExpectFail(
        "tests/65X_import_missing_value/main.rg",
        "module has no value '.missing_value'",
    );
}

test "66X_import_missing_overload" {
    try clean();
    try buildExpectFail(
        "tests/66X_import_missing_overload/main.rg",
        "module 'dep' has no function named 'missing_func'",
    );
}

test "67X_private_module_value" {
    try clean();
    try buildExpectFail(
        "tests/67X_private_module_value/main.rg",
        "value '_hidden_value' is private to its module",
    );
}

test "68X_private_module_type" {
    try clean();
    try buildExpectFail(
        "tests/68X_private_module_type/main.rg",
        "type '_HiddenStatus' is private to its module",
    );
}

test "69X_private_module_function" {
    try clean();
    try buildExpectFail(
        "tests/69X_private_module_function/main.rg",
        "function '_hidden_status' is private to its module",
    );
}

test "70_import_more_library" {
    try clean();
    try build("tests/70_import_more_library/main.rg");
    try run();
}

test "71_import_transitive" {
    try clean();
    try build("tests/71_import_transitive/main.rg");
    try run();
}

test "72X_import_cycle" {
    try clean();
    try buildExpectFail(
        "tests/72X_import_cycle/main.rg",
        "import cycle detected",
    );
}

test "73X_import_requires_binding" {
    try clean();
    try buildExpectFail(
        "tests/73X_import_requires_binding/main.rg",
        "#import must be assigned to a name",
    );
}

test "74X_import_requires_binding_nested" {
    try clean();
    try buildExpectFail(
        "tests/74X_import_requires_binding_nested/main.rg",
        "#import must be assigned to a name",
    );
}

test "75X_missing_function_name" {
    try clean();
    try buildExpectFail(
        "tests/75X_missing_function_name/main.rg",
        "no function named 'missing_func' exists",
    );
}

test "76_import_root_relative" {
    try clean();
    try build("tests/76_import_root_relative/project/app/main.rg");
    try run();
}

test "77X_root_relative_missing_import" {
    try clean();
    try buildExpectFail(
        "tests/77X_root_relative_missing_import/project/app/main.rg",
        "cannot resolve import '.../missing_shared'",
    );
}
