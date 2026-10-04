const std = @import("std");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

const argi_bin = if (@import("builtin").os.tag == .windows) "zig-out/bin/argi.exe" else "zig-out/bin/argi";

fn compilerRoot() []const u8 {
    const this_file = @src().file;
    const tests_dir = std.fs.path.dirname(this_file) orelse ".";
    return std.fs.path.dirname(tests_dir) orelse tests_dir;
}

fn outputPathFor(name: []const u8) ![]u8 {
    return std.fmt.allocPrint(std.testing.allocator, "{s}/build/output{s}", .{ name, if (@import("builtin").os.tag == .windows) ".exe" else "" });
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

fn argiTestCacheDirForModule(module_dir: []const u8) ![]u8 {
    var hasher = std.hash.Wyhash.init(0);
    hasher.update(module_dir);
    return std.fmt.allocPrint(
        std.testing.allocator,
        "{s}/.argi-cache/tests/{x}",
        .{ compilerRoot(), hasher.final() },
    );
}

fn clean(name: []const u8) !void {
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

fn runChild(argv: []const []const u8) !std.process.RunResult {
    const result = try std.process.run(std.testing.allocator, std.testing.io, .{
        .argv = argv,
        .cwd = .{ .path = compilerRoot() },
    });
    return normalizeRunResult(result);
}

fn runArgiCommand(args: []const []const u8) !std.process.RunResult {
    const argv = try std.testing.allocator.alloc([]const u8, args.len + 1);
    defer std.testing.allocator.free(argv);

    argv[0] = argi_bin;
    for (args, 0..) |arg, idx| {
        argv[idx + 1] = arg;
    }

    return runChild(argv);
}

fn runArgiCommandWithEnv(
    args: []const []const u8,
    env_map: *const std.process.Environ.Map,
) !std.process.RunResult {
    const argv = try std.testing.allocator.alloc([]const u8, args.len + 1);
    defer std.testing.allocator.free(argv);

    argv[0] = argi_bin;
    for (args, 0..) |arg, idx| {
        argv[idx + 1] = arg;
    }

    const result = try std.process.run(std.testing.allocator, std.testing.io, .{
        .argv = argv,
        .cwd = .{ .path = compilerRoot() },
        .environ_map = env_map,
    });
    return normalizeRunResult(result);
}

fn expectArgiBuildSuccess(args: []const []const u8) !void {
    const result = try runArgiCommand(args);
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);

    try expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
}

fn runChildInCwd(argv: []const []const u8, cwd: []const u8) !std.process.RunResult {
    const result = try std.process.run(std.testing.allocator, std.testing.io, .{
        .argv = argv,
        .cwd = .{ .path = cwd },
    });
    return normalizeRunResult(result);
}

fn runChildInCwdWithEnv(
    argv: []const []const u8,
    cwd: []const u8,
    env_map: *const std.process.Environ.Map,
) !std.process.RunResult {
    const result = try std.process.run(std.testing.allocator, std.testing.io, .{
        .argv = argv,
        .cwd = .{ .path = cwd },
        .environ_map = env_map,
    });
    return normalizeRunResult(result);
}

fn normalizeRunResult(result: std.process.RunResult) !std.process.RunResult {
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
fn normalizeDiagnosticPaths(bytes: []u8) void {
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

fn normalizeSourceLocation(bytes: []u8) void {
    if (std.mem.indexOf(u8, bytes, ".rg:")) |path_end| {
        for (bytes[0 .. path_end + 3]) |*byte| if (byte.* == '\\') {
            byte.* = '/';
        };
    }
}

fn repoRootPrefix() ![]u8 {
    const cwd = try std.process.currentPathAlloc(std.testing.io, std.testing.allocator);
    defer std.testing.allocator.free(cwd);
    return std.fs.path.resolve(std.testing.allocator, &.{ cwd, compilerRoot() });
}

fn installedArgiPath() ![]u8 {
    const repo_root = try repoRootPrefix();
    defer std.testing.allocator.free(repo_root);
    return std.fs.path.join(std.testing.allocator, &.{ repo_root, argi_bin });
}

fn tmpDirRootPath(tmp: *const std.testing.TmpDir) ![]u8 {
    const repo_root = try repoRootPrefix();
    defer std.testing.allocator.free(repo_root);
    return std.fs.path.join(std.testing.allocator, &.{ repo_root, ".zig-cache", "tmp", tmp.sub_path[0..] });
}

fn buildResult(name: []const u8) !std.process.RunResult {
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

    if (result.term != .exited or result.term.exited != 0)
        std.debug.print("argi build {s} failed:\n{s}", .{ name, result.stderr });
    try expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
}

fn buildExpectFail(name: []const u8, expected_stderr: []const u8) !void {
    const result = try buildResult(name);
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);

    switch (result.term) {
        .exited => |code| try expect(code != 0),
        else => return error.UnexpectedProcessTermination,
    }

    try expect(std.mem.indexOf(u8, result.stderr, expected_stderr) != null);
}

fn buildExpectFailWithoutNoise(name: []const u8, expected_stderr: []const u8, forbidden_stderr: []const u8) !void {
    const result = try buildResult(name);
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);

    switch (result.term) {
        .exited => |code| try expect(code != 0),
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
        .exited => |code| try expect(code != 0),
        else => return error.UnexpectedProcessTermination,
    }

    try expectEqualStrings(expected_stderr, result.stderr);
    try expect(std.mem.indexOf(u8, result.stdout, "Parse error:") == null);
    try expect(std.mem.indexOf(u8, result.stderr, "Parse error:") == null);
}

fn buildExpectFailWithoutParseNoise(name: []const u8, expected_stderr_fragment: []const u8) !void {
    const result = try buildResult(name);
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);

    switch (result.term) {
        .exited => |code| try expect(code != 0),
        else => return error.UnexpectedProcessTermination,
    }

    try expect(std.mem.indexOf(u8, result.stderr, expected_stderr_fragment) != null);
    try expect(std.mem.indexOf(u8, result.stdout, "Parse error:") == null);
    try expect(std.mem.indexOf(u8, result.stderr, "Parse error:") == null);
}

fn runExpect(name: []const u8, expected_code: u8) !void {
    const output_path = try outputPathFor(name);
    defer std.testing.allocator.free(output_path);

    const result = try runChild(&[_][]const u8{output_path});
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);

    try expectEqual(std.process.Child.Term{ .exited = expected_code }, result.term);
}

fn runExpectFailure(name: []const u8) !void {
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

    try expectEqual(std.process.Child.Term{ .exited = expected_code }, result.term);
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

    try expectEqual(std.process.Child.Term{ .exited = expected_code }, result.term);
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

    try expectEqual(std.process.Child.Term{ .exited = expected_code }, result.term);
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

    try expectEqual(std.process.Child.Term{ .exited = expected_code }, result.term);
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

fn pathInTest(name: []const u8, leaf: []const u8) ![]u8 {
    return std.fmt.allocPrint(std.testing.allocator, "{s}/{s}", .{ name, leaf });
}

fn fileHasSubstantiveContent(root: std.Io.Dir, relative_path: []const u8) !bool {
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

test "feature test harness covers all substantive feature mains" {
    var root = try std.Io.Dir.cwd().openDir(std.testing.io, compilerRoot(), .{ .iterate = true });
    defer root.close(std.testing.io);

    const test_file_text = try root.readFileAlloc(std.testing.io, "tests/test.zig", std.testing.allocator, .limited(1024 * 1024));
    defer std.testing.allocator.free(test_file_text);

    var feature_root = try root.openDir(std.testing.io, "tests/feature_tests", .{ .iterate = true });
    defer feature_root.close(std.testing.io);

    var missing = std.array_list.Managed([]const u8).init(std.testing.allocator);
    defer {
        for (missing.items) |item| std.testing.allocator.free(item);
        missing.deinit();
    }

    var category_iter = feature_root.iterate();
    while (try category_iter.next(std.testing.io)) |category| {
        if (category.kind != .directory) continue;

        const category_path = try std.fmt.allocPrint(std.testing.allocator, "tests/feature_tests/{s}", .{category.name});
        defer std.testing.allocator.free(category_path);

        var category_dir = try root.openDir(std.testing.io, category_path, .{ .iterate = true });
        defer category_dir.close(std.testing.io);

        var case_iter = category_dir.iterate();
        while (try case_iter.next(std.testing.io)) |case_entry| {
            if (case_entry.kind != .directory) continue;

            const case_path = try std.fmt.allocPrint(std.testing.allocator, "{s}/{s}", .{ category_path, case_entry.name });
            defer std.testing.allocator.free(case_path);

            const main_path = try std.fmt.allocPrint(std.testing.allocator, "{s}/main.rg", .{case_path});
            defer std.testing.allocator.free(main_path);

            root.access(std.testing.io, main_path, .{}) catch |err| switch (err) {
                error.FileNotFound => continue,
                else => return err,
            };

            if (!try fileHasSubstantiveContent(root, main_path)) continue;
            if (std.mem.indexOf(u8, test_file_text, case_path) != null) continue;

            try missing.append(try std.testing.allocator.dupe(u8, case_path));
        }
    }

    if (missing.items.len != 0) {
        std.debug.print("missing feature test registrations in tests/test.zig:\n", .{});
        for (missing.items) |item| {
            std.debug.print("  {s}\n", .{item});
        }
        return error.MissingFeatureTestCoverage;
    }
}

test "installed argi resolves core from its installation prefix outside repo" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.createDirPath(std.testing.io, "module");
    try tmp.dir.createDirPath(std.testing.io, "outside");

    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "module/main.rg",
        .data =
        \\main() -> (.status_code: Int32 = 0) := {
        \\}
        \\
        ,
    });

    const repo_root = try repoRootPrefix();
    defer std.testing.allocator.free(repo_root);

    const tmp_root = try std.fs.path.join(std.testing.allocator, &.{ repo_root, ".zig-cache", "tmp", tmp.sub_path[0..] });
    defer std.testing.allocator.free(tmp_root);

    const module_dir = try std.fs.path.join(std.testing.allocator, &.{ tmp_root, "module" });
    defer std.testing.allocator.free(module_dir);

    const outside_dir = try std.fs.path.join(std.testing.allocator, &.{ tmp_root, "outside" });
    defer std.testing.allocator.free(outside_dir);

    const installed_argi = try std.fs.path.join(std.testing.allocator, &.{ repo_root, argi_bin });
    defer std.testing.allocator.free(installed_argi);

    const installed_core = try std.fs.path.join(std.testing.allocator, &.{
        repo_root,
        "zig-out",
        "lib",
        "argi",
        "core",
    });
    defer std.testing.allocator.free(installed_core);

    try std.Io.Dir.cwd().access(std.testing.io, installed_argi, .{});
    try std.Io.Dir.cwd().access(std.testing.io, installed_core, .{});

    var env_map = try std.testing.environ.createMap(std.testing.allocator);
    defer env_map.deinit();

    // This test must verify selfExePath-based sysroot resolution.
    _ = env_map.swapRemove("ARGI_SYSROOT");

    const build_result = try runChildInCwdWithEnv(
        &.{ installed_argi, "build", module_dir },
        outside_dir,
        &env_map,
    );
    defer std.testing.allocator.free(build_result.stdout);
    defer std.testing.allocator.free(build_result.stderr);

    try expectEqual(std.process.Child.Term{ .exited = 0 }, build_result.term);

    const output_path = try std.fs.path.join(std.testing.allocator, &.{ module_dir, "build", "output" });
    defer std.testing.allocator.free(output_path);

    try std.Io.Dir.cwd().access(std.testing.io, output_path, .{});

    const run_result = try runChildInCwd(&.{output_path}, outside_dir);
    defer std.testing.allocator.free(run_result.stdout);
    defer std.testing.allocator.free(run_result.stderr);

    try expectEqual(std.process.Child.Term{ .exited = 0 }, run_result.term);
}

fn copyInstalledTree(source: []const u8, destination: std.Io.Dir, prefix: []const u8) !void {
    var directory = try std.Io.Dir.cwd().openDir(std.testing.io, source, .{ .iterate = true });
    defer directory.close(std.testing.io);
    var walker = try directory.walk(std.testing.allocator);
    defer walker.deinit();
    while (try walker.next(std.testing.io)) |entry| {
        if (entry.kind != .file) continue;
        const target = try std.fs.path.join(std.testing.allocator, &.{ prefix, entry.path });
        defer std.testing.allocator.free(target);
        try directory.copyFile(entry.path, destination, target, std.testing.io, .{ .make_path = true });
    }
}

test "installed more imports survive relocation outside the checkout" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const repo = try repoRootPrefix();
    defer std.testing.allocator.free(repo);
    const root = try tmpDirRootPath(&tmp);
    defer std.testing.allocator.free(root);
    for ([_][]const u8{ "bin", "lib/argi/core", "lib/argi/more" }) |part| {
        const source = try std.fs.path.join(std.testing.allocator, &.{ repo, "zig-out", part });
        defer std.testing.allocator.free(source);
        const destination = try std.fs.path.join(std.testing.allocator, &.{ "package", part });
        defer std.testing.allocator.free(destination);
        try copyInstalledTree(source, tmp.dir, destination);
    }
    try tmp.dir.createDirPath(std.testing.io, "outside");
    const executable = try std.fs.path.join(std.testing.allocator, &.{ root, "package", "bin", std.fs.path.basename(argi_bin) });
    defer std.testing.allocator.free(executable);
    const fixture = try std.fs.path.join(std.testing.allocator, &.{ repo, "tests/feature_tests/modules/09_import_more_library" });
    defer std.testing.allocator.free(fixture);
    const outside = try std.fs.path.join(std.testing.allocator, &.{ root, "outside" });
    defer std.testing.allocator.free(outside);
    var environment = try std.testing.environ.createMap(std.testing.allocator);
    defer environment.deinit();
    _ = environment.swapRemove("ARGI_SYSROOT");
    const built = try runChildInCwdWithEnv(&.{ executable, "build", fixture, "--output", "app", "--no-cache" }, outside, &environment);
    defer std.testing.allocator.free(built.stdout);
    defer std.testing.allocator.free(built.stderr);
    if (built.term != .exited or built.term.exited != 0) std.debug.print("{s}", .{built.stderr});
    try expectEqual(std.process.Child.Term{ .exited = 0 }, built.term);
    const app = try std.fs.path.join(std.testing.allocator, &.{ outside, if (@import("builtin").os.tag == .windows) "app.exe" else "app" });
    defer std.testing.allocator.free(app);
    const executed = try runChildInCwd(&.{app}, outside);
    defer std.testing.allocator.free(executed.stdout);
    defer std.testing.allocator.free(executed.stderr);
    try expectEqual(std.process.Child.Term{ .exited = 0 }, executed.term);
}

test "installed argi test resolves core from its installation prefix outside repo" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.createDirPath(std.testing.io, "module");
    try tmp.dir.createDirPath(std.testing.io, "outside");

    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "module/main.rg",
        .data =
        \\test installed_prefix(.system: System) -> !() := {
        \\    testing.expect(.condition = true)!
        \\}
        \\
        ,
    });

    const tmp_root = try tmpDirRootPath(&tmp);
    defer std.testing.allocator.free(tmp_root);

    const module_dir = try std.fs.path.join(std.testing.allocator, &.{ tmp_root, "module" });
    defer std.testing.allocator.free(module_dir);

    const outside_dir = try std.fs.path.join(std.testing.allocator, &.{ tmp_root, "outside" });
    defer std.testing.allocator.free(outside_dir);

    const installed_argi = try installedArgiPath();
    defer std.testing.allocator.free(installed_argi);

    var env_map = try std.testing.environ.createMap(std.testing.allocator);
    defer env_map.deinit();

    // This test must verify selfExePath-based sysroot resolution for argi test.
    _ = env_map.swapRemove("ARGI_SYSROOT");

    const result = try runChildInCwdWithEnv(
        &.{ installed_argi, "test", module_dir },
        outside_dir,
        &env_map,
    );
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);

    try expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try expect(std.mem.indexOf(u8, result.stderr, "PASS installed_prefix\n") != null);
}

test "argi init creates executable package" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_root = try tmpDirRootPath(&tmp);
    defer std.testing.allocator.free(tmp_root);
    const installed_argi = try installedArgiPath();
    defer std.testing.allocator.free(installed_argi);

    const result = try runChildInCwd(&.{ installed_argi, "init", "hello" }, tmp_root);
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);
    try expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);

    const manifest_path = try std.fs.path.join(std.testing.allocator, &.{ tmp_root, "hello", "argi.toml" });
    defer std.testing.allocator.free(manifest_path);
    const text = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, manifest_path, std.testing.allocator, .limited(1024 * 1024));
    defer std.testing.allocator.free(text);

    const source_path = try std.fs.path.join(std.testing.allocator, &.{ tmp_root, "hello", "source", "hello", "main.rg" });
    defer std.testing.allocator.free(source_path);
    try std.Io.Dir.cwd().access(std.testing.io, source_path, .{});
    const source_text = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, source_path, std.testing.allocator, .limited(1024 * 1024));
    defer std.testing.allocator.free(source_text);

    try expect(std.mem.indexOf(u8, text, "kind = ") == null);
    try expect(std.mem.indexOf(u8, text, "[executables.hello]\n") != null);
    try expect(std.mem.indexOf(u8, text, "path = \"source/hello\"\n") != null);
    try expect(std.mem.indexOf(u8, text, "[run]\n") != null);
    try expect(std.mem.indexOf(u8, text, "default = \"hello\"\n") != null);
    try expectEqualStrings(
        "main(.system: System) -> (.status_code: Int32 = 0) := {\n" ++
            "    assume ffi ::= system.ffi\n" ++
            "    assume allocator ::= $&GeneralPurposeAllocator(system.page_allocator)\n" ++
            "    assume error_tracer ::= FixedSizeErrorTracer(\n" ++
            "        .buffer = view($&zeroed#(.t: [4096]UInt8)()),\n" ++
            "    ) | to_virtual#(ErrorTracer)($&_) | $&_\n" ++
            "    assume writer ::= $&BufferedWriter#(.base_type: File)(\n" ++
            "        .base = $&system.terminal&.stdout,\n" ++
            "        .buffer = view($&zeroed#(.t: [4096]UInt8)()),\n" ++
            "    )\n" ++
            "    assume reader ::= $&system.terminal&.stdin\n" ++
            "}\n",
        source_text,
    );
}

test "argi init lib creates package without executables" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_root = try tmpDirRootPath(&tmp);
    defer std.testing.allocator.free(tmp_root);
    const installed_argi = try installedArgiPath();
    defer std.testing.allocator.free(installed_argi);

    const result = try runChildInCwd(&.{ installed_argi, "init", "--lib", "math_utils" }, tmp_root);
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);
    try expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);

    const manifest_path = try std.fs.path.join(std.testing.allocator, &.{ tmp_root, "math_utils", "argi.toml" });
    defer std.testing.allocator.free(manifest_path);
    const text = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, manifest_path, std.testing.allocator, .limited(1024 * 1024));
    defer std.testing.allocator.free(text);

    try expect(std.mem.indexOf(u8, text, "kind = ") == null);
    try expect(std.mem.indexOf(u8, text, "[executables.") == null);
    try expect(std.mem.indexOf(u8, text, "[run]") == null);
}

test "argi build and run executable package from cwd and entry module" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_root = try tmpDirRootPath(&tmp);
    defer std.testing.allocator.free(tmp_root);
    const installed_argi = try installedArgiPath();
    defer std.testing.allocator.free(installed_argi);

    const init_result = try runChildInCwd(&.{ installed_argi, "init", "hello" }, tmp_root);
    defer std.testing.allocator.free(init_result.stdout);
    defer std.testing.allocator.free(init_result.stderr);
    try expectEqual(std.process.Child.Term{ .exited = 0 }, init_result.term);

    const module_root = try std.fs.path.join(std.testing.allocator, &.{ tmp_root, "hello" });
    defer std.testing.allocator.free(module_root);

    const build_result = try runChildInCwd(&.{ installed_argi, "build" }, module_root);
    defer std.testing.allocator.free(build_result.stdout);
    defer std.testing.allocator.free(build_result.stderr);
    try expectEqual(std.process.Child.Term{ .exited = 0 }, build_result.term);

    const output_path = try std.fs.path.join(std.testing.allocator, &.{ module_root, "build", "debug", "hello" });
    defer std.testing.allocator.free(output_path);
    try std.Io.Dir.cwd().access(std.testing.io, output_path, .{});

    const binary_result = try runChildInCwd(&.{output_path}, module_root);
    defer std.testing.allocator.free(binary_result.stdout);
    defer std.testing.allocator.free(binary_result.stderr);
    try expectEqual(std.process.Child.Term{ .exited = 0 }, binary_result.term);

    const run_result = try runChildInCwd(&.{ installed_argi, "run" }, module_root);
    defer std.testing.allocator.free(run_result.stdout);
    defer std.testing.allocator.free(run_result.stderr);
    try expectEqual(std.process.Child.Term{ .exited = 0 }, run_result.term);

    const entry_dir = try std.fs.path.join(std.testing.allocator, &.{ module_root, "source", "hello" });
    defer std.testing.allocator.free(entry_dir);
    const entry_build = try runChildInCwd(&.{ installed_argi, "build", entry_dir }, module_root);
    defer std.testing.allocator.free(entry_build.stdout);
    defer std.testing.allocator.free(entry_build.stderr);
    try expectEqual(std.process.Child.Term{ .exited = 0 }, entry_build.term);

    const file_build = try runChildInCwd(&.{ installed_argi, "build", "main.rg" }, entry_dir);
    defer std.testing.allocator.free(file_build.stdout);
    defer std.testing.allocator.free(file_build.stderr);
    try expectEqual(std.process.Child.Term{ .exited = 0 }, file_build.term);

    const entry_run = try runChildInCwd(&.{ installed_argi, "run" }, entry_dir);
    defer std.testing.allocator.free(entry_run.stdout);
    defer std.testing.allocator.free(entry_run.stderr);
    try expectEqual(std.process.Child.Term{ .exited = 0 }, entry_run.term);
    const nested_build = try std.fs.path.join(std.testing.allocator, &.{ entry_dir, "build" });
    defer std.testing.allocator.free(nested_build);
    try std.testing.expectError(error.FileNotFound, std.Io.Dir.cwd().access(std.testing.io, nested_build, .{}));
}

test "argi init executable package can print from generated main" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_root = try tmpDirRootPath(&tmp);
    defer std.testing.allocator.free(tmp_root);
    const installed_argi = try installedArgiPath();
    defer std.testing.allocator.free(installed_argi);

    const init_result = try runChildInCwd(&.{ installed_argi, "init", "hello" }, tmp_root);
    defer std.testing.allocator.free(init_result.stdout);
    defer std.testing.allocator.free(init_result.stderr);
    try expectEqual(std.process.Child.Term{ .exited = 0 }, init_result.term);

    const module_root = try std.fs.path.join(std.testing.allocator, &.{ tmp_root, "hello" });
    defer std.testing.allocator.free(module_root);

    const source_path = try std.fs.path.join(std.testing.allocator, &.{ module_root, "source", "hello", "main.rg" });
    defer std.testing.allocator.free(source_path);

    const generated = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, source_path, std.testing.allocator, .limited(1024 * 1024));
    defer std.testing.allocator.free(generated);
    const closing_brace = std.mem.lastIndexOfScalar(u8, generated, '}') orelse return error.TestUnexpectedResult;
    const runnable = try std.fmt.allocPrint(std.testing.allocator, "{s}    print(\"Hello, World!\")\n{s}", .{ generated[0..closing_brace], generated[closing_brace..] });
    defer std.testing.allocator.free(runnable);
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = source_path, .data = runnable });

    const build_result = try runChildInCwd(&.{ installed_argi, "build" }, module_root);
    defer std.testing.allocator.free(build_result.stdout);
    defer std.testing.allocator.free(build_result.stderr);
    try expectEqual(std.process.Child.Term{ .exited = 0 }, build_result.term);

    const output_path = try std.fs.path.join(std.testing.allocator, &.{ module_root, "build", "debug", "hello" });
    defer std.testing.allocator.free(output_path);

    const run_result = try runChildInCwd(&.{output_path}, module_root);
    defer std.testing.allocator.free(run_result.stdout);
    defer std.testing.allocator.free(run_result.stderr);
    try expectEqual(std.process.Child.Term{ .exited = 0 }, run_result.term);
    try expectEqualStrings("Hello, World!\n", run_result.stdout);
}

test "argi build package supports explicit dot and executable flag" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_root = try tmpDirRootPath(&tmp);
    defer std.testing.allocator.free(tmp_root);
    const installed_argi = try installedArgiPath();
    defer std.testing.allocator.free(installed_argi);

    const init_result = try runChildInCwd(&.{ installed_argi, "init", "hello" }, tmp_root);
    defer std.testing.allocator.free(init_result.stdout);
    defer std.testing.allocator.free(init_result.stderr);
    try expectEqual(std.process.Child.Term{ .exited = 0 }, init_result.term);

    const module_root = try std.fs.path.join(std.testing.allocator, &.{ tmp_root, "hello" });
    defer std.testing.allocator.free(module_root);

    const dot_result = try runChildInCwd(&.{ installed_argi, "build", "." }, module_root);
    defer std.testing.allocator.free(dot_result.stdout);
    defer std.testing.allocator.free(dot_result.stderr);
    try expectEqual(std.process.Child.Term{ .exited = 0 }, dot_result.term);

    const entry_result = try runChildInCwd(&.{ installed_argi, "build", "--exec", "hello" }, module_root);
    defer std.testing.allocator.free(entry_result.stdout);
    defer std.testing.allocator.free(entry_result.stderr);
    try expectEqual(std.process.Child.Term{ .exited = 0 }, entry_result.term);
}

test "argi build package rejects missing executables" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_root = try tmpDirRootPath(&tmp);
    defer std.testing.allocator.free(tmp_root);
    const installed_argi = try installedArgiPath();
    defer std.testing.allocator.free(installed_argi);

    try tmp.dir.createDirPath(std.testing.io, "math_utils");
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "math_utils/argi.toml",
        .data =
        \\name = "math_utils"
        \\version = "0.0.0"
        \\minimum_argi_version = "0.1.0"
        \\
        ,
    });

    const module_root = try std.fs.path.join(std.testing.allocator, &.{ tmp_root, "math_utils" });
    defer std.testing.allocator.free(module_root);

    const result = try runChildInCwd(&.{ installed_argi, "build" }, module_root);
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);
    try expectEqual(std.process.Child.Term{ .exited = 1 }, result.term);
    try expect(std.mem.indexOf(u8, result.stderr, "package has no executables to build") != null);
}

test "argi build package builds all executables" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_root = try tmpDirRootPath(&tmp);
    defer std.testing.allocator.free(tmp_root);
    const installed_argi = try installedArgiPath();
    defer std.testing.allocator.free(installed_argi);

    try tmp.dir.createDirPath(std.testing.io, "app/source/entrypoints/cli");
    try tmp.dir.createDirPath(std.testing.io, "app/source/entrypoints/server");
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "app/argi.toml",
        .data =
        \\name = "app"
        \\version = "0.0.0"
        \\minimum_argi_version = "0.1.0"
        \\
        \\[executables.cli]
        \\path = "source/entrypoints/cli"
        \\
        \\[executables.server]
        \\path = "source/entrypoints/server"
        \\
        ,
    });
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "app/source/entrypoints/cli/main.rg",
        .data =
        \\main() -> (.status_code: Int32 = 0) := {
        \\}
        \\
        ,
    });
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "app/source/entrypoints/server/main.rg",
        .data =
        \\main() -> (.status_code: Int32 = 0) := {
        \\}
        \\
        ,
    });

    const module_root = try std.fs.path.join(std.testing.allocator, &.{ tmp_root, "app" });
    defer std.testing.allocator.free(module_root);

    const result = try runChildInCwd(&.{ installed_argi, "build" }, module_root);
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);
    try expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);

    const cli_output = try std.fs.path.join(std.testing.allocator, &.{ module_root, "build", "debug", "cli" });
    defer std.testing.allocator.free(cli_output);
    const server_output = try std.fs.path.join(std.testing.allocator, &.{ module_root, "build", "debug", "server" });
    defer std.testing.allocator.free(server_output);
    try std.Io.Dir.cwd().access(std.testing.io, cli_output, .{});
    try std.Io.Dir.cwd().access(std.testing.io, server_output, .{});
}

test "argi run package uses configured default and selected executable" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_root = try tmpDirRootPath(&tmp);
    defer std.testing.allocator.free(tmp_root);
    const installed_argi = try installedArgiPath();
    defer std.testing.allocator.free(installed_argi);

    try tmp.dir.createDirPath(std.testing.io, "app/source/entrypoints/cli");
    try tmp.dir.createDirPath(std.testing.io, "app/source/entrypoints/server");
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "app/argi.toml",
        .data =
        \\name = "app"
        \\version = "0.0.0"
        \\minimum_argi_version = "0.1.0"
        \\
        \\[executables.cli]
        \\path = "source/entrypoints/cli"
        \\
        \\[executables.server]
        \\path = "source/entrypoints/server"
        \\
        \\[run]
        \\default = "cli"
        \\
        ,
    });
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "app/source/entrypoints/cli/main.rg",
        .data =
        \\main() -> (.status_code: Int32 = 7) := {
        \\}
        \\
        ,
    });
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "app/source/entrypoints/server/main.rg",
        .data =
        \\main() -> (.status_code: Int32 = 11) := {
        \\}
        \\
        ,
    });

    const module_root = try std.fs.path.join(std.testing.allocator, &.{ tmp_root, "app" });
    defer std.testing.allocator.free(module_root);

    const default_result = try runChildInCwd(&.{ installed_argi, "run" }, module_root);
    defer std.testing.allocator.free(default_result.stdout);
    defer std.testing.allocator.free(default_result.stderr);
    try expectEqual(std.process.Child.Term{ .exited = 7 }, default_result.term);

    const server_result = try runChildInCwd(&.{ installed_argi, "run", "server" }, module_root);
    defer std.testing.allocator.free(server_result.stdout);
    defer std.testing.allocator.free(server_result.stderr);
    try expectEqual(std.process.Child.Term{ .exited = 11 }, server_result.term);
}

test "argi run package uses single executable without run default" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_root = try tmpDirRootPath(&tmp);
    defer std.testing.allocator.free(tmp_root);
    const installed_argi = try installedArgiPath();
    defer std.testing.allocator.free(installed_argi);

    try tmp.dir.createDirPath(std.testing.io, "app/source/entrypoints/cli");
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "app/argi.toml",
        .data =
        \\name = "app"
        \\version = "0.0.0"
        \\minimum_argi_version = "0.1.0"
        \\
        \\[executables.cli]
        \\path = "source/entrypoints/cli"
        \\
        ,
    });
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "app/source/entrypoints/cli/main.rg",
        .data =
        \\main() -> (.status_code: Int32 = 9) := {
        \\}
        \\
        ,
    });

    const module_root = try std.fs.path.join(std.testing.allocator, &.{ tmp_root, "app" });
    defer std.testing.allocator.free(module_root);

    const result = try runChildInCwd(&.{ installed_argi, "run" }, module_root);
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);
    try expectEqual(std.process.Child.Term{ .exited = 9 }, result.term);
}

test "argi run package rejects ambiguous default" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_root = try tmpDirRootPath(&tmp);
    defer std.testing.allocator.free(tmp_root);
    const installed_argi = try installedArgiPath();
    defer std.testing.allocator.free(installed_argi);

    try tmp.dir.createDirPath(std.testing.io, "app/source/entrypoints/cli");
    try tmp.dir.createDirPath(std.testing.io, "app/source/entrypoints/server");
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "app/argi.toml",
        .data =
        \\name = "app"
        \\version = "0.0.0"
        \\minimum_argi_version = "0.1.0"
        \\
        \\[executables.cli]
        \\path = "source/entrypoints/cli"
        \\
        \\[executables.server]
        \\path = "source/entrypoints/server"
        \\
        ,
    });

    const module_root = try std.fs.path.join(std.testing.allocator, &.{ tmp_root, "app" });
    defer std.testing.allocator.free(module_root);

    const result = try runChildInCwd(&.{ installed_argi, "run" }, module_root);
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);
    try expectEqual(std.process.Child.Term{ .exited = 1 }, result.term);
    try expect(std.mem.indexOf(u8, result.stderr, "multiple executables and no default run target") != null);
    try expect(std.mem.indexOf(u8, result.stderr, "argi run cli") != null);
}

test "argi run package rejects unknown executable" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_root = try tmpDirRootPath(&tmp);
    defer std.testing.allocator.free(tmp_root);
    const installed_argi = try installedArgiPath();
    defer std.testing.allocator.free(installed_argi);

    const init_result = try runChildInCwd(&.{ installed_argi, "init", "hello" }, tmp_root);
    defer std.testing.allocator.free(init_result.stdout);
    defer std.testing.allocator.free(init_result.stderr);
    try expectEqual(std.process.Child.Term{ .exited = 0 }, init_result.term);

    const module_root = try std.fs.path.join(std.testing.allocator, &.{ tmp_root, "hello" });
    defer std.testing.allocator.free(module_root);

    const result = try runChildInCwd(&.{ installed_argi, "run", "worker" }, module_root);
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);
    try expectEqual(std.process.Child.Term{ .exited = 1 }, result.term);
    try expect(std.mem.indexOf(u8, result.stderr, "unknown executable 'worker'") != null);
    try expect(std.mem.indexOf(u8, result.stderr, "  - hello") != null);
}

test "argi build package rejects missing executable path" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_root = try tmpDirRootPath(&tmp);
    defer std.testing.allocator.free(tmp_root);
    const installed_argi = try installedArgiPath();
    defer std.testing.allocator.free(installed_argi);

    try tmp.dir.createDirPath(std.testing.io, "app");
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "app/argi.toml",
        .data =
        \\name = "app"
        \\version = "0.0.0"
        \\minimum_argi_version = "0.1.0"
        \\
        \\[executables.cli]
        \\path = "source/entrypoints/cli"
        \\
        ,
    });

    const module_root = try std.fs.path.join(std.testing.allocator, &.{ tmp_root, "app" });
    defer std.testing.allocator.free(module_root);

    const result = try runChildInCwd(&.{ installed_argi, "build" }, module_root);
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);
    try expectEqual(std.process.Child.Term{ .exited = 1 }, result.term);
    try expect(std.mem.indexOf(u8, result.stderr, "executable 'cli' points to missing path") != null);
    try expect(std.mem.indexOf(u8, result.stderr, "source/entrypoints/cli") != null);
}

test "build publishes artifacts outside the staging filesystem" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const base = if (@import("builtin").os.tag == .linux) "/dev/shm" else "/tmp";
    var parent = std.Io.Dir.openDirAbsolute(io, base, .{}) catch return error.SkipZigTest;
    defer parent.close(io);
    const name = try std.fmt.allocPrint(allocator, "argi-artifacts-{s}", .{tmp.sub_path});
    defer allocator.free(name);
    try parent.createDir(io, name, .default_dir);
    defer parent.deleteTree(io, name) catch {};
    const ir_path = try std.fs.path.join(allocator, &.{ base, name, "output.ll" });
    defer allocator.free(ir_path);
    const obj_path = try std.fs.path.join(allocator, &.{ base, name, "output.o" });
    defer allocator.free(obj_path);
    const test_path = "tests/feature_tests/basics/01_minimal_main";
    for (0..2) |_| {
        try expectArgiBuildSuccess(&.{ "build", test_path, "--emit-llvm", ir_path, "--emit-obj", obj_path });
        const ir = try std.Io.Dir.cwd().readFileAlloc(io, ir_path, allocator, .limited(1024 * 1024));
        defer allocator.free(ir);
        try expect(std.mem.indexOf(u8, ir, "define i32 @main") != null);
        const object = try std.Io.Dir.cwd().readFileAlloc(io, obj_path, allocator, .limited(1024 * 1024));
        defer allocator.free(object);
        try expect(object.len != 0);
    }
}

