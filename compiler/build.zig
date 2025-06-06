const std = @import("std");

fn linkLlvm(step: *std.Build.Step.Compile, libs_str: []const u8) void {
    var it = std.mem.tokenizeScalar(u8, libs_str, ' ');
    while (it.next()) |tok| {
        if (std.mem.startsWith(u8, tok, "-l")) {
            step.linkSystemLibrary(tok[2..]);
        }
    }
}

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    if (std.process.getEnvVarOwned(b.allocator, "PATH") catch null) |path| {
        b.graph.env_map.put("PATH", path) catch @panic("OOM");
    }

    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    // Obtain LLVM paths from the installed `llvm-config` tool.  This avoids
    // hard-coding the version and makes the build portable across systems.
    const llvm_config = blk: {
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
            if (b.findProgram(&.{name}, &.{"/usr/bin"}) catch null) |path| break :blk path;
        }
        std.debug.panic("llvm-config not found; please install LLVM dev tools", .{});
    };

    const include_dir_raw = b.run(&.{ llvm_config, "--includedir" });
    const lib_dir_raw = b.run(&.{ llvm_config, "--libdir" });
    const libs_raw = std.mem.trimRight(u8, b.run(&.{ llvm_config, "--libs" }), "\n");

    const llvm_include_path = std.Build.LazyPath{ .cwd_relative = std.mem.trim(u8, include_dir_raw, " \n") };
    const llvm_lib_path = std.Build.LazyPath{ .cwd_relative = std.mem.trim(u8, lib_dir_raw, " \n") };

    const lib = b.addStaticLibrary(.{
        .name = "argi_compiler",
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    lib.addIncludePath(llvm_include_path);
    lib.addLibraryPath(llvm_lib_path);
    linkLlvm(lib, libs_raw);

    // This declares intent for the library to be installed into the standard
    // location when the user invokes the "install" step (the default step when
    // running `zig build`).
    b.installArtifact(lib);

    const exe = b.addExecutable(.{
        .name = "argi_compiler",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.addIncludePath(llvm_include_path);
    exe.addLibraryPath(llvm_lib_path);
    linkLlvm(exe, libs_raw);

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(exe);

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = b.addRunArtifact(exe);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const lib_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
    test_step.dependOn(&run_exe_unit_tests.step);
}
