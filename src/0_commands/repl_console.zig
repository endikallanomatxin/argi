//! Windows console transport. Pipes keep their ordinary byte-stream reader.
const std = @import("std");
const windows = std.os.windows;

pub const Api = struct {
    pub const Screen = extern struct {
        size: [2]i16,
        cursor: [2]i16,
        attributes: u16,
        window: [4]i16,
        maximum: [2]i16,
    };
    pub extern "kernel32" fn GetConsoleScreenBufferInfo(windows.HANDLE, *Screen) callconv(.winapi) windows.BOOL;
    pub extern "kernel32" fn GetConsoleMode(windows.HANDLE, *u32) callconv(.winapi) windows.BOOL;
    pub extern "kernel32" fn SetConsoleMode(windows.HANDLE, u32) callconv(.winapi) windows.BOOL;
    pub extern "kernel32" fn GetConsoleOutputCP() callconv(.winapi) u32;
    pub extern "kernel32" fn SetConsoleOutputCP(u32) callconv(.winapi) windows.BOOL;
    extern "kernel32" fn ReadConsoleW(windows.HANDLE, [*]u16, u32, *u32, ?*anyopaque) callconv(.winapi) windows.BOOL;

    pub fn readUnits(handle: windows.HANDLE, buffer: []u16) std.Io.Reader.Error!usize {
        var count: u32 = 0;
        if (ReadConsoleW(handle, buffer.ptr, @intCast(buffer.len), &count, null) == .FALSE) return error.ReadFailed;
        return count;
    }
};

/// Output encoding belongs to the complete session, including VM execution.
/// Input modes remain scoped to editing so execution can receive Ctrl-C.
pub const OutputEncoding = struct {
    saved: u32,

    pub fn enter() !OutputEncoding {
        return enterWith(Api);
    }
    fn enterWith(comptime Console: type) !OutputEncoding {
        const encoding: OutputEncoding = .{ .saved = Console.GetConsoleOutputCP() };
        if (encoding.saved == 0) return error.TerminalModeUnavailable;
        errdefer encoding.restoreWith(Console);
        if (Console.SetConsoleOutputCP(65001) == .FALSE) return error.TerminalModeUnavailable;
        return encoding;
    }
    pub fn restore(self: OutputEncoding) void {
        self.restoreWith(Api);
    }
    fn restoreWith(self: OutputEncoding, comptime Console: type) void {
        _ = Console.SetConsoleOutputCP(self.saved);
    }
};

pub const Input = ConsoleReader(Api);

/// An inherited VT-input mode routes Ctrl-C as bytes instead of an execution
/// interrupt. Editing temporarily enables VT input again; between reads the
/// console must process control events for the installed cancellation handler.
pub const ExecutionInput = struct {
    handle: windows.HANDLE,
    saved: u32,

    pub fn enter(handle: windows.HANDLE) !ExecutionInput {
        return enterWith(Api, handle);
    }
    fn enterWith(comptime Console: type, handle: windows.HANDLE) !ExecutionInput {
        var saved: u32 = undefined;
        if (Console.GetConsoleMode(handle, &saved) == .FALSE) return error.TerminalModeUnavailable;
        const result: ExecutionInput = .{ .handle = handle, .saved = saved };
        errdefer result.restoreWith(Console);
        if (Console.SetConsoleMode(handle, (saved | 1) & ~@as(u32, 0x0200)) == .FALSE) return error.TerminalModeUnavailable;
        return result;
    }
    pub fn restore(self: ExecutionInput) void {
        self.restoreWith(Api);
    }
    fn restoreWith(self: ExecutionInput, comptime Console: type) void {
        _ = Console.SetConsoleMode(self.handle, self.saved);
    }
};

test "Windows REPL execution enables processed interrupts and restores inherited input" {
    const Console = struct {
        var mode: u32 = 0x0206;
        var fail: bool = false;
        fn GetConsoleMode(_: windows.HANDLE, value: *u32) windows.BOOL {
            value.* = mode;
            return .TRUE;
        }
        fn SetConsoleMode(_: windows.HANDLE, value: u32) windows.BOOL {
            if (fail) {
                fail = false;
                return .FALSE;
            }
            mode = value;
            return .TRUE;
        }
    };
    Console.mode = 0x0206;
    const saved = try ExecutionInput.enterWith(Console, @ptrFromInt(1));
    try std.testing.expectEqual(@as(u32, 7), Console.mode);
    saved.restoreWith(Console);
    try std.testing.expectEqual(@as(u32, 0x0206), Console.mode);
    Console.fail = true;
    try std.testing.expectError(error.TerminalModeUnavailable, ExecutionInput.enterWith(Console, @ptrFromInt(1)));
    try std.testing.expectEqual(@as(u32, 0x0206), Console.mode);
}

