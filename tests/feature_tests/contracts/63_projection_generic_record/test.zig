const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/63_projection_generic_record" {
    const test_path = "tests/feature_tests/contracts/63_projection_generic_record";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}
