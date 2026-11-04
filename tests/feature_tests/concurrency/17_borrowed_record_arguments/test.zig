const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 17_borrowed_record_arguments" {
    const path = "tests/feature_tests/concurrency/17_borrowed_record_arguments";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
