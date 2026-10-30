//! Process-level terminal probes. All child setup uses prebuilt argv/environment.
const std = @import("std");
const builtin = @import("builtin");
const support = @import("support.zig");

extern "c" fn forkpty(*c_int, ?*anyopaque, ?*anyopaque, ?*anyopaque) c_int;
extern "c" fn fork() c_int;
extern "c" fn execve([*:0]const u8, [*:null]const ?[*:0]const u8, [*:null]const ?[*:0]const u8) c_int;
extern "c" fn _exit(c_int) noreturn;
extern "c" fn pipe(*[2]c_int) c_int;
extern "c" fn dup2(c_int, c_int) c_int;
extern "c" fn close(c_int) c_int;
extern "c" fn read(c_int, [*]u8, usize) isize;
extern "c" fn write(c_int, [*]const u8, usize) isize;
extern "c" fn waitpid(c_int, *c_int, c_int) c_int;
extern "c" fn kill(c_int, c_int) c_int;
extern "c" var environ: [*:null]?[*:0]u8;
const max_output = 1024 * 1024;

fn nowMs() !i64 {
    var ts: std.posix.timespec = undefined;
    if (std.c.clock_gettime(.MONOTONIC, &ts) != 0) return error.ClockFailed;
    return @as(i64, @intCast(ts.sec)) * 1000 + @divTrunc(@as(i64, @intCast(ts.nsec)), 1000000);
}

