const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/334X_caller_storage_branch_initialization" {
    try buildExpectFail("tests/feature_tests/ownership/334X_caller_storage_branch_initialization", "local storage generation");
}
