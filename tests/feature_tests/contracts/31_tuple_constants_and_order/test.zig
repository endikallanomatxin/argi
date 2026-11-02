const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/31_tuple_constants_and_order" {
    const test_path = "tests/feature_tests/contracts/31_tuple_constants_and_order";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}
