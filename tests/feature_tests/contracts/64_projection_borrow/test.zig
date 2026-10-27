const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/64_projection_borrow" {
    const test_path = "tests/feature_tests/contracts/64_projection_borrow";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}