test "build persists module snapshots across processes and dependency edits" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmpDirRootPath(&tmp);
    defer allocator.free(root);
    const argi = try installedArgiPath();
    defer allocator.free(argi);
    try tmp.dir.createDirPath(io, "app");
    try tmp.dir.createDirPath(io, "dep");
    try tmp.dir.writeFile(io, .{
        .sub_path = "app/main.rg",
        .data = "dep := import(\"../dep\")\nmain() -> (.status_code: Int32) := { status_code = dep.answer().result }\n",
    });
    const source = "answer() -> (.result: Int32) := { result = 7 }\n";
    try tmp.dir.writeFile(io, .{ .sub_path = "dep/answer.rg", .data = source });
    for (0..4) |revision| {
        if (revision == 1) {
            try tmp.dir.writeFile(io, .{ .sub_path = "dep/answer.rg", .data = "answer() -> (.result: Int32) := { result = 9 }\n" });
        } else if (revision == 2) {
            try tmp.dir.writeFile(io, .{ .sub_path = "dep/extra.rg", .data = "extra() -> (.result: Int32) := { result = 11 }\n" });
        } else if (revision == 3) {
            try tmp.dir.deleteFile(io, "dep/extra.rg");
            try tmp.dir.rename("dep/answer.rg", tmp.dir, "dep/renamed.rg", io);
        }
        for (0..3) |mode| {
            const args: []const []const u8 = if (mode == 2)
                &.{ argi, "build", "app", "--no-cache", "--stats", "--emit-llvm", "clean.ll" }
            else
                &.{ argi, "build", "app", "--stats", "--emit-llvm", "cached.ll" };
            const result = try runChildInCwd(args, root);
            defer allocator.free(result.stdout);
            defer allocator.free(result.stderr);
            try expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
            if (mode == 1) {
                try expect(std.mem.indexOf(u8, result.stderr, "cache misses:        0") != null);
                try expect(std.mem.indexOf(u8, result.stderr, "persistent hits:     0\n") == null);
                try expect(std.mem.indexOf(u8, result.stderr, "rejected snapshots:  0") != null);
            }
        }
        const cached = try tmp.dir.readFileAlloc(io, "cached.ll", allocator, .limited(1024 * 1024));
        defer allocator.free(cached);
        const clean_ir = try tmp.dir.readFileAlloc(io, "clean.ll", allocator, .limited(1024 * 1024));
        defer allocator.free(clean_ir);
        try expectEqualStrings(clean_ir, cached);
    }
    try tmp.dir.writeFile(io, .{ .sub_path = "dep/renamed.rg", .data = "answer(\n" });
    const broken = try runChildInCwd(&.{ argi, "build", "app" }, root);
    defer allocator.free(broken.stdout);
    defer allocator.free(broken.stderr);
    try expectEqual(std.process.Child.Term{ .exited = 1 }, broken.term);
    try tmp.dir.writeFile(io, .{ .sub_path = "dep/renamed.rg", .data = source });
    const recovered = try runChildInCwd(&.{ argi, "build", "app" }, root);
    defer allocator.free(recovered.stdout);
    defer allocator.free(recovered.stderr);
    try expectEqual(std.process.Child.Term{ .exited = 0 }, recovered.term);
    const output = try std.fs.path.join(allocator, &.{ root, "app", "build", "output" });
    defer allocator.free(output);
    const executed = try runChildInCwd(&.{output}, root);
    defer allocator.free(executed.stdout);
    defer allocator.free(executed.stderr);
    try expectEqual(std.process.Child.Term{ .exited = 7 }, executed.term);
}

test "build overwrites existing output binary" {
    const test_path = "tests/feature_tests/basics/01_minimal_main";
    try clean(test_path);
    try expectArgiBuildSuccess(&.{ "build", test_path });
    try expectArgiBuildSuccess(&.{ "build", test_path });
}

test "build overwrites existing emitted llvm" {
    const test_path = "tests/feature_tests/basics/01_minimal_main";
    const ir_path = try irPathFor(test_path);
    defer std.testing.allocator.free(ir_path);

    try clean(test_path);
    try expectArgiBuildSuccess(&.{ "build", test_path, "--emit-llvm", ir_path });
    try expectArgiBuildSuccess(&.{ "build", test_path, "--emit-llvm", ir_path });
}

test "build overwrites existing emitted object" {
    const test_path = "tests/feature_tests/basics/01_minimal_main";
    const obj_path = try objPathFor(test_path);
    defer std.testing.allocator.free(obj_path);

    try clean(test_path);
    try expectArgiBuildSuccess(&.{ "build", test_path, "--emit-obj", obj_path });
    try expectArgiBuildSuccess(&.{ "build", test_path, "--emit-obj", obj_path });
}

test "build overwrites existing just emitted object" {
    const test_path = "tests/feature_tests/basics/01_minimal_main";
    const obj_path = try objPathFor(test_path);
    defer std.testing.allocator.free(obj_path);

    try clean(test_path);
    try expectArgiBuildSuccess(&.{ "build", test_path, "--just-emit-obj", obj_path });
    try expectArgiBuildSuccess(&.{ "build", test_path, "--just-emit-obj", obj_path });
}

