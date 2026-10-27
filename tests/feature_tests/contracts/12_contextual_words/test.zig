const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/12_contextual_words" {
    const test_path = "tests/feature_tests/contracts/12_contextual_words";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}
