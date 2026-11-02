const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/186_contextual_associated_operation_input" {
    try expectSuccessfulBuild("tests/feature_tests/contracts/186_contextual_associated_operation_input");
    try run("tests/feature_tests/contracts/186_contextual_associated_operation_input");
}
