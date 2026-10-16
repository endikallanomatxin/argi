const std = @import("std");
const sf = @import("../1_base/source_files.zig");
const diag = @import("../1_base/diagnostic.zig");
const frontend = @import("../0_commands/frontend_pipeline.zig");
const lower = @import("lower.zig");
const vm = @import("vm.zig");
const b = @import("bytecode.zig");

fn execute(source: []const u8, limits: vm.Limits) !i128 {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const files = [_]sf.SourceFile{
        .{ .path = "app/main.rg", .code = source },
        .{ .path = "arithmetic_core/scalar_arithmetic.rg", .origin = .bundled_core, .code = @import("../test_support.zig").arithmetic_core_source },
    };
    var diagnostics = diag.Diagnostics.init(&allocator, &files);
    defer diagnostics.deinit();
    var pipeline = frontend.FrontendPipeline.init(allocator, std.testing.io, &diagnostics, .{});
    defer pipeline.deinit();
    const graph = pipeline.semantizeGlobalFiles(&files) catch |err| {
        for (diagnostics.list.items) |d| std.debug.print("{s}\n", .{d.msg});
        return err;
    };
    for (graph.functions.items, 0..) |f, i| {
        if (!std.mem.eql(u8, graph.text(graph.declarationSourceName(f.declaration)), "main")) continue;
        var compiler = try lower.Lower.init(allocator, graph);
        const program = compiler.compile(@enumFromInt(i)) catch |err| {
            return err;
        };
        var executor = try vm.Vm.init(allocator, program, limits);
        defer executor.deinit();
        const result = try executor.run(@enumFromInt(i), &.{});
        return result[0].integer;
    }
    return error.MissingEntry;
}

test "bytecode executes selected arithmetic contracts and loops" {
    try std.testing.expectEqual(@as(i128, 55), try execute(
        \\main() -> (.status_code: Int32 = 0) := {
        \\    index :: Int32 = 0
        \\    while index < 10 {
        \\        index = index + 1
        \\        status_code = status_code + index
        \\    }
        \\}
    , .{}));
}

test "bytecode enforces execution fuel" {
    try std.testing.expectError(error.ExecutionInstructionLimit, execute(
        \\main() -> (.status_code: Int32 = 0) := { while true {} }
    , .{ .instructions = 100 }));
}

test "bytecode refuses unsupported code before execution" {
    try std.testing.expectError(error.UnsupportedExecution, execute(
        \\main() -> (.status_code: Int32 = 0) := { message: Float32 = 1.5 }
    , .{}));
}

test "bytecode reports arithmetic overflow" {
    try std.testing.expectError(error.ExecutionIntegerOverflow, execute(
        \\main() -> (.status_code: Int32 = 0) := {
        \\    value :: Int32 = 2147483647
        \\    status_code = value + 1
        \\}
    , .{}));
}

test "bytecode calls specialize generic functions and short circuit" {
    try std.testing.expectEqual(@as(i128, 42), try execute(
        \\identity#(.T: Type) := (.value: T) -> (.result: T) { result = value }
        \\fail() -> (.result: Bool = false) := { abort }
        \\main() -> (.status_code: Int32 = 0) := {
        \\    if false and fail() { abort }
        \\    if true or fail() { status_code = identity(.value = 42) }
        \\}
    , .{}));
}

test "bytecode limits recursive calls and allocation" {
    const recursive =
        \\recurse(.value: Int32) -> (.result: Int32) := { result = recurse(.value = value) }
        \\main() -> (.status_code: Int32 = 0) := { status_code = recurse(.value = 1) }
    ;
    try std.testing.expectError(error.ExecutionCallDepthLimit, execute(recursive, .{ .call_depth = 8 }));
    try std.testing.expectError(error.ExecutionMemoryLimit, execute(recursive, .{ .value_cells = 4 }));
}

test "bytecode preserves break continue and early return" {
    try std.testing.expectEqual(@as(i128, 12), try execute(
        \\main() -> (.status_code: Int32 = 0) := {
        \\    index :: Int32 = 0
        \\    while index < 20 {
        \\        index = index + 1
        \\        if index < 3 { continue }
        \\        if index > 5 { break }
        \\        status_code = status_code + index
        \\    }
        \\    return
        \\    status_code = 99
        \\}
    , .{}));
}

