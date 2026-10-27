const std = @import("std");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;
const test_support = @import("support.zig");
const compilerRoot = test_support.compilerRoot;
const outputPathFor = test_support.outputPathFor;
const irPathFor = test_support.irPathFor;
const objPathFor = test_support.objPathFor;
const argiTestCacheDirForModule = test_support.argiTestCacheDirForModule;
const clean = test_support.clean;
const compilerTestArgs = test_support.compilerTestArgs;
const runChild = test_support.runChild;
const runArgiCommand = test_support.runArgiCommand;
const runArgiCommandWithEnv = test_support.runArgiCommandWithEnv;
const expectArgiBuildSuccess = test_support.expectArgiBuildSuccess;
const runChildInCwd = test_support.runChildInCwd;
const runChildInCwdWithEnv = test_support.runChildInCwdWithEnv;
const normalizeRunResult = test_support.normalizeRunResult;
const normalizeDiagnosticPaths = test_support.normalizeDiagnosticPaths;
const normalizeSourceLocation = test_support.normalizeSourceLocation;
const repoRootPrefix = test_support.repoRootPrefix;
const installedArgiPath = test_support.installedArgiPath;
const tmpDirRootPath = test_support.tmpDirRootPath;
const buildResult = test_support.buildResult;
const expectSuccessfulBuild = test_support.expectSuccessfulBuild;
const expectDiagnostic = test_support.expectDiagnostic;
const buildExpectFail = test_support.buildExpectFail;
const buildExpectFailWithoutNoise = test_support.buildExpectFailWithoutNoise;
const buildExpectFailExact = test_support.buildExpectFailExact;
const buildExpectFailWithoutParseNoise = test_support.buildExpectFailWithoutParseNoise;
const runExpect = test_support.runExpect;
const runExpectFailure = test_support.runExpectFailure;
const run = test_support.run;
const qualifiedTestOutput = test_support.qualifiedTestOutput;
const argiTestExpectStderr = test_support.argiTestExpectStderr;
const argiTestExpectStderrContains = test_support.argiTestExpectStderrContains;
const runExpectStdoutWithArgs = test_support.runExpectStdoutWithArgs;
const runExpectStdout = test_support.runExpectStdout;
const runExpectStderr = test_support.runExpectStderr;
const runExpectStdoutWithArgsAndStdin = test_support.runExpectStdoutWithArgsAndStdin;
const pathInTest = test_support.pathInTest;
const fileHasSubstantiveContent = test_support.fileHasSubstantiveContent;
const argi_bin = test_support.argi_bin;
const vmExpect = test_support.vmExpect;
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
            const local_test = try std.fmt.allocPrint(std.testing.allocator, "{s}/test.zig", .{case_path});
            defer std.testing.allocator.free(local_test);
            if (root.access(std.testing.io, local_test, .{})) |_| continue else |err| switch (err) {
                error.FileNotFound => {},
                else => return err,
            }
            if (std.mem.indexOf(u8, test_file_text, case_path) != null) continue;

            try missing.append(try std.testing.allocator.dupe(u8, case_path));
        }
    }

    if (missing.items.len != 0) {
        std.debug.print("missing feature coverage through local test.zig or custom tests:\n", .{});
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
        \\main := () -> (.status_code: Int32 = 0)  {
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
        \\test installed_prefix := (.system: System) -> !() {
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
    try expect(std.mem.indexOf(u8, result.stderr, "/installed_prefix\n") != null);
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
        "main := (.system: System) -> (.status_code: Int32 = 0) {\n" ++
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
    try expect(std.mem.indexOf(u8, result.stderr, "module has no executables to build") != null);
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
        \\main := () -> (.status_code: Int32 = 0)  {
        \\}
        \\
        ,
    });
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "app/source/entrypoints/server/main.rg",
        .data =
        \\main := () -> (.status_code: Int32 = 0)  {
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
        \\main := () -> (.status_code: Int32 = 7)  {
        \\}
        \\
        ,
    });
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "app/source/entrypoints/server/main.rg",
        .data =
        \\main := () -> (.status_code: Int32 = 11)  {
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
        \\main := () -> (.status_code: Int32 = 9)  {
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
        .data = "dep := import(\"../dep\")\nmain := () -> (.status_code: Int32)  { status_code = dep.answer().result }\n",
    });
    const source = "answer := () -> (.result: Int32)  { result = 7 }\n";
    try tmp.dir.writeFile(io, .{ .sub_path = "dep/answer.rg", .data = source });
    for (0..4) |revision| {
        if (revision == 1) {
            try tmp.dir.writeFile(io, .{ .sub_path = "dep/answer.rg", .data = "answer := () -> (.result: Int32)  { result = 9 }\n" });
        } else if (revision == 2) {
            try tmp.dir.writeFile(io, .{ .sub_path = "dep/extra.rg", .data = "extra := () -> (.result: Int32)  { result = 11 }\n" });
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

test "usecase_tests/01_cat" {
    const test_path = "tests/usecase_tests/01_cat";
    const expected_help = "Concatenate files to standard output. With no files or FILE '-', read standard input.\nUsage: cat [OPTIONS] [ARGS]\n\nOptions:\n  -h, --help  Show help\n";
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
    try runExpectStdoutWithArgs(test_path, &.{ "missing-cat-input", "--help" }, 0, expected_help);
    try runExpectStdoutWithArgsAndStdin(test_path, &.{}, "stdin\x00bytes\n", 0, "stdin\x00bytes\n");
    try runExpectStdoutWithArgsAndStdin(test_path, &.{"-"}, "", 0, "");
    try runExpectStdoutWithArgsAndStdin(
        test_path,
        &.{ input_1, "-", input_2, "-" },
        "standard input\n",
        0,
        "Hello from Argi.\nThis is a tiny cat clone.\nstandard input\nAnd now a second file.\nCat should concatenate both.\n",
    );

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var binary: [8192 * 2 + 17]u8 = undefined;
    for (&binary, 0..) |*byte, index| byte.* = @truncate(index * 73);
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "--help", .data = &binary });
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "empty", .data = "" });

    var cwd_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const cwd_length = try tmp.dir.realPath(std.testing.io, &cwd_buffer);
    const repo_root = try repoRootPrefix();
    defer std.testing.allocator.free(repo_root);
    const output_path = try outputPathFor(test_path);
    defer std.testing.allocator.free(output_path);
    const executable = try std.fs.path.join(std.testing.allocator, &.{ repo_root, output_path });
    defer std.testing.allocator.free(executable);

    const binary_result = try runChildInCwd(&.{ executable, "--", "empty", "--help", "empty" }, cwd_buffer[0..cwd_length]);
    defer std.testing.allocator.free(binary_result.stdout);
    defer std.testing.allocator.free(binary_result.stderr);
    try expectEqual(std.process.Child.Term{ .exited = 0 }, binary_result.term);
    try expectEqualStrings(&binary, binary_result.stdout);
    try expectEqualStrings("", binary_result.stderr);

    for ([_][]const u8{ "--unknown", "missing-cat-input" }) |argument| {
        const failed = try runChildInCwd(&.{ executable, argument }, cwd_buffer[0..cwd_length]);
        defer std.testing.allocator.free(failed.stdout);
        defer std.testing.allocator.free(failed.stderr);
        try expectEqual(std.process.Child.Term{ .exited = 1 }, failed.term);
        try expectEqualStrings("", failed.stdout);
        try expect(failed.stderr.len > 0);
        if (std.mem.eql(u8, argument, "missing-cat-input")) {
            try expect(std.mem.indexOf(u8, failed.stderr, argument) != null);
        }
    }
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
    try runExpectStdoutWithArgsAndStdin(test_path, &.{}, "", 0, "");
    try runExpectStdoutWithArgsAndStdin(test_path, &.{}, "\nignored\n", 0, "");
    try runExpectStdoutWithArgsAndStdin(test_path, &.{}, "first\nlast", 0, "first\nlast\n");
    try runExpectStdoutWithArgsAndStdin(test_path, &.{}, "a\x00b\n\nignored", 0, "a\x00b\n");

    const long_input = try std.testing.allocator.alloc(u8, 16 * 1024 + 1);
    defer std.testing.allocator.free(long_input);
    @memset(long_input, 'x');
    long_input[long_input.len - 1] = '\n';
    try runExpectStdoutWithArgsAndStdin(test_path, &.{}, long_input, 0, long_input);
}

test "parser errors do not print parse error noise" {
    try buildExpectFailWithoutParseNoise(
        "tests/feature_tests/functions/14X_positional_after_named_call",
        "positional collection items must appear before named items",
    );
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
    try argiTestExpectStderrContains(
        "tests/feature_tests/testing/05_assertion_failure",
        &.{},
        1,
        "FAIL assertion_failure\n",
    );
}

