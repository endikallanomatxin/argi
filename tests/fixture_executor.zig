//! Execute declared expectations through the same process helpers as custom tests.
const std = @import("std");
const catalog = @import("fixture_catalog.zig");
const support = @import("support.zig");

pub fn execute(path: []const u8, steps: []const catalog.Step) !void {
    for (steps) |step| switch (step.kind) {
        .build => try support.expectSuccessfulBuild(path),
        .reject => {
            const result = try support.buildResult(path);
            defer std.testing.allocator.free(result.stdout);
            defer std.testing.allocator.free(result.stderr);
            switch (result.term) {
                .exited => |code| try std.testing.expect(code != 0),
                else => return error.UnexpectedProcessTermination,
            }
            if (step.diagnostic) |text| try support.expectDiagnostic(path, result.stderr, text);
            if (step.stderr) |text| try std.testing.expectEqualStrings(text, result.stderr);
            for (step.forbidden_stdout) |text| if (std.mem.indexOf(u8, result.stdout, text) != null) return error.UnexpectedDiagnostic;
            for (step.forbidden_stderr) |text| if (std.mem.indexOf(u8, result.stderr, text) != null) return error.UnexpectedDiagnostic;
        },
        .run => {
            if (step.stdin) |text|
                try support.runExpectStdoutWithArgsAndStdin(path, step.args, text, step.status.?, step.stdout.?)
            else if (step.stdout) |text|
                try support.runExpectStdoutWithArgs(path, step.args, step.status.?, text)
            else if (step.stderr) |text|
                try support.runExpectStderr(path, step.status.?, text)
            else
                try support.runExpect(path, step.status.?);
        },
        .run_failure => try support.runExpectFailure(path),
        .vm => try support.vmExpect(path, step.status.?, step.diagnostic),
    };
}
