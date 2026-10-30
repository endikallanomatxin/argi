const std = @import("std");
const builtin = @import("builtin");

/// Terminal state is transport-local and must be restored before leaving the REPL.
pub const Terminal = struct {
    saved: if (builtin.os.tag == .windows) WindowsMode else std.posix.termios,

    const WindowsMode = struct {
        input: u32,
        output: u32,
        input_code_page: u32,
        output_code_page: u32,

        fn enter(comptime Api: type, input: std.os.windows.HANDLE, output: std.os.windows.HANDLE) !WindowsMode {
            var saved: WindowsMode = .{
                .input = undefined,
                .output = undefined,
                .input_code_page = Api.GetConsoleCP(),
                .output_code_page = Api.GetConsoleOutputCP(),
            };
            if (saved.input_code_page == 0 or saved.output_code_page == 0 or
                Api.GetConsoleMode(input, &saved.input) == .FALSE or
                Api.GetConsoleMode(output, &saved.output) == .FALSE) return error.TerminalModeUnavailable;
            errdefer saved.restore(Api, input, output);
            // The editor transports UTF-8 bytes, independently of the user's
            // console code pages. Every failed setup restores all saved state.
            if (Api.SetConsoleCP(65001) == .FALSE or Api.SetConsoleOutputCP(65001) == .FALSE or
                Api.SetConsoleMode(output, saved.output | 0x0004) == .FALSE or
                Api.SetConsoleMode(input, (saved.input & ~@as(u32, 0x0007)) | 0x0200) == .FALSE)
                return error.TerminalModeUnavailable;
            return saved;
        }

        fn restore(self: WindowsMode, comptime Api: type, input: std.os.windows.HANDLE, output: std.os.windows.HANDLE) void {
            _ = Api.SetConsoleMode(input, self.input);
            _ = Api.SetConsoleMode(output, self.output);
            _ = Api.SetConsoleCP(self.input_code_page);
            _ = Api.SetConsoleOutputCP(self.output_code_page);
        }
    };
    const Console = struct {
        const Screen = extern struct {
            size: [2]i16,
            cursor: [2]i16,
            attributes: u16,
            window: [4]i16,
            maximum: [2]i16,
        };
        extern "kernel32" fn GetConsoleScreenBufferInfo(std.os.windows.HANDLE, *Screen) callconv(.winapi) std.os.windows.BOOL;
        extern "kernel32" fn GetConsoleMode(std.os.windows.HANDLE, *u32) callconv(.winapi) std.os.windows.BOOL;
        extern "kernel32" fn SetConsoleMode(std.os.windows.HANDLE, u32) callconv(.winapi) std.os.windows.BOOL;
        extern "kernel32" fn GetConsoleCP() callconv(.winapi) u32;
        extern "kernel32" fn GetConsoleOutputCP() callconv(.winapi) u32;
        extern "kernel32" fn SetConsoleCP(u32) callconv(.winapi) std.os.windows.BOOL;
        extern "kernel32" fn SetConsoleOutputCP(u32) callconv(.winapi) std.os.windows.BOOL;
    };

    pub fn columns() usize {
        if (builtin.os.tag == .windows) {
            var screen: Console.Screen = undefined;
            if (Console.GetConsoleScreenBufferInfo(std.Io.File.stdout().handle, &screen) != .FALSE) {
                const visible = @as(i32, screen.window[2]) - screen.window[0] + 1;
                if (visible > 0) return @intCast(visible);
            }
        } else {
            var size: std.posix.winsize = undefined;
            if (std.c.ioctl(std.Io.File.stdout().handle, @as(c_int, @bitCast(@as(u32, std.posix.T.IOCGWINSZ))), &size) == 0 and size.col > 0)
                return size.col;
        }
        return 80;
    }

    pub fn enter() !Terminal {
        if (builtin.os.tag == .windows) {
            const input = std.Io.File.stdin().handle;
            const output = std.Io.File.stdout().handle;
            return .{ .saved = try WindowsMode.enter(Console, input, output) };
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
            self.saved.restore(Console, std.Io.File.stdin().handle, std.Io.File.stdout().handle);
        } else std.posix.tcsetattr(std.Io.File.stdin().handle, .NOW, self.saved) catch {};
    }
};

