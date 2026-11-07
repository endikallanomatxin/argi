const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "types/401X_allocator_short_byte_reservation" {
    try support.expectSuccessfulBuild("tests/feature_tests/types/401X_allocator_short_byte_reservation");
    try support.runExpectFailure("tests/feature_tests/types/401X_allocator_short_byte_reservation");
}
