const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "160_reference_forwarding_preserves_separation" {
    const path = "tests/feature_tests/concurrency/160_reference_forwarding_preserves_separation";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
