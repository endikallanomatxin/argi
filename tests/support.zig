const std = @import("std");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

pub const argi_bin = if (@import("builtin").os.tag == .windows) "zig-out/bin/argi.exe" else "zig-out/bin/argi";

pub fn compilerRoot() []const u8 {
    const this_file = @src().file;
    const tests_dir = std.fs.path.dirname(this_file) orelse ".";
    return std.fs.path.dirname(tests_dir) orelse tests_dir;
}

pub fn outputPathFor(name: []const u8) ![]u8 {
    return std.fmt.allocPrint(std.testing.allocator, "{s}/build/output{s}", .{ name, if (@import("builtin").os.tag == .windows) ".exe" else "" });
}

pub fn irPathFor(name: []const u8) ![]u8 {
    const output_path = try outputPathFor(name);
    defer std.testing.allocator.free(output_path);

    return std.fmt.allocPrint(
        std.testing.allocator,
        "{s}.ll",
        .{output_path},
    );
}

pub fn objPathFor(name: []const u8) ![]u8 {
    const output_path = try outputPathFor(name);
    defer std.testing.allocator.free(output_path);

    return std.fmt.allocPrint(
        std.testing.allocator,
        "{s}.o",
        .{output_path},
    );
}

pub fn argiTestCacheDirForModule(module_dir: []const u8) ![]u8 {
    var hasher = std.hash.Wyhash.init(0);
    hasher.update(module_dir);
    return std.fmt.allocPrint(
        std.testing.allocator,
        "{s}/.argi-cache/tests/{x}",
        .{ compilerRoot(), hasher.final() },
    );
}

pub fn clean(name: []const u8) !void {
    var root = try std.Io.Dir.cwd().openDir(std.testing.io, compilerRoot(), .{});
    defer root.close(std.testing.io);

    const output_path = try outputPathFor(name);
    defer std.testing.allocator.free(output_path);

    const ir_path = try irPathFor(name);
    defer std.testing.allocator.free(ir_path);

    const obj_path = try objPathFor(name);
    defer std.testing.allocator.free(obj_path);

    root.deleteFile(std.testing.io, ir_path) catch |err| {
        if (err != error.FileNotFound) return err;
    };
    root.deleteFile(std.testing.io, output_path) catch |err| {
        if (err != error.FileNotFound) return err;
    };
    root.deleteFile(std.testing.io, obj_path) catch |err| {
        if (err != error.FileNotFound) return err;
    };
}

// Fixture processes already run in parallel. Keep their frontend work serial
// unless a concurrency test explicitly chooses another policy.
pub fn compilerTestArgs(argv: []const []const u8) ![][]const u8 {
    const allocator = std.testing.allocator;
    if (argv.len < 2) return allocator.dupe([]const u8, argv);
    const executable = std.fs.path.basename(argv[0]);
    const compiler = std.mem.eql(u8, executable, "argi") or std.mem.eql(u8, executable, "argi.exe");
    const is_run = std.mem.eql(u8, argv[1], "run");
    const builds = is_run or std.mem.eql(u8, argv[1], "build") or std.mem.eql(u8, argv[1], "check");
    if (!compiler or !builds) return allocator.dupe([]const u8, argv);
    for (argv[2..]) |arg| if (std.mem.eql(u8, arg, "--frontend-jobs")) return allocator.dupe([]const u8, argv);
    // Keep a selected run executable first, before ordinary build flags.
    const insert: usize = if (is_run and argv.len > 2 and !std.mem.startsWith(u8, argv[2], "--")) 3 else 2;
    const result = try allocator.alloc([]const u8, argv.len + 2);
    @memcpy(result[0..insert], argv[0..insert]);
    result[insert] = "--frontend-jobs";
    result[insert + 1] = "1";
    @memcpy(result[insert + 2 ..], argv[insert..]);
    return result;
}

pub fn runChild(argv: []const []const u8) !std.process.RunResult {
    const test_args = try compilerTestArgs(argv);
    defer std.testing.allocator.free(test_args);
    const result = try std.process.run(std.testing.allocator, std.testing.io, .{
        .argv = test_args,
        .cwd = .{ .path = compilerRoot() },
    });
    return normalizeRunResult(result);
}

