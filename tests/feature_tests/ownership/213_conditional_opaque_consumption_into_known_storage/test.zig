const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/213_conditional_opaque_consumption_into_known_storage" {
    const test_path = "tests/feature_tests/ownership/213_conditional_opaque_consumption_into_known_storage";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
