const std = @import("std");
const sf = @import("../1_base/source_files.zig");
const diag = @import("../1_base/diagnostic.zig");
const frontend = @import("frontend_pipeline.zig");
const interactive = @import("../execution/interactive.zig");
const repl_input = @import("repl_input.zig");
const value = @import("../5_codegen/bytecode/value.zig");

const prelude = @embedFile("repl_prelude.rg");

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
        std.debug.print("Usage: argi repl [--sysroot <path>] [execution limits]\nLimits: {s}\n{s}", .{ @import("execution_options.zig").help, help });
        return;
    }
    var options: sf.CoreResolutionOptions = .{ .environ_map = environ };
    var limits: @import("../execution/vm.zig").Limits = .{};
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        if (try @import("execution_options.zig").consume(&limits, args, &index)) continue;
        if (!std.mem.eql(u8, args[index], "--sysroot") or index + 1 >= args.len) return error.InvalidReplArguments;
        index += 1;
        options.explicit_sysroot = args[index];
    }
    // The frontend owns initial source/module views for the whole session.
    // The host grants only the explicit output adapters installed below.
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var files = try sf.collectCoreWithOptions(&allocator, io, options);
    defer sf.freeList(&allocator, &files);
    var diagnostics = diag.Diagnostics.init(&allocator, files.items);
    defer diagnostics.deinit();
    var pipeline = frontend.FrontendPipeline.init(allocator, io, &diagnostics, .{});
    defer pipeline.deinit();
    const prepared = pipeline.prepareSessionFiles(files.items) catch |err| {
        try diagnostics.dump();
        return err;
    };
    var session: interactive.Interactive = undefined;
    try session.initPrepared(std.heap.page_allocator, diagnostics.source_files, prepared, limits);
    defer session.deinit();
    try session.enableImports(io, ".");
    var input_buffer: [64 * 1024]u8 = undefined;
    var input = std.Io.File.stdin().reader(io, &input_buffer);
    var output_buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writer(io, &output_buffer);
    var error_output = std.Io.File.stderr().writer(io, &.{});
    defer error_output.interface.flush() catch {};
    var host_output = @import("repl_host.zig").Output{ .writer = &output.interface, .error_writer = &error_output.interface };
    const host_bindings = host_output.bindings();
    session.runtime.context.host_bindings = &host_bindings;
    const terminal = try std.Io.File.stdin().isTty(io) and try std.Io.File.stdout().isTty(io);
    session.initializePrelude(prelude) catch |err| {
        if (session.diagnostics.hasErrors()) try session.diagnostics.dump();
        return err;
    };
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
    if (terminal) {
        try output.writeAll("Argi experimental REPL. :help for commands.\n");
        try showPrelude(session, output);
    }
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
            session.reset() catch |err| {
                try report(session, output, err);
                continue;
            };
            if (terminal) try showPrelude(session, output);
        } else if (text[0] == ':') {
            try output.writeAll("Unknown REPL command; use :help.\n");
        } else {
            evaluate(session, output, line) catch |err| try report(session, output, err);
        }
    }
    if (multiline) try output.writeAll("Incomplete multiline submission discarded.\n");
}

fn showPrelude(session: *const interactive.Interactive, output: *std.Io.Writer) !void {
    if (session.prelude) |source| try output.print("Prelude:\n{s}\n", .{source});
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

test "REPL standard prelude prints ordinary text across reset" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var files = try sf.collectCoreWithOptions(&allocator, std.testing.io, .{ .fallback_core_dir = "core" });
    defer sf.freeList(&allocator, &files);
    var diagnostics = diag.Diagnostics.init(&allocator, files.items);
    defer diagnostics.deinit();
    var pipeline = frontend.FrontendPipeline.init(allocator, std.testing.io, &diagnostics, .{});
    defer pipeline.deinit();
    const prepared = try pipeline.prepareSessionFiles(files.items);
    var session: interactive.Interactive = undefined;
    try session.initPrepared(std.testing.allocator, diagnostics.source_files, prepared, .{});
    defer session.deinit();
    var output = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer output.deinit();
    var errors = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer errors.deinit();
    var host_output = @import("repl_host.zig").Output{ .writer = &output.writer, .error_writer = &errors.writer };
    const bindings = host_output.bindings();
    session.runtime.context.host_bindings = &bindings;
    session.initializePrelude(prelude) catch |err| {
        try session.diagnostics.dump();
        return err;
    };
    try session.submitStatements("print(\"hola\")");
    try std.testing.expectEqualStrings("hola\n", output.written());
    try session.reset();
    try session.submitStatements("print(\"ñ después\")");
    try std.testing.expectEqualStrings("hola\nñ después\n", output.written());
    try session.submitStatements("init_stderr(.p = $&_repl_terminal.stdout)\nprint(\"error output\")");
    try std.testing.expectEqualStrings("error output\n", errors.written());
    try std.testing.expectEqualStrings("hola\nñ después\n", output.written());
    session.close() catch |err| {
        try session.diagnostics.dump();
        return err;
    };
}