test "feature_tests/testing/06_direct_propagated_error" {
    try argiTestExpectStderrContains(
        "tests/feature_tests/testing/06_direct_propagated_error",
        &.{},
        1,
        "FAIL direct_propagation\n",
    );
}

test "feature_tests/testing/22_optional_system" {
    try argiTestExpectStderr("tests/feature_tests/testing/22_optional_system", &.{}, 0, "PASS without_system\nPASS with_system\n");
}

test "feature_tests/testing/23_no_system_failure" {
    try argiTestExpectStderrContains("tests/feature_tests/testing/23_no_system_failure", &.{}, 1, "FAIL fails_without_system\n");
}

test "feature_tests/testing/24_no_system_skip" {
    try argiTestExpectStderrContains("tests/feature_tests/testing/24_no_system_skip", &.{}, 0, "SKIP skips_without_system\n");
}

test "feature_tests/testing/25X_wrong_system_type" {
    try argiTestExpectStderrContains("tests/feature_tests/testing/25X_wrong_system_type", &.{}, 1, "no function named 'wrong_system_type'");
}

test "feature_tests/testing/08X_test_signature_requires_v1_shape" {
    try argiTestExpectStderrContains(
        "tests/feature_tests/testing/08X_test_signature_requires_v1_shape",
        &.{},
        1,
        "tests accept no inputs or one '.system: System'",
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
    try argiTestExpectStderrContains(
        "tests/feature_tests/testing/10_expected_error_mismatch",
        &.{},
        1,
        "FAIL expected_error_mismatch\n",
    );
}

test "feature_tests/testing/11_expected_error_unexpected_ok" {
    try argiTestExpectStderrContains(
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
    try expect(std.mem.indexOf(u8, result.stderr, "repl [flags]") != null);
    try expect(std.mem.indexOf(u8, result.stderr, "test [directory] [flags]") != null);
    try expect(std.mem.indexOf(u8, result.stderr, "--sysroot <path>") != null);
    try expect(std.mem.indexOf(u8, result.stderr, "--exec <name>") != null);
    try expect(std.mem.indexOf(u8, result.stderr, "--filter <name>") != null);
    try expect(std.mem.indexOf(u8, result.stderr, "init [name]") != null);
    try expect(std.mem.indexOf(u8, result.stderr, "init --lib [name]") != null);
    try expect(std.mem.indexOf(u8, result.stderr, "lsp") != null);
    try expect(std.mem.indexOf(u8, result.stderr, "version") != null);
    try expect(std.mem.indexOf(u8, result.stderr, "format [paths...] [--check]") != null);
    try expect(std.mem.indexOf(u8, result.stderr, "format <file.rg> --stdout") != null);
    try expect(std.mem.indexOf(u8, result.stderr, "--vm-instructions <N>") != null);
    try expect(std.mem.indexOf(u8, result.stderr, "--vm-call-depth <N>") != null);
    try expect(std.mem.indexOf(u8, result.stderr, "--vm-value-cells <N>") != null);
}

test "argi repl terminal colors indentation and history" {
    try @import("terminal_probe.zig").checkEditor();
}

test "argi VM execution interrupts and REPL reset" {
    try @import("terminal_probe.zig").checkInterrupts();
}

test "argi repl retains values and shares compile-time execution" {
    const installed_argi = try installedArgiPath();
    defer std.testing.allocator.free(installed_argi);
    var child = try std.process.spawn(std.testing.io, .{
        .argv = &.{ installed_argi, "repl" },
        .cwd = .{ .path = compilerRoot() },
        .stdin = .pipe,
        .stdout = .pipe,
        .stderr = .pipe,
    });
    defer child.kill(std.testing.io);
    try child.stdin.?.writeStreamingAll(std.testing.io, "value ::= 40 + 2\nunfinished := () -> () {\n:cancel\nvalue\n" ++
        "answer := () -> (.result: Int32) { result = 7 }\nanswer()\n_0 + _1\n" ++
        "enabled := () -> (.result: Bool) { result = true }\n" ++
        "choose := () -> (.result: Int32) {\n" ++
        "    #if enabled() { result = 12 } else { result = missing() }\n" ++
        "}\n#run () -> (.answer: Int32) { answer = choose() }\n:reset\ntrue\n\"hello\"\n_1\n");
    child.stdin.?.close(std.testing.io);
    child.stdin = null;
    var buffer: std.Io.File.MultiReader.Buffer(2) = undefined;
    var reader: std.Io.File.MultiReader = undefined;
    reader.init(std.testing.allocator, std.testing.io, buffer.toStreams(), &.{ child.stdout.?, child.stderr.? });
    defer reader.deinit();
    while (true) reader.fill(1, .none) catch |err| switch (err) {
        error.EndOfStream => break,
        else => return err,
    };
    const stdout = try reader.toOwnedSlice(0);
    defer std.testing.allocator.free(stdout);
    const stderr = try reader.toOwnedSlice(1);
    defer std.testing.allocator.free(stderr);
    if (stderr.len != 0) std.debug.print("REPL stderr: {s}\n", .{stderr});
    try expectEqual(std.process.Child.Term{ .exited = 0 }, try child.wait(std.testing.io));
    try expectEqualStrings("", stderr);
    try expectEqualStrings("_0 = 42\n_1 = 7\n_2 = 49\n_3 = 12\n_0 = true\n_1 = \"hello\"\n_2 = \"hello\"\n", stdout);
}

test "argi version reports current release" {
    const result = try runArgiCommand(&.{"version"});
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);

    try expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try expectEqualStrings("argi 0.3.0\n", result.stderr);
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
    try expect(std.mem.indexOf(u8, result.stderr, "configure [test] modules") != null);
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
    try expect(std.mem.indexOf(u8, result.stderr, "/simple_pass\n") != null);
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
        \\Token := (.value: Int32)
        \\
        \\implement Deinit#(Token) (.deinit = (.self: $&Token) -> () {})
        \\
        \\Result : Type = (
        \\    ..ok(.token: Token)
        \\    ..error
        \\)
        \\
        \\dormant := () -> ()  {
        \\    value : Result = ..ok(.token = Token(.value = 7))
        \\    match value {
        \\        ..ok payload {
        \\            _ ::= payload.token.value
        \\        }
        \\        ..error {}
        \\    }
        \\}
        \\
        \\main := () -> (.status_code: Int32 = 0)  {}
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
        \\dormant := () -> ()  {
        \\    value :: Int32 = 0
        \\    reader : &Int32 = &value
        \\    reader& = 1
        \\}
        \\
        \\main := () -> (.status_code: Int32 = 0)  {}
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
        \\dormant := () -> ()  {
        \\    value :: Int32 = 0
        \\    reader : &Int32 = &value
        \\    reader& = 1
        \\}
        \\
        \\main := () -> (.status_code: Int32 = 0)  {}
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
    try expectSafetyWrapperParity("tests/feature_tests/ownership/220X_virtual_contract_rejects_hidden_dependency", "violates its safety contract");
    try expectSafetyWrapperParity("tests/feature_tests/polymorphism/30X_virtual_declared_dependency_escape", "function output cannot depend on a local storage generation that ends before return");
}

test "safety statistics preserve composed allocator behavior" {
    const path = "tests/feature_tests/system/49_general_purpose_allocator_on_arena";
    const result = try runArgiCommand(&.{ "build", path, "--stats" });
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);
    try expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    for ([_][]const u8{ "summary inference:", "summary bytes requested:", "retained worklist bytes:", "virtual contract summary time:", "state copy time:" }) |label|
        try expect(std.mem.indexOf(u8, result.stderr, label) != null);
    try run(path);
}

