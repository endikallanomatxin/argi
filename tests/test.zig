const std = @import("std");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

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

fn runExpectStdoutWithArgs(
    name: []const u8,
    args: []const []const u8,
    expected_code: u8,
    expected_stdout: []const u8,
) !void {
    const output_path = try outputPathFor(name);
    defer std.testing.allocator.free(output_path);

    const argv = try std.testing.allocator.alloc([]const u8, args.len + 1);
    defer std.testing.allocator.free(argv);

    argv[0] = output_path;
    for (args, 0..) |arg, i| {
        argv[i + 1] = arg;
    }

    const result = try runChild(argv);
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);

    try expectEqual(std.process.Child.Term{ .Exited = expected_code }, result.term);
    try expectEqualStrings(expected_stdout, result.stdout);
}

fn runExpectStdout(name: []const u8, expected_code: u8, expected_stdout: []const u8) !void {
    try runExpectStdoutWithArgs(name, &[_][]const u8{}, expected_code, expected_stdout);
}

fn pathInTest(name: []const u8, leaf: []const u8) ![]u8 {
    return std.fmt.allocPrint(std.testing.allocator, "{s}/{s}", .{ name, leaf });
}

test "feature_tests/basics/01_minimal_main" {
    const test_path = "tests/feature_tests/basics/01_minimal_main";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "usecase_tests/01_cat_cli" {
    const test_path = "tests/usecase_tests/01_cat_cli";
    const input_1 = try pathInTest(test_path, "input.txt");
    defer std.testing.allocator.free(input_1);
    const input_2 = try pathInTest(test_path, "input_2.txt");
    defer std.testing.allocator.free(input_2);
    try expectSuccessfulBuild(test_path);
    try runExpectStdoutWithArgs(
        test_path,
        &[_][]const u8{ input_1, input_2 },
        0,
        "Hello from Argi.\nThis is a tiny cat clone.\nAnd now a second file.\nCat should concatenate both.\n",
    );
}

test "usecase_tests/01_cat_cli_help_short" {
    const test_path = "tests/usecase_tests/01_cat_cli";
    try expectSuccessfulBuild(test_path);
    try runExpectStdoutWithArgs(
        test_path,
        &[_][]const u8{"-h"},
        0,
        "usage: <program> <file> [file...]\nConcatenate files to standard output.\n  -h, --help  Show this help.\n",
    );
}

test "usecase_tests/01_cat_cli_help_long" {
    const test_path = "tests/usecase_tests/01_cat_cli";
    try expectSuccessfulBuild(test_path);
    try runExpectStdoutWithArgs(
        test_path,
        &[_][]const u8{"--help"},
        0,
        "usage: <program> <file> [file...]\nConcatenate files to standard output.\n  -h, --help  Show this help.\n",
    );
}

test "feature_tests/basics/02_comments" {
    const test_path = "tests/feature_tests/basics/02_comments";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/basics/03_constants_and_variables" {
    const test_path = "tests/feature_tests/basics/03_constants_and_variables";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/basics/04_expressions_and_type_inference" {
    const test_path = "tests/feature_tests/basics/04_expressions_and_type_inference";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 3);
}

test "feature_tests/basics/05_literals" {
    const test_path = "tests/feature_tests/basics/05_literals";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/control_flow/01_if" {
    const test_path = "tests/feature_tests/control_flow/01_if";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/basics/06_anonymous_structs" {
    const test_path = "tests/feature_tests/basics/06_anonymous_structs";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/basics/07_struct_default_fields" {
    const test_path = "tests/feature_tests/basics/07_struct_default_fields";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/basics/08_struct_field_store" {
    const test_path = "tests/feature_tests/basics/08_struct_field_store";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/basics/09X_integer_literal_overflow" {
    try buildExpectFail(
        "tests/feature_tests/basics/09X_integer_literal_overflow",
        "integer literal 300 does not fit in 'UInt8' (max 255)",
    );
}

test "feature_tests/basics/10X_signed_integer_literal_overflow" {
    try buildExpectFail(
        "tests/feature_tests/basics/10X_signed_integer_literal_overflow",
        "integer literal 128 does not fit in 'Int8' (min -128, max 127)",
    );
}

