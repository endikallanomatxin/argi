const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "types/406X_allocator_misaligned_reservation" {
    try support.expectSuccessfulBuild("tests/feature_tests/types/406X_allocator_misaligned_reservation");
    try support.runExpectFailure("tests/feature_tests/types/406X_allocator_misaligned_reservation");
}