test "argi run inherits stdin stdout and stderr" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "main.rg",
        .data =
        \\main := (.system: System) -> (.status_code: Int32 = 7)  {
        \\    input ::= unwrap_or_abort(.value = Reader#().read_byte(.self = $&system.terminal&.stdin))
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
        .argv = &.{ installed_argi, "run", module_dir, "--frontend-jobs", "1" },
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
    const extends = (target.cpu.arch == .x86_64 and target.os.tag != .windows) or (target.cpu.arch == .aarch64 and target.os.tag.isDarwin());
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
    try buildExpectFailWithoutNoise("tests/feature_tests/c_interop/48X_incomplete_handle_identity", "no function named '_read' accepts arguments", "failed without a diagnostic");
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
    try buildExpectFailWithoutNoise("tests/feature_tests/c_interop/72X_callback_nominal_identity", "no function named", "failed without a diagnostic");
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
    const target = @import("builtin").target;
    const extends = (target.cpu.arch == .x86_64 and target.os.tag != .windows) or (target.cpu.arch == .aarch64 and target.os.tag.isDarwin());
    try checkNativeCFixture("tests/feature_tests/c_interop/85_callback_invocation_scalar_signatures", if (extends) &.{
        "callback.nonnull",
        "call signext i16 %",
        "i8 signext",
        "call double %",
        "call void %",
    } else &.{
        "callback.nonnull",
        "call i16 %",
        "(i8 ",
        "call double %",
        "call void %",
    });
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
    try expect(std.mem.count(u8, before, "store i32 ") > std.mem.count(u8, after, "store i32 "));
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
    const source = "main := ()->(.status_code:Int32=0){ status_code=0 }\n";
    const expected = "main := () -> (.status_code: Int32 = 0) { status_code = 0 }\n";
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

test "formatter prepares all files before changing any source" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmpDirRootPath(&tmp);
    defer std.testing.allocator.free(root);
    const source = "main := ()->(.status_code:Int32=0){}\n";
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

test "feature_tests/system/55_posix_clock_contract" {
    if (@import("builtin").os.tag == .windows) return error.SkipZigTest;
    try checkNativeCFixture("tests/feature_tests/system/55_posix_clock_contract", &.{ "@clock_gettime", "@nanosleep" });
}

test "feature_tests/system/56_windows_clock_adapter" {
    try checkNativeCFixture("tests/feature_tests/system/56_windows_clock_adapter", &.{"@argi_windows_clock_probe"});
}

test "feature_tests/system/66_windows_process_quoting" {
    try checkNativeCFixture("tests/feature_tests/system/66_windows_process_quoting", &.{"@argi_windows_process_quote_probe"});
}

test "feature_tests/system/67_posix_process_contract" {
    if (@import("builtin").os.tag == .windows) return error.SkipZigTest;
    try checkNativeCFixture("tests/feature_tests/system/67_posix_process_contract", &.{"@argi_posix_process_probe"});
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

test "usecase_tests/05_python_csv_report" {
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
    const fixture = try std.fs.path.join(allocator, &.{ repo, "tests/usecase_tests/05_python_csv_report" });
    defer allocator.free(fixture);
    const sample = try std.fs.path.join(allocator, &.{ fixture, "requests.csv" });
    defer allocator.free(sample);
    const app = if (@import("builtin").os.tag == .windows) "report.exe" else "report";
    const executable = try std.fs.path.join(allocator, &.{ root, app });
    defer allocator.free(executable);

    // Rebuild from outside the checkout to exercise installed module discovery
    // and frontend reuse without a Python import from the example's directory.
    for (0..2) |_| {
        const built = try runChildInCwd(&.{ argi, "build", fixture, "--output", app, "--link-file", runtime, "--link-file", library, "--emit-llvm", "report.ll" }, root);
        defer allocator.free(built.stdout);
        defer allocator.free(built.stderr);
        if (built.term != .exited or built.term.exited != 0) std.debug.print("{s}", .{built.stderr});
        try expectEqual(std.process.Child.Term{ .exited = 0 }, built.term);
        const result = try runChildInCwd(&.{ executable, sample }, root);
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);
        try expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
        try expectEqualStrings("requests\t4\nmean_ms\t40.00\nmedian_ms\t25.00\n", result.stdout);
        try expectEqualStrings("", result.stderr);
    }

    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "custom.csv", .data = "endpoint,latency_ms\r\n\"/caf\xc3\xa9\",1.5\r\n/search,2.5\r\n" });
    const custom = try runChildInCwd(&.{ executable, "custom.csv", "latency_ms" }, root);
    defer allocator.free(custom.stdout);
    defer allocator.free(custom.stderr);
    try expectEqual(std.process.Child.Term{ .exited = 0 }, custom.term);
    try expectEqualStrings("requests\t2\nmean_ms\t2.00\nmedian_ms\t2.00\n", custom.stdout);
    try expectEqualStrings("", custom.stderr);

    for ([_]struct { data: []const u8, diagnostic: []const u8 }{
        .{ .data = "duration_ms\n", .diagnostic = "StatisticsError" },
        .{ .data = "other\n10\n", .diagnostic = "KeyError" },
        .{ .data = "duration_ms\n10\ninvalid\n", .diagnostic = "invalid_input" },
        .{ .data = "endpoint,duration_ms\n/health\n", .diagnostic = "TypeError" },
        .{ .data = "duration_ms\n-1\n", .diagnostic = "invalid_duration" },
        .{ .data = "duration_ms\nnan\n", .diagnostic = "invalid_input" },
        .{ .data = "duration_ms\ninf\n", .diagnostic = "invalid_input" },
        .{ .data = "duration_ms\n\xff\n", .diagnostic = "invalid_utf8" },
    }) |case| {
        try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "invalid.csv", .data = case.data });
        const result = try runChildInCwd(&.{ executable, "invalid.csv" }, root);
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);
        try expectEqual(std.process.Child.Term{ .exited = 1 }, result.term);
        try expectEqualStrings("", result.stdout);
        try expectDiagnostic("csv-report invalid input", result.stderr, case.diagnostic);
    }
    const missing = try runChildInCwd(&.{ executable, "missing.csv" }, root);
    defer allocator.free(missing.stdout);
    defer allocator.free(missing.stderr);
    try expectEqual(std.process.Child.Term{ .exited = 1 }, missing.term);
    try expectEqualStrings("", missing.stdout);
    try expect(std.mem.indexOf(u8, missing.stderr, "missing.csv") != null);
    const usage = try runChildInCwd(&.{executable}, root);
    defer allocator.free(usage.stdout);
    defer allocator.free(usage.stderr);
    try expectEqual(std.process.Child.Term{ .exited = 1 }, usage.term);
    try expect(std.mem.indexOf(u8, usage.stdout, "Usage: csv-report") != null);
}
test "feature_tests/python/02_values_errors" {
    try checkPythonFixture("tests/feature_tests/python/02_values_errors");
}
test "feature_tests/python/03_keywords" {
    try checkPythonFixture("tests/feature_tests/python/03_keywords");
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
    try expect(std.mem.indexOf(u8, result.stderr, "error trace") != null);
    try expect(std.mem.indexOf(u8, result.stderr, "error trace (most recent first)") != null);
    try expect(std.mem.indexOf(u8, result.stderr, "starting application") != null);
    const location = if (@import("builtin").os.tag == .windows) "76_fallible_main_trace\\main.rg:4:" else "76_fallible_main_trace/main.rg:4:";
    try expect(std.mem.indexOf(u8, result.stderr, location) != null);
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
    try expectEqualStrings("custom trace\n", result.stderr);
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
    const location = if (@import("builtin").os.tag == .windows) "83_fallible_main_local_tracer\\main.rg:5:" else "83_fallible_main_local_tracer/main.rg:5:";
    try expect(std.mem.indexOf(u8, result.stderr, location) != null);
}

test "feature_tests/python/13_numpy_vector" {
    var environment = try std.testing.environ.createMap(std.testing.allocator);
    defer environment.deinit();
    if (!std.mem.eql(u8, environment.get("ARGI_PYTHON_NUMPY") orelse "", "1")) return error.SkipZigTest;
    try checkPythonFixture("tests/feature_tests/python/13_numpy_vector");
}

test "feature_tests/system/79_network_native" {
    try checkNativeCFixture("tests/feature_tests/system/79_network_native", &.{"declare i32 @argi_network_probe()"});
}

test "feature_tests/system/85_filesystem_native" {
    try checkNativeCFixture("tests/feature_tests/system/85_filesystem_native", &.{"declare i32 @argi_filesystem_probe()"});
}

test "feature_tests/testing/16_equality_helpers" {
    try argiTestExpectStderr("tests/feature_tests/testing/16_equality_helpers", &.{}, 0, "PASS equality_helpers\n");
}

test "feature_tests/testing/17_numeric_diagnostics signed_value" {
    try argiTestExpectStderrContains("tests/feature_tests/testing/17_numeric_diagnostics", &.{ "--filter", "signed_value" }, 1, "expected -9223372036854775808, actual 9223372036854775807");
}

test "feature_tests/testing/17_numeric_diagnostics unsigned_value" {
    try argiTestExpectStderrContains("tests/feature_tests/testing/17_numeric_diagnostics", &.{ "--filter", "unsigned_value" }, 1, "expected 18446744073709551615, actual 0");
}

test "feature_tests/testing/17_numeric_diagnostics float_value" {
    try argiTestExpectStderrContains("tests/feature_tests/testing/17_numeric_diagnostics", &.{ "--filter", "float_value" }, 1, "expected 1.5, actual 2.5");
}

test "feature_tests/testing/17_numeric_diagnostics bool_value" {
    try argiTestExpectStderrContains("tests/feature_tests/testing/17_numeric_diagnostics", &.{ "--filter", "bool_value" }, 1, "expected true, actual false");
}

