const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "C interop adapts raw pointers for imports bodies and exports" {
    try support.checkNativeCFixture("tests/feature_tests/c_interop/24_raw_pointer_abi", &.{
        "declare ptr @argi_c_static()",
        "declare ptr @argi_c_echo(ptr)",
        "define ptr @argi_pointer_export(ptr",
    });
}
