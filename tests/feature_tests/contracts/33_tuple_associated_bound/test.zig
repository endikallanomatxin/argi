const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/33_tuple_associated_bound" {
    const test_path = "tests/feature_tests/contracts/33_tuple_associated_bound";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}
