const std = @import("std");
const sf = @import("../1_base/source_files.zig");
const diag = @import("../1_base/diagnostic.zig");
const frontend = @import("frontend_pipeline.zig");
const interactive = @import("../execution/interactive.zig");
const repl_input = @import("repl_input.zig");
const value = @import("../5_codegen/bytecode/value.zig");

const prelude = @embedFile("repl_prelude.rg");

const help =
    \\Enter definitions, statements or expressions. Open delimiters continue on the next line.
    \\Expression results remain available as _0, _1, ... until reset or exit.
    \\Up / Down      Recall previous input lines (terminal only)
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
    var arena = std.heap.ArenaAllocator.init(backing_allocator);
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
    try session.initPrepared(backing_allocator, diagnostics.source_files, prepared, limits);
    defer session.deinit();
    try session.enableImports(io, ".");
    var input_buffer: [64 * 1024]u8 = undefined;
    var input = std.Io.File.stdin().reader(io, &input_buffer);
    var output_buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writer(io, &output_buffer);
    var error_output = std.Io.File.stderr().writer(io, &.{});
    defer error_output.interface.flush() catch {};
    var host_output = @import("../execution/host_output.zig").Output{ .writer = &output.interface, .error_writer = &error_output.interface };
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
    var automatic = false;
    var completion: @import("../1_base/lexical.zig").Completion = .{};
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
                if (automatic) {
                    completion.feedLine(line);
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
        } else if (std.mem.eql(u8, text, ":reset")) {
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
                try printValue(output, graph, element_ty, element, depth + 1);
            }
            try output.writeByte(if (item == .record) ')' else ']');
        },
        .choice => |choice| {
            try output.print("<variant {d}", .{choice.variant});
            if (choice.payload) |payload| {
                try output.writeAll(": ");
                const variants = @import("../4_semantics/global/types.zig").variants(graph, ty).?;
                try printValue(output, graph, graph.variants.items[variants.start + choice.variant].payload_type.?, payload.*, depth + 1);
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
    try interact(&session, &input, &output.writer, false);
    try std.testing.expectEqualStrings("_0 = -1\n_1 = 18446744073709551615\n_2 = (-1, 18446744073709551615)\n", output.written());
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

test "REPL standard prelude supplies output and persistent allocation across reset" {
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

test "REPL presents compiler types and reuses them in layout queries" {
    var session: interactive.Interactive = undefined;
    try session.init(std.testing.allocator, &.{}, .{ .exhaustive_function_bodies = false }, .{});
    defer session.deinit();
    var input = std.Io.Reader.fixed("a :: Int32 = 42\ntype_of(a)\nsize_of(a)\nsize_of(.type = _0)\n:quit\n");
    var output = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer output.deinit();
    try interact(&session, &input, &output.writer, false);
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
    try interact(&session, &input, &output.writer, false);
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
    try interact(&session, &input, &output.writer, false);
    try std.testing.expectEqualStrings("_0 = 42\n_1 = 42\n", output.written());
    try std.testing.expect(session.closed);
}
