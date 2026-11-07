const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "types/403X_arena_short_backing_reservation" {
    try support.expectSuccessfulBuild("tests/feature_tests/types/403X_arena_short_backing_reservation");
    try support.runExpectFailure("tests/feature_tests/types/403X_arena_short_backing_reservation");
}
