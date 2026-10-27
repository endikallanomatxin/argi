const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/143X_owned_hash_value_after_move" {
    try buildExpectFail("tests/feature_tests/collections/143X_owned_hash_value_after_move", "moved");
}
