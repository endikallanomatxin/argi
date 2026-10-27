const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/execution/189_array_owner_reference_initialization" {
    try expectSuccessfulBuild("tests/feature_tests/execution/189_array_owner_reference_initialization");
    try runExpect("tests/feature_tests/execution/189_array_owner_reference_initialization", 42);
    try vmExpect("tests/feature_tests/execution/189_array_owner_reference_initialization", 42, null);
}
