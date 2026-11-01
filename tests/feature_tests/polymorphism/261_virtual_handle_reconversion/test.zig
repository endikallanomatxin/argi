const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/261_virtual_handle_reconversion" {
    const path = "tests/feature_tests/polymorphism/261_virtual_handle_reconversion";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
    try support.vmExpect(path, 0, null);
}
