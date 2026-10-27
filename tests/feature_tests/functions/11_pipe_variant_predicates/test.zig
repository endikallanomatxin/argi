const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/functions/11_pipe_variant_predicates" {
    const test_path = "tests/feature_tests/functions/11_pipe_variant_predicates";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}