test "feature_tests/basics/01_minimal_main" {
    const test_path = "tests/feature_tests/basics/01_minimal_main";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "usecase_tests/01_cat_cli" {
    const test_path = "tests/usecase_tests/01_cat_cli";
    const expected_help = "usage: <program> <file> [file...]\nConcatenate files to standard output.\n  -h, --help  Show this help.\n";
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
    try runExpectStdoutWithArgs(
        test_path,
        &[_][]const u8{"-h"},
        0,
        expected_help,
    );
    try runExpectStdoutWithArgs(
        test_path,
        &[_][]const u8{"--help"},
        0,
        expected_help,
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
    try buildExpectFailExact("tests/feature_tests/basics/09X_integer_literal_overflow",
        \\tests/feature_tests/basics/09X_integer_literal_overflow/main.rg:2:21: error: integer literal 300 does not fit in 'UInt8' (max 255)
        \\      value : UInt8 = 300
        \\                      ^
        \\
    );
}

test "feature_tests/basics/10X_signed_integer_literal_overflow" {
    try buildExpectFailExact("tests/feature_tests/basics/10X_signed_integer_literal_overflow",
        \\tests/feature_tests/basics/10X_signed_integer_literal_overflow/main.rg:2:20: error: integer literal 128 does not fit in 'Int8' (min -128, max 127)
        \\      value : Int8 = 128
        \\                     ^
        \\
    );
}

test "feature_tests/basics/11X_negative_integer_literal_overflow" {
    try buildExpectFailExact("tests/feature_tests/basics/11X_negative_integer_literal_overflow",
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
    try buildExpectFailExact("tests/feature_tests/functions/05X_pipe_requires_parentheses",
        \\tests/feature_tests/functions/05X_pipe_requires_parentheses/main.rg:6:22: error: pipe right-hand side must use at least one argument placeholder
        \\      status_code = 41 | add_one
        \\                       ^
        \\
    );
}

test "feature_tests/functions/06X_pipe_requires_placeholder" {
    try buildExpectFailExact("tests/feature_tests/functions/06X_pipe_requires_placeholder",
        \\tests/feature_tests/functions/06X_pipe_requires_placeholder/main.rg:6:22: error: pipe right-hand side must use at least one argument placeholder
        \\      status_code = 41 | add_one(41)
        \\                       ^
        \\
    );
}

test "feature_tests/functions/07_pipe_expression_placeholder" {
    const path = "tests/feature_tests/functions/07_pipe_expression_placeholder";
    try expectSuccessfulBuild(path);
    try runExpect(path, 42);
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
    try buildExpectFailExact("tests/feature_tests/functions/14X_positional_after_named_call",
        \\tests/feature_tests/functions/14X_positional_after_named_call/main.rg:6:40: error: positional collection items must appear before named items
        \\      status_code = subtract(.left = 44, 2).diff
        \\                                         ^
        \\
    );
}

test "parser errors do not print parse error noise" {
    try buildExpectFailWithoutParseNoise(
        "tests/feature_tests/functions/14X_positional_after_named_call",
        "positional collection items must appear before named items",
    );
}

test "feature_tests/functions/15_output_default_implicit_return" {
    const test_path = "tests/feature_tests/functions/15_output_default_implicit_return";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 42);
}

test "feature_tests/functions/16X_function_signature_requires_explicit_types" {
    try buildExpectFailExact("tests/feature_tests/functions/16X_function_signature_requires_explicit_types",
        \\tests/feature_tests/functions/16X_function_signature_requires_explicit_types/main.rg:1:30: error: function output field '.result' requires an explicit type
        \\  identity(.value: Int32) -> (.result) := {
        \\                               ^
        \\
    );
}

test "feature_tests/functions/17_pipe_builtin_is_positional" {
    const test_path = "tests/feature_tests/functions/17_pipe_builtin_is_positional";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/functions/18_choice_variant_equality" {
    const test_path = "tests/feature_tests/functions/18_choice_variant_equality";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
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
    try buildExpectFailExact("tests/feature_tests/pointers/03X_assign_through_readonly_pointer",
        \\tests/feature_tests/pointers/03X_assign_through_readonly_pointer/main.rg:5:11: error: cannot assign through pointer '&Int32' because it is read-only; use '$&' when acquiring it
        \\      reader& = 1
        \\            ^
        \\
    );
}

test "feature_tests/pointers/04X_read-write_pointer_to_constant" {
    try buildExpectFailExact("tests/feature_tests/pointers/04X_read-write_pointer_to_constant",
        \\tests/feature_tests/pointers/04X_read-write_pointer_to_constant/main.rg:4:32: error: binding 'value' is immutable; declare it with '::' or use '&value'
        \\      mutable_view : $&Int32 = $&value
        \\                                 ^
        \\
    );
}

test "feature_tests/pointers/05X_pass_readonly_pointer_to_mutable_param" {
    try buildExpectFailExact("tests/feature_tests/pointers/05X_pass_readonly_pointer_to_mutable_param",
        \\tests/feature_tests/pointers/05X_pass_readonly_pointer_to_mutable_param/main.rg:9:14: error: no overload of 'increment' accepts arguments (.ptr: &Int32). Available signatures:
        \\  - increment (.ptr: $&Int32) -> ()
        \\      increment(.ptr=reader)
        \\               ^
        \\
    );
}

test "feature_tests/pointers/06_explicit_pointer_casts" {
    try expectSuccessfulBuild("tests/feature_tests/pointers/06_explicit_pointer_casts");
}

test "feature_tests/pointers/07X_pointer_arithmetic_requires_cast" {
    try buildExpectFailExact("tests/feature_tests/pointers/07X_pointer_arithmetic_requires_cast",
        \\tests/feature_tests/pointers/07X_pointer_arithmetic_requires_cast/main.rg:4:14: error: pointer arithmetic is not allowed; cast explicitly to an integer, perform the arithmetic, and cast back
        \\      _addr := ptr + 1
        \\               ^
        \\
    );
}

test "feature_tests/pointers/08X_array_index_requires_uint_native" {
    try buildExpectFailExact("tests/feature_tests/pointers/08X_array_index_requires_uint_native",
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
    try buildExpectFailExact("tests/feature_tests/basics/17X_extern_call_requires_exact_argument_types",
        \\tests/feature_tests/basics/17X_extern_call_requires_exact_argument_types/main.rg:4:12: error: no overload of 'putchar' accepts arguments (.character: UInt16). Available signatures:
        \\  - putchar (.character: UInt8, .ffi: $&ForeignFunctionInterface) -> ()
        \\      putchar(.character = value)
        \\             ^
        \\
    );
}

test "feature_tests/basics/18X_constant_reassignment" {
    try buildExpectFailExact("tests/feature_tests/basics/18X_constant_reassignment",
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
    try buildExpectFailExact("tests/feature_tests/polymorphism/09X_abstract_missing_requirement",
        \\tests/feature_tests/polymorphism/09X_abstract_missing_requirement/main.rg:9:1: error: type does not implement abstract 'Animal':
        \\  missing function: speak (.who: Dog)
        \\  Dog implements Animal
        \\  ^
        \\
    );
}

test "feature_tests/polymorphism/10X_abstract_wrong_signature" {
    try buildExpectFailExact("tests/feature_tests/polymorphism/10X_abstract_wrong_signature",
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
    try buildExpectFailExact("tests/feature_tests/polymorphism/12X_abstract_instantiation_missing_default",
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
    try buildExpectFailExact("tests/feature_tests/polymorphism/16X_abstract_self_output_wrong",
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
    try buildExpectFailExact("tests/feature_tests/polymorphism/13X_abstract_function_input_requires_implementation",
        \\tests/feature_tests/polymorphism/13X_abstract_function_input_requires_implementation/main.rg:8:28: error: type 'Int32' does not implement abstract 'ExampleAbstract' required by parameter '.value' of 'use_value'
        \\      status_code = use_value(.value = 7)
        \\                             ^
        \\
    );
}

test "feature_tests/polymorphism/14X_abstract_function_output_requires_default" {
    try buildExpectFailExact("tests/feature_tests/polymorphism/14X_abstract_function_output_requires_default",
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
    try buildExpectFailExact("tests/feature_tests/ownership/05X_noncopyable_assignment",
        \\tests/feature_tests/ownership/05X_noncopyable_assignment/main.rg:11:15: error: type 'Resource' cannot be copied implicitly; use '~value' to transfer ownership
        \\      second := first
        \\                ^
        \\
    );
}

test "feature_tests/ownership/06X_noncopyable_argument_by_value" {
    try buildExpectFailExact("tests/feature_tests/ownership/06X_noncopyable_argument_by_value",
        \\tests/feature_tests/ownership/06X_noncopyable_argument_by_value/main.rg:15:34: error: type 'Resource' cannot be copied implicitly; use '~value' to transfer ownership
        \\      status_code = consume(.res = handle)
        \\                                   ^
        \\
    );
}

test "feature_tests/ownership/07X_noncopyable_struct_field" {
    try buildExpectFailExact("tests/feature_tests/ownership/07X_noncopyable_struct_field",
        \\tests/feature_tests/ownership/07X_noncopyable_struct_field/main.rg:15:33: error: type 'Resource' cannot be copied implicitly; use '~value' to transfer ownership
        \\      wrapped : Wrapper = (.res = handle)
        \\                                  ^
        \\
    );
}

test "feature_tests/ownership/08X_noncopyable_output_binding" {
    try buildExpectFailExact("tests/feature_tests/ownership/08X_noncopyable_output_binding",
        \\tests/feature_tests/ownership/08X_noncopyable_output_binding/main.rg:10:11: error: type 'Resource' cannot be copied implicitly; use '~value' to transfer ownership
        \\      out = res
        \\            ^
        \\
    );
}

test "feature_tests/ownership/09_mutable_and_read_alias_same_call" {
    try expectSuccessfulBuild("tests/feature_tests/ownership/09_mutable_and_read_alias_same_call");
}

test "feature_tests/ownership/10_mutable_and_value_alias_same_call" {
    try expectSuccessfulBuild("tests/feature_tests/ownership/10_mutable_and_value_alias_same_call");
}

test "feature_tests/ownership/11_double_mutable_alias_same_call" {
    try expectSuccessfulBuild("tests/feature_tests/ownership/11_double_mutable_alias_same_call");
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
    try buildExpectFailExact("tests/feature_tests/ownership/14X_use_after_move",
        \\tests/feature_tests/ownership/14X_use_after_move/main.rg:16:34: error: binding 'handle' was moved and cannot be used again (moved at tests/feature_tests/ownership/14X_use_after_move/main.rg:15:34)
        \\      status_code = consume(.res = handle)
        \\                                   ^
        \\
    );
}

test "feature_tests/ownership/15X_reassign_after_move" {
    try buildExpectFailExact("tests/feature_tests/ownership/15X_reassign_after_move",
        \\tests/feature_tests/ownership/15X_reassign_after_move/main.rg:16:5: error: binding 'handle' was moved and cannot be reassigned (moved at tests/feature_tests/ownership/15X_reassign_after_move/main.rg:15:34)
        \\      handle = Resource()
        \\      ^
        \\
    );
}

test "feature_tests/basics/14X_get_and_set_index_operators" {
    try buildExpectFailWithoutParseNoise(
        "tests/feature_tests/basics/14X_get_and_set_index_operators",
        "unsupported operator 'get'",
    );
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

test "feature_tests/basics/19_c_function_alias" {
    const test_path = "tests/feature_tests/basics/19_c_function_alias";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/basics/20_c_enum_baseline" {
    const test_path = "tests/feature_tests/basics/20_c_enum_baseline";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/basics/21X_c_enum_payload" {
    try buildExpectFailExact("tests/feature_tests/basics/21X_c_enum_payload",
        \\tests/feature_tests/basics/21X_c_enum_payload/main.rg:3:7: error: CEnum variant '..exists' cannot carry a payload
        \\      ..exists (.code: Int32),
        \\        ^
        \\
    );
}

test "feature_tests/basics/22_c_union_baseline" {
    const test_path = "tests/feature_tests/basics/22_c_union_baseline";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/basics/23_terminal_abort" {
    const test_path = "tests/feature_tests/basics/23_terminal_abort";
    try expectSuccessfulBuild(test_path);
    try runExpectFailure(test_path);
}

test "feature_tests/basics/24X_abort_is_not_a_call" {
    try buildExpectFail("tests/feature_tests/basics/24X_abort_is_not_a_call", "abort");
}

test "feature_tests/basics/25X_abort_is_not_an_expression" {
    try buildExpectFail("tests/feature_tests/basics/25X_abort_is_not_an_expression", "abort");
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
    try buildExpectFailExact("tests/feature_tests/types/04X_choice_missing_payload",
        \\tests/feature_tests/types/04X_choice_missing_payload/main.rg:7:22: error: choice variant '..ok' requires a payload
        \\      value : Result = ..ok
        \\                       ^
        \\
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

test "feature_tests/types/41_choice_scalar_payload" {
    const test_path = "tests/feature_tests/types/41_choice_scalar_payload";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/types/42_choice_struct_payload_access" {
    const test_path = "tests/feature_tests/types/42_choice_struct_payload_access";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/types/43_choice_payload_precedence" {
    const test_path = "tests/feature_tests/types/43_choice_payload_precedence";
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
    try buildExpectFailExact("tests/feature_tests/types/10X_choice_unknown_variant",
        \\tests/feature_tests/types/10X_choice_unknown_variant/main.rg:7:25: error: choice type 'Direction' has no variant '..east'
        \\      value : Direction = ..east
        \\                          ^
        \\
    );
}

test "feature_tests/types/11X_choice_payload_access_without_payload" {
    try buildExpectFailExact("tests/feature_tests/types/11X_choice_payload_access_without_payload",
        \\tests/feature_tests/types/11X_choice_payload_access_without_payload/main.rg:8:23: error: choice variant '..north' has no payload
        \\      payload := value..north
        \\                        ^
        \\
    );
}

test "feature_tests/types/12X_match_non_choice" {
    try buildExpectFailExact("tests/feature_tests/types/12X_match_non_choice",
        \\tests/feature_tests/types/12X_match_non_choice/main.rg:4:11: error: match expects a choice value, found 'Int32'
        \\      match value {
        \\            ^
        \\
    );
}

test "feature_tests/types/13X_match_bind_payload_without_payload" {
    try buildExpectFailExact("tests/feature_tests/types/13X_match_bind_payload_without_payload",
        \\tests/feature_tests/types/13X_match_bind_payload_without_payload/main.rg:10:17: error: choice variant '..north' has no payload to bind
        \\          ..north payload {
        \\                  ^
        \\
    );
}

test "feature_tests/types/28X_match_omit_payload_pattern" {
    try buildExpectFailExact("tests/feature_tests/types/28X_match_omit_payload_pattern",
        \\tests/feature_tests/types/28X_match_omit_payload_pattern/main.rg:13:11: error: choice variant '..error' carries a payload and match must bind it explicitly; use '..error _' to ignore it
        \\          ..error {
        \\            ^
        \\
    );
}

test "feature_tests/types/32X_match_value_noncopyable_payload" {
    try buildExpectFailExact("tests/feature_tests/types/32X_match_value_noncopyable_payload",
        \\tests/feature_tests/types/32X_match_value_noncopyable_payload/main.rg:17:14: error: type '{...}' cannot be copied implicitly; use '~value' to transfer ownership
        \\          ..ok payload {
        \\               ^
        \\
    );
}

test "feature_tests/types/47X_match_value_payload_ambiguous_copy" {
    try buildExpectFail("tests/feature_tests/types/47X_match_value_payload_ambiguous_copy", "cannot be copied implicitly");
}

test "feature_tests/types/48X_match_move_payload_consumes_binding" {
    try buildExpectFailExact("tests/feature_tests/types/48X_match_move_payload_consumes_binding",
        \\tests/feature_tests/types/48X_match_move_payload_consumes_binding/main.rg:25:8: error: binding 'value' was moved and cannot be used again (moved at tests/feature_tests/types/48X_match_move_payload_consumes_binding/main.rg:16:11)
        \\      if value == ..error {
        \\         ^
        \\
    );
}

test "feature_tests/types/49X_choice_payload_access_ambiguous_copy" {
    try buildExpectFail("tests/feature_tests/types/49X_choice_payload_access_ambiguous_copy", "cannot be copied implicitly");
}

test "feature_tests/types/50X_choice_literal_payload_ambiguous_copy" {
    try buildExpectFail("tests/feature_tests/types/50X_choice_literal_payload_ambiguous_copy", "cannot be copied implicitly");
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
    try buildExpectFailExact("tests/feature_tests/collections/13X_iterator_abstract_missing_implements",
        \\tests/feature_tests/collections/13X_iterator_abstract_missing_implements/main.rg:9:12: error: type 'FakeIterator' does not implement abstract 'Iterator' required by parameter '.it' of 'consume':
        \\missing function: has_next (.self: &FakeIterator)
        \\      consume(.it = $&fake)
        \\             ^
        \\
    );
}

test "feature_tests/control_flow/05X_for_requires_iterator_contract" {
    try buildExpectFailExact("tests/feature_tests/control_flow/05X_for_requires_iterator_contract",
        \\tests/feature_tests/control_flow/05X_for_requires_iterator_contract/main.rg:7:1: error: type does not implement abstract 'Iterable':
        \\  missing function: to_iterator (.value: &FakeIterable)
        \\  possible overloads:
        \\  - to_iterator (.value: &FakeIterable) -> (.iterator: FakeIterator)
        \\      file: tests/feature_tests/control_flow/05X_for_requires_iterator_contract/main.rg:9:1
        \\  FakeIterable implements Iterable
        \\  ^
        \\
    );
}

test "feature_tests/collections/14_iterable_abstract" {
    const test_path = "tests/feature_tests/collections/14_iterable_abstract";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/collections/15X_iterable_abstract_missing_implements" {
    try buildExpectFailExact("tests/feature_tests/collections/15X_iterable_abstract_missing_implements",
        \\tests/feature_tests/collections/15X_iterable_abstract_missing_implements/main.rg:18:31: error: type 'FakeIterable' does not implement abstract 'Iterable' required by parameter '.items' of 'sum_iterable':
        \\missing function: to_iterator (.value: &FakeIterable)
        \\possible overloads:
        \\  - to_iterator (.value: &FakeIterable) -> (.iterator: FakeIterator)
        \\      file: tests/feature_tests/collections/15X_iterable_abstract_missing_implements/main.rg:7:1
        \\      status_code = sum_iterable(.items = &fake).sum
        \\                                ^
        \\
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

test "feature_tests/types/260_generic_type_initializer_defer" {
    const test_path = "tests/feature_tests/types/260_generic_type_initializer_defer";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
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
    try buildExpectFailExact("tests/feature_tests/types/21X_struct_initializer_must_use_visible_init",
        \\tests/feature_tests/types/21X_struct_initializer_must_use_visible_init/main.rg:14:19: error: failed to initialize type 'Point': no visible 'init' overload accepts arguments (.x: Int32, .y: Int32). Available overloads:
        \\  - Point init (.sum: Int32) -> (.result: Point)
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

test "feature_tests/collections/18_dynamic_array_copy" {
    const test_path = "tests/feature_tests/collections/18_dynamic_array_copy";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/collections/19_dynamic_array_borrowed_index_read_only" {
    const test_path = "tests/feature_tests/collections/19_dynamic_array_borrowed_index_read_only";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/collections/20_dynamic_array_borrowed_index_mutable" {
    const test_path = "tests/feature_tests/collections/20_dynamic_array_borrowed_index_mutable";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/collections/21X_index_operator_reached_default" {
    try buildExpectFailWithoutParseNoise(
        "tests/feature_tests/collections/21X_index_operator_reached_default",
        "unsupported operator 'get'",
    );
}

test "feature_tests/collections/22_dynamic_array_borrowed_index_string" {
    const test_path = "tests/feature_tests/collections/22_dynamic_array_borrowed_index_string";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/collections/23_dynamic_array_owning_push_fixed" {
    const test_path = "tests/feature_tests/collections/23_dynamic_array_owning_push_fixed";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/collections/24_dynamic_array_owning_assume_capacity" {
    const test_path = "tests/feature_tests/collections/24_dynamic_array_owning_assume_capacity";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/collections/25X_dynamic_array_owning_push_moves_source" {
    try buildExpectFail(
        "tests/feature_tests/collections/25X_dynamic_array_owning_push_moves_source",
        "binding 'value' was moved and cannot be used again",
    );
}

test "feature_tests/collections/26_dynamic_array_owning_pop" {
    const test_path = "tests/feature_tests/collections/26_dynamic_array_owning_pop";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/collections/27_dynamic_array_owning_pop_preserves_rest" {
    const test_path = "tests/feature_tests/collections/27_dynamic_array_owning_pop_preserves_rest";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/collections/28_dynamic_array_owning_growth" {
    const test_path = "tests/feature_tests/collections/28_dynamic_array_owning_growth";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/collections/29X_dynamic_array_growth_invalidates_old_alias" {
    try buildExpectFail(
        "tests/feature_tests/collections/29X_dynamic_array_growth_invalidates_old_alias",
        "root that has ended",
    );
}

test "feature_tests/collections/30_dynamic_array_owning_growth_failure_atomic" {
    const test_path = "tests/feature_tests/collections/30_dynamic_array_owning_growth_failure_atomic";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/collections/31_dynamic_array_owning_pop_auto_deinit" {
    const test_path = "tests/feature_tests/collections/31_dynamic_array_owning_pop_auto_deinit";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/collections/32_dynamic_array_borrowing_owner" {
    const test_path = "tests/feature_tests/collections/32_dynamic_array_borrowing_owner";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/collections/33X_dynamic_array_retains_external_borrow" {
    try buildExpectFail(
        "tests/feature_tests/collections/33X_dynamic_array_retains_external_borrow",
        "cannot end a root while opaque storage hides a dependency on it",
    );
}

test "feature_tests/collections/34_dynamic_array_string_copy" {
    const test_path = "tests/feature_tests/collections/34_dynamic_array_string_copy";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/collections/35_dynamic_array_fallible_copy_cleanup" {
    const test_path = "tests/feature_tests/collections/35_dynamic_array_fallible_copy_cleanup";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/collections/36_dynamic_array_owning_mutations" {
    const test_path = "tests/feature_tests/collections/36_dynamic_array_owning_mutations";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/collections/37_dynamic_array_associated_copy_reasons" {
    const test_path = "tests/feature_tests/collections/37_dynamic_array_associated_copy_reasons";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/collections/38X_fixed_array_index_out_of_bounds" {
    const test_path = "tests/feature_tests/collections/38X_fixed_array_index_out_of_bounds";
    try expectSuccessfulBuild(test_path);
    try runExpectFailure(test_path);
}

test "feature_tests/collections/46X_fixed_array_constant_index_out_of_bounds" {
    try buildExpectFail(
        "tests/feature_tests/collections/46X_fixed_array_constant_index_out_of_bounds",
        "array index 2 is out of bounds for length 2",
    );
}

test "feature_tests/collections/39X_dynamic_array_get_empty" {
    const test_path = "tests/feature_tests/collections/39X_dynamic_array_get_empty";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/collections/40X_dynamic_array_set_empty" {
    const test_path = "tests/feature_tests/collections/40X_dynamic_array_set_empty";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/collections/41X_dynamic_array_remove_empty" {
    const test_path = "tests/feature_tests/collections/41X_dynamic_array_remove_empty";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/collections/42X_dynamic_array_pop_empty" {
    const test_path = "tests/feature_tests/collections/42X_dynamic_array_pop_empty";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/collections/44X_uninit_helper_private" {
    try buildExpectFail(
        "tests/feature_tests/collections/44X_uninit_helper_private",
        "no function named '_trusted_uninit_slot' exists",
    );
}

test "feature_tests/collections/45X_array_view_out_of_bounds" {
    const test_path = "tests/feature_tests/collections/45X_array_view_out_of_bounds";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/collections/46X_dynamic_array_private_field" {
    try buildExpectFailExact("tests/feature_tests/collections/46X_dynamic_array_private_field",
        \\tests/feature_tests/collections/46X_dynamic_array_private_field/main.rg:5:11: error: field '_length' is private to its module
        \\      array._length = 100
        \\            ^
        \\
    );
}

test "feature_tests/collections/47X_dynamic_array_private_literal" {
    try buildExpectFail(
        "tests/feature_tests/collections/47X_dynamic_array_private_literal",
        "field '_allocation' is private to its module",
    );
}

test "feature_tests/collections/48_array_view_fixed_storage" {
    const test_path = "tests/feature_tests/collections/48_array_view_fixed_storage";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/collections/49X_array_view_unproven_length" {
    try buildExpectFail(
        "tests/feature_tests/collections/49X_array_view_unproven_length",
        "no matching generic overload of 'array_view' accepts arguments",
    );
}

test "feature_tests/collections/50X_array_view_private_literal" {
    try buildExpectFail(
        "tests/feature_tests/collections/50X_array_view_private_literal",
        "field '_data' is private to its module",
    );
}

test "feature_tests/collections/51X_array_view_private_constructor" {
    try buildExpectFail(
        "tests/feature_tests/collections/51X_array_view_private_constructor",
        "field '_data' is private to its module",
    );
}

test "feature_tests/collections/52X_dynamic_array_vacant_storage_reference" {
    try buildExpectFail(
        "tests/feature_tests/collections/52X_dynamic_array_vacant_storage_reference",
        "no function named 'trusted_dynamic_array_storage_pointer' exists",
    );
}

test "feature_tests/collections/53X_array_view_trusted_helper_private" {
    try buildExpectFail(
        "tests/feature_tests/collections/53X_array_view_trusted_helper_private",
        "no function named '_trusted_array_view' exists",
    );
}

test "feature_tests/collections/54X_dynamic_array_trusted_helper_private" {
    try buildExpectFail(
        "tests/feature_tests/collections/54X_dynamic_array_trusted_helper_private",
        "no function named '_trusted_dynamic_array_get' exists",
    );
}

test "feature_tests/collections/55X_allocation_byte_helper_private" {
    try buildExpectFail(
        "tests/feature_tests/collections/55X_allocation_byte_helper_private",
        "no function named '_trusted_allocation_byte_rw' exists",
    );
}

test "feature_tests/control_flow/11_range_default_start_with_step" {
    const test_path = "tests/feature_tests/control_flow/11_range_default_start_with_step";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/control_flow/12X_for_nullable_not_iterable" {
    try buildExpectFailExact("tests/feature_tests/control_flow/12X_for_nullable_not_iterable",
        \\tests/feature_tests/control_flow/12X_for_nullable_not_iterable/main.rg:4:5: error: for expects a type implementing abstract 'Iterable', got '?Int32'
        \\      for item in value {
        \\      ^
        \\
    );
}

test "feature_tests/control_flow/13_for_borrowed_array" {
    const test_path = "tests/feature_tests/control_flow/13_for_borrowed_array";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/control_flow/14_for_mut_borrowed_dynamic_array" {
    const test_path = "tests/feature_tests/control_flow/14_for_mut_borrowed_dynamic_array";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/types/14X_errable_match_unknown_variant" {
    try buildExpectFailExact("tests/feature_tests/types/14X_errable_match_unknown_variant",
        \\tests/feature_tests/types/14X_errable_match_unknown_variant/main.rg:7:11: error: choice type 'Errable#(.t: Int32, .reasons: (..test_error))' has no variant '..none'
        \\          ..none {
        \\            ^
        \\
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
        \\  at tests/feature_tests/types/24_error_trace_report/main.rg:4:14
        \\        result = ..error(.reason = ..test_error)
        \\                 ^
        \\
    );
}

test "feature_tests/types/46_report_error_helper" {
    const test_path = "tests/feature_tests/types/46_report_error_helper";
    try expectSuccessfulBuild(test_path);
    try runExpectStderr(test_path, 0,
        \\error: project build failed
        \\error trace (most recent first):
        \\  at tests/feature_tests/types/46_report_error_helper/main.rg:13:23: loading project config
        \\        value := middle() !! "loading project config"
        \\                          ^
        \\  at tests/feature_tests/types/46_report_error_helper/main.rg:8:20
        \\        value := fail()!
        \\                       ^
        \\  at tests/feature_tests/types/46_report_error_helper/main.rg:4:14
        \\        result = ..error(.reason = ..test_error)
        \\                 ^
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
    try buildExpectFailExact("tests/feature_tests/system/03X_reached_argument_missing",
        \\tests/feature_tests/system/03X_reached_argument_missing/main.rg:12:26: error: cannot resolve reached argument '.writer' with alternatives [writer, terminal.writer, system.terminal.writer] expected as 'Int32'
        \\      status_code = forward()
        \\                           ^
        \\
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
    try runExpect(test_path, 22);
}

test "feature_tests/types/15_default_type_initializer_argument" {
    const test_path = "tests/feature_tests/types/15_default_type_initializer_argument";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 7);
}

test "feature_tests/ownership/16_auto_deinit_at_function_exit" {
    const test_path = "tests/feature_tests/ownership/16_auto_deinit_at_function_exit";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/17X_removed_keep_directive" {
    try buildExpectFailExact("tests/feature_tests/ownership/17X_removed_keep_directive",
        \\tests/feature_tests/ownership/17X_removed_keep_directive/main.rg:3:5: error: unknown directive '#keep'
        \\      #keep value
        \\      ^
        \\
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

test "feature_tests/io/20_read_into_array_view" {
    const test_path = "tests/feature_tests/io/20_read_into_array_view";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/io/21_write_from_array_view" {
    const test_path = "tests/feature_tests/io/21_write_from_array_view";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/io/22_abstract_writer_field_assignment" {
    const test_path = "tests/feature_tests/io/22_abstract_writer_field_assignment";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/io/23X_abstract_writer_field_conflicting_assignment" {
    try buildExpectFailExact("tests/feature_tests/io/23X_abstract_writer_field_conflicting_assignment",
        \\tests/feature_tests/io/23X_abstract_writer_field_conflicting_assignment/main.rg:50:17: error: field '.writer' already stores '$&FirstWriter' for abstract type '$&Writer', so it cannot also store '$&SecondWriter'
        \\      p&.writer = writer
        \\                  ^
        \\
    );
}

test "feature_tests/io/24_terminal_files" {
    const test_path = "tests/feature_tests/io/24_terminal_files";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/io/25_positional_text_helpers" {
    const test_path = "tests/feature_tests/io/25_positional_text_helpers";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/io/26X_print_without_system" {
    try buildExpectFailExact("tests/feature_tests/io/26X_print_without_system",
        \\tests/feature_tests/io/26X_print_without_system/main.rg:2:10: error: no overload of 'print' accepts arguments (.: StringView). Available signatures:
        \\  - print (.value: StringView, .writer: $&Writer, .terminator: StringView) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed)))
        \\  - print (.value: &String, .writer: $&Writer, .terminator: StringView) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed)))
        \\      print("Hello, World!\n")
        \\           ^
        \\
    );
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

test "feature_tests/control_flow/18_continue" {
    const test_path = "tests/feature_tests/control_flow/18_continue";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/control_flow/19X_continue_outside_loop" {
    try buildExpectFailExact("tests/feature_tests/control_flow/19X_continue_outside_loop",
        \\tests/feature_tests/control_flow/19X_continue_outside_loop/main.rg:2:5: error: continue used outside of a loop
        \\      continue
        \\      ^
        \\
    );
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

test "feature_tests/io/14_file_stream_error_reasons" {
    const test_path = "tests/feature_tests/io/14_file_stream_error_reasons";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/io/09_print_string_literal" {
    const test_path = "tests/feature_tests/io/09_print_string_literal";
    try expectSuccessfulBuild(test_path);
    try runExpectStdout(test_path, 0, "literal output\n");
}

test "feature_tests/io/16_print_string_view" {
    const test_path = "tests/feature_tests/io/16_print_string_view";
    try expectSuccessfulBuild(test_path);
    try runExpectStdout(test_path, 0, "string view output\n");
}

test "feature_tests/io/17_print_error_string_view" {
    const test_path = "tests/feature_tests/io/17_print_error_string_view";
    try expectSuccessfulBuild(test_path);
    try runExpectStderr(test_path, 0, "error view");
}

test "feature_tests/io/18_print_borrowed_string_view" {
    const test_path = "tests/feature_tests/io/18_print_borrowed_string_view";
    try expectSuccessfulBuild(test_path);
    try runExpectStdout(test_path, 0, "borrowed view\n");
}

test "feature_tests/io/19_print_error_borrowed_string_view" {
    const test_path = "tests/feature_tests/io/19_print_error_borrowed_string_view";
    try expectSuccessfulBuild(test_path);
    try runExpectStderr(test_path, 0, "borrowed err");
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

test "feature_tests/io/15_read_line_error" {
    const test_path = "tests/feature_tests/io/15_read_line_error";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/system/07_arguments_access" {
    const test_path = "tests/feature_tests/system/07_arguments_access";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/system/08X_arguments_index_operator" {
    try buildExpectFailWithoutParseNoise(
        "tests/feature_tests/system/08X_arguments_index_operator",
        "indexing is only supported for native arrays",
    );
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

test "feature_tests/system/12X_environment_variables_index_operator" {
    try buildExpectFailWithoutParseNoise(
        "tests/feature_tests/system/12X_environment_variables_index_operator",
        "indexing is only supported for native arrays",
    );
}

test "feature_tests/system/13X_environment_variables_string_view_keys" {
    try buildExpectFailWithoutParseNoise(
        "tests/feature_tests/system/13X_environment_variables_string_view_keys",
        "indexing is only supported for native arrays",
    );
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

test "feature_tests/ownership/18_system_reference_copy_assignment" {
    const test_path = "tests/feature_tests/ownership/18_system_reference_copy_assignment";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/ownership/19_system_reference_copy_argument" {
    const test_path = "tests/feature_tests/ownership/19_system_reference_copy_argument";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/ownership/35_system_move_by_value" {
    const test_path = "tests/feature_tests/ownership/35_system_move_by_value";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/36X_double_move" {
    try buildExpectFailExact("tests/feature_tests/ownership/36X_double_move",
        \\tests/feature_tests/ownership/36X_double_move/main.rg:16:35: error: binding 'handle' was moved and cannot be used again (moved at tests/feature_tests/ownership/36X_double_move/main.rg:15:34)
        \\      status_code = consume(.res = ~handle)
        \\                                    ^
        \\
    );
}

test "feature_tests/system/15_once_single_use" {
    const test_path = "tests/feature_tests/system/15_once_single_use";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/system/16X_once_duplicate_direct" {
    try buildExpectFailExact("tests/feature_tests/system/16X_once_duplicate_direct",
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
    try buildExpectFailExact("tests/feature_tests/system/18X_once_duplicate_indirect",
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
    try buildExpectFailExact("tests/feature_tests/system/20X_once_duplicate_init",
        \\tests/feature_tests/system/20X_once_duplicate_init/main.rg:10:15: error: once function 'init' is consumed more than once from the reachable entrypoint graph (first use at tests/feature_tests/system/20X_once_duplicate_init/main.rg:9:14 via 'main')
        \\      second := Token()
        \\                ^
        \\
    );
}

test "feature_tests/system/21X_terminal_duplicate_init" {
    try buildExpectFailWithoutParseNoise(
        "tests/feature_tests/system/21X_terminal_duplicate_init",
        "once function 'init' is consumed more than once",
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

test "feature_tests/system/30_page_allocator_baseline" {
    const test_path = "tests/feature_tests/system/30_page_allocator_baseline";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/system/32_page_allocator_via_allocator_abstract" {
    const test_path = "tests/feature_tests/system/32_page_allocator_via_allocator_abstract";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/system/33_array_view_libc_memcpy" {
    const test_path = "tests/feature_tests/system/33_array_view_libc_memcpy";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/system/34_file_block_short_read" {
    const test_path = "tests/feature_tests/system/34_file_block_short_read";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/polymorphism/20_generic_abstract_bound_syntax" {
    const test_path = "tests/feature_tests/polymorphism/20_generic_abstract_bound_syntax";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 42);
}

test "feature_tests/polymorphism/21X_generic_bound_requires_type_keyword" {
    try buildExpectFailExact("tests/feature_tests/polymorphism/21X_generic_bound_requires_type_keyword",
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

test "feature_tests/ownership/21_explicit_string_deinit" {
    const test_path = "tests/feature_tests/ownership/21_explicit_string_deinit";
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

test "feature_tests/ownership/24_mutable_and_read_field_alias_same_call" {
    try expectSuccessfulBuild("tests/feature_tests/ownership/24_mutable_and_read_field_alias_same_call");
}

test "feature_tests/ownership/25_mutable_and_value_field_alias_same_call" {
    try expectSuccessfulBuild("tests/feature_tests/ownership/25_mutable_and_value_field_alias_same_call");
}

test "feature_tests/ownership/26_distinct_fields_do_not_alias_same_call" {
    const test_path = "tests/feature_tests/ownership/26_distinct_fields_do_not_alias_same_call";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 7);
}

test "feature_tests/ownership/27X_ambiguous_copy_in_array_literal" {
    try buildExpectFail("tests/feature_tests/ownership/27X_ambiguous_copy_in_array_literal", "type 'Resource' cannot be copied implicitly");
}

test "feature_tests/ownership/28X_ambiguous_copy_assignment" {
    try buildExpectFail("tests/feature_tests/ownership/28X_ambiguous_copy_assignment", "cannot be copied implicitly");
}

test "feature_tests/ownership/37X_ambiguous_copy_return" {
    try buildExpectFail("tests/feature_tests/ownership/37X_ambiguous_copy_return", "cannot be copied implicitly");
}

test "feature_tests/ownership/38X_ambiguous_copy_struct_field" {
    try buildExpectFail("tests/feature_tests/ownership/38X_ambiguous_copy_struct_field", "cannot be copied implicitly");
}

test "feature_tests/ownership/39_stable_field_reference_survives_replacement" {
    const test_path = "tests/feature_tests/ownership/39_stable_field_reference_survives_replacement";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/40X_raw_pointer_establish_fresh" {
    try buildExpectFail("tests/feature_tests/ownership/40X_raw_pointer_establish_fresh", "no function named 'establish_fresh_reference' exists");
}

test "feature_tests/ownership/41_raw_pointer_establish_inherit" {
    try expectSuccessfulBuild("tests/feature_tests/ownership/41_raw_pointer_establish_inherit");
}

test "feature_tests/ownership/42X_reference_use_after_root_end" {
    try buildExpectFailExact("tests/feature_tests/ownership/42X_reference_use_after_root_end",
        \\tests/feature_tests/ownership/42X_reference_use_after_root_end/main.rg:12:8: error: reference depends on a root that has ended
        \\      if reference& == 0 {
        \\         ^
        \\
    );
}

test "feature_tests/ownership/53X_pointer_inputs_may_alias" {
    try buildExpectFailExact("tests/feature_tests/ownership/53X_pointer_inputs_may_alias",
        \\tests/feature_tests/ownership/53X_pointer_inputs_may_alias/main.rg:6:25: error: reference depends on a root that has ended
        \\      value = read_alias&.size
        \\                          ^
        \\
    );
}

test "feature_tests/ownership/54_deinit_through_alias_reinitialize" {
    try expectSuccessfulBuild("tests/feature_tests/ownership/54_deinit_through_alias_reinitialize");
}

test "feature_tests/ownership/55X_deinit_through_alias_read" {
    try buildExpectFailExact("tests/feature_tests/ownership/55X_deinit_through_alias_read",
        \\tests/feature_tests/ownership/55X_deinit_through_alias_read/main.rg:12:11: error: reference depends on a root that has ended
        \\      if b&.size == 1 {
        \\            ^
        \\
    );
}

test "feature_tests/ownership/56_branch_ownership_cleanup_resolves" {
    try expectSuccessfulBuild("tests/feature_tests/ownership/56_branch_ownership_cleanup_resolves");
}

test "feature_tests/ownership/57_return_reference_to_local" {
    try expectSuccessfulBuild("tests/feature_tests/ownership/57_return_reference_to_local");
    try runExpect("tests/feature_tests/ownership/57_return_reference_to_local", 3);
}

test "feature_tests/ownership/58X_null_safe_reference" {
    try buildExpectFailExact("tests/feature_tests/ownership/58X_null_safe_reference",
        \\tests/feature_tests/ownership/58X_null_safe_reference/main.rg:3:23: error: no function named 'cast' exists
        \\      reference ::= cast#(.to: $&Int32)(.value = zero)
        \\                        ^
        \\
    );
}

test "feature_tests/ownership/59X_branch_deinit_then_use" {
    try buildExpectFailExact("tests/feature_tests/ownership/59X_branch_deinit_then_use",
        \\tests/feature_tests/ownership/59X_branch_deinit_then_use/main.rg:13:19: error: place rooted at 'allocation' is maybe_initialized and cannot be used
        \\      if allocation.size == 1 {
        \\                    ^
        \\
    );
}

test "feature_tests/ownership/60_partial_field_move_cleanup" {
    try expectSuccessfulBuild("tests/feature_tests/ownership/60_partial_field_move_cleanup");
}

test "feature_tests/ownership/61X_borrowed_foreign_pointer_fresh_root" {
    try buildExpectFail("tests/feature_tests/ownership/61X_borrowed_foreign_pointer_fresh_root", "no function named 'establish_fresh_reference' exists");
}

test "feature_tests/ownership/62X_borrowed_foreign_pointer_roundtrip" {
    try buildExpectFailExact("tests/feature_tests/ownership/62X_borrowed_foreign_pointer_roundtrip",
        \\tests/feature_tests/ownership/62X_borrowed_foreign_pointer_roundtrip/main.rg:5:24: error: no function named 'cast' exists
        \\      fabricated ::= cast#(.to: &Char)(.value = address)
        \\                         ^
        \\
    );
}

test "feature_tests/ownership/63X_malloc_direct_safe_cast" {
    try buildExpectFailExact("tests/feature_tests/ownership/63X_malloc_direct_safe_cast",
        \\tests/feature_tests/ownership/63X_malloc_direct_safe_cast/main.rg:4:24: error: no function named 'cast' exists
        \\      fabricated ::= cast#(.to: $&UInt8)(.value = address)
        \\                         ^
        \\
    );
}

test "feature_tests/ownership/64X_owned_root_cycle" {
    try buildExpectFailExact("tests/feature_tests/ownership/64X_owned_root_cycle",
        \\tests/feature_tests/ownership/64X_owned_root_cycle/main.rg:18:5: error: root ownership must be acyclic
        \\      slot_b& = ~a
        \\      ^
        \\
    );
}

test "feature_tests/ownership/65_allocation_stores_stateful_allocator" {
    const test_path = "tests/feature_tests/ownership/65_allocation_stores_stateful_allocator";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/ownership/66_allocation_stateful_allocator_escape" {
    try expectSuccessfulBuild("tests/feature_tests/ownership/66_allocation_stateful_allocator_escape");
    try runExpect("tests/feature_tests/ownership/66_allocation_stateful_allocator_escape", 0);
}

test "feature_tests/ownership/67_local_binding_summary_dependency" {
    try expectSuccessfulBuild("tests/feature_tests/ownership/67_local_binding_summary_dependency");
    try runExpect("tests/feature_tests/ownership/67_local_binding_summary_dependency", 7);
}

test "feature_tests/ownership/68_arena_child_deinit_preserves_sibling" {
    const test_path = "tests/feature_tests/ownership/68_arena_child_deinit_preserves_sibling";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/ownership/69X_arena_reset_ends_child_domain" {
    try buildExpectFail(
        "tests/feature_tests/ownership/69X_arena_reset_ends_child_domain",
        "reference depends on a root that has ended",
    );
}

test "feature_tests/ownership/70_zero_size_allocation_cleanup" {
    const test_path = "tests/feature_tests/ownership/70_zero_size_allocation_cleanup";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/ownership/71_fallible_allocation_failure_cleanup" {
    const test_path = "tests/feature_tests/ownership/71_fallible_allocation_failure_cleanup";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/ownership/72X_duplicate_storage_establishment" {
    try buildExpectFail(
        "tests/feature_tests/ownership/72X_duplicate_storage_establishment",
        "physical storage capability has already been consumed",
    );
}

test "feature_tests/ownership/73_storage_capability_move" {
    const test_path = "tests/feature_tests/ownership/73_storage_capability_move";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/ownership/74X_core_path_not_trusted" {
    try buildExpectFail(
        "tests/feature_tests/ownership/74X_core_path_not_trusted",
        "no function named 'cast' exists",
    );
}

test "feature_tests/ownership/75_choice_variant_sensitive_roots" {
    const test_path = "tests/feature_tests/ownership/75_choice_variant_sensitive_roots";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/ownership/76X_choice_payload_double_move" {
    try buildExpectFail(
        "tests/feature_tests/ownership/76X_choice_payload_double_move",
        "binding 'payload' was moved and cannot be used again",
    );
}

test "feature_tests/ownership/77_arena_zero_size_allocation" {
    const test_path = "tests/feature_tests/ownership/77_arena_zero_size_allocation";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/ownership/80_arena_repeated_reset" {
    const test_path = "tests/feature_tests/ownership/80_arena_repeated_reset";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/ownership/81_descendant_storage_generations" {
    const test_path = "tests/feature_tests/ownership/81_descendant_storage_generations";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/ownership/82X_descendant_storage_stale_alias" {
    try buildExpectFail(
        "tests/feature_tests/ownership/82X_descendant_storage_stale_alias",
        "reference depends on a root that has ended",
    );
}

test "feature_tests/ownership/83_field_reinitialization_preserves_sibling" {
    const test_path = "tests/feature_tests/ownership/83_field_reinitialization_preserves_sibling";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/ownership/84_semantic_relocation" {
    const test_path = "tests/feature_tests/ownership/84_semantic_relocation";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/ownership/85X_semantic_relocation_double" {
    try buildExpectFail(
        "tests/feature_tests/ownership/85X_semantic_relocation_double",
        "binding 'source' was moved and cannot be used again",
    );
}

test "feature_tests/ownership/86_relocation_storage_capability" {
    const test_path = "tests/feature_tests/ownership/86_relocation_storage_capability";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/ownership/87_relocation_interprocedural" {
    const test_path = "tests/feature_tests/ownership/87_relocation_interprocedural";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/ownership/88_semantic_relocation_trivial" {
    const test_path = "tests/feature_tests/ownership/88_semantic_relocation_trivial";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/ownership/89_semantic_relocation_choice" {
    const test_path = "tests/feature_tests/ownership/89_semantic_relocation_choice";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/ownership/90X_relocation_initialized_destination" {
    try buildExpectFail(
        "tests/feature_tests/ownership/90X_relocation_initialized_destination",
        "relocate destination is initialized",
    );
}

test "feature_tests/ownership/91X_relocation_stale_destination_alias" {
    try buildExpectFail(
        "tests/feature_tests/ownership/91X_relocation_stale_destination_alias",
        "reference depends on a root that has ended",
    );
}

test "feature_tests/ownership/92X_relocation_owning_destination" {
    try buildExpectFail(
        "tests/feature_tests/ownership/92X_relocation_owning_destination",
        "relocate destination is initialized",
    );
}

test "feature_tests/ownership/93X_relocation_maybe_initialized_destination" {
    try buildExpectFail(
        "tests/feature_tests/ownership/93X_relocation_maybe_initialized_destination",
        "relocate destination may be initialized",
    );
}

test "feature_tests/ownership/94_choice_if_narrowing" {
    const test_path = "tests/feature_tests/ownership/94_choice_if_narrowing";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/ownership/95X_choice_unproven_payload" {
    try buildExpectFail(
        "tests/feature_tests/ownership/95X_choice_unproven_payload",
        "requires its variant to be proven active",
    );
}

test "feature_tests/ownership/96_choice_comparison_narrowing" {
    const test_path = "tests/feature_tests/ownership/96_choice_comparison_narrowing";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/ownership/97_choice_nested_narrowing" {
    const test_path = "tests/feature_tests/ownership/97_choice_nested_narrowing";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/ownership/98X_choice_nested_unproven_payload" {
    try buildExpectFail(
        "tests/feature_tests/ownership/98X_choice_nested_unproven_payload",
        "requires its variant to be proven active",
    );
}

test "feature_tests/ownership/99X_choice_else_keeps_multiple_variants" {
    try buildExpectFail(
        "tests/feature_tests/ownership/99X_choice_else_keeps_multiple_variants",
        "requires its variant to be proven active",
    );
}

test "feature_tests/ownership/100_safe_reference_lifetime_restriction" {
    const test_path = "tests/feature_tests/ownership/100_safe_reference_lifetime_restriction";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/286_explicit_value_dependency" {
    const test_path = "tests/feature_tests/ownership/286_explicit_value_dependency";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/287X_explicit_dependency_after_deinit" {
    try buildExpectFail(
        "tests/feature_tests/ownership/287X_explicit_dependency_after_deinit",
        "value depends on a root that has ended",
    );
}

test "feature_tests/ownership/288X_explicit_dependency_through_call" {
    try buildExpectFail(
        "tests/feature_tests/ownership/288X_explicit_dependency_through_call",
        "value depends on a root that has ended",
    );
}

test "feature_tests/ownership/101X_safe_reference_restriction_ended_lifetime" {
    try buildExpectFail(
        "tests/feature_tests/ownership/101X_safe_reference_restriction_ended_lifetime",
        "reference depends on a root that has ended",
    );
}

test "feature_tests/ownership/102X_safe_reference_restriction_ended_source" {
    try buildExpectFail(
        "tests/feature_tests/ownership/102X_safe_reference_restriction_ended_source",
        "reference depends on a root that has ended",
    );
}

test "feature_tests/ownership/103_safe_reference_restriction_after_reinitialize" {
    const test_path = "tests/feature_tests/ownership/103_safe_reference_restriction_after_reinitialize";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/104X_safe_reference_restriction_relocated" {
    try buildExpectFail(
        "tests/feature_tests/ownership/104X_safe_reference_restriction_relocated",
        "reference depends on a root that has ended",
    );
}

test "feature_tests/ownership/105X_safe_reference_restriction_stale_after_reinitialize" {
    try buildExpectFail(
        "tests/feature_tests/ownership/105X_safe_reference_restriction_stale_after_reinitialize",
        "reference depends on a root that has ended",
    );
}

test "feature_tests/ownership/106_trusted_opaque_move_user_call" {
    const test_path = "tests/feature_tests/ownership/106_trusted_opaque_move_user_call";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/107_trusted_opaque_drop_user_call" {
    try expectSuccessfulBuild("tests/feature_tests/ownership/107_trusted_opaque_drop_user_call");
}

test "feature_tests/ownership/108_trusted_opaque_user_core_path" {
    try expectSuccessfulBuild("tests/feature_tests/ownership/108_trusted_opaque_user_core_path/core");
}

test "feature_tests/ownership/109_trusted_opaque_move_scalar" {
    const test_path = "tests/feature_tests/ownership/109_trusted_opaque_move_scalar";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 42);
}

test "feature_tests/ownership/110X_trusted_opaque_move_double_move" {
    try buildExpectFail("tests/feature_tests/ownership/110X_trusted_opaque_move_double_move", "binding 'value' was moved and cannot be used again");
}

test "feature_tests/ownership/111X_trusted_opaque_move_use_after_move" {
    try buildExpectFail("tests/feature_tests/ownership/111X_trusted_opaque_move_use_after_move", "binding 'value' was moved and cannot be used again");
}

test "feature_tests/ownership/112_trusted_opaque_wrapper" {
    const test_path = "tests/feature_tests/ownership/112_trusted_opaque_wrapper";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 42);
}

test "feature_tests/ownership/113_fake_trusted_opaque_name" {
    const test_path = "tests/feature_tests/ownership/113_fake_trusted_opaque_name";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/114X_trusted_opaque_wrapper_use_after_move" {
    try buildExpectFail("tests/feature_tests/ownership/114X_trusted_opaque_wrapper_use_after_move", "binding 'value' was moved and cannot be used again");
}

test "feature_tests/ownership/115X_trusted_opaque_nested_wrapper_double_move" {
    try buildExpectFail("tests/feature_tests/ownership/115X_trusted_opaque_nested_wrapper_double_move", "binding 'value' was moved and cannot be used again");
}

test "feature_tests/ownership/116_trusted_opaque_allocation" {
    const test_path = "tests/feature_tests/ownership/116_trusted_opaque_allocation";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/117X_trusted_opaque_allocation_alias" {
    try buildExpectFail(
        "tests/feature_tests/ownership/117X_trusted_opaque_allocation_alias",
        "opaque ownership storage requires no live external aliases to the consumed root",
    );
}

test "feature_tests/ownership/118_trusted_opaque_allocation_nested" {
    const test_path = "tests/feature_tests/ownership/118_trusted_opaque_allocation_nested";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/119X_trusted_opaque_allocation_nested_alias" {
    try buildExpectFail(
        "tests/feature_tests/ownership/119X_trusted_opaque_allocation_nested_alias",
        "opaque ownership storage requires no live external aliases to the consumed root",
    );
}

test "feature_tests/ownership/120X_trusted_opaque_router_transaction" {
    try buildExpectFail(
        "tests/feature_tests/ownership/120X_trusted_opaque_router_transaction",
        "opaque ownership storage cannot hide dependencies on external roots",
    );
}

test "feature_tests/ownership/121_trusted_opaque_drop_cleanup" {
    const test_path = "tests/feature_tests/ownership/121_trusted_opaque_drop_cleanup";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/122_trusted_opaque_relocate" {
    const test_path = "tests/feature_tests/ownership/122_trusted_opaque_relocate";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/123X_self_referential_move_does_not_retarget" {
    try buildExpectFail(
        "tests/feature_tests/ownership/123X_self_referential_move_does_not_retarget",
        "value was moved",
    );
}

test "feature_tests/ownership/123X_opaque_relocate_self_reference" {
    try buildExpectFail(
        "tests/feature_tests/ownership/123X_opaque_relocate_self_reference",
        "opaque ownership storage cannot hide dependencies on external roots",
    );
}

test "feature_tests/ownership/124_visible_reference_invalidation_is_deferred" {
    const test_path = "tests/feature_tests/ownership/124_visible_reference_invalidation_is_deferred";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/125X_visible_reference_use_after_invalidation" {
    try buildExpectFail(
        "tests/feature_tests/ownership/125X_visible_reference_use_after_invalidation",
        "reference depends on a root that has ended",
    );
}

test "feature_tests/ownership/126_opaque_move_in_external_dependency" {
    const test_path = "tests/feature_tests/ownership/126_opaque_move_in_external_dependency";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/127X_opaque_relocate_mutation_after_move_in" {
    try buildExpectFail(
        "tests/feature_tests/ownership/127X_opaque_relocate_mutation_after_move_in",
        "relocation would invalidate a hidden opaque dependency",
    );
}

test "feature_tests/ownership/128X_opaque_hidden_dependency_blocks_root_end" {
    try buildExpectFail(
        "tests/feature_tests/ownership/128X_opaque_hidden_dependency_blocks_root_end",
        "cannot end a root while opaque storage hides a dependency on it",
    );
}

test "feature_tests/ownership/129_opaque_hidden_dependency_does_not_block_unrelated_root" {
    const test_path = "tests/feature_tests/ownership/129_opaque_hidden_dependency_does_not_block_unrelated_root";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/130X_opaque_hidden_dependency_branch_join" {
    try buildExpectFail(
        "tests/feature_tests/ownership/130X_opaque_hidden_dependency_branch_join",
        "cannot end a root while opaque storage hides a dependency on it",
    );
}

test "feature_tests/ownership/131X_opaque_hidden_dependency_through_wrapper" {
    try buildExpectFail(
        "tests/feature_tests/ownership/131X_opaque_hidden_dependency_through_wrapper",
        "cannot end a root while opaque storage hides a dependency on it",
    );
}

test "feature_tests/ownership/132X_opaque_local_aggregate_dependency_through_wrapper" {
    try buildExpectFail(
        "tests/feature_tests/ownership/132X_opaque_local_aggregate_dependency_through_wrapper",
        "cannot end a root while opaque storage hides a dependency on it",
    );
}

test "feature_tests/ownership/133_opaque_local_aggregate_wrapper_allows_unrelated_end" {
    const test_path = "tests/feature_tests/ownership/133_opaque_local_aggregate_wrapper_allows_unrelated_end";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/134X_opaque_local_aggregate_nested_wrapper" {
    try buildExpectFail(
        "tests/feature_tests/ownership/134X_opaque_local_aggregate_nested_wrapper",
        "cannot end a root while opaque storage hides a dependency on it",
    );
}

test "feature_tests/ownership/135_opaque_move_in_exactly_once_codegen" {
    const test_path = "tests/feature_tests/ownership/135_opaque_move_in_exactly_once_codegen";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/136_opaque_dependency_summary_does_not_duplicate_ownership" {
    const test_path = "tests/feature_tests/ownership/136_opaque_dependency_summary_does_not_duplicate_ownership";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/137X_opaque_hidden_dependency_blocks_owner_consumption" {
    try buildExpectFail(
        "tests/feature_tests/ownership/137X_opaque_hidden_dependency_blocks_owner_consumption",
        "cannot end a root while opaque storage hides a dependency on it",
    );
}

test "feature_tests/ownership/138_opaque_hidden_dependency_allows_unrelated_owner_consumption" {
    const test_path = "tests/feature_tests/ownership/138_opaque_hidden_dependency_allows_unrelated_owner_consumption";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/139X_opaque_hidden_dependency_blocks_owner_consumption_through_wrapper" {
    try buildExpectFail(
        "tests/feature_tests/ownership/139X_opaque_hidden_dependency_blocks_owner_consumption_through_wrapper",
        "cannot end a root while opaque storage hides a dependency on it",
    );
}

test "feature_tests/ownership/140X_opaque_mutation_hides_external_dependency" {
    try buildExpectFail(
        "tests/feature_tests/ownership/140X_opaque_mutation_hides_external_dependency",
        "cannot end a root while opaque storage hides a dependency on it",
    );
}

test "feature_tests/ownership/141_opaque_mutation_allows_unrelated_root_end" {
    const test_path = "tests/feature_tests/ownership/141_opaque_mutation_allows_unrelated_root_end";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/142X_opaque_mutation_dependency_through_wrapper" {
    try buildExpectFail(
        "tests/feature_tests/ownership/142X_opaque_mutation_dependency_through_wrapper",
        "cannot end a root while opaque storage hides a dependency on it",
    );
}

test "feature_tests/ownership/143X_opaque_mutation_existing_internal_pointer_blocks_relocation" {
    try buildExpectFail(
        "tests/feature_tests/ownership/143X_opaque_mutation_existing_internal_pointer_blocks_relocation",
        "relocation would invalidate a hidden opaque dependency",
    );
}

test "feature_tests/ownership/144X_opaque_mutation_cached_internal_pointer_blocks_relocation" {
    try buildExpectFail(
        "tests/feature_tests/ownership/144X_opaque_mutation_cached_internal_pointer_blocks_relocation",
        "relocation would invalidate a hidden opaque dependency",
    );
}

test "feature_tests/ownership/145_opaque_mutation_external_pointer_allows_relocation" {
    const test_path = "tests/feature_tests/ownership/145_opaque_mutation_external_pointer_allows_relocation";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/146X_opaque_mutation_cached_internal_pointer_through_wrapper_blocks_relocation" {
    try buildExpectFail(
        "tests/feature_tests/ownership/146X_opaque_mutation_cached_internal_pointer_through_wrapper_blocks_relocation",
        "relocation would invalidate a hidden opaque dependency",
    );
}

test "feature_tests/ownership/147X_address_through_stale_pointer_does_not_revive" {
    try buildExpectFail(
        "tests/feature_tests/ownership/147X_address_through_stale_pointer_does_not_revive",
        "reference depends on a root that has ended",
    );
}

test "feature_tests/ownership/148X_address_through_stale_opaque_pointer_does_not_revive" {
    try buildExpectFail(
        "tests/feature_tests/ownership/148X_address_through_stale_opaque_pointer_does_not_revive",
        "reference depends on a root that has ended",
    );
}

test "feature_tests/ownership/149X_field_read_through_stale_pointer_fails" {
    try buildExpectFail(
        "tests/feature_tests/ownership/149X_field_read_through_stale_pointer_fails",
        "reference depends on a root that has ended",
    );
}

test "feature_tests/ownership/150X_array_read_through_stale_pointer_fails" {
    try buildExpectFail(
        "tests/feature_tests/ownership/150X_array_read_through_stale_pointer_fails",
        "reference depends on a root that has ended",
    );
}

test "feature_tests/ownership/152X_array_write_through_stale_pointer_fails" {
    try buildExpectFail(
        "tests/feature_tests/ownership/152X_array_write_through_stale_pointer_fails",
        "reference depends on a root that has ended",
    );
}

test "feature_tests/ownership/153_live_array_pointer_accesses" {
    const test_path = "tests/feature_tests/ownership/153_live_array_pointer_accesses";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/154_precise_pointer_assignment_reinitializes_dead_place" {
    const test_path = "tests/feature_tests/ownership/154_precise_pointer_assignment_reinitializes_dead_place";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/155X_extracted_opaque_reference_expires_with_domain" {
    try buildExpectFail(
        "tests/feature_tests/ownership/155X_extracted_opaque_reference_expires_with_domain",
        "reference depends on a root that has ended",
    );
}

test "feature_tests/ownership/156_fresh_opaque_extraction_after_refresh" {
    const test_path = "tests/feature_tests/ownership/156_fresh_opaque_extraction_after_refresh";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/157X_opaque_aggregate_extraction_preserves_domain_dependency" {
    try buildExpectFail(
        "tests/feature_tests/ownership/157X_opaque_aggregate_extraction_preserves_domain_dependency",
        "reference depends on a root that has ended",
    );
}

test "feature_tests/ownership/158_live_opaque_extraction_is_usable" {
    const test_path = "tests/feature_tests/ownership/158_live_opaque_extraction_is_usable";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/159X_opaque_read_generation_survives_wrapper" {
    try buildExpectFail(
        "tests/feature_tests/ownership/159X_opaque_read_generation_survives_wrapper",
        "reference depends on a root that has ended",
    );
}

test "feature_tests/ownership/160X_opaque_read_generation_survives_double_wrapper" {
    try buildExpectFail(
        "tests/feature_tests/ownership/160X_opaque_read_generation_survives_double_wrapper",
        "reference depends on a root that has ended",
    );
}

test "feature_tests/ownership/161_fresh_opaque_wrapper_extraction_after_refresh" {
    const test_path = "tests/feature_tests/ownership/161_fresh_opaque_wrapper_extraction_after_refresh";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/162X_opaque_read_through_identity_wrapper_keeps_generation" {
    try buildExpectFail(
        "tests/feature_tests/ownership/162X_opaque_read_through_identity_wrapper_keeps_generation",
        "reference depends on a root that has ended",
    );
}

test "feature_tests/ownership/163X_stale_pointer_use_through_wrapper_fails" {
    try buildExpectFail(
        "tests/feature_tests/ownership/163X_stale_pointer_use_through_wrapper_fails",
        "reference depends on a root that has ended",
    );
}

test "feature_tests/ownership/164_stale_pointer_identity_is_allowed" {
    const test_path = "tests/feature_tests/ownership/164_stale_pointer_identity_is_allowed";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/165X_stale_pointer_use_through_double_wrapper_fails" {
    try buildExpectFail(
        "tests/feature_tests/ownership/165X_stale_pointer_use_through_double_wrapper_fails",
        "reference depends on a root that has ended",
    );
}

test "feature_tests/ownership/166_fresh_pointer_use_through_wrapper" {
    const test_path = "tests/feature_tests/ownership/166_fresh_pointer_use_through_wrapper";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/167X_stale_array_pointer_use_through_wrapper_fails" {
    try buildExpectFail(
        "tests/feature_tests/ownership/167X_stale_array_pointer_use_through_wrapper_fails",
        "reference depends on a root that has ended",
    );
}

test "feature_tests/ownership/168X_nested_pointer_use_precondition_keeps_projection" {
    try buildExpectFail(
        "tests/feature_tests/ownership/168X_nested_pointer_use_precondition_keeps_projection",
        "reference depends on a root that has ended",
    );
}

test "feature_tests/ownership/169X_struct_field_write_through_stale_pointer_fails" {
    try buildExpectFail(
        "tests/feature_tests/ownership/169X_struct_field_write_through_stale_pointer_fails",
        "reference depends on a root that has ended",
    );
}

test "feature_tests/ownership/170_struct_field_write_through_live_pointer_wrapper" {
    const test_path = "tests/feature_tests/ownership/170_struct_field_write_through_live_pointer_wrapper";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/171X_struct_field_write_through_stale_pointer_wrapper_fails" {
    try buildExpectFail(
        "tests/feature_tests/ownership/171X_struct_field_write_through_stale_pointer_wrapper_fails",
        "reference depends on a root that has ended",
    );
}

test "feature_tests/ownership/172X_nested_struct_field_write_precondition_keeps_projection" {
    try buildExpectFail(
        "tests/feature_tests/ownership/172X_nested_struct_field_write_precondition_keeps_projection",
        "reference depends on a root that has ended",
    );
}

test "feature_tests/ownership/173X_opaque_drop_all_still_blocks_root_end" {
    try buildExpectFail(
        "tests/feature_tests/ownership/173X_opaque_drop_all_still_blocks_root_end",
        "cannot end a root while opaque storage hides a dependency on it",
    );
}

test "feature_tests/ownership/174_opaque_mark_empty_allows_root_end" {
    const test_path = "tests/feature_tests/ownership/174_opaque_mark_empty_allows_root_end";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/175X_opaque_release_one_domain_keeps_other_hidden" {
    try buildExpectFail(
        "tests/feature_tests/ownership/175X_opaque_release_one_domain_keeps_other_hidden",
        "cannot end a root while opaque storage hides a dependency on it",
    );
}

test "feature_tests/ownership/176_opaque_release_each_domain_allows_root_end" {
    const test_path = "tests/feature_tests/ownership/176_opaque_release_each_domain_allows_root_end";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/177_opaque_mark_empty_wrapper" {
    const test_path = "tests/feature_tests/ownership/177_opaque_mark_empty_wrapper";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/178_opaque_mark_empty_double_wrapper" {
    const test_path = "tests/feature_tests/ownership/178_opaque_mark_empty_double_wrapper";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/179X_opaque_mark_empty_projected_domain_is_exact" {
    try buildExpectFail(
        "tests/feature_tests/ownership/179X_opaque_mark_empty_projected_domain_is_exact",
        "cannot end a root while opaque storage hides a dependency on it",
    );
}

test "feature_tests/ownership/180_opaque_mark_empty_keeps_extracted_reference_live" {
    const test_path = "tests/feature_tests/ownership/180_opaque_mark_empty_keeps_extracted_reference_live";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/181X_fake_opaque_mark_empty_name" {
    try buildExpectFail(
        "tests/feature_tests/ownership/181X_fake_opaque_mark_empty_name",
        "cannot end a root while opaque storage hides a dependency on it",
    );
}

test "feature_tests/ownership/182X_opaque_release_after_early_return_is_not_definite" {
    try buildExpectFail(
        "tests/feature_tests/ownership/182X_opaque_release_after_early_return_is_not_definite",
        "cannot end a root while opaque storage hides a dependency on it",
    );
}

test "feature_tests/ownership/183X_opaque_write_after_release_repopulates_domain" {
    try buildExpectFail(
        "tests/feature_tests/ownership/183X_opaque_write_after_release_repopulates_domain",
        "cannot end a root while opaque storage hides a dependency on it",
    );
}

test "feature_tests/ownership/184_opaque_release_in_both_branches_is_definite" {
    const test_path = "tests/feature_tests/ownership/184_opaque_release_in_both_branches_is_definite";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/185X_opaque_release_in_one_branch_is_not_definite" {
    try buildExpectFail(
        "tests/feature_tests/ownership/185X_opaque_release_in_one_branch_is_not_definite",
        "cannot end a root while opaque storage hides a dependency on it",
    );
}

test "feature_tests/ownership/186_opaque_release_after_write_is_definite" {
    const test_path = "tests/feature_tests/ownership/186_opaque_release_after_write_is_definite";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/187X_opaque_release_then_write_double_wrapper_repopulates" {
    try buildExpectFail(
        "tests/feature_tests/ownership/187X_opaque_release_then_write_double_wrapper_repopulates",
        "cannot end a root while opaque storage hides a dependency on it",
    );
}

test "feature_tests/ownership/188_opaque_write_then_release_double_wrapper_is_definite" {
    const test_path = "tests/feature_tests/ownership/188_opaque_write_then_release_double_wrapper_is_definite";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/189X_opaque_pointer_assignment_after_release_repopulates" {
    try buildExpectFail(
        "tests/feature_tests/ownership/189X_opaque_pointer_assignment_after_release_repopulates",
        "cannot end a root while opaque storage hides a dependency on it",
    );
}

test "feature_tests/ownership/190X_opaque_repopulation_inside_initializer_cancels_release" {
    try buildExpectFail(
        "tests/feature_tests/ownership/190X_opaque_repopulation_inside_initializer_cancels_release",
        "cannot end a root while opaque storage hides a dependency on it",
    );
}

test "feature_tests/ownership/191X_opaque_repopulation_inside_return_expression_cancels_release" {
    try buildExpectFail(
        "tests/feature_tests/ownership/191X_opaque_repopulation_inside_return_expression_cancels_release",
        "cannot end a root while opaque storage hides a dependency on it",
    );
}

test "feature_tests/ownership/192X_opaque_repopulation_inside_nested_argument_cancels_release" {
    try buildExpectFail(
        "tests/feature_tests/ownership/192X_opaque_repopulation_inside_nested_argument_cancels_release",
        "cannot end a root while opaque storage hides a dependency on it",
    );
}

test "feature_tests/ownership/193_opaque_release_inside_initializer_is_definite" {
    const test_path = "tests/feature_tests/ownership/193_opaque_release_inside_initializer_is_definite";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/194X_opaque_release_in_short_circuit_rhs_is_not_definite" {
    try buildExpectFail(
        "tests/feature_tests/ownership/194X_opaque_release_in_short_circuit_rhs_is_not_definite",
        "cannot end a root while opaque storage hides a dependency on it",
    );
}

test "feature_tests/ownership/195X_opaque_repopulation_in_short_circuit_rhs_cancels_release" {
    try buildExpectFail(
        "tests/feature_tests/ownership/195X_opaque_repopulation_in_short_circuit_rhs_cancels_release",
        "cannot end a root while opaque storage hides a dependency on it",
    );
}

test "feature_tests/ownership/196X_opaque_expression_order_release_then_repopulate" {
    try buildExpectFail(
        "tests/feature_tests/ownership/196X_opaque_expression_order_release_then_repopulate",
        "cannot end a root while opaque storage hides a dependency on it",
    );
}

test "feature_tests/ownership/197_opaque_expression_order_repopulate_then_release" {
    const test_path = "tests/feature_tests/ownership/197_opaque_expression_order_repopulate_then_release";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/198X_nested_call_post_state_repopulates_with_new_root" {
    try buildExpectFail(
        "tests/feature_tests/ownership/198X_nested_call_post_state_repopulates_with_new_root",
        "cannot end a root while opaque storage hides a dependency on it",
    );
}

test "feature_tests/ownership/199X_nested_initializer_propagates_input_post_state" {
    try buildExpectFail(
        "tests/feature_tests/ownership/199X_nested_initializer_propagates_input_post_state",
        "reference depends on a root that has ended",
    );
}

test "feature_tests/ownership/200X_return_expression_propagates_input_post_state" {
    try buildExpectFail(
        "tests/feature_tests/ownership/200X_return_expression_propagates_input_post_state",
        "reference depends on a root that has ended",
    );
}

test "feature_tests/ownership/201X_nested_argument_propagates_input_post_state" {
    try buildExpectFail(
        "tests/feature_tests/ownership/201X_nested_argument_propagates_input_post_state",
        "reference depends on a root that has ended",
    );
}

test "feature_tests/ownership/202X_conditional_expression_joins_input_post_state" {
    try buildExpectFail(
        "tests/feature_tests/ownership/202X_conditional_expression_joins_input_post_state",
        "place rooted at 'allocation' is maybe_initialized and cannot be used",
    );
}

test "feature_tests/ownership/203_auto_deinit_applies_opaque_release_summary" {
    const test_path = "tests/feature_tests/ownership/203_auto_deinit_applies_opaque_release_summary";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/204X_auto_deinit_respects_required_live_inputs" {
    try buildExpectFail(
        "tests/feature_tests/ownership/204X_auto_deinit_respects_required_live_inputs",
        "reference depends on a root that has ended",
    );
}

test "feature_tests/ownership/205_structural_auto_deinit_applies_field_summary" {
    const test_path = "tests/feature_tests/ownership/205_structural_auto_deinit_applies_field_summary";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/206_auto_deinit_release_propagates_through_wrapper" {
    const test_path = "tests/feature_tests/ownership/206_auto_deinit_release_propagates_through_wrapper";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/207X_auto_deinit_input_post_state_propagates_through_wrapper" {
    try buildExpectFailExact("tests/feature_tests/ownership/207X_auto_deinit_input_post_state_propagates_through_wrapper",
        \\tests/feature_tests/ownership/207X_auto_deinit_input_post_state_propagates_through_wrapper/main.rg:31:41: error: reference depends on a root that has ended
        \\                      observed ::= holder.reference&
        \\                                          ^
        \\
    );
}

test "feature_tests/ownership/208_structural_auto_deinit_effects_propagate_through_wrapper" {
    const test_path = "tests/feature_tests/ownership/208_structural_auto_deinit_effects_propagate_through_wrapper";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/209X_input_post_state_before_early_return_is_preserved" {
    try buildExpectFail(
        "tests/feature_tests/ownership/209X_input_post_state_before_early_return_is_preserved",
        "reference depends on a root that has ended",
    );
}

test "feature_tests/ownership/210_identical_return_post_states_remain_precise" {
    const test_path = "tests/feature_tests/ownership/210_identical_return_post_states_remain_precise";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/211X_distinct_return_post_states_are_joined" {
    try buildExpectFail(
        "tests/feature_tests/ownership/211X_distinct_return_post_states_are_joined",
        "reference depends on a root that has ended",
    );
}

test "feature_tests/ownership/212X_structural_auto_deinit_respects_required_live_inputs" {
    try buildExpectFail(
        "tests/feature_tests/ownership/212X_structural_auto_deinit_respects_required_live_inputs",
        "reference depends on a root that has ended",
    );
}

test "feature_tests/ownership/213_conditional_opaque_consumption_into_known_storage" {
    const test_path = "tests/feature_tests/ownership/213_conditional_opaque_consumption_into_known_storage";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/214X_conditional_opaque_consumption_invalidates_source" {
    try buildExpectFail(
        "tests/feature_tests/ownership/214X_conditional_opaque_consumption_invalidates_source",
        "place rooted at 'source' is moved and cannot be used",
    );
}

test "feature_tests/ownership/215X_conditional_opaque_consumption_hides_dependencies" {
    try buildExpectFail(
        "tests/feature_tests/ownership/215X_conditional_opaque_consumption_hides_dependencies",
        "opaque storage hides a dependency",
    );
}

test "feature_tests/ownership/216_conditional_opaque_consumption_then_release" {
    const test_path = "tests/feature_tests/ownership/216_conditional_opaque_consumption_then_release";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/217X_conditional_opaque_reference_source_hides_dependencies" {
    try buildExpectFail(
        "tests/feature_tests/ownership/217X_conditional_opaque_reference_source_hides_dependencies",
        "opaque storage hides a dependency",
    );
}

test "feature_tests/ownership/218X_conditional_opaque_reference_source_closes_owned_roots" {
    try buildExpectFail(
        "tests/feature_tests/ownership/218X_conditional_opaque_reference_source_closes_owned_roots",
        "opaque ownership storage requires no live external aliases to the consumed root",
    );
}

test "feature_tests/ownership/43X_inferred_cleanup_ends_internal_root" {
    try buildExpectFailExact("tests/feature_tests/ownership/43X_inferred_cleanup_ends_internal_root",
        \\tests/feature_tests/ownership/43X_inferred_cleanup_ends_internal_root/main.rg:21:8: error: reference depends on a root that has ended
        \\      if alias& == 0 {
        \\         ^
        \\
    );
}

test "feature_tests/ownership/44_cross_root_cycle_survivor_remains_usable" {
    try expectSuccessfulBuild("tests/feature_tests/ownership/44_cross_root_cycle_survivor_remains_usable");
}

test "feature_tests/ownership/45X_cross_root_cycle_stale_edge" {
    try buildExpectFailExact("tests/feature_tests/ownership/45X_cross_root_cycle_stale_edge",
        \\tests/feature_tests/ownership/45X_cross_root_cycle_stale_edge/main.rg:15:10: error: reference depends on a root that has ended
        \\      if b.to_a& == 0 {
        \\           ^
        \\
    );
}

test "feature_tests/ownership/46_deinitialized_place_can_be_replaced" {
    try expectSuccessfulBuild("tests/feature_tests/ownership/46_deinitialized_place_can_be_replaced");
}

test "feature_tests/ownership/47X_integer_roundtrip_has_no_safe_provenance" {
    try buildExpectFailExact("tests/feature_tests/ownership/47X_integer_roundtrip_has_no_safe_provenance",
        \\tests/feature_tests/ownership/47X_integer_roundtrip_has_no_safe_provenance/main.rg:4:23: error: no function named 'cast' exists
        \\      reference ::= cast#(.to: $&Int32)(.value = address)
        \\                        ^
        \\
    );
}

test "feature_tests/ownership/48_structural_field_move" {
    const test_path = "tests/feature_tests/ownership/48_structural_field_move";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/49X_structural_field_use_after_move" {
    try buildExpectFailExact("tests/feature_tests/ownership/49X_structural_field_use_after_move",
        \\tests/feature_tests/ownership/49X_structural_field_use_after_move/main.rg:13:24: error: place rooted at 'pair' is moved and cannot be used (moved at tests/feature_tests/ownership/49X_structural_field_use_after_move/main.rg:12:32)
        \\      status_code = pair.left + pair.right - moved
        \\                         ^
        \\
    );
}

test "feature_tests/ownership/50X_branch_may_move_value" {
    try buildExpectFailExact("tests/feature_tests/ownership/50X_branch_may_move_value",
        \\tests/feature_tests/ownership/50X_branch_may_move_value/main.rg:9:24: error: place rooted at 'pair' is moved and cannot be used (moved at tests/feature_tests/ownership/50X_branch_may_move_value/main.rg:7:26)
        \\      status_code = pair.left
        \\                         ^
        \\
    );
}

test "feature_tests/ownership/51X_loop_may_move_value" {
    try buildExpectFailExact("tests/feature_tests/ownership/51X_loop_may_move_value",
        \\tests/feature_tests/ownership/51X_loop_may_move_value/main.rg:7:32: error: place rooted at 'pair' is moved and cannot be used (moved at tests/feature_tests/ownership/51X_loop_may_move_value/main.rg:7:26)
        \\          consume(.value = ~pair.left)
        \\                                 ^
        \\
    );
}

test "feature_tests/ownership/52_user_primitive_name_has_no_authority" {
    const test_path = "tests/feature_tests/ownership/52_user_primitive_name_has_no_authority";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
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
    try buildExpectFailExact("tests/feature_tests/ownership/32X_array_of_noncopyable_is_not_copyable",
        \\tests/feature_tests/ownership/32X_array_of_noncopyable_is_not_copyable/main.rg:11:15: error: type '[2]Resource' cannot be copied implicitly; use '~value' to transfer ownership
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
    try buildExpectFailExact("tests/feature_tests/polymorphism/25X_abstract_overloads_with_defaults_ambiguous",
        \\tests/feature_tests/polymorphism/25X_abstract_overloads_with_defaults_ambiguous/main.rg:14:19: error: ambiguous call to 'pick' for arguments (.value: Int32). Possible overloads:
        \\  - pick (.value: A, .left: Int32) -> (.status_code: Int32)
        \\  - pick (.value: A, .right: Int32) -> (.status_code: Int32)
        \\      status_code = pick(.value = 7).status_code
        \\                    ^
        \\
    );
}

test "feature_tests/polymorphism/26_virtual_abstract_dispatch" {
    const test_path = "tests/feature_tests/polymorphism/26_virtual_abstract_dispatch";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/polymorphism/27_virtual_allocator_dispatch" {
    const test_path = "tests/feature_tests/polymorphism/27_virtual_allocator_dispatch";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/polymorphism/28_virtual_foundation" {
    const test_path = "tests/feature_tests/polymorphism/28_virtual_foundation";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/polymorphism/29X_virtual_dependency_escape" {
    try buildExpectFail(
        "tests/feature_tests/polymorphism/29X_virtual_dependency_escape",
        "function output cannot depend on a local storage generation that ends before return",
    );
}

test "feature_tests/polymorphism/30X_virtual_dependency_union" {
    try buildExpectFail(
        "tests/feature_tests/polymorphism/30X_virtual_dependency_union",
        "function output cannot depend on a local storage generation that ends before return",
    );
}

test "feature_tests/polymorphism/31X_virtual_incompatible_deinit" {
    try buildExpectFail(
        "tests/feature_tests/polymorphism/31X_virtual_incompatible_deinit",
        "cannot form Virtual value because an Abstract method has incompatible safety effects across implementations",
    );
}

test "feature_tests/polymorphism/37_virtual_nested_receiver_borrow" {
    const test_path = "tests/feature_tests/polymorphism/37_virtual_nested_receiver_borrow";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/polymorphism/38X_virtual_nested_receiver_ended" {
    try buildExpectFail(
        "tests/feature_tests/polymorphism/38X_virtual_nested_receiver_ended",
        "reference depends on a root that has ended",
    );
}

test "feature_tests/polymorphism/39_virtual_scalar_move" {
    const test_path = "tests/feature_tests/polymorphism/39_virtual_scalar_move";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/polymorphism/40X_virtual_nested_aggregate_borrow" {
    try buildExpectFail(
        "tests/feature_tests/polymorphism/40X_virtual_nested_aggregate_borrow",
        "reference depends on a root that has ended",
    );
}

test "feature_tests/ownership/219_virtual_post_state_allows_optional_self_mutation" {
    const test_path = "tests/feature_tests/ownership/219_virtual_post_state_allows_optional_self_mutation";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/220X_virtual_post_state_dependency_union" {
    try buildExpectFail(
        "tests/feature_tests/ownership/220X_virtual_post_state_dependency_union",
        "reference depends on a root that has ended",
    );
}

test "feature_tests/ownership/221X_virtual_post_state_initializedness_join" {
    try buildExpectFail(
        "tests/feature_tests/ownership/221X_virtual_post_state_initializedness_join",
        "cannot form Virtual value because an Abstract method has incompatible safety effects across implementations",
    );
}

test "feature_tests/ownership/222X_virtual_conditional_opaque_ownership_same_storage" {
    try buildExpectFail(
        "tests/feature_tests/ownership/222X_virtual_conditional_opaque_ownership_same_storage",
        "cannot form Virtual value because an Abstract method has incompatible safety effects across implementations",
    );
}

test "feature_tests/ownership/222X_virtual_conditional_opaque_ownership_same_storage_invalidates_source" {
    try buildExpectFail(
        "tests/feature_tests/ownership/222X_virtual_conditional_opaque_ownership_same_storage_invalidates_source",
        "cannot form Virtual value because an Abstract method has incompatible safety effects across implementations",
    );
}

test "feature_tests/ownership/223X_virtual_opaque_ownership_different_storages_incompatible" {
    try buildExpectFail(
        "tests/feature_tests/ownership/223X_virtual_opaque_ownership_different_storages_incompatible",
        "cannot form Virtual value because an Abstract method has incompatible safety effects across implementations",
    );
}

test "feature_tests/ownership/224X_virtual_definite_self_destruction_incompatible" {
    try buildExpectFail(
        "tests/feature_tests/ownership/224X_virtual_definite_self_destruction_incompatible",
        "cannot form Virtual value because an Abstract method has incompatible safety effects across implementations",
    );
}

test "feature_tests/ownership/225X_virtual_receiver_uses_self_input_index" {
    try buildExpectFail(
        "tests/feature_tests/ownership/225X_virtual_receiver_uses_self_input_index",
        "reference depends on a root that has ended",
    );
}

test "feature_tests/ownership/226X_virtual_conditional_opaque_ownership_drop_state_incompatible" {
    try buildExpectFail(
        "tests/feature_tests/ownership/226X_virtual_conditional_opaque_ownership_drop_state_incompatible",
        "cannot form Virtual value because an Abstract method has incompatible safety effects across implementations",
    );
}

test "feature_tests/ownership/227X_virtual_definite_opaque_ownership_drop_state_incompatible" {
    try buildExpectFail(
        "tests/feature_tests/ownership/227X_virtual_definite_opaque_ownership_drop_state_incompatible",
        "cannot form Virtual value because an Abstract method has incompatible safety effects across implementations",
    );
}

test "feature_tests/ownership/228_virtual_mutation_preserves_existing_alias" {
    const test_path = "tests/feature_tests/ownership/228_virtual_mutation_preserves_existing_alias";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/229_virtual_mutation_preserves_stored_reference" {
    const test_path = "tests/feature_tests/ownership/229_virtual_mutation_preserves_stored_reference";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/230_virtual_unchanged_alternative_preserves_pointee_facts" {
    const test_path = "tests/feature_tests/ownership/230_virtual_unchanged_alternative_preserves_pointee_facts";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/231X_control_flow_unchanged_preserves_pointee_dependencies" {
    try buildExpectFail(
        "tests/feature_tests/ownership/231X_control_flow_unchanged_preserves_pointee_dependencies",
        "reference depends on a root that has ended",
    );
}

test "feature_tests/ownership/232X_opaque_effect_instantiates_input_place_value_dependencies" {
    try buildExpectFail(
        "tests/feature_tests/ownership/232X_opaque_effect_instantiates_input_place_value_dependencies",
        "cannot end a root while opaque storage hides a dependency on it",
    );
}

test "feature_tests/ownership/233_opaque_effect_input_place_value_mark_empty" {
    const test_path = "tests/feature_tests/ownership/233_opaque_effect_input_place_value_mark_empty";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/types/234_known_choice_literal_payload" {
    const test_path = "tests/feature_tests/types/234_known_choice_literal_payload";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/types/235X_wrong_known_choice_literal_payload" {
    try buildExpectFail(
        "tests/feature_tests/types/235X_wrong_known_choice_literal_payload",
        "choice payload '..0' is not active",
    );
}

test "feature_tests/types/236_choice_equality_refines_payload" {
    const test_path = "tests/feature_tests/types/236_choice_equality_refines_payload";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/types/237_choice_inequality_refines_remaining_payload" {
    const test_path = "tests/feature_tests/types/237_choice_inequality_refines_remaining_payload";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/types/237X_choice_inequality_does_not_over_refine" {
    try buildExpectFail(
        "tests/feature_tests/types/237X_choice_inequality_does_not_over_refine",
        "choice payload '..0' is not active",
    );
}

test "feature_tests/types/238_choice_join_preserves_same_variant" {
    const test_path = "tests/feature_tests/types/238_choice_join_preserves_same_variant";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/types/239X_choice_join_different_variants_is_unknown" {
    try buildExpectFail(
        "tests/feature_tests/types/239X_choice_join_different_variants_is_unknown",
        "choice payload '..0' requires its variant to be proven active",
    );
}

test "feature_tests/types/240_match_temporary_refines_payload" {
    const test_path = "tests/feature_tests/types/240_match_temporary_refines_payload";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/types/241X_choice_reassignment_invalidates_refinement" {
    try buildExpectFail(
        "tests/feature_tests/types/241X_choice_reassignment_invalidates_refinement",
        "choice payload '..0' is not active",
    );
}

test "feature_tests/types/242_choice_move_preserves_known_variant" {
    const test_path = "tests/feature_tests/types/242_choice_move_preserves_known_variant";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/types/242X_choice_move_invalidates_source" {
    try buildExpectFail(
        "tests/feature_tests/types/242X_choice_move_invalidates_source",
        "choice payload '..0' requires its variant to be proven active",
    );
}

test "feature_tests/types/243_choice_field_preserves_known_variant" {
    const test_path = "tests/feature_tests/types/243_choice_field_preserves_known_variant";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/types/244_choice_refinement_survives_breaking_branch" {
    const test_path = "tests/feature_tests/types/244_choice_refinement_survives_breaking_branch";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/types/245_function_output_preserves_known_choice_variant" {
    const test_path = "tests/feature_tests/types/245_function_output_preserves_known_choice_variant";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/types/246X_choice_literal_payload_preserves_reference_dependency" {
    try buildExpectFail(
        "tests/feature_tests/types/246X_choice_literal_payload_preserves_reference_dependency",
        "reference depends on a root that has ended",
    );
}

test "feature_tests/types/247X_choice_literal_payload_move_consumes_source" {
    try buildExpectFail(
        "tests/feature_tests/types/247X_choice_literal_payload_move_consumes_source",
        "reference depends on a root that has ended",
    );
}

test "feature_tests/types/248_choice_payload_mutation_preserves_parent_tag" {
    const test_path = "tests/feature_tests/types/248_choice_payload_mutation_preserves_parent_tag";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/types/249_choice_sibling_mutation_preserves_tag" {
    const test_path = "tests/feature_tests/types/249_choice_sibling_mutation_preserves_tag";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/types/250X_choice_field_overwrite_invalidates_tag" {
    try buildExpectFail(
        "tests/feature_tests/types/250X_choice_field_overwrite_invalidates_tag",
        "choice payload '..0' is not active",
    );
}

test "feature_tests/types/251X_choice_parent_overwrite_invalidates_tag" {
    try buildExpectFail(
        "tests/feature_tests/types/251X_choice_parent_overwrite_invalidates_tag",
        "choice payload '..0' is not active",
    );
}

test "feature_tests/types/252X_choice_payload_integer_address_rejected_on_use" {
    try buildExpectFail(
        "tests/feature_tests/types/252X_choice_payload_integer_address_rejected_on_use",
        "no function named 'cast' exists",
    );
}

test "feature_tests/types/253X_choice_payload_integer_address_rejected_across_call" {
    try buildExpectFail(
        "tests/feature_tests/types/253X_choice_payload_integer_address_rejected_across_call",
        "no function named 'cast' exists",
    );
}

test "feature_tests/types/254_choice_union" {
    const test_path = "tests/feature_tests/types/254_choice_union";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/types/255X_conflicting_abstract_associated_args" {
    try buildExpectFail(
        "tests/feature_tests/types/255X_conflicting_abstract_associated_args",
        "conflicting implementations of abstract 'Capability' for type 'Thing' produce different associated arguments",
    );
}

test "feature_tests/types/256X_abstract_associated_arg_mismatch" {
    try buildExpectFail(
        "tests/feature_tests/types/256X_abstract_associated_arg_mismatch",
        "abstract constraint 'Capability' required by generic function parameter '.t' of 'require_uint'",
    );
}

test "feature_tests/types/257X_abstract_impl_template_checks_associated_args" {
    try buildExpectFail(
        "tests/feature_tests/types/257X_abstract_impl_template_checks_associated_args",
        "abstract constraint 'Other' required by generic function parameter '.t' of 'require_other'",
    );
}

test "feature_tests/types/258_abstract_associated_comptime_values" {
    const test_path = "tests/feature_tests/types/258_abstract_associated_comptime_values";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/types/259X_abstract_associated_comptime_mismatch" {
    try buildExpectFail(
        "tests/feature_tests/types/259X_abstract_associated_comptime_mismatch",
        "abstract constraint 'AbstractMatrix' required by generic function parameter '.t' of 'require_four_rows'",
    );
}

test "feature_tests/ownership/254X_reinitializing_alias_does_not_refresh_sibling" {
    try buildExpectFail(
        "tests/feature_tests/ownership/254X_reinitializing_alias_does_not_refresh_sibling",
        "reference depends on a root that has ended",
    );
}

test "feature_tests/ownership/255_live_pointer_assignment_preserves_sibling_alias" {
    const test_path = "tests/feature_tests/ownership/255_live_pointer_assignment_preserves_sibling_alias";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/256_function_reinitializing_alias_refreshes_itself" {
    const test_path = "tests/feature_tests/ownership/256_function_reinitializing_alias_refreshes_itself";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/257X_function_reinitializing_alias_keeps_sibling_stale" {
    try buildExpectFail(
        "tests/feature_tests/ownership/257X_function_reinitializing_alias_keeps_sibling_stale",
        "reference depends on a root that has ended",
    );
}

test "feature_tests/ownership/258_function_live_write_preserves_sibling_alias" {
    const test_path = "tests/feature_tests/ownership/258_function_live_write_preserves_sibling_alias";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/259_loop_owned_generation_join" {
    const test_path = "tests/feature_tests/ownership/259_loop_owned_generation_join";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/260X_loop_owned_generation_keeps_old_alias_stale" {
    try buildExpectFail(
        "tests/feature_tests/ownership/260X_loop_owned_generation_keeps_old_alias_stale",
        "reference depends on a root that has ended",
    );
}

test "feature_tests/ownership/261_loop_owned_generation_allows_fresh_alias" {
    const test_path = "tests/feature_tests/ownership/261_loop_owned_generation_allows_fresh_alias";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/262_loop_owned_generation_preserves_sibling" {
    const test_path = "tests/feature_tests/ownership/262_loop_owned_generation_preserves_sibling";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/263_loop_optional_owned_generation" {
    const test_path = "tests/feature_tests/ownership/263_loop_optional_owned_generation";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/264_loop_local_storage" {
    const test_path = "tests/feature_tests/ownership/264_loop_local_storage";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/265_loop_local_field_storage" {
    const test_path = "tests/feature_tests/ownership/265_loop_local_field_storage";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/266X_loop_local_storage_escape" {
    try buildExpectFail(
        "tests/feature_tests/ownership/266X_loop_local_storage_escape",
        "reference depends on a root that has ended",
    );
}

test "feature_tests/ownership/267X_loop_local_storage_escape_break" {
    try buildExpectFail(
        "tests/feature_tests/ownership/267X_loop_local_storage_escape_break",
        "reference depends on a root that has ended",
    );
}

test "feature_tests/ownership/268X_loop_local_storage_escape_continue" {
    try buildExpectFail(
        "tests/feature_tests/ownership/268X_loop_local_storage_escape_continue",
        "reference depends on a root that has ended",
    );
}

test "feature_tests/ownership/269_loop_local_owning_cleanup" {
    const test_path = "tests/feature_tests/ownership/269_loop_local_owning_cleanup";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/270_return_local_storage" {
    try expectSuccessfulBuild("tests/feature_tests/ownership/270_return_local_storage");
    try runExpect("tests/feature_tests/ownership/270_return_local_storage", 1);
}

test "feature_tests/ownership/271X_opaque_external_dependency_direct" {
    try buildExpectFail(
        "tests/feature_tests/ownership/271X_opaque_external_dependency_direct",
        "cannot end a root while opaque storage hides a dependency on it",
    );
}

test "feature_tests/ownership/272X_opaque_external_dependency_wrapper" {
    try buildExpectFail(
        "tests/feature_tests/ownership/272X_opaque_external_dependency_wrapper",
        "cannot end a root while opaque storage hides a dependency on it",
    );
}

test "feature_tests/ownership/273X_opaque_external_dependency_nested_wrapper" {
    try buildExpectFail(
        "tests/feature_tests/ownership/273X_opaque_external_dependency_nested_wrapper",
        "cannot end a root while opaque storage hides a dependency on it",
    );
}

test "feature_tests/ownership/274_opaque_external_dependency_release" {
    const test_path = "tests/feature_tests/ownership/274_opaque_external_dependency_release";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/275_opaque_wrapper_self_contained_owner" {
    const test_path = "tests/feature_tests/ownership/275_opaque_wrapper_self_contained_owner";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/276X_opaque_move_out_preserves_external_dependency" {
    try buildExpectFail(
        "tests/feature_tests/ownership/276X_opaque_move_out_preserves_external_dependency",
        "reference depends on a root that has ended",
    );
}

test "feature_tests/ownership/277_implicit_scalar_copy" {
    const test_path = "tests/feature_tests/ownership/277_implicit_scalar_copy";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/278_implicit_struct_copy" {
    const test_path = "tests/feature_tests/ownership/278_implicit_struct_copy";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/279X_infallible_copy_is_not_implicit" {
    try buildExpectFail(
        "tests/feature_tests/ownership/279X_infallible_copy_is_not_implicit",
        "type 'LargeValue' cannot be copied implicitly",
    );
}

test "feature_tests/ownership/280_explicit_infallible_copy" {
    const test_path = "tests/feature_tests/ownership/280_explicit_infallible_copy";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/281X_fallible_copy_is_not_implicit" {
    try buildExpectFail(
        "tests/feature_tests/ownership/281X_fallible_copy_is_not_implicit",
        "type 'FallibleValue' cannot be copied implicitly",
    );
}

test "feature_tests/ownership/282_explicit_fallible_copy" {
    const test_path = "tests/feature_tests/ownership/282_explicit_fallible_copy";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/283_scalar_opaque_read_is_independent" {
    const test_path = "tests/feature_tests/ownership/283_scalar_opaque_read_is_independent";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/284X_integer_cannot_establish_any_reference" {
    try buildExpectFail(
        "tests/feature_tests/ownership/284X_integer_cannot_establish_any_reference",
        "no function named 'cast' exists",
    );
}

test "feature_tests/ownership/285_reference_can_erase_to_any" {
    const test_path = "tests/feature_tests/ownership/285_reference_can_erase_to_any";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/286X_uninitialized_allocation_read" {
    try buildExpectFail(
        "tests/feature_tests/ownership/286X_uninitialized_allocation_read",
        "is not dereferenceable; expected '&T' or '$&T'",
    );
}

test "feature_tests/ownership/287X_aggregate_copy_after_projected_reference_write" {
    try buildExpectFail(
        "tests/feature_tests/ownership/287X_aggregate_copy_after_projected_reference_write",
        "reference depends on a root that has ended",
    );
}

test "feature_tests/ownership/288X_aggregate_read_after_field_move" {
    try buildExpectFail(
        "tests/feature_tests/ownership/288X_aggregate_read_after_field_move",
        "place rooted at 'pair' is moved and cannot be used",
    );
}

test "feature_tests/ownership/289_aggregate_copy_after_field_replacement" {
    const test_path = "tests/feature_tests/ownership/289_aggregate_copy_after_field_replacement";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/290_aggregate_copy_after_disjoint_branch_writes" {
    const test_path = "tests/feature_tests/ownership/290_aggregate_copy_after_disjoint_branch_writes";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/291X_aggregate_read_after_field_deinit" {
    try buildExpectFail(
        "tests/feature_tests/ownership/291X_aggregate_read_after_field_deinit",
        "value was deinitialized",
    );
}

test "feature_tests/ownership/292X_nested_aggregate_copy_after_projected_write" {
    try buildExpectFail(
        "tests/feature_tests/ownership/292X_nested_aggregate_copy_after_projected_write",
        "reference depends on a root that has ended",
    );
}

test "feature_tests/polymorphism/32_static_abstract_generic_fields" {
    const test_path = "tests/feature_tests/polymorphism/32_static_abstract_generic_fields";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/polymorphism/33X_static_abstract_generic_field_requires_implementation" {
    try buildExpectFail(
        "tests/feature_tests/polymorphism/33X_static_abstract_generic_field_requires_implementation",
        "does not implement abstract 'Backend' required by generic type parameter '.backend_type' of 'Wrapper'",
    );
}

test "feature_tests/polymorphism/34X_static_abstract_generic_field_identity" {
    try buildExpectFail(
        "tests/feature_tests/polymorphism/34X_static_abstract_generic_field_identity",
        "no overload of 'accept_b' accepts arguments (.value: Wrapper#(.backend_type: BackendA))",
    );
}

test "feature_tests/polymorphism/35_generic_specialization_cache_nominal_identity" {
    const test_path = "tests/feature_tests/polymorphism/35_generic_specialization_cache_nominal_identity";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 12);
}

test "feature_tests/polymorphism/36_abstract_contract_choice_payload" {
    const test_path = "tests/feature_tests/polymorphism/36_abstract_contract_choice_payload";
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
    try runExpect(test_path, 42);
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

test "feature_tests/modules/25_inferred_errable_omitted_reasons_transitive" {
    const test_path = "tests/feature_tests/modules/25_inferred_errable_omitted_reasons_transitive";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 45);
}

test "feature_tests/modules/26_inferred_shorthand_omitted_reasons_transitive" {
    const test_path = "tests/feature_tests/modules/26_inferred_shorthand_omitted_reasons_transitive";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 46);
}

test "feature_tests/modules/03X_import_missing_module" {
    try buildExpectFailExact("tests/feature_tests/modules/03X_import_missing_module",
        \\cannot resolve import './missing_dep' from 'tests/feature_tests/modules/03X_import_missing_module/main.rg'
        \\Build error: FileNotFound
        \\
    );
}

test "feature_tests/modules/04X_import_missing_value" {
    try buildExpectFailExact("tests/feature_tests/modules/04X_import_missing_value",
        \\tests/feature_tests/modules/04X_import_missing_value/main.rg:3:19: error: module 'dep' has no value '.missing_value'
        \\      status_code = dep.missing_value
        \\                    ^
        \\
    );
}

test "feature_tests/modules/05X_import_missing_overload" {
    try buildExpectFailExact("tests/feature_tests/modules/05X_import_missing_overload",
        \\tests/feature_tests/modules/05X_import_missing_overload/main.rg:3:35: error: module 'dep' has no function named 'missing_func'
        \\      status_code = dep.missing_func()
        \\                                    ^
        \\
    );
}

test "feature_tests/modules/06X_private_module_value" {
    try buildExpectFailExact("tests/feature_tests/modules/06X_private_module_value",
        \\tests/feature_tests/modules/06X_private_module_value/main.rg:3:19: error: value '_hidden_value' is private to its module
        \\      status_code = dep._hidden_value
        \\                    ^
        \\
    );
}

test "feature_tests/modules/07X_private_module_type" {
    try buildExpectFailExact("tests/feature_tests/modules/07X_private_module_type",
        \\tests/feature_tests/modules/07X_private_module_type/main.rg:3:14: error: type '_HiddenStatus' is private to its module
        \\      hidden : dep._HiddenStatus = (.code = 0)
        \\               ^
        \\
    );
}

test "feature_tests/modules/08X_private_module_function" {
    try buildExpectFailExact("tests/feature_tests/modules/08X_private_module_function",
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
    try buildExpectFailExact("tests/feature_tests/modules/11X_import_cycle",
        \\import cycle detected: tests/feature_tests/modules/11X_import_cycle/dep_a -> tests/feature_tests/modules/11X_import_cycle/dep_b -> tests/feature_tests/modules/11X_import_cycle/dep_a
        \\Build error: ImportCycle
        \\
    );
}

test "feature_tests/modules/12X_import_requires_binding" {
    try buildExpectFailExact("tests/feature_tests/modules/12X_import_requires_binding",
        \\tests/feature_tests/modules/12X_import_requires_binding/main.rg:1:1: error: import must be assigned to a name
        \\  import("./dep")
        \\  ^
        \\
    );
}

test "feature_tests/modules/13X_import_requires_binding_nested" {
    try buildExpectFailExact("tests/feature_tests/modules/13X_import_requires_binding_nested",
        \\tests/feature_tests/modules/13X_import_requires_binding_nested/main.rg:3:9: error: import must be assigned to a name
        \\          import("./dep")
        \\          ^
        \\
    );
}

test "feature_tests/modules/30X_import_requires_parentheses" {
    try buildExpectFail("tests/feature_tests/modules/30X_import_requires_parentheses", "expected '(' after import");
}

test "feature_tests/modules/14X_missing_function_name" {
    try buildExpectFailExact("tests/feature_tests/modules/14X_missing_function_name",
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
    try buildExpectFailExact("tests/feature_tests/modules/16X_root_relative_missing_import/project/app",
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
    try buildExpectFailExact("tests/feature_tests/modules/19X_private_struct_field_imported",
        \\tests/feature_tests/modules/19X_private_struct_field_imported/main.rg:4:25: error: field '_hidden' is private to its module
        \\      status_code = point._hidden
        \\                          ^
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

test "feature_tests/modules/27_imported_abstract_qualified_signature" {
    const test_path = "tests/feature_tests/modules/27_imported_abstract_qualified_signature";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/modules/25X_private_choice_option_imported" {
    try buildExpectFailExact("tests/feature_tests/modules/25X_private_choice_option_imported",
        \\tests/feature_tests/modules/25X_private_choice_option_imported/main.rg:4:10: error: choice option '_hidden_reason' is private to its module
        \\      dep.._hidden_reason
        \\           ^
        \\
    );
}

test "feature_tests/modules/26X_module_qualified_ambiguous_overload" {
    try buildExpectFailExact("tests/feature_tests/modules/26X_module_qualified_ambiguous_overload",
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
    try buildExpectFailExact("tests/feature_tests/modules/29X_imported_abstract_ambiguous_overload",
        \\tests/feature_tests/modules/29X_imported_abstract_ambiguous_overload/main.rg:4:19: error: module-qualified call 'dep.pick' is ambiguous for arguments (.value: Int32). Possible overloads:
        \\  - pick (.value: A, .left: Int32) -> (.result: Int32)
        \\  - pick (.value: A, .right: Int32) -> (.result: Int32)
        \\      _ ::= dep.pick(.value = 1)
        \\                    ^
        \\
    );
}

test "feature_tests/modules/30X_nonconstant_module_binding_initialization" {
    try buildExpectFailExact("tests/feature_tests/modules/30X_nonconstant_module_binding_initialization",
        \\tests/feature_tests/modules/30X_nonconstant_module_binding_initialization/main.rg:5:1: error: module-level binding 'computed' must use a constant initializer for now
        \\  computed : Int32 = make_value().value
        \\  ^
        \\
    );
}

test "feature_tests/modules/31X_cyclic_module_binding_initialization" {
    try buildExpectFailExact("tests/feature_tests/modules/31X_cyclic_module_binding_initialization",
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
    var root = try std.Io.Dir.cwd().openDir(std.testing.io, compilerRoot(), .{});
    defer root.close(std.testing.io);

    root.deleteTree(std.testing.io, ".argi-cache/tests") catch |err| {
        if (err != error.FileNotFound) return err;
    };
    root.deleteTree(std.testing.io, "build/tests") catch |err| {
        if (err != error.FileNotFound) return err;
    };

    try argiTestExpectStderr(
        "tests/feature_tests/testing/01_simple_pass",
        &.{},
        0,
        "PASS simple_pass\n",
    );

    try root.access(std.testing.io, ".argi-cache/tests", .{});
    root.access(std.testing.io, "build/tests", .{}) catch |err| switch (err) {
        error.FileNotFound => {},
        else => return err,
    };
}

test "feature_tests/testing/01_simple_pass_cleans_module_test_cache" {
    const test_path = "tests/feature_tests/testing/01_simple_pass";
    const repo_root = try repoRootPrefix();
    defer std.testing.allocator.free(repo_root);

    const module_dir = try std.fs.path.join(std.testing.allocator, &.{ repo_root, test_path });
    defer std.testing.allocator.free(module_dir);

    const cache_dir = try argiTestCacheDirForModule(module_dir);
    defer std.testing.allocator.free(cache_dir);

    const stale_path = try std.fs.path.join(std.testing.allocator, &.{ cache_dir, "stale" });
    defer std.testing.allocator.free(stale_path);

    try std.Io.Dir.cwd().createDirPath(std.testing.io, cache_dir);
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{
        .sub_path = stale_path,
        .data = "stale test binary",
    });

    try argiTestExpectStderr(
        test_path,
        &.{},
        0,
        "PASS simple_pass\n",
    );

    std.Io.Dir.cwd().access(std.testing.io, stale_path, .{}) catch |err| switch (err) {
        error.FileNotFound => return,
        else => return err,
    };
    return error.StaleTestCacheSurvived;
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
        "tests must declare exactly one input: '.system: System'",
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

test "feature_tests/testing/12_language_regression_slice" {
    try argiTestExpectStderr(
        "tests/feature_tests/testing/12_language_regression_slice",
        &.{},
        0,
        "PASS language_regression_slice\n",
    );
}

test "feature_tests/testing/13_collections_text_regression_slice" {
    try argiTestExpectStderr(
        "tests/feature_tests/testing/13_collections_text_regression_slice",
        &.{},
        0,
        "PASS collections_text_array_slice\nPASS collections_text_format_slice\n",
    );
}

test "feature_tests/testing/14_core_path_regression_slice" {
    try argiTestExpectStderr(
        "tests/feature_tests/testing/14_core_path_regression_slice",
        &.{},
        0,
        "PASS core_path_regression_slice\n",
    );
}

test "feature_tests/testing/15_named_optional_view_return" {
    try argiTestExpectStderr(
        "tests/feature_tests/testing/15_named_optional_view_return",
        &.{},
        0,
        "PASS named_optional_view_return\n",
    );
}

test "argi help lists supported commands" {
    const result = try runArgiCommand(&.{"help"});
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);

    try expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try expect(std.mem.indexOf(u8, result.stderr, "Usage: argi <command> [arguments] [options]\n") != null);
    try expect(std.mem.indexOf(u8, result.stderr, "build [path] [flags]") != null);
    try expect(std.mem.indexOf(u8, result.stderr, "run [executable] [build flags]") != null);
    try expect(std.mem.indexOf(u8, result.stderr, "test <directory> [flags]") != null);
    try expect(std.mem.indexOf(u8, result.stderr, "--sysroot <path>") != null);
    try expect(std.mem.indexOf(u8, result.stderr, "--exec <name>") != null);
    try expect(std.mem.indexOf(u8, result.stderr, "--filter <name>") != null);
    try expect(std.mem.indexOf(u8, result.stderr, "init [name]") != null);
    try expect(std.mem.indexOf(u8, result.stderr, "init --lib [name]") != null);
    try expect(std.mem.indexOf(u8, result.stderr, "lsp") != null);
    try expect(std.mem.indexOf(u8, result.stderr, "version") != null);
    try expect(std.mem.indexOf(u8, result.stderr, "format [paths...] [--check]") != null);
    try expect(std.mem.indexOf(u8, result.stderr, "format <file.rg> --stdout") != null);
}

test "argi version reports current release" {
    const result = try runArgiCommand(&.{"version"});
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);

    try expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try expectEqualStrings("argi 0.2.0\n", result.stderr);
}

test "argi unknown command exits with help" {
    const result = try runArgiCommand(&.{"unknown-command"});
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);

    try expectEqual(std.process.Child.Term{ .exited = 1 }, result.term);
    try expect(std.mem.indexOf(u8, result.stderr, "Error: unknown command 'unknown-command'\n") != null);
    try expect(std.mem.indexOf(u8, result.stderr, "Usage: argi <command> [arguments] [options]\n") != null);
}

test "argi build without target uses current directory" {
    const result = try runArgiCommand(&.{"build"});
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);

    try expectEqual(std.process.Child.Term{ .exited = 1 }, result.term);
    try expect(std.mem.indexOf(u8, result.stderr, "module directory required") == null);
}

test "argi run without target uses current directory" {
    const result = try runArgiCommand(&.{"run"});
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);

    try expectEqual(std.process.Child.Term{ .exited = 1 }, result.term);
    try expect(std.mem.indexOf(u8, result.stderr, "module directory required") == null);
}

test "argi test without target exits with error" {
    const result = try runArgiCommand(&.{"test"});
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);

    try expectEqual(std.process.Child.Term{ .exited = 1 }, result.term);
    try expectEqualStrings("Error: module directory required\n", result.stderr);
}

test "argi init without name initializes current directory" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_root = try tmpDirRootPath(&tmp);
    defer std.testing.allocator.free(tmp_root);
    const installed_argi = try installedArgiPath();
    defer std.testing.allocator.free(installed_argi);
    try tmp.dir.createDir(std.testing.io, "current_app", .default_dir);
    const module_root = try std.fs.path.join(std.testing.allocator, &.{ tmp_root, "current_app" });
    defer std.testing.allocator.free(module_root);
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "current_app/README.md", .data = "Keep this README.\n" });
    const result = try runChildInCwd(&.{ installed_argi, "init" }, module_root);
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);
    try expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    const manifest = try tmp.dir.readFileAlloc(std.testing.io, "current_app/argi.toml", std.testing.allocator, .limited(4096));
    defer std.testing.allocator.free(manifest);
    try expect(std.mem.indexOf(u8, manifest, "[executables.current_app]\n") != null);
    try expect(std.mem.indexOf(u8, manifest, "path = \"source/current_app\"\n") != null);
    try expect(std.mem.indexOf(u8, manifest, "default = \"current_app\"\n") != null);
    const readme = try tmp.dir.readFileAlloc(std.testing.io, "current_app/README.md", std.testing.allocator, .limited(4096));
    defer std.testing.allocator.free(readme);
    try expectEqualStrings("Keep this README.\n", readme);
    const built = try runChildInCwd(&.{ installed_argi, "run" }, module_root);
    defer std.testing.allocator.free(built.stdout);
    defer std.testing.allocator.free(built.stderr);
    try expectEqual(std.process.Child.Term{ .exited = 0 }, built.term);
    const repeated = try runChildInCwd(&.{ installed_argi, "init", "." }, module_root);
    defer std.testing.allocator.free(repeated.stdout);
    defer std.testing.allocator.free(repeated.stderr);
    try expectEqual(std.process.Child.Term{ .exited = 0 }, repeated.term);
    try tmp.dir.access(std.testing.io, "current_app/source/current_app/main.rg", .{});
    tmp.dir.access(std.testing.io, "current_app/source/-/main.rg", .{}) catch |err| switch (err) {
        error.FileNotFound => return,
        else => return err,
    };
    return error.UnexpectedFile;
}

test "argi init lib without name initializes current directory" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_root = try tmpDirRootPath(&tmp);
    defer std.testing.allocator.free(tmp_root);
    const installed_argi = try installedArgiPath();
    defer std.testing.allocator.free(installed_argi);
    try tmp.dir.createDir(std.testing.io, "current_library", .default_dir);
    const module_root = try std.fs.path.join(std.testing.allocator, &.{ tmp_root, "current_library" });
    defer std.testing.allocator.free(module_root);
    const result = try runChildInCwd(&.{ installed_argi, "init", "--lib" }, module_root);
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);
    try expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    const manifest = try tmp.dir.readFileAlloc(std.testing.io, "current_library/argi.toml", std.testing.allocator, .limited(4096));
    defer std.testing.allocator.free(manifest);
    try expect(std.mem.indexOf(u8, manifest, "name = \"current_library\"\n") != null);
    try expect(std.mem.indexOf(u8, manifest, "[executables.") == null);
}

test "argi run rejects output override" {
    const result = try runArgiCommand(&.{ "run", "tests/feature_tests/basics/01_minimal_main", "--output", "build/custom-run-output" });
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);

    try expectEqual(std.process.Child.Term{ .exited = 1 }, result.term);
    try expectEqualStrings(
        "Run error: --output is not supported by argi run; use argi build --output and execute the binary manually\n",
        result.stderr,
    );
}

test "argi run accepts explicit sysroot" {
    const sysroot = try std.fs.path.join(std.testing.allocator, &.{ compilerRoot(), "zig-out" });
    defer std.testing.allocator.free(sysroot);

    const result = try runArgiCommand(&.{ "run", "tests/feature_tests/basics/01_minimal_main", "--sysroot", sysroot });
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);

    try expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
}

test "argi test rejects missing filter value" {
    const result = try runArgiCommand(&.{ "test", "tests/feature_tests/testing/01_simple_pass", "--filter" });
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);

    try expectEqual(std.process.Child.Term{ .exited = 1 }, result.term);
    try expectEqualStrings("Test error: MissingFlagValue\n", result.stderr);
}

test "argi build rejects missing sysroot value" {
    const result = try runArgiCommand(&.{ "build", "tests/feature_tests/basics/01_minimal_main", "--sysroot" });
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);

    try expectEqual(std.process.Child.Term{ .exited = 1 }, result.term);
    try expectEqualStrings("Build error: MissingFlagValue\n", result.stderr);
}

test "argi test rejects missing sysroot value" {
    const result = try runArgiCommand(&.{ "test", "tests/feature_tests/testing/01_simple_pass", "--sysroot" });
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);

    try expectEqual(std.process.Child.Term{ .exited = 1 }, result.term);
    try expectEqualStrings("Test error: MissingFlagValue\n", result.stderr);
}

test "argi build reports invalid sysroot core lookup" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const sysroot = try std.fs.path.join(std.testing.allocator, &.{ compilerRoot(), ".zig-cache", "tmp", tmp.sub_path[0..] });
    defer std.testing.allocator.free(sysroot);

    const result = try runArgiCommand(&.{ "build", "tests/feature_tests/basics/01_minimal_main", "--sysroot", sysroot });
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);

    try expectEqual(std.process.Child.Term{ .exited = 1 }, result.term);
    try expect(std.mem.indexOf(u8, result.stderr, "cannot find Argi core library") != null);
    try expect(std.mem.indexOf(u8, result.stderr, "--sysroot") != null);
    try expect(std.mem.indexOf(u8, result.stderr, "ARGI_SYSROOT") != null);
}

test "argi build uses ARGI_SYSROOT when flag is absent" {
    const sysroot = try std.fs.path.join(std.testing.allocator, &.{ compilerRoot(), "zig-out" });
    defer std.testing.allocator.free(sysroot);

    var env_map = try std.testing.environ.createMap(std.testing.allocator);
    defer env_map.deinit();
    try env_map.put("ARGI_SYSROOT", sysroot);

    const result = try runArgiCommandWithEnv(
        &.{ "build", "tests/feature_tests/basics/01_minimal_main" },
        &env_map,
    );
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);

    try expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
}

test "argi run uses ARGI_SYSROOT when flag is absent" {
    const sysroot = try std.fs.path.join(std.testing.allocator, &.{ compilerRoot(), "zig-out" });
    defer std.testing.allocator.free(sysroot);

    var env_map = try std.testing.environ.createMap(std.testing.allocator);
    defer env_map.deinit();
    try env_map.put("ARGI_SYSROOT", sysroot);

    const result = try runArgiCommandWithEnv(
        &.{ "run", "tests/feature_tests/basics/01_minimal_main" },
        &env_map,
    );
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);

    try expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
}

test "argi test uses ARGI_SYSROOT when flag is absent" {
    const sysroot = try std.fs.path.join(std.testing.allocator, &.{ compilerRoot(), "zig-out" });
    defer std.testing.allocator.free(sysroot);

    var env_map = try std.testing.environ.createMap(std.testing.allocator);
    defer env_map.deinit();
    try env_map.put("ARGI_SYSROOT", sysroot);

    const result = try runArgiCommandWithEnv(
        &.{ "test", "tests/feature_tests/testing/01_simple_pass" },
        &env_map,
    );
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);

    try expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try expect(std.mem.indexOf(u8, result.stderr, "PASS simple_pass\n") != null);
}

test "argi build rejects invalid ARGI_SYSROOT without fallback" {
    var bad_tmp = std.testing.tmpDir(.{});
    defer bad_tmp.cleanup();
    const bad_sysroot = try std.fs.path.join(std.testing.allocator, &.{ compilerRoot(), ".zig-cache", "tmp", bad_tmp.sub_path[0..] });
    defer std.testing.allocator.free(bad_sysroot);

    var env_map = try std.testing.environ.createMap(std.testing.allocator);
    defer env_map.deinit();
    try env_map.put("ARGI_SYSROOT", bad_sysroot);

    const result = try runArgiCommandWithEnv(
        &.{ "build", "tests/feature_tests/basics/01_minimal_main" },
        &env_map,
    );
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);

    try expectEqual(std.process.Child.Term{ .exited = 1 }, result.term);
    try expect(std.mem.indexOf(u8, result.stderr, "cannot find Argi core library") != null);
    try expect(std.mem.indexOf(u8, result.stderr, "ARGI_SYSROOT") != null);
    try expect(std.mem.indexOf(u8, result.stderr, "installation prefix, not directly at core") != null);
}

test "argi build sysroot flag takes precedence over ARGI_SYSROOT" {
    const good_sysroot = try std.fs.path.join(std.testing.allocator, &.{ compilerRoot(), "zig-out" });
    defer std.testing.allocator.free(good_sysroot);

    var bad_tmp = std.testing.tmpDir(.{});
    defer bad_tmp.cleanup();
    const bad_sysroot = try std.fs.path.join(std.testing.allocator, &.{ compilerRoot(), ".zig-cache", "tmp", bad_tmp.sub_path[0..] });
    defer std.testing.allocator.free(bad_sysroot);

    var env_map = try std.testing.environ.createMap(std.testing.allocator);
    defer env_map.deinit();
    try env_map.put("ARGI_SYSROOT", bad_sysroot);

    const result = try runArgiCommandWithEnv(
        &.{ "build", "tests/feature_tests/basics/01_minimal_main", "--sysroot", good_sysroot },
        &env_map,
    );
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);

    try expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
}

test "argi build respects CC wrapper from environment" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const repo_root = try repoRootPrefix();
    defer std.testing.allocator.free(repo_root);

    const tmp_root = try std.fs.path.join(std.testing.allocator, &.{ repo_root, ".zig-cache", "tmp", tmp.sub_path[0..] });
    defer std.testing.allocator.free(tmp_root);

    const wrapper_path = try std.fs.path.join(std.testing.allocator, &.{ tmp_root, "cc-wrapper.sh" });
    defer std.testing.allocator.free(wrapper_path);
    const log_path = try std.fs.path.join(std.testing.allocator, &.{ tmp_root, "cc-wrapper.log" });
    defer std.testing.allocator.free(log_path);

    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "cc-wrapper.sh",
        .data =
        \\#!/bin/sh
        \\printf '%s\n' "wrapper-invoked" "$@" >> "$LOG_FILE"
        \\exec cc "$@"
        \\
        ,
        .flags = .{ .permissions = .executable_file },
    });

    var env_map = try std.testing.environ.createMap(std.testing.allocator);
    defer env_map.deinit();
    try env_map.put("CC", wrapper_path);
    try env_map.put("LOG_FILE", log_path);

    const result = try runArgiCommandWithEnv(
        &.{ "build", "tests/feature_tests/basics/01_minimal_main" },
        &env_map,
    );
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);

    try expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);

    const log = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, log_path, std.testing.allocator, .limited(1024 * 1024));
    defer std.testing.allocator.free(log);

    try expect(std.mem.indexOf(u8, log, "wrapper-invoked\n") != null);
    try expect(std.mem.indexOf(u8, log, "-lc\n") != null);
}

test "argi test rejects unknown flag" {
    const result = try runArgiCommand(&.{ "test", "tests/feature_tests/testing/01_simple_pass", "--bogus" });
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);

    try expectEqual(std.process.Child.Term{ .exited = 1 }, result.term);
    try expectEqualStrings("Test error: UnknownFlag\n", result.stderr);
}

test "argi test reports modules without tests" {
    const result = try runArgiCommand(&.{ "test", "tests/feature_tests/system/14_file_system_capability" });
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);

    try expectEqual(std.process.Child.Term{ .exited = 1 }, result.term);
    try expectEqualStrings("No tests found\n", result.stderr);
}

test "argi test reports empty filter matches" {
    const result = try runArgiCommand(&.{ "test", "tests/feature_tests/testing/03_once_isolated_per_test", "--filter", "missing" });
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);

    try expectEqual(std.process.Child.Term{ .exited = 1 }, result.term);
    try expectEqualStrings("No tests found\n", result.stderr);
}

test "dormant match payload copy diagnostics respect reachability" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "main.rg",
        .data =
        \\Token : Type = (.value: Int32)
        \\
        \\deinit(.self: $&Token) -> () := {}
        \\
        \\Result : Type = (
        \\    ..ok(.token: Token)
        \\    ..error
        \\)
        \\
        \\dormant() -> () := {
        \\    value : Result = ..ok(.token = Token(.value = 7))
        \\    match value {
        \\        ..ok payload {
        \\            _ ::= payload.token.value
        \\        }
        \\        ..error {}
        \\    }
        \\}
        \\
        \\main() -> (.status_code: Int32 = 0) := {}
        \\
        ,
    });

    const module_root = try tmpDirRootPath(&tmp);
    defer std.testing.allocator.free(module_root);
    const installed_argi = try installedArgiPath();
    defer std.testing.allocator.free(installed_argi);

    const result = try runChild(&.{ installed_argi, "build", module_root });
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);

    if (result.term != .exited or result.term.exited != 0)
        std.debug.print("dormant match payload build failed:\n{s}", .{result.stderr});
    try expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
}

test "dormant pointer diagnostics respect reachability" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "main.rg",
        .data =
        \\dormant() -> () := {
        \\    value :: Int32 = 0
        \\    reader : &Int32 = &value
        \\    reader& = 1
        \\}
        \\
        \\main() -> (.status_code: Int32 = 0) := {}
        \\
        ,
    });

    const module_root = try tmpDirRootPath(&tmp);
    defer std.testing.allocator.free(module_root);
    const installed_argi = try installedArgiPath();
    defer std.testing.allocator.free(installed_argi);

    const result = try runChild(&.{ installed_argi, "build", module_root });
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);

    if (result.term != .exited or result.term.exited != 0)
        std.debug.print("dormant pointer build failed:\n{s}", .{result.stderr});
    try expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
}

