const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .exclusive;

test "prepared function inputs and results" {
    const path = "tests/feature_tests/polymorphism/83_prepared_function_arguments";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
    try support.vmExpect(path, 0, null);
}
