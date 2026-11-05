const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "C interop 146X_native_contract_ownership" {
    try support.expectFrontendFailure("tests/feature_tests/c_interop/146X_native_contract_ownership", "native access contracts support only reads, writes and no_access");
}
