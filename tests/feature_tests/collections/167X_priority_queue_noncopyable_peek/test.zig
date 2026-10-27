const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/167X_priority_queue_noncopyable_peek" {
    try expectFrontendFailure("tests/feature_tests/collections/167X_priority_queue_noncopyable_peek", "ImplicitlyCopyable");
}
