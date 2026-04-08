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

fn runArgiCommand(args: []const []const u8) !std.process.Child.RunResult {
    const argv = try std.testing.allocator.alloc([]const u8, args.len + 1);
    defer std.testing.allocator.free(argv);

    argv[0] = argi_bin;
    for (args, 0..) |arg, idx| {
        argv[idx + 1] = arg;
    }

    return runChild(argv);
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

fn buildExpectFailWithoutNoise(name: []const u8, expected_stderr: []const u8, forbidden_stderr: []const u8) !void {
    const result = try buildResult(name);
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);

    switch (result.term) {
        .Exited => |code| try expect(code != 0),
        else => return error.UnexpectedProcessTermination,
    }

    try expect(std.mem.indexOf(u8, result.stderr, expected_stderr) != null);
    try expect(std.mem.indexOf(u8, result.stderr, forbidden_stderr) == null);
}

fn buildExpectFailExact(name: []const u8, expected_stderr: []const u8) !void {
    const result = try buildResult(name);
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);

    switch (result.term) {
        .Exited => |code| try expect(code != 0),
        else => return error.UnexpectedProcessTermination,
    }

    try expectEqualStrings(expected_stderr, result.stderr);
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

fn argiTestExpectStderr(
    name: []const u8,
    args: []const []const u8,
    expected_code: u8,
    expected_stderr: []const u8,
) !void {
    const argv = try std.testing.allocator.alloc([]const u8, args.len + 2);
    defer std.testing.allocator.free(argv);

    argv[0] = "test";
    argv[1] = name;
    for (args, 0..) |arg, idx| {
        argv[idx + 2] = arg;
    }

    const result = try runArgiCommand(argv);
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);

    try expectEqual(std.process.Child.Term{ .Exited = expected_code }, result.term);
    try expectEqualStrings(expected_stderr, result.stderr);
}

fn argiTestExpectStderrContains(
    name: []const u8,
    args: []const []const u8,
    expected_code: u8,
    expected_stderr_fragment: []const u8,
) !void {
    const argv = try std.testing.allocator.alloc([]const u8, args.len + 2);
    defer std.testing.allocator.free(argv);

    argv[0] = "test";
    argv[1] = name;
    for (args, 0..) |arg, idx| {
        argv[idx + 2] = arg;
    }

    const result = try runArgiCommand(argv);
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);

    try expectEqual(std.process.Child.Term{ .Exited = expected_code }, result.term);
    try expect(std.mem.indexOf(u8, result.stderr, expected_stderr_fragment) != null);
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

fn runExpectStderr(name: []const u8, expected_code: u8, expected_stderr: []const u8) !void {
    const output_path = try outputPathFor(name);
    defer std.testing.allocator.free(output_path);

    const result = try runChild(&[_][]const u8{output_path});
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);

    try expectEqual(std.process.Child.Term{ .Exited = expected_code }, result.term);
    try expectEqualStrings(expected_stderr, result.stderr);
}

