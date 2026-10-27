const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "C interop transports nominal callback pointers and record fields" {
    try support.checkNativeCFixture("tests/feature_tests/c_interop/66_typed_callback_transport", &.{
        "declare ptr @argi_callback_lookup()",
        "define ptr @argi_callback_echo(ptr",
        "declare i32 @argi_callback_apply(ptr",
    });
}