const Child = struct {
    pid: c_int,
    input: c_int,
    output: c_int,
    errors_fd: c_int = -1,
    errors: std.ArrayList(u8) = .empty,
    reaped: bool = false,
    pending: std.ArrayList(u8) = .empty,
    transcript: std.ArrayList(u8) = .empty,

    fn start(args: []const []const u8, tty: bool, colors: ?bool, ignore_interrupt: bool, separate_stderr: bool) !Child {
        const a = std.testing.allocator;
        const argv = try a.allocSentinel(?[*:0]const u8, args.len, null);
        defer a.free(argv);
        @memset(argv, null);
        defer for (argv) |arg| if (arg) |p| a.free(std.mem.span(p));
        for (args, 0..) |arg, i| argv[i] = (try a.dupeZ(u8, arg)).ptr;
        var env: std.ArrayList(?[*:0]const u8) = .empty;
        defer env.deinit(a);
        var index: usize = 0;
        while (environ[index]) |entry| : (index += 1) {
            const item = std.mem.span(entry);
            if (colors != null and (std.mem.startsWith(u8, item, "TERM=") or std.mem.startsWith(u8, item, "NO_COLOR="))) continue;
            try env.append(a, entry);
        }
        if (colors) |enabled| {
            try env.append(a, "TERM=xterm-256color");
            if (!enabled) try env.append(a, "NO_COLOR=1");
        }
        try env.append(a, null);
        var master: c_int = -1;
        var input_pipe: [2]c_int = undefined;
        var output_pipe: [2]c_int = undefined;
        var errors_pipe: [2]c_int = undefined;
        if (!tty) {
            if (pipe(&input_pipe) != 0) return error.PipeFailed;
            if (pipe(&output_pipe) != 0) {
                _ = close(input_pipe[0]);
                _ = close(input_pipe[1]);
                return error.PipeFailed;
            }
        }
        if (separate_stderr and pipe(&errors_pipe) != 0) {
            _ = close(input_pipe[0]);
            _ = close(input_pipe[1]);
            _ = close(output_pipe[0]);
            _ = close(output_pipe[1]);
            return error.PipeFailed;
        }
        const pid = if (tty) forkpty(&master, null, null, null) else fork();
        if (pid == 0) {
            if (!tty) {
                if (dup2(input_pipe[0], 0) < 0 or dup2(output_pipe[1], 1) < 0 or dup2(if (separate_stderr) errors_pipe[1] else output_pipe[1], 2) < 0) _exit(127);
                _ = close(input_pipe[0]);
                _ = close(input_pipe[1]);
                _ = close(output_pipe[0]);
                _ = close(output_pipe[1]);
                if (separate_stderr) {
                    _ = close(errors_pipe[0]);
                    _ = close(errors_pipe[1]);
                }
            }
            if (ignore_interrupt) {
                const action: std.posix.Sigaction = .{ .handler = .{ .handler = std.posix.SIG.IGN }, .mask = std.mem.zeroes(std.posix.sigset_t), .flags = 0 };
                if (std.c.sigaction(.INT, &action, null) != 0) _exit(127);
                _ = write(1, "R", 1);
            }
            _ = execve(argv[0].?, argv.ptr, @ptrCast(env.items.ptr));
            _exit(127);
        }
        if (pid < 0) {
            if (!tty) {
                _ = close(input_pipe[0]);
                _ = close(input_pipe[1]);
                _ = close(output_pipe[0]);
                _ = close(output_pipe[1]);
            }
            if (separate_stderr) {
                _ = close(errors_pipe[0]);
                _ = close(errors_pipe[1]);
            }
            return error.ForkFailed;
        }
        if (tty) return .{ .pid = pid, .input = master, .output = master };
        _ = close(input_pipe[0]);
        _ = close(output_pipe[1]);
        if (separate_stderr) _ = close(errors_pipe[1]);
        if (ignore_interrupt) {
            var ready = [_]std.posix.pollfd{.{ .fd = output_pipe[0], .events = std.posix.POLL.IN, .revents = 0 }};
            var marker: [1]u8 = undefined;
            if ((std.posix.poll(&ready, 40000) catch 0) != 1 or (std.posix.read(output_pipe[0], &marker) catch 0) != 1 or marker[0] != 'R') {
                _ = kill(pid, @intFromEnum(std.posix.SIG.KILL));
                var status: c_int = 0;
                while (true) {
                    const result = waitpid(pid, &status, 0);
                    if (result >= 0 or std.c.errno(result) != .INTR) break;
                }
                _ = close(input_pipe[1]);
                _ = close(output_pipe[0]);
                return error.ChildStartupFailed;
            }
        }
        return .{ .pid = pid, .input = input_pipe[1], .output = output_pipe[0], .errors_fd = if (separate_stderr) errors_pipe[0] else -1 };
    }

    fn deinit(self: *Child) void {
        if (!self.reaped) {
            _ = kill(self.pid, @intFromEnum(std.posix.SIG.KILL));
            var status: c_int = 0;
            while (true) {
                const result = waitpid(self.pid, &status, 0);
                if (result >= 0 or std.c.errno(result) != .INTR) break;
            }
        }
        _ = close(self.input);
        if (self.output != self.input) _ = close(self.output);
        if (self.errors_fd >= 0) _ = close(self.errors_fd);
        self.errors.deinit(std.testing.allocator);
        self.pending.deinit(std.testing.allocator);
        self.transcript.deinit(std.testing.allocator);
    }
    fn send(self: *Child, bytes: []const u8) !void {
        var written: usize = 0;
        while (written < bytes.len) {
            const n = write(self.input, bytes.ptr + written, bytes.len - written);
            if (n < 0 and std.c.errno(n) == .INTR) continue;
            if (n <= 0) return error.WriteFailed;
            written += @intCast(n);
        }
    }
    fn receive(self: *Child, timeout: c_int) !bool {
        var p = [_]std.posix.pollfd{
            .{ .fd = self.output, .events = std.posix.POLL.IN, .revents = 0 },
            .{ .fd = self.errors_fd, .events = std.posix.POLL.IN, .revents = 0 },
        };
        const ready = try std.posix.poll(&p, timeout);
        if (ready == 0) return false;
        var buf: [4096]u8 = undefined;
        if (p[1].revents != 0) {
            const n = try std.posix.read(self.errors_fd, &buf);
            if (n == 0) {
                _ = close(self.errors_fd);
                self.errors_fd = -1;
            } else {
                if (self.errors.items.len + n > max_output) return error.OutputLimitExceeded;
                try self.errors.appendSlice(std.testing.allocator, buf[0..n]);
            }
        }
        if (p[0].revents == 0) return true;
        const n = std.posix.read(self.output, &buf) catch |err| switch (err) {
            error.InputOutput => return error.ChildClosedOutput,
            else => return err,
        };
        if (n == 0) return error.ChildClosedOutput;
        const data = buf[0..@intCast(n)];
        if (self.transcript.items.len + data.len > max_output) return error.OutputLimitExceeded;
        try self.transcript.appendSlice(std.testing.allocator, data);
        try self.pending.appendSlice(std.testing.allocator, data);
        return true;
    }
    fn until(self: *Child, marker: []const u8) !void {
        const deadline = try nowMs() + 40000;
        while (true) {
            if (std.mem.indexOf(u8, self.pending.items, marker)) |offset| {
                const consumed = offset + marker.len;
                std.mem.copyForwards(u8, self.pending.items, self.pending.items[consumed..]);
                self.pending.shrinkRetainingCapacity(self.pending.items.len - consumed);
                return;
            }
            const remaining = deadline - try nowMs();
            if (remaining <= 0 or !try self.receive(@intCast(remaining))) {
                std.debug.print("terminal probe timed out waiting for {s}; output:\n{s}\n", .{ marker, self.transcript.items });
                return error.TerminalTimeout;
            }
        }
    }
    fn wait(self: *Child, interrupt: bool) !c_int {
        const deadline = try nowMs() + 40000;
        while (try nowMs() < deadline) {
            var status: c_int = 0;
            const result = waitpid(self.pid, &status, std.posix.W.NOHANG);
            if (result == self.pid) {
                self.reaped = true;
                return status;
            }
            if (result < 0) {
                if (std.c.errno(result) == .INTR) continue;
                self.reaped = true;
                return error.WaitFailed;
            }
            if (interrupt) _ = kill(self.pid, @intFromEnum(std.posix.SIG.INT));
            // Drain pipes while waiting so children cannot block on output.
            _ = self.receive(50) catch |err| switch (err) {
                error.ChildClosedOutput => false,
                else => return err,
            };
        }
        return error.ChildTimeout;
    }
    fn quit(self: *Child) !void {
        try self.send(":quit\n");
        try std.testing.expectEqual(@as(c_int, 0), try self.wait(false));
    }
    fn resize(self: *Child, columns: u16) !void {
        var size: std.posix.winsize = .{ .row = 24, .col = columns, .xpixel = 0, .ypixel = 0 };
        if (std.c.ioctl(self.output, @as(c_int, @bitCast(@as(u32, std.posix.T.IOCSWINSZ))), &size) != 0)
            return error.TerminalResizeFailed;
    }
    fn line(self: *Child, text: []const u8, continuation: bool, spaces: usize) !void {
        try self.send(text);
        try self.send("\n");
        try self.until("\r\n");
        const marker = try std.fmt.allocPrint(std.testing.allocator, "\x1b[2K{s}{s}", .{ if (continuation) "... " else ">>> ", "        "[0..spaces] });
        defer std.testing.allocator.free(marker);
        try self.until(marker);
    }
};

