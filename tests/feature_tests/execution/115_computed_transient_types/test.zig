const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/execution/115_computed_transient_types" {
    try expectSuccessfulBuild("tests/feature_tests/execution/115_computed_transient_types");
    try runExpect("tests/feature_tests/execution/115_computed_transient_types", 42);
    try vmExpect("tests/feature_tests/execution/115_computed_transient_types", 42, null);
}
