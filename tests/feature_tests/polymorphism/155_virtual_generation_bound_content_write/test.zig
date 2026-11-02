const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/155_virtual_generation_bound_content_write" {
    try expectSuccessfulBuild("tests/feature_tests/polymorphism/155_virtual_generation_bound_content_write");
    try runExpect("tests/feature_tests/polymorphism/155_virtual_generation_bound_content_write", 0);
}
