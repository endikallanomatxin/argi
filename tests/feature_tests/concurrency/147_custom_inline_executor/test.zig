const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 147_custom_inline_executor" {
    const path = "tests/feature_tests/concurrency/147_custom_inline_executor";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
