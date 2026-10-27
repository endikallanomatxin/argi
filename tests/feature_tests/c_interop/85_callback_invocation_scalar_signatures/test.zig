const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "C interop invokes narrow floating and void callbacks" {
    const target = @import("builtin").target;
    const extends = (target.cpu.arch == .x86_64 and target.os.tag != .windows) or (target.cpu.arch == .aarch64 and target.os.tag.isDarwin());
    try support.checkNativeCFixture("tests/feature_tests/c_interop/85_callback_invocation_scalar_signatures", if (extends) &.{
        "callback.nonnull",
        "call signext i16 %",
        "i8 signext",
        "call double %",
        "call void %",
    } else &.{
        "callback.nonnull",
        "call i16 %",
        "(i8 ",
        "call double %",
        "call void %",
    });
}
