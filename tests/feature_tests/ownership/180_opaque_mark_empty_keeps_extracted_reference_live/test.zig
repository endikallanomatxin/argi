const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/180_opaque_mark_empty_keeps_extracted_reference_live" {
    const test_path = "tests/feature_tests/ownership/180_opaque_mark_empty_keeps_extracted_reference_live";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
