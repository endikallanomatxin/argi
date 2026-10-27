const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/26_virtual_abstract_dispatch" {
    const test_path = "tests/feature_tests/polymorphism/26_virtual_abstract_dispatch";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}
