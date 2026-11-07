const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "413_opaque_owning_transfer" {
    const path = "tests/feature_tests/types/413_opaque_owning_transfer";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
