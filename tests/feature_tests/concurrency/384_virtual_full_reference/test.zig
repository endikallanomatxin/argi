const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "384_virtual_full_reference" {
    const path = "tests/feature_tests/concurrency/384_virtual_full_reference";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
    try support.vmExpect(path, 0, null);
}
