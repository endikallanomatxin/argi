const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/151_factory_owner_mutation" {
    try expectSuccessfulBuild("tests/feature_tests/collections/151_factory_owner_mutation");
    try runExpect("tests/feature_tests/collections/151_factory_owner_mutation", 0);
}
