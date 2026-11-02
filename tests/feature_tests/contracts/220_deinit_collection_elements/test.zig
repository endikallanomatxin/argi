const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/220_deinit_collection_elements" {
    try expectSuccessfulBuild("tests/feature_tests/contracts/220_deinit_collection_elements");
    try run("tests/feature_tests/contracts/220_deinit_collection_elements");
}
