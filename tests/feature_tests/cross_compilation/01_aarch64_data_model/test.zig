const std = @import("std");
const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/cross_compilation/01_aarch64_data_model" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try support.tmpDirRootPath(&tmp);
    defer allocator.free(root);
    const object_path = try std.fs.path.join(allocator, &.{ root, "arm64.o" });
    defer allocator.free(object_path);
    const fixture = "tests/feature_tests/cross_compilation/01_aarch64_data_model";
    // The second process exercises durable ModuleSG reuse for this target.
    for (0..2) |_| try support.expectArgiBuildSuccess(&.{ "build", fixture, "--target", "aarch64-linux-gnu", "--just-emit-obj", object_path });
    const object = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, object_path, allocator, .limited(1024 * 1024));
    defer allocator.free(object);
    try std.testing.expectEqualStrings("\x7fELF", object[0..4]);
    try std.testing.expectEqual(@as(u16, 183), std.mem.readInt(u16, object[18..20], .little));
    // The same sources cannot reuse ARM64's unsigned CChar decision on x86_64.
    const other = try support.runArgiCommand(&.{ "build", fixture, "--target", "x86_64-linux-gnu", "--just-emit-obj", object_path });
    defer allocator.free(other.stdout);
    defer allocator.free(other.stderr);
    try std.testing.expectEqual(std.process.Child.Term{ .exited = 1 }, other.term);
    try std.testing.expect(std.mem.indexOf(u8, other.stderr, "255") != null);
}
