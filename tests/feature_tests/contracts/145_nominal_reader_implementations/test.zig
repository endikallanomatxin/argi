const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/145_nominal_reader_implementations" {
    try expectSuccessfulBuild("tests/feature_tests/contracts/145_nominal_reader_implementations");
    try support.runExpect("tests/feature_tests/contracts/145_nominal_reader_implementations", 0);
}
