const support = @import("../../../support.zig");
const buildExpectFailExact = support.buildExpectFailExact;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/pointers/08X_array_index_requires_uint_native" {
    try buildExpectFailExact("tests/feature_tests/pointers/08X_array_index_requires_uint_native",
        \\tests/feature_tests/pointers/08X_array_index_requires_uint_native/main.rg:4:23: error: array index must be 'UIntNative', got 'Int32'
        \\      status_code = arr[idx]
        \\                        ^
        \\
    );
}
