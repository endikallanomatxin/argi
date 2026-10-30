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
const checkNativeCFixture = test_support.checkNativeCFixture;
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
        \\test installed_prefix := (.system: System, .error_tracer: $&Virtual#(ErrorTracer)) -> !!() {
        \\    assume error_tracer
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
    try expectEqualStrings("argi " ++ @import("program_test_options").compiler_version ++ "\n", result.stderr);
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
        \\    assume error_tracer ::= $&noop_error_tracer
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
    try buildExpectFailWithoutNoise("tests/feature_tests/c_interop/11X_duplicate_exports", "C symbol 'argi_duplicate' has multiple definitions", "failed without a diagnostic");
    try buildExpectFailWithoutNoise("tests/feature_tests/c_interop/12X_reserved_export", "C export symbol 'main' is reserved", "failed without a diagnostic");
}

test "C interop checks lexical and explicit authorization without ABI arguments" {
    try expectSuccessfulBuild("tests/feature_tests/c_interop/13_foreign_capability");
    try run("tests/feature_tests/c_interop/13_foreign_capability");
    try expectSuccessfulBuild("tests/feature_tests/c_interop/22_byte_copy_without_ffi");
    try run("tests/feature_tests/c_interop/22_byte_copy_without_ffi");
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

test "C interop traps null callback invocation" {
    const path = "tests/feature_tests/c_interop/83X_callback_invocation_null";
    try expectSuccessfulBuild(path);
    try runExpectFailure(path);
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
        .{ .data = "duration_ms\n10\ninvalid\n", .diagnostic = "parsing duration" },
        .{ .data = "endpoint,duration_ms\n/health\n", .diagnostic = "TypeError" },
        .{ .data = "duration_ms\n-1\n", .diagnostic = "invalid_duration" },
        .{ .data = "duration_ms\nnan\n", .diagnostic = "parsing duration" },
        .{ .data = "duration_ms\ninf\n", .diagnostic = "parsing duration" },
        .{ .data = "duration_ms\n\xff\n", .diagnostic = "decoding CSV input" },
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
    try expect(std.mem.indexOf(u8, failure.stderr, "read_all_limited") != null);
    try expect(std.mem.indexOf(u8, failure.stderr, "first.txt") != null);

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
    try expect(std.mem.indexOf(u8, invalid_utf8.stderr, "string_from_bytes") != null);
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
        \\Holder := (.counter: Virtual#(Counting))
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
        \\make_array_resource := (.selection: $&UIntNative, .counter: $&Counter, .fail: Bool, .error_tracer: $&Virtual#(ErrorTracer)) -> (.result: Errable#(Resource, (..stop))) {
        \\    assume error_tracer
        \\    selection&= 1
        \\    if fail { result = ..error(.reason = ..stop) } else { result = ..ok Resource(.counter = counter, .value = 9) }
        \\}
        \\replace_array := (.values: $&[2]Resource, .selection: $&UIntNative, .counter: $&Counter, .fail: Bool, .error_tracer: $&Virtual#(ErrorTracer)) -> (.result: Errable#(Int32, (..stop))) {
        \\    assume error_tracer
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
        try tmp.dir.writeFile(std.testing.io, .{ .sub_path = source, .data = "test same_name := (.system: System, .error_tracer: $&Virtual#(ErrorTracer)) -> !!() { assume error_tracer; testing.expect(.condition = true)! }\n" });
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
