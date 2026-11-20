const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "290_constant_array_projection_disjoint_loan" {
    const path = "tests/feature_tests/concurrency/290_constant_array_projection_disjoint_loan";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
