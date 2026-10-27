const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/52_projection_named_participants" {
    const test_path = "tests/feature_tests/contracts/52_projection_named_participants";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}