test "feature_tests/testing/18_string_diagnostics string_mismatch" {
    try argiTestExpectStderrContains("tests/feature_tests/testing/18_string_diagnostics", &.{ "--filter", "string_mismatch" }, 1, "strings differ at byte 1: expected 98, actual 120; lengths expected 3, actual 3");
}

test "feature_tests/testing/18_string_diagnostics string_prefix" {
    try argiTestExpectStderrContains("tests/feature_tests/testing/18_string_diagnostics", &.{ "--filter", "string_prefix" }, 1, "strings differ at byte 2: expected 99, actual <end>; lengths expected 3, actual 2");
}

test "feature_tests/testing/18_string_diagnostics string_empty" {
    try argiTestExpectStderrContains("tests/feature_tests/testing/18_string_diagnostics", &.{ "--filter", "string_empty" }, 1, "strings differ at byte 0: expected <end>, actual 120; lengths expected 0, actual 1");
}

test "feature_tests/testing/18_string_diagnostics string_embedded_nul" {
    try argiTestExpectStderrContains("tests/feature_tests/testing/18_string_diagnostics", &.{ "--filter", "string_embedded_nul" }, 1, "strings differ at byte 2: expected 90, actual 91; lengths expected 3, actual 3");
}

test "feature_tests/testing/19_view_diagnostics view_mismatch" {
    try argiTestExpectStderrContains("tests/feature_tests/testing/19_view_diagnostics", &.{ "--filter", "view_mismatch" }, 1, "views differ at index 1; lengths expected 3, actual 3");
}

test "feature_tests/testing/19_view_diagnostics byte_prefix" {
    try argiTestExpectStderrContains("tests/feature_tests/testing/19_view_diagnostics", &.{ "--filter", "byte_prefix" }, 1, "bytes differ at byte 1: expected 2, actual <end>; lengths expected 2, actual 1");
}

test "feature_tests/testing/20_bounded_diagnostics bounded_message" {
    try argiTestExpectStderrContains("tests/feature_tests/testing/20_bounded_diagnostics", &.{ "--filter", "bounded_message" }, 1, "<context truncated>");
}

test "usecase_tests/03_word_count" {
    const test_path = "tests/usecase_tests/03_word_count";
    try expectSuccessfulBuild(test_path);
    const output_path = try outputPathFor(test_path);
    defer std.testing.allocator.free(output_path);
    const result = try runChild(&.{ output_path, "tests/feature_tests/system/86_word_count_consumer/data", "64" });
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);
    try expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    var lines = std.mem.tokenizeScalar(u8, result.stdout, '\n');
    var seen: u8 = 0;
    while (lines.next()) |line| {
        const bit: u8 = if (std.mem.eql(u8, line, "3\tcafé")) 1 else if (std.mem.eql(u8, line, "2\ttea")) 2 else if (std.mem.eql(u8, line, "2\t🙂")) 4 else return error.UnexpectedWordCount;
        try expect(seen & bit == 0);
        seen |= bit;
    }
    try expectEqual(@as(u8, 7), seen);
    try runExpectStdoutWithArgs(test_path, &.{}, 0, "Usage: word-count <directory> [maximum-file-bytes]\n");
    const failure = try runChild(&.{ output_path, "tests/feature_tests/system/86_word_count_consumer/data", "1" });
    defer std.testing.allocator.free(failure.stdout);
    defer std.testing.allocator.free(failure.stderr);
    switch (failure.term) {
        .exited => |code| try expect(code != 0),
        else => return error.UnexpectedProcessTermination,
    }
    try expectEqualStrings("", failure.stdout);
    try expect(std.mem.indexOf(u8, failure.stderr, "size_limit_exceeded") != null);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const large_input = try std.testing.allocator.alloc(u8, 5 * 2000);
    defer std.testing.allocator.free(large_input);
    for (0..2000) |index| @memcpy(large_input[index * 5 ..][0..5], "word ");
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "large.txt", .data = large_input });
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "unicode.txt", .data = "word\tcafé\r\n" });
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "empty.txt", .data = "" });
    try tmp.dir.createDirPath(std.testing.io, "nested");
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "nested/ignored.txt", .data = "ignored" });

    var cwd_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const cwd_length = try tmp.dir.realPath(std.testing.io, &cwd_buffer);
    const repo_root = try repoRootPrefix();
    defer std.testing.allocator.free(repo_root);
    const executable = try std.fs.path.join(std.testing.allocator, &.{ repo_root, output_path });
    defer std.testing.allocator.free(executable);

    for ([_][]const u8{ ".", "./" }) |directory| {
        const counted = try runChildInCwd(&.{ executable, directory, "10000" }, cwd_buffer[0..cwd_length]);
        defer std.testing.allocator.free(counted.stdout);
        defer std.testing.allocator.free(counted.stderr);
        try expectEqual(std.process.Child.Term{ .exited = 0 }, counted.term);
        try expectEqualStrings("", counted.stderr);
        try expect(std.mem.eql(u8, counted.stdout, "2001\tword\n1\tcafé\n") or
            std.mem.eql(u8, counted.stdout, "1\tcafé\n2001\tword\n"));
    }

    for ([_][]const u8{ "9999", "invalid", "-1" }) |limit| {
        const rejected = try runChildInCwd(&.{ executable, ".", limit }, cwd_buffer[0..cwd_length]);
        defer std.testing.allocator.free(rejected.stdout);
        defer std.testing.allocator.free(rejected.stderr);
        try expectEqual(std.process.Child.Term{ .exited = 1 }, rejected.term);
        try expectEqualStrings("", rejected.stdout);
        try expect(rejected.stderr.len > 0);
        if (std.mem.eql(u8, limit, "9999")) {
            try expect(std.mem.indexOf(u8, rejected.stderr, "large.txt") != null);
        }
    }

    try tmp.dir.createDirPath(std.testing.io, "invalid-utf8");
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "invalid-utf8/bad.txt", .data = "valid \xff" });
    const invalid_utf8 = try runChildInCwd(&.{ executable, "invalid-utf8" }, cwd_buffer[0..cwd_length]);
    defer std.testing.allocator.free(invalid_utf8.stdout);
    defer std.testing.allocator.free(invalid_utf8.stderr);
    try expectEqual(std.process.Child.Term{ .exited = 1 }, invalid_utf8.term);
    try expectEqualStrings("", invalid_utf8.stdout);
    try expect(std.mem.indexOf(u8, invalid_utf8.stderr, "invalid_utf8") != null);
    try expect(std.mem.indexOf(u8, invalid_utf8.stderr, "bad.txt") != null);

    try tmp.dir.createDirPath(std.testing.io, "empty-directory");
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "empty-directory/empty.txt", .data = "" });
    const empty = try runChildInCwd(&.{ executable, "empty-directory", "0" }, cwd_buffer[0..cwd_length]);
    defer std.testing.allocator.free(empty.stdout);
    defer std.testing.allocator.free(empty.stderr);
    try expectEqual(std.process.Child.Term{ .exited = 0 }, empty.term);
    try expectEqualStrings("", empty.stdout);
    try expectEqualStrings("", empty.stderr);
}

test "usecase_tests/04_tree" {
    const path = "tests/usecase_tests/04_tree";
    try expectSuccessfulBuild(path);
    try runExpectStdoutWithArgs(path, &.{ "--root", "does-not-exist", "--depth=0" }, 0, "");
    const output = try outputPathFor(path);
    defer std.testing.allocator.free(output);
    const result = try runChild(&.{ output, "-r", "tests/feature_tests/system/86_word_count_consumer/data", "-d2" });
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);
    try expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try expect(std.mem.indexOf(u8, result.stdout, "/ignored/nested.txt\n") != null);
    var lines = std.mem.tokenizeScalar(u8, result.stdout, '\n');
    var count: usize = 0;
    while (lines.next() != null) count += 1;
    try expectEqual(@as(usize, 5), count);
    const help = try runChild(&.{ output, "--help" });
    defer std.testing.allocator.free(help.stdout);
    defer std.testing.allocator.free(help.stderr);
    try expectEqual(std.process.Child.Term{ .exited = 0 }, help.term);
    try expect(std.mem.indexOf(u8, help.stdout, "-r, --root <PATH> (required)") != null);
    try expect(std.mem.indexOf(u8, help.stdout, "[default: 64]") != null);
}

