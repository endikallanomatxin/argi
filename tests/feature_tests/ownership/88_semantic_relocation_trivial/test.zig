const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/88_semantic_relocation_trivial" {
    const test_path = "tests/feature_tests/ownership/88_semantic_relocation_trivial";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}
