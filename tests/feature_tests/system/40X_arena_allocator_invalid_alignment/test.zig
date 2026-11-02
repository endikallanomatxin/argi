const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpectFailure = support.runExpectFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/system/40X_arena_allocator_invalid_alignment" {
    const test_path = "tests/feature_tests/system/40X_arena_allocator_invalid_alignment";
    try expectSuccessfulBuild(test_path);
    try runExpectFailure(test_path);
}
