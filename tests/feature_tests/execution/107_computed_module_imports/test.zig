const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/107_computed_module_imports" {
    try expectSuccessfulBuild("tests/feature_tests/execution/107_computed_module_imports");
    try runExpect("tests/feature_tests/execution/107_computed_module_imports", 42);
    try vmExpect("tests/feature_tests/execution/107_computed_module_imports", 42, null);
}
