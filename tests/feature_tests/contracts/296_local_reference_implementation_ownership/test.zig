const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/296_local_reference_implementation_ownership" {
    try expectSuccessfulBuild("tests/feature_tests/contracts/296_local_reference_implementation_ownership");
    try runExpect("tests/feature_tests/contracts/296_local_reference_implementation_ownership", 0);
}