test "Windows terminal setup restores code pages and modes after every failure" {
    const Handle = std.os.windows.HANDLE;
    const Bool = std.os.windows.BOOL;
    const Api = struct {
        var state: Terminal.WindowsMode = undefined;
        var calls: usize = 0;
        var fail_at: usize = 0;
        fn GetConsoleCP() u32 {
            return state.input_code_page;
        }
        fn GetConsoleOutputCP() u32 {
            return state.output_code_page;
        }
        fn GetConsoleMode(handle: Handle, mode: *u32) Bool {
            mode.* = if (@intFromPtr(handle) == 1) state.input else state.output;
            return .TRUE;
        }
        fn set(destination: *u32, mode: u32) Bool {
            calls += 1;
            if (calls == fail_at) return .FALSE;
            destination.* = mode;
            return .TRUE;
        }
        fn SetConsoleCP(page: u32) Bool {
            return set(&state.input_code_page, page);
        }
        fn SetConsoleOutputCP(page: u32) Bool {
            return set(&state.output_code_page, page);
        }
        fn SetConsoleMode(handle: Handle, mode: u32) Bool {
            return set(if (@intFromPtr(handle) == 1) &state.input else &state.output, mode);
        }
    };
    const initial: Terminal.WindowsMode = .{ .input = 0x87, .output = 1, .input_code_page = 437, .output_code_page = 850 };
    const input: Handle = @ptrFromInt(1);
    const output: Handle = @ptrFromInt(2);
    for (0..5) |failure| {
        Api.state = initial;
        Api.calls = 0;
        Api.fail_at = failure;
        if (failure == 0) {
            const saved = try Terminal.WindowsMode.enter(Api, input, output);
            try std.testing.expectEqualDeep(initial, saved);
            try std.testing.expectEqual(@as(u32, 65001), Api.state.input_code_page);
            try std.testing.expectEqual(@as(u32, 65001), Api.state.output_code_page);
            try std.testing.expectEqual(initial.input & ~@as(u32, 7) | 0x0200, Api.state.input);
            try std.testing.expectEqual(initial.output | 0x0004, Api.state.output);
            saved.restore(Api, input, output);
        } else try std.testing.expectError(error.TerminalModeUnavailable, Terminal.WindowsMode.enter(Api, input, output));
        try std.testing.expectEqualDeep(initial, Api.state);
    }
}

