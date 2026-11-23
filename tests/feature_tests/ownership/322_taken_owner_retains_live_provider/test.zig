const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "taken owner retains its live provider" {
    const path = "tests/feature_tests/ownership/322_taken_owner_retains_live_provider";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
