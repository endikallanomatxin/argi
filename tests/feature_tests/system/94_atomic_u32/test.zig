const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/system/94_atomic_u32" {
    try expectSuccessfulBuild("tests/feature_tests/system/94_atomic_u32");
    try runExpect("tests/feature_tests/system/94_atomic_u32", 0);
}
