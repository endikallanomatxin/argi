const support = @import("../../../support.zig");
const buildExpectFailExact = support.buildExpectFailExact;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/basics/21X_c_enum_payload" {
    try buildExpectFailExact("tests/feature_tests/basics/21X_c_enum_payload",
        \\tests/feature_tests/basics/21X_c_enum_payload/main.rg:3:7: error: CEnum variant '..exists' cannot carry a payload
        \\      ..exists(.code: Int32)
        \\        ^
        \\
    );
}
