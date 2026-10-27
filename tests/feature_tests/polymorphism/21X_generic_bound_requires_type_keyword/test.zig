const support = @import("../../../support.zig");
const buildExpectFailExact = support.buildExpectFailExact;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/21X_generic_bound_requires_type_keyword" {
    try buildExpectFailExact("tests/feature_tests/polymorphism/21X_generic_bound_requires_type_keyword",
        \\tests/feature_tests/polymorphism/21X_generic_bound_requires_type_keyword/main.rg:3:19: error: generic parameter bounds use '.t: Type: Constraint'
        \\  foo := #(.t: Int32: ExampleAbstract ) (.value: Int32) -> (.result: Int32) {
        \\                    ^
        \\
    );
}
