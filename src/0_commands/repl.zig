const std = @import("std");
const sf = @import("../1_base/source_files.zig");
const diag = @import("../1_base/diagnostic.zig");
const frontend = @import("frontend_pipeline.zig");
const interactive = @import("../execution/interactive.zig");
const value = @import("../5_codegen/bytecode/value.zig");

const help =
    \\Enter definitions, statements or expressions. Each line is one submission.
    \\Expression results remain available as _0, _1, ... until reset or exit.
    \\:begin / :end  Submit a multiline definition or statement block
    \\:reset         Clean up and start a fresh session
    \\:quit          Clean up and exit
    \\:help          Show these commands
    \\
;

pub fn run(io: std.Io, environ: ?*const std.process.Environ.Map, args: []const []const u8) !void {
    if (args.len == 1 and std.mem.eql(u8, args[0], "--help")) {
        std.debug.print("Usage: argi repl [--sysroot <path>]\n{s}", .{help});
        return;
    }
    var options: sf.CoreResolutionOptions = .{ .environ_map = environ };
    if (args.len != 0) {
        if (args.len != 2 or !std.mem.eql(u8, args[0], "--sysroot")) return error.InvalidReplArguments;
        options.explicit_sysroot = args[1];
    }
    // The frontend owns initial source/module views for the whole session.
    // Runtime capabilities and native calls are not granted by this host loop.
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var files = try sf.collectCoreWithOptions(&allocator, io, options);
    defer sf.freeList(&allocator, &files);
    var diagnostics = diag.Diagnostics.init(&allocator, files.items);
    defer diagnostics.deinit();
    var pipeline = frontend.FrontendPipeline.init(allocator, io, &diagnostics, .{});
    defer pipeline.deinit();
    const modules = pipeline.prepareModuleFiles(files.items) catch |err| {
        try diagnostics.dump();
        return err;
    };
    var session: interactive.Interactive = undefined;
    try session.initWithSources(std.heap.page_allocator, files.items, modules, .{ .exhaustive_function_bodies = false }, .{});
    defer session.deinit();
    var input_buffer: [64 * 1024]u8 = undefined;
    var input = std.Io.File.stdin().reader(io, &input_buffer);
    var output_buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writer(io, &output_buffer);
    try interact(&session, &input.interface, &output.interface, try std.Io.File.stdin().isTty(io));
}

/// Transport loop only. Parsing, resolution, safety, publication and execution
/// stay in the shared interactive controller, independent of terminal I/O.
fn interact(session: *interactive.Interactive, input: *std.Io.Reader, output: *std.Io.Writer, terminal: bool) !void {
    const read_result = readSubmissions(session, input, output, terminal);
    // Trapped execution cannot safely unwind user code. Retire its poisoned
    // context before closing. Healthy sessions also clean up on transport error.
    if (session.runtime.context.state == .poisoned) try session.reset();
    try session.close();
    try read_result;
    try output.flush();
}

fn readSubmissions(session: *interactive.Interactive, input: *std.Io.Reader, output: *std.Io.Writer, terminal: bool) !void {
    var block: std.ArrayList(u8) = .empty;
    defer block.deinit(session.allocator);
    var multiline = false;
    if (terminal) try output.writeAll("Argi experimental REPL. :help for commands.\n");
    while (true) {
        if (terminal) try output.writeAll(if (multiline) "... " else ">>> ");
        try output.flush();
        const line = (try input.takeDelimiter('\n')) orelse break;
        const text = std.mem.trim(u8, line, " \t\r");
        if (multiline) {
            if (std.mem.eql(u8, text, ":end")) {
                multiline = false;
                evaluate(session, output, block.items) catch |err| try report(session, output, err);
                block.clearRetainingCapacity();
            } else {
                if (block.items.len + line.len > 1024 * 1024) return error.SubmissionTooLarge;
                try block.appendSlice(session.allocator, line);
                try block.append(session.allocator, '\n');
            }
            continue;
        }
        if (text.len == 0) continue;
        session.diagnostics.list.clearRetainingCapacity();
        if (std.mem.eql(u8, text, ":quit")) break;
        if (std.mem.eql(u8, text, ":help")) {
            try output.writeAll(help);
        } else if (std.mem.eql(u8, text, ":begin")) {
            multiline = true;
        } else if (std.mem.eql(u8, text, ":reset")) {
            session.reset() catch |err| try report(session, output, err);
        } else if (text[0] == ':') {
            try output.writeAll("Unknown REPL command; use :help.\n");
        } else {
            evaluate(session, output, line) catch |err| try report(session, output, err);
        }
    }
    if (multiline) try output.writeAll("Incomplete multiline submission discarded.\n");
}

