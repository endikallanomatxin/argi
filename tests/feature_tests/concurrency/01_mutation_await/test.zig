const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 01_mutation_await" {
    const path = "tests/feature_tests/concurrency/01_mutation_await";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
