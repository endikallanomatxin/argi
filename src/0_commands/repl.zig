const std = @import("std");
const builtin = @import("builtin");
const sf = @import("../1_base/source_files.zig");
const diag = @import("../1_base/diagnostic.zig");
const frontend = @import("frontend_pipeline.zig");
const interactive = @import("../execution/interactive.zig");
const vm = @import("../execution/vm.zig");
const repl_input = @import("repl_input.zig");
const repl_console = @import("repl_console.zig");
const value = @import("../5_codegen/bytecode/value.zig");

const prelude = @embedFile("repl_prelude.rg");

const help =
    \\Enter definitions, statements or expressions. Open delimiters continue on the next line.
    \\Expression results remain available as _0, _1, ... until reset or exit.
    \\Terminal input uses syntax colors and automatic brace indentation.
    \\Set NO_COLOR to disable colors.
    \\Up / Down      Recall previous input lines (terminal only)
    \\Ctrl+C         Discard pending input or cancel execution (then use :reset)
    \\:begin / :end  Submit a multiline definition or statement block
    \\:cancel        Discard the pending submission
    \\:reset         Clean up and start a fresh session
    \\:quit          Clean up and exit
    \\:help          Show these commands
    \\
;

pub fn run(backing_allocator: std.mem.Allocator, io: std.Io, environ: ?*const std.process.Environ.Map, args: []const []const u8) !void {
    if (args.len == 1 and std.mem.eql(u8, args[0], "--help")) {
        std.debug.print("Usage: argi repl [--sysroot <path>] [execution limits]\nLimits: {s}\n{s}", .{ @import("execution_options.zig").help, help });
        return;
    }
    var options: sf.CoreResolutionOptions = .{ .environ_map = environ };
    var limits: vm.Limits = .{};
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        if (try @import("execution_options.zig").consume(&limits, args, &index)) continue;
        if (!std.mem.eql(u8, args[index], "--sysroot") or index + 1 >= args.len) return error.InvalidReplArguments;
        index += 1;
        options.explicit_sysroot = args[index];
    }
    // The frontend owns initial source/module views for the whole session.
    // The host grants only the explicit output adapters installed below.
    var arena = std.heap.ArenaAllocator.init(backing_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var files = try sf.collectCoreWithOptions(&allocator, io, options);
    defer sf.freeList(&allocator, &files);
    var diagnostics = try diag.Diagnostics.init(&allocator, files.items);
    defer diagnostics.deinit();
    var pipeline = frontend.FrontendPipeline.init(allocator, io, &diagnostics, .{});
    defer pipeline.deinit();
    const prepared = pipeline.prepareSessionFiles(files.items) catch |err| {
        try diagnostics.dump();
        return err;
    };
    var session: interactive.Interactive = undefined;
    const interrupts = try @import("execution_interrupt.zig").Guard.init();
    defer interrupts.deinit();
    limits.cancellation = interrupts.token();
    try session.initPrepared(backing_allocator, diagnostics.source_files, prepared, limits);
    defer session.deinit();
    try session.enableImports(io, ".");
    const input_terminal = try std.Io.File.stdin().isTty(io);
    const output_terminal = try std.Io.File.stdout().isTty(io);
    const terminal = input_terminal and output_terminal;
    const console_encoding: ?repl_console.OutputEncoding = if (builtin.os.tag == .windows and (output_terminal or try std.Io.File.stderr().isTty(io))) try repl_console.OutputEncoding.enter() else null;
    defer if (console_encoding) |saved| saved.restore();
    var input_buffer: [64 * 1024]u8 = undefined;
    var input = std.Io.File.stdin().reader(io, &input_buffer);
    var console_input: repl_console.Input = undefined;
    const input_reader = if (builtin.os.tag == .windows) console: {
        if (!input_terminal) break :console &input.interface;
        console_input = .init(std.Io.File.stdin().handle, &input_buffer);
        break :console &console_input.interface;
    } else &input.interface;
    var output_buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writerStreaming(io, &output_buffer);
    defer output.interface.flush() catch {};
    var error_output = std.Io.File.stderr().writerStreaming(io, &.{});
    defer error_output.interface.flush() catch {};
    var host_output = @import("../execution/host_output.zig").Output{ .writer = &output.interface, .error_writer = &error_output.interface };
    const host_bindings = host_output.bindings();
    session.runtime.context.host_bindings = &host_bindings;
    session.initializePrelude(prelude) catch |err| {
        if (session.diagnostics.hasErrors()) try session.diagnostics.dump();
        return err;
    };
    const colors = terminal and if (environ) |env|
        !env.contains("NO_COLOR") and !std.mem.eql(u8, env.get("TERM") orelse "", "dumb")
    else
        true;
    try interact(&session, input_reader, &output.interface, terminal, colors, interrupts.token());
}

/// Transport loop only. Parsing, resolution, safety, publication and execution
/// stay in the shared interactive controller, independent of terminal I/O.
fn interact(session: *interactive.Interactive, input: *std.Io.Reader, output: *std.Io.Writer, terminal: bool, colors: bool, cancellation: ?*vm.Cancellation) !void {
    const read_result = readSubmissions(session, input, output, terminal, colors, cancellation);
    // Trapped execution cannot safely unwind user code. Retire its poisoned
    // context before closing. Healthy sessions also clean up on transport error.
    if (cancellation) |token| token.reset();
    if (session.runtime.context.state == .poisoned) try session.reset();
    try session.close();
    try read_result;
    try output.flush();
}

