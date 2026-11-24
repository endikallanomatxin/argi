const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "383_zeroed_heap_acquisition" {
    const path = "tests/feature_tests/concurrency/383_zeroed_heap_acquisition";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
