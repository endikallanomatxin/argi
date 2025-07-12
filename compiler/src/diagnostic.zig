const std = @import("std");
const sf = @import("source_files.zig");
const tok = @import("token.zig");

pub const Kind = enum {
    syntax,
    semantic,
    codegen,
    internal,
};

pub const Diagnostic = struct {
    loc: tok.Location,
    kind: Kind,
    msg: []const u8,
};

/// Pequeño *bag* que vive en un `Allocator` (arena está bien)
pub const Diagnostics = struct {
    arena: *const std.mem.Allocator,
    source_files: []const sf.SourceFile, // slice inmutable
    list: std.ArrayList(Diagnostic),

    pub fn init(
        a: *const std.mem.Allocator,
        files: []const sf.SourceFile,
    ) Diagnostics {
        return .{
            .arena = a,
            .source_files = files,
            .list = std.ArrayList(Diagnostic).init(a.*),
        };
    }

    pub fn deinit(self: *const Diagnostics) void {
        self.list.deinit();
    }

    pub fn add(self: *Diagnostics, loc: tok.Location, kind: Kind, comptime fmt: []const u8, args: anytype) !void {
        const txt = try std.fmt.allocPrint(self.arena.*, fmt, args);
        try self.list.append(.{ .loc = loc, .kind = kind, .msg = txt });
    }
    pub fn hasErrors(self: *Diagnostics) bool {
        return self.list.items.len != 0;
    }

    pub fn dump(self: *Diagnostics) !void {
        for (self.source_files) |f| {
            // pre-split en líneas para subrayado
            var lines_it = std.mem.splitAny(u8, f.code, "\n");
            var lines = std.ArrayList([]const u8).init(std.heap.page_allocator);
            defer lines.deinit();
            while (lines_it.next()) |l| lines.append(l) catch {};

            for (self.list.items) |d| {
                if (!std.mem.eql(u8, d.loc.file, f.path)) continue;
                std.debug.print(
                    "{s}:{d}:{d}: error: {s}\n",
                    .{ f.path, d.loc.line, d.loc.column, d.msg },
                );

                if (d.loc.line - 1 < lines.items.len) {
                    const code = lines.items[d.loc.line - 1];
                    std.debug.print("  {s}\n", .{code});
                    const indent_len = @min(code.len, d.loc.column - 1);
                    std.debug.print("  ", .{});
                    indent(indent_len);
                    std.debug.print("^\n", .{});
                }
            }
        }
    }
};

fn indent(lvl: usize) void {
    var i: usize = 0;
    while (i < lvl) : (i += 1) std.debug.print(" ", .{});
}
