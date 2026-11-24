const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "379_virtual_readonly_descriptor" {
    const path = "tests/feature_tests/concurrency/379_virtual_readonly_descriptor";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
    try support.vmExpect(path, 0, null);
}
