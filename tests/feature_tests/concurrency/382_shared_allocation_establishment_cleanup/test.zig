const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "382_shared_allocation_establishment_cleanup" {
    const path = "tests/feature_tests/concurrency/382_shared_allocation_establishment_cleanup";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
