const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "295_constant_offset_copies_element_lifetime" {
    const path = "tests/feature_tests/concurrency/295_constant_offset_copies_element_lifetime";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
