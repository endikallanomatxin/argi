const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "397_isolated_full_reference_virtual" {
    const path = "tests/feature_tests/concurrency/397_isolated_full_reference_virtual";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
