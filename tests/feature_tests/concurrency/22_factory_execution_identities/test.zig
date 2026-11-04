const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 22_factory_execution_identities" {
    const path = "tests/feature_tests/concurrency/22_factory_execution_identities";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
