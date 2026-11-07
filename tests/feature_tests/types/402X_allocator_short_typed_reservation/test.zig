const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "types/402X_allocator_short_typed_reservation" {
    try support.expectSuccessfulBuild("tests/feature_tests/types/402X_allocator_short_typed_reservation");
    try support.runExpectFailure("tests/feature_tests/types/402X_allocator_short_typed_reservation");
}
