const std = @import("std");
const build_cmd = @import("build.zig");

pub fn run(args: []const []const u8) !u8 {
    if (args.len == 0) return error.MissingRunTarget;

    try build_cmd.compile(args);

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const module_dir = try build_cmd.resolveBuildModuleDir(allocator, args[0]);
    const output_path = try build_cmd.defaultOutputPathForModuleDir(allocator, module_dir);

    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{output_path},
    });

    return switch (result.term) {
        .Exited => |code| @intCast(code),
        else => error.UnexpectedProcessTermination,
    };
}

test "run command builds and runs a module" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{
        .sub_path = "main.rg",
        .data =
            \\main() -> (.status_code: Int32 = 0) := {
            \\}
            \\
        ,
    });

    const module_dir = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(module_dir);

    const code = try run(&.{module_dir});
    try std.testing.expectEqual(@as(u8, 0), code);
}

test "run command returns executable status code" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{
        .sub_path = "main.rg",
        .data =
            \\main() -> (.status_code: Int32 = 7) := {
            \\}
            \\
        ,
    });

    const module_dir = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(module_dir);

    const code = try run(&.{module_dir});
    try std.testing.expectEqual(@as(u8, 7), code);
}