fn evaluate(session: *interactive.Interactive, output: *std.Io.Writer, source: []const u8) !void {
    if (try session.submitInput(source)) |result| {
        try output.print("{s} = ", .{result.name});
        try printValue(output, result.value, 0);
        try output.writeByte('\n');
    }
}

fn report(session: *interactive.Interactive, output: *std.Io.Writer, err: anyerror) !void {
    if (session.diagnostics.hasErrors()) {
        try output.flush();
        try session.diagnostics.dump();
    } else try output.print("Error: {s}\n", .{@errorName(err)});
}

fn printValue(output: *std.Io.Writer, item: value.Value, depth: usize) std.Io.Writer.Error!void {
    if (depth >= 16) return output.writeAll("...");
    switch (item) {
        .integer => |number| try output.print("{d}", .{number}),
        .boolean => |boolean| try output.writeAll(if (boolean) "true" else "false"),
        .unit => try output.writeAll("()"),
        .reference => try output.writeAll("<reference>"),
        .record, .array => |elements| {
            try output.writeByte(if (item == .record) '(' else '[');
            for (elements, 0..) |element, index| {
                if (index != 0) try output.writeAll(", ");
                if (index == 32) {
                    try output.writeAll("...");
                    break;
                }
                try printValue(output, element, depth + 1);
            }
            try output.writeByte(if (item == .record) ')' else ']');
        },
        .choice => |choice| {
            try output.print("<variant {d}", .{choice.variant});
            if (choice.payload) |payload| {
                try output.writeAll(": ");
                try printValue(output, payload.*, depth + 1);
            }
            try output.writeByte('>');
        },
    }
}

test "REPL transport executes multiline definitions expressions and checked reset" {
    var session: interactive.Interactive = undefined;
    try session.init(std.testing.allocator, &.{}, .{ .exhaustive_function_bodies = false }, .{});
    defer session.deinit();
    var input = std.Io.Reader.fixed(
        ":begin\n" ++
            "answer := () -> (.result: Int32) {\n" ++
            "    result = 42\n" ++
            "}\n" ++
            ":end\n" ++
            "value ::= answer()\n" ++
            "value\n" ++
            ":reset\n" ++
            "7\n" ++
            ":quit\n",
    );
    var output = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer output.deinit();
    try interact(&session, &input, &output.writer, false);
    try std.testing.expectEqualStrings("_0 = 42\n_0 = 7\n", output.written());
    try std.testing.expect(session.closed);
    try std.testing.expectEqual(.fresh, session.runtime.context.state);
}

test "REPL transport requires reset after a runtime trap" {
    var session: interactive.Interactive = undefined;
    try session.init(std.testing.allocator, &.{}, .{ .exhaustive_function_bodies = false }, .{});
    defer session.deinit();
    var input = std.Io.Reader.fixed("abort\n1\n:reset\n2\n:quit\n");
    var output = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer output.deinit();
    try interact(&session, &input, &output.writer, false);
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "ExecutionContextPoisoned") != null);
    try std.testing.expect(std.mem.endsWith(u8, output.written(), "_0 = 2\n"));
    try std.testing.expect(session.closed);
}
