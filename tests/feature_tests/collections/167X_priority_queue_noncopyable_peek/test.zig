const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/167X_priority_queue_noncopyable_peek" {
    try buildExpectFail("tests/feature_tests/collections/167X_priority_queue_noncopyable_peek", "ImplicitlyCopyable");
}
