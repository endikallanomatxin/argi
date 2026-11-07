const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "140_zero_sized_borrow_completion" {
    const path = "tests/feature_tests/concurrency/140_zero_sized_borrow_completion";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
