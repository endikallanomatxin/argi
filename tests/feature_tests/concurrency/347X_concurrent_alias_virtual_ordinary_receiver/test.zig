const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "347X_concurrent_alias_virtual_ordinary_receiver" {
    const path = "tests/feature_tests/concurrency/347X_concurrent_alias_virtual_ordinary_receiver";
    try support.expectFrontendFailure(path, "must preserve concurrent reference authority");
}