fn readSubmissions(session: *interactive.Interactive, input: *std.Io.Reader, output: *std.Io.Writer, terminal: bool, colors: bool, cancellation: ?*vm.Cancellation) !void {
    var block: std.ArrayList(u8) = .empty;
    defer block.deinit(session.allocator);
    var editor: repl_input.Editor = .{ .allocator = session.allocator, .highlight = colors };
    defer editor.deinit();
    var multiline = false;
    var automatic = false;
    var completion: @import("../1_base/lexical.zig").Completion = .{};
    if (terminal) {
        try output.writeAll("Argi experimental REPL. :help for commands.\n");
        try showPrelude(session, output);
    }
    while (true) {
        try output.flush();
        editor.context = if (multiline) completion else .{};
        const line = (if (terminal)
            try readTerminal(&editor, input, output, if (multiline) "... " else ">>> ")
        else
            try input.takeDelimiter('\n')) orelse break;
        const text = std.mem.trim(u8, line, " \t\r");
        if ((terminal and editor.cancelled) or std.mem.eql(u8, text, ":cancel")) {
            block.clearRetainingCapacity();
            multiline = false;
            automatic = false;
            completion = .{};
            continue;
        }
        if (multiline) {
            if (std.mem.eql(u8, text, ":end")) {
                multiline = false;
                evaluate(session, output, block.items) catch |err| try report(session, output, err);
                block.clearRetainingCapacity();
            } else {
                if (block.items.len + line.len > 1024 * 1024) return error.SubmissionTooLarge;
                try block.appendSlice(session.allocator, line);
                try block.append(session.allocator, '\n');
                completion.feedLine(line);
                if (automatic) {
                    if (completion.complete()) {
                        multiline = false;
                        automatic = false;
                        evaluate(session, output, block.items) catch |err| try report(session, output, err);
                        block.clearRetainingCapacity();
                    }
                }
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
            automatic = false;
            completion = .{};
        } else if (std.mem.eql(u8, text, ":reset")) {
            if (cancellation) |token| token.reset();
            session.reset() catch |err| {
                try report(session, output, err);
                continue;
            };
            if (terminal) try showPrelude(session, output);
        } else if (text[0] == ':') {
            try output.writeAll("Unknown REPL command; use :help.\n");
        } else {
            completion = .{};
            completion.feedLine(line);
            if (!completion.complete()) {
                multiline = true;
                automatic = true;
                try block.appendSlice(session.allocator, line);
                try block.append(session.allocator, '\n');
            } else evaluate(session, output, line) catch |err| try report(session, output, err);
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
    editor.measure_terminal = true;
    return editor.read(input, output, prompt);
}

fn evaluate(session: *interactive.Interactive, output: *std.Io.Writer, source: []const u8) !void {
    if (try session.submitInput(source)) |result| {
        try output.print("{s} = ", .{result.name});
        const graph = &session.compiler.semantic.relocation.graph;
        if (result.value == .type_) {
            const ty = result.value.type_;
            var text = std.array_list.Managed(u8).init(session.allocator);
            defer text.deinit();
            try @import("../4_semantics/global/semantizer.zig").appendTypeName(&text, graph, ty);
            try output.writeAll(text.items);
        } else if (@import("../4_semantics/global/types.zig").isStringView(graph, result.ty)) {
            const reference = result.value.runtime.record[0].reference;
            const length = std.math.cast(usize, result.value.runtime.record[1].integer) orelse return error.ExecutionInvalidReference;
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
        } else try printValue(output, graph, result.ty, result.value.runtime, 0);
        try output.writeByte('\n');
    }
}

fn report(session: *interactive.Interactive, output: *std.Io.Writer, err: anyerror) !void {
    if (session.diagnostics.hasErrors()) {
        try output.flush();
        try session.diagnostics.dump();
    } else try output.print("Error: {s}\n", .{@errorName(err)});
}

fn printValue(output: *std.Io.Writer, graph: *const @import("../4_semantics/global/graph.zig").GlobalSemanticGraph, ty: @import("../4_semantics/global/graph.zig").GlobalTypeId, item: value.Value, depth: usize) std.Io.Writer.Error!void {
    if (depth >= 16) return output.writeAll("...");
    switch (item) {
        .integer => |number| try output.print("{d}", .{@import("../5_codegen/integer_arithmetic.zig").decode(number, @import("../5_codegen/bytecode/bytecode.zig").integerBounds(graph, ty).?)}),
        inline .float16, .float32, .float64 => |number| try output.print("{d}", .{number}),
        .boolean => |boolean| try output.writeAll(if (boolean) "true" else "false"),
        .unit => try output.writeAll("()"),
        .erased => try output.writeAll("<opaque>"),
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
                const types = @import("../4_semantics/global/types.zig");
                const element_ty = if (item == .array) types.arrayElement(graph, ty).? else graph.fields.items[types.fields(graph, ty).?.start + index].ty;
                if (item == .record) {
                    const field = graph.fields.items[types.fields(graph, ty).?.start + index];
                    const name = graph.text(field.name);
                    if (name.len != 0) try output.print(".{s} = ", .{name});
                }
                try printValue(output, graph, element_ty, element, depth + 1);
            }
            try output.writeByte(if (item == .record) ')' else ']');
        },
        .choice => |choice| {
            const variants = @import("../4_semantics/global/types.zig").variants(graph, ty).?;
            const selected = graph.variants.items[variants.start + choice.variant];
            try output.print("..{s}", .{graph.text(selected.name)});
            if (choice.payload) |payload| {
                if (payload.* != .record) try output.writeByte('(');
                try printValue(output, graph, selected.payload_type.?, payload.*, depth + 1);
                if (payload.* != .record) try output.writeByte(')');
            }
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
    try interact(&session, &input, &output.writer, false, false, null);
    try std.testing.expectEqualStrings("_0 = 42\n_0 = 7\n", output.written());
    try std.testing.expect(session.closed);
    try std.testing.expectEqual(.fresh, session.runtime.context.state);
}

test "REPL transport clears cancellation before explicit reset and exit" {
    var cancellation: vm.Cancellation = .{};
    var session: interactive.Interactive = undefined;
    try session.init(std.testing.allocator, &.{}, .{ .exhaustive_function_bodies = false }, .{ .cancellation = &cancellation });
    defer session.deinit();
    cancellation.cancel();
    var input = std.Io.Reader.fixed("1\n:reset\n2\n:quit\n");
    var output = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer output.deinit();
    try interact(&session, &input, &output.writer, false, false, &cancellation);
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "_0 = 2\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "_0 = 1\n") == null);
    try std.testing.expect(!cancellation.isCancelled());
    try std.testing.expect(session.closed);
    try std.testing.expectEqual(.fresh, session.runtime.context.state);
}

test "REPL integer presentation uses slot and aggregate field types" {
    var session: interactive.Interactive = undefined;
    try session.init(std.testing.allocator, &.{}, .{ .exhaustive_function_bodies = false }, .{});
    defer session.deinit();
    var input = std.Io.Reader.fixed(
        "negative :: Int8 = -1\n" ++
            "large :: UInt64 = 18446744073709551615\n" ++
            "negative\nlarge\n" ++
            "pair :: (.small: Int8, .large: UInt64) = (.small = negative, .large = large)\n" ++
            "pair\n:quit\n",
    );
    var output = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer output.deinit();
    try interact(&session, &input, &output.writer, false, false, null);
    try std.testing.expectEqualStrings("_0 = -1\n_1 = 18446744073709551615\n_2 = (.small = -1, .large = 18446744073709551615)\n", output.written());
}

test "REPL presentation names nested variants and fields without reading references" {
    var session: interactive.Interactive = undefined;
    try session.init(std.testing.allocator, &.{}, .{ .exhaustive_function_bodies = false }, .{});
    defer session.deinit();
    var input = std.Io.Reader.fixed(
        "State := (..ready(.count: UInt8), ..empty)\n" ++
            "state :: State = ..ready(.count = 7)\n" ++
            "state\n" ++
            "state = ..empty\nstate\n" ++
            "number :: Int32 = 42\n" ++
            "record :: (.state: State, .numbers: [2]Int32, .link: &Int32) = (.state = state, .numbers = (1, 2), .link = &number)\n" ++
            "record\n:quit\n",
    );
    var output = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer output.deinit();
    try interact(&session, &input, &output.writer, false, false, null);
    try std.testing.expectEqualStrings(
        "_0 = ..ready(.count = 7)\n_1 = ..empty\n" ++
            "_2 = (.state = ..empty, .numbers = [1, 2], .link = <reference>)\n",
        output.written(),
    );
}

test "REPL aggregate presentation remains bounded" {
    const a = std.testing.allocator;
    var graph: @import("../4_semantics/global/graph.zig").GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    try graph.types.appendSlice(a, &.{
        .{ .builtin = .Int32 },
        .{ .array = .{ .element = @enumFromInt(0), .length = 33 } },
    });
    const elements = [_]value.Value{.{ .integer = 7 }} ** 33;
    var output = std.Io.Writer.Allocating.init(a);
    defer output.deinit();
    try printValue(&output.writer, &graph, @enumFromInt(1), .{ .array = &elements }, 0);
    try std.testing.expectEqual(@as(usize, 32), std.mem.count(u8, output.written(), "7"));
    try std.testing.expect(std.mem.endsWith(u8, output.written(), ", ...]"));
    output.clearRetainingCapacity();
    try printValue(&output.writer, &graph, @enumFromInt(1), .{ .array = &elements }, 16);
    try std.testing.expectEqualStrings("...", output.written());
}

test "REPL transport requires reset after a runtime trap" {
    var session: interactive.Interactive = undefined;
    try session.init(std.testing.allocator, &.{}, .{ .exhaustive_function_bodies = false }, .{});
    defer session.deinit();
    var input = std.Io.Reader.fixed("abort\n1\n:reset\n2\n:quit\n");
    var output = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer output.deinit();
    try interact(&session, &input, &output.writer, false, false, null);
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "ExecutionContextPoisoned") != null);
    try std.testing.expect(std.mem.endsWith(u8, output.written(), "_0 = 2\n"));
    try std.testing.expect(session.closed);
}

test "REPL presents persistent string literals as escaped text" {
    const allocator = std.testing.allocator;
    var sources = @import("../execution/submissions.zig").Sources.init(allocator);
    defer sources.deinit();
    var diagnostics = try diag.Diagnostics.init(&allocator, &.{});
    defer diagnostics.deinit();
    const loaded = try sources.loadModule(&diagnostics, "StringView := (._data: &UInt8, ._length: UIntNative)");
    var core = loaded.*;
    core.is_bundled_core = true;
    var session: interactive.Interactive = undefined;
    try session.initWithSources(allocator, diagnostics.source_files, &.{core}, .{ .exhaustive_function_bodies = false }, .{});
    defer session.deinit();
    var input = std.Io.Reader.fixed("\"hello\"\n_0\n\"ñ€\"\n\"\"\n:reset\n:quit\n");
    var output = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer output.deinit();
    try interact(&session, &input, &output.writer, false, false, null);
    try std.testing.expectEqualStrings("_0 = \"hello\"\n_1 = \"hello\"\n_2 = \"ñ€\"\n_3 = \"\"\n", output.written());
}

test "REPL standard prelude supplies output and persistent allocation across reset" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var files = try sf.collectCoreWithOptions(&allocator, std.testing.io, .{ .fallback_core_dir = "core" });
    defer sf.freeList(&allocator, &files);
    var diagnostics = try diag.Diagnostics.init(&allocator, files.items);
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
    var host_output = @import("../execution/host_output.zig").Output{ .writer = &output.writer, .error_writer = &errors.writer };
    const bindings = host_output.bindings();
    session.runtime.context.host_bindings = &bindings;
    session.initializePrelude(prelude) catch |err| {
        try session.diagnostics.dump();
        return err;
    };
    try session.submitStatements("print(\"hola\")");
    try std.testing.expectEqualStrings("hola\n", output.written());
    session.submitStatements("text ::= unwrap_or_abort(.value = String(.length = 3))") catch |err| {
        try session.diagnostics.dump();
        return err;
    };
    try std.testing.expectEqual(@as(usize, 1), session.runtime.context.storage.acquisitions.entries.items.len);
    try std.testing.expect(session.runtime.context.storage.acquisitions.entries.items[0].live);
    try session.submitStatements("deinit(.self = $&text)");
    try std.testing.expect(!session.runtime.context.storage.acquisitions.entries.items[0].live);
    try session.submitStatements("retained ::= unwrap_or_abort(.value = String(.length = 2))");
    try std.testing.expect(session.runtime.context.storage.acquisitions.entries.items[1].live);
    try session.reset();
    try std.testing.expectEqual(@as(usize, 0), session.runtime.context.storage.acquisitions.entries.items.len);
    try session.submitStatements("after_reset ::= unwrap_or_abort(.value = String(.length = 4))");
    try std.testing.expect(session.runtime.context.storage.acquisitions.entries.items[0].live);
    session.submitStatements("numbers ::= unwrap_or_abort(.value = DynamicArray#(.t: Int32)(.capacity = 2))\npush_assume_capacity(.self = $&numbers, .value = 42)") catch |err| {
        try session.diagnostics.dump();
        return err;
    };
    try std.testing.expectEqual(@as(u64, 42), (try session.submitInput("unwrap_or_abort(.value = get(.self = &numbers, .index = 0))")).?.value.runtime.integer);
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
    var diagnostics = try diag.Diagnostics.init(&a, files.items);
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
    session.submitStatements("assume error_tracer ::= $&noop_error_tracer\nallocator ::= CAllocator(.ffi = ffi)\n{ result ::= allocate_bytes(.self = $&allocator, .size = 16, .alignment = 8)\nmatch result { ..error _ { abort } ..ok ~memory {} } }") catch |err| {
        try session.diagnostics.dump();
        return err;
    };
    // The block's ordinary Allocation cleanup releases only its own region.
    const regions = session.runtime.context.storage.acquisitions.entries.items;
    try std.testing.expectEqual(@as(usize, 2), regions.len);
    try std.testing.expect(regions[0].live);
    try std.testing.expect(!regions[1].live);
    const raw = (try session.submitInput("address")).?.value.runtime.integer;
    try std.testing.expect(raw != 0);
    const range = try session.runtime.context.storage.acquisitions.resolveAddress(&session.runtime.context.storage, @intCast(raw), 16, 8);
    session.submitStatements("anchor :: UInt8 = 0\nraw ::= raw_pointer#(.t: Int32)(.address = address).raw\nreference ::= trusted_establish_inherited_reference#(.t: Int32)(.raw = raw, .root = erase_reference#(.t: UInt8)(.base = &anchor).reference).reference\nreference&= 42") catch |err| {
        try session.diagnostics.dump();
        return err;
    };
    try std.testing.expectEqual(@as(i128, 42), (try session.submitInput("reference&")).?.value.runtime.integer);
    try session.submitStatements("aligned_free(.address = address)");
    try std.testing.expectError(error.ExecutionReleasedAcquisition, session.runtime.context.storage.acquisitions.range(&session.runtime.context.storage, range.handle, 0, 0, 1));
    const revision = session.compiler.revision;
    try std.testing.expectError(error.Reported, session.submitInput("#run () -> (.address: UIntNative) { address = aligned_alloc(.alignment = 8, .size = 16).address }"));
    try std.testing.expectEqual(revision, session.compiler.revision);
    try std.testing.expectError(error.ExecutionReleasedAcquisition, session.submitStatements("aligned_free(.address = address)"));
    try std.testing.expectEqual(.poisoned, session.runtime.context.state);
    try session.reset();
    try session.close();
}

