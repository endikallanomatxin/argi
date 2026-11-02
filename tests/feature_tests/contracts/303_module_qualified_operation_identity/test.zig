const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/303_module_qualified_operation_identity" {
    try expectSuccessfulBuild("tests/feature_tests/contracts/303_module_qualified_operation_identity");
    try runExpect("tests/feature_tests/contracts/303_module_qualified_operation_identity", 0);
}
