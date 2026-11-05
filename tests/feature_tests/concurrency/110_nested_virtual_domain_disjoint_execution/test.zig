const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 110_nested_virtual_domain_disjoint_execution" {
    const path = "tests/feature_tests/concurrency/110_nested_virtual_domain_disjoint_execution";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