test "argi check validates dormant function bodies" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "main.rg",
        .data =
        \\dormant() -> () := {
        \\    value :: Int32 = 0
        \\    reader : &Int32 = &value
        \\    reader& = 1
        \\}
        \\
        \\main() -> (.status_code: Int32 = 0) := {}
        \\
        ,
    });

    const module_root = try tmpDirRootPath(&tmp);
    defer std.testing.allocator.free(module_root);
    const installed_argi = try installedArgiPath();
    defer std.testing.allocator.free(installed_argi);

    const result = try runChild(&.{ installed_argi, "check", module_root });
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);

    try expectEqual(std.process.Child.Term{ .exited = 1 }, result.term);
}

test "feature_tests/functions/20_assume_arguments" {
    const test_path = "tests/feature_tests/functions/20_assume_arguments";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/functions/21X_assume_no_propagation" {
    try buildExpectFail("tests/feature_tests/functions/21X_assume_no_propagation", "no overload of 'take' accepts arguments");
}

test "feature_tests/functions/22X_assume_incompatible_default" {
    try buildExpectFail("tests/feature_tests/functions/22X_assume_incompatible_default", "no overload of 'take' accepts arguments");
}

test "feature_tests/functions/23X_assume_unknown_variable" {
    try buildExpectFail("tests/feature_tests/functions/23X_assume_unknown_variable", "assume requires an existing variable; 'missing' is not declared in this scope");
}

