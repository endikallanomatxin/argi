const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/199_deinit_invocation_forms" {
    try expectSuccessfulBuild("tests/feature_tests/contracts/199_deinit_invocation_forms");
    try run("tests/feature_tests/contracts/199_deinit_invocation_forms");
}
