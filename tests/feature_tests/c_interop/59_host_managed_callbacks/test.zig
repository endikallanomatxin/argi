const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "C interop invokes host-managed scalar and record callbacks" {
    try support.checkNativeCFixture("tests/feature_tests/c_interop/59_host_managed_callbacks", &.{
        "define i32 @argi_callback_add(i32",
        "@argi_callback_packet(",
        "define void @argi_callback_packet(ptr sret(",
    });
}