test "feature_tests/system/95_atomic_native" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmpDirRootPath(&tmp);
    defer allocator.free(root);
    const argi = try installedArgiPath();
    defer allocator.free(argi);
    const repo = try repoRootPrefix();
    defer allocator.free(repo);
    const fixture = try std.fs.path.join(allocator, &.{ repo, "tests/feature_tests/system/95_atomic_native" });
    defer allocator.free(fixture);
    const source = try std.fs.path.join(allocator, &.{ fixture, "native.c" });
    defer allocator.free(source);
    const windows = @import("builtin").os.tag == .windows;
    const compiled = try runChildInCwd(if (windows) &.{ "cc", "-c", source, "-o", "native.o" } else &.{ "cc", "-pthread", "-c", source, "-o", "native.o" }, root);
    defer allocator.free(compiled.stdout);
    defer allocator.free(compiled.stderr);
    try expectEqual(std.process.Child.Term{ .exited = 0 }, compiled.term);
    const built = try runChildInCwd(if (windows) &.{ argi, "build", fixture, "--output", "app", "--link-file", "native.o" } else &.{ argi, "build", fixture, "--output", "app", "--link-file", "native.o", "--link-library", "pthread" }, root);
    defer allocator.free(built.stdout);
    defer allocator.free(built.stderr);
    if (built.term != .exited or built.term.exited != 0) std.debug.print("{s}", .{built.stderr});
    try expectEqual(std.process.Child.Term{ .exited = 0 }, built.term);
    const executed = try runChildInCwd(&.{"./app"}, root);
    defer allocator.free(executed.stdout);
    defer allocator.free(executed.stderr);
    try expectEqual(std.process.Child.Term{ .exited = 0 }, executed.term);
}

test "program test shard assignment preserves fixture isolation" {
    try @import("program_test_sharding").verifyIsolation();
}

test "discovered fixture groups preserve published namespaces" {
    const suite = @import("program_tests");
    try expect(suite.groups.len != 0);
    for (suite.groups) |group| {
        try expect(std.mem.startsWith(u8, group.fixture, "tests/feature_tests/"));
        try expect(std.mem.endsWith(u8, group.prefix, ".test."));
    }
}

test "feature_tests/contracts/321X_unused_conformance_consumption" {
    try expectSuccessfulBuild("tests/feature_tests/contracts/321X_unused_conformance_consumption");
    const result = try runChild(&.{ argi_bin, "check", "tests/feature_tests/contracts/321X_unused_conformance_consumption" });
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);
    try expect(result.term == .exited and result.term.exited != 0);
    try expect(std.mem.indexOf(u8, result.stderr, "cannot prove consumes") != null);
}

test "feature_tests/contracts/325_deferred_operation_body" {
    try expectSuccessfulBuild("tests/feature_tests/contracts/325_deferred_operation_body");
    const result = try runChild(&.{ argi_bin, "check", "tests/feature_tests/contracts/325_deferred_operation_body" });
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);
    try expect(result.term == .exited and result.term.exited != 0);
    try expect(std.mem.indexOf(u8, result.stderr, "cannot materialize function body") != null);
}

test "compiler fixture frontend policy preserves explicit workers and run selection" {
    const allocator = std.testing.allocator;
    const normal = try compilerTestArgs(&.{ argi_bin, "build", "module" });
    defer allocator.free(normal);
    try expectEqualStrings("--frontend-jobs", normal[2]);
    try expectEqualStrings("1", normal[3]);
    const explicit = try compilerTestArgs(&.{ argi_bin, "build", "module", "--frontend-jobs", "8" });
    defer allocator.free(explicit);
    try expectEqual(@as(usize, 5), explicit.len);
    try expectEqualStrings("8", explicit[4]);
    const selected = try compilerTestArgs(&.{ argi_bin, "run", "example" });
    defer allocator.free(selected);
    try expectEqualStrings("example", selected[2]);
    try expectEqualStrings("--frontend-jobs", selected[3]);
    const other = try compilerTestArgs(&.{ "native-program", "build" });
    defer allocator.free(other);
    try expectEqual(@as(usize, 2), other.len);
}

test "usecase_tests/06_weighted_regression" {
    try expectSuccessfulBuild("tests/usecase_tests/06_weighted_regression");
    try runExpect("tests/usecase_tests/06_weighted_regression", 0);
}

test "feature_tests/execution/14_integer_boundaries_vm" {
    try expectSuccessfulBuild("tests/feature_tests/execution/14_integer_boundaries_vm");
    try runExpect("tests/feature_tests/execution/14_integer_boundaries_vm", 42);
    try expectArgiBuildSuccess(&.{ "build", "tests/feature_tests/execution/14_integer_boundaries_vm", "--release" });
    try runExpect("tests/feature_tests/execution/14_integer_boundaries_vm", 42);
    try vmExpect("tests/feature_tests/execution/14_integer_boundaries_vm", 42, null);
}

test "feature_tests/execution/15_native_constant_wrapping" {
    try expectSuccessfulBuild("tests/feature_tests/execution/15_native_constant_wrapping");
    try runExpect("tests/feature_tests/execution/15_native_constant_wrapping", 42);
    try expectArgiBuildSuccess(&.{ "build", "tests/feature_tests/execution/15_native_constant_wrapping", "--release" });
    try runExpect("tests/feature_tests/execution/15_native_constant_wrapping", 42);
}

test "feature_tests/execution/16X_integer_division_zero" {
    try expectSuccessfulBuild("tests/feature_tests/execution/16X_integer_division_zero");
    try runExpectFailure("tests/feature_tests/execution/16X_integer_division_zero");
    try expectArgiBuildSuccess(&.{ "build", "tests/feature_tests/execution/16X_integer_division_zero", "--release" });
    try runExpectFailure("tests/feature_tests/execution/16X_integer_division_zero");
    try vmExpect("tests/feature_tests/execution/16X_integer_division_zero", 1, "ExecutionDivisionByZero");
}

test "feature_tests/execution/17X_integer_remainder_zero" {
    try expectSuccessfulBuild("tests/feature_tests/execution/17X_integer_remainder_zero");
    try runExpectFailure("tests/feature_tests/execution/17X_integer_remainder_zero");
    try expectArgiBuildSuccess(&.{ "build", "tests/feature_tests/execution/17X_integer_remainder_zero", "--release" });
    try runExpectFailure("tests/feature_tests/execution/17X_integer_remainder_zero");
    try vmExpect("tests/feature_tests/execution/17X_integer_remainder_zero", 1, "ExecutionDivisionByZero");
}

test "feature_tests/execution/34X_destination_checked_before_rhs" {
    const fixture = "tests/feature_tests/execution/34X_destination_checked_before_rhs";
    try expectSuccessfulBuild(fixture);
    const path = try outputPathFor(fixture);
    defer std.testing.allocator.free(path);
    const result = try runChild(&.{path});
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);
    try expect(result.term != .exited or result.term.exited != 0);
    try expect(std.mem.indexOf(u8, result.stderr, "runtime error: array index is out of bounds") != null);
    try expect(std.mem.indexOf(u8, result.stderr, "explicit abort") == null);
    try vmExpect("tests/feature_tests/execution/34X_destination_checked_before_rhs", 1, "ExecutionIndexOutOfBounds");
}

test "feature_tests/execution/77_computed_test_condition" {
    try argiTestExpectStderr("tests/feature_tests/execution/77_computed_test_condition", &.{}, 0, "PASS selected\n");
}

test "feature_tests/testing/31_computed_module_selection" {
    try argiTestExpectStderr("tests/feature_tests/testing/31_computed_module_selection", &.{}, 0, "PASS selected\n");
    try argiTestExpectStderr("tests/feature_tests/testing/31_computed_module_selection", &.{ "--filter", "discarded" }, 1, "No tests found\n");
}

test "bytecode CLI execution budgets" {
    const path = "tests/feature_tests/execution/115_computed_transient_types";
    const bounded = try runChild(&.{ argi_bin, "run", "--vm", "--frontend-jobs", "1", "--vm-instructions", "0", path });
    defer std.testing.allocator.free(bounded.stdout);
    defer std.testing.allocator.free(bounded.stderr);
    try expect(bounded.term == .exited and bounded.term.exited != 0);
    try expect(std.mem.indexOf(u8, bounded.stderr, "ExecutionInstructionLimit") != null);
    const allowed = try runChild(&.{ argi_bin, "run", "--vm", "--frontend-jobs", "1", "--vm-instructions", "1000000", "--vm-call-depth", "128", "--vm-value-cells", "1000000", path });
    defer std.testing.allocator.free(allowed.stdout);
    defer std.testing.allocator.free(allowed.stderr);
    try expect(allowed.term == .exited and allowed.term.exited == 42);
    const invalid = try runChild(&.{ argi_bin, "repl", "--vm-instructions", "-1" });
    defer std.testing.allocator.free(invalid.stdout);
    defer std.testing.allocator.free(invalid.stderr);
    try expect(invalid.term == .exited and invalid.term.exited != 0);
    try expect(std.mem.indexOf(u8, invalid.stderr, "InvalidExecutionLimit") != null);
}

