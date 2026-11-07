const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "types/398_slot_outlives_nonowning_receipt" {
    try support.expectSuccessfulBuild("tests/feature_tests/types/398_slot_outlives_nonowning_receipt");
    try support.runExpect("tests/feature_tests/types/398_slot_outlives_nonowning_receipt", 0);
}
