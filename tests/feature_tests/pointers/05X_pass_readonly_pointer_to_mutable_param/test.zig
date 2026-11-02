const support = @import("../../../support.zig");
const buildExpectFailExact = support.buildExpectFailExact;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/pointers/05X_pass_readonly_pointer_to_mutable_param" {
    try buildExpectFailExact("tests/feature_tests/pointers/05X_pass_readonly_pointer_to_mutable_param",
        \\tests/feature_tests/pointers/05X_pass_readonly_pointer_to_mutable_param/main.rg:9:14: error: no function named 'increment' accepts arguments (.ptr: &Int32). Available signatures:
        \\  - increment (.ptr: $&Int32) -> ()
        \\      increment(.ptr = reader)
        \\               ^
        \\
    );
}
