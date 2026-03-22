const std = @import("std");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

const argi_bin = "./zig-out/bin/argi";
const output_bin = "./output";

fn modulePathFor(path: []const u8) []const u8 {
    if (std.mem.endsWith(u8, path, "/main.rg")) {
        return std.fs.path.dirname(path) orelse path;
    }
    return path;
}

fn clean() !void {
    const cwd = std.fs.cwd();
    cwd.deleteFile("output.ll") catch |err| {
        if (err != error.FileNotFound) return err;
    };
    cwd.deleteFile("output") catch |err| {
        if (err != error.FileNotFound) return err;
    };
    cwd.deleteFile("output.o") catch |err| {
        if (err != error.FileNotFound) return err;
    };
}

fn runChild(argv: []const []const u8) !std.process.Child.RunResult {
    return std.process.Child.run(.{
        .allocator = std.testing.allocator,
        .argv = argv,
    });
}

fn buildResult(name: []const u8) !std.process.Child.RunResult {
    return runChild(&[_][]const u8{ argi_bin, "build", modulePathFor(name) });
}

fn expectSuccessfulBuild(name: []const u8) !void {
    const result = try buildResult(name);
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);
    try expectEqual(std.process.Child.Term{ .Exited = 0 }, result.term);
}

fn buildExpectFail(name: []const u8, expected_stderr: []const u8) !void {
    const result = try buildResult(name);
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);

    switch (result.term) {
        .Exited => |code| try expect(code != 0),
        else => return error.UnexpectedProcessTermination,
    }

    try expect(std.mem.indexOf(u8, result.stderr, expected_stderr) != null);
}

fn runExpect(expected_code: u8) !void {
    const result = try runChild(&[_][]const u8{output_bin});
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);
    try expectEqual(std.process.Child.Term{ .Exited = expected_code }, result.term);
}

fn run() !void {
    try runExpect(0);
}

test "00_minimal_main" {
    try clean();
    try expectSuccessfulBuild("tests/00_minimal_main/main.rg");
    try run();
}

test "01_comments" {
    try clean();
    try expectSuccessfulBuild("tests/01_comments/main.rg");
    try run();
}

test "02_constants_and_variables" {
    try clean();
    try expectSuccessfulBuild("tests/02_constants_and_variables/main.rg");
    try run();
}

test "03_expressions_and_type_inference" {
    try clean();
    try expectSuccessfulBuild("tests/03_expressions_and_type_inference/main.rg");
    try runExpect(3);
}

test "04_literals" {
    try clean();
    try expectSuccessfulBuild("tests/04_literals/main.rg");
    try run();
}

test "06_if" {
    try clean();
    try expectSuccessfulBuild("tests/06_if/main.rg");
    try run();
}

test "050_anonymous_structs" {
    try clean();
    try expectSuccessfulBuild("tests/050_anonymous_structs/main.rg");
    try run();
}

test "051_struct_default_fields" {
    try clean();
    try expectSuccessfulBuild("tests/051_struct_default_fields/main.rg");
    try run();
}

