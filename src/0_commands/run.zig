const std = @import("std");
const build_cmd = @import("build.zig");

fn rejectUnsupportedRunFlags(args: []const []const u8) !void {
    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--output")) return error.RunOutputFlagUnsupported;
        if (std.mem.eql(u8, arg, "--emit-llvm")) return error.RunEmitLlvmUnsupported;
        if (std.mem.eql(u8, arg, "--emit-obj")) return error.RunEmitObjectUnsupported;
        if (std.mem.eql(u8, arg, "--just-emit-obj")) return error.RunEmitObjectUnsupported;
    }
}

fn tmpDirPath(tmp: *const std.testing.TmpDir) ![]u8 {
    return std.fs.path.resolve(std.testing.allocator, &.{ ".", ".zig-cache", "tmp", tmp.sub_path[0..] });
}

pub fn run(
    io: std.Io,
    environ_map: ?*const std.process.Environ.Map,
    args: []const []const u8,
) !u8 {
    if (args.len == 0) return error.MissingRunTarget;
    try rejectUnsupportedRunFlags(args);

    try build_cmd.compile(io, environ_map, args);

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const module_dir = try build_cmd.resolveBuildModuleDir(allocator, io, args[0]);
    const output_path = try build_cmd.defaultOutputPathForModuleDir(allocator, module_dir);

    const result = try std.process.run(allocator, io, .{
        .argv = &.{output_path},
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
