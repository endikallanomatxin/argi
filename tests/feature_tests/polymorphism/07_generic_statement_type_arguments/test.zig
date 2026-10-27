const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/07_generic_statement_type_arguments" {
    const test_path = "tests/feature_tests/polymorphism/07_generic_statement_type_arguments";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}
