const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "types/408X_allocator_inflated_usable_grant" {
    try support.expectSuccessfulBuild("tests/feature_tests/types/408X_allocator_inflated_usable_grant");
    try support.runExpectFailure("tests/feature_tests/types/408X_allocator_inflated_usable_grant");
}
