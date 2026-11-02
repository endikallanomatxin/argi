const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/41_raw_pointer_establish_inherit" {
    try expectSuccessfulBuild("tests/feature_tests/ownership/41_raw_pointer_establish_inherit");
    try support.runExpect("tests/feature_tests/ownership/41_raw_pointer_establish_inherit", 0);
}
