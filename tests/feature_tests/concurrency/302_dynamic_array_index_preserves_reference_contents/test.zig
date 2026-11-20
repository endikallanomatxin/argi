const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "302_dynamic_array_index_preserves_reference_contents" {
    const path = "tests/feature_tests/concurrency/302_dynamic_array_index_preserves_reference_contents";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
