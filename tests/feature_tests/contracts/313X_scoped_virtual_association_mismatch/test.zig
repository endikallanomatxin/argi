const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/313X_scoped_virtual_association_mismatch" {
    try buildExpectFail("tests/feature_tests/contracts/313X_scoped_virtual_association_mismatch", "incompatible associated elements for the operation interface");
}
