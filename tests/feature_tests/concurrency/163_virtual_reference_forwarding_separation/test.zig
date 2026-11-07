const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "163_virtual_reference_forwarding_separation" {
    const path = "tests/feature_tests/concurrency/163_virtual_reference_forwarding_separation";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