test "REPL resource-bearing prelude survives failed reset and releases poisoned storage" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var files = try sf.collectCoreWithOptions(&allocator, std.testing.io, .{ .fallback_core_dir = "core" });
    defer sf.freeList(&allocator, &files);
    var diagnostics = try diag.Diagnostics.init(&allocator, files.items);
    defer diagnostics.deinit();
    var pipeline = frontend.FrontendPipeline.init(allocator, std.testing.io, &diagnostics, .{});
    defer pipeline.deinit();
    const prepared = try pipeline.prepareSessionFiles(files.items);
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    var session: interactive.Interactive = undefined;
    try session.initPrepared(failing.allocator(), diagnostics.source_files, prepared, .{});
    var deinitialized = false;
    defer if (!deinitialized) session.deinit();
    var output = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer output.deinit();
    var errors = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer errors.deinit();
    var host_output = @import("../execution/host_output.zig").Output{ .writer = &output.writer, .error_writer = &errors.writer };
    const bindings = host_output.bindings();
    session.runtime.context.host_bindings = &bindings;

    const owning_prelude = prelude ++ "\nowned ::= unwrap_or_abort(.value = String(.length = 8))\n";
    try std.testing.expectError(error.ExecutionAborted, session.initializePrelude(owning_prelude ++ "abort\n"));
    try std.testing.expect(session.prelude == null);
    try std.testing.expectEqual(.poisoned, session.runtime.context.state);
    try std.testing.expectEqual(@as(usize, 1), session.runtime.context.storage.acquisitions.entries.items.len);
    try std.testing.expect(session.runtime.context.storage.acquisitions.entries.items[0].live);
    const failed_revision = session.compiler.revision;
    try std.testing.expectError(error.ExecutionContextPoisoned, session.submitStatements("print(\"unavailable\")"));
    try std.testing.expectEqual(failed_revision, session.compiler.revision);
    try std.testing.expectEqualStrings("", output.written());

    // Reset discards the trapped context without executing user destructors.
    try session.reset();
    try std.testing.expectEqual(.fresh, session.runtime.context.state);
    var unavailable_output: std.Io.Writer = .failing;
    for ([_]bool{ false, true }) |host_failure| {
        session.limits.instructions = 100_000;
        if (host_failure) host_output.writer = &unavailable_output;
        const source = if (host_failure)
            owning_prelude ++ "unwrap_or_abort(.value = print(\"unavailable\"))\n"
        else
            owning_prelude ++ "while true {}\n";
        try std.testing.expectError(
            if (host_failure) error.ExecutionAborted else error.ExecutionInstructionLimit,
            session.initializePrelude(source),
        );
        try std.testing.expect(session.prelude == null);
        try std.testing.expectEqual(.poisoned, session.runtime.context.state);
        try std.testing.expectEqual(@as(usize, 1), session.runtime.context.storage.acquisitions.entries.items.len);
        try std.testing.expect(session.runtime.context.storage.acquisitions.entries.items[0].live);
        const trapped_revision = session.compiler.revision;
        try std.testing.expectError(error.ExecutionContextPoisoned, session.submitStatements("owned"));
        try std.testing.expectEqual(trapped_revision, session.compiler.revision);
        session.limits.instructions = 1_000_000;
        host_output.writer = &output.writer;
        try session.reset();
        try std.testing.expectEqual(.fresh, session.runtime.context.state);
        try std.testing.expectEqualStrings("", output.written());
    }
    try session.initializePrelude(owning_prelude);
    try std.testing.expect(session.runtime.context.storage.acquisitions.entries.items[0].live);
    const namespace = session.compiler.namespace;
    const revision = session.compiler.revision;
    const accepted_graph = session.compiler.semantic.relocation.graph.checkpoint();
    failing.fail_index = failing.alloc_index;
    try std.testing.expectError(error.OutOfMemory, session.compiler.beginPreparation(&session.diagnostics));
    failing.fail_index = std.math.maxInt(usize);
    try std.testing.expectEqualDeep(accepted_graph, session.compiler.semantic.relocation.graph.checkpoint());
    try std.testing.expectEqual(revision, session.compiler.revision);
    try std.testing.expectEqual(.ready, session.runtime.context.state);
    try std.testing.expect(session.runtime.context.storage.acquisitions.entries.items[0].live);
    {
        var retry = try session.compiler.beginPreparation(&session.diagnostics);
        defer retry.deinit();
    }
    try std.testing.expectEqualDeep(accepted_graph, session.compiler.semantic.relocation.graph.checkpoint());
    var rejected_preparations: usize = 0;
    for ([_]usize{ 0, 1, 8, 32, 128, 512 }) |offset| {
        const saved_sources = try session.sources.beginBatch(&session.diagnostics);
        defer session.sources.rollbackBatch(&session.diagnostics, saved_sources);
        const pending = try session.sources.loadCommand(&session.diagnostics, "trial ::= unwrap_or_abort(.value = String(.length = 3))");
        const modules = try session.sources.appendModuleViews(session.compiler.semantic.modules, pending.module);
        const function: @import("../4_semantics/global/graph.zig").GlobalFunctionId = @enumFromInt(session.compiler.semantic.relocation.graph.functions.items.len + @intFromEnum(pending.function));
        failing.fail_index = failing.alloc_index + offset;
        {
            defer failing.fail_index = std.math.maxInt(usize);
            if (session.compiler.prepareContinuation(modules, &session.diagnostics, function)) |prepared_candidate| {
                var candidate = prepared_candidate;
                candidate.deinit();
            } else |err| {
                try std.testing.expectEqual(error.OutOfMemory, err);
                rejected_preparations += 1;
            }
        }
        try std.testing.expectEqualDeep(accepted_graph, session.compiler.semantic.relocation.graph.checkpoint());
        try std.testing.expectEqual(revision, session.compiler.revision);
        try std.testing.expectEqual(.ready, session.runtime.context.state);
        try std.testing.expect(session.runtime.context.storage.acquisitions.entries.items[0].live);
    }
    try std.testing.expect(rejected_preparations != 0);
    failing.fail_index = failing.alloc_index;
    try std.testing.expectError(error.OutOfMemory, session.reset());
    failing.fail_index = std.math.maxInt(usize);
    try std.testing.expectEqual(namespace, session.compiler.namespace);
    try std.testing.expectEqual(revision, session.compiler.revision);
    try std.testing.expectEqual(.ready, session.runtime.context.state);
    try std.testing.expect(session.runtime.context.storage.acquisitions.entries.items[0].live);
    try std.testing.expectEqual(@as(i128, 8), (try session.submitInput("byte_length(&owned).count")).?.value.runtime.integer);

    // A healthy reset performs ordinary cleanup, then recreates the prelude.
    try session.reset();
    try std.testing.expect(session.compiler.namespace != namespace);
    try std.testing.expectEqual(@as(usize, 1), session.runtime.context.storage.acquisitions.entries.items.len);
    try std.testing.expect(session.runtime.context.storage.acquisitions.entries.items[0].live);
    try session.close();
    try std.testing.expectEqual(.fresh, session.runtime.context.state);
    try std.testing.expectEqual(@as(u32, 0), session.runtime.context.bindings.count());
    session.deinit();
    deinitialized = true;
    try std.testing.expectEqual(failing.allocated_bytes, failing.freed_bytes);
}

