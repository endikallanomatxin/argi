const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/text/01_string_bytes" {
    const test_path = "tests/feature_tests/text/01_string_bytes";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}
