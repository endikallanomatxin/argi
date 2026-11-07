const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "167_same_type_reference_copy_separation" {
    const path = "tests/feature_tests/concurrency/167_same_type_reference_copy_separation";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
