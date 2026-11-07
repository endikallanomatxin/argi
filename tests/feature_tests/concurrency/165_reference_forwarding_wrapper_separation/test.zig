const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "165_reference_forwarding_wrapper_separation" {
    const path = "tests/feature_tests/concurrency/165_reference_forwarding_wrapper_separation";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
