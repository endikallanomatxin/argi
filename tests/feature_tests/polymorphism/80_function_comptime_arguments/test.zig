const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .exclusive;

test "function compile-time arguments and defaults" {
    const path = "tests/feature_tests/polymorphism/80_function_comptime_arguments";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
    try support.vmExpect(path, 0, null);
}
