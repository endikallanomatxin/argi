const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "feature_tests/types/434_choice_keyword_names" {
    const path = "tests/feature_tests/types/434_choice_keyword_names";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
    try support.vmExpect(path, 0, null);
}
