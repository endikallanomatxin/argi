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

/// One unchanged source span embedded in generated code. Semantic locations
/// retain generated offsets; only diagnostic presentation follows this map.
pub const SourceMap = struct {
    generated: source_db.FileId,
    original: source_db.FileId,
    offset: u32,
    length: u32,
};

/// A small *bag* allocated from an `Allocator` (an arena works well).
pub const Diagnostics = struct {
    arena: *const std.mem.Allocator,
    // Optional short-lived message storage; source indexes keep arena ownership.
    message_allocator: ?std.mem.Allocator = null,
    source_files: []const sf.SourceFile, // Immutable initialized prefix.
    source_db: source_db.SourceDb,
    owned_source_files: ?[]sf.SourceFile = null,
    owns_source_db: bool = true,
    source_maps: []const SourceMap = &.{},
    source_map_capacity: usize = 0,
    list: std.array_list.Managed(Diagnostic),

    pub fn init(
        a: *const std.mem.Allocator,
        files: []const sf.SourceFile,
    ) !Diagnostics {
        return .{
            .arena = a,
            .source_files = files,
            .source_db = try source_db.SourceDb.init(a.*, files),
            .list = std.array_list.Managed(Diagnostic).init(a.*),
        };
    }

    /// A task-local bag over a frozen source index. The owner must outlive it;
    /// borrowed bags cannot append sources.
    pub fn initBorrowed(a: *const std.mem.Allocator, owner: *const Diagnostics) Diagnostics {
        return .{
            .arena = a,
            .source_files = owner.source_files,
            .source_db = owner.source_db,
            .owns_source_db = false,
            .source_maps = owner.source_maps,
            .list = std.array_list.Managed(Diagnostic).init(a.*),
        };
    }

    pub fn deinit(self: *Diagnostics) void {
        self.list.deinit();
        if (self.owns_source_db) {
            self.source_db.deinit(self.arena.*);
            self.arena.free(self.source_maps.ptr[0..@max(self.source_map_capacity, self.source_maps.len)]);
        }
        if (self.owned_source_files) |files| self.arena.free(files);
    }

    pub fn appendSource(self: *Diagnostics, source: sf.SourceFile) !source_db.FileId {
        std.debug.assert(self.owns_source_db);
        const count = try std.math.add(usize, self.source_files.len, 1);
        const previous: []sf.SourceFile = self.owned_source_files orelse &.{};
        const grow = previous.len < count;
        const capacity = if (grow) try std.math.ceilPowerOfTwo(usize, @max(count, 4)) else previous.len;
        const files = if (grow) try self.arena.alloc(sf.SourceFile, capacity) else previous;
        errdefer if (grow) self.arena.free(files);
        if (grow) @memcpy(files[0..self.source_files.len], self.source_files);
        files[self.source_files.len] = source;
        const id = try self.source_db.append(self.arena.*, source);
        if (grow) self.arena.free(previous);
        self.owned_source_files = files;
        self.source_files = files[0..count];
        return id;
    }

    /// Discard an unpublished source tail after its last diagnostic is cleared.
    /// Accepted source IDs retain their coordinates; table capacity is reused.
    pub fn truncateSources(self: *Diagnostics, count: usize, maps: usize) void {
        std.debug.assert(self.owns_source_db and self.list.items.len == 0);
        std.debug.assert(count <= self.source_files.len and maps <= self.source_maps.len);
        for (self.source_db.files[count..]) |file| self.arena.free(file.line_starts);
        self.source_db.files = self.source_db.files[0..count];
        self.source_files = self.source_files[0..count];
        self.source_maps = self.source_maps[0..maps];
    }

    /// Missing source metadata must never suppress a semantic failure.
    pub fn addUnlocated(self: *Diagnostics, kind: Kind, comptime fmt: []const u8, args: anytype) !void {
        return self.add(tok.Location.unavailable, kind, fmt, args);
    }

    pub fn add(self: *Diagnostics, loc: tok.Location, kind: Kind, comptime fmt: []const u8, args: anytype) !void {
        const messages = self.message_allocator orelse self.arena.*;
        const txt = try std.fmt.allocPrint(messages, fmt, args);
        errdefer messages.free(txt);
        try self.list.append(.{ .loc = self.presentedLocation(loc), .kind = kind, .msg = txt });
    }

    pub fn addSourceMap(self: *Diagnostics, map: SourceMap) !void {
        std.debug.assert(self.owns_source_db);
        if (@intFromEnum(map.generated) >= self.source_files.len or @intFromEnum(map.original) >= self.source_files.len or map.generated == map.original) return error.InvalidDiagnosticSourceMap;
        const generated = self.source_db.get(map.generated).source;
        const original = self.source_db.get(map.original).source;
        if (map.offset > generated.len or map.length > generated.len - map.offset or map.length != original.len or
            !std.mem.eql(u8, generated[map.offset..][0..map.length], original)) return error.InvalidDiagnosticSourceMap;
        for (self.source_maps) |existing| {
            // Keep presentation idempotent: each generated file has one span,
            // and original buffers are never themselves generated buffers.
            if (existing.generated == map.generated or existing.original == map.generated or existing.generated == map.original) return error.InvalidDiagnosticSourceMap;
        }
        const count = try std.math.add(usize, self.source_maps.len, 1);
        const previous = @constCast(self.source_maps.ptr)[0..@max(self.source_map_capacity, self.source_maps.len)];
        const grow = previous.len < count;
        const capacity = if (grow) try std.math.ceilPowerOfTwo(usize, @max(count, 4)) else previous.len;
        const maps = if (grow) try self.arena.alloc(SourceMap, capacity) else previous;
        if (grow) @memcpy(maps[0..self.source_maps.len], self.source_maps);
        maps[self.source_maps.len] = map;
        if (grow) self.arena.free(previous);
        self.source_map_capacity = maps.len;
        self.source_maps = maps[0..count];
    }

    pub fn presentedLocation(self: *const Diagnostics, loc: tok.Location) tok.Location {
        for (self.source_maps) |map| {
            if (loc.file == map.generated and loc.offset >= map.offset and loc.offset - map.offset <= map.length)
                return .{ .file = map.original, .offset = loc.offset - map.offset };
        }
        return loc;
    }
    pub fn hasErrors(self: *Diagnostics) bool {
        return self.list.items.len != 0;
    }

    pub fn path(self: *const Diagnostics, loc: tok.Location) []const u8 {
        const file = self.presentedLocation(loc).file;
        if (@intFromEnum(file) >= self.source_db.files.len) return "<unknown>";
        return self.source_db.path(file);
    }

    pub fn lineColumn(self: *const Diagnostics, loc: tok.Location) source_db.LineColumn {
        const presented = self.presentedLocation(loc);
        if (@intFromEnum(presented.file) >= self.source_db.files.len) return .{ .line = 1, .column = 1 };
        return self.source_db.lineColumn(presented.file, presented.offset);
    }

    pub fn dump(self: *Diagnostics) !void {
        try self.dumpWithLimit(std.math.maxInt(usize));
    }

    pub fn dumpWithLimit(self: *Diagnostics, max_count: usize) !void {
        for (self.source_files, 0..) |f, file_index| {
            // Pre-split into lines for highlighting.
            var lines_it = std.mem.splitAny(u8, f.code, "\n");
            var lines = std.array_list.Managed([]const u8).init(std.heap.page_allocator);
            defer lines.deinit();
            while (lines_it.next()) |l| try lines.append(l);

            var shown: usize = 0;
            for (self.list.items) |d| {
                const loc = self.presentedLocation(d.loc);
                if (@intFromEnum(loc.file) != file_index) continue;
                if (shown >= max_count) break;
                const position = self.lineColumn(loc);
                std.debug.print(
                    "{s}:{d}:{d}: error: {s}\n",
                    .{ f.path, position.line, position.column, d.msg },
                );

                if (position.line - 1 < lines.items.len) {
                    // CRLF is one line ending; do not emit its carriage return
                    // as part of the source excerpt or caret width.
                    const code = std.mem.trimEnd(u8, lines.items[position.line - 1], "\r");
                    std.debug.print("  {s}\n", .{code});
                    const indent_len = @min(code.len, position.column - 1);
                    std.debug.print("  ", .{});
                    indent(indent_len);
                    std.debug.print("^\n", .{});
                }
                shown += 1;
            }
        }
        var unlocated_shown: usize = 0;
        for (self.list.items) |diagnostic| {
            if (@intFromEnum(self.presentedLocation(diagnostic.loc).file) < self.source_db.files.len) continue;
            if (unlocated_shown >= max_count) break;
            std.debug.print("error: {s}\n", .{diagnostic.msg});
            unlocated_shown += 1;
        }
    }
};

