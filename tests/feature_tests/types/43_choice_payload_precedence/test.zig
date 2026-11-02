const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/43_choice_payload_precedence" {
    const test_path = "tests/feature_tests/types/43_choice_payload_precedence";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}
