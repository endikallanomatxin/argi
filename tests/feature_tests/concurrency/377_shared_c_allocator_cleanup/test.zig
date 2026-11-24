const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "377_shared_c_allocator_cleanup" {
    const path = "tests/feature_tests/concurrency/377_shared_c_allocator_cleanup";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