test "052_struct_field_store" {
    try clean();
    try expectSuccessfulBuild("tests/052_struct_field_store/main.rg");
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

test "055X_negative_integer_literal_overflow" {
    try clean();
    try buildExpectFail(
        "tests/055X_negative_integer_literal_overflow/main.rg",
        "integer literal -129 does not fit in 'Int8' (min -128, max 127)",
    );
}

test "11_function_calling" {
    try clean();
    try expectSuccessfulBuild("tests/11_function_calling/main.rg");
    try runExpect(42);
}

test "12_function_args" {
    try clean();
    try expectSuccessfulBuild("tests/12_function_args/main.rg");
    try runExpect(42);
}

test "13_pipe_operator" {
    try clean();
    try expectSuccessfulBuild("tests/13_pipe_operator/main.rg");
    try runExpect(42);
}

test "14_pipe_pointer" {
    try clean();
    try expectSuccessfulBuild("tests/14_pipe_pointer/main.rg");
    try runExpect(42);
}

test "15X_pipe_requires_parentheses" {
    try clean();
    try buildExpectFail(
        "tests/15X_pipe_requires_parentheses/main.rg",
        "pipe right-hand side must use at least one argument placeholder",
    );
}

test "16X_pipe_requires_placeholder" {
    try clean();
    try buildExpectFail(
        "tests/16X_pipe_requires_placeholder/main.rg",
        "expected struct field",
    );
}

test "17X_pipe_expression_placeholder_not_supported" {
    try clean();
    try buildExpectFail(
        "tests/17X_pipe_expression_placeholder_not_supported/main.rg",
        "expected struct field",
    );
}

test "18_pipe_chain" {
    try clean();
    try expectSuccessfulBuild("tests/18_pipe_chain/main.rg");
    try runExpect(42);
}

test "19_pipe_generic_inferred" {
    try clean();
    try expectSuccessfulBuild("tests/19_pipe_generic_inferred/main.rg");
    try runExpect(42);
}

test "20_pipe_generic_explicit" {
    try clean();
    try expectSuccessfulBuild("tests/20_pipe_generic_explicit/main.rg");
    try runExpect(42);
}

test "21_pipe_builtin_is" {
    try clean();
    try expectSuccessfulBuild("tests/21_pipe_builtin_is/main.rg");
    try run();
}

test "130_multiple_dispatch" {
    try clean();
    try expectSuccessfulBuild("tests/130_multiple_dispatch/main.rg");
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
    try expectSuccessfulBuild("tests/21_named_struct_types/main.rg");
    try run();
}

test "221_pointers" {
    try clean();
    try expectSuccessfulBuild("tests/221_pointers/main.rg");
    try run();
}

test "222_read-only_vs_read-and-write_pointers" {
    try clean();
    try expectSuccessfulBuild("tests/222_read-only_vs_read-and-write_pointers/main.rg");
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
    try expectSuccessfulBuild("tests/226_explicit_pointer_casts/main.rg");
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
    try expectSuccessfulBuild("tests/30_core_and_libc/main.rg");
    try run();
}

test "321_generic_functions" {
    try clean();
    try expectSuccessfulBuild("tests/321_generic_functions/main.rg");
    try runExpect(42);
}

test "322_generic_structs" {
    try clean();
    try expectSuccessfulBuild("tests/322_generic_structs/main.rg");
    try runExpect(42);
}

test "323_generic_functions_multi" {
    try clean();
    try expectSuccessfulBuild("tests/323_generic_functions_multi/main.rg");
    try runExpect(42);
}

test "324_generic_structs_multi" {
    try clean();
    try expectSuccessfulBuild("tests/324_generic_structs_multi/main.rg");
    try runExpect(20);
}

test "325_generic_statement_type_arguments" {
    try clean();
    try expectSuccessfulBuild("tests/325_generic_statement_type_arguments/main.rg");
    try run();
}

test "331_abstract" {
    try clean();
    try expectSuccessfulBuild("tests/331_abstract/main.rg");
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
    try expectSuccessfulBuild("tests/334_abstract_instantiation/main.rg");
    try run();
}

test "335X_abstract_instantiation_missing_default" {
    try clean();
    try buildExpectFail(
        "tests/335X_abstract_instantiation_missing_default/main.rg",
        "cannot use abstract 'ExampleAbstract' as a type for a symbol",
    );
}

test "339_abstract_self_output" {
    try clean();
    try expectSuccessfulBuild("tests/339_abstract_self_output/main.rg");
    try run();
}

test "340X_abstract_self_output_wrong" {
    try clean();
    try buildExpectFail(
        "tests/340X_abstract_self_output_wrong/main.rg",
        "type does not implement abstract 'Animal':\n  missing function: clone (.who: Dog)",
    );
}

test "341_abstract_function_input_monomorphization" {
    try clean();
    try expectSuccessfulBuild("tests/341_abstract_function_input_monomorphization/main.rg");
    try runExpect(7);
}

test "342_abstract_dispatch_prefers_concrete" {
    try clean();
    try expectSuccessfulBuild("tests/342_abstract_dispatch_prefers_concrete/main.rg");
    try runExpect(2);
}

test "343_abstract_monomorphization_isolation" {
    try clean();
    try expectSuccessfulBuild("tests/343_abstract_monomorphization_isolation/main.rg");
    try runExpect(3);
}

test "336X_abstract_function_input_requires_implementation" {
    try clean();
    try buildExpectFail(
        "tests/336X_abstract_function_input_requires_implementation/main.rg",
        "type 'Int32' does not implement abstract 'ExampleAbstract' required by parameter '.value' of 'use_value'",
    );
}

test "338X_abstract_function_output_requires_default" {
    try clean();
    try buildExpectFail(
        "tests/338X_abstract_function_output_requires_default/main.rg",
        "abstract types without a default are not supported in function outputs yet",
    );
}

test "351_init" {
    try clean();
    try expectSuccessfulBuild("tests/351_init/main.rg");
    try run();
}

test "352_defer" {
    try clean();
    try expectSuccessfulBuild("tests/352_defer/main.rg");
    try run();
}

test "353_deinit" {
    try clean();
    try expectSuccessfulBuild("tests/353_deinit/main.rg");
    try run();
}

test "354_noncopyable_temporary_values" {
    try clean();
    try expectSuccessfulBuild("tests/354_noncopyable_temporary_values/main.rg");
    try run();
}

test "355X_noncopyable_assignment" {
    try clean();
    try buildExpectFail(
        "tests/355X_noncopyable_assignment/main.rg",
        "type 'Resource' is not copyable, so it cannot be used by value here",
    );
}

test "356X_noncopyable_argument_by_value" {
    try clean();
    try buildExpectFail(
        "tests/356X_noncopyable_argument_by_value/main.rg",
        "type 'Resource' is not copyable, so it cannot be used by value here",
    );
}

test "357X_noncopyable_struct_field" {
    try clean();
    try buildExpectFail(
        "tests/357X_noncopyable_struct_field/main.rg",
        "type 'Resource' is not copyable, so it cannot be used by value here",
    );
}

test "358X_noncopyable_output_binding" {
    try clean();
    try buildExpectFail(
        "tests/358X_noncopyable_output_binding/main.rg",
        "type 'Resource' is not copyable, so it cannot be used by value here",
    );
}

test "359X_mutable_and_read_alias_same_call" {
    try clean();
    try buildExpectFail(
        "tests/359X_mutable_and_read_alias_same_call/main.rg",
        "binding 'value' cannot be passed as '$&' and '&' in the same call to 'mix'",
    );
}

test "360X_mutable_and_value_alias_same_call" {
    try clean();
    try buildExpectFail(
        "tests/360X_mutable_and_value_alias_same_call/main.rg",
        "binding 'value' cannot be passed as '$&' and 'value' in the same call to 'mix'",
    );
}

test "361X_double_mutable_alias_same_call" {
    try clean();
    try buildExpectFail(
        "tests/361X_double_mutable_alias_same_call/main.rg",
        "binding 'value' cannot be passed as '$&' and '$&' in the same call to 'mix'",
    );
}

test "362_copy_function_value_positions" {
    try clean();
    try expectSuccessfulBuild("tests/362_copy_function_value_positions/main.rg");
    try run();
}

test "363_move_operator" {
    try clean();
    try expectSuccessfulBuild("tests/363_move_operator/main.rg");
    try run();
}

test "364X_use_after_move" {
    try clean();
    try buildExpectFail(
        "tests/364X_use_after_move/main.rg",
        "binding 'handle' was moved and cannot be used again before reinitialization",
    );
}

test "365_move_then_reinitialize" {
    try clean();
    try expectSuccessfulBuild("tests/365_move_then_reinitialize/main.rg");
    try run();
}

test "36_get_and_set_index_operators" {
    try clean();
    try expectSuccessfulBuild("tests/36_get_and_set_index_operators/main.rg");
    try run();
}

test "37_size_of_and_alignment_of_builtin_functions" {
    try clean();
    try expectSuccessfulBuild("tests/37_size_of_and_alignment_of_builtin_functions/main.rg");
    try run();
}

test "42_choice" {
    try clean();
    try expectSuccessfulBuild("tests/42_choice/main.rg");
    try run();
}

test "43_choice_payloads" {
    try clean();
    try expectSuccessfulBuild("tests/43_choice_payloads/main.rg");
    try run();
}

test "44X_choice_missing_payload" {
    try clean();
    try buildExpectFail(
        "tests/44X_choice_missing_payload/main.rg",
        "choice variant '..ok' requires a payload",
    );
}

test "45_choice_is_builtin" {
    try clean();
    try expectSuccessfulBuild("tests/45_choice_is_builtin/main.rg");
    try run();
}

test "46_choice_match" {
    try clean();
    try expectSuccessfulBuild("tests/46_choice_match/main.rg");
    try run();
}

test "47_choice_match_payload_binding" {
    try clean();
    try expectSuccessfulBuild("tests/47_choice_match_payload_binding/main.rg");
    try run();
}

test "48_nullable_generic" {
    try clean();
    try expectSuccessfulBuild("tests/48_nullable_generic/main.rg");
    try run();
}

test "49_errable_generic" {
    try clean();
    try expectSuccessfulBuild("tests/49_errable_generic/main.rg");
    try run();
}

test "50X_choice_unknown_variant" {
    try clean();
    try buildExpectFail(
        "tests/50X_choice_unknown_variant/main.rg",
        "choice type 'Direction' has no variant '..east'",
    );
}

test "51X_choice_payload_access_without_payload" {
    try clean();
    try buildExpectFail(
        "tests/51X_choice_payload_access_without_payload/main.rg",
        "choice variant '..north' has no payload",
    );
}

test "52X_match_non_choice" {
    try clean();
    try buildExpectFail(
        "tests/52X_match_non_choice/main.rg",
        "match expects a choice value, found 'Int32'",
    );
}

test "54X_match_bind_payload_without_payload" {
    try clean();
    try buildExpectFail(
        "tests/54X_match_bind_payload_without_payload/main.rg",
        "choice variant '..north' has no payload to bind",
    );
}

test "411_list_literal_length" {
    try clean();
    try expectSuccessfulBuild("tests/411_list_literal_length/main.rg");
    try run();
}

test "412_list_literal_access" {
    try clean();
    try expectSuccessfulBuild("tests/412_list_literal_access/main.rg");
    try run();
}

test "413_arrays" {
    try clean();
    try expectSuccessfulBuild("tests/413_arrays/main.rg");
    try run();
}

test "414_list_view" {
    try clean();
    try expectSuccessfulBuild("tests/414_list_view/main.rg");
    try run();
}

test "417_array_index_uint_native" {
    try clean();
    try expectSuccessfulBuild("tests/417_array_index_uint_native/main.rg");
    try run();
}

test "418_dynamic_array" {
    try clean();
    try expectSuccessfulBuild("tests/418_dynamic_array/main.rg");
    try run();
}

test "419_dynamic_array_ergonomic" {
    try clean();
    try expectSuccessfulBuild("tests/419_dynamic_array_ergonomic/main.rg");
    try runExpect(80);
}

test "420_string_bytes" {
    try clean();
    try expectSuccessfulBuild("tests/420_string_bytes/main.rg");
    try run();
}

test "421_string_copy" {
    try clean();
    try expectSuccessfulBuild("tests/421_string_copy/main.rg");
    try run();
}

test "422_array_explicit_type" {
    try clean();
    try expectSuccessfulBuild("tests/422_array_explicit_type/main.rg");
    try run();
}

test "423_array_iterator_manual" {
    try clean();
    try expectSuccessfulBuild("tests/423_array_iterator_manual/main.rg");
    try run();
}

test "424_iterator_abstract" {
    try clean();
    try expectSuccessfulBuild("tests/424_iterator_abstract/main.rg");
    try run();
}

test "425X_iterator_abstract_missing_implements" {
    try clean();
    try buildExpectFail(
        "tests/425X_iterator_abstract_missing_implements/main.rg",
        "does not implement abstract 'Iterator'",
    );
}

test "426X_for_requires_iterator_contract" {
    try clean();
    try buildExpectFail(
        "tests/426X_for_requires_iterator_contract/main.rg",
        "for expects 'to_iterator(.value = &...)' to return a type implementing abstract 'Iterator'",
    );
}

test "427_iterable_abstract" {
    try clean();
    try expectSuccessfulBuild("tests/427_iterable_abstract/main.rg");
    try run();
}

test "428X_iterable_abstract_missing_implements" {
    try clean();
    try buildExpectFail(
        "tests/428X_iterable_abstract_missing_implements/main.rg",
        "does not implement abstract 'Iterable'",
    );
}

test "429_range_for" {
    try clean();
    try expectSuccessfulBuild("tests/429_range_for/main.rg");
    try run();
}

test "430_range_step" {
    try clean();
    try expectSuccessfulBuild("tests/430_range_step/main.rg");
    try run();
}

test "431_negative_integer_literals" {
    try clean();
    try expectSuccessfulBuild("tests/431_negative_integer_literals/main.rg");
    try run();
}

test "432_range_int64" {
    try clean();
    try expectSuccessfulBuild("tests/432_range_int64/main.rg");
    try run();
}

test "433_range_default_start" {
    try clean();
    try expectSuccessfulBuild("tests/433_range_default_start/main.rg");
    try run();
}

test "434_generic_type_initializer_from_init" {
    try clean();
    try expectSuccessfulBuild("tests/434_generic_type_initializer_from_init/main.rg");
    try run();
}

test "435_dynamic_array_iterator_manual" {
    try clean();
    try expectSuccessfulBuild("tests/435_dynamic_array_iterator_manual/main.rg");
    try run();
}

test "436_range_default_start_with_step" {
    try clean();
    try expectSuccessfulBuild("tests/436_range_default_start_with_step/main.rg");
    try run();
}

test "437X_for_nullable_not_iterable" {
    try clean();
    try buildExpectFail(
        "tests/437X_for_nullable_not_iterable/main.rg",
        "for expects a type implementing abstract 'Iterable', got 'Nullable#(.t: Int32)'",
    );
}

test "438X_errable_match_unknown_variant" {
    try clean();
    try buildExpectFail(
        "tests/438X_errable_match_unknown_variant/main.rg",
        "choice type 'Errable#(.t: Int32, .e: Char)' has no variant '..none'",
    );
}

test "439_reached_arguments" {
    try clean();
    try expectSuccessfulBuild("tests/439_reached_arguments/main.rg");
    try runExpect(9);
}

test "440X_reached_argument_missing" {
    try clean();
    try buildExpectFail(
        "tests/440X_reached_argument_missing/main.rg",
        "cannot resolve reached argument '.stdout'",
    );
}

test "441_output_stream_capability" {
    try clean();
    try expectSuccessfulBuild("tests/441_output_stream_capability/main.rg");
    try runExpect(1);
}

test "442_reached_output_stream" {
    try clean();
    try expectSuccessfulBuild("tests/442_reached_output_stream/main.rg");
    try runExpect(15);
}

test "443_terminal_stderr_helper" {
    try clean();
    try expectSuccessfulBuild("tests/443_terminal_stderr_helper/main.rg");
    try runExpect(11);
}

test "444_reached_stdin_helper" {
    try clean();
    try expectSuccessfulBuild("tests/444_reached_stdin_helper/main.rg");
    try runExpect(15);
}

test "445_reached_terminal_stdin" {
    try clean();
    try expectSuccessfulBuild("tests/445_reached_terminal_stdin/main.rg");
    try runExpect(16);
}

test "62_folder_module_namespace" {
    try clean();
    try expectSuccessfulBuild("tests/62_folder_module_namespace/main.rg");
    try runExpect(1);
}

test "63_import_current_relative" {
    try clean();
    try expectSuccessfulBuild("tests/63_import_current_relative/main.rg");
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
    try expectSuccessfulBuild("tests/70_import_more_library/main.rg");
    try run();
}

test "71_import_transitive" {
    try clean();
    try expectSuccessfulBuild("tests/71_import_transitive/main.rg");
    try run();
}

test "71_loops" {
    try clean();
    try expectSuccessfulBuild("tests/71_loops/main.rg");
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
    try expectSuccessfulBuild("tests/76_import_root_relative/project/app/main.rg");
    try run();
}

test "77X_root_relative_missing_import" {
    try clean();
    try buildExpectFail(
        "tests/77X_root_relative_missing_import/project/app/main.rg",
        "cannot resolve import '.../missing_shared'",
    );
}

test "78_for_array" {
    try clean();
    try expectSuccessfulBuild("tests/78_for_array/main.rg");
    try run();
}

test "79_for_dynamic_array" {
    try clean();
    try expectSuccessfulBuild("tests/79_for_dynamic_array/main.rg");
    try run();
}
