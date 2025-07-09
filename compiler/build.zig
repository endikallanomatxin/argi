const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const llvm_include_path, const llvm_lib_path, const llvm_libs_raw = prepareLlvm(b) catch |err| {
        std.debug.print("Error preparing LLVM paths: {s}\n", .{err});
        return;
    };

    //
    // INSTALL EXECUTABLE (default step) --------------------------------------

    const exe = b.addExecutable(.{
        .name = "argi",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.addIncludePath(llvm_include_path);
    exe.addLibraryPath(llvm_lib_path);
    linkLlvm(exe, llvm_libs_raw);

    exe.linkSystemLibrary("c");

    b.installArtifact(exe);

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

    const exe_tests = b.addTest(.{
        .root_source_file = b.path("tests/test.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_exe_tests = b.addRunArtifact(exe_tests);
    run_exe_tests.step.dependOn(b.getInstallStep());

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_tests.step);
    test_step.dependOn(b.getInstallStep());
}

fn prepareLlvm(b: *std.Build) !struct { std.Build.LazyPath, std.Build.LazyPath, []const u8 } {
    if (std.process.getEnvVarOwned(b.allocator, "PATH") catch null) |path| {
        b.graph.env_map.put("PATH", path) catch @panic("OOM");
    }

    // Obtain LLVM paths. First try environment variables to avoid spawning
    // `llvm-config` which might not be supported in restricted environments.
    const env_include = std.process.getEnvVarOwned(b.allocator, "LLVM_INCLUDE_DIR") catch null;
    const env_lib = std.process.getEnvVarOwned(b.allocator, "LLVM_LIB_DIR") catch null;
    const env_libs = std.process.getEnvVarOwned(b.allocator, "LLVM_LIBS") catch null;

    const include_dir_raw: []const u8 = if (env_include) |v| v else blk: {
        // Fallback to using `llvm-config` when environment variables are not provided.
        const llvm_config = blk2: {
            const names = &[_][]const u8{
                "llvm-config",
                "llvm-config-20",
                "llvm-config-19",
                "llvm-config-18",
                "llvm-config-17",
                "llvm-config-16",
                "llvm-config-15",
            };
            for (names) |name| {
                if (b.findProgram(&.{name}, &.{"/usr/bin"}) catch null) |path| break :blk2 path;
            }
            std.debug.panic("llvm-config not found; please install LLVM dev tools", .{});
        };
        break :blk b.run(&.{ llvm_config, "--includedir" });
    };

    const lib_dir_raw: []const u8 = if (env_lib) |v| v else blk: {
        const llvm_config = blk2: {
            const names = &[_][]const u8{
                "llvm-config",
                "llvm-config-20",
                "llvm-config-19",
                "llvm-config-18",
                "llvm-config-17",
                "llvm-config-16",
                "llvm-config-15",
            };
            for (names) |name| {
                if (b.findProgram(&.{name}, &.{"/usr/bin"}) catch null) |path| break :blk2 path;
            }
            std.debug.panic("llvm-config not found; please install LLVM dev tools", .{});
        };
        break :blk b.run(&.{ llvm_config, "--libdir" });
    };

    const llvm_libs_raw: []const u8 = if (env_libs) |v| v else blk: {
        const llvm_config = blk2: {
            const names = &[_][]const u8{
                "llvm-config",
                "llvm-config-20",
                "llvm-config-19",
                "llvm-config-18",
                "llvm-config-17",
                "llvm-config-16",
                "llvm-config-15",
            };
            for (names) |name| {
                if (b.findProgram(&.{name}, &.{"/usr/bin"}) catch null) |path| break :blk2 path;
            }
            std.debug.panic("llvm-config not found; please install LLVM dev tools", .{});
        };
        break :blk std.mem.trimRight(u8, b.run(&.{ llvm_config, "--libs" }), "\n");
    };

    const llvm_include_path = std.Build.LazyPath{ .cwd_relative = std.mem.trim(u8, include_dir_raw, " \n") };
    const llvm_lib_path = std.Build.LazyPath{ .cwd_relative = std.mem.trim(u8, lib_dir_raw, " \n") };

    return .{ llvm_include_path, llvm_lib_path, llvm_libs_raw };
}

fn linkLlvm(step: *std.Build.Step.Compile, libs_str: []const u8) void {
    var it = std.mem.tokenizeScalar(u8, libs_str, ' ');
    while (it.next()) |tok| {
        if (std.mem.startsWith(u8, tok, "-l")) {
            step.linkSystemLibrary(tok[2..]);
        }
    }
}
