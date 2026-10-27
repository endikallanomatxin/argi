const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/154_precise_pointer_assignment_reinitializes_dead_place" {
    const test_path = "tests/feature_tests/ownership/154_precise_pointer_assignment_reinitializes_dead_place";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
