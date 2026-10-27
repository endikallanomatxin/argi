const std = @import("std");
pub const frontend_context = @import("frontend_context.zig");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

pub const argi_bin = if (@import("builtin").os.tag == .windows) "zig-out/bin/argi.exe" else "zig-out/bin/argi";

pub fn compilerRoot() []const u8 {
    return @import("program_test_options").repository_root;
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

pub fn buildExpectFail(name: []const u8, expected_stderr: []const u8) !void {
    const result = try buildResult(name);
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);

    switch (result.term) {
        .exited => |code| try expect(code != 0),
        else => return error.UnexpectedProcessTermination,
    }

    try expectDiagnostic(name, result.stderr, expected_stderr);
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

pub fn buildExpectFailWithoutParseNoise(name: []const u8, expected_stderr_fragment: []const u8) !void {
    const result = try buildResult(name);
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);

    switch (result.term) {
        .exited => |code| try expect(code != 0),
        else => return error.UnexpectedProcessTermination,
    }

    try expectDiagnostic(name, result.stderr, expected_stderr_fragment);
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
    try runFailure(name, null);
}

pub fn runExpectFailureContaining(name: []const u8, diagnostic: []const u8) !void {
    try runFailure(name, diagnostic);
}

fn runFailure(name: []const u8, diagnostic: ?[]const u8) !void {
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
    if (diagnostic) |text| try expectDiagnostic(name, result.stderr, text);
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

pub fn runExpectStdout(name: []const u8, expected_code: u8, expected_stdout: []const u8) !void {
    try runExpectStdoutWithArgs(name, &[_][]const u8{}, expected_code, expected_stdout);
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

pub fn fileHasSubstantiveContent(root: std.Io.Dir, relative_path: []const u8) !bool {
    const text = try root.readFileAlloc(std.testing.io, relative_path, std.testing.allocator, .limited(1024 * 1024));
    defer std.testing.allocator.free(text);

    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;
        if (std.mem.startsWith(u8, trimmed, "--")) continue;
        return true;
    }

    return false;
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

pub const Isolation = enum { fixture, exclusive };

/// Semantic rejection through the real frontend and Safety, without a CLI process.
pub fn expectFrontendFailure(name: []const u8, diagnostic: []const u8) !void {
    return @import("frontend_context.zig").check(name, .{ .message = diagnostic });
}

pub fn expectFrontendFailureWithoutNoise(name: []const u8, diagnostic: []const u8, forbidden: []const u8) !void {
    return @import("frontend_context.zig").check(name, .{ .message = diagnostic, .forbidden = &.{forbidden} });
}

pub fn expectFrontendFailureWithoutParseNoise(name: []const u8, diagnostic: []const u8) !void {
    return @import("frontend_context.zig").check(name, .{ .message = diagnostic, .no_syntax_noise = true });
}

pub fn expectSyntaxFailure(name: []const u8, diagnostic: []const u8) !void {
    return @import("frontend_context.zig").check(name, .{ .message = diagnostic, .kind = .syntax });
}

pub fn expectSyntaxFailureWithoutNoise(name: []const u8, diagnostic: []const u8, forbidden: []const u8) !void {
    return @import("frontend_context.zig").check(name, .{ .message = diagnostic, .kind = .syntax, .forbidden = &.{forbidden} });
}

pub fn expectFrontendDiagnostic(name: []const u8, expected: @import("compiler_test_frontend").ExpectedDiagnostic) !void {
    return @import("frontend_context.zig").check(name, expected);
}

pub fn checkNativeCFixture(path: []const u8, ir_needles: []const []const u8) !void {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmpDirRootPath(&tmp);
    defer allocator.free(root);
    const argi = try installedArgiPath();
    defer allocator.free(argi);
    const repo = try repoRootPrefix();
    defer allocator.free(repo);
    const fixture = try std.fs.path.join(allocator, &.{ repo, path });
    defer allocator.free(fixture);
    const source = try std.fs.path.join(allocator, &.{ fixture, "native.c" });
    defer allocator.free(source);
    const compiled = try runChildInCwd(&.{ "cc", "-c", source, "-o", "native.o" }, root);
    defer allocator.free(compiled.stdout);
    defer allocator.free(compiled.stderr);
    try expectEqual(std.process.Child.Term{ .exited = 0 }, compiled.term);
    for (0..2) |_| {
        const built = try runChildInCwd(&.{ argi, "build", fixture, "--output", "app", "--link-file", "native.o", "--emit-llvm", "app.ll" }, root);
        defer allocator.free(built.stdout);
        defer allocator.free(built.stderr);
        if (built.term != .exited or built.term.exited != 0) std.debug.print("{s}", .{built.stderr});
        try expectEqual(std.process.Child.Term{ .exited = 0 }, built.term);
        const executed = try runChildInCwd(&.{"./app"}, root);
        defer allocator.free(executed.stdout);
        defer allocator.free(executed.stderr);
        try expectEqual(std.process.Child.Term{ .exited = 0 }, executed.term);
        const ir = try tmp.dir.readFileAlloc(std.testing.io, "app.ll", allocator, .limited(1024 * 1024));
        defer allocator.free(ir);
        for (ir_needles) |needle| try expect(std.mem.indexOf(u8, ir, needle) != null);
    }
}

// Reuse the same scenario as an entry body and behind one extra call boundary.
// Concrete checking visits both bodies, while the caller observes only the
// inferred summary. This catches lost cleanup/dependency effects in wrappers.
pub fn expectSafetyWrapperParity(case_path: []const u8, diagnostic: ?[]const u8) !void {
    const allocator = std.testing.allocator;
    const io = std.testing.io;
    const source_path = try std.fs.path.join(allocator, &.{ case_path, "main.rg" });
    defer allocator.free(source_path);
    const source = try std.Io.Dir.cwd().readFileAlloc(io, source_path, allocator, .limited(1024 * 1024));
    defer allocator.free(source);
    const entry = std.mem.indexOf(u8, source, "main :=") orelse return error.MissingParityEntry;
    const renamed = try std.fmt.allocPrint(allocator, "{s}parity_body{s}", .{ source[0..entry], source[entry + 4 ..] });
    defer allocator.free(renamed);
    const relocated = try std.mem.replaceOwned(u8, allocator, renamed, "../../_support/unsafe_allocation", "./support");
    defer allocator.free(relocated);
    // Add summary boundaries around transfers whose effects are observed later
    // in the same scenario; merely wrapping the entry would hide local effects.
    const cleanup_calls = try std.mem.replaceOwned(u8, allocator, relocated, "deinit(.self =", "parity_deinit(.self =");
    defer allocator.free(cleanup_calls);
    const opaque_calls = try std.mem.replaceOwned(u8, allocator, cleanup_calls, "trusted_opaque_drop(.slot =", "parity_drop(.slot =");
    defer allocator.free(opaque_calls);
    const constructor_calls = try std.mem.replaceOwned(u8, allocator, opaque_calls, "Owned(.allocator =", "parity_owned(.allocator =");
    defer allocator.free(constructor_calls);
    const constructor_wrapper: []const u8 = if (std.mem.indexOf(u8, relocated, "Owned :=") != null)
        if (std.mem.indexOf(u8, relocated, ".fail =") != null)
            "parity_owned := #(.AllocatorType: Type: Allocator#(AllocatorType)) (.allocator: $&AllocatorType, .fail: Bool) -> (.result: Errable#(.t: Owned, .reasons: (..out_of_memory))) { result = Owned(.allocator = allocator, .fail = fail) }\n"
        else
            "parity_owned := #(.AllocatorType: Type: Allocator#(AllocatorType)) (.allocator: $&AllocatorType) -> (.result: Errable#(.t: Owned, .reasons: (..out_of_memory))) { result = Owned(.allocator = allocator) }\n"
    else
        "";
    const arguments = if (std.mem.startsWith(u8, source[entry..], "main := (.system: System")) ".system = system" else "";
    const wrapped = try std.fmt.allocPrint(
        allocator,
        "{s}\nmain := (.system: System) -> (.status_code: Int32) {{\n    status_code = parity_body({s})\n}}\n",
        .{ constructor_calls, arguments },
    );
    defer allocator.free(wrapped);
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(io, "module/support");
    try tmp.dir.writeFile(io, .{ .sub_path = "module/main.rg", .data = wrapped });
    const transfers = try std.fmt.allocPrint(
        allocator,
        "parity_deinit := #(.t: Type) (.self: $&t) -> () {{ deinit(.self = self) }}\n" ++
            "parity_drop := #(.t: Type) (.slot: $&t) -> () {{ trusted_opaque_drop(.slot = slot) }}\n{s}",
        .{constructor_wrapper},
    );
    defer allocator.free(transfers);
    try tmp.dir.writeFile(io, .{ .sub_path = "module/transfers.rg", .data = transfers });
    const support = try std.Io.Dir.cwd().readFileAlloc(io, "tests/feature_tests/_support/unsafe_allocation/helpers.rg", allocator, .limited(1024 * 1024));
    defer allocator.free(support);
    try tmp.dir.writeFile(io, .{ .sub_path = "module/support/helpers.rg", .data = support });
    const tmp_root = try tmpDirRootPath(&tmp);
    defer allocator.free(tmp_root);
    const module_path = try std.fs.path.join(allocator, &.{ tmp_root, "module" });
    defer allocator.free(module_path);
    const original = try buildResult(case_path);
    defer allocator.free(original.stdout);
    defer allocator.free(original.stderr);
    const caller = try buildResult(module_path);
    defer allocator.free(caller.stdout);
    defer allocator.free(caller.stderr);
    if (!std.meta.eql(original.term, caller.term)) {
        std.debug.print("safety parity mismatch for {s}:\n{s}\n{s}\n", .{ case_path, original.stderr, caller.stderr });
    }
    try expectEqual(original.term, caller.term);
    if (diagnostic) |message| {
        try expectEqual(std.process.Child.Term{ .exited = 1 }, original.term);
        try expect(std.mem.indexOf(u8, original.stderr, message) != null);
        if (std.mem.indexOf(u8, caller.stderr, message) == null)
            std.debug.print("missing parity diagnostic for {s}:\n{s}\n", .{ case_path, caller.stderr });
        try expect(std.mem.indexOf(u8, caller.stderr, message) != null);
    } else {
        try expectEqual(std.process.Child.Term{ .exited = 0 }, original.term);
        const original_exe = try outputPathFor(case_path);
        defer allocator.free(original_exe);
        const caller_exe = try outputPathFor(module_path);
        defer allocator.free(caller_exe);
        const direct = try runChild(&.{original_exe});
        defer allocator.free(direct.stdout);
        defer allocator.free(direct.stderr);
        const indirect = try runChild(&.{caller_exe});
        defer allocator.free(indirect.stdout);
        defer allocator.free(indirect.stderr);
        try expectEqual(std.process.Child.Term{ .exited = 0 }, direct.term);
        try expectEqual(direct.term, indirect.term);
        try expectEqualStrings(direct.stdout, indirect.stdout);
        try expectEqualStrings(direct.stderr, indirect.stderr);
    }
}