test "feature_tests/basics/11X_negative_integer_literal_overflow" {
    try buildExpectFail(
        "tests/feature_tests/basics/11X_negative_integer_literal_overflow",
        "integer literal -129 does not fit in 'Int8' (min -128, max 127)",
    );
}

test "feature_tests/functions/01_function_calling" {
    const test_path = "tests/feature_tests/functions/01_function_calling";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 42);
}

test "feature_tests/functions/02_function_args" {
    const test_path = "tests/feature_tests/functions/02_function_args";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 42);
}

test "feature_tests/functions/03_pipe_operator" {
    const test_path = "tests/feature_tests/functions/03_pipe_operator";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 42);
}

test "feature_tests/functions/04_pipe_pointer" {
    const test_path = "tests/feature_tests/functions/04_pipe_pointer";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 42);
}

test "feature_tests/functions/05X_pipe_requires_parentheses" {
    try buildExpectFail(
        "tests/feature_tests/functions/05X_pipe_requires_parentheses",
        "pipe right-hand side must use at least one argument placeholder",
    );
}

test "feature_tests/functions/06X_pipe_requires_placeholder" {
    try buildExpectFail(
        "tests/feature_tests/functions/06X_pipe_requires_placeholder",
        "pipe right-hand side must use at least one argument placeholder",
    );
}

test "feature_tests/functions/07X_pipe_expression_placeholder_not_supported" {
    try buildExpectFail(
        "tests/feature_tests/functions/07X_pipe_expression_placeholder_not_supported",
        "pipe placeholders are only supported as '_', '&_', '$&_', '_.field', or '..variant' payload access for now",
    );
}

test "feature_tests/functions/08_pipe_chain" {
    const test_path = "tests/feature_tests/functions/08_pipe_chain";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 42);
}

test "feature_tests/functions/09_pipe_generic_inferred" {
    const test_path = "tests/feature_tests/functions/09_pipe_generic_inferred";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 42);
}

test "feature_tests/functions/10_pipe_generic_explicit" {
    const test_path = "tests/feature_tests/functions/10_pipe_generic_explicit";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 42);
}

test "feature_tests/functions/11_pipe_builtin_is" {
    const test_path = "tests/feature_tests/functions/11_pipe_builtin_is";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/functions/12_positional_function_call" {
    const test_path = "tests/feature_tests/functions/12_positional_function_call";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 42);
}

test "feature_tests/functions/13_mixed_function_call" {
    const test_path = "tests/feature_tests/functions/13_mixed_function_call";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 42);
}

test "feature_tests/functions/14X_positional_after_named_call" {
    try buildExpectFail(
        "tests/feature_tests/functions/14X_positional_after_named_call",
        "positional collection items must appear before named items",
    );
}

test "feature_tests/functions/15_output_default_implicit_return" {
    const test_path = "tests/feature_tests/functions/15_output_default_implicit_return";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 42);
}

test "feature_tests/polymorphism/01_multiple_dispatch" {
    const test_path = "tests/feature_tests/polymorphism/01_multiple_dispatch";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 2);
}

test "feature_tests/polymorphism/02X_multiple_dispatch_ambiguous" {
    try buildExpectFail(
        "tests/feature_tests/polymorphism/02X_multiple_dispatch_ambiguous",
        "ambiguous call to 'choose2'",
    );
}

test "feature_tests/basics/12_named_struct_types" {
    const test_path = "tests/feature_tests/basics/12_named_struct_types";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/pointers/01_pointers" {
    const test_path = "tests/feature_tests/pointers/01_pointers";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/pointers/02_read-only_vs_read-and-write_pointers" {
    const test_path = "tests/feature_tests/pointers/02_read-only_vs_read-and-write_pointers";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/pointers/03X_assign_through_readonly_pointer" {
    try buildExpectFail(
        "tests/feature_tests/pointers/03X_assign_through_readonly_pointer",
        "cannot assign through pointer '&Int32' because it is read-only",
    );
}

test "feature_tests/pointers/04X_read-write_pointer_to_constant" {
    try buildExpectFail(
        "tests/feature_tests/pointers/04X_read-write_pointer_to_constant",
        "binding 'value' is immutable",
    );
}

test "feature_tests/pointers/05X_pass_readonly_pointer_to_mutable_param" {
    try buildExpectFail(
        "tests/feature_tests/pointers/05X_pass_readonly_pointer_to_mutable_param",
        "no overload of 'increment' accepts arguments (.ptr: &Int32)",
    );
}