test "REPL configured instruction budget rejects execution and permits reset" {
    var session: interactive.Interactive = undefined;
    try session.init(std.testing.allocator, &.{}, .{ .exhaustive_function_bodies = false }, .{ .instructions = 0 });
    defer session.deinit();
    try std.testing.expectError(error.ExecutionInstructionLimit, session.submitStatements("value ::= 42"));
    try std.testing.expectEqual(.poisoned, session.runtime.context.state);
    try std.testing.expect(std.mem.indexOf(u8, session.diagnostics.list.items[0].msg, "ExecutionInstructionLimit") != null);
    try session.reset();
    try std.testing.expectEqual(.fresh, session.runtime.context.state);
    try std.testing.expectEqual(@as(usize, 0), session.limits.instructions);
    try std.testing.expectEqual(@as(usize, 0), session.compiler.semantic.resolvers.expressions.session_bindings.items.len);
}

test "REPL checked core allocations use virtual regions and explicit release" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var files = try sf.collectCoreWithOptions(&a, std.testing.io, .{ .fallback_core_dir = "core" });
    defer sf.freeList(&a, &files);
    var diagnostics = diag.Diagnostics.init(&a, files.items);
    defer diagnostics.deinit();
    var pipeline = frontend.FrontendPipeline.init(a, std.testing.io, &diagnostics, .{});
    defer pipeline.deinit();
    const prepared = try pipeline.prepareSessionFiles(files.items);
    var session: interactive.Interactive = undefined;
    try session.initPrepared(std.testing.allocator, diagnostics.source_files, prepared, .{});
    defer session.deinit();
    try session.submitStatements("assume ffi ::= $&ForeignFunctionInterface()");
    session.submitStatements("address ::= aligned_alloc(.alignment = 8, .size = 16).address") catch |err| {
        try session.diagnostics.dump();
        return err;
    };
    const raw = (try session.submitInput("address")).?.value.integer;
    try std.testing.expect(raw != 0);
    const range = try session.runtime.context.storage.acquisitions.resolveAddress(&session.runtime.context.storage, @intCast(raw), 16, 8);
    session.submitStatements("anchor :: UInt8 = 0\nraw ::= raw_pointer#(.t: Int32)(.address = address).raw\nreference ::= trusted_establish_inherited_reference#(.t: Int32)(.raw = raw, .root = erase_reference#(.t: UInt8)(.base = &anchor).reference).reference\nreference&= 42") catch |err| {
        try session.diagnostics.dump();
        return err;
    };
    try std.testing.expectEqual(@as(i128, 42), (try session.submitInput("reference&")).?.value.integer);
    try session.submitStatements("aligned_free(.address = address)");
    try std.testing.expectError(error.ExecutionReleasedAcquisition, session.runtime.context.storage.acquisitions.range(&session.runtime.context.storage, range.handle, 0, 0, 1));
    const revision = session.compiler.revision;
    try std.testing.expectError(error.Reported, session.submitInput("#run aligned_alloc(.alignment = 8, .size = 16)"));
    try std.testing.expectEqual(revision, session.compiler.revision);
    try std.testing.expectError(error.ExecutionReleasedAcquisition, session.submitStatements("aligned_free(.address = address)"));
    try std.testing.expectEqual(.poisoned, session.runtime.context.state);
    try session.reset();
    try session.close();
}
