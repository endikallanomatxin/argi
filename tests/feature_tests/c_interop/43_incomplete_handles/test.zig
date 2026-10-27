const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "C interop preserves incomplete handle identities through raw pointers" {
    try support.checkNativeCFixture("tests/feature_tests/c_interop/43_incomplete_handles", &.{
        "declare ptr @argi_c_handle_create()",
        "define ptr @argi_c_handle_export(ptr",
    });
}
