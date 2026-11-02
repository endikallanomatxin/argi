const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/170_struct_field_write_through_live_pointer_wrapper" {
    const test_path = "tests/feature_tests/ownership/170_struct_field_write_through_live_pointer_wrapper";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
