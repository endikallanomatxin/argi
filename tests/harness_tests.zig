const std = @import("std");
const catalog = @import("fixture_catalog.zig");
const sharding = @import("sharding.zig");

test "expectations reject missing or ignored assertions" {
    try std.testing.expectError(error.RunWithoutBuild, catalog.validateSteps(&.{.{ .kind = .run, .status = 0 }}));
    try std.testing.expectError(error.MissingExitStatus, catalog.validateSteps(&.{.{ .kind = .vm }}));
    try std.testing.expectError(error.MissingRejectionDiagnostic, catalog.validateSteps(&.{.{ .kind = .reject }}));
    try std.testing.expectError(error.UnusedProcessArguments, catalog.validateSteps(&.{.{ .kind = .build, .args = &.{"ignored"} }}));
    try std.testing.expectError(error.UnusedDiagnosticExclusions, catalog.validateSteps(&.{.{ .kind = .vm, .status = 0, .forbidden_stderr = &.{"ignored"} }}));
    try catalog.validateSteps(&.{ .{ .kind = .build }, .{ .kind = .run, .status = 42 }, .{ .kind = .vm, .status = 42 } });
}

test "descriptor schema rejects unknown fields" {
    try std.testing.expectError(error.UnknownField, std.json.parseFromSlice(catalog.Descriptor, std.testing.allocator,
        \\{"version":1,"isolation":"fixture","cases":[],"typo":true}
    , .{}));
}

test "fixture paths cannot escape their case directory" {
    try catalog.validateFixturePath("tests/feature_tests/types/01_example");
    for ([_][]const u8{ "tests/feature_tests/../outside", "tests/feature_tests/types/case/nested", "tests/feature_tests/types/", "tests/feature_tests/types/a\\b" }) |path|
        try std.testing.expectError(error.InvalidFixturePath, catalog.validateFixturePath(path));
}

test "explicit fixture groups stay together on exactly one worker" {
    const entry: catalog.Entry = .{ .name = "first", .fixture = "tests/feature_tests/execution/example", .isolation = .fixture, .custom = false };
    var matches: usize = 0;
    for (0..16) |worker| {
        var buffer: [8]u8 = undefined;
        const shard = try std.fmt.bufPrint(&buffer, "{d}", .{worker});
        const selected = try sharding.selected(entry, shard, 16);
        var second = entry;
        second.name = "second";
        try std.testing.expectEqual(selected, try sharding.selected(second, shard, 16));
        matches += @intFromBool(selected);
        var exclusive = entry;
        exclusive.isolation = .exclusive;
        try std.testing.expect(!try sharding.selected(exclusive, shard, 16));
    }
    try std.testing.expectEqual(@as(usize, 1), matches);
    try std.testing.expect(!try sharding.selected(entry, "serial", 16));
    try std.testing.expect(try sharding.selected(entry, "all", 1));
}

test "runtime filters match fixture and custom names consistently" {
    try std.testing.expect(catalog.matchesFilters("feature_tests/types/example", &.{"types/"}));
    try std.testing.expect(catalog.matchesFilters("custom example", &.{ "absent", "example" }));
    try std.testing.expect(!catalog.matchesFilters("custom example", &.{"types/"}));
    try std.testing.expect(catalog.matchesFilters("anything", &.{}));
}

test "discovery requires declared coverage and ignores nested module mains" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const io = std.testing.io;
    try tmp.dir.createDirPath(io, "tests/feature_tests/types/example/nested");
    try tmp.dir.writeFile(io, .{ .sub_path = "tests/custom_tests.json", .data = "{\"version\":1,\"tests\":[]}" });
    try tmp.dir.writeFile(io, .{ .sub_path = "tests/feature_tests/types/example/main.rg", .data = "main := () -> () {}" });
    try tmp.dir.writeFile(io, .{ .sub_path = "tests/feature_tests/types/example/nested/main.rg", .data = "Nested := ()" });
    const root = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    defer std.testing.allocator.free(root);
    var discovered: catalog.Catalog = undefined;
    try std.testing.expectError(error.MissingFeatureTestCoverage, discovered.init(std.testing.allocator, io, root));
    try tmp.dir.writeFile(io, .{ .sub_path = "tests/feature_tests/types/example/test.json", .data =
        \\{"version":1,"isolation":"fixture","cases":[{"steps":[{"kind":"build"}]}]}
    });
    try discovered.init(std.testing.allocator, io, root);
    defer discovered.deinit();
    try std.testing.expectEqual(@as(usize, 1), discovered.entries.items.len);
    try std.testing.expectEqualStrings("feature_tests/types/example", discovered.entries.items[0].name);
}

test "custom coverage is explicit and descriptor names are unique" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const io = std.testing.io;
    try tmp.dir.createDirPath(io, "tests/feature_tests/types/example");
    try tmp.dir.writeFile(io, .{ .sub_path = "tests/feature_tests/types/example/main.rg", .data = "main := () -> () {}" });
    try tmp.dir.writeFile(io, .{ .sub_path = "tests/custom_tests.json", .data =
        \\{"version":1,"tests":[{"name":"custom.example","isolation":"exclusive","covers":["tests/feature_tests/types/example"]}]}
    });
    const root = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    defer std.testing.allocator.free(root);
    var discovered: catalog.Catalog = undefined;
    {
        try discovered.init(std.testing.allocator, io, root);
        defer discovered.deinit();
        try std.testing.expectEqual(@as(usize, 1), discovered.entries.items.len);
        try std.testing.expectEqualStrings("custom.example", discovered.customName("test.custom.example").?);
        try std.testing.expect(discovered.customName("undeclared") == null);
    }
    try tmp.dir.writeFile(io, .{ .sub_path = "tests/feature_tests/types/example/test.json", .data =
        \\{"version":1,"isolation":"fixture","cases":[{"name":"custom.example","steps":[{"kind":"build"}]}]}
    });
    try std.testing.expectError(error.DuplicateTestName, discovered.init(std.testing.allocator, io, root));
    try tmp.dir.writeFile(io, .{ .sub_path = "tests/feature_tests/types/example/test.json", .data =
        \\{"version":2,"isolation":"fixture","cases":[{"steps":[{"kind":"build"}]}]}
    });
    try std.testing.expectError(error.UnsupportedTestDescriptorVersion, discovered.init(std.testing.allocator, io, root));
}
