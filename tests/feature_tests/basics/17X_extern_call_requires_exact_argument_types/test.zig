const support = @import("../../../support.zig");
const buildExpectFailExact = support.buildExpectFailExact;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/basics/17X_extern_call_requires_exact_argument_types" {
    try buildExpectFailExact("tests/feature_tests/basics/17X_extern_call_requires_exact_argument_types",
        \\tests/feature_tests/basics/17X_extern_call_requires_exact_argument_types/main.rg:4:12: error: no function named 'putchar' accepts arguments (.character: UInt16). Available signatures:
        \\  - putchar (.character: UInt8, .ffi: $&ForeignFunctionInterface) -> ()
        \\      putchar(.character = value)
        \\             ^
        \\
    );
}
