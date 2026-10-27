const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/334X_caller_storage_branch_initialization" {
    try expectFrontendFailure("tests/feature_tests/ownership/334X_caller_storage_branch_initialization", "local storage generation");
}
