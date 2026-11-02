const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/259_string_add_static_allocator" {
    try expectSuccessfulBuild("tests/feature_tests/contracts/259_string_add_static_allocator");
    try runExpect("tests/feature_tests/contracts/259_string_add_static_allocator", 0);
}