fn contains(child: *const Child, needle: []const u8) !void {
    if (std.mem.indexOf(u8, child.transcript.items, needle) == null) {
        std.debug.print("missing terminal output {s}:\n{s}\n", .{ needle, child.transcript.items });
        return error.MissingTerminalOutput;
    }
}
fn executable() ![:0]u8 {
    const path = try support.installedArgiPath();
    defer std.testing.allocator.free(path);
    return std.testing.allocator.dupeZ(u8, path);
}

pub fn checkEditor() !void {
    if (builtin.os.tag == .windows) return error.SkipZigTest;
    const argi = try executable();
    defer std.testing.allocator.free(argi);
    {
        var repl = try Child.start(&.{ argi, "repl" }, true, true, false, false);
        defer repl.deinit();
        try repl.resize(24);
        try repl.until(">>> ");
        try repl.line("answer := () -> (.result: Int32 = 0) {", true, 4);
        try repl.line("if true {", true, 8);
        try repl.line("result = 42", true, 8);
        try repl.line("}", true, 4);
        try repl.line("}", false, 0);
        try contains(&repl, "\x1b[2K>>> <");
        try contains(&repl, "\x1b[2K...     }");
        try contains(&repl, "\x1b[2K... }");
        try contains(&repl, "\x1b[35mif\x1b[0m");
        try contains(&repl, "\x1b[33m42\x1b[0m");
        try repl.send("answer()\n");
        try repl.until("_0 = 42");
        try repl.until(">>> ");
        try repl.send("\x1b[A\n");
        try repl.until("_1 = 42");
        try repl.until(">>> ");
        try repl.line("unfinished := () -> () {", true, 4);
        try repl.send("\x03");
        try repl.until("^C");
        try repl.until(">>> ");
        try repl.resize(80);
        try repl.send("answer()\n");
        try repl.until("_2 = 42");
        try repl.until(">>> ");
        try repl.quit();
    }
    {
        var repl = try Child.start(&.{ argi, "repl" }, true, false, false, false);
        defer repl.deinit();
        try repl.until(">>> ");
        // Delete the middle digit through the real terminal input path.
        try repl.send("402\x1b[D\x1b[D\x1b[3~\n");
        try repl.until("_0 = 42");
        try repl.until(">>> ");
        try repl.resize(12);
        try repl.send("\"界a🙂\"\x1b[H\x1b[C\x1b[3~\n");
        try repl.until("_1 = \"a🙂\"");
        try repl.until(">>> ");
        try contains(&repl, "\x1b[s");
        try contains(&repl, "\x1b[u");
        try repl.quit();
        const text = repl.transcript.items;
        for (text, 0..) |byte, i| {
            if (byte != 0x1b or i + 1 >= text.len or text[i + 1] != '[') continue;
            var j = i + 2;
            while (j < text.len and (std.ascii.isDigit(text[j]) or text[j] == ';')) : (j += 1) {}
            if (j < text.len and text[j] == 'm') return error.UnexpectedColorEscape;
        }
    }
    {
        var repl = try Child.start(&.{ argi, "repl" }, false, null, false, true);
        defer repl.deinit();
        try repl.send("text ::= \"a\nb\"\ntext\n:quit\n");
        _ = close(repl.input);
        repl.input = -1;
        try std.testing.expectEqual(@as(c_int, 0), try repl.wait(false));
        // Consume output already buffered by the kernel after child exit.
        while (repl.receive(0) catch false) {}
        try contains(&repl, "_0 = \"a\\nb\"");
        try std.testing.expect(std.mem.indexOfScalar(u8, repl.transcript.items, 0x1b) == null);
    }
}

