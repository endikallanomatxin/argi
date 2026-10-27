const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/05_choice_variant_predicate" {
    const test_path = "tests/feature_tests/types/05_choice_variant_predicate";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}
