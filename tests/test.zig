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
    const root_with_sep = try std.fmt.allocPrint(std.testing.allocator, "{s}/", .{root});
    defer std.testing.allocator.free(root_with_sep);

    var normalized = result;
    const stdout = normalized.stdout;
    normalized.stdout = try std.mem.replaceOwned(u8, std.testing.allocator, stdout, root_with_sep, "");
    std.testing.allocator.free(stdout);

    const stderr = normalized.stderr;
    normalized.stderr = try std.mem.replaceOwned(u8, std.testing.allocator, stderr, root_with_sep, "");
    std.testing.allocator.free(stderr);

    return normalized;
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

test "installed argi test resolves core from its installation prefix outside repo" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.createDirPath(std.testing.io, "module");
    try tmp.dir.createDirPath(std.testing.io, "outside");

    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "module/main.rg",
        .data =
        \\test installed_prefix(.system: System = System()) -> !() := {
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

    const source_path = try std.fs.path.join(std.testing.allocator, &.{ tmp_root, "hello", "source", "entrypoints", "hello", "main.rg" });
    defer std.testing.allocator.free(source_path);
    try std.Io.Dir.cwd().access(std.testing.io, source_path, .{});
    const source_text = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, source_path, std.testing.allocator, .limited(1024 * 1024));
    defer std.testing.allocator.free(source_text);

    try expect(std.mem.indexOf(u8, text, "kind = ") == null);
    try expect(std.mem.indexOf(u8, text, "[executables.hello]\n") != null);
    try expect(std.mem.indexOf(u8, text, "path = \"source/entrypoints/hello\"\n") != null);
    try expect(std.mem.indexOf(u8, text, "[run]\n") != null);
    try expect(std.mem.indexOf(u8, text, "default = \"hello\"\n") != null);
    try expectEqualStrings("main(.system: System = System()) -> (.status_code: Int32 = 0) := {\n}\n", source_text);
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