pub fn runArgiCommand(args: []const []const u8) !std.process.RunResult {
    const argv = try std.testing.allocator.alloc([]const u8, args.len + 1);
    defer std.testing.allocator.free(argv);

    argv[0] = argi_bin;
    for (args, 0..) |arg, idx| {
        argv[idx + 1] = arg;
    }

    return runChild(argv);
}

pub fn runArgiCommandWithEnv(
    args: []const []const u8,
    env_map: *const std.process.Environ.Map,
) !std.process.RunResult {
    const argv = try std.testing.allocator.alloc([]const u8, args.len + 1);
    defer std.testing.allocator.free(argv);

    argv[0] = argi_bin;
    for (args, 0..) |arg, idx| {
        argv[idx + 1] = arg;
    }

    const test_args = try compilerTestArgs(argv);
    defer std.testing.allocator.free(test_args);
    const result = try std.process.run(std.testing.allocator, std.testing.io, .{
        .argv = test_args,
        .cwd = .{ .path = compilerRoot() },
        .environ_map = env_map,
    });
    return normalizeRunResult(result);
}

pub fn expectArgiBuildSuccess(args: []const []const u8) !void {
    const result = try runArgiCommand(args);
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);

    try expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
}

pub fn runChildInCwd(argv: []const []const u8, cwd: []const u8) !std.process.RunResult {
    const test_args = try compilerTestArgs(argv);
    defer std.testing.allocator.free(test_args);
    const result = try std.process.run(std.testing.allocator, std.testing.io, .{
        .argv = test_args,
        .cwd = .{ .path = cwd },
    });
    return normalizeRunResult(result);
}

pub fn runChildInCwdWithEnv(
    argv: []const []const u8,
    cwd: []const u8,
    env_map: *const std.process.Environ.Map,
) !std.process.RunResult {
    const test_args = try compilerTestArgs(argv);
    defer std.testing.allocator.free(test_args);
    const result = try std.process.run(std.testing.allocator, std.testing.io, .{
        .argv = test_args,
        .cwd = .{ .path = cwd },
        .environ_map = env_map,
    });
    return normalizeRunResult(result);
}

pub fn normalizeRunResult(result: std.process.RunResult) !std.process.RunResult {
    const root = try repoRootPrefix();
    defer std.testing.allocator.free(root);
    const root_with_sep = try std.fmt.allocPrint(std.testing.allocator, "{s}{c}", .{ root, std.fs.path.sep });
    defer std.testing.allocator.free(root_with_sep);

    var normalized = result;
    const stdout = normalized.stdout;
    normalized.stdout = try std.mem.replaceOwned(u8, std.testing.allocator, stdout, root_with_sep, "");
    std.testing.allocator.free(stdout);

    const stderr = normalized.stderr;
    normalized.stderr = try std.mem.replaceOwned(u8, std.testing.allocator, stderr, root_with_sep, "");
    std.testing.allocator.free(stderr);
    if (@import("builtin").os.tag == .windows) normalizeDiagnosticPaths(normalized.stderr);

    return normalized;
}

// Normalize source-location headers only; code excerpts and program output may
// contain literal backslashes whose spelling is part of the asserted behavior.
pub fn normalizeDiagnosticPaths(bytes: []u8) void {
    var start: usize = 0;
    while (start < bytes.len) {
        const end = std.mem.indexOfScalarPos(u8, bytes, start, '\n') orelse bytes.len;
        const line = bytes[start..end];
        if (line.len > 0 and !std.ascii.isWhitespace(line[0])) {
            normalizeSourceLocation(line);
            if (std.mem.indexOf(u8, line, "first use at ")) |first_use|
                normalizeSourceLocation(line[first_use + "first use at ".len ..]);
        } else {
            const trimmed = std.mem.trimStart(u8, line, " \t");
            if (std.mem.startsWith(u8, trimmed, "file: "))
                normalizeSourceLocation(line[line.len - trimmed.len + "file: ".len ..]);
        }
        start = end + 1;
    }
}

pub fn normalizeSourceLocation(bytes: []u8) void {
    if (std.mem.indexOf(u8, bytes, ".rg:")) |path_end| {
        for (bytes[0 .. path_end + 3]) |*byte| if (byte.* == '\\') {
            byte.* = '/';
        };
    }
}

