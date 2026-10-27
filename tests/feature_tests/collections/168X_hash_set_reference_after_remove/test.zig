const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/168X_hash_set_reference_after_remove" {
    try buildExpectFail("tests/feature_tests/collections/168X_hash_set_reference_after_remove", "root that has ended");
}
