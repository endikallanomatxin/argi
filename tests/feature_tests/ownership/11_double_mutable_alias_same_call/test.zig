const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/11_double_mutable_alias_same_call" {
    const path = "tests/feature_tests/ownership/11_double_mutable_alias_same_call";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 42);
    try support.vmExpect(path, 42, null);
}