fn indent(lvl: usize) void {
    var i: usize = 0;
    while (i < lvl) : (i += 1) std.debug.print(" ", .{});
}

test "diagnostic source maps preserve semantic offsets and borrowed presentation" {
    const allocator = std.testing.allocator;
    const files = [_]sf.SourceFile{
        .{ .path = "generated.rg", .code = "header\nvalue\nfooter" },
        .{ .path = "input.rg", .code = "value" },
    };
    var diagnostics = try Diagnostics.init(&allocator, &files);
    defer {
        for (diagnostics.list.items) |item| allocator.free(item.msg);
        diagnostics.deinit();
    }
    try diagnostics.addSourceMap(.{ .generated = @enumFromInt(0), .original = @enumFromInt(1), .offset = 7, .length = 5 });
    const generated = tok.Location{ .file = @enumFromInt(0), .offset = 9 };
    try diagnostics.add(generated, .semantic, "invalid value", .{});
    const mapped = diagnostics.list.items[0].loc;
    try std.testing.expectEqual(@as(u32, 9), generated.offset);
    try std.testing.expectEqual(@as(u32, 2), mapped.offset);
    try std.testing.expectEqualStrings("input.rg", diagnostics.path(generated));
    try std.testing.expectEqual(@as(u32, 3), diagnostics.lineColumn(generated).column);
    try std.testing.expectEqualDeep(mapped, diagnostics.presentedLocation(mapped));
    var borrowed = Diagnostics.initBorrowed(&allocator, &diagnostics);
    defer borrowed.deinit();
    try std.testing.expectEqualDeep(mapped, borrowed.presentedLocation(generated));
    try std.testing.expectError(error.InvalidDiagnosticSourceMap, diagnostics.addSourceMap(.{ .generated = @enumFromInt(1), .original = @enumFromInt(0), .offset = 0, .length = 5 }));
}

