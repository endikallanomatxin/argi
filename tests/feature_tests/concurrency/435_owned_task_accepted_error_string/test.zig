const support = @import("../../../support.zig");
const builtin = @import("builtin");

pub const isolation: support.Isolation = .fixture;

test "435_owned_task_accepted_error_string" {
    const path = "tests/feature_tests/concurrency/435_owned_task_accepted_error_string";
    if (builtin.os.tag == .linux) {
        try support.clean(path);
        try support.expectArgiBuildSuccess(&.{
            "build",    path,
            "--cc-arg", path ++ "/count_release.c",
            "--cc-arg", "-Wl,--wrap=_argi_c_aligned_release",
        });
    } else {
        try support.expectSuccessfulBuild(path);
    }
    try support.runExpect(path, 0);
}
