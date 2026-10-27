const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/pointers/06_explicit_pointer_casts" {
    try expectSuccessfulBuild("tests/feature_tests/pointers/06_explicit_pointer_casts");
}