test "feature_tests/functions/24X_assume_initializer" {
    try buildExpectFail("tests/feature_tests/functions/24X_assume_initializer", "use ':=' to declare an assumed variable, or 'assume name' for an existing variable");
}

test "feature_tests/functions/25X_assume_stale_reference" {
    try buildExpectFail("tests/feature_tests/functions/25X_assume_stale_reference", "reference depends on a root that has ended");
}

test "feature_tests/functions/26X_assume_scope_does_not_escape" {
    try buildExpectFail("tests/feature_tests/functions/26X_assume_scope_does_not_escape", "no overload of 'take' accepts arguments");
}

test "feature_tests/functions/27_assume_automatic_cleanup" {
    try expectSuccessfulBuild("tests/feature_tests/functions/27_assume_automatic_cleanup");
    try runExpect("tests/feature_tests/functions/27_assume_automatic_cleanup", 0);
}

test "feature_tests/functions/28_assume_constructor_temporary" {
    try expectSuccessfulBuild("tests/feature_tests/functions/28_assume_constructor_temporary");
    try runExpect("tests/feature_tests/functions/28_assume_constructor_temporary", 0);
}

test "feature_tests/functions/29X_assume_constructor_temporary_escape" {
    try buildExpectFail(
        "tests/feature_tests/functions/29X_assume_constructor_temporary_escape",
        "function output cannot depend on a local storage generation that ends before return",
    );
}

test "feature_tests/functions/30_reference_to_constructor_expression" {
    try expectSuccessfulBuild("tests/feature_tests/functions/30_reference_to_constructor_expression");
    try runExpect("tests/feature_tests/functions/30_reference_to_constructor_expression", 0);
}

test "feature_tests/functions/31X_reference_to_constructor_temporary_escape" {
    try buildExpectFail(
        "tests/feature_tests/functions/31X_reference_to_constructor_temporary_escape",
        "function output cannot depend on a local storage generation that ends before return",
    );
}

test "feature_tests/system/36_entry_flushes_stdout" {
    const test_path = "tests/feature_tests/system/36_entry_flushes_stdout";
    try expectSuccessfulBuild(test_path);
    try runExpectStdout(test_path, 0, "A");
}

test "feature_tests/system/37_c_allocator_alignment" {
    const test_path = "tests/feature_tests/system/37_c_allocator_alignment";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/system/38X_c_allocator_invalid_alignment" {
    const test_path = "tests/feature_tests/system/38X_c_allocator_invalid_alignment";
    try expectSuccessfulBuild(test_path);
    try runExpectFailure(test_path);
}

test "feature_tests/system/39X_page_allocator_invalid_alignment" {
    const test_path = "tests/feature_tests/system/39X_page_allocator_invalid_alignment";
    try expectSuccessfulBuild(test_path);
    try runExpectFailure(test_path);
}

test "feature_tests/system/40X_arena_allocator_invalid_alignment" {
    const test_path = "tests/feature_tests/system/40X_arena_allocator_invalid_alignment";
    try expectSuccessfulBuild(test_path);
    try runExpectFailure(test_path);
}

test "feature_tests/system/41_general_purpose_allocator" {
    const test_path = "tests/feature_tests/system/41_general_purpose_allocator";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/system/41X_c_allocator_zero_alignment" {
    const test_path = "tests/feature_tests/system/41X_c_allocator_zero_alignment";
    try expectSuccessfulBuild(test_path);
    try runExpectFailure(test_path);
}

test "feature_tests/system/42X_general_purpose_allocator_invalid_alignment" {
    const test_path = "tests/feature_tests/system/42X_general_purpose_allocator_invalid_alignment";
    try expectSuccessfulBuild(test_path);
    try runExpectFailure(test_path);
}

test "feature_tests/system/43X_general_purpose_large_double_free" {
    const test_path = "tests/feature_tests/system/43X_general_purpose_large_double_free";
    try expectSuccessfulBuild(test_path);
    try runExpectFailure(test_path);
}

test "feature_tests/system/37_system_local_resource_escape" {
    try expectSuccessfulBuild("tests/feature_tests/system/37_system_local_resource_escape");
    try runExpect("tests/feature_tests/system/37_system_local_resource_escape", 0);
}

test "feature_tests/system/44_memory_allocator_composition" {
    const test_path = "tests/feature_tests/system/44_memory_allocator_composition";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/system/45X_c_allocator_missing_ffi" {
    try buildExpectFail("tests/feature_tests/system/45X_c_allocator_missing_ffi", "ffi");
}

test "feature_tests/system/46X_general_purpose_allocator_missing_backing_allocator" {
    try buildExpectFail("tests/feature_tests/system/46X_general_purpose_allocator_missing_backing_allocator", "allocator");
}

test "feature_tests/system/47X_page_allocator_missing_memory" {
    try buildExpectFail("tests/feature_tests/system/47X_page_allocator_missing_memory", "memory");
}

test "feature_tests/system/48X_general_purpose_backing_ended" {
    try buildExpectFail("tests/feature_tests/system/48X_general_purpose_backing_ended", "reference depends on a root that has ended");
}

test "feature_tests/system/49X_initializer_temporary_ends_backing" {
    try buildExpectFail("tests/feature_tests/system/49X_initializer_temporary_ends_backing", "main.rg:28:24: error: reference depends on a root that has ended");
}

test "feature_tests/system/49_general_purpose_allocator_on_arena" {
    const test_path = "tests/feature_tests/system/49_general_purpose_allocator_on_arena";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/296_module_binding_reference_escape" {
    const test_path = "tests/feature_tests/ownership/296_module_binding_reference_escape";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/system/49X_general_purpose_allocator_on_arena_reset_live" {
    try buildExpectFail(
        "tests/feature_tests/system/49X_general_purpose_allocator_on_arena_reset_live",
        "reference depends on a root that has ended",
    );
}

test "feature_tests/system/49X_general_purpose_large_on_arena_reset_live" {
    try buildExpectFail(
        "tests/feature_tests/system/49X_general_purpose_large_on_arena_reset_live",
        "reference depends on a root that has ended",
    );
}

test "feature_tests/system/50X_initializer_summary_ends_backing" {
    try buildExpectFail("tests/feature_tests/system/50X_initializer_summary_ends_backing", "reference depends on a root that has ended");
}

test "feature_tests/system/51_general_purpose_slot_reuse" {
    const test_path = "tests/feature_tests/system/51_general_purpose_slot_reuse";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/system/52X_general_purpose_reused_slot_borrow" {
    try buildExpectFail("tests/feature_tests/system/52X_general_purpose_reused_slot_borrow", "reference depends on a root that has ended");
}

test "feature_tests/system/53X_general_purpose_small_double_free" {
    const test_path = "tests/feature_tests/system/53X_general_purpose_small_double_free";
    try expectSuccessfulBuild(test_path);
    try runExpectFailure(test_path);
}

test "feature_tests/types/261_fallible_constructor" {
    const test_path = "tests/feature_tests/types/261_fallible_constructor";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/types/265_direct_fallible_init" {
    const test_path = "tests/feature_tests/types/265_direct_fallible_init";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/293_fallible_constructor_owns_success" {
    const test_path = "tests/feature_tests/ownership/293_fallible_constructor_owns_success";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/text/20_fallible_string_constructor" {
    const test_path = "tests/feature_tests/text/20_fallible_string_constructor";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/types/262X_fallible_init_success_without_value" {
    try buildExpectFail(
        "tests/feature_tests/types/262X_fallible_init_success_without_value",
        "value was deinitialized",
    );
}

test "feature_tests/types/263_fallible_constructor_error_cleanup" {
    const path = "tests/feature_tests/types/263_fallible_constructor_error_cleanup";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/types/264X_fallible_init_requires_outcome" {
    try buildExpectFail(
        "tests/feature_tests/types/264X_fallible_init_requires_outcome",
        "value was deinitialized",
    );
}

test "feature_tests/types/266X_direct_fallible_init_error_leaves_empty" {
    try buildExpectFail(
        "tests/feature_tests/types/266X_direct_fallible_init_error_leaves_empty",
        "value was deinitialized",
    );
}

test "feature_tests/ownership/294X_fallible_constructor_preserves_root" {
    try buildExpectFail(
        "tests/feature_tests/ownership/294X_fallible_constructor_preserves_root",
        "reference depends on a root that has ended",
    );
}

test "feature_tests/types/267X_initializer_wrong_result" {
    try buildExpectFail(
        "tests/feature_tests/types/267X_initializer_wrong_result",
        "initializer must return its constructed type or one Errable of that type",
    );
}

test "feature_tests/text/22_format_propagation_cleanup" {
    const test_path = "tests/feature_tests/text/22_format_propagation_cleanup";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/types/268_fallible_nested_constructor_propagation" {
    const test_path = "tests/feature_tests/types/268_fallible_nested_constructor_propagation";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/text/23_propagated_constructor_failure" {
    const test_path = "tests/feature_tests/text/23_propagated_constructor_failure";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/135_inherited_reference_escapes_root" {
    try expectSuccessfulBuild("tests/feature_tests/ownership/135_inherited_reference_escapes_root");
    try runExpect("tests/feature_tests/ownership/135_inherited_reference_escapes_root", 7);
}

test "feature_tests/ownership/136X_duplicate_aligned_storage_establishment" {
    try buildExpectFail(
        "tests/feature_tests/ownership/136X_duplicate_aligned_storage_establishment",
        "physical storage capability has already been consumed",
    );
}

test "feature_tests/ownership/137_inherited_reference_wrapper_escapes_root" {
    try expectSuccessfulBuild("tests/feature_tests/ownership/137_inherited_reference_wrapper_escapes_root");
    try runExpect("tests/feature_tests/ownership/137_inherited_reference_wrapper_escapes_root", 7);
}

test "feature_tests/types/65_error_tracer_capability" {
    const path = "tests/feature_tests/types/65_error_tracer_capability";
    try expectSuccessfulBuild(path);
    try run(path);
}

test "feature_tests/types/66_error_tracer_context_copy" {
    const path = "tests/feature_tests/types/66_error_tracer_context_copy";
    try expectSuccessfulBuild(path);
    try runExpectStderr(path, 0,
        \\error trace (most recent first):
        \\  at tests/feature_tests/types/66_error_tracer_context_copy/main.rg:10:12: AB
        \\        fail() !! view
        \\               ^
        \\  at tests/feature_tests/types/66_error_tracer_context_copy/main.rg:2:31
        \\    fail() -> !Void := { result = ..error(.reason = ..copy_test_failure) }
        \\                                  ^
        \\
    );
}

test "feature_tests/types/67_error_tracer_escape" {
    try expectSuccessfulBuild("tests/feature_tests/types/67_error_tracer_escape");
    try runExpect("tests/feature_tests/types/67_error_tracer_escape", 0);
}

test "feature_tests/types/68_error_tracer_bounded_failures" {
    const path = "tests/feature_tests/types/68_error_tracer_bounded_failures";
    try expectSuccessfulBuild(path);
    try run(path);
}

test "feature_tests/types/69_error_tracer_truncation" {
    const path = "tests/feature_tests/types/69_error_tracer_truncation";
    try expectSuccessfulBuild(path);
    try runExpectStderr(path, 0,
        \\error trace (most recent first):
        \\  at tests/feature_tests/types/69_error_tracer_truncation/main.rg:9:5: latest
        \\        add_context(.context = "latest")
        \\        ^
        \\  <context truncated>
        \\  at tests/feature_tests/types/69_error_tracer_truncation/main.rg:2:31
        \\    fail() -> !Void := { result = ..error(.reason = ..truncated_test_failure) }
        \\                                  ^
        \\
    );
}

test "feature_tests/types/70_virtual_context_inference" {
    const path = "tests/feature_tests/types/70_virtual_context_inference";
    try expectSuccessfulBuild(path);
    try run(path);
}

test "feature_tests/types/71_virtual_pipe_temporary_escape" {
    try expectSuccessfulBuild("tests/feature_tests/types/71_virtual_pipe_temporary_escape");
    try runExpect("tests/feature_tests/types/71_virtual_pipe_temporary_escape", 0);
}

test "feature_tests/types/72X_virtual_inference_missing_context" {
    try buildExpectFail("tests/feature_tests/types/72X_virtual_inference_missing_context", "cannot infer the abstract parameter");
}

test "feature_tests/polymorphism/41_recursive_virtual_summaries" {
    const path = "tests/feature_tests/polymorphism/41_recursive_virtual_summaries";
    try expectSuccessfulBuild(path);
    try run(path);
}

test "feature_tests/types/73_error_tracer_shared_log" {
    const path = "tests/feature_tests/types/73_error_tracer_shared_log";
    try expectSuccessfulBuild(path);
    try run(path);
}

test "feature_tests/basics/26_arithmetic_precedence" {
    const path = "tests/feature_tests/basics/26_arithmetic_precedence";
    try expectSuccessfulBuild(path);
    try run(path);
}