test "feature_tests/pointers/06_explicit_pointer_casts" {
    const test_path = "tests/feature_tests/pointers/06_explicit_pointer_casts";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/pointers/07X_pointer_arithmetic_requires_cast" {
    try buildExpectFail(
        "tests/feature_tests/pointers/07X_pointer_arithmetic_requires_cast",
        "pointer arithmetic is not allowed; cast explicitly to an integer, perform the arithmetic, and cast back",
    );
}

test "feature_tests/pointers/08X_array_index_requires_uint_native" {
    try buildExpectFail(
        "tests/feature_tests/pointers/08X_array_index_requires_uint_native",
        "array index must be 'UIntNative'",
    );
}

test "feature_tests/basics/13_core_and_libc" {
    const test_path = "tests/feature_tests/basics/13_core_and_libc";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/polymorphism/03_generic_functions" {
    const test_path = "tests/feature_tests/polymorphism/03_generic_functions";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 42);
}

test "feature_tests/polymorphism/04_generic_structs" {
    const test_path = "tests/feature_tests/polymorphism/04_generic_structs";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 42);
}

test "feature_tests/polymorphism/05_generic_functions_multi" {
    const test_path = "tests/feature_tests/polymorphism/05_generic_functions_multi";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 42);
}

test "feature_tests/polymorphism/06_generic_structs_multi" {
    const test_path = "tests/feature_tests/polymorphism/06_generic_structs_multi";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 20);
}

test "feature_tests/polymorphism/07_generic_statement_type_arguments" {
    const test_path = "tests/feature_tests/polymorphism/07_generic_statement_type_arguments";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/polymorphism/08_abstract" {
    const test_path = "tests/feature_tests/polymorphism/08_abstract";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/polymorphism/09X_abstract_missing_requirement" {
    try buildExpectFail(
        "tests/feature_tests/polymorphism/09X_abstract_missing_requirement",
        "type does not implement abstract 'Animal':\n  missing function: speak (.who: Dog)",
    );
}

test "feature_tests/polymorphism/10X_abstract_wrong_signature" {
    try buildExpectFail(
        "tests/feature_tests/polymorphism/10X_abstract_wrong_signature",
        "type does not implement abstract 'Animal':\n  missing function: speak (.who: Dog)",
    );
}

test "feature_tests/polymorphism/11_abstract_instantiation" {
    const test_path = "tests/feature_tests/polymorphism/11_abstract_instantiation";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/polymorphism/12X_abstract_instantiation_missing_default" {
    try buildExpectFail(
        "tests/feature_tests/polymorphism/12X_abstract_instantiation_missing_default",
        "cannot use abstract 'ExampleAbstract' as a type for a symbol",
    );
}

test "feature_tests/polymorphism/15_abstract_self_output" {
    const test_path = "tests/feature_tests/polymorphism/15_abstract_self_output";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/polymorphism/16X_abstract_self_output_wrong" {
    try buildExpectFail(
        "tests/feature_tests/polymorphism/16X_abstract_self_output_wrong",
        "type does not implement abstract 'Animal':\n  missing function: clone (.who: Dog)",
    );
}

test "feature_tests/polymorphism/17_abstract_function_input_monomorphization" {
    const test_path = "tests/feature_tests/polymorphism/17_abstract_function_input_monomorphization";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 7);
}

test "feature_tests/polymorphism/18_abstract_dispatch_prefers_concrete" {
    const test_path = "tests/feature_tests/polymorphism/18_abstract_dispatch_prefers_concrete";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 2);
}

test "feature_tests/polymorphism/19_abstract_monomorphization_isolation" {
    const test_path = "tests/feature_tests/polymorphism/19_abstract_monomorphization_isolation";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 3);
}

test "feature_tests/polymorphism/13X_abstract_function_input_requires_implementation" {
    try buildExpectFail(
        "tests/feature_tests/polymorphism/13X_abstract_function_input_requires_implementation",
        "type 'Int32' does not implement abstract 'ExampleAbstract' required by parameter '.value' of 'use_value'",
    );
}

