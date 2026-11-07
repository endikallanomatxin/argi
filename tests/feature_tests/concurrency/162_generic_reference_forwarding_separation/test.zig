const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "162_generic_reference_forwarding_separation" {
    const path = "tests/feature_tests/concurrency/162_generic_reference_forwarding_separation";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
