const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .exclusive;

test "packed calls preserve returned borrows and reference effects" {
    const path = "tests/feature_tests/polymorphism/87_packed_reference_effects";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
    try support.vmExpect(path, 0, null);
}
