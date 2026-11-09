const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "204_reference_retargeted_local_alias_independent" {
    const path = "tests/feature_tests/concurrency/204_reference_retargeted_local_alias_independent";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
