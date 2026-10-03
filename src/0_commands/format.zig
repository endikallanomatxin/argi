const std = @import("std");
const formatter = @import("../3_syntax/formatter.zig");

pub fn run(io: std.Io, args: []const []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var paths = std.array_list.Managed([]const u8).init(allocator);
    var check = false;
    var stdout = false;
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--check")) {
            check = true;
        } else if (std.mem.eql(u8, arg, "--stdout")) {
            stdout = true;
        } else if (std.mem.startsWith(u8, arg, "-")) {
            std.debug.print("Unknown formatting option: {s}\n", .{arg});
            return error.InvalidArguments;
        } else try paths.append(arg);
    }
    if (check and stdout) return error.InvalidArguments;
    if (paths.items.len == 0) try paths.append(".");
    if (stdout and (paths.items.len != 1 or !std.mem.endsWith(u8, paths.items[0], ".rg"))) return error.InvalidArguments;
    var files = std.array_list.Managed([]const u8).init(allocator);
    for (paths.items) |path| {
        if (std.mem.endsWith(u8, path, ".rg")) {
            try files.append(path);
            continue;
        }
        var dir = try std.Io.Dir.cwd().openDir(io, path, .{ .iterate = true });
        defer dir.close(io);
        var walker = try dir.walk(allocator);
        defer walker.deinit();
        while (try walker.next(io)) |entry| {
            if (entry.kind == .directory and ignored(entry.path)) {
                walker.leave(io);
                continue;
            }
            if (entry.kind != .file or !std.mem.endsWith(u8, entry.path, ".rg")) continue;
            if (ignored(entry.path)) continue;
            try files.append(try std.fs.path.join(allocator, &.{ path, entry.path }));
        }
    }
    std.mem.sort([]const u8, files.items, {}, struct {
        fn less(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.less);
    // Prepare every edit before writing, so invalid input leaves the entire
    // request untouched. Duplicate paths are harmless and omitted.
    var edits = std.array_list.Managed(struct { path: []const u8, text: []const u8 }).init(allocator);
    for (files.items, 0..) |path, index| {
        if (index != 0 and std.mem.eql(u8, files.items[index - 1], path)) continue;
        const source = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(16 * 1024 * 1024));
        const formatted = formatter.format(allocator, source) catch |err| {
            std.debug.print("Cannot format '{s}': {s}\n", .{ path, @errorName(err) });
            return err;
        };
        if (stdout) {
            var buffer: [4096]u8 = undefined;
            var writer = std.Io.File.stdout().writer(io, &buffer);
            try writer.interface.writeAll(formatted);
            try writer.interface.flush();
        } else if (!std.mem.eql(u8, source, formatted)) try edits.append(.{ .path = path, .text = formatted });
    }
    if (check) {
        for (edits.items) |edit| std.debug.print("Would format: {s}\n", .{edit.path});
        if (edits.items.len != 0) return error.UnformattedSource;
    } else for (edits.items) |edit| {
        const stat = try std.Io.Dir.cwd().statFile(io, edit.path, .{});
        var atomic = try std.Io.Dir.cwd().createFileAtomic(io, edit.path, .{ .replace = true, .permissions = stat.permissions });
        defer atomic.deinit(io);
        var buffer: [8192]u8 = undefined;
        var writer = atomic.file.writer(io, &buffer);
        try writer.interface.writeAll(edit.text);
        try writer.interface.flush();
        try atomic.replace(io);
        std.debug.print("Formatted: {s}\n", .{edit.path});
    }
}

fn ignored(path: []const u8) bool {
    var parts = std.mem.tokenizeAny(u8, path, "/\\");
    while (parts.next()) |part| {
        if (part[0] == '.' or std.mem.eql(u8, part, "zig-out") or std.mem.eql(u8, part, "references") or std.mem.eql(u8, part, "node_modules")) return true;
    }
    return false;
}