/// Bounded session-local editing. No semantic or execution state is stored here.
pub const Editor = struct {
    allocator: std.mem.Allocator,
    history: std.ArrayList([]const u8) = .empty,
    line: std.ArrayList(u8) = .empty,
    cancelled: bool = false,
    draft: std.ArrayList(u8) = .empty,
    highlight: bool = false,
    columns: ?usize = null,
    measure_terminal: bool = false,
    context: @import("../1_base/lexical.zig").Completion = .{},
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
        if (self.measure_terminal) self.columns = Terminal.columns();
        const columns = self.columns orelse std.math.maxInt(usize);
        const shown_prompt = if (columns < 8) "" else prompt;
        try output.print("\r\x1b[2K{s}", .{shown_prompt});
        if (columns < 4) return output.flush();
        const highlight = @import("repl_highlight.zig");
        if (cellBound(self.line.items) < columns -| shown_prompt.len) {
            try highlight.renderWithCursor(self.allocator, output, self.line.items, self.context.quote, cursor, self.highlight);
        } else {
            const budget = columns -| shown_prompt.len -| 3;
            var start = cursor;
            var cells: usize = 0;
            const left_budget = if (cursor == self.line.items.len) budget else budget * 3 / 4;
            while (start > 0) {
                const previous = previousBoundary(self.line.items, start);
                const cost = scalarBound(self.line.items[previous]);
                if (cells + cost > left_budget) break;
                start = previous;
                cells += cost;
            }
            var end = cursor;
            while (end < self.line.items.len) {
                const cost = scalarBound(self.line.items[end]);
                if (cells + cost > budget) break;
                cells += cost;
                end = nextBoundary(self.line.items, end);
            }
            if (start != 0) try output.writeByte('<');
            try highlight.renderWindowWithCursor(self.allocator, output, self.line.items, self.context.quote, cursor, self.highlight, start, end);
        }
        try output.flush();
    }

    // A safe viewport budget, not a Unicode width table: reserve two cells per
    // non-ASCII scalar. The terminal still places the actual cursor, including
    // combining sequences. This can leave spare columns but avoids guessing
    // grapheme widths or allowing long input to scroll the editing origin away.
    fn scalarBound(first: u8) usize {
        return if (first < 0x80) 1 else 2;
    }

    fn cellBound(line: []const u8) usize {
        var cells: usize = 0;
        var index: usize = 0;
        while (index < line.len) {
            cells += scalarBound(line[index]);
            index = nextBoundary(line, index);
        }
        return cells;
    }

    fn indentation(self: *const Editor) usize {
        if (self.context.quote != null or self.context.invalid) return 0;
        var spaces: usize = 0;
        for (self.context.stack[0..self.context.depth]) |open| if (open == '{') {
            spaces += 4;
        };
        return spaces;
    }

    pub fn read(self: *Editor, input: *std.Io.Reader, output: *std.Io.Writer, prompt: []const u8) !?[]const u8 {
        self.line.clearRetainingCapacity();
        self.cancelled = false;
        self.draft.clearRetainingCapacity();
        var selected = self.history.items.len;
        var automatic_indent = self.indentation();
        try self.line.appendNTimes(self.allocator, ' ', automatic_indent);
        var cursor = automatic_indent;
        try self.redraw(output, prompt, cursor);
        while (true) {
            const byte = input.takeByte() catch |err| switch (err) {
                error.EndOfStream => return null,
                else => return err,
            };
            switch (byte) {
                '\n', '\r' => {
                    // Finish after the displayed source, even when Enter is
                    // pressed while editing in the middle of the line.
                    if (cursor != self.line.items.len) try self.redraw(output, prompt, self.line.items.len);
                    try output.writeByte('\n');
                    try self.remember();
                    return self.line.items;
                },
                3 => {
                    if (cursor != self.line.items.len) try self.redraw(output, prompt, self.line.items.len);
                    self.cancelled = true;
                    self.line.clearRetainingCapacity();
                    try output.writeAll("^C\n");
                    return self.line.items;
                },
                4 => if (std.mem.trim(u8, self.line.items, " \t").len == 0) {
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
                            automatic_indent = 0;
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
                            // Consume complete CSI parameters before interpreting a
                            // key, so unsupported suffixes never become source text.
                            var tail = key;
                            var plain_delete = prefix == '[' and key == '3';
                            while (tail < 0x40 or tail > 0x7e) {
                                tail = input.takeByte() catch |err| switch (err) {
                                    error.EndOfStream => return null,
                                    else => return err,
                                };
                                if (tail < 0x40 or tail > 0x7e) plain_delete = false;
                            }
                            if (plain_delete and tail == '~' and cursor < self.line.items.len) {
                                const end = nextBoundary(self.line.items, cursor);
                                try self.line.replaceRange(self.allocator, cursor, end - cursor, &.{});
                            }
                        },
                    }
                },
                0...2, 5...7, 9, 11...12, 14...26, 28...31 => continue,
                else => {
                    // A terminal character can arrive in separate reads. Never
                    // redraw between its UTF-8 bytes or split it at the limit.
                    var encoded: [4]u8 = undefined;
                    encoded[0] = byte;
                    const expected = std.unicode.utf8ByteSequenceLength(byte) catch 1;
                    var count: usize = 1;
                    while (count < expected) {
                        const next = input.peekByte() catch |err| switch (err) {
                            error.EndOfStream => break,
                            else => return err,
                        };
                        if (next & 0xc0 != 0x80) break;
                        encoded[count] = try input.takeByte();
                        count += 1;
                    }
                    if (self.line.items.len + count > max_line) continue;
                    if (byte == '}' and automatic_indent >= 4 and cursor == automatic_indent and self.line.items.len == automatic_indent) {
                        try self.line.replaceRange(self.allocator, 0, 4, &.{});
                        cursor -= 4;
                        automatic_indent -= 4;
                    }
                    try self.line.insertSlice(self.allocator, cursor, encoded[0..count]);
                    automatic_indent = 0;
                    cursor += count;
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
    try std.testing.expect(editor.cancelled);
    try std.testing.expectEqualStrings("a€", (try editor.read(&input, &output.writer, "")).?);
    try std.testing.expect(!editor.cancelled);
    try std.testing.expectEqual(@as(usize, 1), editor.history.items.len);
}

test "REPL redraw keeps typed UTF-8 characters complete" {
    var editor: Editor = .{ .allocator = std.testing.allocator };
    defer editor.deinit();
    var input = std.Io.Reader.fixed("a界€ñ\n");
    var output = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer output.deinit();
    try std.testing.expectEqualStrings("a界€ñ", (try editor.read(&input, &output.writer, "")).?);
    try std.testing.expect(std.unicode.utf8ValidateSlice(output.written()));
}

test "REPL submission and cancellation finish after the displayed source" {
    var editor: Editor = .{ .allocator = std.testing.allocator };
    defer editor.deinit();
    var input = std.Io.Reader.fixed("a界z\x1b[H\nignored\x1b[H\x03");
    var output = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer output.deinit();
    try std.testing.expectEqualStrings("a界z", (try editor.read(&input, &output.writer, ">>> ")).?);
    try std.testing.expect(std.mem.endsWith(u8, output.written(), "\r\x1b[2K>>> a界z\n"));
    try std.testing.expectEqualStrings("", (try editor.read(&input, &output.writer, ">>> ")).?);
    try std.testing.expect(editor.cancelled);
    try std.testing.expect(std.mem.endsWith(u8, output.written(), "\r\x1b[2K>>> ignored^C\n"));
}

test "REPL narrow terminal pans without wrapping or changing input" {
    var editor: Editor = .{ .allocator = std.testing.allocator, .columns = 12 };
    defer editor.deinit();
    try editor.line.appendSlice(editor.allocator, "0123456789abcdefghij");
    var output = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer output.deinit();
    try editor.redraw(&output.writer, ">>> ", editor.line.items.len);
    try std.testing.expectEqualStrings("\r\x1b[2K>>> <fghij", output.written());
    output.clearRetainingCapacity();
    try editor.redraw(&output.writer, ">>> ", 0);
    try std.testing.expectEqualStrings("\r\x1b[2K>>> \x1b[s01234>\x1b[u", output.written());
    output.clearRetainingCapacity();
    try editor.redraw(&output.writer, ">>> ", 10);
    try std.testing.expectEqualStrings("\r\x1b[2K>>> <789\x1b[sab>\x1b[u", output.written());
    var input = std.Io.Reader.fixed("0123456789abcdefghij\x1b[H\x1b[3~\x1b[F\n");
    try std.testing.expectEqualStrings("123456789abcdefghij", (try editor.read(&input, &output.writer, ">>> ")).?);
}

test "REPL viewport preserves Unicode boundaries at every cursor position" {
    var editor: Editor = .{ .allocator = std.testing.allocator, .columns = 12 };
    defer editor.deinit();
    const text = "界a🙂e\u{301}界🙂end";
    try editor.line.appendSlice(editor.allocator, text);
    var output = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer output.deinit();
    var cursor: usize = 0;
    while (true) {
        output.clearRetainingCapacity();
        try editor.redraw(&output.writer, ">>> ", cursor);
        try std.testing.expect(std.unicode.utf8ValidateSlice(output.written()));
        if (cursor == text.len) break;
        cursor = Editor.nextBoundary(text, cursor);
    }
    // Resize is applied on the next redraw, without retaining stale offsets.
    editor.columns = 80;
    output.clearRetainingCapacity();
    try editor.redraw(&output.writer, ">>> ", text.len);
    try std.testing.expectEqualStrings("\r\x1b[2K>>> " ++ text, output.written());
}

test "REPL truncated UTF-8 does not consume editing controls" {
    var editor: Editor = .{ .allocator = std.testing.allocator };
    defer editor.deinit();
    var input = std.Io.Reader.fixed("\xc3\x7fok\n\xe2\n");
    var output = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer output.deinit();
    try std.testing.expectEqualStrings("ok", (try editor.read(&input, &output.writer, "")).?);
    try std.testing.expectEqualStrings("\xe2", (try editor.read(&input, &output.writer, "")).?);
}

test "REPL Delete removes one UTF-8 character without consuming neighbouring input" {
    var editor: Editor = .{ .allocator = std.testing.allocator };
    defer editor.deinit();
    var input = std.Io.Reader.fixed("añ€z\x1b[H\x1b[C\x1b[3~\x1b[3~\n\x1b[A\x1b[3~\n\x1b[H\x1b[3~\n\x1b[3;2~ok\n");
    var output = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer output.deinit();
    try std.testing.expectEqualStrings("az", (try editor.read(&input, &output.writer, "")).?);
    // Delete at the end of recalled history is a no-op.
    try std.testing.expectEqualStrings("az", (try editor.read(&input, &output.writer, "")).?);
    try std.testing.expectEqualStrings("", (try editor.read(&input, &output.writer, "")).?);
    // Unsupported modified keys must not leak their suffix into source text.
    try std.testing.expectEqualStrings("ok", (try editor.read(&input, &output.writer, "")).?);
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

test "REPL continuation indentation follows lexical braces and dedents a closing line" {
    var editor: Editor = .{ .allocator = std.testing.allocator, .highlight = true };
    defer editor.deinit();
    var output = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer output.deinit();
    var input = std.Io.Reader.fixed("result = 42\n}\n\x1b[A\n\x03\x04");
    editor.context.feedLine("answer := () -> () { -- } ignored");
    editor.context.feedLine("if true { text ::= \"}\"");
    try std.testing.expectEqualStrings("        result = 42", (try editor.read(&input, &output.writer, "... ")).?);
    try std.testing.expectEqualStrings("    }", (try editor.read(&input, &output.writer, "... ")).?);
    try std.testing.expectEqualStrings("    }", (try editor.read(&input, &output.writer, "... ")).?);
    try std.testing.expectEqualStrings("", (try editor.read(&input, &output.writer, "... ")).?);
    try std.testing.expect(editor.cancelled);
    try std.testing.expectEqual(@as(?[]const u8, null), try editor.read(&input, &output.writer, "... "));
    for (editor.history.items) |line| try std.testing.expect(std.mem.indexOfScalar(u8, line, 27) == null);
}

test "REPL continuation strings preserve their bytes and manual indentation stays editable" {
    var editor: Editor = .{ .allocator = std.testing.allocator };
    defer editor.deinit();
    var output = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer output.deinit();
    var input = std.Io.Reader.fixed("continued }\"\n \x7f}\n");
    editor.context.feedLine("function := () -> () {");
    editor.context.feedLine("text ::= \"open {");
    try std.testing.expectEqualStrings("continued }\"", (try editor.read(&input, &output.writer, "... ")).?);
    editor.context.feedLine(editor.line.items);
    try std.testing.expect(editor.context.quote == null);
    // A manual indentation edit takes precedence over automatic dedentation.
    try std.testing.expectEqualStrings("    }", (try editor.read(&input, &output.writer, "... ")).?);
}
