const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/31_array_of_pointers_is_copyable" {
    const test_path = "tests/feature_tests/ownership/31_array_of_pointers_is_copyable";
    try expectSuccessfulBuild(test_path);
    try run(test_path);
}
