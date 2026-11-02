const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "C interop checks null callback values" {
    try support.checkNativeCFixture("tests/feature_tests/c_interop/78_callback_null", &.{
        "declare ptr @argi_callback_lookup(i32",
        "icmp eq ptr",
        "ptr null",
    });
}
