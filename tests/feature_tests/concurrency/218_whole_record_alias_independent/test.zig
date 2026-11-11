const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "218_whole_record_alias_independent" {
    const path = "tests/feature_tests/concurrency/218_whole_record_alias_independent";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