test "REPL bundled prelude runtime allocation failures preserve publication boundaries" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var files = try sf.collectCoreWithOptions(&allocator, std.testing.io, .{ .fallback_core_dir = "core" });
    defer sf.freeList(&allocator, &files);
    var diagnostics = try diag.Diagnostics.init(&allocator, files.items);
    defer diagnostics.deinit();
    var pipeline = frontend.FrontendPipeline.init(allocator, std.testing.io, &diagnostics, .{});
    defer pipeline.deinit();
    const prepared = try pipeline.prepareSessionFiles(files.items);
    var allocation_count: usize = 0;
    var resize_count: usize = 0;
    var rejected: usize = 0;
    var trapped: usize = 0;
    // Establish counts first, then probe both ends of allocation and resize
    // sequences. Exhaustive initialization sweeps remain a separate task.
    for (0..7) |probe| {
        var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
        if (probe > 0 and probe < 5) failing.fail_index = switch (probe) {
            1 => 0,
            2 => 1,
            3 => allocation_count - 2,
            else => allocation_count - 1,
        };
        if (probe >= 5) failing.resize_fail_index = if (probe == 5) 0 else resize_count - 1;
        var session: interactive.Interactive = undefined;
        try session.initPrepared(std.testing.allocator, diagnostics.source_files, prepared, .{});
        var deinitialized = false;
        defer if (!deinitialized) session.deinit();
        // Frontend preparation uses its normal allocator. Only executable-unit
        // preparation and execution storage participate in this failure probe.
        session.runtime.deinit();
        session.runtime = .init(failing.allocator(), &session.compiler, session.limits);
        var output: std.Io.Writer = .failing;
        var adapter: @import("../execution/host_output.zig").Output = .{ .writer = &output, .error_writer = &output };
        const bindings = adapter.bindings();
        session.runtime.context.host_bindings = &bindings;
        const source = prelude ++ "\nowned ::= unwrap_or_abort(.value = String(.length = 8))\n";
        session.initializePrelude(source) catch |err| {
            failing.fail_index = std.math.maxInt(usize);
            failing.resize_fail_index = std.math.maxInt(usize);
            try std.testing.expectEqual(error.OutOfMemory, err);
            try std.testing.expect(session.prelude == null);
            if (session.compiler.revision == 0) {
                rejected += 1;
                try std.testing.expectEqual(.fresh, session.runtime.context.state);
            } else {
                trapped += 1;
                try std.testing.expectEqual(.poisoned, session.runtime.context.state);
                try std.testing.expectError(error.ExecutionContextPoisoned, session.submitStatements("owned"));
            }
            try session.reset();
            try session.initializePrelude(source);
            try std.testing.expectEqual(@as(i128, 8), (try session.submitInput("byte_length(&owned).count")).?.value.runtime.integer);
            try session.close();
            session.deinit();
            deinitialized = true;
            try std.testing.expectEqual(failing.allocated_bytes, failing.freed_bytes);
            continue;
        };
        if (probe == 0) {
            allocation_count = failing.alloc_index;
            resize_count = failing.resize_index;
            try std.testing.expect(allocation_count >= 2 and resize_count != 0);
        }
        // A failed resize may use the ordinary allocation fallback successfully.
        failing.fail_index = std.math.maxInt(usize);
        failing.resize_fail_index = std.math.maxInt(usize);
        try session.close();
        session.deinit();
        deinitialized = true;
        try std.testing.expectEqual(failing.allocated_bytes, failing.freed_bytes);
    }
    try std.testing.expect(rejected > 0);
    try std.testing.expect(trapped > 0);
}

