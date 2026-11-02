const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/types/313_generic_contract_operation" {
    const path = "tests/feature_tests/types/313_generic_contract_operation";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
    try vmExpect(path, 0, null);
}
