const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/223_deinit_collection_reached_capability" {
    try expectSuccessfulBuild("tests/feature_tests/contracts/223_deinit_collection_reached_capability");
    try run("tests/feature_tests/contracts/223_deinit_collection_reached_capability");
}
