const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "a constant offset selects within every possible typed array" {
    const path = "tests/feature_tests/concurrency/312_conditional_array_offset_loads_all_targets";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
