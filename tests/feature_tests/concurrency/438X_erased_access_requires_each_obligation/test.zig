const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "438X_erased_access_requires_each_obligation" {
    try support.expectFrontendFailure(
        "tests/feature_tests/concurrency/438X_erased_access_requires_each_obligation",
        "virtual operation has unknown memory effects while storage is concurrently shared",
    );
}