// Reuse the same scenario as an entry body and behind one extra call boundary.
// Concrete checking visits both bodies, while the caller observes only the
// inferred summary. This catches lost cleanup/dependency effects in wrappers.
fn expectSafetyWrapperParity(case_path: []const u8, diagnostic: ?[]const u8) !void {
    const allocator = std.testing.allocator;
    const io = std.testing.io;
    const source_path = try std.fs.path.join(allocator, &.{ case_path, "main.rg" });
    defer allocator.free(source_path);
    const source = try std.Io.Dir.cwd().readFileAlloc(io, source_path, allocator, .limited(1024 * 1024));
    defer allocator.free(source);
    const entry = std.mem.indexOf(u8, source, "main(") orelse return error.MissingParityEntry;
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
    const constructor_wrapper: []const u8 = if (std.mem.indexOf(u8, relocated, "Owned : Type") != null)
        if (std.mem.indexOf(u8, relocated, ".fail: Bool") != null)
            "parity_owned(.allocator: $&Allocator, .fail: Bool) -> (.result: Errable#(.t: Owned, .reasons: (..out_of_memory))) := { result = Owned(.allocator = allocator, .fail = fail) }\n"
        else
            "parity_owned(.allocator: $&Allocator) -> (.result: Errable#(.t: Owned, .reasons: (..out_of_memory))) := { result = Owned(.allocator = allocator) }\n"
    else
        "";
    const arguments = if (std.mem.startsWith(u8, source[entry..], "main(.system: System")) ".system = system" else "";
    const wrapped = try std.fmt.allocPrint(
        allocator,
        "{s}\nmain(.system: System) -> (.status_code: Int32) := {{\n    status_code = parity_body({s})\n}}\n",
        .{ constructor_calls, arguments },
    );
    defer allocator.free(wrapped);
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(io, "module/support");
    try tmp.dir.writeFile(io, .{ .sub_path = "module/main.rg", .data = wrapped });
    const transfers = try std.fmt.allocPrint(
        allocator,
        "parity_deinit#(.t: Type)(.self: $&t) -> () := {{ deinit(.self = self) }}\n" ++
            "parity_drop#(.t: Type)(.slot: $&t) -> () := {{ trusted_opaque_drop(.slot = slot) }}\n{s}",
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

test "safety wrapper parity for move and cleanup" {
    try expectSafetyWrapperParity("tests/feature_tests/ownership/13_move_operator", null);
    try expectSafetyWrapperParity("tests/feature_tests/ownership/59X_branch_deinit_then_use", "maybe_initialized and cannot be used");
}

test "safety wrapper parity for opaque storage and generations" {
    try expectSafetyWrapperParity("tests/feature_tests/ownership/136_opaque_dependency_summary_does_not_duplicate_ownership", null);
    try expectSafetyWrapperParity("tests/feature_tests/ownership/162X_opaque_read_through_identity_wrapper_keeps_generation", "reference depends on a root that has ended");
}

test "safety wrapper parity for fallible initialization outcomes" {
    try expectSafetyWrapperParity("tests/feature_tests/ownership/293_fallible_constructor_owns_success", null);
    try expectSafetyWrapperParity("tests/feature_tests/ownership/294X_fallible_constructor_preserves_root", "reference depends on a root that has ended");
}

test "safety wrapper parity for recursion and virtual dispatch" {
    try expectSafetyWrapperParity("tests/feature_tests/polymorphism/41_recursive_virtual_summaries", null);
    try expectSafetyWrapperParity("tests/feature_tests/ownership/220X_virtual_post_state_dependency_union", "reference depends on a root that has ended");
    try expectSafetyWrapperParity("tests/feature_tests/polymorphism/30X_virtual_dependency_union", "function output cannot depend on a local storage generation that ends before return");
}

test "feature_tests/basics/27X_mixed_width_arithmetic" {
    try buildExpectFailExact("tests/feature_tests/basics/27X_mixed_width_arithmetic",
        \\tests/feature_tests/basics/27X_mixed_width_arithmetic/main.rg:4:22: error: operator '+' is not defined for 'UIntNative' and 'UInt8'
        \\      invalid ::= wide + narrow
        \\                       ^
        \\
    );
}

test "feature_tests/basics/28X_unsupported_initializer_expression" {
    try buildExpectFailExact("tests/feature_tests/basics/28X_unsupported_initializer_expression",
        \\tests/feature_tests/basics/28X_unsupported_initializer_expression/main.rg:3:19: error: choice option '..first_reason' needs a concrete choice type
        \\  Wrong : Choice = (..first_reason, ..second_reason)
        \\                    ^
        \\
    );
}

test "safety statistics preserve composed allocator behavior" {
    const path = "tests/feature_tests/system/49_general_purpose_allocator_on_arena";
    const result = try runArgiCommand(&.{ "build", path, "--stats" });
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);
    try expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    for ([_][]const u8{ "summary inference:", "summary bytes requested:", "retained worklist bytes:", "virtual summary time:", "virtual receiver lookup:", "state copy time:" }) |label|
        try expect(std.mem.indexOf(u8, result.stderr, label) != null);
    try run(path);
}

test "feature_tests/types/74_reference_offset_checked_arithmetic" {
    const path = "tests/feature_tests/types/74_reference_offset_checked_arithmetic";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/types/75X_reference_offset_multiplication_overflow" {
    const path = "tests/feature_tests/types/75X_reference_offset_multiplication_overflow";
    try expectSuccessfulBuild(path);
    try runExpectFailure(path);
}

test "feature_tests/types/76X_reference_offset_multiplication_overflow" {
    const path = "tests/feature_tests/types/76X_reference_offset_multiplication_overflow";
    try expectSuccessfulBuild(path);
    try runExpectFailure(path);
}

test "feature_tests/types/77X_reference_offset_addition_overflow" {
    const path = "tests/feature_tests/types/77X_reference_offset_addition_overflow";
    try expectSuccessfulBuild(path);
    try runExpectFailure(path);
}

test "feature_tests/types/78X_reference_offset_addition_overflow" {
    const path = "tests/feature_tests/types/78X_reference_offset_addition_overflow";
    try expectSuccessfulBuild(path);
    try runExpectFailure(path);
}

test "feature_tests/types/79_allocation_slot_range_checks" {
    const path = "tests/feature_tests/types/79_allocation_slot_range_checks";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/types/80X_allocation_slot_before_storage" {
    const path = "tests/feature_tests/types/80X_allocation_slot_before_storage";
    try expectSuccessfulBuild(path);
    try runExpectFailure(path);
}

test "feature_tests/types/81X_allocation_slot_at_storage_end" {
    const path = "tests/feature_tests/types/81X_allocation_slot_at_storage_end";
    try expectSuccessfulBuild(path);
    try runExpectFailure(path);
}

test "feature_tests/types/82X_allocation_slot_crosses_storage_end" {
    const path = "tests/feature_tests/types/82X_allocation_slot_crosses_storage_end";
    try expectSuccessfulBuild(path);
    try runExpectFailure(path);
}

test "feature_tests/types/83X_allocation_slot_misaligned" {
    const path = "tests/feature_tests/types/83X_allocation_slot_misaligned";
    try expectSuccessfulBuild(path);
    try runExpectFailure(path);
}

test "feature_tests/types/84X_allocation_slot_empty_storage" {
    const path = "tests/feature_tests/types/84X_allocation_slot_empty_storage";
    try expectSuccessfulBuild(path);
    try runExpectFailure(path);
}

test "feature_tests/types/85X_allocation_inflated_receipt" {
    const path = "tests/feature_tests/types/85X_allocation_inflated_receipt";
    try expectSuccessfulBuild(path);
    try runExpectFailure(path);
}

test "feature_tests/types/86X_allocation_redirected_receipt" {
    const path = "tests/feature_tests/types/86X_allocation_redirected_receipt";
    try expectSuccessfulBuild(path);
    try runExpectFailure(path);
}

test "feature_tests/types/87X_allocation_private_bounds" {
    try buildExpectFail("tests/feature_tests/types/87X_allocation_private_bounds", "field '_storage_size' is private to its module");
}

test "feature_tests/types/88_allocation_authenticated_cleanup" {
    const path = "tests/feature_tests/types/88_allocation_authenticated_cleanup";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/types/89X_allocation_forged_bounds_literal" {
    try buildExpectFail("tests/feature_tests/types/89X_allocation_forged_bounds_literal", "field '_storage_address' is private to its module");
}

test "feature_tests/types/90X_allocation_establishment_wrap" {
    const path = "tests/feature_tests/types/90X_allocation_establishment_wrap";
    try expectSuccessfulBuild(path);
    try runExpectFailure(path);
}

test "feature_tests/types/91_acquired_storage_establishment" {
    const path = "tests/feature_tests/types/91_acquired_storage_establishment";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/types/92X_acquired_storage_integer_establishment" {
    try buildExpectFail("tests/feature_tests/types/92X_acquired_storage_integer_establishment", "no overload");
}

test "feature_tests/types/93X_acquired_storage_private_extent" {
    try buildExpectFail("tests/feature_tests/types/93X_acquired_storage_private_extent", "field '_size' is private to its module");
}

test "feature_tests/types/94X_acquired_storage_extent" {
    const path = "tests/feature_tests/types/94X_acquired_storage_extent";
    try expectSuccessfulBuild(path);
    try runExpectFailure(path);
}

test "feature_tests/types/95X_acquired_storage_duplicate_establishment" {
    try buildExpectFail("tests/feature_tests/types/95X_acquired_storage_duplicate_establishment", "was moved and cannot be used again");
}

test "feature_tests/types/96X_acquired_page_storage_duplicate" {
    try buildExpectFail("tests/feature_tests/types/96X_acquired_page_storage_duplicate", "was moved and cannot be used again");
}

test "feature_tests/types/97X_acquired_storage_forged_literal" {
    try buildExpectFail("tests/feature_tests/types/97X_acquired_storage_forged_literal", "field '_address' is private to its module");
}

test "feature_tests/types/98X_acquired_storage_shared_authorization" {
    try buildExpectFail("tests/feature_tests/types/98X_acquired_storage_shared_authorization", "was moved and cannot be used again");
}

test "feature_tests/types/99X_acquired_storage_consumed_forwarding" {
    try buildExpectFail("tests/feature_tests/types/99X_acquired_storage_consumed_forwarding", "was moved and cannot be used again");
}

test "feature_tests/types/100X_acquired_page_storage_padding" {
    const path = "tests/feature_tests/types/100X_acquired_page_storage_padding";
    try expectSuccessfulBuild(path);
    try runExpectFailure(path);
}

test "feature_tests/types/101_acquired_storage_failure_and_empty" {
    const path = "tests/feature_tests/types/101_acquired_storage_failure_and_empty";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/types/102X_acquired_storage_private_subaddress" {
    try buildExpectFail("tests/feature_tests/types/102X_acquired_storage_private_subaddress", "no function named '_trusted_acquisition_subaddress' exists");
}

test "feature_tests/types/103_acquired_storage_prefix_cleanup" {
    const path = "tests/feature_tests/types/103_acquired_storage_prefix_cleanup";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/types/104X_acquired_storage_implicit_copy" {
    try buildExpectFail("tests/feature_tests/types/104X_acquired_storage_implicit_copy", "type 'AcquiredStorage' cannot be copied implicitly");
}

test "feature_tests/types/105_checked_uninit_slots" {
    const path = "tests/feature_tests/types/105_checked_uninit_slots";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/types/106X_checked_uninit_slot_extent" {
    const path = "tests/feature_tests/types/106X_checked_uninit_slot_extent";
    try expectSuccessfulBuild(path);
    try runExpectFailure(path);
}

test "feature_tests/types/107X_checked_uninit_slot_after_cleanup" {
    try buildExpectFail("tests/feature_tests/types/107X_checked_uninit_slot_after_cleanup", "root that has ended");
}

test "feature_tests/types/108X_checked_uninit_slot_private" {
    try buildExpectFail("tests/feature_tests/types/108X_checked_uninit_slot_private", "field '_raw' is private to its module");
}

test "feature_tests/types/109X_checked_uninit_slot_read" {
    try buildExpectFail("tests/feature_tests/types/109X_checked_uninit_slot_read", "not dereferenceable");
}

test "feature_tests/types/110X_checked_uninit_slot_empty" {
    const path = "tests/feature_tests/types/110X_checked_uninit_slot_empty";
    try expectSuccessfulBuild(path);
    try runExpectFailure(path);
}

test "feature_tests/types/111X_checked_uninit_slot_overflow" {
    const path = "tests/feature_tests/types/111X_checked_uninit_slot_overflow";
    try expectSuccessfulBuild(path);
    try runExpectFailure(path);
}

test "feature_tests/types/112X_checked_uninit_slot_backing_reset" {
    try buildExpectFail("tests/feature_tests/types/112X_checked_uninit_slot_backing_reset", "root that has ended");
}

test "feature_tests/collections/56_empty_array_views" {
    const path = "tests/feature_tests/collections/56_empty_array_views";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/collections/57X_empty_view_data" {
    const path = "tests/feature_tests/collections/57X_empty_view_data";
    try expectSuccessfulBuild(path);
    try runExpectFailure(path);
}

test "feature_tests/collections/58_spatial_borrowed_ranges" {
    const path = "tests/feature_tests/collections/58_spatial_borrowed_ranges";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/collections/59X_spatial_view_after_pop" {
    try buildExpectFail("tests/feature_tests/collections/59X_spatial_view_after_pop", "root that has ended");
}

test "feature_tests/collections/60X_spatial_view_after_growth" {
    try buildExpectFail("tests/feature_tests/collections/60X_spatial_view_after_growth", "root that has ended");
}

test "feature_tests/collections/61X_spatial_view_after_release" {
    try buildExpectFail("tests/feature_tests/collections/61X_spatial_view_after_release", "root that has ended");
}

test "feature_tests/collections/62X_spatial_view_after_insert" {
    try buildExpectFail("tests/feature_tests/collections/62X_spatial_view_after_insert", "root that has ended");
}

test "feature_tests/collections/63X_spatial_view_after_remove" {
    try buildExpectFail("tests/feature_tests/collections/63X_spatial_view_after_remove", "root that has ended");
}

test "feature_tests/collections/64X_spatial_view_after_append" {
    try buildExpectFail("tests/feature_tests/collections/64X_spatial_view_after_append", "root that has ended");
}

test "feature_tests/collections/65X_spatial_view_after_arena_reset" {
    try buildExpectFail("tests/feature_tests/collections/65X_spatial_view_after_arena_reset", "root that has ended");
}

test "feature_tests/collections/66X_spatial_view_shape_private" {
    try buildExpectFail("tests/feature_tests/collections/66X_spatial_view_shape_private", "field '_shape' is private to its module");
}

test "feature_tests/collections/67X_spatial_view_element_after_pop" {
    try buildExpectFail(
        "tests/feature_tests/collections/67X_spatial_view_element_after_pop",
        "root that has ended",
    );
}

test "feature_tests/ownership/297_local_pointee_summary" {
    const test_path = "tests/feature_tests/ownership/297_local_pointee_summary";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/298X_local_pointee_summary_after_deinit" {
    try buildExpectFail(
        "tests/feature_tests/ownership/298X_local_pointee_summary_after_deinit",
        "root that has ended",
    );
}

test "feature_tests/ownership/299X_nullable_pointee_summary_read" {
    try buildExpectFail(
        "tests/feature_tests/ownership/299X_nullable_pointee_summary_read",
        "root that has ended",
    );
}

test "feature_tests/collections/68_spatial_direct_loans" {
    const test_path = "tests/feature_tests/collections/68_spatial_direct_loans";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/collections/69X_spatial_direct_reference_after_pop" {
    try buildExpectFail("tests/feature_tests/collections/69X_spatial_direct_reference_after_pop", "root that has ended");
}

test "feature_tests/collections/70X_spatial_mutable_reference_after_remove" {
    try buildExpectFail("tests/feature_tests/collections/70X_spatial_mutable_reference_after_remove", "root that has ended");
}

test "feature_tests/collections/71X_spatial_value_iterator_after_append" {
    try buildExpectFail("tests/feature_tests/collections/71X_spatial_value_iterator_after_append", "root that has ended");
}

test "feature_tests/collections/72X_spatial_ro_iterator_after_pop" {
    try buildExpectFail("tests/feature_tests/collections/72X_spatial_ro_iterator_after_pop", "root that has ended");
}

test "feature_tests/collections/73X_spatial_rw_iterator_after_growth" {
    try buildExpectFail("tests/feature_tests/collections/73X_spatial_rw_iterator_after_growth", "root that has ended");
}

test "feature_tests/collections/74X_spatial_iterator_element_after_pop" {
    try buildExpectFail("tests/feature_tests/collections/74X_spatial_iterator_element_after_pop", "root that has ended");
}

test "feature_tests/collections/75X_spatial_iterator_private_fields" {
    try buildExpectFail("tests/feature_tests/collections/75X_spatial_iterator_private_fields", "field '_index' is private");
}

test "feature_tests/collections/76X_spatial_private_element_pointer" {
    try buildExpectFail("tests/feature_tests/collections/76X_spatial_private_element_pointer", "no function named '_trusted_dynamic_array_element_ro_pointer' exists");
}

test "feature_tests/ownership/301X_storage_capability_forwarded_twice" {
    try buildExpectFail("tests/feature_tests/ownership/301X_storage_capability_forwarded_twice", "already been consumed");
}

test "feature_tests/ownership/302X_storage_capability_alias_inputs" {
    try buildExpectFail("tests/feature_tests/ownership/302X_storage_capability_alias_inputs", "more than once");
}

test "feature_tests/ownership/303X_storage_capability_conditional_use" {
    try buildExpectFail("tests/feature_tests/ownership/303X_storage_capability_conditional_use", "already been consumed");
}

test "feature_tests/ownership/304X_storage_capability_loop_reuse" {
    try buildExpectFail("tests/feature_tests/ownership/304X_storage_capability_loop_reuse", "more than once");
}

test "feature_tests/ownership/305X_storage_capability_recursive_reuse" {
    try buildExpectFail("tests/feature_tests/ownership/305X_storage_capability_recursive_reuse", "more than once");
}

test "feature_tests/ownership/306X_storage_capability_consumed_acquisition" {
    try buildExpectFail("tests/feature_tests/ownership/306X_storage_capability_consumed_acquisition", "already been consumed");
}

test "feature_tests/ownership/307X_storage_capability_forwarded_allocation" {
    try buildExpectFail("tests/feature_tests/ownership/307X_storage_capability_forwarded_allocation", "already been consumed");
}

test "feature_tests/ownership/309X_storage_capability_shared_outputs" {
    try buildExpectFail("tests/feature_tests/ownership/309X_storage_capability_shared_outputs", "already been consumed");
}

test "feature_tests/ownership/310X_storage_capability_reference_input" {
    try buildExpectFail("tests/feature_tests/ownership/310X_storage_capability_reference_input", "already been consumed");
}

test "feature_tests/ownership/311X_storage_capability_internal_alias" {
    try buildExpectFail("tests/feature_tests/ownership/311X_storage_capability_internal_alias", "more than once");
}

test "feature_tests/ownership/308_storage_capability_forwarding" {
    const test_path = "tests/feature_tests/ownership/308_storage_capability_forwarding";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/312X_storage_capability_nested_reference" {
    try buildExpectFail("tests/feature_tests/ownership/312X_storage_capability_nested_reference", "already been consumed");
}

test "feature_tests/ownership/313X_storage_capability_post_state_alias" {
    try buildExpectFail("tests/feature_tests/ownership/313X_storage_capability_post_state_alias", "already been consumed");
}

test "feature_tests/ownership/314X_storage_capability_consumed_choice" {
    try buildExpectFail("tests/feature_tests/ownership/314X_storage_capability_consumed_choice", "already been consumed");
}

test "feature_tests/ownership/315X_storage_capability_local_pointer_write" {
    try buildExpectFail("tests/feature_tests/ownership/315X_storage_capability_local_pointer_write", "already been consumed");
}

test "feature_tests/ownership/316X_storage_capability_mutual_forwarding" {
    try buildExpectFail("tests/feature_tests/ownership/316X_storage_capability_mutual_forwarding", "already been consumed");
}

test "feature_tests/ownership/317X_storage_capability_forwarded_shared_outputs" {
    try buildExpectFail("tests/feature_tests/ownership/317X_storage_capability_forwarded_shared_outputs", "already been consumed");
}

test "feature_tests/ownership/318X_storage_capability_loop_condition" {
    try buildExpectFail("tests/feature_tests/ownership/318X_storage_capability_loop_condition", "more than once");
}

test "feature_tests/ownership/319X_storage_capability_consumed_post_state" {
    try buildExpectFail("tests/feature_tests/ownership/319X_storage_capability_consumed_post_state", "already been consumed");
}

test "feature_tests/collections/77X_spatial_reference_after_set" {
    try buildExpectFail("tests/feature_tests/collections/77X_spatial_reference_after_set", "root that has ended");
}

test "feature_tests/collections/78X_spatial_forwarded_reference_after_set" {
    try buildExpectFail("tests/feature_tests/collections/78X_spatial_forwarded_reference_after_set", "root that has ended");
}

test "feature_tests/collections/79_dynamic_array_occupancy_transitions" {
    const path = "tests/feature_tests/collections/79_dynamic_array_occupancy_transitions";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "tests/feature_tests/basics/29_unsigned_literal_extrema" {
    try expectSuccessfulBuild("tests/feature_tests/basics/29_unsigned_literal_extrema");
    try runExpect("tests/feature_tests/basics/29_unsigned_literal_extrema", 0);
}

test "tests/feature_tests/basics/30X_unsigned_literal_magnitude_overflow" {
    try buildExpectFailExact("tests/feature_tests/basics/30X_unsigned_literal_magnitude_overflow",
        \\tests/feature_tests/basics/30X_unsigned_literal_magnitude_overflow/main.rg:2:22: error: integer literal magnitude exceeds the supported 64-bit range
        \\      value : UInt64 = 18446744073709551616
        \\                       ^
        \\
    );
}

test "tests/feature_tests/basics/31X_int64_positive_literal_overflow" {
    try buildExpectFail("tests/feature_tests/basics/31X_int64_positive_literal_overflow", "does not fit in");
}

test "tests/feature_tests/basics/32X_int64_negative_literal_overflow" {
    try buildExpectFail("tests/feature_tests/basics/32X_int64_negative_literal_overflow", "does not fit in");
}

test "tests/feature_tests/basics/33X_generic_integer_literal_magnitude_overflow" {
    try buildExpectFailExact("tests/feature_tests/basics/33X_generic_integer_literal_magnitude_overflow",
        \\tests/feature_tests/basics/33X_generic_integer_literal_magnitude_overflow/main.rg:1:52: error: integer literal magnitude exceeds the supported 64-bit range
        \\  maximum#(.t: Type)() -> (.result: t) := { result = 18446744073709551616 }
        \\                                                     ^
        \\
    );
}

test "tests/feature_tests/basics/34X_unsigned_negative_literal" {
    try buildExpectFail("tests/feature_tests/basics/34X_unsigned_negative_literal", "does not fit in");
}

test "feature_tests/types/269_nested_generic_argument_ranges" {
    const path = "tests/feature_tests/types/269_nested_generic_argument_ranges";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/polymorphism/42_virtual_nonleading_receiver" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/42_virtual_nonleading_receiver");
    try runExpect("tests/feature_tests/polymorphism/42_virtual_nonleading_receiver", 0);
}

test "feature_tests/polymorphism/43X_virtual_multiple_self_receivers" {
    try buildExpectFail("tests/feature_tests/polymorphism/43X_virtual_multiple_self_receivers", "exactly one borrowed Self receiver");
}

test "feature_tests/polymorphism/44X_virtual_self_result" {
    try buildExpectFail("tests/feature_tests/polymorphism/44X_virtual_self_result", "Self cannot appear in a virtual method result");
}

test "feature_tests/polymorphism/45X_virtual_self_by_value" {
    try buildExpectFail("tests/feature_tests/polymorphism/45X_virtual_self_by_value", "Self is only allowed as a direct borrowed receiver");
}

test "feature_tests/polymorphism/46X_virtual_nested_self_input" {
    try buildExpectFail("tests/feature_tests/polymorphism/46X_virtual_nested_self_input", "Self is only allowed as a direct borrowed receiver");
}

test "feature_tests/polymorphism/47X_virtual_missing_receiver" {
    try buildExpectFail("tests/feature_tests/polymorphism/47X_virtual_missing_receiver", "exactly one borrowed Self receiver");
}

test "feature_tests/polymorphism/48X_virtual_associated_parameters" {
    try buildExpectFail("tests/feature_tests/polymorphism/48X_virtual_associated_parameters", "does not implement the selected abstract");
}

test "feature_tests/polymorphism/49_virtual_explicit_peer_handle" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/49_virtual_explicit_peer_handle");
    try runExpect("tests/feature_tests/polymorphism/49_virtual_explicit_peer_handle", 0);
}

test "feature_tests/types/270X_acquired_storage_inspected_alias_consumed" {
    try buildExpectFail("tests/feature_tests/types/270X_acquired_storage_inspected_alias_consumed", "already been consumed");
}

test "feature_tests/polymorphism/50X_virtual_readonly_mutable_contract" {
    try buildExpectFail("tests/feature_tests/polymorphism/50X_virtual_readonly_mutable_contract", "a mutable Self receiver requires a mutable concrete reference");
}

test "feature_tests/polymorphism/51X_virtual_readonly_generic_conversion" {
    try buildExpectFail("tests/feature_tests/polymorphism/51X_virtual_readonly_generic_conversion", "a mutable Self receiver requires a mutable concrete reference");
}

test "feature_tests/polymorphism/52X_virtual_receiver_identity_same_type_argument" {
    try buildExpectFail("tests/feature_tests/polymorphism/52X_virtual_receiver_identity_same_type_argument", "root that has ended");
}

test "feature_tests/polymorphism/53_virtual_receiver_identity_same_type_argument" {
    const path = "tests/feature_tests/polymorphism/53_virtual_receiver_identity_same_type_argument";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/collections/80_collection_contracts" {
    const path = "tests/feature_tests/collections/80_collection_contracts";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/collections/81X_readonly_collection_mutation" {
    try buildExpectFail("tests/feature_tests/collections/81X_readonly_collection_mutation", "does not implement");
}

test "feature_tests/collections/82X_owning_collection_value_read" {
    try buildExpectFail("tests/feature_tests/collections/82X_owning_collection_value_read", "no overload");
}

test "feature_tests/text/24_string_view_search" {
    const path = "tests/feature_tests/text/24_string_view_search";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/collections/83_string_hash_map_full_key" {
    const path = "tests/feature_tests/collections/83_string_hash_map_full_key";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/text/25_integer_parsing" {
    const path = "tests/feature_tests/text/25_integer_parsing";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/types/271_constructor_choice_context" {
    const path = "tests/feature_tests/types/271_constructor_choice_context";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/types/272X_constructor_choice_nominal_mismatch" {
    try buildExpectFail("tests/feature_tests/types/272X_constructor_choice_nominal_mismatch", "no function named 'FirstWrapper'");
}

test "feature_tests/ownership/320X_unwrapped_allocation_after_cleanup" {
    try buildExpectFail("tests/feature_tests/ownership/320X_unwrapped_allocation_after_cleanup", "root that has ended");
}

test "feature_tests/text/28X_string_view_after_cleanup" {
    try buildExpectFail("tests/feature_tests/text/28X_string_view_after_cleanup", "root that has ended");
}

test "feature_tests/text/26_string_view_trim" {
    const path = "tests/feature_tests/text/26_string_view_trim";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/text/27X_trimmed_view_after_cleanup" {
    try buildExpectFail("tests/feature_tests/text/27X_trimmed_view_after_cleanup", "root that has ended");
}

test "feature_tests/text/29_string_view_split" {
    const path = "tests/feature_tests/text/29_string_view_split";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/text/30X_split_source_after_cleanup" {
    try buildExpectFail("tests/feature_tests/text/30X_split_source_after_cleanup", "root that has ended");
}

test "feature_tests/text/31X_split_separator_after_cleanup" {
    try buildExpectFail("tests/feature_tests/text/31X_split_separator_after_cleanup", "root that has ended");
}

test "feature_tests/text/32_string_join" {
    const path = "tests/feature_tests/text/32_string_join";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/text/33_string_join_errors" {
    const path = "tests/feature_tests/text/33_string_join_errors";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/text/34_string_join_allocation_counts" {
    const path = "tests/feature_tests/text/34_string_join_allocation_counts";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/text/37X_joined_view_after_cleanup" {
    try buildExpectFail("tests/feature_tests/text/37X_joined_view_after_cleanup", "root that has ended");
}

test "feature_tests/text/35_string_replace" {
    const path = "tests/feature_tests/text/35_string_replace";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/text/36_string_replace_errors" {
    const path = "tests/feature_tests/text/36_string_replace_errors";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/text/38X_replaced_view_after_cleanup" {
    try buildExpectFail("tests/feature_tests/text/38X_replaced_view_after_cleanup", "root that has ended");
}

test "feature_tests/text/39_string_replace_allocation_counts" {
    const path = "tests/feature_tests/text/39_string_replace_allocation_counts";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/text/40_string_size_overflow" {
    const path = "tests/feature_tests/text/40_string_size_overflow";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/types/273_specialized_comparison_operators" {
    const path = "tests/feature_tests/types/273_specialized_comparison_operators";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/types/274X_specialized_comparison_missing" {
    try buildExpectFail("tests/feature_tests/types/274X_specialized_comparison_missing", "no matching comparison operator '==' for 'Record' and 'Record'");
}

test "feature_tests/types/275X_specialized_ordering_missing" {
    try buildExpectFail("tests/feature_tests/types/275X_specialized_ordering_missing", "no matching comparison operator '<' for 'StringView' and 'StringView'");
}

test "feature_tests/types/276X_specialized_numeric_comparison_mismatch" {
    try buildExpectFail("tests/feature_tests/types/276X_specialized_numeric_comparison_mismatch", "no matching comparison operator '==' for 'UInt64' and 'Int64'");
}

test "feature_tests/types/277_specialized_comparison_assumed_input" {
    const path = "tests/feature_tests/types/277_specialized_comparison_assumed_input";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/collections/84_collection_search" {
    const path = "tests/feature_tests/collections/84_collection_search";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/collections/85X_collection_search_missing_equality" {
    try buildExpectFail("tests/feature_tests/collections/85X_collection_search_missing_equality", "no matching comparison operator '==' for 'Record' and 'Record'");
}

test "feature_tests/collections/86_ring_buffer" {
    const path = "tests/feature_tests/collections/86_ring_buffer";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/collections/87_ring_buffer_ownership" {
    const path = "tests/feature_tests/collections/87_ring_buffer_ownership";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/collections/88_ring_buffer_errors" {
    const path = "tests/feature_tests/collections/88_ring_buffer_errors";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/collections/89X_ring_buffer_borrow_after_pop" {
    try buildExpectFail("tests/feature_tests/collections/89X_ring_buffer_borrow_after_pop", "root that has ended");
}

test "feature_tests/collections/90X_ring_buffer_forwarded_borrow_after_push" {
    try buildExpectFail("tests/feature_tests/collections/90X_ring_buffer_forwarded_borrow_after_push", "root that has ended");
}

test "feature_tests/collections/91X_ring_buffer_borrow_after_cleanup" {
    try buildExpectFail("tests/feature_tests/collections/91X_ring_buffer_borrow_after_cleanup", "root that has ended");
}

test "feature_tests/collections/92X_ring_buffer_push_moves_source" {
    try buildExpectFail("tests/feature_tests/collections/92X_ring_buffer_push_moves_source", "moved and cannot be used");
}

test "feature_tests/collections/93X_ring_buffer_private_occupancy" {
    try buildExpectFail("tests/feature_tests/collections/93X_ring_buffer_private_occupancy", "field '_head' is private");
}

test "feature_tests/collections/94_ring_buffer_zero_sized" {
    const path = "tests/feature_tests/collections/94_ring_buffer_zero_sized";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/collections/95_ring_buffer_allocation_counts" {
    const path = "tests/feature_tests/collections/95_ring_buffer_allocation_counts";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/collections/96_hash_policies" {
    const path = "tests/feature_tests/collections/96_hash_policies";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/collections/97_hash_map" {
    const path = "tests/feature_tests/collections/97_hash_map";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/collections/98_hash_map_collisions" {
    const path = "tests/feature_tests/collections/98_hash_map_collisions";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/collections/99_hash_map_growth_failure" {
    const path = "tests/feature_tests/collections/99_hash_map_growth_failure";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/collections/100_hash_map_string_keys" {
    const path = "tests/feature_tests/collections/100_hash_map_string_keys";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/collections/101X_hash_map_borrow_after_put" {
    try buildExpectFail("tests/feature_tests/collections/101X_hash_map_borrow_after_put", "root that has ended");
}

test "feature_tests/collections/102X_hash_map_borrow_after_remove" {
    try buildExpectFail("tests/feature_tests/collections/102X_hash_map_borrow_after_remove", "root that has ended");
}

test "feature_tests/collections/103X_hash_map_borrow_after_cleanup" {
    try buildExpectFail("tests/feature_tests/collections/103X_hash_map_borrow_after_cleanup", "root that has ended");
}

test "feature_tests/types/278_parameterized_contract_static_calls" {
    const path = "tests/feature_tests/types/278_parameterized_contract_static_calls";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/collections/104X_hash_map_key_after_cleanup" {
    try buildExpectFail("tests/feature_tests/collections/104X_hash_map_key_after_cleanup", "opaque storage hides a dependency");
}

test "feature_tests/collections/105_hash_set" {
    const path = "tests/feature_tests/collections/105_hash_set";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/collections/106_hash_set_growth_failure" {
    const path = "tests/feature_tests/collections/106_hash_set_growth_failure";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/collections/107X_hash_set_key_after_cleanup" {
    try buildExpectFail("tests/feature_tests/collections/107X_hash_set_key_after_cleanup", "opaque storage hides a dependency");
}

test "feature_tests/collections/108_collection_reverse" {
    const path = "tests/feature_tests/collections/108_collection_reverse";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/collections/109X_collection_reverse_owning" {
    try buildExpectFail("tests/feature_tests/collections/109X_collection_reverse_owning", "abstract constraint 'ImplicitlyCopyable' required by generic function parameter '.t' of 'reverse'");
}

test "feature_tests/collections/110_order_policies" {
    const path = "tests/feature_tests/collections/110_order_policies";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/collections/111_collection_binary_search" {
    const path = "tests/feature_tests/collections/111_collection_binary_search";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/collections/112_binary_search_large_index" {
    const path = "tests/feature_tests/collections/112_binary_search_large_index";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/collections/113_collection_sort" {
    const path = "tests/feature_tests/collections/113_collection_sort";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/collections/114_collection_sort_cases" {
    const path = "tests/feature_tests/collections/114_collection_sort_cases";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/collections/115_collection_sort_records" {
    const path = "tests/feature_tests/collections/115_collection_sort_records";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/collections/116X_collection_sort_readonly" {
    try buildExpectFail("tests/feature_tests/collections/116X_collection_sort_readonly", "no matching generic overload of 'sort' accepts arguments");
}

test "tests/feature_tests/basics/25X_numeric_binding_type" {
    try buildExpectFail("tests/feature_tests/basics/25X_numeric_binding_type", "cannot assign numeric value of type");
}

test "tests/feature_tests/basics/26X_numeric_assignment_type" {
    try buildExpectFail("tests/feature_tests/basics/26X_numeric_assignment_type", "cannot assign numeric value of type");
}

test "tests/feature_tests/basics/27X_numeric_pointer_assignment_type" {
    try buildExpectFail("tests/feature_tests/basics/27X_numeric_pointer_assignment_type", "cannot assign numeric value of type");
}

test "tests/feature_tests/basics/28X_numeric_signedness_assignment" {
    try buildExpectFail("tests/feature_tests/basics/28X_numeric_signedness_assignment", "cannot assign numeric value of type");
}

test "tests/feature_tests/basics/29X_numeric_float_assignment" {
    try buildExpectFail("tests/feature_tests/basics/29X_numeric_float_assignment", "cannot assign numeric value of type");
}

test "tests/feature_tests/basics/30_numeric_contextual_assignment" {
    const path = "tests/feature_tests/basics/30_numeric_contextual_assignment";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "tests/feature_tests/polymorphism/59X_generic_constraint_implicit" {
    try buildExpectFail("tests/feature_tests/polymorphism/59X_generic_constraint_implicit", "abstract constraint 'ImplicitlyCopyable' required by generic function parameter '.t' of 'accept'");
}

test "tests/feature_tests/polymorphism/60X_generic_constraint_explicit" {
    try buildExpectFail("tests/feature_tests/polymorphism/60X_generic_constraint_explicit", "abstract constraint 'ImplicitlyCopyable' required by generic function parameter '.t' of 'accept'");
}

test "tests/feature_tests/polymorphism/61_generic_constraint_alternate" {
    const path = "tests/feature_tests/polymorphism/61_generic_constraint_alternate";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "tests/feature_tests/polymorphism/62X_generic_constraint_wrong_shape" {
    try buildExpectFail("tests/feature_tests/polymorphism/62X_generic_constraint_wrong_shape", "no matching generic overload of 'accept_owned' accepts arguments");
}

test "tests/feature_tests/polymorphism/63X_generic_constraint_qualified" {
    try buildExpectFail("tests/feature_tests/polymorphism/63X_generic_constraint_qualified", "abstract constraint 'ImplicitlyCopyable' required by generic function parameter '.t' of 'accept'");
}

test "feature_tests/polymorphism/64_generic_constraint_fallback" {
    const path = "tests/feature_tests/polymorphism/64_generic_constraint_fallback";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "tests/feature_tests/basics/35X_float_literal_integer_destination" {
    try buildExpectFail("tests/feature_tests/basics/35X_float_literal_integer_destination", "cannot assign numeric value of type");
}

test "tests/feature_tests/basics/36X_integer_literal_float_destination" {
    try buildExpectFail("tests/feature_tests/basics/36X_integer_literal_float_destination", "cannot assign numeric value of type");
}

test "argi run inherits stdin stdout and stderr" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "main.rg",
        .data =
        \\main(.system: System) -> (.status_code: Int32 = 7) := {
        \\    input ::= unwrap_or_abort(.value = read_byte(.self = $&system.terminal&.stdin))
        \\    match input {
        \\        ..ok byte {
        \\            if byte != 65 { status_code = 8 return }
        \\        }
        \\        ..end { status_code = 9 return }
        \\    }
        \\    print(.value = "stdout marker", .writer = $&system.terminal&.stdout)
        \\    print_error(.value = "stderr marker\n", .writer = $&system.terminal&.stderr)
        \\}
        ,
    });
    const module_dir = try tmpDirRootPath(&tmp);
    defer std.testing.allocator.free(module_dir);
    const installed_argi = try installedArgiPath();
    defer std.testing.allocator.free(installed_argi);
    var child = try std.process.spawn(std.testing.io, .{
        .argv = &.{ installed_argi, "run", module_dir },
        .stdin = .pipe,
        .stdout = .pipe,
        .stderr = .pipe,
    });
    defer child.kill(std.testing.io);
    try child.stdin.?.writeStreamingAll(std.testing.io, "A");
    child.stdin.?.close(std.testing.io);
    child.stdin = null;
    var buffer: std.Io.File.MultiReader.Buffer(2) = undefined;
    var reader: std.Io.File.MultiReader = undefined;
    reader.init(std.testing.allocator, std.testing.io, buffer.toStreams(), &.{ child.stdout.?, child.stderr.? });
    defer reader.deinit();
    while (true) {
        reader.fill(1, .none) catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };
    }
    const stdout = try reader.toOwnedSlice(0);
    defer std.testing.allocator.free(stdout);
    const stderr = try reader.toOwnedSlice(1);
    defer std.testing.allocator.free(stderr);
    try expectEqual(std.process.Child.Term{ .exited = 7 }, try child.wait(std.testing.io));
    try expectEqualStrings("stdout marker\n", stdout);
    try expect(std.mem.indexOf(u8, stderr, "stderr marker\n") != null);
    try expect(std.mem.indexOf(u8, stderr, "stdout marker") == null);
}

test "feature_tests/io/27_buffered_writer_policy" {
    const test_path = "tests/feature_tests/io/27_buffered_writer_policy";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/io/28_buffered_terminal_output" {
    const test_path = "tests/feature_tests/io/28_buffered_terminal_output";
    try expectSuccessfulBuild(test_path);
    try runExpectStdout(test_path, 0, "Buffered output\nOK");
}

test "feature_tests/io/29X_buffered_writer_invalid_length" {
    const test_path = "tests/feature_tests/io/29X_buffered_writer_invalid_length";
    try expectSuccessfulBuild(test_path);
    try runExpectFailure(test_path);
}

test "feature_tests/io/30_zeroed_arrays" {
    const test_path = "tests/feature_tests/io/30_zeroed_arrays";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/io/31X_buffered_writer_expired_buffer" {
    try buildExpectFailWithoutParseNoise("tests/feature_tests/io/31X_buffered_writer_expired_buffer", "reference depends on a root that has ended");
}

test "feature_tests/io/32X_zeroed_reference" {
    try buildExpectFailWithoutParseNoise("tests/feature_tests/io/32X_zeroed_reference", "zeroed requires a numeric type or a fixed array of numeric types");
}

test "feature_tests/types/113_error_tracer_borrowed_buffer" {
    const path = "tests/feature_tests/types/113_error_tracer_borrowed_buffer";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/types/114X_error_tracer_expired_buffer" {
    try buildExpectFailWithoutParseNoise("tests/feature_tests/types/114X_error_tracer_expired_buffer", "reference depends on a root that has ended");
}

test "feature_tests/types/115X_error_tracer_corrupt_header" {
    const path = "tests/feature_tests/types/115X_error_tracer_corrupt_header";
    try expectSuccessfulBuild(path);
    try runExpectFailure(path);
}

test "feature_tests/basics/37_nested_array_inference" {
    const path = "tests/feature_tests/basics/37_nested_array_inference";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/basics/38_used_array_inference" {
    const path = "tests/feature_tests/basics/38_used_array_inference";
    try expectSuccessfulBuild(path);
    try runExpect(path, 1);
}

test "feature_tests/basics/39_contextual_nested_array" {
    const path = "tests/feature_tests/basics/39_contextual_nested_array";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/basics/40X_array_initializer_unknown_call" {
    try buildExpectFailWithoutNoise("tests/feature_tests/basics/40X_array_initializer_unknown_call", "no function named 'missing_value' exists", "cannot infer the array type");
}

test "feature_tests/basics/41_array_address_inference" {
    const path = "tests/feature_tests/basics/41_array_address_inference";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/basics/42_inferred_array_element_types" {
    const path = "tests/feature_tests/basics/42_inferred_array_element_types";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/basics/43X_heterogeneous_array_inference" {
    try buildExpectFailWithoutNoise("tests/feature_tests/basics/43X_heterogeneous_array_inference", "cannot infer the array type of 'values' from this literal; add an explicit array type annotation", "UnsupportedGlobalSemantic");
}

test "feature_tests/basics/44X_ragged_array_inference" {
    try buildExpectFailWithoutNoise("tests/feature_tests/basics/44X_ragged_array_inference", "cannot infer the array type of 'values' from this literal; add an explicit array type annotation", "UnsupportedGlobalSemantic");
}

test "feature_tests/basics/45X_empty_array_inference" {
    try buildExpectFailWithoutNoise("tests/feature_tests/basics/45X_empty_array_inference", "cannot infer the array type of 'values' from this literal; add an explicit array type annotation", "UnsupportedGlobalSemantic");
}

test "feature_tests/basics/46X_nested_empty_array_inference" {
    try buildExpectFailWithoutNoise("tests/feature_tests/basics/46X_nested_empty_array_inference", "cannot infer the array type of 'values' from this literal; add an explicit array type annotation", "UnsupportedGlobalSemantic");
}

