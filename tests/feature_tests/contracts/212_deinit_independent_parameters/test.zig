const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/212_deinit_independent_parameters" {
    try expectSuccessfulBuild("tests/feature_tests/contracts/212_deinit_independent_parameters");
    try run("tests/feature_tests/contracts/212_deinit_independent_parameters");
}
