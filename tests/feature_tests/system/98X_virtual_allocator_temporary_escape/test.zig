const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/system/98X_virtual_allocator_temporary_escape" {
    try support.expectFrontendFailure(
        "tests/feature_tests/system/98X_virtual_allocator_temporary_escape",
        "function output cannot depend on a local storage generation that ends before return",
    );
}
