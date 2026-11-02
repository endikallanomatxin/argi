const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "C interop selects typed record callbacks with indirect results" {
    try support.checkNativeCFixture("tests/feature_tests/c_interop/77_typed_record_callback", &.{
        "declare i32 @argi_typed_callback_probe(ptr",
        "sret({ double, i32, { i64 } })",
    });
}
