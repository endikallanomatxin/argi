const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/261X_virtual_handle_reconversion_receiver_ended" {
    try support.expectFrontendFailure(
        "tests/feature_tests/polymorphism/261X_virtual_handle_reconversion_receiver_ended",
        "reference depends on a root that has ended",
    );
}