pub fn repoRootPrefix() ![]u8 {
    const cwd = try std.process.currentPathAlloc(std.testing.io, std.testing.allocator);
    defer std.testing.allocator.free(cwd);
    return std.fs.path.resolve(std.testing.allocator, &.{ cwd, compilerRoot() });
}

pub fn installedArgiPath() ![]u8 {
    const repo_root = try repoRootPrefix();
    defer std.testing.allocator.free(repo_root);
    return std.fs.path.join(std.testing.allocator, &.{ repo_root, argi_bin });
}

pub fn tmpDirRootPath(tmp: *const std.testing.TmpDir) ![]u8 {
    const repo_root = try repoRootPrefix();
    defer std.testing.allocator.free(repo_root);
    return std.fs.path.join(std.testing.allocator, &.{ repo_root, ".zig-cache", "tmp", tmp.sub_path[0..] });
}

pub fn buildResult(name: []const u8) !std.process.RunResult {
    try clean(name);
    return runChild(&[_][]const u8{
        argi_bin,
        "build",
        name,
    });
}

pub fn expectSuccessfulBuild(name: []const u8) !void {
    const result = try buildResult(name);
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);

    if (result.term != .exited or result.term.exited != 0)
        std.debug.print("argi build {s} failed:\n{s}", .{ name, result.stderr });
    try expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
}

pub fn expectDiagnostic(name: []const u8, actual: []const u8, expected: []const u8) !void {
    if (std.mem.indexOf(u8, actual, expected) != null) return;
    std.debug.print("build rejection for {s} is missing diagnostic '{s}':\n{s}\n", .{ name, expected, actual });
    return error.MissingExpectedDiagnostic;
}

pub fn buildExpectFailWithoutNoise(name: []const u8, expected_stderr: []const u8, forbidden_stderr: []const u8) !void {
    const result = try buildResult(name);
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);

    switch (result.term) {
        .exited => |code| try expect(code != 0),
        else => return error.UnexpectedProcessTermination,
    }

    try expectDiagnostic(name, result.stderr, expected_stderr);
    if (std.mem.indexOf(u8, result.stderr, forbidden_stderr) != null) {
        std.debug.print("build rejection for {s} contains forbidden diagnostic '{s}':\n{s}\n", .{ name, forbidden_stderr, result.stderr });
        return error.UnexpectedDiagnostic;
    }
}

pub fn buildExpectFailExact(name: []const u8, expected_stderr: []const u8) !void {
    const result = try buildResult(name);
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);

    switch (result.term) {
        .exited => |code| try expect(code != 0),
        else => return error.UnexpectedProcessTermination,
    }

    try expectEqualStrings(expected_stderr, result.stderr);
    try expect(std.mem.indexOf(u8, result.stdout, "Parse error:") == null);
    try expect(std.mem.indexOf(u8, result.stderr, "Parse error:") == null);
}

pub fn runExpect(name: []const u8, expected_code: u8) !void {
    const output_path = try outputPathFor(name);
    defer std.testing.allocator.free(output_path);

    const result = try runChild(&[_][]const u8{output_path});
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);

    if (result.term != .exited or result.term.exited != expected_code) {
        std.debug.print("execution of {s}: expected exit {d}, got {any}\nstdout:\n{s}\nstderr:\n{s}\n", .{
            name, expected_code, result.term, result.stdout, result.stderr,
        });
    }
    try expectEqual(std.process.Child.Term{ .exited = expected_code }, result.term);
}

pub fn runExpectFailure(name: []const u8) !void {
    const output_path = try outputPathFor(name);
    defer std.testing.allocator.free(output_path);

    const result = try runChild(&[_][]const u8{output_path});
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);

    switch (result.term) {
        .exited => |code| try expect(code != 0),
        .signal, .stopped => {},
        .unknown => return error.UnexpectedProcessTermination,
    }
}

pub fn run(name: []const u8) !void {
    try runExpect(name, 0);
}

