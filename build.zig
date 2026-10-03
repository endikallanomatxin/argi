const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const test_filters = b.option([]const []const u8, "test-filter", "Only run tests whose name contains this text (repeatable)") orelse &.{};
    const test_progress = b.option(bool, "test-progress", "Print each test as it runs") orelse false;
    const frontend_build_options = b.addOptions();
    frontend_build_options.addOption([32]u8, "cache_build_id", compilerFingerprint(b) catch @panic("cannot fingerprint compiler sources"));

    const llvm_include_path, const llvm_lib_path, const llvm_libs_raw = prepareLlvm(b) catch |err| {
        if (err != error.LlvmNotFound) {
            std.debug.print("Error preparing LLVM paths: {s}\n", .{@errorName(err)});
            @panic("failed to prepare LLVM paths");
        }
        @panic("LLVM development files were not found");
    };

    //
    // INSTALL EXECUTABLE (default step) --------------------------------------

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        // Zig 0.16 error tracing can fault while recording handled I/O errors
        // (reproduced in createDirPath when PathAlreadyExists is returned).
        .error_tracing = if (optimize == .Debug) false else null,
    });

    const llvm_c = b.addTranslateC(.{
        .root_source_file = b.path("src/5_codegen/llvm-c.h"),
        .target = target,
        .optimize = optimize,
    });
    llvm_c.addIncludePath(llvm_include_path);
    const llvm_c_mod = llvm_c.createModule();
    exe_mod.addImport("llvm_c", llvm_c_mod);
    exe_mod.addOptions("frontend_build_options", frontend_build_options);

    const exe = b.addExecutable(.{
        .name = "argi",
        .root_module = exe_mod,
    });
    // Binary distributions replace Homebrew library paths with relative load
    // commands. Leave room for longer names before signing the relocated image.
    exe.headerpad_max_install_names = target.result.os.tag == .macos;

    linkLlvmModule(exe_mod, llvm_lib_path, llvm_libs_raw);

    b.installArtifact(exe);
    const core_suffix = std.fs.path.join(b.allocator, &.{ "lib", "argi", "core" }) catch @panic("out of memory");
    const installed_core_path = b.getInstallPath(.prefix, core_suffix);
    if (!std.mem.endsWith(u8, installed_core_path, core_suffix)) {
        @panic("refusing to clean an unexpected core installation path");
    }
    const clean_installed_core = CleanInstalledLibrary.create(b, installed_core_path, "clean installed core");
    const install_core = b.addInstallDirectory(.{
        .source_dir = b.path("core"),
        .install_dir = .prefix,
        .install_subdir = "lib/argi/core",
    });
    install_core.step.dependOn(&clean_installed_core.step);
    b.getInstallStep().dependOn(&install_core.step);

    const more_suffix = std.fs.path.join(b.allocator, &.{ "lib", "argi", "more" }) catch @panic("out of memory");
    const installed_more_path = b.getInstallPath(.prefix, more_suffix);
    if (!std.mem.endsWith(u8, installed_more_path, more_suffix)) {
        @panic("refusing to clean an unexpected more installation path");
    }
    const clean_installed_more = CleanInstalledLibrary.create(b, installed_more_path, "clean installed more");
    const install_more = b.addInstallDirectory(.{
        .source_dir = b.path("more"),
        .install_dir = .prefix,
        .install_subdir = "lib/argi/more",
    });
    install_more.step.dependOn(&clean_installed_more.step);
    b.getInstallStep().dependOn(&install_more.step);

    //
    // INSTALL AND RUN EXECUTABLE ---------------------------------------------

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    //
    // TEST -------------------------------------------------------------------

    const tests_mod = b.createModule(.{
        .root_source_file = b.path("tests/test.zig"),
        .target = target,
        .optimize = optimize,
    });
    tests_mod.addImport("llvm_c", llvm_c_mod);
    linkLlvmModule(tests_mod, llvm_lib_path, llvm_libs_raw);

    const exe_tests = b.addTest(.{
        .root_module = tests_mod,
        .filters = test_filters,
    });
    const run_exe_tests = addTestRun(b, exe_tests, test_progress);
    run_exe_tests.step.dependOn(b.getInstallStep());

    const internal_tests_mod = b.createModule(.{
        .root_source_file = b.path("src/internal_tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    internal_tests_mod.addImport("llvm_c", llvm_c_mod);
    internal_tests_mod.addOptions("frontend_build_options", frontend_build_options);
    linkLlvmModule(internal_tests_mod, llvm_lib_path, llvm_libs_raw);
    const internal_tests = b.addTest(.{
        .root_module = internal_tests_mod,
        .filters = test_filters,
    });
    const run_internal_tests = addTestRun(b, internal_tests, test_progress);

    const internal_test_step = b.step("test-internal", "Run compiler unit tests");
    internal_test_step.dependOn(&run_internal_tests.step);

    const program_test_step = b.step("test-programs", "Run Argi program tests");
    program_test_step.dependOn(&run_exe_tests.step);
    program_test_step.dependOn(b.getInstallStep());

    const benchmark_mod = b.createModule(.{
        .root_source_file = b.path("src/frontend_benchmark.zig"),
        .target = target,
        .optimize = optimize,
        .error_tracing = if (optimize == .Debug) false else null,
    });
    benchmark_mod.addOptions("frontend_build_options", frontend_build_options);
    const benchmark_exe = b.addExecutable(.{ .name = "frontend-benchmark", .root_module = benchmark_mod });
    const benchmark_run = b.addRunArtifact(benchmark_exe);
    if (b.args) |args| benchmark_run.addArgs(args);
    const benchmark_step = b.step("benchmark-frontend", "Measure clean and reused frontend compilations");
    benchmark_step.dependOn(&benchmark_run.step);

    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(internal_test_step);
    test_step.dependOn(program_test_step);
}

fn addTestRun(b: *std.Build, tests: *std.Build.Step.Compile, progress: bool) *std.Build.Step.Run {
    if (!progress) return b.addRunArtifact(tests);
    // Terminal mode reports the active case even when a test never returns.
    // It retains the standard test runner's failure exit status.
    const run = std.Build.Step.Run.create(b, "run tests with progress");
    run.producer = tests;
    run.addArtifactArg(tests);
    run.stdio = .inherit;
    return run;
}

// Library installation must discard removed source files before copying the
// current bundle. Use the build runner's I/O rather than a host shell utility.
const CleanInstalledLibrary = struct {
    step: std.Build.Step,
    path: []const u8,

    fn create(b: *std.Build, path: []const u8, name: []const u8) *CleanInstalledLibrary {
        const clean = b.allocator.create(CleanInstalledLibrary) catch @panic("OOM");
        clean.* = .{
            .step = std.Build.Step.init(.{
                .id = .custom,
                .name = name,
                .owner = b,
                .makeFn = make,
            }),
            .path = b.dupe(path),
        };
        return clean;
    }

    fn make(step: *std.Build.Step, options: std.Build.Step.MakeOptions) !void {
        _ = options;
        const clean: *CleanInstalledLibrary = @fieldParentPtr("step", step);
        try std.Io.Dir.cwd().deleteTree(step.owner.graph.io, clean.path);
    }
};

fn prepareLlvm(b: *std.Build) !struct { std.Build.LazyPath, std.Build.LazyPath, []const u8 } {
    const env_include = b.graph.environ_map.get("LLVM_INCLUDE_DIR");
    const env_lib = b.graph.environ_map.get("LLVM_LIB_DIR");
    const env_libs = b.graph.environ_map.get("LLVM_LIBS");
    const tried_llvm_configs = llvmConfigCandidates();
    const llvm_config_path = findLlvmConfig(b, tried_llvm_configs);

    const include_dir_raw: []const u8 = if (env_include) |v| v else blk: {
        const llvm_config = llvm_config_path orelse {
            printMissingLlvmHelp(tried_llvm_configs);
            return error.LlvmNotFound;
        };
        break :blk b.run(&.{ llvm_config, "--includedir" });
    };

    const lib_dir_raw: []const u8 = if (env_lib) |v| v else blk: {
        const llvm_config = llvm_config_path orelse {
            printMissingLlvmHelp(tried_llvm_configs);
            return error.LlvmNotFound;
        };
        break :blk b.run(&.{ llvm_config, "--libdir" });
    };

    const llvm_libs_raw: []const u8 = if (env_libs) |v| v else blk: {
        const llvm_config = llvm_config_path orelse {
            printMissingLlvmHelp(tried_llvm_configs);
            return error.LlvmNotFound;
        };
        break :blk std.mem.trim(u8, b.run(&.{ llvm_config, "--libs", "--system-libs" }), " \r\n\t");
    };

    const llvm_include_path = std.Build.LazyPath{ .cwd_relative = std.mem.trim(u8, include_dir_raw, " \r\n\t") };
    const llvm_lib_path = std.Build.LazyPath{ .cwd_relative = std.mem.trim(u8, lib_dir_raw, " \r\n\t") };

    return .{ llvm_include_path, llvm_lib_path, llvm_libs_raw };
}

const llvm_config_candidates = [_][]const u8{
    "llvm-config-21",
    "llvm-config.exe",
    "llvm-config",
    "llvm-config-20",
    "llvm-config-19",
    "llvm-config-18",
    "llvm-config-17",
    "llvm-config-16",
    "llvm-config-15",
};

fn llvmConfigCandidates() []const []const u8 {
    return &llvm_config_candidates;
}

fn findLlvmConfig(b: *std.Build, names: []const []const u8) ?[]const u8 {
    for (names) |name| {
        if (b.findProgram(&.{name}, &.{"/usr/bin"}) catch null) |path| return path;
    }
    return null;
}

fn printMissingLlvmHelp(tried: []const []const u8) void {
    std.debug.print("LLVM development files were not found.\n", .{});
    std.debug.print("Install LLVM development tools, including llvm-config, or set:\n", .{});
    std.debug.print("  LLVM_INCLUDE_DIR=/path/to/llvm/include\n", .{});
    std.debug.print("  LLVM_LIB_DIR=/path/to/llvm/lib\n", .{});
    std.debug.print("  LLVM_LIBS=\"-lLLVM...\"\n", .{});
    std.debug.print("\nTried:\n", .{});
    for (tried) |name| {
        std.debug.print("  {s}\n", .{name});
    }
}

fn linkLlvmModule(module: *std.Build.Module, lib_path: std.Build.LazyPath, libs_str: []const u8) void {
    module.addLibraryPath(lib_path);
    module.linkSystemLibrary("c", .{});
    linkLlvm(module, libs_str);
}

fn linkLlvm(module: *std.Build.Module, libs_str: []const u8) void {
    // llvm-config uses -l names on Unix and .lib names on Windows. Explicit
    // LLVM_LIBS accepts either form; preserve system dependencies for static
    // LLVM installations as well as monolithic shared builds.
    var it = std.mem.tokenizeAny(u8, libs_str, " \r\n\t");
    while (it.next()) |tok| {
        if (std.mem.startsWith(u8, tok, "-l")) {
            module.linkSystemLibrary(tok[2..], .{});
        } else if (std.mem.endsWith(u8, tok, ".lib")) {
            if (std.fs.path.isAbsolute(tok)) {
                module.addObjectFile(.{ .cwd_relative = tok });
            } else {
                module.linkSystemLibrary(tok[0 .. tok.len - 4], .{});
            }
        }
    }
}

// Persistent modules must not survive a compiler/schema change even when the
// public language version is unchanged during development. Use relative source
// paths and content, not mtimes or the checkout location, for the build identity.
fn compilerFingerprint(b: *std.Build) ![32]u8 {
    const io = b.graph.io;
    var dir = try std.Io.Dir.cwd().openDir(io, b.pathFromRoot("src"), .{ .iterate = true });
    defer dir.close(io);
    var walker = try dir.walk(b.allocator);
    defer walker.deinit();
    var paths: std.ArrayList([]const u8) = .empty;
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.path, ".zig") and !std.mem.endsWith(u8, entry.path, ".rg")) continue;
        try paths.append(b.allocator, try b.allocator.dupe(u8, entry.path));
    }
    std.mem.sort([]const u8, paths.items, {}, struct {
        fn lessThan(_: void, lhs: []const u8, rhs: []const u8) bool {
            return std.mem.lessThan(u8, lhs, rhs);
        }
    }.lessThan);
    var hash = std.crypto.hash.Blake3.init(.{});
    for (paths.items) |path| {
        const contents = try dir.readFileAlloc(io, path, b.allocator, .limited(16 * 1024 * 1024));
        const length: u64 = @intCast(path.len);
        hash.update(std.mem.asBytes(&length));
        hash.update(path);
        const content_length: u64 = @intCast(contents.len);
        hash.update(std.mem.asBytes(&content_length));
        hash.update(contents);
    }
    var fingerprint: [32]u8 = undefined;
    hash.final(&fingerprint);
    return fingerprint;
}
