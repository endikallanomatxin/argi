const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/41_choice_scalar_payload" {
    const test_path = "tests/feature_tests/types/41_choice_scalar_payload";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}
