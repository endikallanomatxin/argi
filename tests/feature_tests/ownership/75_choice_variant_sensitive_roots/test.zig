const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/75_choice_variant_sensitive_roots" {
    const test_path = "tests/feature_tests/ownership/75_choice_variant_sensitive_roots";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}
