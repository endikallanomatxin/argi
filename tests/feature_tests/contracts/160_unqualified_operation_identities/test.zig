const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/160_unqualified_operation_identities" {
    try expectSuccessfulBuild("tests/feature_tests/contracts/160_unqualified_operation_identities");
    try support.runExpect("tests/feature_tests/contracts/160_unqualified_operation_identities", 0);
}
