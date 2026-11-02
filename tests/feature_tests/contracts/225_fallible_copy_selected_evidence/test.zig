const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/225_fallible_copy_selected_evidence" {
    const path = "tests/feature_tests/contracts/225_fallible_copy_selected_evidence";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
