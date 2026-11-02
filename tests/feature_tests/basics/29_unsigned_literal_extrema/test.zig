const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "tests/feature_tests/basics/29_unsigned_literal_extrema" {
    try expectSuccessfulBuild("tests/feature_tests/basics/29_unsigned_literal_extrema");
    try runExpect("tests/feature_tests/basics/29_unsigned_literal_extrema", 0);
}
