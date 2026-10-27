const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/156_fresh_opaque_extraction_after_refresh" {
    const test_path = "tests/feature_tests/ownership/156_fresh_opaque_extraction_after_refresh";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
