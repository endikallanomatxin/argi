const std = @import("std");
const builtin = @import("builtin");

/// Terminal state is transport-local and must be restored before leaving the REPL.
pub const Terminal = struct {
    saved: if (builtin.os.tag == .windows) WindowsMode else std.posix.termios,

    const WindowsMode = struct { input: u32, output: u32 };
    const Console = struct {
        extern "kernel32" fn GetConsoleMode(std.os.windows.HANDLE, *u32) callconv(.winapi) std.os.windows.BOOL;
        extern "kernel32" fn SetConsoleMode(std.os.windows.HANDLE, u32) callconv(.winapi) std.os.windows.BOOL;
    };

    pub fn enter() !Terminal {
        if (builtin.os.tag == .windows) {
            var saved: WindowsMode = undefined;
            const input = std.Io.File.stdin().handle;
            const output = std.Io.File.stdout().handle;
            if (Console.GetConsoleMode(input, &saved.input) == .FALSE or
                Console.GetConsoleMode(output, &saved.output) == .FALSE) return error.TerminalModeUnavailable;
            // Enable virtual-terminal output before input so failure can roll back.
            if (Console.SetConsoleMode(output, saved.output | 0x0004) == .FALSE) return error.TerminalModeUnavailable;
            errdefer _ = Console.SetConsoleMode(output, saved.output);
            // Disable processed, line and echo input; request ANSI key sequences.
            if (Console.SetConsoleMode(input, (saved.input & ~@as(u32, 0x0007)) | 0x0200) == .FALSE) return error.TerminalModeUnavailable;
            return .{ .saved = saved };
        }
        const saved = try std.posix.tcgetattr(std.Io.File.stdin().handle);
        var edited = saved;
        edited.lflag.ICANON = false;
        edited.lflag.ECHO = false;
        edited.lflag.ISIG = false;
        edited.lflag.IEXTEN = false;
        edited.iflag.IXON = false;
        edited.cc[@intFromEnum(std.posix.V.MIN)] = 1;
        edited.cc[@intFromEnum(std.posix.V.TIME)] = 0;
        try std.posix.tcsetattr(std.Io.File.stdin().handle, .NOW, edited);
        return .{ .saved = saved };
    }

    pub fn restore(self: Terminal) void {
        if (builtin.os.tag == .windows) {
            _ = Console.SetConsoleMode(std.Io.File.stdin().handle, self.saved.input);
            _ = Console.SetConsoleMode(std.Io.File.stdout().handle, self.saved.output);
        } else std.posix.tcsetattr(std.Io.File.stdin().handle, .NOW, self.saved) catch {};
    }
};