test "feature_tests/polymorphism/14X_abstract_function_output_requires_default" {
    try buildExpectFail(
        "tests/feature_tests/polymorphism/14X_abstract_function_output_requires_default",
        "error generating function make_value: InvalidType",
    );
}

test "feature_tests/ownership/01_init" {
    const test_path = "tests/feature_tests/ownership/01_init";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/ownership/02_defer" {
    const test_path = "tests/feature_tests/ownership/02_defer";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/ownership/03_deinit" {
    const test_path = "tests/feature_tests/ownership/03_deinit";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/ownership/04_noncopyable_temporary_values" {
    const test_path = "tests/feature_tests/ownership/04_noncopyable_temporary_values";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/ownership/05X_noncopyable_assignment" {
    try buildExpectFail(
        "tests/feature_tests/ownership/05X_noncopyable_assignment",
        "type 'Resource' is not copyable, so it cannot be used by value here",
    );
}

test "feature_tests/ownership/06X_noncopyable_argument_by_value" {
    try buildExpectFail(
        "tests/feature_tests/ownership/06X_noncopyable_argument_by_value",
        "type 'Resource' is not copyable, so it cannot be used by value here",
    );
}

test "feature_tests/ownership/07X_noncopyable_struct_field" {
    try buildExpectFail(
        "tests/feature_tests/ownership/07X_noncopyable_struct_field",
        "type 'Resource' is not copyable, so it cannot be used by value here",
    );
}

test "feature_tests/ownership/08X_noncopyable_output_binding" {
    try buildExpectFail(
        "tests/feature_tests/ownership/08X_noncopyable_output_binding",
        "type 'Resource' is not copyable, so it cannot be used by value here",
    );
}

test "feature_tests/ownership/09X_mutable_and_read_alias_same_call" {
    try buildExpectFail(
        "tests/feature_tests/ownership/09X_mutable_and_read_alias_same_call",
        "binding 'value' cannot be passed as '$&' and '&' in the same call to 'mix'",
    );
}

test "feature_tests/ownership/10X_mutable_and_value_alias_same_call" {
    try buildExpectFail(
        "tests/feature_tests/ownership/10X_mutable_and_value_alias_same_call",
        "binding 'value' cannot be passed as '$&' and 'value' in the same call to 'mix'",
    );
}

test "feature_tests/ownership/11X_double_mutable_alias_same_call" {
    try buildExpectFail(
        "tests/feature_tests/ownership/11X_double_mutable_alias_same_call",
        "binding 'value' cannot be passed as '$&' and '$&' in the same call to 'mix'",
    );
}

test "feature_tests/ownership/12_copy_function_value_positions" {
    const test_path = "tests/feature_tests/ownership/12_copy_function_value_positions";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/ownership/13_move_operator" {
    const test_path = "tests/feature_tests/ownership/13_move_operator";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/ownership/14X_use_after_move" {
    try buildExpectFail(
        "tests/feature_tests/ownership/14X_use_after_move",
        "binding 'handle' was moved and cannot be used again before reinitialization",
    );
}

test "feature_tests/ownership/15_move_then_reinitialize" {
    const test_path = "tests/feature_tests/ownership/15_move_then_reinitialize";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/basics/14_get_and_set_index_operators" {
    const test_path = "tests/feature_tests/basics/14_get_and_set_index_operators";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/basics/15_size_of_and_alignment_of_builtin_functions" {
    const test_path = "tests/feature_tests/basics/15_size_of_and_alignment_of_builtin_functions";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/basics/16_bool_literals" {
    const test_path = "tests/feature_tests/basics/16_bool_literals";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/types/01_choice" {
    const test_path = "tests/feature_tests/types/01_choice";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/types/03_choice_payloads" {
    const test_path = "tests/feature_tests/types/03_choice_payloads";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/types/04X_choice_missing_payload" {
    try buildExpectFail(
        "tests/feature_tests/types/04X_choice_missing_payload",
        "choice variant '..ok' requires a payload",
    );
}

test "feature_tests/types/05_choice_is_builtin" {
    const test_path = "tests/feature_tests/types/05_choice_is_builtin";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/types/06_choice_match" {
    const test_path = "tests/feature_tests/types/06_choice_match";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/types/07_choice_match_payload_binding" {
    const test_path = "tests/feature_tests/types/07_choice_match_payload_binding";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/types/08_nullable_generic" {
    const test_path = "tests/feature_tests/types/08_nullable_generic";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/types/09_errable_generic" {
    const test_path = "tests/feature_tests/types/09_errable_generic";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/types/10X_choice_unknown_variant" {
    try buildExpectFail(
        "tests/feature_tests/types/10X_choice_unknown_variant",
        "choice type 'Direction' has no variant '..east'",
    );
}

