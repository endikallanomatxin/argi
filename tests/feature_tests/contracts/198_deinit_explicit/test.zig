const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/198_deinit_explicit" {
    try expectSuccessfulBuild("tests/feature_tests/contracts/198_deinit_explicit");
    try run("tests/feature_tests/contracts/198_deinit_explicit");
}
