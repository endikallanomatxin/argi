const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "feature_tests/types/435_nullable_contract_patterns" {
    const path = "tests/feature_tests/types/435_nullable_contract_patterns";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
    try support.vmExpect(path, 0, null);
}