test "feature_tests/types/11X_choice_payload_access_without_payload" {
    try buildExpectFail(
        "tests/feature_tests/types/11X_choice_payload_access_without_payload",
        "choice variant '..north' has no payload",
    );
}

test "feature_tests/types/12X_match_non_choice" {
    try buildExpectFail(
        "tests/feature_tests/types/12X_match_non_choice",
        "match expects a choice value, found 'Int32'",
    );
}

test "feature_tests/types/13X_match_bind_payload_without_payload" {
    try buildExpectFail(
        "tests/feature_tests/types/13X_match_bind_payload_without_payload",
        "choice variant '..north' has no payload to bind",
    );
}

test "feature_tests/collections/01_list_literal_length" {
    const test_path = "tests/feature_tests/collections/01_list_literal_length";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/collections/02_list_literal_access" {
    const test_path = "tests/feature_tests/collections/02_list_literal_access";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/collections/03_arrays" {
    const test_path = "tests/feature_tests/collections/03_arrays";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/collections/04_list_view" {
    const test_path = "tests/feature_tests/collections/04_list_view";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/collections/07_array_index_uint_native" {
    const test_path = "tests/feature_tests/collections/07_array_index_uint_native";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/collections/08_dynamic_array" {
    const test_path = "tests/feature_tests/collections/08_dynamic_array";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/collections/09_dynamic_array_ergonomic" {
    const test_path = "tests/feature_tests/collections/09_dynamic_array_ergonomic";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 80);
}

test "feature_tests/text/01_string_bytes" {
    const test_path = "tests/feature_tests/text/01_string_bytes";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/text/02_string_copy" {
    const test_path = "tests/feature_tests/text/02_string_copy";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/collections/10_array_explicit_type" {
    const test_path = "tests/feature_tests/collections/10_array_explicit_type";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/collections/11_array_iterator_manual" {
    const test_path = "tests/feature_tests/collections/11_array_iterator_manual";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/collections/12_iterator_abstract" {
    const test_path = "tests/feature_tests/collections/12_iterator_abstract";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/collections/13X_iterator_abstract_missing_implements" {
    try buildExpectFail(
        "tests/feature_tests/collections/13X_iterator_abstract_missing_implements",
        "does not implement abstract 'Iterator'",
    );
}

test "feature_tests/control_flow/05X_for_requires_iterator_contract" {
    try buildExpectFail(
        "tests/feature_tests/control_flow/05X_for_requires_iterator_contract",
        "for expects 'to_iterator(.value = &...)' to return a type implementing abstract 'Iterator'",
    );
}

test "feature_tests/collections/14_iterable_abstract" {
    const test_path = "tests/feature_tests/collections/14_iterable_abstract";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/collections/15X_iterable_abstract_missing_implements" {
    try buildExpectFail(
        "tests/feature_tests/collections/15X_iterable_abstract_missing_implements",
        "does not implement abstract 'Iterable'",
    );
}

test "feature_tests/control_flow/06_range_for" {
    const test_path = "tests/feature_tests/control_flow/06_range_for";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/control_flow/07_range_step" {
    const test_path = "tests/feature_tests/control_flow/07_range_step";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/control_flow/08_negative_integer_literals" {
    const test_path = "tests/feature_tests/control_flow/08_negative_integer_literals";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/control_flow/09_range_int64" {
    const test_path = "tests/feature_tests/control_flow/09_range_int64";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/control_flow/10_range_default_start" {
    const test_path = "tests/feature_tests/control_flow/10_range_default_start";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/types/17_generic_type_initializer_from_init" {
    const test_path = "tests/feature_tests/types/17_generic_type_initializer_from_init";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/types/18_positional_type_initializer" {
    const test_path = "tests/feature_tests/types/18_positional_type_initializer";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 42);
}

test "feature_tests/types/19_mixed_type_initializer" {
    const test_path = "tests/feature_tests/types/19_mixed_type_initializer";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 42);
}

