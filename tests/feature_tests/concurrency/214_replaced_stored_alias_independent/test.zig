const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "214_replaced_stored_alias_independent" {
    const path = "tests/feature_tests/concurrency/214_replaced_stored_alias_independent";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
