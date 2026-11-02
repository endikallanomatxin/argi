const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/191_init_owner_cleanup" {
    try expectSuccessfulBuild("tests/feature_tests/contracts/191_init_owner_cleanup");
    try run("tests/feature_tests/contracts/191_init_owner_cleanup");
}
