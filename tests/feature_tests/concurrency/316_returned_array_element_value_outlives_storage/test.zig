const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "a returned array element can copy a reference beyond the array lifetime" {
    const path = "tests/feature_tests/concurrency/316_returned_array_element_value_outlives_storage";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
