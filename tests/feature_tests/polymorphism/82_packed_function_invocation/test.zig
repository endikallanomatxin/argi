const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "packed invocation of a function argument" {
    const path = "tests/feature_tests/polymorphism/82_packed_function_invocation";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
    try support.vmExpect(path, 0, null);
}
