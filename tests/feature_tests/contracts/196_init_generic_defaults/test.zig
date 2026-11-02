const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/196_init_generic_defaults" {
    try expectSuccessfulBuild("tests/feature_tests/contracts/196_init_generic_defaults");
    try run("tests/feature_tests/contracts/196_init_generic_defaults");
}
