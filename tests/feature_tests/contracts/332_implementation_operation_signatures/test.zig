const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/contracts/332_implementation_operation_signatures" {
    const path = "tests/feature_tests/contracts/332_implementation_operation_signatures";
    try expectSuccessfulBuild(path);
    try runExpect(path, 42);
    try vmExpect(path, 42, null);
}