test "argi repl retains transient default recipes across commands" {
    try expectReplFixture(
        "tests/feature_tests/execution/137_comptime_transient_defaults/main.rg",
        "with_default(.value = 7)\n#run () -> (.answer: Int32) { answer = with_default(.value = 9) }\nwith_default(.value = true)\n",
        "_0 = 42\n_1 = 42\n_2 = 42\n",
    );
}

test "argi repl distinguishes transient expression default specializations" {
    try expectReplFixture(
        "tests/feature_tests/execution/138_comptime_transient_expression_defaults/main.rg",
        "with_default#(.T: Int32, .n = 40)(.value = 7)\n#run () -> (.answer: Int32) { answer = with_default#(.T: Int32, .n = 39)(.value = 9) }\nwith_default#(.T: Bool, .n = 40)(.value = true)\n",
        "_0 = 42\n_1 = 41\n_2 = 42\n",
    );
}

fn expectReplFixture(fixture_path: ?[]const u8, commands: []const u8, expected: []const u8) !void {
    return expectReplFixtureWithDiagnostic(fixture_path, commands, expected, null);
}

fn expectReplFixtureWithDiagnostic(fixture_path: ?[]const u8, commands: []const u8, expected: []const u8, expected_diagnostic: ?[]const u8) !void {
    const installed_argi = try installedArgiPath();
    defer std.testing.allocator.free(installed_argi);
    var child = try std.process.spawn(std.testing.io, .{
        .argv = &.{ installed_argi, "repl" },
        .cwd = .{ .path = compilerRoot() },
        .stdin = .pipe,
        .stdout = .pipe,
        .stderr = .pipe,
    });
    defer child.kill(std.testing.io);
    if (fixture_path) |path| {
        const fixture = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, std.testing.allocator, .limited(64 * 1024));
        defer std.testing.allocator.free(fixture);
        const definitions_end = std.mem.indexOf(u8, fixture, "main :=") orelse return error.MissingFixtureEntrypoint;
        try child.stdin.?.writeStreamingAll(std.testing.io, ":begin\n");
        try child.stdin.?.writeStreamingAll(std.testing.io, fixture[0..definitions_end]);
        try child.stdin.?.writeStreamingAll(std.testing.io, ":end\n");
    }
    try child.stdin.?.writeStreamingAll(std.testing.io, commands);
    try child.stdin.?.writeStreamingAll(std.testing.io, ":reset\n");
    child.stdin.?.close(std.testing.io);
    child.stdin = null;
    var buffer: std.Io.File.MultiReader.Buffer(2) = undefined;
    var reader: std.Io.File.MultiReader = undefined;
    reader.init(std.testing.allocator, std.testing.io, buffer.toStreams(), &.{ child.stdout.?, child.stderr.? });
    defer reader.deinit();
    while (true) reader.fill(1, .none) catch |err| switch (err) {
        error.EndOfStream => break,
        else => return err,
    };
    const stdout = try reader.toOwnedSlice(0);
    defer std.testing.allocator.free(stdout);
    const stderr = try reader.toOwnedSlice(1);
    defer std.testing.allocator.free(stderr);
    try expectEqual(std.process.Child.Term{ .exited = 0 }, try child.wait(std.testing.io));
    if (expected_diagnostic) |message| {
        try expectDiagnostic("argi repl", stderr, message);
        try expectEqual(@as(usize, 1), std.mem.count(u8, stderr, ": error:"));
    } else {
        if (stderr.len != 0) std.debug.print("REPL stderr: {s}\n", .{stderr});
        try expectEqualStrings("", stderr);
    }
    try expectEqualStrings(expected, stdout);
}

test "argi repl preserves record defaults across specializations" {
    try expectReplFixture(
        "tests/feature_tests/execution/149_comptime_record_defaults/main.rg",
        "with_default#(.T: Int32, .n = 17)(.value = 7)\n#run () -> (.answer: Int32) { answer = with_default#(.T: Bool, .n = 16)(.value = true) }\nwith_default#(.T: Int32, .n = 17)(.value = 9)\n",
        "_0 = 42\n_1 = 41\n_2 = 42\n",
    );
}

test "argi repl preserves array defaults across specializations" {
    try expectReplFixture(
        "tests/feature_tests/execution/150_comptime_array_defaults/main.rg",
        "with_default#(.T: Int32, .n = 17)(.value = 7)\n#run () -> (.answer: Int32) { answer = with_default#(.T: Bool, .n = 16)(.value = true) }\nwith_default#(.T: Int32, .n = 17)(.value = 9)\n",
        "_0 = 42\n_1 = 41\n_2 = 42\n",
    );
}

test "argi repl preserves choice defaults across specializations" {
    try expectReplFixture(
        "tests/feature_tests/execution/160_comptime_choice_defaults/main.rg",
        "with_default#(.T: Int32, .n = 42)(.value = 7)\nwith_default#(.T: Bool, .n = 41)(.value = true)\nwith_default#(.T: Int32, .n = 0)(.value = 9)\n#run () -> (.answer: Int32) { answer = with_default#(.T: Bool, .n = 42)(.value = true) }\n",
        "_0 = 42\n_1 = 41\n_2 = 0\n_3 = 42\n",
    );
}

test "argi repl supplies persistent allocator capabilities across reset" {
    try expectReplFixture(
        null,
        "text ::= unwrap_or_abort(.value = String(.length = 3))\nbyte_length(.self = &text)\nnumbers ::= unwrap_or_abort(.value = DynamicArray#(.t: Int32)(.capacity = 2))\npush_assume_capacity(.self = $&numbers, .value = 42)\nunwrap_or_abort(.value = get(.self = &numbers, .index = 0))\n:reset\ntext ::= unwrap_or_abort(.value = String(.length = 4))\nbyte_length(.self = &text)\n",
        "_0 = 3\n_1 = ()\n_2 = 42\n_0 = 4\n",
    );
}

test "feature_tests/execution/169X_acquired_slot_index_mismatch" {
    try expectSuccessfulBuild("tests/feature_tests/execution/169X_acquired_slot_index_mismatch");
    try runExpectFailure("tests/feature_tests/execution/169X_acquired_slot_index_mismatch");
    const result = try runArgiCommand(&.{ "run", "--vm", "tests/feature_tests/execution/169X_acquired_slot_index_mismatch" });
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);
    try expectEqual(std.process.Child.Term{ .exited = 1 }, result.term);
    try expectDiagnostic("tests/feature_tests/execution/169X_acquired_slot_index_mismatch", result.stderr, "ExecutionAborted");
    try expectDiagnostic("tests/feature_tests/execution/169X_acquired_slot_index_mismatch", result.stderr, "allocation_slots.rg:");
}

