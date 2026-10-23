const std = @import("std");
const builtin = @import("builtin");
const Cancellation = @import("../execution/vm.zig").Cancellation;

// Process signals touch only static atomic storage. They never borrow a command's
// stack, access a VM, allocate, print, or unwind language cleanup.
var active: std.atomic.Value(bool) = .init(false);
var cancellation: Cancellation = .{};

fn interrupt(_: if (builtin.os.tag == .windows) u32 else std.posix.SIG) callconv(.c) void {
    if (active.load(.monotonic)) cancellation.cancel();
}

const Console = struct {
    const Handler = *const fn (u32) callconv(.winapi) std.os.windows.BOOL;
    extern "kernel32" fn SetConsoleCtrlHandler(?Handler, std.os.windows.BOOL) callconv(.winapi) std.os.windows.BOOL;

    fn interrupt(event: u32) callconv(.winapi) std.os.windows.BOOL {
        if ((event != 0 and event != 1) or !active.load(.monotonic)) return .FALSE;
        cancellation.cancel();
        return .TRUE;
    }
};

/// One CLI execution owns the process interrupt handler. Embedders continue to
/// supply their own cancellation tokens and never install handlers through VM APIs.
pub const Guard = struct {
    saved: if (builtin.os.tag == .windows) void else std.posix.Sigaction,

    pub fn init() !Guard {
        if (active.cmpxchgStrong(false, true, .monotonic, .monotonic) != null) return error.ExecutionInterruptInUse;
        errdefer active.store(false, .monotonic);
        cancellation.reset();
        if (builtin.os.tag == .windows) {
            if (Console.SetConsoleCtrlHandler(Console.interrupt, .TRUE) == .FALSE) return error.ExecutionInterruptUnavailable;
            return .{ .saved = {} };
        }
        var saved: std.posix.Sigaction = undefined;
        const action: std.posix.Sigaction = .{
            .handler = .{ .handler = interrupt },
            .mask = std.posix.sigemptyset(),
            .flags = std.posix.SA.RESTART,
        };
        std.posix.sigaction(.INT, &action, &saved);
        return .{ .saved = saved };
    }

    pub fn token(_: *const Guard) *Cancellation {
        return &cancellation;
    }

    pub fn deinit(self: Guard) void {
        if (builtin.os.tag == .windows) {
            _ = Console.SetConsoleCtrlHandler(Console.interrupt, .FALSE);
        } else std.posix.sigaction(.INT, &self.saved, null);
        active.store(false, .monotonic);
    }
};

test "execution interrupt handler owns one token and resets between commands" {
    {
        const first = try Guard.init();
        defer first.deinit();
        try std.testing.expect(!first.token().isCancelled());
        try std.testing.expectError(error.ExecutionInterruptInUse, Guard.init());
        interrupt(if (builtin.os.tag == .windows) 0 else .INT);
        try std.testing.expect(first.token().isCancelled());
    }
    const second = try Guard.init();
    defer second.deinit();
    try std.testing.expect(!second.token().isCancelled());
}

test "execution interrupt handler receives SIGINT and restores the previous handler" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;
    var before: std.posix.Sigaction = undefined;
    std.posix.sigaction(.INT, null, &before);
    const cancelled = blk: {
        const guard = try Guard.init();
        defer guard.deinit();
        try std.posix.raise(.INT);
        break :blk guard.token().isCancelled();
    };
    try std.testing.expect(cancelled);
    var after: std.posix.Sigaction = undefined;
    std.posix.sigaction(.INT, null, &after);
    try std.testing.expectEqual(before.handler.handler, after.handler.handler);
}
