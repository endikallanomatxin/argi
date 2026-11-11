const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "224_dynamic_alias_result_independent" {
    const path = "tests/feature_tests/concurrency/224_dynamic_alias_result_independent";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