fn ConsoleReader(comptime Console: type) type {
    return struct {
        const Self = @This();
        handle: windows.HANDLE,
        interface: std.Io.Reader,
        units: [128]u16 = undefined,
        unit_start: usize = 0,
        unit_end: usize = 0,
        bytes: [4]u8 = undefined,
        byte_start: usize = 0,
        byte_end: usize = 0,

        pub fn init(handle: windows.HANDLE, buffer: []u8) Self {
            return .{ .handle = handle, .interface = .{
                .buffer = buffer,
                .vtable = &.{ .stream = stream },
                .seek = 0,
                .end = 0,
            } };
        }

        fn unit(self: *Self) std.Io.Reader.Error!u16 {
            if (self.unit_start == self.unit_end) {
                self.unit_end = try Console.readUnits(self.handle, &self.units);
                self.unit_start = 0;
                if (self.unit_end == 0) return error.EndOfStream;
            }
            const result = self.units[self.unit_start];
            self.unit_start += 1;
            return result;
        }

        fn stream(reader: *std.Io.Reader, writer: *std.Io.Writer, limit: std.Io.Limit) std.Io.Reader.StreamError!usize {
            const self: *Self = @fieldParentPtr("interface", reader);
            if (limit == .nothing) return 0;
            if (self.byte_start == self.byte_end) {
                const first = try self.unit();
                const scalar: u21 = if (std.unicode.utf16IsHighSurrogate(first)) pair: {
                    const second = self.unit() catch return error.ReadFailed;
                    break :pair std.unicode.utf16DecodeSurrogatePair(&.{ first, second }) catch return error.ReadFailed;
                } else if (std.unicode.utf16IsLowSurrogate(first)) return error.ReadFailed else first;
                self.byte_end = std.unicode.utf8Encode(scalar, &self.bytes) catch return error.ReadFailed;
                self.byte_start = 0;
            }
            const count = try writer.write(limit.slice(self.bytes[self.byte_start..self.byte_end]));
            self.byte_start += count;
            return count;
        }
    };
}

test "Windows REPL output encoding lasts until session teardown" {
    const Console = struct {
        var page: u32 = 0;
        var fail: bool = false;
        fn GetConsoleOutputCP() u32 {
            return page;
        }
        fn SetConsoleOutputCP(value: u32) windows.BOOL {
            if (fail) {
                fail = false;
                return .FALSE;
            }
            page = value;
            return .TRUE;
        }
    };
    Console.page = 850;
    const saved = try OutputEncoding.enterWith(Console);
    try std.testing.expectEqual(@as(u32, 65001), Console.page);
    saved.restoreWith(Console);
    try std.testing.expectEqual(@as(u32, 850), Console.page);
    Console.fail = true;
    try std.testing.expectError(error.TerminalModeUnavailable, OutputEncoding.enterWith(Console));
    try std.testing.expectEqual(@as(u32, 850), Console.page);
}

const MockInput = struct {
    source: []const u16,
    offset: usize = 0,
    chunk: usize,

    fn readUnits(handle: windows.HANDLE, buffer: []u16) std.Io.Reader.Error!usize {
        const self: *MockInput = @ptrCast(@alignCast(handle));
        const count = @min(buffer.len, self.chunk, self.source.len - self.offset);
        @memcpy(buffer[0..count], self.source[self.offset..][0..count]);
        self.offset += count;
        return count;
    }
};

test "Windows REPL console input preserves surrogate pairs across reads" {
    const text = std.unicode.utf8ToUtf16LeStringLiteral("界a🙂\x1b[D\x03\x04");
    for ([_]usize{ 1, 2, 3, 128 }) |chunk| {
        var source: MockInput = .{ .source = text, .chunk = chunk };
        var buffer: [1]u8 = undefined;
        var input = ConsoleReader(MockInput).init(@ptrCast(&source), &buffer);
        var output: std.ArrayList(u8) = .empty;
        defer output.deinit(std.testing.allocator);
        while (true) {
            const byte = input.interface.takeByte() catch |err| switch (err) {
                error.EndOfStream => break,
                else => return err,
            };
            try output.append(std.testing.allocator, byte);
        }
        try std.testing.expectEqualStrings("界a🙂\x1b[D\x03\x04", output.items);
    }
}

test "Windows REPL console input rejects unpaired surrogates" {
    for ([_][]const u16{ &.{0xd800}, &.{0xdc00}, &.{ 0xd800, 'a' } }) |units| {
        var source: MockInput = .{ .source = units, .chunk = 1 };
        var buffer: [4]u8 = undefined;
        var input = ConsoleReader(MockInput).init(@ptrCast(&source), &buffer);
        try std.testing.expectError(error.ReadFailed, input.interface.takeByte());
    }
}