test "REPL resource prelude releases failed source and backend allocations" {
    const bytecode = @import("../5_codegen/bytecode/bytecode.zig");
    const vm_mod = @import("../execution/vm.zig");
    const checkFailures = @import("../test_support.zig").checkAllocationAndResizeFailures;
    const options = @import("internal_test_options");
    const source = prelude ++ "\nowned ::= unwrap_or_abort(.value = String(.length = 8))\n";
    if (!options.extended_allocation_sweeps) try checkFailures(std.testing.allocator, struct {
        fn run(a: std.mem.Allocator, text: []const u8) !void {
            var sources = @import("../execution/submissions.zig").Sources.init(a);
            defer sources.deinit();
            var source_allocator = a;
            var messages = try diag.Diagnostics.init(&source_allocator, &.{});
            defer messages.deinit();
            const saved = try sources.beginBatch(&messages);
            {
                defer sources.rollbackBatch(&messages, saved);
                const command = try sources.loadCommand(&messages, text);
                try std.testing.expect(command.module.semantic.local_semantics_complete);
            }
            try std.testing.expectEqual(@as(usize, 0), sources.modules.items.len);
            try std.testing.expectEqual(@as(usize, 0), sources.arenaBytes());
            try std.testing.expectEqual(@as(usize, 0), messages.source_files.len);
            try std.testing.expectEqual(@as(usize, 0), messages.source_maps.len);
        }
    }.run, .{source});
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var files = try sf.collectCoreWithOptions(&allocator, std.testing.io, .{ .fallback_core_dir = "core" });
    defer sf.freeList(&allocator, &files);
    var diagnostics = try diag.Diagnostics.init(&allocator, files.items);
    defer diagnostics.deinit();
    var pipeline = frontend.FrontendPipeline.init(allocator, std.testing.io, &diagnostics, .{});
    defer pipeline.deinit();
    const prepared = try pipeline.prepareSessionFiles(files.items);
    const initial_graph = prepared.relocation.graph.checkpoint();
    // Thousands of rollbacks release the same core structures. Keep allocator
    // safety checks without repeatedly unwinding identical free-site stacks.
    var strict = std.heap.DebugAllocator(.{ .stack_trace_frames = 0 }){};
    defer std.testing.expect(strict.deinit() == .ok) catch @panic("resource-prelude sweep leaked backing memory");
    const Preparation = struct {
        fn run(a: std.mem.Allocator, initial_files: []const sf.SourceFile, template: *const @import("../4_semantics/global/semantizer.zig").Session, text: []const u8) !void {
            const checkpoint = template.relocation.graph.checkpoint();
            var candidate: interactive.Interactive = undefined;
            candidate.initPrepared(a, initial_files, template, .{}) catch |err| {
                try std.testing.expectEqualDeep(checkpoint, template.relocation.graph.checkpoint());
                return err;
            };
            defer candidate.deinit();
            try std.testing.expectEqual(@as(u64, 0), candidate.compiler.revision);
            try std.testing.expectEqual(.fresh, candidate.runtime.context.state);
            try std.testing.expectEqual(template.relocation.graph.types.items.len, candidate.compiler.semantic.relocation.graph.types.items.len);
            if (!@import("internal_test_options").extended_allocation_sweeps) return;
            const accepted = candidate.compiler.semantic.relocation.graph.checkpoint();
            {
                var command = candidate.sources.prepareCommand(&candidate.compiler, &candidate.diagnostics, text) catch |err| {
                    try std.testing.expectEqualDeep(accepted, candidate.compiler.semantic.relocation.graph.checkpoint());
                    try std.testing.expectEqual(@as(u64, 0), candidate.compiler.revision);
                    try std.testing.expectEqual(.fresh, candidate.runtime.context.state);
                    return err;
                };
                defer command.deinit();
                try std.testing.expect(command.candidate.checked != null);
            }
            try std.testing.expectEqualDeep(accepted, candidate.compiler.semantic.relocation.graph.checkpoint());
        }
    };
    if (options.extended_allocation_sweeps) {
        try @import("../test_support.zig").checkAllocationAndResizeFailureRange(strict.allocator(), Preparation.run, .{ diagnostics.source_files, prepared, source }, options.allocation_failure_start, options.allocation_failure_end);
    } else try checkFailures(strict.allocator(), Preparation.run, .{ diagnostics.source_files, prepared, source });
    try std.testing.expectEqualDeep(initial_graph, prepared.relocation.graph.checkpoint());
    // The ordinary run covers source and backend failures. Range runs isolate
    // semantic preparation rather than repeating those complete sweeps for
    // every independent range.
    if (options.extended_allocation_sweeps) return;
    var session: interactive.Interactive = undefined;
    try session.initPrepared(std.testing.allocator, diagnostics.source_files, prepared, .{});
    defer session.deinit();
    var command = try session.sources.prepareCommand(&session.compiler, &session.diagnostics, source);
    defer command.deinit();
    const checked = command.candidate.checked.?;
    const semantic = command.candidate.semantic.?;
    const layout = try @import("../5_codegen/bytecode/session_layout.zig").build(allocator, checked.graph, semantic.resolvers.expressions.session_bindings.items);
    const LoweringProbe = struct {
        fn run(a: std.mem.Allocator, candidate: *const @import("../execution/compilation_session.zig").CompilationSession.Candidate, catalogue: bytecode.Session, messages: *const diag.Diagnostics) !void {
            var code = std.heap.ArenaAllocator.init(a);
            defer code.deinit();
            var scratch = std.heap.ArenaAllocator.init(a);
            defer scratch.deinit();
            const proof = candidate.checked.?;
            var lowering = try @import("../5_codegen/bytecode/lower.zig").Lower.init(code.allocator(), proof.graph, .{ .session = catalogue, .scratch_allocator = scratch.allocator(), .proofs = &proof.bodies });
            lowering.annotations = &proof.annotations;
            lowering.diagnostics = messages;
            const executable = try lowering.compile(candidate.entry.?);
            try std.testing.expect(executable.function(candidate.entry.?) != null);
        }
    };
    const catalogue: bytecode.Session = .{ .namespace = session.compiler.namespace, .bindings = layout };
    try checkFailures(std.testing.allocator, LoweringProbe.run, .{ &command.candidate, catalogue, &session.diagnostics });
    var lower = try @import("../5_codegen/bytecode/lower.zig").Lower.init(allocator, checked.graph, .{ .session = .{ .namespace = session.compiler.namespace, .bindings = layout } });
    lower.annotations = &checked.annotations;
    lower.diagnostics = &session.diagnostics;
    const program = try lower.compile(command.function);
    const VerificationProbe = struct {
        fn run(a: std.mem.Allocator, candidate_program: bytecode.Program) !void {
            const unit = try bytecode.Verified.create(a, a, candidate_program);
            defer unit.destroy(a);
            try std.testing.expectEqual(candidate_program.graph, unit.program().graph);
        }
    };
    try checkFailures(std.testing.allocator, VerificationProbe.run, .{program});
    const verified = try bytecode.Verified.create(allocator, std.testing.allocator, program);
    var output: std.Io.Writer = .failing;
    var adapter: @import("../execution/host_output.zig").Output = .{ .writer = &output, .error_writer = &output };
    const bindings = adapter.bindings();
    // Reuse the verified handle for the separate execution sweep. Only
    // invocation metadata and retained runtime storage fail in this phase.
    const Probe = struct {
        fn run(a: std.mem.Allocator, unit: *const bytecode.Verified, entry: @import("../4_semantics/global/graph.zig").GlobalFunctionId, hosts: []const @import("../execution/host.zig").Binding) !void {
            var context = vm_mod.Context.init(a, 1_000_000);
            defer context.deinit();
            context.host_bindings = hosts;
            var executor = vm_mod.Vm.initVerifiedShared(a, unit, .{}, &context) catch |err| {
                try std.testing.expectEqual(error.OutOfMemory, err);
                try std.testing.expectEqual(.fresh, context.state);
                return err;
            };
            defer executor.deinit();
            _ = executor.invoke(entry, &.{}) catch |err| {
                try std.testing.expectEqual(error.OutOfMemory, err);
                try std.testing.expectEqual(.poisoned, context.state);
                context.reset();
                try std.testing.expectEqual(.fresh, context.state);
                return err;
            };
            try std.testing.expectEqual(.ready, context.state);
            var live: usize = 0;
            for (context.storage.acquisitions.entries.items) |region| if (region.live) {
                live += 1;
            };
            try std.testing.expectEqual(@as(usize, 1), live);
            // Context teardown releases host memory, not user destructors. The
            // separate interactive lifecycle tests exercise checked close/reset.
        }
    };
    try checkFailures(std.testing.allocator, Probe.run, .{ verified, command.function, &bindings });
}

