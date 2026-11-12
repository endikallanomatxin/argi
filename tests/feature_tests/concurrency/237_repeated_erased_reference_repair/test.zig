const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "237_repeated_erased_reference_repair" {
    const path = "tests/feature_tests/concurrency/237_repeated_erased_reference_repair";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
