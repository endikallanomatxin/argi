const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/361_opaque_plain_output_caller" {
    try expectSuccessfulBuild("tests/feature_tests/ownership/361_opaque_plain_output_caller");
    try runExpect("tests/feature_tests/ownership/361_opaque_plain_output_caller", 0);
}
