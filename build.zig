const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

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
    });

    const llvm_c = b.addTranslateC(.{
        .root_source_file = b.path("src/5_codegen/llvm-c.h"),
        .target = target,
        .optimize = optimize,
    });
    llvm_c.addIncludePath(llvm_include_path);
    const llvm_c_mod = llvm_c.createModule();
    exe_mod.addImport("llvm_c", llvm_c_mod);

    const exe = b.addExecutable(.{
        .name = "argi",
        .root_module = exe_mod,
    });

    linkLlvmModule(exe_mod, llvm_lib_path, llvm_libs_raw);

    b.installArtifact(exe);
    b.installDirectory(.{
        .source_dir = b.path("core"),
        .install_dir = .prefix,
        .install_subdir = "lib/argi/core",
    });

    //
    // INSTALL AND RUN EXECUTABLE ---------------------------------------------

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    // Allow argument passing: `zig build run -- arg1 arg2 etc`
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
    });
    const run_exe_tests = b.addRunArtifact(exe_tests);
    run_exe_tests.step.dependOn(b.getInstallStep());

    const internal_tests_mod = b.createModule(.{
        .root_source_file = b.path("src/internal_tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    internal_tests_mod.addImport("llvm_c", llvm_c_mod);
    linkLlvmModule(internal_tests_mod, llvm_lib_path, llvm_libs_raw);
    const internal_tests = b.addTest(.{
        .root_module = internal_tests_mod,
    });
    const run_internal_tests = b.addRunArtifact(internal_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_tests.step);
    test_step.dependOn(&run_internal_tests.step);
    test_step.dependOn(b.getInstallStep());
}

fn prepareLlvm(b: *std.Build) !struct { std.Build.LazyPath, std.Build.LazyPath, []const u8 } {
    // Obtain LLVM paths. First try environment variables to avoid spawning
    // `llvm-config` which might not be supported in restricted environments.
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
        break :blk std.mem.trim(u8, b.run(&.{ llvm_config, "--libs" }), "\n");
    };

    const llvm_include_path = std.Build.LazyPath{ .cwd_relative = std.mem.trim(u8, include_dir_raw, " \n") };
    const llvm_lib_path = std.Build.LazyPath{ .cwd_relative = std.mem.trim(u8, lib_dir_raw, " \n") };

    return .{ llvm_include_path, llvm_lib_path, llvm_libs_raw };
}

const llvm_config_candidates = [_][]const u8{
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
    var it = std.mem.tokenizeScalar(u8, libs_str, ' ');
    while (it.next()) |tok| {
        if (std.mem.startsWith(u8, tok, "-l")) {
            module.linkSystemLibrary(tok[2..], .{});
        }
    }
}
