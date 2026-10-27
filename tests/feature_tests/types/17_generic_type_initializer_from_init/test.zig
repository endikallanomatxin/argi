const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/17_generic_type_initializer_from_init" {
    const test_path = "tests/feature_tests/types/17_generic_type_initializer_from_init";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}
