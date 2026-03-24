const std = @import("std");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

const argi_bin = "zig-out/bin/argi";

fn compilerRoot() []const u8 {
    const this_file = @src().file;
    const tests_dir = std.fs.path.dirname(this_file) orelse ".";
    return std.fs.path.dirname(tests_dir) orelse tests_dir;
}

fn outputPathFor(name: []const u8) ![]u8 {
    return std.fmt.allocPrint(
        std.testing.allocator,
        "{s}/build/output",
        .{name},
    );
}

fn irPathFor(name: []const u8) ![]u8 {
    const output_path = try outputPathFor(name);
    defer std.testing.allocator.free(output_path);

    return std.fmt.allocPrint(
        std.testing.allocator,
        "{s}.ll",
        .{output_path},
    );
}

fn objPathFor(name: []const u8) ![]u8 {
    const output_path = try outputPathFor(name);
    defer std.testing.allocator.free(output_path);

    return std.fmt.allocPrint(
        std.testing.allocator,
        "{s}.o",
        .{output_path},
    );
}

fn clean(name: []const u8) !void {
    var root = try std.fs.cwd().openDir(compilerRoot(), .{});
    defer root.close();

    const output_path = try outputPathFor(name);
    defer std.testing.allocator.free(output_path);

    const ir_path = try irPathFor(name);
    defer std.testing.allocator.free(ir_path);

    const obj_path = try objPathFor(name);
    defer std.testing.allocator.free(obj_path);

    root.deleteFile(ir_path) catch |err| {
        if (err != error.FileNotFound) return err;
    };
    root.deleteFile(output_path) catch |err| {
        if (err != error.FileNotFound) return err;
    };
    root.deleteFile(obj_path) catch |err| {
        if (err != error.FileNotFound) return err;
    };
}

fn runChild(argv: []const []const u8) !std.process.Child.RunResult {
    return std.process.Child.run(.{
        .allocator = std.testing.allocator,
        .argv = argv,
        .cwd = compilerRoot(),
    });
}

fn buildResult(name: []const u8) !std.process.Child.RunResult {
    try clean(name);
    return runChild(&[_][]const u8{
        argi_bin,
        "build",
        name,
    });
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

fn runExpect(name: []const u8, expected_code: u8) !void {
    const output_path = try outputPathFor(name);
    defer std.testing.allocator.free(output_path);

    const result = try runChild(&[_][]const u8{output_path});
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);

    try expectEqual(std.process.Child.Term{ .Exited = expected_code }, result.term);
}

fn run(name: []const u8) !void {
    try runExpect(name, 0);
}

test "00_minimal_main" {
    const test_path = "tests/00_minimal_main";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "01_comments" {
    const test_path = "tests/01_comments";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "02_constants_and_variables" {
    const test_path = "tests/02_constants_and_variables";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "03_expressions_and_type_inference" {
    const test_path = "tests/03_expressions_and_type_inference";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 3);
}

test "04_literals" {
    const test_path = "tests/04_literals";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "06_if" {
    const test_path = "tests/06_if";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "050_anonymous_structs" {
    const test_path = "tests/050_anonymous_structs";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "051_struct_default_fields" {
    const test_path = "tests/051_struct_default_fields";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "052_struct_field_store" {
    const test_path = "tests/052_struct_field_store";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "053X_integer_literal_overflow" {
    try buildExpectFail(
        "tests/053X_integer_literal_overflow",
        "integer literal 300 does not fit in 'UInt8' (max 255)",
    );
}

test "054X_signed_integer_literal_overflow" {
    try buildExpectFail(
        "tests/054X_signed_integer_literal_overflow",
        "integer literal 128 does not fit in 'Int8' (min -128, max 127)",
    );
}

test "055X_negative_integer_literal_overflow" {
    try buildExpectFail(
        "tests/055X_negative_integer_literal_overflow",
        "integer literal -129 does not fit in 'Int8' (min -128, max 127)",
    );
}

test "11_function_calling" {
    const test_path = "tests/11_function_calling";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 42);
}

test "12_function_args" {
    const test_path = "tests/12_function_args";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 42);
}

test "13_pipe_operator" {
    const test_path = "tests/13_pipe_operator";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 42);
}

test "14_pipe_pointer" {
    const test_path = "tests/14_pipe_pointer";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 42);
}

test "15X_pipe_requires_parentheses" {
    try buildExpectFail(
        "tests/15X_pipe_requires_parentheses",
        "pipe right-hand side must use at least one argument placeholder",
    );
}

test "16X_pipe_requires_placeholder" {
    try buildExpectFail(
        "tests/16X_pipe_requires_placeholder",
        "expected struct field",
    );
}

test "17X_pipe_expression_placeholder_not_supported" {
    try buildExpectFail(
        "tests/17X_pipe_expression_placeholder_not_supported",
        "expected struct field",
    );
}

test "18_pipe_chain" {
    const test_path = "tests/18_pipe_chain";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 42);
}

test "19_pipe_generic_inferred" {
    const test_path = "tests/19_pipe_generic_inferred";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 42);
}

test "20_pipe_generic_explicit" {
    const test_path = "tests/20_pipe_generic_explicit";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 42);
}

