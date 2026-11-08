const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "171_sequential_derived_reference_aliases" {
    const path = "tests/feature_tests/concurrency/171_sequential_derived_reference_aliases";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