test "bytecode verifier rejects malformed control flow and missing initialization" {
    const g = @import("../4_semantics/global/graph.zig");
    var graph: g.GlobalSemanticGraph = .{};
    defer graph.deinit(std.testing.allocator);
    const a = std.testing.allocator;
    try graph.types.append(a, .{ .builtin = .Int32 });
    try graph.types.append(a, .{ .builtin = .Bool });
    try graph.fields.append(a, .{ .name = .{ .start = 0, .len = 0 }, .ty = @enumFromInt(0), .source = .{ .file_index = 0, .offset = 0 } });
    try graph.functions.append(a, .{ .declaration = @enumFromInt(0), .input = .{ .start = 0, .len = 0 }, .output = .{ .start = 0, .len = 1 } });
    const source = @import("../4_semantics/primitives/schema.zig").SourceRef{ .file_index = 0, .offset = 0 };
    var code = [_]b.Instruction{
        .{ .source = source, .op = .{ .constant = .{ .dst = 0, .value = .{ .boolean = true } } } },
        .{ .source = source, .op = .{ .branch = .{ .condition = 0, .yes = 3, .no = 2 } } },
        .{ .source = source, .op = .{ .constant = .{ .dst = 1, .value = .{ .integer = 42 } } } },
        .{ .source = source, .op = .{ .ret = &.{1} } },
    };
    const functions = [_]?b.Function{.{ .slots = &.{ @enumFromInt(1), @enumFromInt(0) }, .inputs = &.{}, .outputs = &.{1}, .code = &code }};
    const program = b.Program{ .graph = &graph, .functions = &functions };
    try std.testing.expectError(error.UninitializedBytecodeSlot, b.verify(a, program));
    code[1].op.branch.yes = 2;
    try b.verify(a, program);
    code[1].op.branch.yes = 99;
    try std.testing.expectError(error.InvalidBytecode, b.verify(a, program));
    code[1].op.branch.yes = 2;
    code[2].op.constant.value = .{ .boolean = false };
    try std.testing.expectError(error.InvalidBytecode, b.verify(a, program));
    graph.target.arch = if (@import("builtin").cpu.arch == .aarch64) .x86_64 else .aarch64;
    try std.testing.expectError(error.UnsupportedExecutionTarget, b.verify(a, program));
}

test "bytecode returns immutable records across frames" {
    try std.testing.expectEqual(@as(i128, 42), try execute(
        \\Pair: Type = (.left: Int32, .right: Int32)
        \\make_pair(.left: Int32, .right: Int32) -> (.result: Pair) := {
        \\    result = (.left = left, .right = right)
        \\}
        \\main() -> (.status_code: Int32 = 0) := {
        \\    pair ::= make_pair(.left = 20, .right = 22)
        \\    status_code = pair.left + pair.right
        \\}
    , .{}));
}

test "bytecode arrays preserve value copies and frame isolation" {
    try std.testing.expectEqual(@as(i128, 42), try execute(
        \\change(.values: [2]Int32) -> (.result: [2]Int32) := {
        \\    result = values
        \\    result[0] = 20
        \\}
        \\main() -> (.status_code: Int32 = 0) := {
        \\    original :: [2]Int32 = (1, 22)
        \\    changed ::= change(.values = original)
        \\    original[1] = 99
        \\    status_code = changed[0] + changed[1]
        \\}
    , .{}));
}

test "bytecode array indexing is checked at runtime" {
    try std.testing.expectError(error.ExecutionIndexOutOfBounds, execute(
        \\main() -> (.status_code: Int32 = 0) := {
        \\    values :: [2]Int32 = (10, 20)
        \\    index :: UIntNative = 2
        \\    status_code = values[index]
        \\}
    , .{}));
    try std.testing.expectError(error.ExecutionIndexOutOfBounds, execute(
        \\main() -> (.status_code: Int32 = 0) := {
        \\    values :: [0]Int32 = ()
        \\    index :: UIntNative = 0
        \\    values[index] = 1
        \\}
    , .{}));
}

