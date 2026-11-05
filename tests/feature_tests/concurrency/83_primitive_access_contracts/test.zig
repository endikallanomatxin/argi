const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 83_primitive_access_contracts" {
    const path = "tests/feature_tests/concurrency/83_primitive_access_contracts";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
