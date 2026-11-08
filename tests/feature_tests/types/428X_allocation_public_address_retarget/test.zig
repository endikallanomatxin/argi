const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "428X_allocation_public_address_retarget" {
    const path = "tests/feature_tests/types/428X_allocation_public_address_retarget";
    try support.expectSuccessfulBuild(path);
    try support.runExpectFailure(path);
}