test "bytecode array verifier rejects malformed elements and indices" {
    const g = @import("../4_semantics/global/graph.zig");
    var graph: g.GlobalSemanticGraph = .{};
    defer graph.deinit(std.testing.allocator);
    const a = std.testing.allocator;
    try graph.types.append(a, .{ .builtin = .Int32 });
    try graph.types.append(a, .{ .builtin = .Bool });
    try graph.types.append(a, .{ .array = .{ .length = 1, .element = @enumFromInt(0) } });
    try graph.fields.append(a, .{ .name = .{ .start = 0, .len = 0 }, .ty = @enumFromInt(0), .source = .{ .file_index = 0, .offset = 0 } });
    try graph.functions.append(a, .{ .declaration = @enumFromInt(0), .input = .{ .start = 0, .len = 0 }, .output = .{ .start = 0, .len = 1 } });
    const source = @import("../4_semantics/primitives/schema.zig").SourceRef{ .file_index = 0, .offset = 0 };
    var code = [_]b.Instruction{
        .{ .source = source, .op = .{ .constant = .{ .dst = 0, .value = .{ .integer = 0 } } } },
        .{ .source = source, .op = .{ .constant = .{ .dst = 1, .value = .{ .boolean = false } } } },
        .{ .source = source, .op = .{ .array = .{ .dst = 2, .elements = &.{0} } } },
        .{ .source = source, .op = .{ .index = .{ .dst = 3, .base = 2, .index = 0 } } },
        .{ .source = source, .op = .{ .ret = &.{3} } },
    };
    const functions = [_]?b.Function{.{ .slots = &.{ @enumFromInt(0), @enumFromInt(1), @enumFromInt(2), @enumFromInt(0) }, .inputs = &.{}, .outputs = &.{3}, .code = &code }};
    const program = b.Program{ .graph = &graph, .functions = &functions };
    try b.verify(a, program);
    code[2].op.array.elements = &.{};
    try std.testing.expectError(error.InvalidBytecode, b.verify(a, program));
    code[2].op.array.elements = &.{1};
    try std.testing.expectError(error.InvalidBytecode, b.verify(a, program));
    code[2].op.array.elements = &.{0};
    code[3].op.index.index = 1;
    try std.testing.expectError(error.InvalidBytecode, b.verify(a, program));
    code[3].op = .{ .store = .{ .place = .{ .root = 2, .path = &.{.{ .element = 0 }} }, .value = 1 } };
    try std.testing.expectError(error.InvalidBytecode, b.verify(a, program));
    code[3].op = .{ .check_place = .{ .root = 2, .path = &.{.{ .field = 0 }} } };
    try std.testing.expectError(error.InvalidBytecode, b.verify(a, program));
    code[3].op = .{ .check_place = .{ .root = 2, .path = &.{.{ .element = 99 }} } };
    try std.testing.expectError(error.InvalidBytecode, b.verify(a, program));
}

test "bytecode places update nested aggregates without changing copies" {
    try std.testing.expectEqual(@as(i128, 42), try execute(
        \\Pair: Type = (.left: Int32, .right: Int32)
        \\Box: Type = (.pairs: [2]Pair)
        \\main() -> (.status_code: Int32 = 0) := {
        \\    box :: Box = (.pairs = ((.left = 1, .right = 2), (.left = 3, .right = 4)))
        \\    saved ::= box
        \\    box.pairs[1].left = 40
        \\    box.pairs[0].right = 2
        \\    if saved.pairs[1].left != 3 { abort }
        \\    status_code = box.pairs[1].left + box.pairs[0].right
        \\}
    , .{}));
}

test "bytecode validates intermediate destinations before later operands" {
    try std.testing.expectError(error.ExecutionIndexOutOfBounds, execute(
        \\fail() -> (.result: UIntNative = 0) := { abort }
        \\main() -> (.status_code: Int32 = 0) := {
        \\    values :: [2][2]Int32 = ((1, 2), (3, 4))
        \\    index :: UIntNative = 2
        \\    values[index][fail()] = 9
        \\}
    , .{}));
}
