const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "C interop extends narrow scalars according to the platform ABI" {
    const target = @import("builtin").target;
    const extends = (target.cpu.arch == .x86_64 and target.os.tag != .windows) or (target.cpu.arch == .aarch64 and target.os.tag.isDarwin());
    try support.checkNativeCFixture("tests/feature_tests/c_interop/33_narrow_scalar_abi", if (extends) &.{
        "define signext i8 @argi_c_small_signed(i8 signext",
        "define zeroext i8 @argi_c_small_unsigned(i8 zeroext",
        "call signext i16 @argi_c_short_import(i16 signext",
        "declare zeroext i1 @argi_c_bool_import(i1 zeroext",
    } else &.{
        "define i8 @argi_c_small_signed(i8",
        "define i1 @argi_c_bool(i1",
    });
}
