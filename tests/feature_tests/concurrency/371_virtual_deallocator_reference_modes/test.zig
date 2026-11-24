const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "371_virtual_deallocator_reference_modes" {
    const path = "tests/feature_tests/concurrency/371_virtual_deallocator_reference_modes";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