test "feature_tests/collections/16_dynamic_array_iterator_manual" {
    const test_path = "tests/feature_tests/collections/16_dynamic_array_iterator_manual";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/control_flow/11_range_default_start_with_step" {
    const test_path = "tests/feature_tests/control_flow/11_range_default_start_with_step";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/control_flow/12X_for_nullable_not_iterable" {
    try buildExpectFail(
        "tests/feature_tests/control_flow/12X_for_nullable_not_iterable",
        "for expects a type implementing abstract 'Iterable', got 'Nullable#(.t: Int32)'",
    );
}

test "feature_tests/types/14X_errable_match_unknown_variant" {
    try buildExpectFail(
        "tests/feature_tests/types/14X_errable_match_unknown_variant",
        "choice type 'Errable#(.t: Int32, .e: Char)' has no variant '..none'",
    );
}

test "feature_tests/system/02_reached_arguments" {
    const test_path = "tests/feature_tests/system/02_reached_arguments";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 9);
}

test "feature_tests/system/03X_reached_argument_missing" {
    try buildExpectFail(
        "tests/feature_tests/system/03X_reached_argument_missing",
        "cannot resolve reached argument '.stdout'",
    );
}

test "feature_tests/io/01_output_stream_capability" {
    const test_path = "tests/feature_tests/io/01_output_stream_capability";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 1);
}

test "feature_tests/io/02_reached_output_stream" {
    const test_path = "tests/feature_tests/io/02_reached_output_stream";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 15);
}

test "feature_tests/io/03_terminal_stderr_helper" {
    const test_path = "tests/feature_tests/io/03_terminal_stderr_helper";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 11);
}

test "feature_tests/io/04_input_stream_capability" {
    const test_path = "tests/feature_tests/io/04_input_stream_capability";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/system/04_reached_allocator_string" {
    const test_path = "tests/feature_tests/system/04_reached_allocator_string";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 11);
}

test "feature_tests/system/05_reached_allocator_dynamic_array" {
    const test_path = "tests/feature_tests/system/05_reached_allocator_dynamic_array";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 24);
}

test "feature_tests/types/15_default_type_initializer_argument" {
    const test_path = "tests/feature_tests/types/15_default_type_initializer_argument";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 7);
}

test "feature_tests/ownership/16_keep_cancels_auto_deinit" {
    const test_path = "tests/feature_tests/ownership/16_keep_cancels_auto_deinit";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/17X_keep_without_auto_deinit" {
    try buildExpectFail(
        "tests/feature_tests/ownership/17X_keep_without_auto_deinit",
        "cannot keep binding 'value': no automatic deinit is scheduled",
    );
}

test "feature_tests/types/16_empty_type_initializer_resolution" {
    const test_path = "tests/feature_tests/types/16_empty_type_initializer_resolution";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/pointers/09_addressable_struct_subfields" {
    const test_path = "tests/feature_tests/pointers/09_addressable_struct_subfields";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/system/06_main_arguments_count" {
    const test_path = "tests/feature_tests/system/06_main_arguments_count";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/io/05_buffered_file_wrappers" {
    const test_path = "tests/feature_tests/io/05_buffered_file_wrappers";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/io/06_file_preopened_stdio" {
    const test_path = "tests/feature_tests/io/06_file_preopened_stdio";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/io/07_file_open_close" {
    const test_path = "tests/feature_tests/io/07_file_open_close";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/text/03_text_buffer_io" {
    const test_path = "tests/feature_tests/text/03_text_buffer_io";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/control_flow/13_while_if_break_codegen" {
    const test_path = "tests/feature_tests/control_flow/13_while_if_break_codegen";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/control_flow/14_if_break_only_codegen" {
    const test_path = "tests/feature_tests/control_flow/14_if_break_only_codegen";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/control_flow/15_logical_and_or" {
    const test_path = "tests/feature_tests/control_flow/15_logical_and_or";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/text/04_text_buffer_helpers" {
    const test_path = "tests/feature_tests/text/04_text_buffer_helpers";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/text/05_string_views" {
    const test_path = "tests/feature_tests/text/05_string_views";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/text/06_empty_string_cstring" {
    const test_path = "tests/feature_tests/text/06_empty_string_cstring";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/text/07_string_view_length" {
    const test_path = "tests/feature_tests/text/07_string_view_length";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/text/08_string_allocator_size" {
    const test_path = "tests/feature_tests/text/08_string_allocator_size";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/text/09_cstring_literal" {
    const test_path = "tests/feature_tests/text/09_cstring_literal";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/io/08_file_open_modes" {
    const test_path = "tests/feature_tests/io/08_file_open_modes";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/io/09_print_c_string_literal" {
    const test_path = "tests/feature_tests/io/09_print_c_string_literal";
    try expectSuccessfulBuild(test_path);
    try runExpectStdout(test_path, 0, "literal output");
}

