const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 144_inline_execution" {
    const path = "tests/feature_tests/concurrency/144_inline_execution";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
