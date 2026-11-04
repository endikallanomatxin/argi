const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 63_copy_virtual_during_exclusive_loan" {
    const path = "tests/feature_tests/concurrency/63_copy_virtual_during_exclusive_loan";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
