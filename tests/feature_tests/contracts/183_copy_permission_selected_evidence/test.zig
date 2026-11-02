const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/183_copy_permission_selected_evidence" {
    try expectSuccessfulBuild("tests/feature_tests/contracts/183_copy_permission_selected_evidence");
    try run("tests/feature_tests/contracts/183_copy_permission_selected_evidence");
}
