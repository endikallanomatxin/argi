const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "types/404X_gpa_short_backing_reservation" {
    try support.expectSuccessfulBuild("tests/feature_tests/types/404X_gpa_short_backing_reservation");
    try support.runExpectFailure("tests/feature_tests/types/404X_gpa_short_backing_reservation");
}