pub fn checkInterrupts() !void {
    if (builtin.os.tag == .windows) return error.SkipZigTest;
    const argi = try executable();
    defer std.testing.allocator.free(argi);
    {
        var vm = try Child.start(&.{ argi, "run", "--vm", "tests/feature_tests/execution/03X_vm_instruction_limit", "--frontend-jobs", "1", "--vm-instructions", "1000000000" }, false, null, true, false);
        defer vm.deinit();
        const status = try vm.wait(true);
        while (vm.receive(0) catch false) {}
        try std.testing.expectEqual(@as(c_int, 130 << 8), status);
        try contains(&vm, "ExecutionCancelled");
    }
    {
        var repl = try Child.start(&.{ argi, "repl", "--vm-instructions", "1000000000" }, true, null, false, false);
        defer repl.deinit();
        try repl.until(">>> ");
        try repl.send("unfinished := {\x03");
        try repl.until(">>> ");
        try repl.send(":begin\n");
        try repl.until("... ");
        for ([_][]const u8{ "print(\"VM_RUNNING\")\n", "Writer#().flush(.self = writer)\n", "while true {}\n" }) |line_text| {
            try repl.send(line_text);
            try repl.until("... ");
        }
        try repl.send(":end\n");
        try repl.until("\r\nVM_RUNNING\r\n");
        try repl.send("\x03");
        try repl.until("ExecutionCancelled");
        try repl.until(">>> ");
        try repl.send(":reset\n");
        try repl.until(">>> ");
        try repl.send("42\n");
        try repl.until("_0 = 42");
        try repl.until(">>> ");
        try repl.quit();
    }
}