test "REPL presents compiler types and reuses them in layout queries" {
    var session: interactive.Interactive = undefined;
    try session.init(std.testing.allocator, &.{}, .{ .exhaustive_function_bodies = false }, .{});
    defer session.deinit();
    var input = std.Io.Reader.fixed("a :: Int32 = 42\ntype_of(a)\nsize_of(a)\nsize_of(.type = _0)\n:quit\n");
    var output = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer output.deinit();
    try interact(&session, &input, &output.writer, false, false, null);
    try std.testing.expectEqualStrings("_0 = Int32\n_1 = 4\n_2 = 4\n", output.written());
}

test "REPL automatically completes open function and call delimiters" {
    var session: interactive.Interactive = undefined;
    try session.init(std.testing.allocator, &.{}, .{ .exhaustive_function_bodies = false }, .{});
    defer session.deinit();
    var input = std.Io.Reader.fixed(
        "answer := (.value: Int32) -> (.result: Int32) { -- } ignored\n" ++
            "    if true {\n" ++
            "        result = value\n" ++
            "    } else { result = 0 }\n" ++
            "}\n" ++
            "answer(\n" ++
            "    .value = 42\n" ++
            ")\n:quit\n",
    );
    var output = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer output.deinit();
    try interact(&session, &input, &output.writer, false, false, null);
    try std.testing.expectEqualStrings("_0 = 42\n", output.written());
    try std.testing.expect(session.closed);
}

test "REPL cancels pending input without publishing or resetting accepted state" {
    var session: interactive.Interactive = undefined;
    try session.init(std.testing.allocator, &.{}, .{ .exhaustive_function_bodies = false }, .{});
    defer session.deinit();
    var input = std.Io.Reader.fixed(
        "value :: Int32 = 42\n" ++
            "unfinished := () -> () {\n:cancel\nvalue\n" ++
            ":begin\nvalue = 9\n:cancel\nvalue\n:quit\n",
    );
    var output = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer output.deinit();
    try interact(&session, &input, &output.writer, false, false, null);
    try std.testing.expectEqualStrings("_0 = 42\n_1 = 42\n", output.written());
    try std.testing.expect(session.closed);
}