test "diagnostics retain errors without source metadata" {
    const a = std.testing.allocator;
    var diagnostics = try Diagnostics.init(&a, &.{});
    defer {
        for (diagnostics.list.items) |item| a.free(item.msg);
        diagnostics.deinit();
    }
    try diagnostics.addUnlocated(.semantic, "invalid value {d}", .{42});
    try std.testing.expect(diagnostics.hasErrors());
    const diagnostic = diagnostics.list.items[0];
    try std.testing.expectEqual(source_db.FileId.unknown, diagnostic.loc.file);
    try std.testing.expectEqualStrings("invalid value 42", diagnostic.msg);
    try std.testing.expectEqualStrings("<unknown>", diagnostics.path(diagnostic.loc));
    try std.testing.expectEqual(@as(u32, 1), diagnostics.lineColumn(diagnostic.loc).line);
}

fn exerciseDiagnosticIndexAllocationFailures(allocator: std.mem.Allocator) !void {
    var diagnostics = try Diagnostics.init(&allocator, &.{});
    defer diagnostics.deinit();
    for (0..8) |_| {
        const original = diagnostics.appendSource(.{ .path = "original.rg", .code = "42" }) catch |err| {
            try std.testing.expectEqual(diagnostics.source_files.len, diagnostics.source_db.files.len);
            return err;
        };
        const before = diagnostics.source_files.len;
        const generated = diagnostics.appendSource(.{ .path = "generated.rg", .code = "wrap42" }) catch |err| {
            try std.testing.expectEqual(before, diagnostics.source_files.len);
            try std.testing.expectEqual(before, diagnostics.source_db.files.len);
            try std.testing.expectEqualStrings("42", diagnostics.source_db.get(original).source);
            return err;
        };
        const maps = diagnostics.source_maps.len;
        diagnostics.addSourceMap(.{ .generated = generated, .original = original, .offset = 4, .length = 2 }) catch |err| {
            try std.testing.expectEqual(maps, diagnostics.source_maps.len);
            return err;
        };
        const location = diagnostics.presentedLocation(.{ .file = generated, .offset = 5 });
        try std.testing.expectEqual(original, location.file);
        try std.testing.expectEqual(@as(u32, 1), location.offset);
    }
}

test "diagnostic source and mapping growth remains atomic on allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, exerciseDiagnosticIndexAllocationFailures, .{});
}

test "diagnostic initialization releases partially built source indexes on allocation failure" {
    const files = [_]sf.SourceFile{
        .{ .path = "first.rg", .code = "first\nsecond\nthird" },
        .{ .path = "second.rg", .code = "one\ntwo" },
        .{ .path = "third.rg", .code = "last\n" },
    };
    try @import("../test_support.zig").checkAllocationAndResizeFailures(std.testing.allocator, struct {
        fn run(allocator: std.mem.Allocator, sources: []const sf.SourceFile) !void {
            var diagnostics = try Diagnostics.init(&allocator, sources);
            defer diagnostics.deinit();
            try std.testing.expectEqual(sources.len, diagnostics.source_db.files.len);
            const location: tok.Location = .{ .file = diagnostics.source_db.fileId(0), .offset = 6 };
            try std.testing.expectEqualStrings("first.rg", diagnostics.path(location));
            try std.testing.expectEqual(@as(u32, 2), diagnostics.lineColumn(location).line);
        }
    }.run, .{&files});
}
