const std = @import("std");
const sf = @import("source_files.zig");
const source_db = @import("source_db.zig");
const tok = @import("../2_tokens/token.zig");

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
    source_db: source_db.SourceDb,
    list: std.array_list.Managed(Diagnostic),

    pub fn init(
        a: *const std.mem.Allocator,
        files: []const sf.SourceFile,
    ) Diagnostics {
        return .{
            .arena = a,
            .source_files = files,
            .source_db = source_db.SourceDb.init(a.*, files) catch unreachable,
            .list = std.array_list.Managed(Diagnostic).init(a.*),
        };
    }

    pub fn deinit(self: *Diagnostics) void {
        self.list.deinit();
        self.source_db.deinit(self.arena.*);
    }

    pub fn add(self: *Diagnostics, loc: tok.Location, kind: Kind, comptime fmt: []const u8, args: anytype) !void {
        const txt = try std.fmt.allocPrint(self.arena.*, fmt, args);
        try self.list.append(.{ .loc = loc, .kind = kind, .msg = txt });
    }
    pub fn hasErrors(self: *Diagnostics) bool {
        return self.list.items.len != 0;
    }

    pub fn path(self: *const Diagnostics, loc: tok.Location) []const u8 {
        return self.source_db.path(loc.file);
    }

    pub fn lineColumn(self: *const Diagnostics, loc: tok.Location) source_db.LineColumn {
        return self.source_db.lineColumn(loc.file, loc.offset);
    }

    pub fn dump(self: *Diagnostics) !void {
        try self.dumpWithLimit(std.math.maxInt(usize));
    }

    pub fn dumpWithLimit(self: *Diagnostics, max_count: usize) !void {
        for (self.source_files, 0..) |f, file_index| {
            // pre-split en líneas para subrayado
            var lines_it = std.mem.splitAny(u8, f.code, "\n");
            var lines = std.array_list.Managed([]const u8).init(std.heap.page_allocator);
            defer lines.deinit();
            while (lines_it.next()) |l| try lines.append(l);

            var shown: usize = 0;
            for (self.list.items) |d| {
                if (@intFromEnum(d.loc.file) != file_index) continue;
                if (shown >= max_count) break;
                const position = self.lineColumn(d.loc);
                std.debug.print(
                    "{s}:{d}:{d}: error: {s}\n",
                    .{ f.path, position.line, position.column, d.msg },
                );

                if (position.line - 1 < lines.items.len) {
                    const code = lines.items[position.line - 1];
                    std.debug.print("  {s}\n", .{code});
                    const indent_len = @min(code.len, position.column - 1);
                    std.debug.print("  ", .{});
                    indent(indent_len);
                    std.debug.print("^\n", .{});
                }
                shown += 1;
            }
        }
    }
};

fn indent(lvl: usize) void {
    var i: usize = 0;
    while (i < lvl) : (i += 1) std.debug.print(" ", .{});
}
