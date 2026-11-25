const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "439_reference_observation_through_choice" {
    const path = "tests/feature_tests/concurrency/439_reference_observation_through_choice";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