test "argi repl retains prepared generic resource slots across submissions" {
    const commands =
        \\Box := #(.T: Type) (.value: T)
        \\implement#(.T: Type) Deinit#(Box#(T)) (
        \\    .deinit = (.self: $&Box#(T)) -> () {}
        \\)
        \\memory ::= unwrap_or_abort(.value = allocate#(.t: Box#(Int32))(.self = allocator, .count = 1))
        \\raw ::= raw_pointer#(.t: Box#(Int32))(.address = memory.data.address).raw
        \\first ::= trusted_establish_allocation_slot#(.t: Box#(Int32))(.allocation = &memory, .slot = raw, .anchor = memory.anchor, .index = ..some(.value = 0)).reference
        \\trusted_opaque_move_in(.storage = $&memory, .destination = first, .source = Box#(Int32)(.value = 42))
        \\first&.value
        \\trusted_opaque_drop(.slot = first)
        \\trusted_opaque_mark_empty(.storage = $&memory)
        \\
    ;
    try expectReplFixture(null, commands, "_0 = ()\n_1 = 42\n_2 = ()\n_3 = ()\n");
}

test "argi repl retains acquired reference companions across submissions" {
    const commands =
        \\Pair := (.source: &Int32)
        \\value :: Int32 = 42
        \\memory ::= unwrap_or_abort(.value = allocate#(.t: Pair)(.self = allocator))
        \\raw ::= raw_pointer#(.t: Pair)(.address = memory.data.address).raw
        \\reference ::= trusted_establish_allocation_slot#(.t: Pair)(.allocation = &memory, .slot = raw, .anchor = memory.anchor, .index = ..some(.value = 0)).reference
        \\trusted_opaque_move_in(.storage = $&memory, .destination = reference, .source = Pair(.source = &value))
        \\borrowed ::= reference&.source
        \\borrowed&
        \\
    ;
    try expectReplFixture(null, commands, "_0 = ()\n_1 = 42\n");
}

test "argi repl retains acquired virtual witnesses across submissions" {
    const commands =
        \\Counter := (.value: Int32)
        \\Counting#(.State: Type): Contract = (
        \\    .bump: (.self: $&State, .amount: Int32) -> () where {}
        \\    .read: (.self: &State) -> (.result: Int32) where {}
        \\)
        \\implement Counting#(Counter) (
        \\    .bump = (.self: $&Counter, .amount: Int32) -> () { self&.value = self&.value + amount }
        \\    .read = (.self: &Counter) -> (.result: Int32) { result = self&.value }
        \\)
        \\Holder := (.counter: Virtual#(.contract: Counting))
        \\counter :: Counter = (.value = 7)
        \\memory ::= unwrap_or_abort(.value = allocate#(.t: Holder)(.self = allocator))
        \\raw ::= raw_pointer#(.t: Holder)(.address = memory.data.address).raw
        \\slot ::= trusted_establish_allocation_slot#(.t: Holder)(.allocation = &memory, .slot = raw, .anchor = memory.anchor, .index = ..some(.value = 0)).reference
        \\trusted_opaque_move_in(.storage = $&memory, .destination = slot, .source = Holder(.counter = to_virtual#(.contract: Counting)(.value = $&counter)))
        \\Counting#().bump(.self = $&slot&.counter, .amount = 35)
        \\Counting#().read(.self = &slot&.counter).result
        \\
    ;
    try expectReplFixture(null, commands, "_0 = ()\n_1 = ()\n_2 = 42\n");
}

test "argi repl retains acquired choice cleanup identities across submissions" {
    const commands =
        \\Counter := (.drops: Int32 = 0)
        \\Resource := (.counter: $&Counter, .id: Int32)
        \\Choice: Type = (..pair(.left: Resource, .right: Resource), ..empty)
        \\implement Deinit#(Resource) (
        \\    .deinit = (.self: $&Resource) -> () { self&.counter&.drops = self&.counter&.drops + self&.id }
        \\)
        \\counter :: Counter = Counter()
        \\memory ::= unwrap_or_abort(.value = allocate#(.t: Choice)(.self = allocator))
        \\raw ::= raw_pointer#(.t: Choice)(.address = memory.data.address).raw
        \\slot ::= trusted_establish_allocation_slot#(.t: Choice)(.allocation = &memory, .slot = raw, .anchor = memory.anchor, .index = ..some(.value = 0)).reference
        \\value :: Choice = ..pair(.left = (.counter = $&counter, .id = 11), .right = (.counter = $&counter, .id = 31))
        \\filled ::= trusted_opaque_move_in(.storage = $&memory, .destination = slot, .source = ~value)
        \\dropped ::= trusted_opaque_drop(.slot = slot)
        \\emptied ::= trusted_opaque_mark_empty(.storage = $&memory)
        \\counter.drops
        \\
    ;
    try expectReplFixture(null, commands, "_0 = 42\n");
}

test "argi repl cleans fallible aggregate operands across submissions" {
    const commands =
        \\counter :: Counter = Counter()
        \\failed ::= build_owned(.counter = $&counter, .fail = true, .tracer = error_tracer)
        \\counter.drops
        \\succeeded ::= build_owned(.counter = $&counter, .fail = false, .tracer = error_tracer)
        \\counter.drops
        \\discarded ::= discard_result(.value = ~succeeded)
        \\counter.drops
        \\probe()
        \\
    ;
    try expectReplFixture("tests/feature_tests/execution/263_comptime_fallible_operand_cleanup/main.rg", commands, "_0 = 7\n_1 = 7\n_2 = 28\n_3 = 112\n");
}

test "argi repl preserves captured destinations and rejects historical retargeted references" {
    const commands =
        \\counter :: Counter = Counter()
        \\owner :: Resource = Resource(.counter = $&counter, .value = 1)
        \\other :: Resource = Resource(.counter = $&counter, .value = 2)
        \\holder :: Holder = Holder(.reference = $&owner)
        \\failed ::= replace(.holder = $&holder, .other = $&other, .counter = $&counter, .fail = true)
        \\owner.value
        \\counter.drops
        \\holder.reference&.value
        \\holder.reference = $&owner
        \\historical ::= holder.reference
        \\succeeded ::= replace(.holder = $&holder, .other = $&other, .counter = $&counter, .fail = false)
        \\historical&.value
        \\owner.value
        \\counter.drops
        \\holder.reference&.value
        \\counter.selections
        \\closed_owner ::= deinit(.self = $&owner)
        \\closed_other ::= deinit(.self = $&other)
        \\counter.drops
        \\
    ;
    try expectReplFixtureWithDiagnostic(
        "tests/feature_tests/execution/265_fallible_retargeted_reference_replacement/main.rg",
        commands,
        "_0 = 1\n_1 = 0\n_2 = 2\n_4 = 9\n_5 = 1\n_6 = 2\n_7 = 2\n_8 = 3\n",
        "reference depends on a root that has ended",
    );
}

test "argi repl retains partial acquired array cleanup across submissions" {
    const commands =
        \\counter :: Counter = Counter()
        \\memory ::= unwrap_or_abort(.value = allocate#(.t: [3]Resource)(.self = allocator))
        \\raw ::= raw_pointer#(.t: [3]Resource)(.address = memory.data.address).raw
        \\slot ::= trusted_establish_allocation_slot#(.t: [3]Resource)(.allocation = &memory, .slot = raw, .anchor = memory.anchor, .index = ..some(.value = 0)).reference
        \\index :: UIntNative = 0
        \\slot&[index] = Resource(.counter = $&counter, .value = 10)
        \\slot&[0].value
        \\index = 2
        \\slot&[index] = Resource(.counter = $&counter, .value = 32)
        \\slot&[2].value
        \\trusted_opaque_drop(.slot = slot)
        \\trusted_opaque_mark_empty(.storage = $&memory)
        \\counter.drops
        \\
    ;
    try expectReplFixture("tests/feature_tests/execution/270_large_reference_aggregate_cleanup/main.rg", commands, "_0 = 10\n_1 = 32\n_2 = ()\n_3 = ()\n_4 = 2\n");
}

test "argi repl preserves indexed replacement destinations across submissions" {
    const commands =
        \\:begin
        \\select_array_index := (.selection: $&UIntNative, .counter: $&Counter) -> (.result: UIntNative)  {
        \\    counter&.selections = counter&.selections + 1
        \\    result = selection&
        \\}
        \\make_array_resource := (.selection: $&UIntNative, .counter: $&Counter, .fail: Bool) -> (.result: Errable#(Resource, (..stop)))  {
        \\    selection&= 1
        \\    if fail { result = ..error(.reason = ..stop) } else { result = ..ok Resource(.counter = counter, .value = 9) }
        \\}
        \\replace_array := (.values: $&[2]Resource, .selection: $&UIntNative, .counter: $&Counter, .fail: Bool) -> (.result: Errable#(Int32, (..stop)))  {
        \\    values&[select_array_index(.selection = selection, .counter = counter)] = make_array_resource(.selection = selection, .counter = counter, .fail = fail)!
        \\    result = ..ok 42
        \\}
        \\:end
        \\counter :: Counter = Counter()
        \\values :: [2]Resource = (Resource(.counter = $&counter, .value = 1), Resource(.counter = $&counter, .value = 2))
        \\selection :: UIntNative = 0
        \\failed ::= replace_array(.values = $&values, .selection = $&selection, .counter = $&counter, .fail = true)
        \\values[0].value
        \\counter.drops
        \\selection
        \\counter.selections
        \\selection = 0
        \\succeeded ::= replace_array(.values = $&values, .selection = $&selection, .counter = $&counter, .fail = false)
        \\values[0].value
        \\values[1].value
        \\counter.drops
        \\counter.selections
        \\closed_first ::= deinit(.self = $&values[0])
        \\closed_second ::= deinit(.self = $&values[1])
        \\counter.drops
        \\
    ;
    try expectReplFixture("tests/feature_tests/execution/265_fallible_retargeted_reference_replacement/main.rg", commands, "_0 = 1\n_1 = 0\n_2 = 1\n_3 = 1\n_4 = 9\n_5 = 2\n_6 = 1\n_7 = 2\n_8 = 3\n");
}

test "argi repl renews borrowed argument references without renewing copies" {
    const commands =
        \\counter :: Counter = Counter()
        \\owner :: Resource = Resource(.counter = $&counter)
        \\args: Args = (.target = $&owner, .counter = $&counter)
        \\historical ::= args.target
        \\closed ::= deinit(.self = args.target)
        \\initialize_borrowed(.args = &args)
        \\args.target&.counter&.count
        \\historical&.counter&.count
        \\owner.counter&.count
        \\closed_owner ::= deinit(.self = $&owner)
        \\counter.count
        \\
    ;
    try expectReplFixtureWithDiagnostic("tests/feature_tests/ownership/364_projected_call_reinitialization/main.rg", commands, "_0 = ()\n_1 = 1\n_3 = 1\n_4 = 2\n", "reference depends on a root that has ended");
}

test "feature_tests/execution/275_comptime_system_entry" {
    const built = try buildResult("tests/feature_tests/execution/275_comptime_system_entry");
    defer std.testing.allocator.free(built.stdout);
    defer std.testing.allocator.free(built.stderr);
    try expectEqual(std.process.Child.Term{ .exited = 0 }, built.term);
    try expect(std.mem.count(u8, built.stdout, "compile-time host") == 1);
    try runExpect("tests/feature_tests/execution/275_comptime_system_entry", 42);
    try vmExpect("tests/feature_tests/execution/275_comptime_system_entry", 42, null);
}

test "argi repl evaluates independent System entries" {
    const commands =
        \\first ::= #run (.system: System) -> (.value: Int32) { value = 40 }
        \\second ::= #run (.system: System) -> (.value: Int32) { value = 2 }
        \\first + second
        \\
    ;
    try expectReplFixture(null, commands, "_0 = 42\n");
}

test "argi repl preserves generic System specializations after rejected captures" {
    const commands =
        \\calculate#(.T: Int8, .n = 41)()
        \\captured_local#(.n = 42)()
        \\selected_capture#(.n = 42)(.runtime_value = 7)
        \\bad ::= selected_capture#(.n = 41)(.runtime_value = 7)
        \\default_host#(.n = 42)()
        \\tuple_host#(.n = 41)()
        \\allocate_host#(.n = 42)()
        \\
    ;
    try expectReplFixtureWithDiagnostic("tests/feature_tests/execution/279_generic_comptime_system_entry/main.rg", commands, "_0 = 41\n_1 = 42\n_2 = 42\n_3 = 42\n_4 = 42\n_5 = 42\n", "#run arguments must be compile-time constants");
}

test "argi repl recovers from aborted allocated System evaluations" {
    const commands =
        \\allocate_host#(.n = 41)()
        \\failed ::= abort_host#(.n = 42)()
        \\allocate_host#(.n = 42)()
        \\captured_local#(.n = 42)()
        \\
    ;
    try expectReplFixtureWithDiagnostic("tests/feature_tests/execution/279_generic_comptime_system_entry/main.rg", commands, "_0 = 41\n_1 = 42\n_2 = 42\n", "#run evaluation aborted");
}

test "feature_tests/testing/21_modern_test_syntax" {
    try argiTestExpectStderr(
        "tests/feature_tests/testing/21_modern_test_syntax",
        &.{},
        0,
        "PASS modern\nPASS multiline\nPASS explicit\n",
    );
}

test "argi test runs configured modules and explicit target overrides suite" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmpDirRootPath(&tmp);
    defer std.testing.allocator.free(root);
    const argi = try installedArgiPath();
    defer std.testing.allocator.free(argi);
    for ([_][]const u8{ "first", "second" }) |module| {
        try tmp.dir.createDir(std.testing.io, module, .default_dir);
        const source = try std.fs.path.join(std.testing.allocator, &.{ module, "main.rg" });
        defer std.testing.allocator.free(source);
        try tmp.dir.writeFile(std.testing.io, .{ .sub_path = source, .data = "test same_name := (.system: System) -> !() { testing.expect(.condition = true)! }\n" });
    }
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "argi.toml", .data = "[test]\nmodules = [\n  'first',\n  'second',\n]\n" });
    const suite = try runChildInCwd(&.{ argi, "test", "--filter", "same_name" }, root);
    defer std.testing.allocator.free(suite.stdout);
    defer std.testing.allocator.free(suite.stderr);
    try expectEqual(std.process.Child.Term{ .exited = 0 }, suite.term);
    const repo_root = try repoRootPrefix();
    defer std.testing.allocator.free(repo_root);
    const relative_root = root[repo_root.len + 1 ..];
    const expected = try std.fmt.allocPrint(std.testing.allocator, "PASS {s}/first/same_name\nPASS {s}/second/same_name\n", .{ relative_root, relative_root });
    defer std.testing.allocator.free(expected);
    try expectEqualStrings(expected, suite.stderr);
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "argi.toml", .data = "[test]\nmodules = ['first']\n" });
    const explicit = try runChildInCwd(&.{ argi, "test", "second" }, root);
    defer std.testing.allocator.free(explicit.stdout);
    defer std.testing.allocator.free(explicit.stderr);
    try expectEqual(std.process.Child.Term{ .exited = 0 }, explicit.term);
    const single = try std.fmt.allocPrint(std.testing.allocator, "PASS {s}/second/same_name\n", .{relative_root});
    defer std.testing.allocator.free(single);
    try expectEqualStrings(single, explicit.stderr);
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "argi.toml", .data = "[test]\nmodules = [1]\n" });
    const invalid = try runChildInCwd(&.{ argi, "test" }, root);
    defer std.testing.allocator.free(invalid.stdout);
    defer std.testing.allocator.free(invalid.stderr);
    try expectEqual(std.process.Child.Term{ .exited = 1 }, invalid.term);
    try expect(std.mem.indexOf(u8, invalid.stderr, "configure [test] modules") != null);
}

