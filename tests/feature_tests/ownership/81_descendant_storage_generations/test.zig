const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/81_descendant_storage_generations" {
    const test_path = "tests/feature_tests/ownership/81_descendant_storage_generations";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}
