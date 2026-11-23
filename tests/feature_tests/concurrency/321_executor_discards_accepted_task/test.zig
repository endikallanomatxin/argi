const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "an executor can finish and discard an accepted task before returning an error" {
    const path = "tests/feature_tests/concurrency/321_executor_discards_accepted_task";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
