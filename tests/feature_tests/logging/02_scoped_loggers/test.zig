const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const run = support.run;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/logging/02_scoped_loggers" {
    try expectSuccessfulBuild("tests/feature_tests/logging/02_scoped_loggers");
    try run("tests/feature_tests/logging/02_scoped_loggers");
}
