const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "plain data type query" {
    const path = "tests/feature_tests/types/355_plain_data_query";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
    try support.vmExpect(path, 0, null);
}
