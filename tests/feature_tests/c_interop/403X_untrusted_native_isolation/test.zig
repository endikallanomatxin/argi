const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "403X_untrusted_native_isolation" {
    try support.expectFrontendFailure("tests/feature_tests/c_interop/403X_untrusted_native_isolation", "native isolated() requires a private bundled-core C import");
}
