const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/system/99_dynamic_array_virtual_adapter" {
    const path = "tests/feature_tests/system/99_dynamic_array_virtual_adapter";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
