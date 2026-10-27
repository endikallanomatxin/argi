//! In-process source checks through the production frontend and Safety pipeline.
const std = @import("std");
const Frontend = @import("../0_commands/frontend_pipeline.zig").FrontendPipeline;
const Diagnostics = @import("../1_base/diagnostic.zig").Diagnostics;
const SourceFile = @import("../1_base/source_files.zig").SourceFile;

pub fn checkSource(name: []const u8, source: []const u8, marker: ?[]const u8, expected: ?[]const u8, exact: bool) !void {
    errdefer std.debug.print("source case {s}:\n{s}\n", .{ name, source });
    const a = std.testing.allocator;
    const file_path = try std.fmt.allocPrint(a, "source_cases/{s}/main.rg", .{name});
    defer a.free(file_path);
    const files = [_]SourceFile{.{ .path = file_path, .code = source }};
    var messages = std.heap.ArenaAllocator.init(a);
    defer messages.deinit();
    const diagnostic_allocator = messages.allocator();
    var diagnostics = Diagnostics.init(&diagnostic_allocator, &files);
    defer diagnostics.deinit();
    var frontend = Frontend.init(a, std.testing.io, &diagnostics, .{});
    defer frontend.deinit();
    const result = frontend.semantizeGlobalFiles(&files);
    if (expected) |message| {
        if (result) |_| {
            std.debug.print("source case {s} unexpectedly accepted\n", .{name});
            return error.ExpectedRejection;
        } else |err| try std.testing.expectEqual(error.Reported, err);
        const diagnostic = for (diagnostics.list.items) |item| {
            if (if (exact) std.mem.eql(u8, item.msg, message) else std.mem.indexOf(u8, item.msg, message) != null) break item;
        } else {
            for (diagnostics.list.items) |item| std.debug.print("source case {s}: {s}\n", .{ name, item.msg });
            return error.MissingExpectedDiagnostic;
        };
        try std.testing.expectEqual(.semantic, diagnostic.kind);
        try std.testing.expectEqualStrings(file_path, diagnostics.path(diagnostic.loc));
        if (marker) |location| try std.testing.expectEqual(std.mem.indexOf(u8, source, location).?, diagnostics.presentedLocation(diagnostic.loc).offset);
    } else {
        _ = result catch |err| {
            for (diagnostics.list.items) |diagnostic| std.debug.print("source case {s}: {s}\n", .{ name, diagnostic.msg });
            return err;
        };
        try std.testing.expectEqual(@as(usize, 0), diagnostics.list.items.len);
        // Successful cases must reach the real Safety checker too.
        try std.testing.expect(frontend.safety_ctx != null);
    }
}
