const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "executor wrappers forward sealed requests through monomorphic dispatch" {
    const path = "tests/feature_tests/system/114_forwarding_executor";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
