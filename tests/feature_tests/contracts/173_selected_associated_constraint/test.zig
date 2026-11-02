const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/173_selected_associated_constraint" {
    try expectSuccessfulBuild("tests/feature_tests/contracts/173_selected_associated_constraint");
    try run("tests/feature_tests/contracts/173_selected_associated_constraint");
}