test "bytecode nominal underlying scalar and aggregate representations" {
    try vmExpect("tests/feature_tests/execution/281_nominal_scalar_representations", 0, null);
    try vmExpect("tests/feature_tests/types/294_annotated_alias_shapes", 0, null);
}

test "argi repl discovers public submodules from retained import aliases" {
    const commands =
        \\root := import("./tests/feature_tests/modules/32_public_submodules/tree")
        \\root.branch.leaf.answer()
        \\root.branch.leaf.identity#(.T: Int32)(42)
        \\:begin
        \\answer := () -> (.value: Int32) { value = root.branch.leaf.answer() }
        \\:end
        \\answer()
        \\:reset
        \\root := import("./tests/feature_tests/modules/32_public_submodules/tree")
        \\root.branch.leaf.answer()
        \\:begin
        \\enabled := () -> (.value: Bool) { value = true }
        \\selected := () -> (.value: Int32) {
        \\    #if enabled() { value = root.branch.leaf.answer() }
        \\    #else { value = 0 }
        \\}
        \\:end
        \\selected()
        \\
    ;
    try expectReplFixture(null, commands, "_0 = 42\n_1 = 42\n_2 = 42\n_0 = 42\n_1 = 42\n");
}

test "argi repl rolls back newly discovered submodules after rejection" {
    const commands =
        \\root := import("./tests/feature_tests/modules/32_public_submodules/tree")
        \\root.branch.leaf.answer() + missing()
        \\root.branch.leaf.answer()
        \\
    ;
    try expectReplFixtureWithDiagnostic(null, commands, "_1 = 42\n", "no function named 'missing' exists");
}

test "argi repl preserves inferred operation participants across rejected submissions" {
    const commands =
        \\first ::= build_cell(42)
        \\number :: UInt8 = 5
        \\bad ::= build_cell(number) + true
        \\first.value
        \\second ::= build_cell(7)
        \\first = second
        \\first.value
        \\third ::= build_cell(number)
        \\third.value
        \\
    ;
    try expectReplFixtureWithDiagnostic("tests/feature_tests/contracts/342_open_operation_inference/main.rg", commands, "_0 = 42\n_1 = 7\n_2 = 5\n", "operator '+' is not defined");
}

test "argi repl preserves bound operation definition values" {
    const commands =
        \\identity := #(.T: Type) (.value: T) -> (.result: T) { result = value }
        \\int_identity := identity#(Int32)
        \\Bound#(.T: Type): Contract = (.bound_value: _)
        \\implement Bound#(Int32) (.bound_value = int_identity)
        \\bound_value(42)
        \\bound_value(7)
        \\
    ;
    try expectReplFixture(null, commands, "_0 = 42\n_1 = 7\n");
}

test "argi repl resolves operation value expressions" {
    const commands =
        \\identity := #(.T: Type) (.value: T) -> (.result: T) { result = value }
        \\Direct#(.T: Type): Contract = (.direct_value: _)
        \\implement Direct#(Int32) (.direct_value = identity#(Int32))
        \\direct_value(42)
        \\Box := #(.T: Type) (.value: T)
        \\make_box := #(.T: Type) (.value: T) -> (.result: Box#(T)) { result = (.value = value) }
        \\BoxInitArgs: Type = #(.T: Type) (.value: T)
        \\
        \\implement#(.T: Type) Init#(Box#(T), BoxInitArgs#(T)) (
        \\    .Result: Type = Box#(T)
        \\.init = make_box#(T))
        \\value ::= Box(7)
        \\value.value
        \\
    ;
    try expectReplFixture(null, commands, "_0 = 42\n_1 = 7\n");
}
