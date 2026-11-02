const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/25_choice_options_open_choices" {
    const test_path = "tests/feature_tests/types/25_choice_options_open_choices";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}