test "feature_tests/system/07_arguments_access" {
    const test_path = "tests/feature_tests/system/07_arguments_access";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/system/08_arguments_index_operator" {
    const test_path = "tests/feature_tests/system/08_arguments_index_operator";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/system/09_arguments_iterable" {
    const test_path = "tests/feature_tests/system/09_arguments_iterable";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/system/10_length_named_function" {
    const test_path = "tests/feature_tests/system/10_length_named_function";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/system/11_environment_variables" {
    const test_path = "tests/feature_tests/system/11_environment_variables";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/system/12_environment_variables_index_operator" {
    const test_path = "tests/feature_tests/system/12_environment_variables_index_operator";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/system/13_environment_variables_string_keys" {
    const test_path = "tests/feature_tests/system/13_environment_variables_string_keys";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/system/14_file_system_capability" {
    const test_path = "tests/feature_tests/system/14_file_system_capability";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/18X_system_noncopyable_assignment" {
    try buildExpectFail(
        "tests/feature_tests/ownership/18X_system_noncopyable_assignment",
        "type 'System' is not copyable, so it cannot be used by value here",
    );
}

test "feature_tests/ownership/19X_system_noncopyable_argument" {
    try buildExpectFail(
        "tests/feature_tests/ownership/19X_system_noncopyable_argument",
        "type 'System' is not copyable, so it cannot be used by value here",
    );
}

test "feature_tests/system/15_once_single_use" {
    const test_path = "tests/feature_tests/system/15_once_single_use";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/system/16X_once_duplicate_direct" {
    try buildExpectFail(
        "tests/feature_tests/system/16X_once_duplicate_direct",
        "once function 'setup' is consumed more than once from the reachable entrypoint graph",
    );
}

test "feature_tests/system/17_once_unreached_duplicate_allowed" {
    const test_path = "tests/feature_tests/system/17_once_unreached_duplicate_allowed";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/system/18X_once_duplicate_indirect" {
    try buildExpectFail(
        "tests/feature_tests/system/18X_once_duplicate_indirect",
        "once function 'setup' is consumed more than once from the reachable entrypoint graph",
    );
}

test "feature_tests/system/19X_once_duplicate_branches" {
    try buildExpectFail(
        "tests/feature_tests/system/19X_once_duplicate_branches",
        "once function 'setup' is consumed more than once from the reachable entrypoint graph",
    );
}

test "feature_tests/system/20X_once_duplicate_init" {
    try buildExpectFail(
        "tests/feature_tests/system/20X_once_duplicate_init",
        "once function 'init' is consumed more than once from the reachable entrypoint graph",
    );
}

test "feature_tests/system/21X_system_duplicate_init" {
    try buildExpectFail(
        "tests/feature_tests/system/21X_system_duplicate_init",
        "once function 'init' is consumed more than once from the reachable entrypoint graph",
    );
}

test "feature_tests/system/22_file_system_mutations" {
    const test_path = "tests/feature_tests/system/22_file_system_mutations";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/system/23_file_system_read_write" {
    const test_path = "tests/feature_tests/system/23_file_system_read_write";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/system/24_arguments_length_pipe_positional" {
    const test_path = "tests/feature_tests/system/24_arguments_length_pipe_positional";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/polymorphism/20_generic_abstract_bound_syntax" {
    const test_path = "tests/feature_tests/polymorphism/20_generic_abstract_bound_syntax";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 42);
}

test "feature_tests/polymorphism/21X_generic_bound_requires_type_keyword" {
    try buildExpectFail(
        "tests/feature_tests/polymorphism/21X_generic_bound_requires_type_keyword",
        "generic parameter bounds use '.t: Type: Constraint'",
    );
}

