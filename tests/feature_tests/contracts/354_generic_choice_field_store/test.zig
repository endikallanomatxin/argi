const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/354_generic_choice_field_store" {
    const path = "tests/feature_tests/contracts/354_generic_choice_field_store";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
    try support.vmExpect(path, 0, null);
}
