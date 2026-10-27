const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/execution/205_initial_symbolic_reference_survives_retargeting" {
    try expectSuccessfulBuild("tests/feature_tests/execution/205_initial_symbolic_reference_survives_retargeting");
    try runExpect("tests/feature_tests/execution/205_initial_symbolic_reference_survives_retargeting", 42);
    try vmExpect("tests/feature_tests/execution/205_initial_symbolic_reference_survives_retargeting", 42, null);
}