test "C interop links native archives by file and library name" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmpDirRootPath(&tmp);
    defer allocator.free(root);
    const argi = try installedArgiPath();
    defer allocator.free(argi);
    const repo = try repoRootPrefix();
    defer allocator.free(repo);
    const fixture = try std.fs.path.join(allocator, &.{ repo, "tests/feature_tests/c_interop/01_native_library" });
    defer allocator.free(fixture);
    const source = try std.fs.path.join(allocator, &.{ fixture, "native.c" });
    defer allocator.free(source);
    const compiled = try runChildInCwd(&.{ "cc", "-c", source, "-o", "native.o" }, root);
    defer allocator.free(compiled.stdout);
    defer allocator.free(compiled.stderr);
    try expectEqual(std.process.Child.Term{ .exited = 0 }, compiled.term);
    const archived = try runChildInCwd(&.{ "ar", "rcs", "libargi_fixture.a", "native.o" }, root);
    defer allocator.free(archived.stdout);
    defer allocator.free(archived.stderr);
    try expectEqual(std.process.Child.Term{ .exited = 0 }, archived.term);
    for (0..2) |mode| {
        const args: []const []const u8 = if (mode == 0)
            &.{ argi, "build", fixture, "--output", "app", "--link-file", "libargi_fixture.a" }
        else
            &.{ argi, "build", fixture, "--output", "app", "--library-path", ".", "--link-library", "argi_fixture" };
        const built = try runChildInCwd(args, root);
        defer allocator.free(built.stdout);
        defer allocator.free(built.stderr);
        if (built.term != .exited or built.term.exited != 0) std.debug.print("{s}", .{built.stderr});
        try expectEqual(std.process.Child.Term{ .exited = 0 }, built.term);
        const executed = try runChildInCwd(&.{"./app"}, root);
        defer allocator.free(executed.stdout);
        defer allocator.free(executed.stderr);
        try expectEqual(std.process.Child.Term{ .exited = 0 }, executed.term);
    }
    // A package can be built from elsewhere, from its module, or run at its
    // root without relying on the caller's directory for native input paths.
    try tmp.dir.createDirPath(std.testing.io, "source/app");
    const rg_path = try std.fs.path.join(allocator, &.{ fixture, "main.rg" });
    defer allocator.free(rg_path);
    const rg_source = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, rg_path, allocator, .limited(8192));
    defer allocator.free(rg_source);
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "source/app/main.rg", .data = rg_source });
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "argi.toml", .data =
        \\[executables.app]
        \\path = "source/app"
        \\[[native]]
        \\file = "libargi_fixture.a"
    });
    const module_path = try std.fs.path.join(allocator, &.{ root, "source/app" });
    defer allocator.free(module_path);
    for ([_][]const u8{ root, module_path }) |target| {
        const built = try runChildInCwd(&.{ argi, "build", target }, repo);
        defer allocator.free(built.stdout);
        defer allocator.free(built.stderr);
        if (built.term != .exited or built.term.exited != 0) std.debug.print("{s}", .{built.stderr});
        try expectEqual(std.process.Child.Term{ .exited = 0 }, built.term);
    }
    const ran = try runChildInCwd(&.{ argi, "run" }, root);
    defer allocator.free(ran.stdout);
    defer allocator.free(ran.stderr);
    try expectEqual(std.process.Child.Term{ .exited = 0 }, ran.term);
    const missing = try runChildInCwd(&.{ argi, "build", fixture, "--output", "missing", "--link-library", "argi_missing_library_fixture" }, root);
    defer allocator.free(missing.stdout);
    defer allocator.free(missing.stderr);
    try expectEqual(std.process.Child.Term{ .exited = 1 }, missing.term);
    try expect(std.mem.indexOf(u8, missing.stderr, "argi_missing_library_fixture") != null);
}

test "C interop rejects unsupported signatures during exhaustive checking" {
    const cases = .{
        .{ "tests/feature_tests/c_interop/02X_aggregate_argument", "input 'value' has an unsupported C ABI type" },
        .{ "tests/feature_tests/c_interop/03X_multiple_outputs", "must have zero or one output" },
        .{ "tests/feature_tests/c_interop/04X_aggregate_result", "output 'result' has an unsupported C ABI type" },
    };
    inline for (cases) |case| {
        for ([_][]const u8{ "build", "check" }) |command| {
            const result = try runArgiCommand(&.{ command, case[0] });
            defer std.testing.allocator.free(result.stdout);
            defer std.testing.allocator.free(result.stderr);
            try expectEqual(std.process.Child.Term{ .exited = 1 }, result.term);
            try expect(std.mem.indexOf(u8, result.stderr, case[1]) != null);
            try expect(std.mem.indexOf(u8, result.stderr, "failed without a diagnostic") == null);
        }
    }
}

test "C interop symbol aliases reuse one external symbol across cached builds" {
    const path = "tests/feature_tests/c_interop/05_symbol_alias";
    for (0..2) |_| {
        try expectArgiBuildSuccess(&.{ "build", path });
        const output = try outputPathFor(path);
        defer std.testing.allocator.free(output);
        const result = try runChild(&.{output});
        defer std.testing.allocator.free(result.stdout);
        defer std.testing.allocator.free(result.stderr);
        try expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    }
}

test "C interop diagnoses invalid symbol options and conflicting declarations" {
    try buildExpectFailWithoutNoise("tests/feature_tests/c_interop/06X_invalid_symbol_options", "CFunction '.symbol' requires a string literal", "failed without a diagnostic");
    try buildExpectFailWithoutNoise("tests/feature_tests/c_interop/07X_conflicting_symbols", "C symbol 'abs' is declared with incompatible signatures", "failed without a diagnostic");
}

test "C interop exports are reachable from native code without Argi callers" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmpDirRootPath(&tmp);
    defer allocator.free(root);
    const argi = try installedArgiPath();
    defer allocator.free(argi);
    const repo = try repoRootPrefix();
    defer allocator.free(repo);
    const fixture = try std.fs.path.join(allocator, &.{ repo, "tests/feature_tests/c_interop/08_exported_functions" });
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
        try expect(std.mem.indexOf(u8, ir, "define i32 @argi_export_sum(i32") != null);
        try expect(std.mem.indexOf(u8, ir, "define void @argi_export_set(ptr") != null);
    }
}

test "C interop validates exported bodies and signatures" {
    try buildExpectFailWithoutNoise("tests/feature_tests/c_interop/09X_export_without_body", "an exported CFunction requires a body", "failed without a diagnostic");
    try buildExpectFailWithoutNoise("tests/feature_tests/c_interop/10X_export_aggregate", "input 'value' has an unsupported C ABI type", "failed without a diagnostic");
    try buildExpectFailWithoutNoise("tests/feature_tests/c_interop/11X_duplicate_exports", "C symbol 'argi_duplicate' has multiple definitions", "failed without a diagnostic");
    try buildExpectFailWithoutNoise("tests/feature_tests/c_interop/12X_reserved_export", "C export symbol 'main' is reserved", "failed without a diagnostic");
}

test "C interop checks reached and explicit authorization without ABI arguments" {
    try expectSuccessfulBuild("tests/feature_tests/c_interop/13_foreign_capability");
    try run("tests/feature_tests/c_interop/13_foreign_capability");
    try expectSuccessfulBuild("tests/feature_tests/c_interop/22_byte_copy_without_ffi");
    try run("tests/feature_tests/c_interop/22_byte_copy_without_ffi");
}

test "C interop rejects missing invalid and stale authorization" {
    const cases = .{
        .{ "tests/feature_tests/c_interop/14X_missing_foreign_capability", ".ffi uses reach [ffi]" },
        .{ "tests/feature_tests/c_interop/15X_wrong_foreign_capability", "ForeignFunctionInterface" },
        .{ "tests/feature_tests/c_interop/16X_stale_foreign_capability", "binding 'storage' was moved" },
        .{ "tests/feature_tests/c_interop/17X_export_missing_capability", ".ffi uses reach [ffi]" },
        .{ "tests/feature_tests/c_interop/18X_legacy_missing_capability", ".ffi uses reach [ffi]" },
        .{ "tests/feature_tests/c_interop/19X_stale_wrapper_capability", "binding 'storage' was moved" },
        .{ "tests/feature_tests/c_interop/20X_reserved_capability_parameter", "reserve '.ffi' for the checked capability" },
        .{ "tests/feature_tests/c_interop/21X_counterfeit_foreign_capability", "ForeignFunctionInterface" },
        .{ "tests/feature_tests/c_interop/23X_memory_stale_capability", "binding 'storage' was moved" },
    };
    inline for (cases) |case| {
        try buildExpectFailWithoutNoise(case[0], case[1], "failed without a diagnostic");
    }
}

fn checkNativeCFixture(path: []const u8, ir_needles: []const []const u8) !void {
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

test "C interop adapts raw pointers for imports bodies and exports" {
    try checkNativeCFixture("tests/feature_tests/c_interop/24_raw_pointer_abi", &.{
        "declare ptr @argi_c_static()",
        "declare ptr @argi_c_echo(ptr)",
        "define ptr @argi_pointer_export(ptr",
    });
    try buildExpectFailWithoutNoise("tests/feature_tests/c_interop/25X_counterfeit_raw_pointer", "input 'pointer' has an unsupported C ABI type", "failed without a diagnostic");
}

test "C interop resolves target scalar aliases" {
    try checkNativeCFixture("tests/feature_tests/c_interop/26_c_scalar_aliases", &.{
        "declare i32 @argi_c_int(i32)",
        "declare double @argi_c_double(double)",
    });
}

test "C interop uses a bounded zlib checksum wrapper and manifest linking" {
    const allocator = std.testing.allocator;
    const fixture = "tests/feature_tests/c_interop/27_zlib_checksum";
    for (0..2) |_| {
        const built = try runArgiCommand(&.{ "build", fixture });
        defer allocator.free(built.stdout);
        defer allocator.free(built.stderr);
        if (built.term != .exited or built.term.exited != 0) std.debug.print("{s}", .{built.stderr});
        try expectEqual(std.process.Child.Term{ .exited = 0 }, built.term);
        const executed = try runChild(&.{"tests/feature_tests/c_interop/27_zlib_checksum/build/debug/checksum"});
        defer allocator.free(executed.stdout);
        defer allocator.free(executed.stderr);
        try expectEqual(std.process.Child.Term{ .exited = 0 }, executed.term);
    }
    try buildExpectFailWithoutNoise("tests/feature_tests/c_interop/28X_zlib_missing_capability", ".ffi uses reach [ffi]", "failed without a diagnostic");
}

test "C interop preserves explicit record layouts through native pointers" {
    try checkNativeCFixture("tests/feature_tests/c_interop/29_c_struct_layout", &.{
        "declare i32 @argi_c_payload_verify(ptr)",
        "declare void @argi_c_payload_fill(ptr)",
        "define i32 @argi_c_payload_export(ptr",
    });
    try buildExpectFailWithoutNoise("tests/feature_tests/c_interop/30X_c_struct_non_c_field", "field 'ordinary' has no supported C representation", "failed without a diagnostic");
    try buildExpectFailWithoutNoise("tests/feature_tests/c_interop/31X_c_struct_by_value", "input 'record' has an unsupported C ABI type", "failed without a diagnostic");
    try buildExpectFailWithoutNoise("tests/feature_tests/c_interop/32X_generic_c_struct_non_c_field", "field 'value' has no supported C representation", "failed without a diagnostic");
}

test "C interop extends narrow scalars according to the platform ABI" {
    const target = @import("builtin").target;
    const extends = target.cpu.arch == .x86_64 or (target.cpu.arch == .aarch64 and target.os.tag.isDarwin());
    try checkNativeCFixture("tests/feature_tests/c_interop/33_narrow_scalar_abi", if (extends) &.{
        "define signext i8 @argi_c_small_signed(i8 signext",
        "define zeroext i8 @argi_c_small_unsigned(i8 zeroext",
        "call signext i16 @argi_c_short_import(i16 signext",
        "declare zeroext i1 @argi_c_bool_import(i1 zeroext",
    } else &.{
        "define i8 @argi_c_small_signed(i8",
        "define i1 @argi_c_bool(i1",
    });
}

test "C interop adapts integer record arguments and results" {
    const x64 = @import("builtin").target.cpu.arch == .x86_64;
    try checkNativeCFixture("tests/feature_tests/c_interop/34_integer_record_abi", if (x64) &.{
        "declare i64 @argi_c_pair(i64)",
        "declare { i64, i64 } @argi_c_words(i64, i64)",
        "byval({ i64, i64 }) align 8",
        "sret({ i64, i64, i64 }) align 8",
        "define i24 @argi_c_tiny_export(i24",
    } else &.{
        "declare i64 @argi_c_pair(i64)",
        "declare [2 x i64] @argi_c_words([2 x i64])",
        "sret({ i64, i64, i64 }) align 8",
        "define i24 @argi_c_tiny_export(i64",
    });
}

test "C interop diagnoses conflicting function ABI attributes" {
    try buildExpectFailWithoutNoise("tests/feature_tests/c_interop/35X_conflicting_record_abi", "C symbol 'argi_c_conflict' is declared with incompatible signatures", "failed without a diagnostic");
    const target = @import("builtin").target;
    if (target.cpu.arch == .x86_64 or target.os.tag.isDarwin())
        try buildExpectFailWithoutNoise("tests/feature_tests/c_interop/36X_conflicting_scalar_extension", "C symbol 'argi_c_conflict' is declared with incompatible signatures", "failed without a diagnostic");
}

test "C interop selects static and shared named libraries without fallback" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmpDirRootPath(&tmp);
    defer allocator.free(root);
    const argi = try installedArgiPath();
    defer allocator.free(argi);
    const repo = try repoRootPrefix();
    defer allocator.free(repo);
    const fixture = try std.fs.path.join(allocator, &.{ repo, "tests/feature_tests/c_interop/01_native_library" });
    defer allocator.free(fixture);
    const source = try std.fs.path.join(allocator, &.{ fixture, "native.c" });
    defer allocator.free(source);
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "shared.c", .data = "float argi_c_scale(int value, float factor) { (void)value; (void)factor; return 0; }" });
    const shared_path = try std.fs.path.join(allocator, &.{ root, if (@import("builtin").os.tag.isDarwin()) "libargi_mode_fixture.dylib" else "libargi_mode_fixture.so" });
    defer allocator.free(shared_path);
    for ([_][]const []const u8{
        &.{ "cc", "-c", source, "-o", "native.o" },
        &.{ "ar", "rcs", "libargi_mode_fixture.a", "native.o" },
        &.{ "cc", if (@import("builtin").os.tag.isDarwin()) "-dynamiclib" else "-shared", "-fPIC", "shared.c", "-o", shared_path },
    }) |args| {
        const result = try runChildInCwd(args, root);
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);
        try expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    }
    // The two artifacts return different results, so a successful link alone
    // cannot conceal selection of the wrong library mode.
    for ([_][]const u8{ "--link-static-library", "--link-shared-library" }, 0..) |flag, mode| {
        const built = try runChildInCwd(&.{ argi, "build", fixture, "--output", "app", flag, "argi_mode_fixture", "--library-path", "." }, root);
        defer allocator.free(built.stdout);
        defer allocator.free(built.stderr);
        if (built.term != .exited or built.term.exited != 0) std.debug.print("{s}", .{built.stderr});
        try expectEqual(std.process.Child.Term{ .exited = 0 }, built.term);
        const ran = try runChildInCwd(&.{"./app"}, root);
        defer allocator.free(ran.stdout);
        defer allocator.free(ran.stderr);
        try expectEqual(std.process.Child.Term{ .exited = @intCast(mode) }, ran.term);
    }
    try tmp.dir.createDirPath(std.testing.io, "source/app");
    const rg_path = try std.fs.path.join(allocator, &.{ fixture, "main.rg" });
    defer allocator.free(rg_path);
    const rg_source = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, rg_path, allocator, .limited(8192));
    defer allocator.free(rg_source);
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "source/app/main.rg", .data = rg_source });
    for ([_][]const u8{ "static_library", "shared_library" }, 0..) |key, mode| {
        const manifest = try std.fmt.allocPrint(allocator, "[executables.app]\npath = \"source/app\"\n[[native]]\n{s} = \"argi_mode_fixture\"\n[[native]]\nsearch_path = \".\"\n", .{key});
        defer allocator.free(manifest);
        try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "argi.toml", .data = manifest });
        const ran = try runChildInCwd(&.{ argi, "run" }, root);
        defer allocator.free(ran.stdout);
        defer allocator.free(ran.stderr);
        try expectEqual(std.process.Child.Term{ .exited = @intCast(mode) }, ran.term);
    }
    try tmp.dir.deleteFile(std.testing.io, "libargi_mode_fixture.a");
    const missing = try runChildInCwd(&.{ argi, "build", fixture, "--output", "missing", "--library-path", ".", "--link-static-library", "argi_mode_fixture" }, root);
    defer allocator.free(missing.stdout);
    defer allocator.free(missing.stderr);
    try expectEqual(std.process.Child.Term{ .exited = 1 }, missing.term);
    try expect(std.mem.indexOf(u8, missing.stderr, "static native library 'argi_mode_fixture' was not found") != null);
    try tmp.dir.deleteFile(std.testing.io, std.fs.path.basename(shared_path));
    const archived = try runChildInCwd(&.{ "ar", "rcs", "libargi_mode_fixture.a", "native.o" }, root);
    defer allocator.free(archived.stdout);
    defer allocator.free(archived.stderr);
    try expectEqual(std.process.Child.Term{ .exited = 0 }, archived.term);
    const missing_shared = try runChildInCwd(&.{ argi, "build", fixture, "--output", "missing", "--library-path", ".", "--link-shared-library", "argi_mode_fixture" }, root);
    defer allocator.free(missing_shared.stdout);
    defer allocator.free(missing_shared.stderr);
    try expectEqual(std.process.Child.Term{ .exited = 1 }, missing_shared.term);
    try expect(std.mem.indexOf(u8, missing_shared.stderr, "shared native library 'argi_mode_fixture' was not found") != null);
}

test "C interop adapts floating and mixed record arguments and results" {
    const target = @import("builtin").target;
    try checkNativeCFixture("tests/feature_tests/c_interop/37_numeric_record_abi", if (target.cpu.arch == .x86_64) &.{
        "declare float @argi_c_one(float)",
        "declare { <2 x float>, float } @argi_c_floats(<2 x float>, float)",
        "declare { i32, double } @argi_c_mixed(i32, double)",
        "declare { double, i32 } @argi_c_reverse(double, i32)",
        "byval({ float, float, float }) align 8",
        "sret({ [4 x double] }) align 8",
    } else if (target.os.tag.isDarwin()) &.{
        "declare { float } @argi_c_one([1 x float])",
        "declare { float, float, float } @argi_c_floats([3 x float])",
        "declare { double, double, double, double } @argi_c_doubles([4 x double])",
        "declare [2 x i64] @argi_c_mixed([2 x i64])",
    } else &.{
        "declare { float } @argi_c_one([1 x float] alignstack(8))",
        "declare { float, float, float } @argi_c_floats([3 x float] alignstack(8))",
        "declare { double, double, double, double } @argi_c_doubles([4 x double] alignstack(8))",
        "declare [2 x i64] @argi_c_mixed([2 x i64])",
    });
}

test "C interop adapts overlapping numeric union arguments and results" {
    try buildExpectFailWithoutNoise("tests/feature_tests/c_interop/39X_safe_reference_union_abi", "input 'value' has an unsupported C ABI type", "failed without a diagnostic");
    const target = @import("builtin").target;
    try checkNativeCFixture("tests/feature_tests/c_interop/38_numeric_union_abi", if (target.cpu.arch == .x86_64) &.{
        "declare i64 @argi_c_union_number(i64)",
        "declare float @argi_c_union_single(float)",
        "declare { <2 x float>, float } @argi_c_union_floats(<2 x float>, float)",
        "declare { double, float } @argi_c_union_mixed(double, float)",
        "sret({ [4 x double] }) align 8",
        "byval({ [3 x float] }) align 8",
    } else if (target.os.tag.isDarwin()) &.{
        "declare { float } @argi_c_union_single([1 x float])",
        "declare { float, float, float } @argi_c_union_floats([3 x float])",
        "declare { double, double, double, double } @argi_c_union_doubles([4 x double])",
        "declare [2 x i64] @argi_c_union_mixed([2 x i64])",
    } else &.{
        "declare { float } @argi_c_union_single([1 x float] alignstack(8))",
        "declare { float, float, float } @argi_c_union_floats([3 x float] alignstack(8))",
        "declare { double, double, double, double } @argi_c_union_doubles([4 x double] alignstack(8))",
        "declare [2 x i64] @argi_c_union_mixed([2 x i64])",
    });
}

test "C interop adapts raw pointer fields without accepting safe reference fields" {
    try buildExpectFailWithoutNoise("tests/feature_tests/c_interop/41X_safe_reference_array_abi", "input 'value' has an unsupported C ABI type", "failed without a diagnostic");
    try checkNativeCFixture("tests/feature_tests/c_interop/40_raw_pointer_record_abi", if (@import("builtin").target.cpu.arch == .x86_64) &.{
        "declare { i64, i64 } @argi_c_buffer_get()",
        "declare { i64, float } @argi_c_buffer_weighted(i64, float)",
        "byval({ { i64 }, i64 }) align 8",
        "sret({ { i64 }, i64, { i64 } }) align 8",
    } else &.{
        "declare [2 x i64] @argi_c_buffer_get()",
        "declare [2 x i64] @argi_c_buffer_weighted([2 x i64])",
        "sret({ { i64 }, i64, { i64 } }) align 8",
    });
}

test "C interop adapts raw pointer arrays and union alternatives" {
    try checkNativeCFixture("tests/feature_tests/c_interop/42_raw_pointer_aggregate_abi", if (@import("builtin").target.cpu.arch == .x86_64) &.{
        "declare { i64, i64 } @argi_c_pointers_get()",
        "declare i64 @argi_c_address_get()",
        "declare { i64, i64 } @argi_c_alternatives_get()",
        "byval({ [2 x { i64 }] }) align 8",
        "sret({ [2 x { { i64 }, i64 }] }) align 8",
    } else &.{
        "declare [2 x i64] @argi_c_pointers_get()",
        "declare i64 @argi_c_address_get()",
        "declare [2 x i64] @argi_c_alternatives_get()",
        "sret({ [2 x { { i64 }, i64 }] }) align 8",
    });
}

test "C interop preserves incomplete handle identities through raw pointers" {
    try checkNativeCFixture("tests/feature_tests/c_interop/43_incomplete_handles", &.{
        "declare ptr @argi_c_handle_create()",
        "define ptr @argi_c_handle_export(ptr",
    });
}

test "C interop rejects incomplete values construction layout and definitions" {
    try buildExpectFailWithoutNoise("tests/feature_tests/c_interop/44X_incomplete_by_value", "has no value representation", "failed without a diagnostic");
    try buildExpectFailWithoutNoise("tests/feature_tests/c_interop/45X_incomplete_size", "has no size or alignment", "failed without a diagnostic");
    try buildExpectFailWithoutNoise("tests/feature_tests/c_interop/46X_incomplete_construction", "cannot be constructed", "failed without a diagnostic");
    try buildExpectFailWithoutNoise("tests/feature_tests/c_interop/47X_incomplete_definition", "omit the definition", "failed without a diagnostic");
}

test "C interop rejects incompatible incomplete handles and safe references" {
    try buildExpectFailWithoutNoise("tests/feature_tests/c_interop/48X_incomplete_handle_identity", "no overload of '_read' accepts arguments", "failed without a diagnostic");
    try buildExpectFailWithoutNoise("tests/feature_tests/c_interop/49X_incomplete_safe_reference", "cannot form a safe reference", "failed without a diagnostic");
    try buildExpectFailWithoutNoise("tests/feature_tests/c_interop/50X_incomplete_alignment", "has no size or alignment", "failed without a diagnostic");
    try buildExpectFailWithoutNoise("tests/feature_tests/c_interop/51X_incomplete_value_storage", "has no value representation", "failed without a diagnostic");
    try buildExpectFailWithoutNoise("tests/feature_tests/c_interop/52X_incomplete_parameters", "cannot have compile-time parameters", "failed without a diagnostic");
}

test "C interop pairs owned handle acquisition and automatic cleanup" {
    try checkNativeCFixture("tests/feature_tests/c_interop/53_owned_foreign_handles", &.{
        "declare ptr @argi_c_owned_create(i32",
        "declare void @argi_c_owned_destroy(ptr",
    });
}

test "C interop protects owned handles and their retained capabilities" {
    try buildExpectFailWithoutNoise("tests/feature_tests/c_interop/54X_owned_handle_copy", "cannot be copied implicitly", "failed without a diagnostic");
    try buildExpectFailWithoutNoise("tests/feature_tests/c_interop/55X_owned_handle_after_cleanup", "reference depends on a root that has ended", "failed without a diagnostic");
    try buildExpectFailWithoutNoise("tests/feature_tests/c_interop/56X_owned_handle_stale_capability", "binding 'capability' was moved", "failed without a diagnostic");
    try buildExpectFailWithoutNoise("tests/feature_tests/c_interop/57X_owned_handle_private_storage", "field '_handle' is private to its module", "failed without a diagnostic");
    try buildExpectFailWithoutNoise("tests/feature_tests/c_interop/58X_owned_handle_stale_cleanup", "binding 'capability' was moved", "failed without a diagnostic");
}

test "feature_tests/modules/32_qualified_comptime_calls" {
    const test_path = "tests/feature_tests/modules/32_qualified_comptime_calls";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/modules/33X_qualified_comptime_call_missing_input" {
    try buildExpectFailWithoutNoise("tests/feature_tests/modules/33X_qualified_comptime_call_missing_input", "ExpectedLeftParen", "failed without a diagnostic");
}

test "C interop invokes host-managed scalar and record callbacks" {
    try checkNativeCFixture("tests/feature_tests/c_interop/59_host_managed_callbacks", &.{
        "define i32 @argi_callback_add(i32",
        "@argi_callback_packet(",
        "define void @argi_callback_packet(ptr sret(",
    });
}

test "C interop preserves explicit enum values across modules and caching" {
    try checkNativeCFixture("tests/feature_tests/c_interop/60_explicit_enum_values", &.{
        "define i32 @argi_enum_next(i32",
        "i32 -2147483648",
        "i32 2147483647",
    });
}

test "C interop rejects 61X_enum_value_overflow" {
    try buildExpectFailWithoutNoise("tests/feature_tests/c_interop/61X_enum_value_overflow", "CEnum value is outside", "failed without a diagnostic");
}

test "C interop rejects 62X_enum_implicit_overflow" {
    try buildExpectFailWithoutNoise("tests/feature_tests/c_interop/62X_enum_implicit_overflow", "CEnum value is outside", "failed without a diagnostic");
}

test "C interop rejects 63X_enum_value_not_integer" {
    try buildExpectFailWithoutNoise("tests/feature_tests/c_interop/63X_enum_value_not_integer", "CEnum value must be an Int32 integer literal", "failed without a diagnostic");
}

test "C interop rejects 64X_enum_duplicate_value" {
    try buildExpectFailWithoutNoise("tests/feature_tests/c_interop/64X_enum_duplicate_value", "duplicate CEnum numeric values", "failed without a diagnostic");
}

test "C interop diagnoses unsupported enum constant expressions" {
    try buildExpectFailWithoutNoise("tests/feature_tests/c_interop/65X_enum_constant_expression", "constant expressions are not supported", "failed without a diagnostic");
}

test "C interop transports nominal callback pointers and record fields" {
    try checkNativeCFixture("tests/feature_tests/c_interop/66_typed_callback_transport", &.{
        "declare ptr @argi_callback_lookup()",
        "define ptr @argi_callback_echo(ptr",
        "declare i32 @argi_callback_apply(ptr",
    });
}

test "C interop rejects 67X_callback_wrong_body_signature" {
    try buildExpectFailWithoutNoise("tests/feature_tests/c_interop/67X_callback_wrong_body_signature", "no visible concrete CFunction body matches", "failed without a diagnostic");
}

test "C interop rejects 68X_callback_argi_body" {
    try buildExpectFailWithoutNoise("tests/feature_tests/c_interop/68X_callback_argi_body", "no visible concrete CFunction body matches", "failed without a diagnostic");
}

test "C interop rejects 69X_callback_numeric_construction" {
    try buildExpectFailWithoutNoise("tests/feature_tests/c_interop/69X_callback_numeric_construction", "construction requires '.function = name'", "failed without a diagnostic");
}

test "C interop rejects 70X_callback_safe_reference" {
    try buildExpectFailWithoutNoise("tests/feature_tests/c_interop/70X_callback_safe_reference", "parameters require RawPointer", "failed without a diagnostic");
}

test "C interop rejects 71X_callback_declared_body" {
    try buildExpectFailWithoutNoise("tests/feature_tests/c_interop/71X_callback_declared_body", "without symbol options or a body", "failed without a diagnostic");
}

test "C interop rejects 72X_callback_nominal_identity" {
    try buildExpectFailWithoutNoise("tests/feature_tests/c_interop/72X_callback_nominal_identity", "no overload of", "failed without a diagnostic");
}

test "C interop rejects 73X_callback_missing_capability" {
    try buildExpectFailWithoutNoise("tests/feature_tests/c_interop/73X_callback_missing_capability", ".ffi uses reach [ffi]", "failed without a diagnostic");
}

test "C interop rejects 74X_callback_body_missing_capability" {
    try buildExpectFailWithoutNoise("tests/feature_tests/c_interop/74X_callback_body_missing_capability", ".ffi uses reach [ffi]", "failed without a diagnostic");
}

test "C interop rejects 75X_callback_multiple_outputs" {
    try buildExpectFailWithoutNoise("tests/feature_tests/c_interop/75X_callback_multiple_outputs", "must have zero or one output", "failed without a diagnostic");
}

test "C interop rejects 76X_callback_once_body" {
    try buildExpectFailWithoutNoise("tests/feature_tests/c_interop/76X_callback_once_body", "no visible concrete CFunction body matches", "failed without a diagnostic");
}

test "C interop selects typed record callbacks with indirect results" {
    try checkNativeCFixture("tests/feature_tests/c_interop/77_typed_record_callback", &.{
        "declare i32 @argi_typed_callback_probe(ptr",
        "sret({ double, i32, { i64 } })",
    });
}

test "C interop checks null callback values" {
    try checkNativeCFixture("tests/feature_tests/c_interop/78_callback_null", &.{
        "declare ptr @argi_callback_lookup(i32",
        "icmp eq ptr",
        "ptr null",
    });
}

test "C interop checks indirect callback invocation arguments and capabilities" {
    const cases = .{
        .{ "tests/feature_tests/c_interop/79X_callback_invocation_missing_capability", ".ffi uses reach [ffi]" },
        .{ "tests/feature_tests/c_interop/80X_callback_invocation_wrong_argument", "arguments do not match the C callback signature" },
        .{ "tests/feature_tests/c_interop/81X_callback_invocation_non_callable", "expected a CFunctionPointer value" },
        .{ "tests/feature_tests/c_interop/82X_callback_invocation_moved_value", "binding 'callback' was moved" },
        .{ "tests/feature_tests/c_interop/84X_callback_invocation_stale_capability", "binding 'storage' was moved" },
        .{ "tests/feature_tests/c_interop/86X_callback_wrapper_stale_capability", "binding 'storage' was moved" },
        .{ "tests/feature_tests/c_interop/87X_callback_body_invocation_missing_capability", ".ffi uses reach [ffi]" },
    };
    inline for (cases) |case| {
        try buildExpectFailWithoutNoise(case[0], case[1], "failed without a diagnostic");
    }
}

test "C interop traps null callback invocation" {
    const path = "tests/feature_tests/c_interop/83X_callback_invocation_null";
    try expectSuccessfulBuild(path);
    try runExpectFailure(path);
}

test "C interop invokes narrow floating and void callbacks" {
    try checkNativeCFixture("tests/feature_tests/c_interop/85_callback_invocation_scalar_signatures", &.{
        "callback.nonnull",
        "call signext i16 %",
        "i8 signext",
        "call double %",
        "call void %",
    });
}

test "feature_tests/basics/47_contextual_float_literals" {
    const path = "tests/feature_tests/basics/47_contextual_float_literals";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/basics/48X_numeric_record_field" {
    try buildExpectFail("tests/feature_tests/basics/48X_numeric_record_field", "cannot assign numeric value of type");
}

test "feature_tests/basics/49_release_ir_optimization" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmpDirRootPath(&tmp);
    defer allocator.free(root);
    const fixture = "tests/feature_tests/basics/49_release_ir_optimization";
    const debug_ir = try std.fs.path.join(allocator, &.{ root, "debug.ll" });
    defer allocator.free(debug_ir);
    const release_ir = try std.fs.path.join(allocator, &.{ root, "release.ll" });
    defer allocator.free(release_ir);
    try expectArgiBuildSuccess(&.{ "build", fixture, "--emit-llvm", debug_ir });
    try runExpect(fixture, 0);
    try expectArgiBuildSuccess(&.{ "build", fixture, "--release", "--emit-llvm", release_ir });
    try runExpect(fixture, 0);
    const before = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, debug_ir, allocator, .limited(1024 * 1024));
    defer allocator.free(before);
    const after = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, release_ir, allocator, .limited(1024 * 1024));
    defer allocator.free(after);
    try expect(std.mem.count(u8, before, "alloca ") > std.mem.count(u8, after, "alloca "));
    try expect(std.mem.count(u8, before, "store i1 ") > std.mem.count(u8, after, "store i1 "));
}

test "feature_tests/cross_compilation/01_aarch64_data_model" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmpDirRootPath(&tmp);
    defer allocator.free(root);
    const object_path = try std.fs.path.join(allocator, &.{ root, "arm64.o" });
    defer allocator.free(object_path);
    const fixture = "tests/feature_tests/cross_compilation/01_aarch64_data_model";
    // The second process exercises durable ModuleSG reuse for this target.
    for (0..2) |_| try expectArgiBuildSuccess(&.{ "build", fixture, "--target", "aarch64-linux-gnu", "--just-emit-obj", object_path });
    const object = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, object_path, allocator, .limited(1024 * 1024));
    defer allocator.free(object);
    try expectEqualStrings("\x7fELF", object[0..4]);
    try expectEqual(@as(u16, 183), std.mem.readInt(u16, object[18..20], .little));
    // The same sources cannot reuse ARM64's unsigned CChar decision on x86_64.
    const other = try runArgiCommand(&.{ "build", fixture, "--target", "x86_64-linux-gnu", "--just-emit-obj", object_path });
    defer allocator.free(other.stdout);
    defer allocator.free(other.stderr);
    try expectEqual(std.process.Child.Term{ .exited = 1 }, other.term);
    try expect(std.mem.indexOf(u8, other.stderr, "255") != null);
}

test "cross compilation rejects incompatible run targets" {
    const target = if (@import("builtin").cpu.arch == .aarch64 and @import("builtin").os.tag == .linux) "x86_64-linux-gnu" else "aarch64-linux-gnu";
    const result = try runArgiCommand(&.{ "run", "tests/feature_tests/basics/01_minimal_main", "--target", target });
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);
    try expectEqual(std.process.Child.Term{ .exited = 1 }, result.term);
    try expect(std.mem.indexOf(u8, result.stderr, "cannot execute an incompatible target") != null);
}

test "feature_tests/cross_compilation/02_aarch64_c_roundtrip" {
    const allocator = std.testing.allocator;
    var env_map = try std.testing.environ.createMap(allocator);
    defer env_map.deinit();
    const cc = env_map.get("ARGI_CROSS_CC") orelse return error.SkipZigTest;
    const runner = env_map.get("ARGI_CROSS_RUNNER") orelse return error.SkipZigTest;
    const runtime_root = env_map.get("ARGI_CROSS_RUNTIME_ROOT") orelse return error.SkipZigTest;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmpDirRootPath(&tmp);
    defer allocator.free(root);
    const repo = try repoRootPrefix();
    defer allocator.free(repo);
    const fixture = try std.fs.path.join(allocator, &.{ repo, "tests/feature_tests/cross_compilation/02_aarch64_c_roundtrip" });
    defer allocator.free(fixture);
    const native = try std.fs.path.join(allocator, &.{ fixture, "native.c" });
    defer allocator.free(native);
    const compiled = try runChildInCwd(&.{ cc, "-c", native, "-o", "native.o" }, root);
    defer allocator.free(compiled.stdout);
    defer allocator.free(compiled.stderr);
    if (compiled.term != .exited or compiled.term.exited != 0) std.debug.print("cross C fixture failed: {s}\n", .{compiled.stderr});
    try expectEqual(std.process.Child.Term{ .exited = 0 }, compiled.term);
    const argi = try installedArgiPath();
    defer allocator.free(argi);
    for ([_][]const u8{ "--stats", "--release" }) |mode| {
        const built = try runChildInCwd(&.{ argi, "build", fixture, "--target", "aarch64-linux-gnu", "--cc", cc, "--link-file", "native.o", "--output", "app", mode }, root);
        defer allocator.free(built.stdout);
        defer allocator.free(built.stderr);
        if (built.term != .exited or built.term.exited != 0) std.debug.print("cross build failed: {s}\n", .{built.stderr});
        try expectEqual(std.process.Child.Term{ .exited = 0 }, built.term);
        const executed = try runChildInCwd(&.{ runner, "-L", runtime_root, "./app" }, root);
        defer allocator.free(executed.stdout);
        defer allocator.free(executed.stderr);
        try expectEqual(std.process.Child.Term{ .exited = 0 }, executed.term);
    }
}

