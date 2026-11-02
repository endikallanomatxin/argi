const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/41_nullable_sugar" {
    const test_path = "tests/feature_tests/types/41_nullable_sugar";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}