fn runExpectStdoutWithArgsAndStdin(
    name: []const u8,
    args: []const []const u8,
    stdin_text: []const u8,
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

    var child = std.process.Child.init(argv, std.testing.allocator);
    child.cwd = compilerRoot();
    child.stdin_behavior = .Pipe;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    var stdout: std.ArrayList(u8) = .empty;
    defer stdout.deinit(std.testing.allocator);
    var stderr: std.ArrayList(u8) = .empty;
    defer stderr.deinit(std.testing.allocator);

    try child.spawn();
    errdefer {
        _ = child.kill() catch {};
    }

    if (child.stdin) |stdin_file| {
        try stdin_file.writeAll(stdin_text);
        stdin_file.close();
        child.stdin = null;
    }

    try child.collectOutput(std.testing.allocator, &stdout, &stderr, 50 * 1024);

    const stdout_owned = try stdout.toOwnedSlice(std.testing.allocator);
    defer std.testing.allocator.free(stdout_owned);
    const stderr_owned = try stderr.toOwnedSlice(std.testing.allocator);
    defer std.testing.allocator.free(stderr_owned);

    try expectEqual(std.process.Child.Term{ .Exited = expected_code }, try child.wait());
    try expectEqualStrings(expected_stdout, stdout_owned);
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

test "usecase_tests/02_echo_until_empty" {
    const test_path = "tests/usecase_tests/02_echo_until_empty";
    try expectSuccessfulBuild(test_path);
    try runExpectStdoutWithArgsAndStdin(
        test_path,
        &[_][]const u8{},
        "hello\nworld\n\nignored\n",
        0,
        "hello\nworld\n",
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
    try buildExpectFailExact(
        "tests/feature_tests/basics/09X_integer_literal_overflow",
        \\tests/feature_tests/basics/09X_integer_literal_overflow/main.rg:2:21: error: integer literal 300 does not fit in 'UInt8' (max 255)
        \\      value : UInt8 = 300
        \\                      ^
        \\
    );
}

test "feature_tests/basics/10X_signed_integer_literal_overflow" {
    try buildExpectFailExact(
        "tests/feature_tests/basics/10X_signed_integer_literal_overflow",
        \\tests/feature_tests/basics/10X_signed_integer_literal_overflow/main.rg:2:20: error: integer literal 128 does not fit in 'Int8' (min -128, max 127)
        \\      value : Int8 = 128
        \\                     ^
        \\
    );
}

test "feature_tests/basics/11X_negative_integer_literal_overflow" {
    try buildExpectFailExact(
        "tests/feature_tests/basics/11X_negative_integer_literal_overflow",
        \\tests/feature_tests/basics/11X_negative_integer_literal_overflow/main.rg:2:20: error: integer literal -129 does not fit in 'Int8' (min -128, max 127)
        \\      value : Int8 = -129
        \\                     ^
        \\
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
    try buildExpectFailExact(
        "tests/feature_tests/functions/05X_pipe_requires_parentheses",
        \\tests/feature_tests/functions/05X_pipe_requires_parentheses/main.rg:6:22: error: pipe right-hand side must use at least one argument placeholder
        \\      status_code = 41 | add_one
        \\                       ^
        \\
    );
}

test "feature_tests/functions/06X_pipe_requires_placeholder" {
    try buildExpectFailExact(
        "tests/feature_tests/functions/06X_pipe_requires_placeholder",
        \\tests/feature_tests/functions/06X_pipe_requires_placeholder/main.rg:6:22: error: pipe right-hand side must use at least one argument placeholder
        \\      status_code = 41 | add_one(41)
        \\                       ^
        \\
    );
}

test "feature_tests/functions/07X_pipe_expression_placeholder_not_supported" {
    try buildExpectFailExact(
        "tests/feature_tests/functions/07X_pipe_expression_placeholder_not_supported",
        \\tests/feature_tests/functions/07X_pipe_expression_placeholder_not_supported/main.rg:6:34: error: pipe placeholders are only supported as '_', '&_', '$&_', '_.field', or '..variant' payload access for now
        \\      status_code = 41 | add_one(_ + 1)
        \\                                   ^
        \\
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
    try buildExpectFailExact(
        "tests/feature_tests/functions/14X_positional_after_named_call",
        \\Parse error: ExpectedStructField
        \\tests/feature_tests/functions/14X_positional_after_named_call/main.rg:6:40: error: positional collection items must appear before named items
        \\      status_code = subtract(.left = 44, 2).diff
        \\                                         ^
        \\
    );
}

test "feature_tests/functions/15_output_default_implicit_return" {
    const test_path = "tests/feature_tests/functions/15_output_default_implicit_return";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 42);
}

test "feature_tests/functions/16X_function_signature_requires_explicit_types" {
    try buildExpectFailExact(
        "tests/feature_tests/functions/16X_function_signature_requires_explicit_types",
        \\tests/feature_tests/functions/16X_function_signature_requires_explicit_types/main.rg:1:30: error: function output field '.result' requires an explicit type
        \\  identity(.value: Int32) -> (.result) := {
        \\                               ^
        \\
    );
}

test "feature_tests/polymorphism/01_multiple_dispatch" {
    const test_path = "tests/feature_tests/polymorphism/01_multiple_dispatch";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 2);
}

test "feature_tests/polymorphism/02X_multiple_dispatch_ambiguous" {
    try buildExpectFailExact(
        "tests/feature_tests/polymorphism/02X_multiple_dispatch_ambiguous",
        \\tests/feature_tests/polymorphism/02X_multiple_dispatch_ambiguous/main.rg:12:19: error: ambiguous call to 'choose2' for arguments (.a: &Int32, .b: &Int32). Possible overloads:
        \\  - choose2 (.a: &Any, .b: &Int32) -> (.r: Int32)
        \\  - choose2 (.a: &Int32, .b: &Any) -> (.r: Int32)
        \\      status_code = choose2(.a = &i, .b = &i).r
        \\                    ^
        ++ "\n",
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
    try buildExpectFailExact(
        "tests/feature_tests/pointers/03X_assign_through_readonly_pointer",
        \\tests/feature_tests/pointers/03X_assign_through_readonly_pointer/main.rg:5:11: error: cannot assign through pointer '&Int32' because it is read-only; use '$&' when acquiring it
        \\      reader& = 1
        \\            ^
        \\
    );
}

test "feature_tests/pointers/04X_read-write_pointer_to_constant" {
    try buildExpectFailExact(
        "tests/feature_tests/pointers/04X_read-write_pointer_to_constant",
        \\tests/feature_tests/pointers/04X_read-write_pointer_to_constant/main.rg:4:32: error: binding 'value' is immutable; declare it with '::' or use '&value'
        \\      mutable_view : $&Int32 = $&value
        \\                                 ^
        \\
    );
}

test "feature_tests/pointers/05X_pass_readonly_pointer_to_mutable_param" {
    try buildExpectFailExact(
        "tests/feature_tests/pointers/05X_pass_readonly_pointer_to_mutable_param",
        \\tests/feature_tests/pointers/05X_pass_readonly_pointer_to_mutable_param/main.rg:9:14: error: no overload of 'increment' accepts arguments (.ptr: &Int32). Available signatures:
        \\  - increment (.ptr: $&Int32) -> ()
        \\      increment(.ptr=reader)
        \\               ^
        \\
    );
}

test "feature_tests/pointers/06_explicit_pointer_casts" {
    const test_path = "tests/feature_tests/pointers/06_explicit_pointer_casts";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/pointers/07X_pointer_arithmetic_requires_cast" {
    try buildExpectFailExact(
        "tests/feature_tests/pointers/07X_pointer_arithmetic_requires_cast",
        \\tests/feature_tests/pointers/07X_pointer_arithmetic_requires_cast/main.rg:4:14: error: pointer arithmetic is not allowed; cast explicitly to an integer, perform the arithmetic, and cast back
        \\      _addr := ptr + 1
        \\               ^
        \\
    );
}

test "feature_tests/pointers/08X_array_index_requires_uint_native" {
    try buildExpectFailExact(
        "tests/feature_tests/pointers/08X_array_index_requires_uint_native",
        \\tests/feature_tests/pointers/08X_array_index_requires_uint_native/main.rg:4:23: error: array index must be 'UIntNative', got 'Int32'
        \\      status_code = arr[idx]
        \\                        ^
        \\
    );
}

test "feature_tests/basics/13_core_and_libc" {
    const test_path = "tests/feature_tests/basics/13_core_and_libc";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/basics/17X_extern_call_requires_exact_argument_types" {
    try buildExpectFail(
        "tests/feature_tests/basics/17X_extern_call_requires_exact_argument_types",
        "no overload of 'putchar' accepts arguments (.character: UInt16)",
    );
}

test "feature_tests/basics/18X_constant_reassignment" {
    try buildExpectFailExact(
        "tests/feature_tests/basics/18X_constant_reassignment",
        \\tests/feature_tests/basics/18X_constant_reassignment/main.rg:3:5: error: binding 'answer' is constant and cannot be reassigned after initialization
        \\      answer = 2
        \\      ^
        \\
    );
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
    try buildExpectFailExact(
        "tests/feature_tests/polymorphism/09X_abstract_missing_requirement",
        \\tests/feature_tests/polymorphism/09X_abstract_missing_requirement/main.rg:9:1: error: type does not implement abstract 'Animal':
        \\  missing function: speak (.who: Dog)
        \\  Dog implements Animal
        \\  ^
        \\
    );
}

test "feature_tests/polymorphism/10X_abstract_wrong_signature" {
    try buildExpectFailExact(
        "tests/feature_tests/polymorphism/10X_abstract_wrong_signature",
        \\tests/feature_tests/polymorphism/10X_abstract_wrong_signature/main.rg:9:1: error: type does not implement abstract 'Animal':
        \\  missing function: speak (.who: Dog)
        \\  possible overloads:
        \\  - speak (.who: Dog) -> (.s: Int32)
        \\      file: tests/feature_tests/polymorphism/10X_abstract_wrong_signature/main.rg:13:1
        \\  Dog implements Animal
        \\  ^
        \\
    );
}

test "feature_tests/polymorphism/11_abstract_instantiation" {
    const test_path = "tests/feature_tests/polymorphism/11_abstract_instantiation";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/polymorphism/12X_abstract_instantiation_missing_default" {
    try buildExpectFailExact(
        "tests/feature_tests/polymorphism/12X_abstract_instantiation_missing_default",
        \\tests/feature_tests/polymorphism/12X_abstract_instantiation_missing_default/main.rg:4:5: error: cannot use abstract 'ExampleAbstract' as a type for a symbol. Use a concrete type or add a default concrete type to the abstract type ('ExampleAbstract defaultsto <Type>')
        \\      x : ExampleAbstract
        \\      ^
        \\
    );
}

test "feature_tests/polymorphism/15_abstract_self_output" {
    const test_path = "tests/feature_tests/polymorphism/15_abstract_self_output";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/polymorphism/16X_abstract_self_output_wrong" {
    try buildExpectFailExact(
        "tests/feature_tests/polymorphism/16X_abstract_self_output_wrong",
        \\tests/feature_tests/polymorphism/16X_abstract_self_output_wrong/main.rg:13:1: error: type does not implement abstract 'Animal':
        \\  missing function: clone (.who: Dog)
        \\  possible overloads:
        \\  - clone (.who: Dog) -> (.copy: Int32)
        \\      file: tests/feature_tests/polymorphism/16X_abstract_self_output_wrong/main.rg:9:1
        \\  Dog implements Animal
        \\  ^
        \\
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
    try buildExpectFailExact(
        "tests/feature_tests/polymorphism/13X_abstract_function_input_requires_implementation",
        \\tests/feature_tests/polymorphism/13X_abstract_function_input_requires_implementation/main.rg:8:28: error: type 'Int32' does not implement abstract 'ExampleAbstract' required by parameter '.value' of 'use_value'
        \\      status_code = use_value(.value = 7)
        \\                             ^
        \\
    );
}

test "feature_tests/polymorphism/14X_abstract_function_output_requires_default" {
    try buildExpectFailExact(
        "tests/feature_tests/polymorphism/14X_abstract_function_output_requires_default",
        \\tests/feature_tests/polymorphism/14X_abstract_function_output_requires_default/main.rg:3:1: error: error generating function make_value: InvalidType
        \\  make_value () -> (.value: ExampleAbstract) := {
        \\  ^
        \\
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
    try buildExpectFailExact(
        "tests/feature_tests/ownership/05X_noncopyable_assignment",
        \\tests/feature_tests/ownership/05X_noncopyable_assignment/main.rg:9:15: error: type 'Resource' is not copyable, so it cannot be used by value here; pass it by '&' or '$&', or implement 'copy()'
        \\      second := first
        \\                ^
        \\
    );
}

test "feature_tests/ownership/06X_noncopyable_argument_by_value" {
    try buildExpectFailExact(
        "tests/feature_tests/ownership/06X_noncopyable_argument_by_value",
        \\tests/feature_tests/ownership/06X_noncopyable_argument_by_value/main.rg:13:34: error: type 'Resource' is not copyable, so it cannot be used by value here; pass it by '&' or '$&', or implement 'copy()'
        \\      status_code = consume(.res = handle)
        \\                                   ^
        \\
    );
}

test "feature_tests/ownership/07X_noncopyable_struct_field" {
    try buildExpectFailExact(
        "tests/feature_tests/ownership/07X_noncopyable_struct_field",
        \\tests/feature_tests/ownership/07X_noncopyable_struct_field/main.rg:13:33: error: type 'Resource' is not copyable, so it cannot be used by value here; pass it by '&' or '$&', or implement 'copy()'
        \\      wrapped : Wrapper = (.res = handle)
        \\                                  ^
        \\
    );
}

test "feature_tests/ownership/08X_noncopyable_output_binding" {
    try buildExpectFailExact(
        "tests/feature_tests/ownership/08X_noncopyable_output_binding",
        \\tests/feature_tests/ownership/08X_noncopyable_output_binding/main.rg:8:11: error: type 'Resource' is not copyable, so it cannot be used by value here; pass it by '&' or '$&', or implement 'copy()'
        \\      out = res
        \\            ^
        \\
    );
}

test "feature_tests/ownership/09X_mutable_and_read_alias_same_call" {
    try buildExpectFailExact(
        "tests/feature_tests/ownership/09X_mutable_and_read_alias_same_call",
        \\tests/feature_tests/ownership/09X_mutable_and_read_alias_same_call/main.rg:5:8: error: binding 'value' cannot be passed as '$&' and '&' in the same call to 'mix'
        \\      mix(.target = $&value, .reader = &value)
        \\         ^
        \\
    );
}

test "feature_tests/ownership/10X_mutable_and_value_alias_same_call" {
    try buildExpectFailExact(
        "tests/feature_tests/ownership/10X_mutable_and_value_alias_same_call",
        \\tests/feature_tests/ownership/10X_mutable_and_value_alias_same_call/main.rg:5:8: error: binding 'value' cannot be passed as '$&' and 'value' in the same call to 'mix'
        \\      mix(.target = $&value, .snapshot = value)
        \\         ^
        \\
    );
}

test "feature_tests/ownership/11X_double_mutable_alias_same_call" {
    try buildExpectFailExact(
        "tests/feature_tests/ownership/11X_double_mutable_alias_same_call",
        \\tests/feature_tests/ownership/11X_double_mutable_alias_same_call/main.rg:5:8: error: binding 'value' cannot be passed as '$&' and '$&' in the same call to 'mix'
        \\      mix(.left = $&value, .right = $&value)
        \\         ^
        \\
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
    try buildExpectFailExact(
        "tests/feature_tests/ownership/14X_use_after_move",
        \\tests/feature_tests/ownership/14X_use_after_move/main.rg:14:34: error: binding 'handle' was moved and cannot be used again before reinitialization (moved at tests/feature_tests/ownership/14X_use_after_move/main.rg:13:34)
        \\      status_code = consume(.res = handle)
        \\                                   ^
        \\
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

test "feature_tests/types/28X_match_omit_payload_pattern" {
    try buildExpectFail(
        "tests/feature_tests/types/28X_match_omit_payload_pattern",
        "choice variant '..error' carries a payload and match must bind it explicitly; use '..error _' to ignore it",
    );
}

test "feature_tests/types/32X_match_value_noncopyable_payload" {
    try buildExpectFail(
        "tests/feature_tests/types/32X_match_value_noncopyable_payload",
        "type '{...}' is not copyable, so it cannot be used by value here; pass it by '&' or '$&', or implement 'copy()'",
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
        "type does not implement abstract 'Iterable'",
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

test "feature_tests/types/20_struct_initializer_without_init" {
    const test_path = "tests/feature_tests/types/20_struct_initializer_without_init";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 42);
}

test "feature_tests/types/21X_struct_initializer_must_use_visible_init" {
    try buildExpectFailExact(
        "tests/feature_tests/types/21X_struct_initializer_must_use_visible_init",
        \\tests/feature_tests/types/21X_struct_initializer_must_use_visible_init/main.rg:14:19: error: failed to initialize type 'Point': no visible 'init' overload accepts arguments (.x: Int32, .y: Int32). Available overloads:
        \\  - init (.p: $&Point, .sum: Int32) -> ()
        \\      point := Point(.x = 1, .y = 2)
        \\                    ^
        \\
    );
}

test "feature_tests/collections/16_dynamic_array_iterator_manual" {
    const test_path = "tests/feature_tests/collections/16_dynamic_array_iterator_manual";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/collections/17_string_hash_map_baseline" {
    const test_path = "tests/feature_tests/collections/17_string_hash_map_baseline";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/control_flow/11_range_default_start_with_step" {
    const test_path = "tests/feature_tests/control_flow/11_range_default_start_with_step";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/control_flow/12X_for_nullable_not_iterable" {
    try buildExpectFail(
        "tests/feature_tests/control_flow/12X_for_nullable_not_iterable",
        "for expects a type implementing abstract 'Iterable', got '?Int32'",
    );
}

test "feature_tests/types/14X_errable_match_unknown_variant" {
    try buildExpectFail(
        "tests/feature_tests/types/14X_errable_match_unknown_variant",
        "choice type 'Errable#(.t: Int32, .reasons: choice)' has no variant '..none'",
    );
}

test "feature_tests/types/22_error_propagation_trace" {
    const test_path = "tests/feature_tests/types/22_error_propagation_trace";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/types/23_error_context_trace" {
    const test_path = "tests/feature_tests/types/23_error_context_trace";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/types/24_error_trace_report" {
    const test_path = "tests/feature_tests/types/24_error_trace_report";
    try expectSuccessfulBuild(test_path);
    try runExpectStderr(test_path, 0,
        \\error trace (most recent first):
        \\  at tests/feature_tests/types/24_error_trace_report/main.rg:13:23: reading config
        \\        value := middle() !! "reading config"
        \\                          ^
        \\  at tests/feature_tests/types/24_error_trace_report/main.rg:8:20
        \\        value := fail()!
        \\                       ^
        \\
    );
}

test "feature_tests/types/25_choice_options_open_choices" {
    const test_path = "tests/feature_tests/types/25_choice_options_open_choices";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/types/26_error_reason_superset_propagation" {
    const test_path = "tests/feature_tests/types/26_error_reason_superset_propagation";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/types/27_void_builtin" {
    const test_path = "tests/feature_tests/types/27_void_builtin";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/types/29_match_borrowed_payload" {
    const test_path = "tests/feature_tests/types/29_match_borrowed_payload";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/types/30_match_mut_borrowed_payload" {
    const test_path = "tests/feature_tests/types/30_match_mut_borrowed_payload";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/types/31_match_move_payload" {
    const test_path = "tests/feature_tests/types/31_match_move_payload";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
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

test "feature_tests/text/03_string_buffer_io" {
    const test_path = "tests/feature_tests/text/03_string_buffer_io";
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

test "feature_tests/control_flow/16_forward_call_in_if" {
    const test_path = "tests/feature_tests/control_flow/16_forward_call_in_if";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/control_flow/17_forward_call_output_field_access_in_if" {
    const test_path = "tests/feature_tests/control_flow/17_forward_call_output_field_access_in_if";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/text/04_string_buffer_helpers" {
    const test_path = "tests/feature_tests/text/04_string_buffer_helpers";
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

test "feature_tests/io/13_file_open_error" {
    const test_path = "tests/feature_tests/io/13_file_open_error";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/io/09_print_c_string_literal" {
    const test_path = "tests/feature_tests/io/09_print_c_string_literal";
    try expectSuccessfulBuild(test_path);
    try runExpectStdout(test_path, 0, "literal output");
}

test "feature_tests/io/16_print_string_view" {
    const test_path = "tests/feature_tests/io/16_print_string_view";
    try expectSuccessfulBuild(test_path);
    try runExpectStdout(test_path, 0, "string view output");
}

test "feature_tests/io/10_read_line" {
    const test_path = "tests/feature_tests/io/10_read_line";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/io/11_read_line_grows" {
    const test_path = "tests/feature_tests/io/11_read_line_grows";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/io/12_read_line_end" {
    const test_path = "tests/feature_tests/io/12_read_line_end";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
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

test "feature_tests/system/30_environment_variables_string_view_get" {
    const test_path = "tests/feature_tests/system/30_environment_variables_string_view_get";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/system/14_file_system_capability" {
    const test_path = "tests/feature_tests/system/14_file_system_capability";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/18X_system_noncopyable_assignment" {
    try buildExpectFailExact(
        "tests/feature_tests/ownership/18X_system_noncopyable_assignment",
        \\tests/feature_tests/ownership/18X_system_noncopyable_assignment/main.rg:2:15: error: type 'System' is not copyable, so it cannot be used by value here; pass it by '&' or '$&', or implement 'copy()'
        \\      copied := system
        \\                ^
        \\
    );
}

test "feature_tests/ownership/19X_system_noncopyable_argument" {
    try buildExpectFailExact(
        "tests/feature_tests/ownership/19X_system_noncopyable_argument",
        \\tests/feature_tests/ownership/19X_system_noncopyable_argument/main.rg:6:37: error: type 'System' is not copyable, so it cannot be used by value here; pass it by '&' or '$&', or implement 'copy()'
        \\      status_code = consume(.system = system)
        \\                                      ^
        \\
    );
}

test "feature_tests/ownership/35X_system_move_by_value" {
    try buildExpectFailExact(
        "tests/feature_tests/ownership/35X_system_move_by_value",
        \\tests/feature_tests/ownership/35X_system_move_by_value/main.rg:6:37: error: System cannot be moved by value; pass it by '&' or '$&' instead
        \\      status_code = consume(.system = ~system)
        \\                                      ^
        \\
    );
}

test "feature_tests/system/15_once_single_use" {
    const test_path = "tests/feature_tests/system/15_once_single_use";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/system/16X_once_duplicate_direct" {
    try buildExpectFailExact(
        "tests/feature_tests/system/16X_once_duplicate_direct",
        \\tests/feature_tests/system/16X_once_duplicate_direct/main.rg:6:5: error: once function 'setup' is consumed more than once from the reachable entrypoint graph (first use at tests/feature_tests/system/16X_once_duplicate_direct/main.rg:5:5 via 'main')
        \\      setup()
        \\      ^
        \\
    );
}

test "feature_tests/system/17_once_unreached_duplicate_allowed" {
    const test_path = "tests/feature_tests/system/17_once_unreached_duplicate_allowed";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/system/18X_once_duplicate_indirect" {
    try buildExpectFailExact(
        "tests/feature_tests/system/18X_once_duplicate_indirect",
        \\tests/feature_tests/system/18X_once_duplicate_indirect/main.rg:9:5: error: once function 'setup' is consumed more than once from the reachable entrypoint graph (first use at tests/feature_tests/system/18X_once_duplicate_indirect/main.rg:5:5 via 'path_a')
        \\      setup()
        \\      ^
        \\
    );
}

test "feature_tests/system/19X_once_duplicate_branches" {
    try buildExpectFail(
        "tests/feature_tests/system/19X_once_duplicate_branches",
        "once function 'setup' is consumed more than once from the reachable entrypoint graph",
    );
}

test "feature_tests/system/20X_once_duplicate_init" {
    try buildExpectFailExact(
        "tests/feature_tests/system/20X_once_duplicate_init",
        \\tests/feature_tests/system/20X_once_duplicate_init/main.rg:8:15: error: once function 'init' is consumed more than once from the reachable entrypoint graph (first use at tests/feature_tests/system/20X_once_duplicate_init/main.rg:7:14 via 'main')
        \\      second := Token()
        \\                ^
        \\
    );
}

test "feature_tests/system/21X_system_duplicate_init" {
    try buildExpectFailExact(
        "tests/feature_tests/system/21X_system_duplicate_init",
        \\tests/feature_tests/system/21X_system_duplicate_init/main.rg:2:15: error: once function 'init' is consumed more than once from the reachable entrypoint graph (first use at tests/feature_tests/system/21X_system_duplicate_init/main.rg:1:24 via 'main')
        \\      second := System()
        \\                ^
        \\
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

test "feature_tests/system/25_local_typed_reach_binding" {
    const test_path = "tests/feature_tests/system/25_local_typed_reach_binding";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/system/26_file_system_error_reasons" {
    const test_path = "tests/feature_tests/system/26_file_system_error_reasons";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/system/27_path_basics" {
    const test_path = "tests/feature_tests/system/27_path_basics";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/system/28_arena_allocator_baseline" {
    const test_path = "tests/feature_tests/system/28_arena_allocator_baseline";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/system/29_array_view_baseline" {
    const test_path = "tests/feature_tests/system/29_array_view_baseline";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 12);
}

test "feature_tests/polymorphism/20_generic_abstract_bound_syntax" {
    const test_path = "tests/feature_tests/polymorphism/20_generic_abstract_bound_syntax";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 42);
}

test "feature_tests/polymorphism/21X_generic_bound_requires_type_keyword" {
    try buildExpectFailExact(
        "tests/feature_tests/polymorphism/21X_generic_bound_requires_type_keyword",
        \\Parse error: ExpectedStructField
        \\tests/feature_tests/polymorphism/21X_generic_bound_requires_type_keyword/main.rg:3:15: error: generic parameter bounds use '.t: Type: Constraint'
        \\  foo#(.t: Int32: ExampleAbstract)(.value: Int32) -> (.result: Int32) := {
        \\                ^
        \\
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

test "feature_tests/ownership/23_named_struct_auto_deinit" {
    const test_path = "tests/feature_tests/ownership/23_named_struct_auto_deinit";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 11);
}

test "feature_tests/ownership/24X_mutable_and_read_field_alias_same_call" {
    try buildExpectFailExact(
        "tests/feature_tests/ownership/24X_mutable_and_read_field_alias_same_call",
        \\tests/feature_tests/ownership/24X_mutable_and_read_field_alias_same_call/main.rg:13:8: error: binding 'pair' cannot be passed as '$&' and '&' in the same call to 'mix'
        \\      mix(.target = $&pair.left, .reader = &pair.left)
        \\         ^
        \\
    );
}

test "feature_tests/ownership/25X_mutable_and_value_field_alias_same_call" {
    try buildExpectFailExact(
        "tests/feature_tests/ownership/25X_mutable_and_value_field_alias_same_call",
        \\tests/feature_tests/ownership/25X_mutable_and_value_field_alias_same_call/main.rg:13:8: error: binding 'pair' cannot be passed as '$&' and 'value' in the same call to 'mix'
        \\      mix(.target = $&pair.left, .snapshot = pair.left)
        \\         ^
        \\
    );
}

test "feature_tests/ownership/26_distinct_fields_do_not_alias_same_call" {
    const test_path = "tests/feature_tests/ownership/26_distinct_fields_do_not_alias_same_call";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 7);
}

test "feature_tests/ownership/27X_ambiguous_copy_in_array_literal" {
    try buildExpectFailExact(
        "tests/feature_tests/ownership/27X_ambiguous_copy_in_array_literal",
        \\tests/feature_tests/ownership/27X_ambiguous_copy_in_array_literal/main.rg:17:28: error: copy() for type 'Resource' is ambiguous in value position
        \\      values : [2]Resource = (source, source)
        \\                             ^
        \\
    );
}

test "feature_tests/ownership/28X_ambiguous_copy_assignment" {
    try buildExpectFailExact(
        "tests/feature_tests/ownership/28X_ambiguous_copy_assignment",
        \\tests/feature_tests/ownership/28X_ambiguous_copy_assignment/main.rg:17:15: error: ambiguous call to 'copy' for arguments (.__arg0: Resource). Possible overloads:
        \\  - copy (.res: Resource, .tag: Int32) -> (.out: Resource)
        \\  - copy (.res: Resource, .flag: Bool) -> (.out: Resource)
        \\  - copy (.allocator: $&Allocator, .self: String) -> (.out: String)
        \\  - copy (.self: Path, .allocator: $&Allocator) -> (.out: Path)
        \\      copied := source
        \\                ^
        \\
    );
}

test "feature_tests/ownership/29_string_view_is_copyable" {
    const test_path = "tests/feature_tests/ownership/29_string_view_is_copyable";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/ownership/30_pointer_to_noncopyable_is_copyable" {
    const test_path = "tests/feature_tests/ownership/30_pointer_to_noncopyable_is_copyable";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/ownership/31_array_of_pointers_is_copyable" {
    const test_path = "tests/feature_tests/ownership/31_array_of_pointers_is_copyable";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/ownership/32X_array_of_noncopyable_is_not_copyable" {
    try buildExpectFailExact(
        "tests/feature_tests/ownership/32X_array_of_noncopyable_is_not_copyable",
        \\tests/feature_tests/ownership/32X_array_of_noncopyable_is_not_copyable/main.rg:9:15: error: type '[2]Resource' is not copyable, so it cannot be used by value here; pass it by '&' or '$&', or implement 'copy()'
        \\      copied := resources
        \\                ^
        \\
    );
}

test "feature_tests/ownership/33_return_runs_defer" {
    const test_path = "tests/feature_tests/ownership/33_return_runs_defer";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/ownership/34_error_propagation_runs_auto_deinit" {
    const test_path = "tests/feature_tests/ownership/34_error_propagation_runs_auto_deinit";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/polymorphism/23_abstract_requirement_reached_default" {
    const test_path = "tests/feature_tests/polymorphism/23_abstract_requirement_reached_default";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/polymorphism/24_abstract_dispatch_beats_regular_generic_with_defaults" {
    const test_path = "tests/feature_tests/polymorphism/24_abstract_dispatch_beats_regular_generic_with_defaults";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 1);
}

test "feature_tests/polymorphism/25X_abstract_overloads_with_defaults_ambiguous" {
    try buildExpectFailExact(
        "tests/feature_tests/polymorphism/25X_abstract_overloads_with_defaults_ambiguous",
        \\tests/feature_tests/polymorphism/25X_abstract_overloads_with_defaults_ambiguous/main.rg:14:19: error: ambiguous call to 'pick' for arguments (.value: Int32). Possible overloads:
        \\  - pick (.value: A, .left: Int32) -> (.status_code: Int32)
        \\  - pick (.value: A, .right: Int32) -> (.status_code: Int32)
        \\      status_code = pick(.value = 7).status_code
        \\                    ^
        \\
    );
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

test "feature_tests/text/12_string_concat" {
    const test_path = "tests/feature_tests/text/12_string_concat";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/text/13_string_concat_string" {
    const test_path = "tests/feature_tests/text/13_string_concat_string";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/text/14_string_concat_string_view" {
    const test_path = "tests/feature_tests/text/14_string_concat_string_view";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/text/15_string_view_concat_c_string" {
    const test_path = "tests/feature_tests/text/15_string_view_concat_c_string";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/text/16_string_view_concat_string_view" {
    const test_path = "tests/feature_tests/text/16_string_view_concat_string_view";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/text/17_string_view_concat_string" {
    const test_path = "tests/feature_tests/text/17_string_view_concat_string";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/text/18_string_view_equals_string" {
    const test_path = "tests/feature_tests/text/18_string_view_equals_string";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/text/19_string_defer_growing_cleanup" {
    const test_path = "tests/feature_tests/text/19_string_defer_growing_cleanup";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/text/21_format_baseline" {
    const test_path = "tests/feature_tests/text/21_format_baseline";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/text/22_user_module_oom_helpers" {
    const test_path = "tests/feature_tests/text/22_user_module_oom_helpers";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/text/23_cstring_as_view" {
    const test_path = "tests/feature_tests/text/23_cstring_as_view";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/types/33_error_propagation_statement_void" {
    const test_path = "tests/feature_tests/types/33_error_propagation_statement_void";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 7);
}

test "feature_tests/types/34_error_context_statement_void" {
    const test_path = "tests/feature_tests/types/34_error_context_statement_void";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/types/35_error_propagation_call_argument" {
    const test_path = "tests/feature_tests/types/35_error_propagation_call_argument";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 6);
}

test "feature_tests/types/36_error_propagation_if_condition" {
    const test_path = "tests/feature_tests/types/36_error_propagation_if_condition";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 1);
}

test "feature_tests/types/37_error_propagation_assignment" {
    const test_path = "tests/feature_tests/types/37_error_propagation_assignment";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 5);
}

test "feature_tests/types/38_inferred_errable_from_propagation" {
    const test_path = "tests/feature_tests/types/38_inferred_errable_from_propagation";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 41);
}

test "feature_tests/types/39_inferred_errable_direct_error" {
    const test_path = "tests/feature_tests/types/39_inferred_errable_direct_error";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 42);
}

test "feature_tests/types/40_inferred_errable_explicit_output" {
    const test_path = "tests/feature_tests/types/40_inferred_errable_explicit_output";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 40);
}

test "feature_tests/types/41_nullable_sugar" {
    const test_path = "tests/feature_tests/types/41_nullable_sugar";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/types/42_nullable_unwrap_or" {
    const test_path = "tests/feature_tests/types/42_nullable_unwrap_or";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/types/43_nullable_unwrap_or_do" {
    const test_path = "tests/feature_tests/types/43_nullable_unwrap_or_do";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/types/44_nullable_if_some_narrowing" {
    const test_path = "tests/feature_tests/types/44_nullable_if_some_narrowing";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
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

test "feature_tests/modules/20_inferred_errable_imported" {
    const test_path = "tests/feature_tests/modules/20_inferred_errable_imported";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 43);
}

test "feature_tests/modules/21_inferred_explicit_errable_imported" {
    const test_path = "tests/feature_tests/modules/21_inferred_explicit_errable_imported";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 44);
}


test "feature_tests/modules/03X_import_missing_module" {
    try buildExpectFailExact(
        "tests/feature_tests/modules/03X_import_missing_module",
        \\cannot resolve import './missing_dep' from 'tests/feature_tests/modules/03X_import_missing_module/main.rg'
        \\Build error: FileNotFound
        \\
    );
}

test "feature_tests/modules/04X_import_missing_value" {
    try buildExpectFailExact(
        "tests/feature_tests/modules/04X_import_missing_value",
        \\tests/feature_tests/modules/04X_import_missing_value/main.rg:3:19: error: module 'dep' has no value '.missing_value'
        \\      status_code = dep.missing_value
        \\                    ^
        \\
    );
}

test "feature_tests/modules/05X_import_missing_overload" {
    try buildExpectFailExact(
        "tests/feature_tests/modules/05X_import_missing_overload",
        \\tests/feature_tests/modules/05X_import_missing_overload/main.rg:3:35: error: module 'dep' has no function named 'missing_func'
        \\      status_code = dep.missing_func()
        \\                                    ^
        \\
    );
}

test "feature_tests/modules/06X_private_module_value" {
    try buildExpectFailExact(
        "tests/feature_tests/modules/06X_private_module_value",
        \\tests/feature_tests/modules/06X_private_module_value/main.rg:3:19: error: value '_hidden_value' is private to its module
        \\      status_code = dep._hidden_value
        \\                    ^
        \\
    );
}

test "feature_tests/modules/07X_private_module_type" {
    try buildExpectFailExact(
        "tests/feature_tests/modules/07X_private_module_type",
        \\tests/feature_tests/modules/07X_private_module_type/main.rg:3:14: error: type '_HiddenStatus' is private to its module
        \\      hidden : dep._HiddenStatus = (.code = 0)
        \\               ^
        \\
    );
}

test "feature_tests/modules/08X_private_module_function" {
    try buildExpectFailExact(
        "tests/feature_tests/modules/08X_private_module_function",
        \\tests/feature_tests/modules/08X_private_module_function/main.rg:3:37: error: function '_hidden_status' is private to its module
        \\      status_code = dep._hidden_status()
        \\                                      ^
        \\
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
    try buildExpectFailExact(
        "tests/feature_tests/modules/11X_import_cycle",
        \\import cycle detected: tests/feature_tests/modules/11X_import_cycle/dep_a -> tests/feature_tests/modules/11X_import_cycle/dep_b -> tests/feature_tests/modules/11X_import_cycle/dep_a
        \\Build error: ImportCycle
        \\
    );
}

test "feature_tests/modules/12X_import_requires_binding" {
    try buildExpectFailExact(
        "tests/feature_tests/modules/12X_import_requires_binding",
        \\Parse error: ExpectedDeclarationOrAssignment
        \\tests/feature_tests/modules/12X_import_requires_binding/main.rg:1:1: error: #import must be assigned to a name
        \\  #import("./dep")
        \\  ^
        \\
    );
}

test "feature_tests/modules/13X_import_requires_binding_nested" {
    try buildExpectFailExact(
        "tests/feature_tests/modules/13X_import_requires_binding_nested",
        \\Parse error: ExpectedDeclarationOrAssignment
        \\tests/feature_tests/modules/13X_import_requires_binding_nested/main.rg:3:9: error: #import must be assigned to a name
        \\          #import("./dep")
        \\          ^
        \\
    );
}

test "feature_tests/modules/14X_missing_function_name" {
    try buildExpectFailExact(
        "tests/feature_tests/modules/14X_missing_function_name",
        \\tests/feature_tests/modules/14X_missing_function_name/main.rg:2:31: error: no function named 'missing_func' exists
        \\      status_code = missing_func()
        \\                                ^
        \\
    );
}

test "feature_tests/modules/15_import_root_relative" {
    const test_path = "tests/feature_tests/modules/15_import_root_relative/project/app";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/modules/16X_root_relative_missing_import" {
    try buildExpectFailExact(
        "tests/feature_tests/modules/16X_root_relative_missing_import/project/app",
        \\cannot resolve import '.../missing_shared' from 'tests/feature_tests/modules/16X_root_relative_missing_import/project/app/main.rg'
        \\Build error: FileNotFound
        \\
    );
}

test "feature_tests/modules/17_multi_file_module_forward_calls" {
    const test_path = "tests/feature_tests/modules/17_multi_file_module_forward_calls";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/modules/27_multi_file_typed_binding_initialization" {
    const test_path = "tests/feature_tests/modules/27_multi_file_typed_binding_initialization";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 42);
}

test "feature_tests/modules/18_private_struct_field_same_module" {
    const test_path = "tests/feature_tests/modules/18_private_struct_field_same_module";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 42);
}

test "feature_tests/modules/19X_private_struct_field_imported" {
    try buildExpectFailExact(
        "tests/feature_tests/modules/19X_private_struct_field_imported",
        \\tests/feature_tests/modules/19X_private_struct_field_imported/main.rg:4:32: error: field '_hidden' is private to its module
        \\      status_code = point._hidden
        \\                                 ^
        \\
    );
}

test "feature_tests/modules/22_imported_abstract_input_dispatch" {
    const test_path = "tests/feature_tests/modules/22_imported_abstract_input_dispatch";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 45);
}

test "feature_tests/modules/23_imported_abstract_monomorphization" {
    const test_path = "tests/feature_tests/modules/23_imported_abstract_monomorphization";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 3);
}

test "feature_tests/modules/24_imported_generic_abstract_dispatch_prefers_concrete" {
    const test_path = "tests/feature_tests/modules/24_imported_generic_abstract_dispatch_prefers_concrete";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 2);
}

test "feature_tests/modules/25X_private_choice_option_imported" {
    try buildExpectFailExact(
        "tests/feature_tests/modules/25X_private_choice_option_imported",
        \\tests/feature_tests/modules/25X_private_choice_option_imported/main.rg:4:10: error: choice option '_hidden_reason' is private to its module
        \\      dep.._hidden_reason
        \\           ^
        \\
    );
}

test "feature_tests/modules/26X_module_qualified_ambiguous_overload" {
    try buildExpectFailExact(
        "tests/feature_tests/modules/26X_module_qualified_ambiguous_overload",
        \\tests/feature_tests/modules/26X_module_qualified_ambiguous_overload/main.rg:4:19: error: module-qualified call 'dep.pick' is ambiguous for arguments (.value: Int32). Possible overloads:
        \\  - pick (.value: Int32, .left: Int32) -> (.result: Int32)
        \\  - pick (.value: Int32, .right: Int32) -> (.result: Int32)
        \\      _ ::= dep.pick(.value = 1)
        \\                    ^
        \\
    );
}

test "feature_tests/modules/28X_imported_abstract_input_requires_implementation" {
    try buildExpectFail(
        "tests/feature_tests/modules/28X_imported_abstract_input_requires_implementation",
        "type 'Int32' does not implement abstract 'ExampleAbstract' required by parameter '.value' of 'use_value'",
    );
}

test "feature_tests/modules/29X_imported_abstract_ambiguous_overload" {
    try buildExpectFailExact(
        "tests/feature_tests/modules/29X_imported_abstract_ambiguous_overload",
        \\tests/feature_tests/modules/29X_imported_abstract_ambiguous_overload/main.rg:4:19: error: module-qualified call 'dep.pick' is ambiguous for arguments (.value: Int32). Possible overloads:
        \\  - pick (.value: A, .left: Int32) -> (.result: Int32)
        \\  - pick (.value: A, .right: Int32) -> (.result: Int32)
        \\      _ ::= dep.pick(.value = 1)
        \\                    ^
        \\
    );
}

test "feature_tests/modules/30X_nonconstant_module_binding_initialization" {
    try buildExpectFailExact(
        "tests/feature_tests/modules/30X_nonconstant_module_binding_initialization",
        \\tests/feature_tests/modules/30X_nonconstant_module_binding_initialization/main.rg:5:1: error: module-level binding 'computed' must use a constant initializer for now
        \\  computed : Int32 = make_value().value
        \\  ^
        \\
    );
}

test "feature_tests/modules/31X_cyclic_module_binding_initialization" {
    try buildExpectFailExact(
        "tests/feature_tests/modules/31X_cyclic_module_binding_initialization",
        \\tests/feature_tests/modules/31X_cyclic_module_binding_initialization/a_first.rg:1:1: error: module-level binding 'first' participates in a cyclic initializer dependency
        \\  first : Int32 = second + 1
        \\  ^
        \\
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

test "feature_tests/testing/01_simple_pass" {
    try argiTestExpectStderr(
        "tests/feature_tests/testing/01_simple_pass",
        &.{},
        0,
        "PASS simple_pass\n",
    );
}

test "feature_tests/testing/01_simple_pass_uses_local_cache" {
    var root = try std.fs.cwd().openDir(compilerRoot(), .{});
    defer root.close();

    root.deleteTree(".argi-cache/tests") catch |err| {
        if (err != error.FileNotFound) return err;
    };
    root.deleteTree("build/tests") catch |err| {
        if (err != error.FileNotFound) return err;
    };

    try argiTestExpectStderr(
        "tests/feature_tests/testing/01_simple_pass",
        &.{},
        0,
        "PASS simple_pass\n",
    );

    try root.access(".argi-cache/tests", .{});
    root.access("build/tests", .{}) catch |err| switch (err) {
        error.FileNotFound => {},
        else => return err,
    };
}

test "feature_tests/testing/02_skip" {
    try argiTestExpectStderrContains(
        "tests/feature_tests/testing/02_skip",
        &.{},
        0,
        "SKIP skipped_case\n",
    );
}

test "feature_tests/testing/03_once_isolated_per_test" {
    try argiTestExpectStderr(
        "tests/feature_tests/testing/03_once_isolated_per_test",
        &.{},
        0,
        "PASS first\nPASS second\n",
    );
}

test "feature_tests/testing/03_once_isolated_per_test_filter" {
    try argiTestExpectStderr(
        "tests/feature_tests/testing/03_once_isolated_per_test",
        &.{ "--filter", "second" },
        0,
        "PASS second\n",
    );
}

test "feature_tests/testing/04_expect_equal" {
    try argiTestExpectStderr(
        "tests/feature_tests/testing/04_expect_equal",
        &.{},
        0,
        "PASS equality\n",
    );
}

test "feature_tests/testing/05_assertion_failure" {
    try argiTestExpectStderr(
        "tests/feature_tests/testing/05_assertion_failure",
        &.{},
        1,
        "FAIL assertion_failure\n",
    );
}

test "feature_tests/testing/06_direct_propagated_error" {
    try argiTestExpectStderr(
        "tests/feature_tests/testing/06_direct_propagated_error",
        &.{},
        1,
        "FAIL direct_propagation\n",
    );
}

test "feature_tests/testing/07_build_ignores_tests" {
    const test_path = "tests/feature_tests/testing/07_build_ignores_tests";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/testing/08X_test_signature_requires_v1_shape" {
    try argiTestExpectStderrContains(
        "tests/feature_tests/testing/08X_test_signature_requires_v1_shape",
        &.{},
        1,
        "tests must declare exactly one input: '.system: System = System()'",
    );
}

test "feature_tests/testing/09_expected_error" {
    try argiTestExpectStderr(
        "tests/feature_tests/testing/09_expected_error",
        &.{},
        0,
        "PASS expected_error\n",
    );
}

test "feature_tests/testing/10_expected_error_mismatch" {
    try argiTestExpectStderr(
        "tests/feature_tests/testing/10_expected_error_mismatch",
        &.{},
        1,
        "FAIL expected_error_mismatch\n",
    );
}

test "feature_tests/testing/11_expected_error_unexpected_ok" {
    try argiTestExpectStderr(
        "tests/feature_tests/testing/11_expected_error_unexpected_ok",
        &.{},
        1,
        "FAIL expected_error_unexpected_ok\n",
    );
}
