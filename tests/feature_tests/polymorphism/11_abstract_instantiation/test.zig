const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/11_abstract_instantiation" {
    const test_path = "tests/feature_tests/polymorphism/11_abstract_instantiation";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}
