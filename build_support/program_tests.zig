const std = @import("std");

/// Assemble discovered tests in one module, so Zig collects their test blocks.
/// Fixture test files may import the shared support module, but other local
/// imports and embedded files need to be added to this generated tree too.
pub fn discover(b: *std.Build) !std.Build.LazyPath {
    const io = b.graph.io;
    const allocator = b.allocator;
    var root = try std.Io.Dir.cwd().openDir(io, b.pathFromRoot("tests/feature_tests"), .{ .iterate = true });
    defer root.close(io);

    var paths: std.ArrayList([]const u8) = .empty;
    var categories = root.iterate();
    while (try categories.next(io)) |category| {
        if (category.kind != .directory) continue;
        var category_dir = try root.openDir(io, category.name, .{ .iterate = true });
        defer category_dir.close(io);
        var cases = category_dir.iterate();
        while (try cases.next(io)) |case| {
            if (case.kind != .directory) continue;
            const relative = try std.fmt.allocPrint(allocator, "{s}/{s}/test.zig", .{ category.name, case.name });
            category_dir.access(io, try std.fmt.allocPrint(allocator, "{s}/test.zig", .{case.name}), .{}) catch |err| switch (err) {
                error.FileNotFound => continue,
                else => return err,
            };
            try paths.append(allocator, relative);
        }
    }
    std.mem.sort([]const u8, paths.items, {}, struct {
        fn lessThan(_: void, lhs: []const u8, rhs: []const u8) bool {
            return std.mem.lessThan(u8, lhs, rhs);
        }
    }.lessThan);

    var prefixes: std.ArrayList([]const u8) = .empty;
    for (paths.items) |path| {
        const prefix = try allocator.dupe(u8, b.fmt("tests.feature_tests.{s}.test.", .{path[0 .. path.len - ".zig".len]}));
        for (prefix) |*byte| if (byte.* == '/') {
            byte.* = '.';
        };
        try prefixes.append(allocator, prefix);
    }
    std.mem.sort([]const u8, prefixes.items, {}, struct {
        fn lessThan(_: void, lhs: []const u8, rhs: []const u8) bool {
            return std.mem.lessThan(u8, lhs, rhs);
        }
    }.lessThan);
    for (prefixes.items[0..], 0..) |prefix, index| {
        if (index == 0) continue;
        const previous = prefixes.items[index - 1];
        if (std.mem.startsWith(u8, prefix, previous)) {
            std.debug.print("ambiguous fixture test prefix: {s} and {s}\n", .{ previous, prefix });
            return error.AmbiguousFixtureTestPrefix;
        }
    }

    const files = b.addWriteFiles();
    _ = files.addCopyFile(b.path("tests/test.zig"), "tests/test.zig");
    _ = files.addCopyFile(b.path("tests/support.zig"), "tests/support.zig");
    var source: std.ArrayList(u8) = .empty;
    try source.appendSlice(allocator,
        \\pub const central = @import("tests/test.zig");
        \\pub const central_prefix = @typeName(central) ++ ".test.";
        \\pub const Group = struct { prefix: []const u8, fixture: []const u8, isolation: @import("tests/support.zig").Isolation };
        \\pub const groups = [_]Group{
        \\
    );
    for (paths.items) |path| {
        const fixture = path[0 .. path.len - "/test.zig".len];
        const import_path = b.fmt("tests/feature_tests/{s}", .{path});
        const fixture_path = b.fmt("tests/feature_tests/{s}", .{fixture});
        _ = files.addCopyFile(b.path(import_path), import_path);
        try source.appendSlice(allocator, b.fmt(
            "    .{{ .prefix = @typeName(@import(\"{f}\")) ++ \".test.\", .fixture = \"{f}\", .isolation = @import(\"{f}\").isolation }},\n",
            .{ std.zig.fmtString(import_path), std.zig.fmtString(fixture_path), std.zig.fmtString(import_path) },
        ));
    }
    try source.appendSlice(allocator,
        \\};
        \\comptime { _ = central; _ = groups; }
        \\
    );
    return files.add("root.zig", source.items);
}
