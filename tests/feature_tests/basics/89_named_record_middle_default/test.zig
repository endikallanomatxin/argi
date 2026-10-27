const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/basics/89_named_record_middle_default" {
    try expectSuccessfulBuild("tests/feature_tests/basics/89_named_record_middle_default");
    try runExpect("tests/feature_tests/basics/89_named_record_middle_default", 0);
}