test "argi build and run executable package from cwd" {
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

    const source_path = try std.fs.path.join(std.testing.allocator, &.{ module_root, "source", "entrypoints", "hello", "main.rg" });
    defer std.testing.allocator.free(source_path);

    try std.Io.Dir.cwd().writeFile(std.testing.io, .{
        .sub_path = source_path,
        .data =
        \\main(.system: System = System()) -> (.status_code: Int32 = 0) := {
        \\    print("Hello, World!\n")
        \\}
        \\
        ,
    });

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

test "feature_tests/functions/07X_pipe_expression_placeholder_not_supported" {
    try buildExpectFailExact("tests/feature_tests/functions/07X_pipe_expression_placeholder_not_supported",
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
    const test_path = "tests/feature_tests/pointers/06_explicit_pointer_casts";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
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
        \\tests/feature_tests/basics/17X_extern_call_requires_exact_argument_types/main.rg:3:12: error: no overload of 'putchar' accepts arguments (.character: UInt16). Available signatures:
        \\  - putchar (.character: UInt8) -> ()
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
        \\tests/feature_tests/ownership/05X_noncopyable_assignment/main.rg:9:15: error: type 'Resource' is not copyable, so it cannot be used by value here; pass it by '&' or '$&', or implement 'copy()'
        \\      second := first
        \\                ^
        \\
    );
}

test "feature_tests/ownership/06X_noncopyable_argument_by_value" {
    try buildExpectFailExact("tests/feature_tests/ownership/06X_noncopyable_argument_by_value",
        \\tests/feature_tests/ownership/06X_noncopyable_argument_by_value/main.rg:13:34: error: type 'Resource' is not copyable, so it cannot be used by value here; pass it by '&' or '$&', or implement 'copy()'
        \\      status_code = consume(.res = handle)
        \\                                   ^
        \\
    );
}

test "feature_tests/ownership/07X_noncopyable_struct_field" {
    try buildExpectFailExact("tests/feature_tests/ownership/07X_noncopyable_struct_field",
        \\tests/feature_tests/ownership/07X_noncopyable_struct_field/main.rg:13:33: error: type 'Resource' is not copyable, so it cannot be used by value here; pass it by '&' or '$&', or implement 'copy()'
        \\      wrapped : Wrapper = (.res = handle)
        \\                                  ^
        \\
    );
}

test "feature_tests/ownership/08X_noncopyable_output_binding" {
    try buildExpectFailExact("tests/feature_tests/ownership/08X_noncopyable_output_binding",
        \\tests/feature_tests/ownership/08X_noncopyable_output_binding/main.rg:8:11: error: type 'Resource' is not copyable, so it cannot be used by value here; pass it by '&' or '$&', or implement 'copy()'
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
        \\tests/feature_tests/ownership/14X_use_after_move/main.rg:14:34: error: binding 'handle' was moved and cannot be used again (moved at tests/feature_tests/ownership/14X_use_after_move/main.rg:13:34)
        \\      status_code = consume(.res = handle)
        \\                                   ^
        \\
    );
}

test "feature_tests/ownership/15X_reassign_after_move" {
    try buildExpectFailExact("tests/feature_tests/ownership/15X_reassign_after_move",
        \\tests/feature_tests/ownership/15X_reassign_after_move/main.rg:14:5: error: binding 'handle' was moved and cannot be reassigned (moved at tests/feature_tests/ownership/15X_reassign_after_move/main.rg:13:34)
        \\      handle = Resource()
        \\      ^
        \\
    );
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
        \\tests/feature_tests/types/32X_match_value_noncopyable_payload/main.rg:17:14: error: type '{...}' is not copyable, so it cannot be used by value here; pass it by '&' or '$&', or implement 'copy()'
        \\          ..ok payload {
        \\               ^
        \\
    );
}

test "feature_tests/types/47X_match_value_payload_ambiguous_copy" {
    try buildExpectFailExact("tests/feature_tests/types/47X_match_value_payload_ambiguous_copy",
        \\tests/feature_tests/types/47X_match_value_payload_ambiguous_copy/main.rg:26:14: error: ambiguous call to 'copy' for arguments (.__arg0: Payload). Possible overloads:
        \\  - copy (.payload: Payload, .tag: Int32) -> (.out: Payload)
        \\  - copy (.payload: Payload, .flag: Bool) -> (.out: Payload)
        \\  - copy (.allocator: $&Allocator, .self: String) -> (.out: String)
        \\  - copy (.self: Path, .allocator: $&Allocator) -> (.out: Path)
        \\          ..ok payload {
        \\               ^
        \\
    );
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
    try buildExpectFailExact("tests/feature_tests/types/49X_choice_payload_access_ambiguous_copy",
        \\tests/feature_tests/types/49X_choice_payload_access_ambiguous_copy/main.rg:24:21: error: ambiguous call to 'copy' for arguments (.__arg0: Payload). Possible overloads:
        \\  - copy (.payload: Payload, .tag: Int32) -> (.out: Payload)
        \\  - copy (.payload: Payload, .flag: Bool) -> (.out: Payload)
        \\  - copy (.allocator: $&Allocator, .self: String) -> (.out: String)
        \\  - copy (.self: Path, .allocator: $&Allocator) -> (.out: Path)
        \\      payload := value..ok
        \\                      ^
        \\
    );
}

test "feature_tests/types/50X_choice_literal_payload_ambiguous_copy" {
    try buildExpectFailExact("tests/feature_tests/types/50X_choice_literal_payload_ambiguous_copy",
        \\tests/feature_tests/types/50X_choice_literal_payload_ambiguous_copy/main.rg:24:28: error: ambiguous call to 'copy' for arguments (.__arg0: Payload). Possible overloads:
        \\  - copy (.payload: Payload, .tag: Int32) -> (.out: Payload)
        \\  - copy (.payload: Payload, .flag: Bool) -> (.out: Payload)
        \\  - copy (.allocator: $&Allocator, .self: String) -> (.out: String)
        \\  - copy (.self: Path, .allocator: $&Allocator) -> (.out: Path)
        \\      result : Result = ..ok payload
        \\                             ^
        \\
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

test "feature_tests/collections/21_index_operator_reached_default" {
    const test_path = "tests/feature_tests/collections/21_index_operator_reached_default";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 42);
}

test "feature_tests/collections/22_dynamic_array_borrowed_index_string" {
    const test_path = "tests/feature_tests/collections/22_dynamic_array_borrowed_index_string";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
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
        \\tests/feature_tests/types/14X_errable_match_unknown_variant/main.rg:7:11: error: choice type 'Errable#(.t: Int32, .reasons: choice)' has no variant '..none'
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
        \\tests/feature_tests/system/03X_reached_argument_missing/main.rg:12:26: error: cannot resolve reached argument '.stdout' with alternatives [stdout, terminal.stdout, system.terminal.stdout] expected as 'Int32'
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
    try buildExpectFailExact("tests/feature_tests/ownership/17X_keep_without_auto_deinit",
        \\tests/feature_tests/ownership/17X_keep_without_auto_deinit/main.rg:3:11: error: cannot keep binding 'value': no automatic deinit is scheduled
        \\      #keep value
        \\            ^
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
        \\tests/feature_tests/io/23X_abstract_writer_field_conflicting_assignment/main.rg:46:17: error: field '.writer' already stores '$&FirstWriter' for abstract type '$&Writer', so it cannot also store '$&SecondWriter'
        \\      p&.writer = writer
        \\                  ^
        \\
    );
}

test "feature_tests/io/24_terminal_stream_aliases" {
    const test_path = "tests/feature_tests/io/24_terminal_stream_aliases";
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
        \\tests/feature_tests/io/26X_print_without_system/main.rg:2:10: error: function 'print' exists, but no overload matches the provided arguments.
        \\Overloads with omitted #reach defaults:
        \\  - print(.value: StringView, .stdout: $&Writer = #reach stdout, terminal.stdout, system.terminal.stdout) -> (.result: Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed)))
        \\    omitted #reach defaults:
        \\      - .stdout uses #reach [stdout, terminal.stdout, system.terminal.stdout] expected as '$&Writer'
        \\
        \\Add a reachable value in the caller, for example:
        \\  main(.system: System = System()) -> (.status_code: Int32 = 0) := { ... }
        \\
        \\Or pass the omitted argument explicitly.
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
    try runExpectStdout(test_path, 0, "literal output");
}

test "feature_tests/io/16_print_string_view" {
    const test_path = "tests/feature_tests/io/16_print_string_view";
    try expectSuccessfulBuild(test_path);
    try runExpectStdout(test_path, 0, "string view output");
}

test "feature_tests/io/17_print_error_string_view" {
    const test_path = "tests/feature_tests/io/17_print_error_string_view";
    try expectSuccessfulBuild(test_path);
    try runExpectStderr(test_path, 0, "error view");
}

test "feature_tests/io/18_print_borrowed_string_view" {
    const test_path = "tests/feature_tests/io/18_print_borrowed_string_view";
    try expectSuccessfulBuild(test_path);
    try runExpectStdout(test_path, 0, "borrowed view");
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

test "feature_tests/system/13_environment_variables_string_view_keys" {
    const test_path = "tests/feature_tests/system/13_environment_variables_string_view_keys";
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
    try buildExpectFailExact("tests/feature_tests/ownership/18X_system_noncopyable_assignment",
        \\tests/feature_tests/ownership/18X_system_noncopyable_assignment/main.rg:2:15: error: type 'System' is not copyable, so it cannot be used by value here; pass it by '&' or '$&', or implement 'copy()'
        \\      copied := system
        \\                ^
        \\
    );
}

test "feature_tests/ownership/19X_system_noncopyable_argument" {
    try buildExpectFailExact("tests/feature_tests/ownership/19X_system_noncopyable_argument",
        \\tests/feature_tests/ownership/19X_system_noncopyable_argument/main.rg:6:37: error: type 'System' is not copyable, so it cannot be used by value here; pass it by '&' or '$&', or implement 'copy()'
        \\      status_code = consume(.system = system)
        \\                                      ^
        \\
    );
}

test "feature_tests/ownership/35X_system_move_by_value" {
    try buildExpectFailExact("tests/feature_tests/ownership/35X_system_move_by_value",
        \\tests/feature_tests/ownership/35X_system_move_by_value/main.rg:6:37: error: System cannot be moved by value; pass it by '&' or '$&' instead
        \\      status_code = consume(.system = ~system)
        \\                                      ^
        \\
    );
}

test "feature_tests/ownership/36X_double_move" {
    try buildExpectFailExact("tests/feature_tests/ownership/36X_double_move",
        \\tests/feature_tests/ownership/36X_double_move/main.rg:14:35: error: binding 'handle' was moved and cannot be used again (moved at tests/feature_tests/ownership/36X_double_move/main.rg:13:34)
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
        \\tests/feature_tests/system/20X_once_duplicate_init/main.rg:8:15: error: once function 'init' is consumed more than once from the reachable entrypoint graph (first use at tests/feature_tests/system/20X_once_duplicate_init/main.rg:7:14 via 'main')
        \\      second := Token()
        \\                ^
        \\
    );
}

test "feature_tests/system/21X_system_duplicate_init" {
    try buildExpectFailExact("tests/feature_tests/system/21X_system_duplicate_init",
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

test "feature_tests/ownership/24_mutable_and_read_field_alias_same_call" {
    try expectSuccessfulBuild("tests/feature_tests/ownership/24_mutable_and_read_field_alias_same_call");
}

test "feature_tests/ownership/25_mutable_and_value_field_alias_same_call" {
    try expectSuccessfulBuild("tests/feature_tests/ownership/25_mutable_and_value_field_alias_same_call");
}

test "feature_tests/ownership/39_exclusive_reference_permissions" {
    const test_path = "tests/feature_tests/ownership/39_exclusive_reference_permissions";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/40X_exclusive_and_read_alias_same_call" {
    try buildExpectFailExact("tests/feature_tests/ownership/40X_exclusive_and_read_alias_same_call",
        \\tests/feature_tests/ownership/40X_exclusive_and_read_alias_same_call/main.rg:5:8: error: binding 'value' cannot be passed as '$$&' and '&' in the same call to 'mix'
        \\      mix(.target = $$&value, .reader = &value)
        \\         ^
        \\
    );
}

test "feature_tests/ownership/41X_double_exclusive_alias_same_call" {
    try buildExpectFailExact("tests/feature_tests/ownership/41X_double_exclusive_alias_same_call",
        \\tests/feature_tests/ownership/41X_double_exclusive_alias_same_call/main.rg:5:8: error: binding 'value' cannot be passed as '$$&' and '$$&' in the same call to 'mix'
        \\      mix(.left = $$&value, .right = $$&value)
        \\         ^
        \\
    );
}

test "feature_tests/ownership/42X_mutable_cannot_upgrade_to_exclusive" {
    try buildExpectFail(
        "tests/feature_tests/ownership/42X_mutable_cannot_upgrade_to_exclusive",
        "no overload of 'consume' accepts arguments (.value: $&Int32)",
    );
}

test "feature_tests/ownership/26_distinct_fields_do_not_alias_same_call" {
    const test_path = "tests/feature_tests/ownership/26_distinct_fields_do_not_alias_same_call";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 7);
}

test "feature_tests/ownership/43_distinct_literal_indices_do_not_alias" {
    const test_path = "tests/feature_tests/ownership/43_distinct_literal_indices_do_not_alias";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/44X_dynamic_index_may_alias" {
    try buildExpectFail(
        "tests/feature_tests/ownership/44X_dynamic_index_may_alias",
        "binding 'values' cannot be passed as '$$&' and '$$&' in the same call to 'mix'",
    );
}

test "feature_tests/ownership/45_reference_last_use_before_deinit" {
    const test_path = "tests/feature_tests/ownership/45_reference_last_use_before_deinit";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/46X_reference_use_after_deinit" {
    try buildExpectFail(
        "tests/feature_tests/ownership/46X_reference_use_after_deinit",
        "reference 'pointer' is no longer valid; it refers to 'resource'",
    );
}

test "feature_tests/ownership/47X_conditional_invalidation" {
    try buildExpectFail(
        "tests/feature_tests/ownership/47X_conditional_invalidation",
        "reference 'pointer' is no longer valid; it refers to 'resource'",
    );
}

test "feature_tests/ownership/48_branch_local_invalidation" {
    const test_path = "tests/feature_tests/ownership/48_branch_local_invalidation";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/49X_loop_carried_invalidation" {
    try buildExpectFail(
        "tests/feature_tests/ownership/49X_loop_carried_invalidation",
        "reference 'pointer' is no longer valid; it refers to 'resource'",
    );
}

test "feature_tests/ownership/50_independent_field_replacement" {
    const test_path = "tests/feature_tests/ownership/50_independent_field_replacement";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/51X_referenced_field_replacement" {
    try buildExpectFail(
        "tests/feature_tests/ownership/51X_referenced_field_replacement",
        "reference 'pointer' is no longer valid; it refers to 'pair'",
    );
}

test "feature_tests/ownership/52_array_subobject_replacement" {
    const test_path = "tests/feature_tests/ownership/52_array_subobject_replacement";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/53X_array_element_replacement" {
    try buildExpectFail(
        "tests/feature_tests/ownership/53X_array_element_replacement",
        "reference 'pointer' is no longer valid; it refers to 'values' at place 'values[1]'",
    );
}

test "feature_tests/ownership/54X_exclusive_call_may_invalidate" {
    try buildExpectFail(
        "tests/feature_tests/ownership/54X_exclusive_call_may_invalidate",
        "reference 'pointer' is no longer valid; it refers to 'resource'",
    );
}

test "feature_tests/ownership/55_mutable_call_preserves_temporal_identity" {
    const test_path = "tests/feature_tests/ownership/55_mutable_call_preserves_temporal_identity";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/56X_stored_reference_use_after_deinit" {
    try buildExpectFail(
        "tests/feature_tests/ownership/56X_stored_reference_use_after_deinit",
        "reference 'holder' is no longer valid; it refers to 'resource'",
    );
}

test "feature_tests/ownership/57_independent_value_field_after_dependency_invalidation" {
    const test_path = "tests/feature_tests/ownership/57_independent_value_field_after_dependency_invalidation";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/58_array_reference_dependencies" {
    const test_path = "tests/feature_tests/ownership/58_array_reference_dependencies";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/59X_array_reference_dependency_invalid" {
    try buildExpectFail(
        "tests/feature_tests/ownership/59X_array_reference_dependency_invalid",
        "reference 'pointers' is no longer valid; it refers to 'first'",
    );
}

test "feature_tests/ownership/60X_mutable_reference_cannot_change_dependencies" {
    try buildExpectFail(
        "tests/feature_tests/ownership/60X_mutable_reference_cannot_change_dependencies",
        "changing temporal dependencies of field '.pointer' requires '$$&' access",
    );
}

test "feature_tests/ownership/61_exclusive_reference_changes_dependencies" {
    const test_path = "tests/feature_tests/ownership/61_exclusive_reference_changes_dependencies";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/62_direct_owner_changes_dependencies" {
    const test_path = "tests/feature_tests/ownership/62_direct_owner_changes_dependencies";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/63X_interprocedural_return_dependency" {
    try buildExpectFail(
        "tests/feature_tests/ownership/63X_interprocedural_return_dependency",
        "reference 'pointer' is no longer valid; it refers to 'resource'",
    );
}

test "feature_tests/ownership/64X_composed_temporal_summaries" {
    try buildExpectFail(
        "tests/feature_tests/ownership/64X_composed_temporal_summaries",
        "reference 'pointer' is no longer valid; it refers to 'resource'",
    );
}

test "feature_tests/ownership/65X_arena_reset_invalidates_allocations" {
    try buildExpectFail(
        "tests/feature_tests/ownership/65X_arena_reset_invalidates_allocations",
        "reference 'pointer' is no longer valid; it refers to 'arena'",
    );
}

test "feature_tests/ownership/66_arena_allocations_before_reset" {
    const test_path = "tests/feature_tests/ownership/66_arena_allocations_before_reset";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/67_transfer_preserves_temporal_identity" {
    const test_path = "tests/feature_tests/ownership/67_transfer_preserves_temporal_identity";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/68_address_dependent_call_transfer" {
    const test_path = "tests/feature_tests/ownership/68_address_dependent_call_transfer";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/69X_abstract_concrete_temporal_summary" {
    try buildExpectFail(
        "tests/feature_tests/ownership/69X_abstract_concrete_temporal_summary",
        "reference 'pointer' is no longer valid; it refers to 'resource'",
    );
}

test "feature_tests/ownership/70X_post_state_dependency_summary" {
    try buildExpectFail(
        "tests/feature_tests/ownership/70X_post_state_dependency_summary",
        "reference 'holder' is no longer valid; it refers to 'second'",
    );
}

test "feature_tests/ownership/71X_composite_pointer_input_dependency" {
    try buildExpectFail(
        "tests/feature_tests/ownership/71X_composite_pointer_input_dependency",
        "reference 'pointer' is no longer valid; it refers to 'resource'",
    );
}

test "feature_tests/ownership/72X_composite_value_input_dependency" {
    try buildExpectFail(
        "tests/feature_tests/ownership/72X_composite_value_input_dependency",
        "reference 'returned' is no longer valid; it refers to 'resource'",
    );
}

test "feature_tests/ownership/73X_loop_dependency_fixed_point" {
    try buildExpectFail(
        "tests/feature_tests/ownership/73X_loop_dependency_fixed_point",
        "reference 'first' is no longer valid; it refers to 'victim'",
    );
}

test "feature_tests/ownership/74X_extern_exclusive_invalidation" {
    try buildExpectFail(
        "tests/feature_tests/ownership/74X_extern_exclusive_invalidation",
        "reference 'pointer' is no longer valid",
    );
}

test "feature_tests/ownership/75X_extern_return_dependency" {
    try buildExpectFail(
        "tests/feature_tests/ownership/75X_extern_return_dependency",
        "reference 'pointer' is no longer valid",
    );
}

test "feature_tests/ownership/76_destination_passed_self_reference" {
    const test_path = "tests/feature_tests/ownership/76_destination_passed_self_reference";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/77X_address_dependent_result_requires_destination" {
    try buildExpectFail(
        "tests/feature_tests/ownership/77X_address_dependent_result_requires_destination",
        "address-dependent result of 'make_node' requires a stable destination",
    );
}

test "feature_tests/ownership/78X_destination_return_dependency_invalidation" {
    try buildExpectFail(
        "tests/feature_tests/ownership/78X_destination_return_dependency_invalidation",
        "reference 'pointer' is no longer valid",
    );
}

test "feature_tests/ownership/79X_owned_buffer_deinit_invalidation" {
    try buildExpectFail(
        "tests/feature_tests/ownership/79X_owned_buffer_deinit_invalidation",
        "reference 'pointer' is no longer valid",
    );
}

test "feature_tests/ownership/80_dependency_invalidation_preserves_other_borrows" {
    const test_path = "tests/feature_tests/ownership/80_dependency_invalidation_preserves_other_borrows";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/81X_initializer_fresh_post_state" {
    try buildExpectFail(
        "tests/feature_tests/ownership/81X_initializer_fresh_post_state",
        "reference 'pointer' is no longer valid",
    );
}

test "feature_tests/ownership/82_owned_buffer_deinit_preserves_allocator" {
    const test_path = "tests/feature_tests/ownership/82_owned_buffer_deinit_preserves_allocator";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/polymorphism/31X_virtual_rejects_permission_upgrade" {
    try buildExpectFail(
        "tests/feature_tests/polymorphism/31X_virtual_rejects_permission_upgrade",
        "to_virtual requires a mutable reference",
    );
}

test "feature_tests/polymorphism/32X_virtual_rejects_exclusive_permission_upgrade" {
    try buildExpectFail(
        "tests/feature_tests/polymorphism/32X_virtual_rejects_exclusive_permission_upgrade",
        "to_virtual requires an exclusive reference",
    );
}

test "feature_tests/ownership/83X_dynamic_array_element_deinit_invalidation" {
    try buildExpectFail(
        "tests/feature_tests/ownership/83X_dynamic_array_element_deinit_invalidation",
        "reference 'pointer' is no longer valid",
    );
}

test "feature_tests/ownership/84_fresh_dependency_transition_contract" {
    const test_path = "tests/feature_tests/ownership/84_fresh_dependency_transition_contract";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/ownership/85X_dynamic_array_growth_invalidates_element" {
    try buildExpectFail(
        "tests/feature_tests/ownership/85X_dynamic_array_growth_invalidates_element",
        "reference 'pointer' is no longer valid",
    );
}

test "feature_tests/ownership/86X_fresh_dependency_contract_requires_boundary" {
    try buildExpectFail(
        "tests/feature_tests/ownership/86X_fresh_dependency_contract_requires_boundary",
        "#sets_dependency_fresh requires #raw_boundary or #trusted_temporal",
    );
}

test "feature_tests/ownership/27X_ambiguous_copy_in_array_literal" {
    try buildExpectFailExact("tests/feature_tests/ownership/27X_ambiguous_copy_in_array_literal",
        \\tests/feature_tests/ownership/27X_ambiguous_copy_in_array_literal/main.rg:17:28: error: ambiguous call to 'copy' for arguments (.__arg0: Resource). Possible overloads:
        \\  - copy (.res: Resource, .tag: Int32) -> (.out: Resource)
        \\  - copy (.res: Resource, .flag: Bool) -> (.out: Resource)
        \\      values : [2]Resource = (source, source)
        \\                             ^
        \\
    );
}

test "feature_tests/ownership/28X_ambiguous_copy_assignment" {
    try buildExpectFailExact("tests/feature_tests/ownership/28X_ambiguous_copy_assignment",
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

test "feature_tests/ownership/37X_ambiguous_copy_return" {
    try buildExpectFailExact("tests/feature_tests/ownership/37X_ambiguous_copy_return",
        \\tests/feature_tests/ownership/37X_ambiguous_copy_return/main.rg:16:12: error: ambiguous call to 'copy' for arguments (.__arg0: Resource). Possible overloads:
        \\  - copy (.res: Resource, .tag: Int32) -> (.out: Resource)
        \\  - copy (.res: Resource, .flag: Bool) -> (.out: Resource)
        \\  - copy (.allocator: $&Allocator, .self: String) -> (.out: String)
        \\  - copy (.self: Path, .allocator: $&Allocator) -> (.out: Path)
        \\      return source
        \\             ^
        \\
    );
}

test "feature_tests/ownership/38X_ambiguous_copy_struct_field" {
    try buildExpectFailExact("tests/feature_tests/ownership/38X_ambiguous_copy_struct_field",
        \\tests/feature_tests/ownership/38X_ambiguous_copy_struct_field/main.rg:21:33: error: ambiguous call to 'copy' for arguments (.__arg0: Resource). Possible overloads:
        \\  - copy (.res: Resource, .tag: Int32) -> (.out: Resource)
        \\  - copy (.res: Resource, .flag: Bool) -> (.out: Resource)
        \\  - copy (.allocator: $&Allocator, .self: String) -> (.out: String)
        \\  - copy (.self: Path, .allocator: $&Allocator) -> (.out: Path)
        \\      wrapped : Wrapper = (.res = handle)
        \\                                  ^
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
    try buildExpectFailExact("tests/feature_tests/ownership/32X_array_of_noncopyable_is_not_copyable",
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
    try buildExpectFailExact("tests/feature_tests/polymorphism/25X_abstract_overloads_with_defaults_ambiguous",
        \\tests/feature_tests/polymorphism/25X_abstract_overloads_with_defaults_ambiguous/main.rg:14:19: error: ambiguous call to 'pick' for arguments (.value: Int32). Possible overloads:
        \\  - pick (.value: A, .left: Int32) -> (.status_code: Int32)
        \\  - pick (.value: A, .right: Int32) -> (.status_code: Int32)
        \\      status_code = pick(.value = 7).status_code
        \\                    ^
        \\
    );
}

test "feature_tests/polymorphism/26_virtual_type_representation" {
    const test_path = "tests/feature_tests/polymorphism/26_virtual_type_representation";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/polymorphism/27X_virtual_temporal_envelope" {
    try buildExpectFail(
        "tests/feature_tests/polymorphism/27X_virtual_temporal_envelope",
        "reference 'pointer' is no longer valid",
    );
}

test "feature_tests/polymorphism/28X_virtual_exclusive_invalidation" {
    try buildExpectFail(
        "tests/feature_tests/polymorphism/28X_virtual_exclusive_invalidation",
        "reference 'pointer' is no longer valid",
    );
}

test "feature_tests/polymorphism/29_virtual_heterogeneous_dispatch" {
    const test_path = "tests/feature_tests/polymorphism/29_virtual_heterogeneous_dispatch";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}

test "feature_tests/polymorphism/30X_virtual_rejects_self_output" {
    try buildExpectFail(
        "tests/feature_tests/polymorphism/30X_virtual_rejects_self_output",
        "is not virtual-safe because Self escapes by value or output",
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
        \\tests/feature_tests/modules/12X_import_requires_binding/main.rg:1:1: error: #import must be assigned to a name
        \\  #import("./dep")
        \\  ^
        \\
    );
}

test "feature_tests/modules/13X_import_requires_binding_nested" {
    try buildExpectFailExact("tests/feature_tests/modules/13X_import_requires_binding_nested",
        \\tests/feature_tests/modules/13X_import_requires_binding_nested/main.rg:3:9: error: #import must be assigned to a name
        \\          #import("./dep")
        \\          ^
        \\
    );
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

test "argi help lists supported 0.1 commands" {
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
    try expect(std.mem.indexOf(u8, result.stderr, "init <name>") != null);
    try expect(std.mem.indexOf(u8, result.stderr, "init --lib <name>") != null);
    try expect(std.mem.indexOf(u8, result.stderr, "lsp") != null);
    try expect(std.mem.indexOf(u8, result.stderr, "version") != null);
    try expect(std.mem.indexOf(u8, result.stderr, "format") == null);
}

test "argi version reports current release" {
    const result = try runArgiCommand(&.{"version"});
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);

    try expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try expectEqualStrings("argi 0.1.0\n", result.stderr);
}

test "argi unknown command exits with help" {
    const result = try runArgiCommand(&.{"format"});
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);

    try expectEqual(std.process.Child.Term{ .exited = 1 }, result.term);
    try expect(std.mem.indexOf(u8, result.stderr, "Error: unknown command 'format'\n") != null);
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

test "argi init without full arguments exits with error" {
    const result = try runArgiCommand(&.{"init"});
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);

    try expectEqual(std.process.Child.Term{ .exited = 1 }, result.term);
    try expectEqualStrings("Error: init requires <name> or --lib <name>\n", result.stderr);
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
