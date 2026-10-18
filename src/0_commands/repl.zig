const std = @import("std");
const sf = @import("../1_base/source_files.zig");
const diag = @import("../1_base/diagnostic.zig");
const frontend = @import("frontend_pipeline.zig");
const interactive = @import("../execution/interactive.zig");
const repl_input = @import("repl_input.zig");
const value = @import("../5_codegen/bytecode/value.zig");

const help =
    \\Enter definitions, statements or expressions. Each line is one submission.
    \\Expression results remain available as _0, _1, ... until reset or exit.
    \\Up / Down      Recall previous input lines (terminal only)
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
    try session.enableImports(io, ".");
    var input_buffer: [64 * 1024]u8 = undefined;
    var input = std.Io.File.stdin().reader(io, &input_buffer);
    var output_buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writer(io, &output_buffer);
    const terminal = try std.Io.File.stdin().isTty(io) and try std.Io.File.stdout().isTty(io);
    try interact(&session, &input.interface, &output.interface, terminal);
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
    var editor: repl_input.Editor = .{ .allocator = session.allocator };
    defer editor.deinit();
    var multiline = false;
    if (terminal) try output.writeAll("Argi experimental REPL. :help for commands.\n");
    while (true) {
        try output.flush();
        const line = (if (terminal)
            try readTerminal(&editor, input, output, if (multiline) "... " else ">>> ")
        else
            try input.takeDelimiter('\n')) orelse break;
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

fn readTerminal(editor: *repl_input.Editor, input: *std.Io.Reader, output: *std.Io.Writer, prompt: []const u8) !?[]const u8 {
    const terminal = try repl_input.Terminal.enter();
    defer terminal.restore();
    return editor.read(input, output, prompt);
}

fn evaluate(session: *interactive.Interactive, output: *std.Io.Writer, source: []const u8) !void {
    if (try session.submitInput(source)) |result| {
        try output.print("{s} = ", .{result.name});
        const graph = &session.compiler.semantic.relocation.graph;
        if (@import("../4_semantics/global/types.zig").isStringView(graph, result.ty)) {
            const reference = result.value.record[0].reference;
            const length = std.math.cast(usize, result.value.record[1].integer) orelse return error.ExecutionInvalidReference;
            try output.writeByte('"');
            var scalars: usize = 0;
            for (0..length) |index| {
                const byte: u8 = @intCast((try session.runtime.context.storage.readOffset(reference, @intCast(index))).integer);
                if (byte & 0xc0 != 0x80) {
                    if (scalars == 256) {
                        try output.writeAll("...");
                        break;
                    }
                    scalars += 1;
                }
                switch (byte) {
                    '"' => try output.writeAll("\\\""),
                    '\\' => try output.writeAll("\\\\"),
                    '\n' => try output.writeAll("\\n"),
                    '\r' => try output.writeAll("\\r"),
                    '\t' => try output.writeAll("\\t"),
                    0...8, 11, 12, 14...31, 127 => try output.print("\\x{x:0>2}", .{byte}),
                    else => try output.writeByte(byte),
                }
            }
            try output.writeByte('"');
        } else try printValue(output, result.value, 0);
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
        .virtual_ => try output.writeAll("<virtual>"),
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

test "REPL presents persistent string literals as escaped text" {
    const allocator = std.testing.allocator;
    var sources = @import("../execution/submissions.zig").Sources.init(allocator);
    defer sources.deinit();
    var diagnostics = diag.Diagnostics.init(&allocator, &.{});
    defer diagnostics.deinit();
    const loaded = try sources.loadModule(&diagnostics, "StringView: Type = (._data: &UInt8, ._length: UIntNative)");
    var core = loaded.*;
    core.is_bundled_core = true;
    var session: interactive.Interactive = undefined;
    try session.initWithSources(allocator, diagnostics.source_files, &.{core}, .{ .exhaustive_function_bodies = false }, .{});
    defer session.deinit();
    var input = std.Io.Reader.fixed("\"hello\"\n_0\n\"ñ€\"\n\"\"\n:reset\n:quit\n");
    var output = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer output.deinit();
    try interact(&session, &input, &output.writer, false);
    try std.testing.expectEqualStrings("_0 = \"hello\"\n_1 = \"hello\"\n_2 = \"ñ€\"\n_3 = \"\"\n", output.written());
}
