//! A runner-owned cache of immutable modules. Every check has fresh semantic state.
const std = @import("std");
const compiler = @import("compiler_test_frontend");

pub const Context = struct {
    io: std.Io,
    backing: std.heap.DebugAllocator(.{ .thread_safe = false }) = .{},
    state: ?compiler.Environment = null,
    finished: bool = false,
    checks: usize = 0,

    pub fn deinit(self: *Context) bool {
        if (self.finished) return false;
        if (self.state) |*environment| environment.deinit();
        self.state = null;
        self.finished = true;
        return self.backing.deinit() == .leak;
    }

    pub fn check(self: *Context, directory: []const u8, expected: compiler.ExpectedDiagnostic) !void {
        if (self.finished) return error.FrontendContextFinished;
        self.checks += 1;
        if (self.state == null) self.state = try compiler.Environment.init(self.backing.allocator(), self.io);
        _ = try self.state.?.checkModule(std.testing.allocator, directory, expected);
    }
};

// Zig tests take no context argument. The runner installs its own owner for the
// duration of its test loop, just as it installs std.testing.io and allocator.
var active: ?*Context = null;

pub fn install(context: ?*Context) void {
    if (context != null) std.debug.assert(active == null);
    active = context;
}

pub fn check(directory: []const u8, expected: compiler.ExpectedDiagnostic) !void {
    const context = active orelse return error.MissingFrontendTestContext;
    return context.check(directory, expected);
}
