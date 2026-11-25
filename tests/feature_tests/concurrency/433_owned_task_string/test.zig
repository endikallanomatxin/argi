const support = @import("../../../support.zig");
const builtin = @import("builtin");

pub const isolation: support.Isolation = .fixture;

test "433_owned_task_string" {
    const path = "tests/feature_tests/concurrency/433_owned_task_string";
    if (builtin.os.tag == .linux) {
        try support.clean(path);
        try support.expectArgiBuildSuccess(&.{
            "build",    path,
            "--cc-arg", "tests/feature_tests/_support/count_heap_releases.c",
            "--cc-arg", "-DEXPECTED_RELEASES=4",
            "--cc-arg", "-Wl,--wrap=_argi_c_aligned_release",
        });
    } else {
        try support.expectSuccessfulBuild(path);
    }
    try support.runExpect(path, 0);
}