/// Bounded session-local history. No source or execution state is stored here.
pub const Editor = struct {
    allocator: std.mem.Allocator,
    history: std.ArrayList([]const u8) = .empty,
    line: std.ArrayList(u8) = .empty,
    draft: std.ArrayList(u8) = .empty,
    const max_history = 256;
    const max_line = 64 * 1024;

    pub fn deinit(self: *Editor) void {
        for (self.history.items) |item| self.allocator.free(item);
        self.history.deinit(self.allocator);
        self.line.deinit(self.allocator);
        self.draft.deinit(self.allocator);
    }

    fn remember(self: *Editor) !void {
        const line = self.line.items;
        if (std.mem.trim(u8, line, " \t\r").len == 0) return;
        if (self.history.items.len != 0 and std.mem.eql(u8, self.history.items[self.history.items.len - 1], line)) return;
        const copy = try self.allocator.dupe(u8, line);
        errdefer self.allocator.free(copy);
        try self.history.append(self.allocator, copy);
        if (self.history.items.len > max_history) self.allocator.free(self.history.orderedRemove(0));
    }

    fn previousBoundary(line: []const u8, cursor: usize) usize {
        var index = cursor - 1;
        while (index > 0 and line[index] & 0xc0 == 0x80) index -= 1;
        return index;
    }

    fn nextBoundary(line: []const u8, cursor: usize) usize {
        var index = cursor + 1;
        while (index < line.len and line[index] & 0xc0 == 0x80) index += 1;
        return index;
    }

    fn redraw(self: *Editor, output: *std.Io.Writer, prompt: []const u8, cursor: usize) !void {
        try output.print("\r\x1b[2K{s}{s}", .{ prompt, self.line.items });
        // Move by characters rather than UTF-8 bytes. Full terminal display-width
        // accounting is deliberately left to a future multiline editor.
        var remaining: usize = 0;
        for (self.line.items[cursor..]) |byte| if (byte & 0xc0 != 0x80) {
            remaining += 1;
        };
        if (remaining != 0) try output.print("\x1b[{d}D", .{remaining});
        try output.flush();
    }

    pub fn read(self: *Editor, input: *std.Io.Reader, output: *std.Io.Writer, prompt: []const u8) !?[]const u8 {
        self.line.clearRetainingCapacity();
        self.draft.clearRetainingCapacity();
        var selected = self.history.items.len;
        var cursor: usize = 0;
        try output.writeAll(prompt);
        try output.flush();
        while (true) {
            const byte = input.takeByte() catch |err| switch (err) {
                error.EndOfStream => return null,
                else => return err,
            };
            switch (byte) {
                '\n', '\r' => {
                    try output.writeByte('\n');
                    try self.remember();
                    return self.line.items;
                },
                3 => {
                    self.line.clearRetainingCapacity();
                    try output.writeAll("^C\n");
                    return self.line.items;
                },
                4 => if (self.line.items.len == 0) {
                    try output.writeByte('\n');
                    return null;
                },
                8, 127 => if (cursor > 0) {
                    const start = previousBoundary(self.line.items, cursor);
                    try self.line.replaceRange(self.allocator, start, cursor - start, &.{});
                    cursor = start;
                },
                27 => {
                    const prefix = input.takeByte() catch |err| switch (err) {
                        error.EndOfStream => return null,
                        else => return err,
                    };
                    if (prefix != '[' and prefix != 'O') continue;
                    const key = input.takeByte() catch |err| switch (err) {
                        error.EndOfStream => return null,
                        else => return err,
                    };
                    switch (key) {
                        'A', 'B' => {
                            if (key == 'A') {
                                if (selected == 0) continue;
                                if (selected == self.history.items.len) {
                                    self.draft.clearRetainingCapacity();
                                    try self.draft.appendSlice(self.allocator, self.line.items);
                                }
                                selected -= 1;
                            } else {
                                if (selected == self.history.items.len) continue;
                                selected += 1;
                            }
                            const replacement = if (selected == self.history.items.len) self.draft.items else self.history.items[selected];
                            self.line.clearRetainingCapacity();
                            try self.line.appendSlice(self.allocator, replacement);
                            cursor = self.line.items.len;
                        },
                        'C' => if (cursor < self.line.items.len) {
                            cursor = nextBoundary(self.line.items, cursor);
                        },
                        'D' => if (cursor > 0) {
                            cursor = previousBoundary(self.line.items, cursor);
                        },
                        'H' => cursor = 0,
                        'F' => cursor = self.line.items.len,
                        else => {
                            // Consume the rest of unsupported CSI keys (e.g. Delete)
                            // so their numeric suffix never becomes source text.
                            var tail = key;
                            while (tail < 0x40 or tail > 0x7e) tail = input.takeByte() catch |err| switch (err) {
                                error.EndOfStream => return null,
                                else => return err,
                            };
                        },
                    }
                },
                0...2, 5...7, 9, 11...12, 14...26, 28...31 => continue,
                else => {
                    if (self.line.items.len == max_line) continue;
                    try self.line.insert(self.allocator, cursor, byte);
                    cursor += 1;
                },
            }
            try self.redraw(output, prompt, cursor);
        }
    }
};

test "REPL history recalls edits and restores the unfinished draft" {
    var editor: Editor = .{ .allocator = std.testing.allocator };
    defer editor.deinit();
    var input = std.Io.Reader.fixed("first\nsecond\ndraft\x1b[A\x1b[A\x1b[B\x1b[B\n\x1b[A\x7f!\n\x04");
    var output = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer output.deinit();
    try std.testing.expectEqualStrings("first", (try editor.read(&input, &output.writer, ">>> ")).?);
    try std.testing.expectEqualStrings("second", (try editor.read(&input, &output.writer, ">>> ")).?);
    try std.testing.expectEqualStrings("draft", (try editor.read(&input, &output.writer, ">>> ")).?);
    try std.testing.expectEqualStrings("draf!", (try editor.read(&input, &output.writer, ">>> ")).?);
    try std.testing.expectEqual(@as(?[]const u8, null), try editor.read(&input, &output.writer, ">>> "));
}

test "REPL editing preserves UTF-8 and cancels without recording a line" {
    var editor: Editor = .{ .allocator = std.testing.allocator };
    defer editor.deinit();
    var input = std.Io.Reader.fixed("ñ€\x1b[D\x7fa\nignored\x03\x1b[A\n");
    var output = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer output.deinit();
    try std.testing.expectEqualStrings("a€", (try editor.read(&input, &output.writer, "")).?);
    try std.testing.expectEqualStrings("", (try editor.read(&input, &output.writer, "")).?);
    try std.testing.expectEqualStrings("a€", (try editor.read(&input, &output.writer, "")).?);
    try std.testing.expectEqual(@as(usize, 1), editor.history.items.len);
}

test "REPL history bounds memory and ignores empty and consecutive duplicate lines" {
    var editor: Editor = .{ .allocator = std.testing.allocator };
    defer editor.deinit();
    for (0..Editor.max_history + 5) |index| {
        editor.line.clearRetainingCapacity();
        var buffer: [32]u8 = undefined;
        try editor.line.appendSlice(editor.allocator, try std.fmt.bufPrint(&buffer, "line {d}", .{index}));
        try editor.remember();
    }
    try editor.remember();
    editor.line.clearRetainingCapacity();
    try editor.line.appendSlice(editor.allocator, "   ");
    try editor.remember();
    try std.testing.expectEqual(Editor.max_history, editor.history.items.len);
    try std.testing.expectEqualStrings("line 5", editor.history.items[0]);
}