pub fn qualifiedTestOutput(name: []const u8, output: []const u8) ![]u8 {
    const allocator = std.testing.allocator;
    const path = name;
    var writer: std.Io.Writer.Allocating = .init(allocator);
    defer writer.deinit();
    var lines = std.mem.splitScalar(u8, output, '\n');
    var first = true;
    while (lines.next()) |line| {
        if (!first) try writer.writer.writeByte('\n');
        first = false;
        if (std.mem.startsWith(u8, line, "PASS ") or std.mem.startsWith(u8, line, "FAIL ") or std.mem.startsWith(u8, line, "SKIP ")) {
            try writer.writer.print("{s}{s}/{s}", .{ line[0..5], path, line[5..] });
        } else try writer.writer.writeAll(line);
    }
    return allocator.dupe(u8, writer.written());
}

pub fn argiTestExpectStderr(
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

    try expectEqual(std.process.Child.Term{ .exited = expected_code }, result.term);
    const qualified = try qualifiedTestOutput(name, expected_stderr);
    defer std.testing.allocator.free(qualified);
    try expectEqualStrings(qualified, result.stderr);
}

pub fn argiTestExpectStderrContains(
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

    try expectEqual(std.process.Child.Term{ .exited = expected_code }, result.term);
    const qualified = try qualifiedTestOutput(name, expected_stderr_fragment);
    defer std.testing.allocator.free(qualified);
    try expect(std.mem.indexOf(u8, result.stderr, qualified) != null);
}

pub fn runExpectStdoutWithArgs(
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

    try expectEqual(std.process.Child.Term{ .exited = expected_code }, result.term);
    try expectEqualStrings(expected_stdout, result.stdout);
}

pub fn runExpectStderr(name: []const u8, expected_code: u8, expected_stderr: []const u8) !void {
    const output_path = try outputPathFor(name);
    defer std.testing.allocator.free(output_path);

    const result = try runChild(&[_][]const u8{output_path});
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);

    try expectEqual(std.process.Child.Term{ .exited = expected_code }, result.term);
    try expectEqualStrings(expected_stderr, result.stderr);
}

pub fn runExpectStdoutWithArgsAndStdin(
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

    var child = try std.process.spawn(std.testing.io, .{
        .argv = argv,
        .cwd = .{ .path = compilerRoot() },
        .stdin = .pipe,
        .stdout = .pipe,
        .stderr = .pipe,
    });

    if (child.stdin) |stdin_pipe| {
        try stdin_pipe.writeStreamingAll(std.testing.io, stdin_text);
        stdin_pipe.close(std.testing.io);
        child.stdin = null;
    }

    var mr_buffer: std.Io.File.MultiReader.Buffer(2) = undefined;
    var multi_reader: std.Io.File.MultiReader = undefined;
    multi_reader.init(std.testing.allocator, std.testing.io, mr_buffer.toStreams(), &.{ child.stdout.?, child.stderr.? });
    defer multi_reader.deinit();

    while (true) {
        if (multi_reader.fill(1, .none)) |_| {
            continue;
        } else |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        }
    }

    const stdout_owned = try multi_reader.toOwnedSlice(0);
    defer std.testing.allocator.free(stdout_owned);
    const stderr_owned = try multi_reader.toOwnedSlice(1);
    defer std.testing.allocator.free(stderr_owned);

    try expectEqual(std.process.Child.Term{ .exited = expected_code }, try child.wait(std.testing.io));
    try expectEqualStrings(expected_stdout, stdout_owned);
}

pub fn pathInTest(name: []const u8, leaf: []const u8) ![]u8 {
    return std.fmt.allocPrint(std.testing.allocator, "{s}/{s}", .{ name, leaf });
}

pub fn vmExpect(path: []const u8, status: u8, diagnostic: ?[]const u8) !void {
    const result = try runArgiCommand(&.{ "run", "--vm", path });
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);
    if (result.term != .exited or result.term.exited != status) std.debug.print("VM stderr: {s}\n", .{result.stderr});
    try expectEqual(std.process.Child.Term{ .exited = status }, result.term);
    if (diagnostic) |text| {
        try expect(std.mem.indexOf(u8, result.stderr, text) != null);
        try expect(std.mem.indexOf(u8, result.stderr, "main.rg:") != null);
    }
}
