const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/171_iteration_operation_identity" {
    try expectSuccessfulBuild("tests/feature_tests/contracts/171_iteration_operation_identity");
    try run("tests/feature_tests/contracts/171_iteration_operation_identity");
}
