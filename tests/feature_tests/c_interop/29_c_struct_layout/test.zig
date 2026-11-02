const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "C interop preserves explicit record layouts through native pointers" {
    try support.checkNativeCFixture("tests/feature_tests/c_interop/29_c_struct_layout", &.{
        "declare i32 @argi_c_payload_verify(ptr)",
        "declare void @argi_c_payload_fill(ptr)",
        "define i32 @argi_c_payload_export(ptr",
    });
}