test "21_pipe_builtin_is" {
    const test_path = "tests/21_pipe_builtin_is";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "130_multiple_dispatch" {
    const test_path = "tests/130_multiple_dispatch";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 2);
}

test "131X_multiple_dispatch_ambiguous" {
    try buildExpectFail(
        "tests/131X_multiple_dispatch_ambiguous",
        "ambiguous call to 'choose2'",
    );
}

test "21_named_struct_types" {
    const test_path = "tests/21_named_struct_types";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "221_pointers" {
    const test_path = "tests/221_pointers";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "222_read-only_vs_read-and-write_pointers" {
    const test_path = "tests/222_read-only_vs_read-and-write_pointers";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "223X_assign_through_readonly_pointer" {
    try buildExpectFail(
        "tests/223X_assign_through_readonly_pointer",
        "cannot assign through pointer '&Int32' because it is read-only",
    );
}

test "224X_read-write_pointer_to_constant" {
    try buildExpectFail(
        "tests/224X_read-write_pointer_to_constant",
        "binding 'value' is immutable",
    );
}

test "225X_pass_readonly_pointer_to_mutable_param" {
    try buildExpectFail(
        "tests/225X_pass_readonly_pointer_to_mutable_param",
        "no overload of 'increment' accepts arguments (.ptr: &Int32)",
    );
}

test "226_explicit_pointer_casts" {
    const test_path = "tests/226_explicit_pointer_casts";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "227X_pointer_arithmetic_requires_cast" {
    try buildExpectFail(
        "tests/227X_pointer_arithmetic_requires_cast",
        "pointer arithmetic is not allowed; cast explicitly to an integer, perform the arithmetic, and cast back",
    );
}

test "228X_array_index_requires_uint_native" {
    try buildExpectFail(
        "tests/228X_array_index_requires_uint_native",
        "array index must be 'UIntNative'",
    );
}

test "30_core_and_libc" {
    const test_path = "tests/30_core_and_libc";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "321_generic_functions" {
    const test_path = "tests/321_generic_functions";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 42);
}

test "322_generic_structs" {
    const test_path = "tests/322_generic_structs";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 42);
}

test "323_generic_functions_multi" {
    const test_path = "tests/323_generic_functions_multi";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 42);
}

test "324_generic_structs_multi" {
    const test_path = "tests/324_generic_structs_multi";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 20);
}

test "325_generic_statement_type_arguments" {
    const test_path = "tests/325_generic_statement_type_arguments";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "331_abstract" {
    const test_path = "tests/331_abstract";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "332X_abstract_missing_requirement" {
    try buildExpectFail(
        "tests/332X_abstract_missing_requirement",
        "type does not implement abstract 'Animal':\n  missing function: speak (.who: Dog)",
    );
}

test "333X_abstract_wrong_signature" {
    try buildExpectFail(
        "tests/333X_abstract_wrong_signature",
        "type does not implement abstract 'Animal':\n  missing function: speak (.who: Dog)",
    );
}

test "334_abstract_instantiation" {
    const test_path = "tests/334_abstract_instantiation";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "335X_abstract_instantiation_missing_default" {
    try buildExpectFail(
        "tests/335X_abstract_instantiation_missing_default",
        "cannot use abstract 'ExampleAbstract' as a type for a symbol",
    );
}

test "339_abstract_self_output" {
    const test_path = "tests/339_abstract_self_output";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "340X_abstract_self_output_wrong" {
    try buildExpectFail(
        "tests/340X_abstract_self_output_wrong",
        "type does not implement abstract 'Animal':\n  missing function: clone (.who: Dog)",
    );
}

test "341_abstract_function_input_monomorphization" {
    const test_path = "tests/341_abstract_function_input_monomorphization";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 7);
}

test "342_abstract_dispatch_prefers_concrete" {
    const test_path = "tests/342_abstract_dispatch_prefers_concrete";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 2);
}

test "343_abstract_monomorphization_isolation" {
    const test_path = "tests/343_abstract_monomorphization_isolation";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 3);
}

test "336X_abstract_function_input_requires_implementation" {
    try buildExpectFail(
        "tests/336X_abstract_function_input_requires_implementation",
        "type 'Int32' does not implement abstract 'ExampleAbstract' required by parameter '.value' of 'use_value'",
    );
}

test "338X_abstract_function_output_requires_default" {
    try buildExpectFail(
        "tests/338X_abstract_function_output_requires_default",
        "error generating function make_value: InvalidType",
    );
}

test "351_init" {
    const test_path = "tests/351_init";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "352_defer" {
    const test_path = "tests/352_defer";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "353_deinit" {
    const test_path = "tests/353_deinit";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "354_noncopyable_temporary_values" {
    const test_path = "tests/354_noncopyable_temporary_values";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "355X_noncopyable_assignment" {
    try buildExpectFail(
        "tests/355X_noncopyable_assignment",
        "type 'Resource' is not copyable, so it cannot be used by value here",
    );
}

test "356X_noncopyable_argument_by_value" {
    try buildExpectFail(
        "tests/356X_noncopyable_argument_by_value",
        "type 'Resource' is not copyable, so it cannot be used by value here",
    );
}

test "357X_noncopyable_struct_field" {
    try buildExpectFail(
        "tests/357X_noncopyable_struct_field",
        "type 'Resource' is not copyable, so it cannot be used by value here",
    );
}

test "358X_noncopyable_output_binding" {
    try buildExpectFail(
        "tests/358X_noncopyable_output_binding",
        "type 'Resource' is not copyable, so it cannot be used by value here",
    );
}

test "359X_mutable_and_read_alias_same_call" {
    try buildExpectFail(
        "tests/359X_mutable_and_read_alias_same_call",
        "binding 'value' cannot be passed as '$&' and '&' in the same call to 'mix'",
    );
}

test "360X_mutable_and_value_alias_same_call" {
    try buildExpectFail(
        "tests/360X_mutable_and_value_alias_same_call",
        "binding 'value' cannot be passed as '$&' and 'value' in the same call to 'mix'",
    );
}

test "361X_double_mutable_alias_same_call" {
    try buildExpectFail(
        "tests/361X_double_mutable_alias_same_call",
        "binding 'value' cannot be passed as '$&' and '$&' in the same call to 'mix'",
    );
}

test "362_copy_function_value_positions" {
    const test_path = "tests/362_copy_function_value_positions";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "363_move_operator" {
    const test_path = "tests/363_move_operator";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "364X_use_after_move" {
    try buildExpectFail(
        "tests/364X_use_after_move",
        "binding 'handle' was moved and cannot be used again before reinitialization",
    );
}

test "365_move_then_reinitialize" {
    const test_path = "tests/365_move_then_reinitialize";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "36_get_and_set_index_operators" {
    const test_path = "tests/36_get_and_set_index_operators";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "37_size_of_and_alignment_of_builtin_functions" {
    const test_path = "tests/37_size_of_and_alignment_of_builtin_functions";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "42_choice" {
    const test_path = "tests/42_choice";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "43_choice_payloads" {
    const test_path = "tests/43_choice_payloads";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "44X_choice_missing_payload" {
    try buildExpectFail(
        "tests/44X_choice_missing_payload",
        "choice variant '..ok' requires a payload",
    );
}

test "45_choice_is_builtin" {
    const test_path = "tests/45_choice_is_builtin";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "46_choice_match" {
    const test_path = "tests/46_choice_match";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "47_choice_match_payload_binding" {
    const test_path = "tests/47_choice_match_payload_binding";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "48_nullable_generic" {
    const test_path = "tests/48_nullable_generic";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "49_errable_generic" {
    const test_path = "tests/49_errable_generic";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "50X_choice_unknown_variant" {
    try buildExpectFail(
        "tests/50X_choice_unknown_variant",
        "choice type 'Direction' has no variant '..east'",
    );
}

test "51X_choice_payload_access_without_payload" {
    try buildExpectFail(
        "tests/51X_choice_payload_access_without_payload",
        "choice variant '..north' has no payload",
    );
}

test "52X_match_non_choice" {
    try buildExpectFail(
        "tests/52X_match_non_choice",
        "match expects a choice value, found 'Int32'",
    );
}

test "54X_match_bind_payload_without_payload" {
    try buildExpectFail(
        "tests/54X_match_bind_payload_without_payload",
        "choice variant '..north' has no payload to bind",
    );
}

test "411_list_literal_length" {
    const test_path = "tests/411_list_literal_length";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "412_list_literal_access" {
    const test_path = "tests/412_list_literal_access";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "413_arrays" {
    const test_path = "tests/413_arrays";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "414_list_view" {
    const test_path = "tests/414_list_view";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "417_array_index_uint_native" {
    const test_path = "tests/417_array_index_uint_native";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "418_dynamic_array" {
    const test_path = "tests/418_dynamic_array";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "419_dynamic_array_ergonomic" {
    const test_path = "tests/419_dynamic_array_ergonomic";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 80);
}

test "420_string_bytes" {
    const test_path = "tests/420_string_bytes";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "421_string_copy" {
    const test_path = "tests/421_string_copy";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "422_array_explicit_type" {
    const test_path = "tests/422_array_explicit_type";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "423_array_iterator_manual" {
    const test_path = "tests/423_array_iterator_manual";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "424_iterator_abstract" {
    const test_path = "tests/424_iterator_abstract";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "425X_iterator_abstract_missing_implements" {
    try buildExpectFail(
        "tests/425X_iterator_abstract_missing_implements",
        "does not implement abstract 'Iterator'",
    );
}

test "426X_for_requires_iterator_contract" {
    try buildExpectFail(
        "tests/426X_for_requires_iterator_contract",
        "for expects 'to_iterator(.value = &...)' to return a type implementing abstract 'Iterator'",
    );
}

test "427_iterable_abstract" {
    const test_path = "tests/427_iterable_abstract";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "428X_iterable_abstract_missing_implements" {
    try buildExpectFail(
        "tests/428X_iterable_abstract_missing_implements",
        "does not implement abstract 'Iterable'",
    );
}

test "429_range_for" {
    const test_path = "tests/429_range_for";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "430_range_step" {
    const test_path = "tests/430_range_step";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "431_negative_integer_literals" {
    const test_path = "tests/431_negative_integer_literals";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "432_range_int64" {
    const test_path = "tests/432_range_int64";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "433_range_default_start" {
    const test_path = "tests/433_range_default_start";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "434_generic_type_initializer_from_init" {
    const test_path = "tests/434_generic_type_initializer_from_init";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "435_dynamic_array_iterator_manual" {
    const test_path = "tests/435_dynamic_array_iterator_manual";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "436_range_default_start_with_step" {
    const test_path = "tests/436_range_default_start_with_step";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "437X_for_nullable_not_iterable" {
    try buildExpectFail(
        "tests/437X_for_nullable_not_iterable",
        "for expects a type implementing abstract 'Iterable', got 'Nullable#(.t: Int32)'",
    );
}

test "438X_errable_match_unknown_variant" {
    try buildExpectFail(
        "tests/438X_errable_match_unknown_variant",
        "choice type 'Errable#(.t: Int32, .e: Char)' has no variant '..none'",
    );
}

test "439_reached_arguments" {
    const test_path = "tests/439_reached_arguments";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 9);
}

test "440X_reached_argument_missing" {
    try buildExpectFail(
        "tests/440X_reached_argument_missing",
        "cannot resolve reached argument '.stdout'",
    );
}

test "441_output_stream_capability" {
    const test_path = "tests/441_output_stream_capability";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 1);
}

test "442_reached_output_stream" {
    const test_path = "tests/442_reached_output_stream";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 15);
}

test "443_terminal_stderr_helper" {
    const test_path = "tests/443_terminal_stderr_helper";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 11);
}

test "444_input_stream_capability" {
    const test_path = "tests/444_input_stream_capability";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "447_reached_allocator_string" {
    const test_path = "tests/447_reached_allocator_string";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 11);
}

test "448_reached_allocator_dynamic_array" {
    const test_path = "tests/448_reached_allocator_dynamic_array";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 22);
}

test "449_main_system_input" {
    const test_path = "tests/449_main_system_input";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "450_default_type_initializer_argument" {
    const test_path = "tests/450_default_type_initializer_argument";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 7);
}

test "451_keep_cancels_auto_deinit" {
    const test_path = "tests/451_keep_cancels_auto_deinit";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "452X_keep_without_auto_deinit" {
    try buildExpectFail(
        "tests/452X_keep_without_auto_deinit",
        "cannot keep binding 'value': no automatic deinit is scheduled",
    );
}

test "453_main_system_reached_allocator" {
    const test_path = "tests/453_main_system_reached_allocator";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "454_main_system_reached_stdout" {
    const test_path = "tests/454_main_system_reached_stdout";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "455_empty_type_initializer_resolution" {
    const test_path = "tests/455_empty_type_initializer_resolution";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "456_addressable_struct_subfields" {
    const test_path = "tests/456_addressable_struct_subfields";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "457_main_arguments_count" {
    const test_path = "tests/457_main_arguments_count";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "458_buffered_file_wrappers" {
    const test_path = "tests/458_buffered_file_wrappers";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "459_file_preopened_stdio" {
    const test_path = "tests/459_file_preopened_stdio";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "460_file_open_close" {
    const test_path = "tests/460_file_open_close";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "461_text_buffer_io" {
    const test_path = "tests/461_text_buffer_io";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "462_while_if_break_codegen" {
    const test_path = "tests/462_while_if_break_codegen";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "463_if_break_only_codegen" {
    const test_path = "tests/463_if_break_only_codegen";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "464_text_buffer_helpers" {
    const test_path = "tests/464_text_buffer_helpers";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "465_string_views" {
    const test_path = "tests/465_string_views";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "466_empty_string_cstring" {
    const test_path = "tests/466_empty_string_cstring";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "467_string_view_length" {
    const test_path = "tests/467_string_view_length";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "468_string_allocator_size" {
    const test_path = "tests/468_string_allocator_size";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "469_cstring_literal" {
    const test_path = "tests/469_cstring_literal";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "470_file_open_modes" {
    const test_path = "tests/470_file_open_modes";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "62_folder_module_namespace" {
    const test_path = "tests/62_folder_module_namespace";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 1);
}

test "63_import_current_relative" {
    const test_path = "tests/63_import_current_relative";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "64X_import_missing_module" {
    try buildExpectFail(
        "tests/64X_import_missing_module",
        "cannot resolve import './missing_dep'",
    );
}

test "65X_import_missing_value" {
    try buildExpectFail(
        "tests/65X_import_missing_value",
        "module has no value '.missing_value'",
    );
}

test "66X_import_missing_overload" {
    try buildExpectFail(
        "tests/66X_import_missing_overload",
        "module 'dep' has no function named 'missing_func'",
    );
}

test "67X_private_module_value" {
    try buildExpectFail(
        "tests/67X_private_module_value",
        "value '_hidden_value' is private to its module",
    );
}

test "68X_private_module_type" {
    try buildExpectFail(
        "tests/68X_private_module_type",
        "type '_HiddenStatus' is private to its module",
    );
}

test "69X_private_module_function" {
    try buildExpectFail(
        "tests/69X_private_module_function",
        "function '_hidden_status' is private to its module",
    );
}

test "70_import_more_library" {
    const test_path = "tests/70_import_more_library";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "71_import_transitive" {
    const test_path = "tests/71_import_transitive";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "71_loops" {
    const test_path = "tests/71_loops";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "72X_import_cycle" {
    try buildExpectFail(
        "tests/72X_import_cycle",
        "import cycle detected",
    );
}

test "73X_import_requires_binding" {
    try buildExpectFail(
        "tests/73X_import_requires_binding",
        "#import must be assigned to a name",
    );
}

test "74X_import_requires_binding_nested" {
    try buildExpectFail(
        "tests/74X_import_requires_binding_nested",
        "#import must be assigned to a name",
    );
}

test "75X_missing_function_name" {
    try buildExpectFail(
        "tests/75X_missing_function_name",
        "no function named 'missing_func' exists",
    );
}

test "76_import_root_relative" {
    const test_path = "tests/76_import_root_relative/project/app";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "77X_root_relative_missing_import" {
    try buildExpectFail(
        "tests/77X_root_relative_missing_import/project/app",
        "cannot resolve import '.../missing_shared'",
    );
}

test "78_for_array" {
    const test_path = "tests/78_for_array";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "79_for_dynamic_array" {
    const test_path = "tests/79_for_dynamic_array";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}
