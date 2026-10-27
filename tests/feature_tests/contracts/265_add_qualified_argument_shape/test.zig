const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/265_add_qualified_argument_shape" {
    try expectSuccessfulBuild("tests/feature_tests/contracts/265_add_qualified_argument_shape");
    try runExpect("tests/feature_tests/contracts/265_add_qualified_argument_shape", 0);
}
