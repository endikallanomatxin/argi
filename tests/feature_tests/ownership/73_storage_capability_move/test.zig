const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/73_storage_capability_move" {
    const test_path = "tests/feature_tests/ownership/73_storage_capability_move";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}