test "cross compilation requires an explicitly configured driver" {
    const allocator = std.testing.allocator;
    var env_map = try std.testing.environ.createMap(allocator);
    defer env_map.deinit();
    _ = env_map.swapRemove("CC");
    const target = if (@import("builtin").cpu.arch == .aarch64 and @import("builtin").os.tag == .linux) "x86_64-linux-gnu" else "aarch64-linux-gnu";
    const result = try runArgiCommandWithEnv(&.{ "build", "tests/feature_tests/basics/01_minimal_main", "--target", target }, &env_map);
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    try expectEqual(std.process.Child.Term{ .exited = 1 }, result.term);
    try expect(std.mem.indexOf(u8, result.stderr, "requires an explicit toolchain") != null);
}

test "cross compilation rejects the host C driver" {
    const target = if (@import("builtin").cpu.arch == .aarch64 and @import("builtin").os.tag == .linux) "x86_64-linux-gnu" else "aarch64-linux-gnu";
    const result = try runArgiCommand(&.{ "build", "tests/feature_tests/basics/01_minimal_main", "--target", target, "--cc", "cc" });
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);
    try expectEqual(std.process.Child.Term{ .exited = 1 }, result.term);
    try expect(std.mem.indexOf(u8, result.stderr, "incompatible with") != null);
}

test "feature_tests/basics/50X_undeclared_assignment" {
    try buildExpectFailExact("tests/feature_tests/basics/50X_undeclared_assignment",
        \\tests/feature_tests/basics/50X_undeclared_assignment/main.rg:2:5: error: cannot assign to undeclared binding 'value'; declare it first with ':=' or '::='
        \\      value = 1
        \\      ^
        \\
    );
}

test "feature_tests/basics/51X_array_outer_length" {
    try buildExpectFail("tests/feature_tests/basics/51X_array_outer_length", "array initializer has 2 elements; expected 3");
}

test "feature_tests/basics/52X_array_inner_length" {
    try buildExpectFail("tests/feature_tests/basics/52X_array_inner_length", "array initializer has 2 elements; expected 3");
}

test "feature_tests/basics/53X_array_reference_shape" {
    try buildExpectFail("tests/feature_tests/basics/53X_array_reference_shape", "array value has type '&[3][3]Int32'; expected '&[2][2]Int32'");
}

test "feature_tests/basics/54_generic_numeric_zero" {
    const path = "tests/feature_tests/basics/54_generic_numeric_zero";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/basics/55_large_aggregate_returns" {
    const path = "tests/feature_tests/basics/55_large_aggregate_returns";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/basics/56_temporary_record_array_read" {
    const path = "tests/feature_tests/basics/56_temporary_record_array_read";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/basics/57X_temporary_record_array_bounds" {
    const path = "tests/feature_tests/basics/57X_temporary_record_array_bounds";
    try expectSuccessfulBuild(path);
    try runExpectFailure(path);
}

test "feature_tests/io/33_print_owned_text" {
    const path = "tests/feature_tests/io/33_print_owned_text";
    try expectSuccessfulBuild(path);
    try runExpectStdout(path, 0, "Hello world 123\n123!\n123123\nleftright\ninline 123\n");
}

test "feature_tests/io/34_print_terminator" {
    const path = "tests/feature_tests/io/34_print_terminator";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/system/48_windows_path_roots" {
    if (@import("builtin").os.tag != .windows) return error.SkipZigTest;
    const test_path = "tests/feature_tests/system/48_windows_path_roots";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "diagnostic path normalization preserves code excerpt spelling" {
    var bytes = "tests\\feature_tests\\case\\main.rg:2:5: error: invalid value\n    path := \"C:\\file.rg:test\"\n".*;
    normalizeDiagnosticPaths(&bytes);
    try expectEqualStrings("tests/feature_tests/case/main.rg:2:5: error: invalid value\n    path := \"C:\\file.rg:test\"\n", &bytes);
}

test "diagnostic path normalization handles related source locations" {
    var bytes = "tests\\case\\main.rg:2:5: error: already used (first use at tests\\case\\main.rg:1:1)\n      file: tests\\case\\other.rg:7:1\n".*;
    normalizeDiagnosticPaths(&bytes);
    try expectEqualStrings("tests/case/main.rg:2:5: error: already used (first use at tests/case/main.rg:1:1)\n      file: tests/case/other.rg:7:1\n", &bytes);
}

test "feature_tests/system/49_target_selection" {
    const test_path = "tests/feature_tests/system/49_target_selection";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/system/50X_target_condition" {
    try buildExpectFailWithoutNoise("tests/feature_tests/system/50X_target_condition", "unknown OS, architecture, or ABI name", "failed without a diagnostic");
}

test "feature_tests/types/273_associated_constructor_dispatch" {
    const test_path = "tests/feature_tests/types/273_associated_constructor_dispatch";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}

test "feature_tests/types/274X_constructor_wrong_association" {
    try buildExpectFail("tests/feature_tests/types/274X_constructor_wrong_association", "initializer must return its constructed type");
}

test "feature_tests/types/275X_constructor_return_only_overloads" {
    try buildExpectFail("tests/feature_tests/types/275X_constructor_return_only_overloads", "ambiguous constructor call");
}

test "feature_tests/types/276X_constructor_unknown_type" {
    try buildExpectFail("tests/feature_tests/types/276X_constructor_unknown_type", "constructor type 'Missing' must name a type declared in this module");
}

test "feature_tests/types/277_associated_destructor_dispatch" {
    const test_path = "tests/feature_tests/types/277_associated_destructor_dispatch";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/types/278X_destructor_wrong_association" {
    try buildExpectFail("tests/feature_tests/types/278X_destructor_wrong_association", "destructor must receive a mutable reference to its associated type");
}

test "feature_tests/types/279X_destructor_unknown_type" {
    try buildExpectFail("tests/feature_tests/types/279X_destructor_unknown_type", "destructor type 'Missing' must name a type declared in this module");
}

test "feature_tests/basics/58_bracket_expression_grouping" {
    const path = "tests/feature_tests/basics/58_bracket_expression_grouping";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/basics/59X_empty_expression_grouping" {
    try buildExpectFail("tests/feature_tests/basics/59X_empty_expression_grouping", "expression grouping requires exactly one expression");
}

test "feature_tests/basics/60X_multiple_expression_grouping" {
    try buildExpectFail("tests/feature_tests/basics/60X_multiple_expression_grouping", "expected ']' after grouped expression");
}

test "feature_tests/ownership/300_opaque_scalar_borrow_cleanup" {
    const path = "tests/feature_tests/ownership/300_opaque_scalar_borrow_cleanup";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/ownership/301X_opaque_scalar_borrow_element_moved" {
    try buildExpectFail("tests/feature_tests/ownership/301X_opaque_scalar_borrow_element_moved", "place rooted at 'element' is moved and cannot be used");
}

test "feature_tests/basics/61_explicit_integer_conversions" {
    const path = "tests/feature_tests/basics/61_explicit_integer_conversions";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/basics/62_integer_conversion_ranges" {
    const path = "tests/feature_tests/basics/62_integer_conversion_ranges";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/basics/63X_implicit_integer_widening" {
    try buildExpectFail("tests/feature_tests/basics/63X_implicit_integer_widening", "implicit numeric conversion is not supported");
}

test "feature_tests/basics/64X_checked_integer_conversion_requires_errable" {
    try buildExpectFail("tests/feature_tests/basics/64X_checked_integer_conversion_requires_errable", "cannot assign a fallible numeric result directly");
}

test "feature_tests/basics/65_integer_conversion_error_trace" {
    const path = "tests/feature_tests/basics/65_integer_conversion_error_trace";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/modules/34X_missing_imported_type" {
    try buildExpectFailWithoutNoise("tests/feature_tests/modules/34X_missing_imported_type", "module 'dep' has no type named 'Missing'", "no matching function");
}

test "runtime safety diagnostics include cause and source location" {
    const cases = .{
        .{ "tests/feature_tests/basics/66X_runtime_abort_diagnostic", "main.rg:2:5: runtime error: explicit abort" },
        .{ "tests/feature_tests/collections/38X_fixed_array_index_out_of_bounds", "runtime error: array index is out of bounds" },
        .{ "tests/feature_tests/c_interop/83X_callback_invocation_null", "runtime error: cannot call a null C function pointer" },
    };
    inline for (cases) |case| {
        try expectSuccessfulBuild(case[0]);
        const path = try outputPathFor(case[0]);
        defer std.testing.allocator.free(path);
        const result = try runChild(&.{path});
        defer std.testing.allocator.free(result.stdout);
        defer std.testing.allocator.free(result.stderr);
        try expect(result.term != .exited or result.term.exited != 0);
        try expect(std.mem.indexOf(u8, result.stderr, case[1]) != null);
    }
}

test "formatter CLI checks prints and atomically updates source" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmpDirRootPath(&tmp);
    defer std.testing.allocator.free(root);
    const path = try std.fs.path.join(std.testing.allocator, &.{ root, "main.rg" });
    defer std.testing.allocator.free(path);
    const source = "main()->(.status_code:Int32=0):={ status_code=0 }\n";
    const expected = "main() -> (.status_code: Int32 = 0) := { status_code = 0 }\n";
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "main.rg", .data = source });
    const printed = try runArgiCommand(&.{ "format", path, "--stdout" });
    defer std.testing.allocator.free(printed.stdout);
    defer std.testing.allocator.free(printed.stderr);
    try expectEqual(std.process.Child.Term{ .exited = 0 }, printed.term);
    try expectEqualStrings(expected, printed.stdout);
    const checked = try runArgiCommand(&.{ "format", root, "--check" });
    defer std.testing.allocator.free(checked.stdout);
    defer std.testing.allocator.free(checked.stderr);
    try expectEqual(std.process.Child.Term{ .exited = 1 }, checked.term);
    const untouched = try tmp.dir.readFileAlloc(std.testing.io, "main.rg", std.testing.allocator, .limited(4096));
    defer std.testing.allocator.free(untouched);
    try expectEqualStrings(source, untouched);
    const written = try runArgiCommand(&.{ "format", root });
    defer std.testing.allocator.free(written.stdout);
    defer std.testing.allocator.free(written.stderr);
    try expectEqual(std.process.Child.Term{ .exited = 0 }, written.term);
    const contents = try tmp.dir.readFileAlloc(std.testing.io, "main.rg", std.testing.allocator, .limited(4096));
    defer std.testing.allocator.free(contents);
    try expectEqualStrings(expected, contents);
    const clean_check = try runArgiCommand(&.{ "format", root, "--check" });
    defer std.testing.allocator.free(clean_check.stdout);
    defer std.testing.allocator.free(clean_check.stderr);
    try expectEqual(std.process.Child.Term{ .exited = 0 }, clean_check.term);
    const app = try std.fs.path.join(std.testing.allocator, &.{ root, "app" });
    defer std.testing.allocator.free(app);
    try expectArgiBuildSuccess(&.{ "build", root, "--output", app });
}

test "feature_tests/basics/67_formatter_layout" {
    const path = "tests/feature_tests/basics/67_formatter_layout";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "formatter prepares all files before changing any source" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmpDirRootPath(&tmp);
    defer std.testing.allocator.free(root);
    const source = "main()->(.status_code:Int32=0):={}\n";
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "a.rg", .data = source });
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "b.rg", .data = "main(]" });
    const result = try runArgiCommand(&.{ "format", root });
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);
    try expectEqual(std.process.Child.Term{ .exited = 1 }, result.term);
    const after = try tmp.dir.readFileAlloc(std.testing.io, "a.rg", std.testing.allocator, .limited(4096));
    defer std.testing.allocator.free(after);
    try expectEqualStrings(source, after);
}

test "feature_tests/text/41_float_parsing" {
    const path = "tests/feature_tests/text/41_float_parsing";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/polymorphism/65_contextual_choice_arguments" {
    const path = "tests/feature_tests/polymorphism/65_contextual_choice_arguments";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/polymorphism/66X_contextual_choice_ambiguous" {
    try buildExpectFail("tests/feature_tests/polymorphism/66X_contextual_choice_ambiguous", "ambiguous call to 'select'");
}

test "feature_tests/basics/68_contextual_array_stores" {
    const path = "tests/feature_tests/basics/68_contextual_array_stores";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/basics/69X_typed_array_store" {
    try buildExpectFail("tests/feature_tests/basics/69X_typed_array_store", "implicit numeric conversion is not supported");
}

test "feature_tests/basics/70X_array_store_range" {
    try buildExpectFail("tests/feature_tests/basics/70X_array_store_range", "integer literal 256 does not fit in 'UInt8'");
}

test "feature_tests/io/35_numeric_writer_formatting" {
    const path = "tests/feature_tests/io/35_numeric_writer_formatting";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/text/42_numeric_formatting_allocations" {
    const path = "tests/feature_tests/text/42_numeric_formatting_allocations";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/io/36_float_writer_formatting" {
    const path = "tests/feature_tests/io/36_float_writer_formatting";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/text/43_float_formatting_allocations" {
    const path = "tests/feature_tests/text/43_float_formatting_allocations";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/text/44_float16_formatting_roundtrip" {
    const path = "tests/feature_tests/text/44_float16_formatting_roundtrip";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/numbers/01_pcg32" {
    const path = "tests/feature_tests/numbers/01_pcg32";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/numbers/02X_pcg32_private_state" {
    try buildExpectFail("tests/feature_tests/numbers/02X_pcg32_private_state", "field '_state' is private to its module");
}

test "feature_tests/numbers/03_duration" {
    const path = "tests/feature_tests/numbers/03_duration";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/numbers/04X_duration_private_state" {
    try buildExpectFail("tests/feature_tests/numbers/04X_duration_private_state", "field '_nanoseconds' is private to its module");
}

test "feature_tests/system/54_clock" {
    const path = "tests/feature_tests/system/54_clock";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/system/55_posix_clock_contract" {
    if (@import("builtin").os.tag == .windows) return error.SkipZigTest;
    try checkNativeCFixture("tests/feature_tests/system/55_posix_clock_contract", &.{ "@clock_gettime", "@nanosleep" });
}

test "feature_tests/system/56_windows_clock_adapter" {
    try checkNativeCFixture("tests/feature_tests/system/56_windows_clock_adapter", &.{"@argi_windows_clock_probe"});
}

test "feature_tests/system/57X_clock_missing_capability" {
    try buildExpectFail("tests/feature_tests/system/57X_clock_missing_capability", ".self uses reach [clock] expected as '&Clock'");
}

test "feature_tests/system/58X_clock_missing_ffi" {
    try buildExpectFail("tests/feature_tests/system/58X_clock_missing_ffi", "failed to initialize type 'Clock'");
}

test "feature_tests/system/59X_clock_domains" {
    try buildExpectFail("tests/feature_tests/system/59X_clock_domains", "no overload of 'elapsed' accepts arguments (.start: UnixTimestamp, .end: MonotonicInstant)");
}

test "feature_tests/system/60_processes" {
    const path = "tests/feature_tests/system/60_processes";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/system/61_process_errors" {
    const path = "tests/feature_tests/system/61_process_errors";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/system/62_process_termination" {
    const path = "tests/feature_tests/system/62_process_termination";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/system/63X_process_missing_capability" {
    try buildExpectFail("tests/feature_tests/system/63X_process_missing_capability", ".self uses reach [proc_man] expected as '&ProcessManager'");
}

test "feature_tests/system/64X_process_private_handle" {
    try buildExpectFail("tests/feature_tests/system/64X_process_private_handle", "field '_handle' is private to its module");
}

test "feature_tests/system/65X_process_stream_lifetime" {
    try buildExpectFail("tests/feature_tests/system/65X_process_stream_lifetime", "reference depends on a root that has ended");
}

test "feature_tests/system/66_windows_process_quoting" {
    try checkNativeCFixture("tests/feature_tests/system/66_windows_process_quoting", &.{"@argi_windows_process_quote_probe"});
}

test "feature_tests/system/67_posix_process_contract" {
    if (@import("builtin").os.tag == .windows) return error.SkipZigTest;
    try checkNativeCFixture("tests/feature_tests/system/67_posix_process_contract", &.{"@argi_posix_process_probe"});
}

test "feature_tests/system/68X_process_missing_ffi" {
    try buildExpectFail("tests/feature_tests/system/68X_process_missing_ffi", "failed to initialize type 'ProcessManager'");
}

test "feature_tests/system/69X_process_copy" {
    try buildExpectFailWithoutNoise("tests/feature_tests/system/69X_process_copy", "cannot be copied implicitly", "failed without a diagnostic");
}

test "feature_tests/system/70_process_argument_lifetime" {
    const path = "tests/feature_tests/system/70_process_argument_lifetime";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/semver/01_parse_compare" {
    const path = "tests/feature_tests/semver/01_parse_compare";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/semver/02_format" {
    const path = "tests/feature_tests/semver/02_format";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/semver/03X_private_state" {
    try buildExpectFail("tests/feature_tests/semver/03X_private_state", "field '_text' is private to its module");
}

test "feature_tests/semver/04X_view_lifetime" {
    try buildExpectFail("tests/feature_tests/semver/04X_view_lifetime", "reference depends on a root that has ended");
}

test "feature_tests/basics/71_large_numeric_array_branches" {
    const path = "tests/feature_tests/basics/71_large_numeric_array_branches";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

// CPython remains an optional native dependency. Supplying its adapter object
// and embedding library enables executable coverage without requiring Python
// development packages for ordinary compiler builds.
fn checkPythonFixture(path: []const u8) !void {
    const allocator = std.testing.allocator;
    var environment = try std.testing.environ.createMap(allocator);
    defer environment.deinit();
    const runtime = environment.get("ARGI_PYTHON_RUNTIME_OBJECT") orelse return error.SkipZigTest;
    const library = environment.get("ARGI_PYTHON_LIBRARY") orelse return error.SkipZigTest;
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
    const app = if (@import("builtin").os.tag == .windows) "app.exe" else "app";
    const executable = try std.fs.path.join(allocator, &.{ root, app });
    defer allocator.free(executable);
    for (0..2) |_| {
        const built = try runChildInCwd(&.{ argi, "build", fixture, "--output", app, "--link-file", runtime, "--link-file", library, "--emit-llvm", "app.ll" }, root);
        defer allocator.free(built.stdout);
        defer allocator.free(built.stderr);
        if (built.term != .exited or built.term.exited != 0) std.debug.print("{s}", .{built.stderr});
        try expectEqual(std.process.Child.Term{ .exited = 0 }, built.term);
        const executed = try runChildInCwd(&.{executable}, root);
        defer allocator.free(executed.stdout);
        defer allocator.free(executed.stderr);
        if (executed.term != .exited or executed.term.exited != 0) std.debug.print("{s}", .{executed.stderr});
        try expectEqual(std.process.Child.Term{ .exited = 0 }, executed.term);
        try expectEqualStrings("", executed.stderr);
        const ir = try tmp.dir.readFileAlloc(std.testing.io, "app.ll", allocator, .limited(16 * 1024 * 1024));
        defer allocator.free(ir);
        try expect(std.mem.indexOf(u8, ir, "@_argi_python_start") != null);
        try expect(std.mem.indexOf(u8, ir, "@_argi_python_stop") != null);
        try expect(std.mem.indexOf(u8, ir, "@_argi_python_release") != null);
    }
}

test "feature_tests/python/01_json" {
    try checkPythonFixture("tests/feature_tests/python/01_json");
}
test "feature_tests/python/02_values_errors" {
    try checkPythonFixture("tests/feature_tests/python/02_values_errors");
}
test "feature_tests/python/03_keywords" {
    try checkPythonFixture("tests/feature_tests/python/03_keywords");
}
test "feature_tests/python/04X_object_lifetime" {
    try buildExpectFail("tests/feature_tests/python/04X_object_lifetime", "reference depends on a root that has ended");
}
test "feature_tests/python/05X_object_copy" {
    try buildExpectFail("tests/feature_tests/python/05X_object_copy", "cannot be copied implicitly");
}
test "feature_tests/python/06X_private_handle" {
    try buildExpectFail("tests/feature_tests/python/06X_private_handle", "field '_handle' is private to its module");
}
test "feature_tests/python/07_object_escape" {
    try checkPythonFixture("tests/feature_tests/python/07_object_escape");
}

test "feature_tests/python/08_conversions" {
    try checkPythonFixture("tests/feature_tests/python/08_conversions");
}

test "feature_tests/python/09_methods_iteration" {
    try checkPythonFixture("tests/feature_tests/python/09_methods_iteration");
}

test "feature_tests/python/10_exceptions" {
    try checkPythonFixture("tests/feature_tests/python/10_exceptions");
}

test "feature_tests/python/11_numeric_buffers" {
    try checkPythonFixture("tests/feature_tests/python/11_numeric_buffers");
}
test "feature_tests/python/12X_numeric_readonly" {
    try buildExpectFail("tests/feature_tests/python/12X_numeric_readonly", "no overload of 'copy_numeric' accepts arguments");
}

test "feature_tests/functions/32_generic_view_dispatch_order" {
    const path = "tests/feature_tests/functions/32_generic_view_dispatch_order";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/system/71_system_entropy" {
    const path = "tests/feature_tests/system/71_system_entropy";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/system/72X_entropy_readonly" {
    try buildExpectFail("tests/feature_tests/system/72X_entropy_readonly", "no overload of 'fill_random_bytes' accepts arguments");
}

test "feature_tests/more/01_uri" {
    const path = "tests/feature_tests/more/01_uri";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/more/02_linear_algebra" {
    const path = "tests/feature_tests/more/02_linear_algebra";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/more/03X_matrix_dimensions" {
    try buildExpectFailWithoutNoise("tests/feature_tests/more/03X_matrix_dimensions", "repeated generic dimensions must agree", "failed without a diagnostic");
}

test "feature_tests/functions/33X_generic_conflict_diagnostic" {
    try buildExpectFailWithoutNoise("tests/feature_tests/functions/33X_generic_conflict_diagnostic", "conflicting inferred generic parameters", "failed without a diagnostic");
}

test "feature_tests/functions/34_pipe_value_expressions" {
    const path = "tests/feature_tests/functions/34_pipe_value_expressions";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/functions/35X_nested_pipe_requires_outer_placeholder" {
    try buildExpectFail("tests/feature_tests/functions/35X_nested_pipe_requires_outer_placeholder", "pipe right-hand side must use at least one argument placeholder");
}

test "feature_tests/functions/36_generic_pipe_temporary_escape" {
    try expectSuccessfulBuild("tests/feature_tests/functions/36_generic_pipe_temporary_escape");
    try runExpect("tests/feature_tests/functions/36_generic_pipe_temporary_escape", 0);
}

test "feature_tests/functions/37X_pipe_temporary_consumed_twice" {
    try buildExpectFail(
        "tests/feature_tests/functions/37X_pipe_temporary_consumed_twice",
        "was moved and cannot be used again",
    );
}

test "feature_tests/basics/72_multiline_operations" {
    const path = "tests/feature_tests/basics/72_multiline_operations";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/basics/73X_multiline_operation_missing_operand" {
    try buildExpectFail("tests/feature_tests/basics/73X_multiline_operation_missing_operand", "expected an expression after operator '+'");
}

test "feature_tests/basics/74X_leading_operator_requires_group" {
    try buildExpectFail("tests/feature_tests/basics/74X_leading_operator_requires_group", "a leading operator requires scalar grouping");
}

test "feature_tests/basics/75_fallible_main_success" {
    const path = "tests/feature_tests/basics/75_fallible_main_success";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/basics/76_fallible_main_trace" {
    const path = "tests/feature_tests/basics/76_fallible_main_trace";
    try expectSuccessfulBuild(path);
    const output = try outputPathFor(path);
    defer std.testing.allocator.free(output);
    const result = try runChild(&.{output});
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);
    try expectEqual(std.process.Child.Term{ .exited = 1 }, result.term);
    try expectEqualStrings("", result.stdout);
    try expect(std.mem.indexOf(u8, result.stderr, "error: unhandled error in main") != null);
    try expect(std.mem.indexOf(u8, result.stderr, "error trace (most recent first)") != null);
    try expect(std.mem.indexOf(u8, result.stderr, "starting application") != null);
    try expect(std.mem.indexOf(u8, result.stderr, "76_fallible_main_trace/main.rg:3:") != null);
}

test "feature_tests/basics/77_fallible_main_system" {
    const path = "tests/feature_tests/basics/77_fallible_main_system";
    try expectSuccessfulBuild(path);
    try runExpectStdoutWithArgs(path, &.{}, 0, "ready\n");
}

test "feature_tests/basics/78X_fallible_main_non_void" {
    try buildExpectFail("tests/feature_tests/basics/78X_fallible_main_non_void", "Expected main() -> (.status_code: Int32) or main() -> !Void.");
}

test "feature_tests/basics/79_fallible_main_custom_tracer" {
    const path = "tests/feature_tests/basics/79_fallible_main_custom_tracer";
    try expectSuccessfulBuild(path);
    const output = try outputPathFor(path);
    defer std.testing.allocator.free(output);
    const result = try runChild(&.{output});
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);
    try expectEqual(std.process.Child.Term{ .exited = 1 }, result.term);
    try expectEqualStrings("error: unhandled error in main\ncustom trace\n", result.stderr);
}

test "feature_tests/basics/80_fallible_output_defaults" {
    const path = "tests/feature_tests/basics/80_fallible_output_defaults";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/basics/81X_fallible_output_default_missing_value" {
    try buildExpectFail("tests/feature_tests/basics/81X_fallible_output_default_missing_value", "expected a default expression");
}

test "feature_tests/basics/82_fallible_main_explicit" {
    const path = "tests/feature_tests/basics/82_fallible_main_explicit";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/ownership/338X_caller_storage_overwritten_cleanup" {
    try buildExpectFail("tests/feature_tests/ownership/338X_caller_storage_overwritten_cleanup", "retained storage cleanup depends on a root that has ended");
}

test "feature_tests/ownership/339X_caller_storage_field_cleanup_borrow" {
    try buildExpectFail("tests/feature_tests/ownership/339X_caller_storage_field_cleanup_borrow", "retained storage cleanup depends on a root that has ended");
}

test "feature_tests/ownership/340_caller_storage_field_cleanup" {
    const path = "tests/feature_tests/ownership/340_caller_storage_field_cleanup";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/ownership/341X_caller_storage_array_cleanup_borrow" {
    try buildExpectFail("tests/feature_tests/ownership/341X_caller_storage_array_cleanup_borrow", "retained storage cleanup depends on a root that has ended");
}

test "feature_tests/ownership/342_caller_storage_array_cleanup" {
    const path = "tests/feature_tests/ownership/342_caller_storage_array_cleanup";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}

test "feature_tests/ownership/321_caller_storage_cleanup" {
    try expectSuccessfulBuild("tests/feature_tests/ownership/321_caller_storage_cleanup");
    try runExpect("tests/feature_tests/ownership/321_caller_storage_cleanup", 0);
}

test "feature_tests/ownership/322_caller_storage_forwarding" {
    try expectSuccessfulBuild("tests/feature_tests/ownership/322_caller_storage_forwarding");
    try runExpect("tests/feature_tests/ownership/322_caller_storage_forwarding", 0);
}

test "feature_tests/ownership/323_caller_storage_branches" {
    try expectSuccessfulBuild("tests/feature_tests/ownership/323_caller_storage_branches");
    try runExpect("tests/feature_tests/ownership/323_caller_storage_branches", 0);
}

test "feature_tests/ownership/324X_caller_storage_loop" {
    try buildExpectFail("tests/feature_tests/ownership/324X_caller_storage_loop", "use an explicit allocator");
}

test "feature_tests/ownership/325X_caller_storage_recursive" {
    try buildExpectFail("tests/feature_tests/ownership/325X_caller_storage_recursive", "recursive retention is not supported");
}

test "feature_tests/ownership/326X_caller_storage_scope" {
    try buildExpectFail("tests/feature_tests/ownership/326X_caller_storage_scope", "reference depends on a root that has ended");
}

test "feature_tests/basics/83_fallible_main_local_tracer" {
    const path = "tests/feature_tests/basics/83_fallible_main_local_tracer";
    try expectSuccessfulBuild(path);
    const output = try outputPathFor(path);
    defer std.testing.allocator.free(output);
    const result = try runChild(&.{output});
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);
    try expectEqual(std.process.Child.Term{ .exited = 1 }, result.term);
    try expectEqualStrings("", result.stdout);
    try expect(std.mem.indexOf(u8, result.stderr, "error trace (most recent first)") != null);
    try expect(std.mem.indexOf(u8, result.stderr, "83_fallible_main_local_tracer/main.rg:8:") != null);
}

test "feature_tests/ownership/327_caller_storage_generic" {
    try expectSuccessfulBuild("tests/feature_tests/ownership/327_caller_storage_generic");
    try runExpect("tests/feature_tests/ownership/327_caller_storage_generic", 0);
}

test "feature_tests/ownership/328X_caller_storage_virtual" {
    try buildExpectFail("tests/feature_tests/ownership/328X_caller_storage_virtual", "virtual methods cannot return local storage");
}

test "feature_tests/ownership/329X_caller_storage_dynamic_references" {
    try buildExpectFail("tests/feature_tests/ownership/329X_caller_storage_dynamic_references", "reference depends on a root that has ended");
}

test "feature_tests/ownership/330X_caller_storage_dynamic_wrapper" {
    try buildExpectFail("tests/feature_tests/ownership/330X_caller_storage_dynamic_wrapper", "reference depends on a root that has ended");
}

test "feature_tests/ownership/331_caller_storage_virtual_value" {
    try expectSuccessfulBuild("tests/feature_tests/ownership/331_caller_storage_virtual_value");
    try runExpect("tests/feature_tests/ownership/331_caller_storage_virtual_value", 0);
}

test "feature_tests/ownership/332_caller_storage_array" {
    try expectSuccessfulBuild("tests/feature_tests/ownership/332_caller_storage_array");
    try runExpect("tests/feature_tests/ownership/332_caller_storage_array", 0);
}

test "feature_tests/ownership/333_caller_storage_large_return" {
    try expectSuccessfulBuild("tests/feature_tests/ownership/333_caller_storage_large_return");
    try runExpect("tests/feature_tests/ownership/333_caller_storage_large_return", 0);
}

test "feature_tests/ownership/334_caller_storage_branch_initialization" {
    try expectSuccessfulBuild("tests/feature_tests/ownership/334_caller_storage_branch_initialization");
    try runExpect("tests/feature_tests/ownership/334_caller_storage_branch_initialization", 0);
}

test "feature_tests/ownership/335_caller_storage_cleanup_dependencies" {
    try expectSuccessfulBuild("tests/feature_tests/ownership/335_caller_storage_cleanup_dependencies");
    try runExpect("tests/feature_tests/ownership/335_caller_storage_cleanup_dependencies", 0);
}

test "feature_tests/ownership/336X_caller_storage_cleanup_borrow" {
    try buildExpectFail("tests/feature_tests/ownership/336X_caller_storage_cleanup_borrow", "root that has ended");
}

test "feature_tests/ownership/337X_caller_storage_cleanup_after_borrow" {
    try buildExpectFail("tests/feature_tests/ownership/337X_caller_storage_cleanup_after_borrow", "retained storage cleanup depends on a root that has ended");
}

test "feature_tests/errors/80_local_handle" {
    try expectSuccessfulBuild("tests/feature_tests/errors/80_local_handle");
    try runExpect("tests/feature_tests/errors/80_local_handle", 0);
}

test "feature_tests/errors/81X_handle_unassigned" {
    try buildExpectFail("tests/feature_tests/errors/81X_handle_unassigned", "cannot be used");
}

test "feature_tests/errors/82X_handle_duplicate_names" {
    try buildExpectFail("tests/feature_tests/errors/82X_handle_duplicate_names", "must have different names");
}

test "feature_tests/errors/83_handle_owner" {
    try expectSuccessfulBuild("tests/feature_tests/errors/83_handle_owner");
    try runExpect("tests/feature_tests/errors/83_handle_owner", 0);
}

test "feature_tests/polymorphism/51_virtual_associated_parameters" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/51_virtual_associated_parameters");
    try runExpect("tests/feature_tests/polymorphism/51_virtual_associated_parameters", 0);
}

test "feature_tests/collections/117_deque" {
    try expectSuccessfulBuild("tests/feature_tests/collections/117_deque");
    try runExpect("tests/feature_tests/collections/117_deque", 0);
}

test "feature_tests/collections/118_deque_ownership" {
    try expectSuccessfulBuild("tests/feature_tests/collections/118_deque_ownership");
    try runExpect("tests/feature_tests/collections/118_deque_ownership", 0);
}

test "feature_tests/collections/119_deque_growth_failure" {
    try expectSuccessfulBuild("tests/feature_tests/collections/119_deque_growth_failure");
    try runExpect("tests/feature_tests/collections/119_deque_growth_failure", 0);
}

test "feature_tests/collections/123_deque_zero_sized" {
    try expectSuccessfulBuild("tests/feature_tests/collections/123_deque_zero_sized");
    try runExpect("tests/feature_tests/collections/123_deque_zero_sized", 0);
}

test "feature_tests/collections/120X_deque_borrow_after_growth" {
    try buildExpectFail("tests/feature_tests/collections/120X_deque_borrow_after_growth", "root that has ended");
}

test "feature_tests/collections/121X_deque_borrow_after_pop" {
    try buildExpectFail("tests/feature_tests/collections/121X_deque_borrow_after_pop", "root that has ended");
}

test "feature_tests/collections/122X_deque_copy" {
    try buildExpectFail("tests/feature_tests/collections/122X_deque_copy", "cannot be copied implicitly");
}

test "feature_tests/system/73_network_loopback" {
    try expectSuccessfulBuild("tests/feature_tests/system/73_network_loopback");
    try runExpect("tests/feature_tests/system/73_network_loopback", 0);
}

test "feature_tests/system/74_network_errors" {
    try expectSuccessfulBuild("tests/feature_tests/system/74_network_errors");
    try runExpect("tests/feature_tests/system/74_network_errors", 0);
}

test "feature_tests/system/75X_network_owner_copy" {
    try buildExpectFail("tests/feature_tests/system/75X_network_owner_copy", "cannot be copied implicitly");
}

test "feature_tests/system/76X_network_private_handle" {
    try buildExpectFail("tests/feature_tests/system/76X_network_private_handle", "field '_handle' is private");
}

test "feature_tests/system/77X_network_after_cleanup" {
    try buildExpectFail("tests/feature_tests/system/77X_network_after_cleanup", "root that has ended");
}

test "feature_tests/system/78X_network_missing_capability" {
    try buildExpectFail("tests/feature_tests/system/78X_network_missing_capability", "network");
}

test "feature_tests/errors/84X_handle_non_errable" {
    try buildExpectFail("tests/feature_tests/errors/84X_handle_non_errable", "handle expects an Errable value");
}

test "feature_tests/polymorphism/52_virtual_bound_values" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/52_virtual_bound_values");
    try runExpect("tests/feature_tests/polymorphism/52_virtual_bound_values", 0);
}

test "feature_tests/polymorphism/53X_virtual_bound_value_mismatch" {
    try buildExpectFail("tests/feature_tests/polymorphism/53X_virtual_bound_value_mismatch", "does not implement the selected abstract");
}

test "feature_tests/polymorphism/54X_virtual_bound_borrow_after_cleanup" {
    try buildExpectFail("tests/feature_tests/polymorphism/54X_virtual_bound_borrow_after_cleanup", "root that has ended");
}

test "feature_tests/polymorphism/55X_virtual_method_generic" {
    try buildExpectFail("tests/feature_tests/polymorphism/55X_virtual_method_generic", "method-local generic parameters");
}

test "feature_tests/python/13_numpy_vector" {
    var environment = try std.testing.environ.createMap(std.testing.allocator);
    defer environment.deinit();
    if (!std.mem.eql(u8, environment.get("ARGI_PYTHON_NUMPY") orelse "", "1")) return error.SkipZigTest;
    try checkPythonFixture("tests/feature_tests/python/13_numpy_vector");
}

test "feature_tests/errors/85_handle_evaluation_cleanup" {
    try expectSuccessfulBuild("tests/feature_tests/errors/85_handle_evaluation_cleanup");
    try runExpect("tests/feature_tests/errors/85_handle_evaluation_cleanup", 0);
}

test "feature_tests/errors/86X_handle_local_borrow" {
    try buildExpectFail("tests/feature_tests/errors/86X_handle_local_borrow", "root that has ended");
}

test "feature_tests/errors/87X_handle_arbitrary_choice" {
    try buildExpectFail("tests/feature_tests/errors/87X_handle_arbitrary_choice", "handle expects an Errable value");
}

test "feature_tests/python/14X_numpy_copy" {
    try buildExpectFail("tests/feature_tests/python/14X_numpy_copy", "cannot be copied implicitly");
}

test "feature_tests/python/15X_numpy_context_lifetime" {
    try buildExpectFail("tests/feature_tests/python/15X_numpy_context_lifetime", "root that has ended");
}

test "feature_tests/python/16X_numpy_private_object" {
    try buildExpectFail("tests/feature_tests/python/16X_numpy_private_object", "field '_object' is private");
}

test "feature_tests/system/79_network_native" {
    try checkNativeCFixture("tests/feature_tests/system/79_network_native", &.{"declare i32 @argi_network_probe()"});
}

test "feature_tests/binary/01_endian" {
    try expectSuccessfulBuild("tests/feature_tests/binary/01_endian");
    try runExpect("tests/feature_tests/binary/01_endian", 0);
}

test "feature_tests/binary/02_cursor" {
    try expectSuccessfulBuild("tests/feature_tests/binary/02_cursor");
    try runExpect("tests/feature_tests/binary/02_cursor", 0);
}
