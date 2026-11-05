const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 108_nested_virtual_access_reference" {
    const path = "tests/feature_tests/concurrency/108_nested_virtual_access_reference";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
