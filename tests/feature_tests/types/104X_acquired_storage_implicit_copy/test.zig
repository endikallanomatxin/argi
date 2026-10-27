const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/104X_acquired_storage_implicit_copy" {
    try buildExpectFail("tests/feature_tests/types/104X_acquired_storage_implicit_copy", "type 'AcquiredStorage' cannot be copied implicitly");
}
