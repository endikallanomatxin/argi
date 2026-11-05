const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 121_heterogeneous_virtual_common_contract" {
    try support.expectSuccessfulBuild("tests/feature_tests/concurrency/121_heterogeneous_virtual_common_contract");
    try support.runExpect("tests/feature_tests/concurrency/121_heterogeneous_virtual_common_contract", 0);
}
