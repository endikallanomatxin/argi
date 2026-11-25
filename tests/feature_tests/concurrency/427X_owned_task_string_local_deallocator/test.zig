const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "427X_owned_task_string_local_deallocator" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/427X_owned_task_string_local_deallocator", "an address is not proved to refer to backing owned by the value");
}
