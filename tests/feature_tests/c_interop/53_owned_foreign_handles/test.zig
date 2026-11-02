const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "C interop pairs owned handle acquisition and automatic cleanup" {
    try support.checkNativeCFixture("tests/feature_tests/c_interop/53_owned_foreign_handles", &.{
        "declare ptr @argi_c_owned_create(i32",
        "declare void @argi_c_owned_destroy(ptr",
    });
}
