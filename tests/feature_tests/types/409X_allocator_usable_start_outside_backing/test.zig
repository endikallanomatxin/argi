const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "types/409X_allocator_usable_start_outside_backing" {
    try support.expectSuccessfulBuild("tests/feature_tests/types/409X_allocator_usable_start_outside_backing");
    try support.runExpectFailure("tests/feature_tests/types/409X_allocator_usable_start_outside_backing");
}
