const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/46_deinitialized_place_can_be_replaced" {
    try expectSuccessfulBuild("tests/feature_tests/ownership/46_deinitialized_place_can_be_replaced");
    try support.runExpect("tests/feature_tests/ownership/46_deinitialized_place_can_be_replaced", 0);
}
