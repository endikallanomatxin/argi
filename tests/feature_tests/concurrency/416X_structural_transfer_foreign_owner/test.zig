const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "416X_structural_transfer_foreign_owner" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/416X_structural_transfer_foreign_owner", "StructurallyTransferable requires a nominal value type defined by the implementing module");
}
