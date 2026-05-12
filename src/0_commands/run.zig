const std = @import("std");
const build_cmd = @import("build.zig");

fn rejectUnsupportedRunFlags(args: []const []const u8) !void {
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--output")) return error.RunOutputFlagUnsupported;
        if (std.mem.eql(u8, arg, "--emit-llvm")) return error.RunEmitLlvmUnsupported;
        if (std.mem.eql(u8, arg, "--emit-obj")) return error.RunEmitObjectUnsupported;
        if (std.mem.eql(u8, arg, "--just-emit-obj")) return error.RunEmitObjectUnsupported;
    }
}

fn tmpDirPath(tmp: *const std.testing.TmpDir) ![]u8 {
    return std.fs.path.resolve(std.testing.allocator, &.{ ".", ".zig-cache", "tmp", tmp.sub_path[0..] });
}

fn cwdHasManifest(io: std.Io) bool {
    std.Io.Dir.cwd().access(io, "argi.toml", .{}) catch return false;
    return true;
}

pub fn run(
    io: std.Io,
    environ_map: ?*const std.process.Environ.Map,
    args: []const []const u8,
) !u8 {
    try rejectUnsupportedRunFlags(args);

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const in_package = cwdHasManifest(io);
    const selected_executable: ?[]const u8 = if (in_package and args.len > 0 and !std.mem.startsWith(u8, args[0], "--") and !std.mem.eql(u8, args[0], "."))
        args[0]
    else
        null;
    const build_args = if (selected_executable != null) args[1..] else args;
    const parsed = try build_cmd.parseBuildArgs(build_args);

    const plan = if (in_package)
        try build_cmd.resolveRunPlan(allocator, io, selected_executable)
    else
        try build_cmd.resolveBuildPlan(allocator, io, parsed.target_path, parsed.flags);

    var flags = parsed.flags;
    if (plan.executable_name) |name| flags.executable_name = name;

    try build_cmd.compileTarget(parsed.target_path, flags, .{}, io, environ_map);

    const result = try std.process.run(allocator, io, .{
        .argv = &.{plan.output_path},
    });

    return switch (result.term) {
        .exited => |code| @intCast(code),
        else => error.UnexpectedProcessTermination,
    };
}

test "run command rejects output path override" {
    try std.testing.expectError(error.RunOutputFlagUnsupported, run(std.testing.io, null, &.{ "/tmp/module", "--output", "bin/app" }));
}

test "run command builds and runs a module" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "main.rg",
        .data =
        \\main() -> (.status_code: Int32 = 0) := {
        \\}
        \\
        ,
    });

    const module_dir = try tmpDirPath(&tmp);
    defer std.testing.allocator.free(module_dir);

    const code = try run(std.testing.io, null, &.{module_dir});
    try std.testing.expectEqual(@as(u8, 0), code);
}

test "run command returns executable status code" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "main.rg",
        .data =
        \\main() -> (.status_code: Int32 = 7) := {
        \\}
        \\
        ,
    });

    const module_dir = try tmpDirPath(&tmp);
    defer std.testing.allocator.free(module_dir);

    const code = try run(std.testing.io, null, &.{module_dir});
    try std.testing.expectEqual(@as(u8, 7), code);
}
