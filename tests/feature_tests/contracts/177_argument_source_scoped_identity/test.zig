const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/177_argument_source_scoped_identity" {
    try expectSuccessfulBuild("tests/feature_tests/contracts/177_argument_source_scoped_identity");
    try run("tests/feature_tests/contracts/177_argument_source_scoped_identity");
}
