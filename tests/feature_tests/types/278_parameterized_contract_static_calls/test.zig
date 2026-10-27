const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/278_parameterized_contract_static_calls" {
    const path = "tests/feature_tests/types/278_parameterized_contract_static_calls";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
