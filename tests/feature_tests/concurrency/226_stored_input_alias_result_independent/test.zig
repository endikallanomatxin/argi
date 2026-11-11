const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "226_stored_input_alias_result_independent" {
    const path = "tests/feature_tests/concurrency/226_stored_input_alias_result_independent";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