test "feature_tests/polymorphism/22_generic_wrapper_abstract_conformance" {
    const test_path = "tests/feature_tests/polymorphism/22_generic_wrapper_abstract_conformance";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/20_anonymous_struct_auto_deinit" {
    const test_path = "tests/feature_tests/ownership/20_anonymous_struct_auto_deinit";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 11);
}

test "feature_tests/ownership/21_keep_string_auto_deinit" {
    const test_path = "tests/feature_tests/ownership/21_keep_string_auto_deinit";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 11);
}

test "feature_tests/ownership/22_while_body_auto_deinit" {
    const test_path = "tests/feature_tests/ownership/22_while_body_auto_deinit";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/polymorphism/23_abstract_requirement_reached_default" {
    const test_path = "tests/feature_tests/polymorphism/23_abstract_requirement_reached_default";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/text/10_string_view_c_string_storage" {
    const test_path = "tests/feature_tests/text/10_string_view_c_string_storage";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/text/11_string_view_equals" {
    const test_path = "tests/feature_tests/text/11_string_view_equals";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/modules/01_folder_module_namespace" {
    const test_path = "tests/feature_tests/modules/01_folder_module_namespace";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 1);
}

test "feature_tests/modules/02_import_current_relative" {
    const test_path = "tests/feature_tests/modules/02_import_current_relative";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/modules/03X_import_missing_module" {
    try buildExpectFail(
        "tests/feature_tests/modules/03X_import_missing_module",
        "cannot resolve import './missing_dep'",
    );
}

test "feature_tests/modules/04X_import_missing_value" {
    try buildExpectFail(
        "tests/feature_tests/modules/04X_import_missing_value",
        "module has no value '.missing_value'",
    );
}

test "feature_tests/modules/05X_import_missing_overload" {
    try buildExpectFail(
        "tests/feature_tests/modules/05X_import_missing_overload",
        "module 'dep' has no function named 'missing_func'",
    );
}

test "feature_tests/modules/06X_private_module_value" {
    try buildExpectFail(
        "tests/feature_tests/modules/06X_private_module_value",
        "value '_hidden_value' is private to its module",
    );
}

test "feature_tests/modules/07X_private_module_type" {
    try buildExpectFail(
        "tests/feature_tests/modules/07X_private_module_type",
        "type '_HiddenStatus' is private to its module",
    );
}

test "feature_tests/modules/08X_private_module_function" {
    try buildExpectFail(
        "tests/feature_tests/modules/08X_private_module_function",
        "function '_hidden_status' is private to its module",
    );
}

test "feature_tests/modules/09_import_more_library" {
    const test_path = "tests/feature_tests/modules/09_import_more_library";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/modules/10_import_transitive" {
    const test_path = "tests/feature_tests/modules/10_import_transitive";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/control_flow/02_loops" {
    const test_path = "tests/feature_tests/control_flow/02_loops";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/modules/11X_import_cycle" {
    try buildExpectFail(
        "tests/feature_tests/modules/11X_import_cycle",
        "import cycle detected",
    );
}

test "feature_tests/modules/12X_import_requires_binding" {
    try buildExpectFail(
        "tests/feature_tests/modules/12X_import_requires_binding",
        "#import must be assigned to a name",
    );
}

test "feature_tests/modules/13X_import_requires_binding_nested" {
    try buildExpectFail(
        "tests/feature_tests/modules/13X_import_requires_binding_nested",
        "#import must be assigned to a name",
    );
}

test "feature_tests/modules/14X_missing_function_name" {
    try buildExpectFail(
        "tests/feature_tests/modules/14X_missing_function_name",
        "no function named 'missing_func' exists",
    );
}

test "feature_tests/modules/15_import_root_relative" {
    const test_path = "tests/feature_tests/modules/15_import_root_relative/project/app";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/modules/16X_root_relative_missing_import" {
    try buildExpectFail(
        "tests/feature_tests/modules/16X_root_relative_missing_import/project/app",
        "cannot resolve import '.../missing_shared'",
    );
}

test "feature_tests/control_flow/03_for_array" {
    const test_path = "tests/feature_tests/control_flow/03_for_array";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/control_flow/04_for_dynamic_array" {
    const test_path = "tests/feature_tests/control_flow/04_for_dynamic_array";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}
