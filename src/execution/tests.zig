const std = @import("std");
const sf = @import("../1_base/source_files.zig");
const diag = @import("../1_base/diagnostic.zig");
const frontend = @import("../0_commands/frontend_pipeline.zig");
const lower = @import("../5_codegen/bytecode/lower.zig");
const vm = @import("vm.zig");
const b = @import("../5_codegen/bytecode/bytecode.zig");

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

test "bytecode call stack does not recurse through the host stack" {
    try std.testing.expectEqual(@as(i128, 42), try execute(
        \\recurse(.remaining: Int32) -> (.result: Int32 = 42) := {
        \\    if remaining > 0 { result = recurse(.remaining = remaining - 1) }
        \\}
        \\main() -> (.status_code: Int32 = 0) := {
        \\    status_code = recurse(.remaining = 512)
        \\}
    , .{ .call_depth = 1024 }));
}

test "bytecode VM reuses returned aggregates and recovers after failure" {
    const g = @import("../4_semantics/global/graph.zig");
    var graph: g.GlobalSemanticGraph = .{};
    defer graph.deinit(std.testing.allocator);
    const a = std.testing.allocator;
    try graph.types.append(a, .{ .builtin = .Int32 });
    try graph.types.append(a, .{ .array = .{ .length = 1, .element = @enumFromInt(0) } });
    const source = @import("../4_semantics/primitives/schema.zig").SourceRef{ .file_index = 0, .offset = 0 };
    try graph.fields.append(a, .{ .name = .{ .start = 0, .len = 0 }, .ty = @enumFromInt(1), .source = source });
    try graph.functions.append(a, .{ .declaration = @enumFromInt(0), .input = .{ .start = 0, .len = 1 }, .output = .{ .start = 0, .len = 1 } });
    const code = [_]b.Instruction{.{ .source = source, .op = .{ .ret = &.{0} } }};
    const functions = [_]?b.Function{.{ .slots = &.{@enumFromInt(1)}, .inputs = &.{0}, .outputs = &.{0}, .code = &code }};
    var executor = try vm.Vm.init(a, .{ .graph = &graph, .functions = &functions }, .{});
    defer executor.deinit();
    var result = try executor.run(@enumFromInt(0), &.{.{ .array = &.{.{ .integer = 42 }} }});
    result = try executor.run(@enumFromInt(0), result);
    try std.testing.expectEqual(@as(i128, 42), result[0].array[0].integer);
    try std.testing.expectError(error.InvalidArguments, executor.run(@enumFromInt(0), &.{.{ .array = &.{.{ .boolean = false }} }}));
    try std.testing.expectError(error.InvalidEntry, executor.run(@enumFromInt(99), &.{}));
    executor.limits.instructions = 0;
    try std.testing.expectError(error.ExecutionInstructionLimit, executor.run(@enumFromInt(0), &.{.{ .array = &.{.{ .integer = 42 }} }}));
    for (executor.storage.frames.items) |frame_| try std.testing.expect(!frame_.alive);
    executor.limits.instructions = 100;
    result = try executor.run(@enumFromInt(0), &.{.{ .array = &.{.{ .integer = 42 }} }});
    try std.testing.expectEqual(@as(i128, 42), result[0].array[0].integer);
    executor.limits.call_depth = 0;
    try std.testing.expectError(error.ExecutionCallDepthLimit, executor.run(@enumFromInt(0), result));
}

test "bytecode references preserve caller storage across calls" {
    try std.testing.expectEqual(@as(i128, 42), try execute(
        \\update(.value: $&Int32) -> () := { value& = value& + 1 }
        \\borrow(.value: &Int32) -> (.result: &Int32) := { result = value }
        \\main() -> (.status_code: Int32 = 0) := {
        \\    value :: Int32 = 41
        \\    update(.value = $&value)
        \\    reference ::= borrow(.value = &value)
        \\    status_code = reference&
        \\}
    , .{}));
}

test "bytecode reference projections capture indices and preserve aggregate copies" {
    try std.testing.expectEqual(@as(i128, 42), try execute(
        \\Pair: Type = (.left: Int32, .right: Int32)
        \\update(.value: $&Pair) -> () := { value&.left = 40 }
        \\main() -> (.status_code: Int32 = 0) := {
        \\    pairs :: [2]Pair = ((.left = 1, .right = 2), (.left = 3, .right = 4))
        \\    saved ::= pairs
        \\    index :: UIntNative = 0
        \\    reference ::= $&pairs[index]
        \\    index = 1
        \\    update(.value = reference)
        \\    if saved[0].left != 1 or pairs[1].left != 3 { abort }
        \\    status_code = pairs[0].left + pairs[0].right
        \\}
    , .{}));
}

test "bytecode storage rejects dead frames and readonly writes" {
    const Storage = @import("storage.zig").Storage;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var storage = Storage{ .allocator = arena.allocator(), .limit = 100 };
    const first = try storage.enter(1);
    const slots = try storage.slots(first);
    slots[0] = .{ .integer = 42 };
    const reference = @import("../5_codegen/bytecode/value.zig").Reference{
        .frame = first,
        .root = 0,
        .path = &.{},
        .mutability = .read_write,
    };
    const readonly = try storage.borrow(reference, .read_only);
    try std.testing.expectError(error.ExecutionReadonlyReference, storage.store(readonly.reference, .{ .integer = 99 }));
    try std.testing.expectError(error.ExecutionReadonlyReference, storage.borrow(readonly.reference, .read_write));
    try std.testing.expectEqual(@as(i128, 42), (try storage.read(reference)).integer);
    storage.leave(first);
    const second = try storage.enter(1);
    try std.testing.expect(first != second);
    try std.testing.expectError(error.ExecutionDeadReference, storage.read(reference));
    try std.testing.expectError(error.ExecutionDeadReference, storage.validateLive(&.{.{ .record = &.{readonly} }}));
}

test "bytecode accepts mutable reference arguments for readonly inputs" {
    try std.testing.expectEqual(@as(i128, 42), try execute(
        \\read(.value: &Int32) -> (.result: Int32) := { result = value& }
        \\main() -> (.status_code: Int32 = 0) := {
        \\    value :: Int32 = 42
        \\    status_code = read(.value = $&value)
        \\}
    , .{}));
}

test "bytecode verifies reference access and traps escaped frame storage" {
    const g = @import("../4_semantics/global/graph.zig");
    var graph: g.GlobalSemanticGraph = .{};
    defer graph.deinit(std.testing.allocator);
    const a = std.testing.allocator;
    try graph.types.append(a, .{ .builtin = .Int32 });
    try graph.types.append(a, .{ .pointer = .{ .child = @enumFromInt(0), .mutability = .read_only } });
    try graph.types.append(a, .{ .pointer = .{ .child = @enumFromInt(0), .mutability = .read_write } });
    const source = @import("../4_semantics/primitives/schema.zig").SourceRef{ .file_index = 0, .offset = 0 };
    try graph.fields.append(a, .{ .name = .{ .start = 0, .len = 0 }, .ty = @enumFromInt(1), .source = source });
    try graph.functions.append(a, .{ .declaration = @enumFromInt(0), .input = .{ .start = 0, .len = 0 }, .output = .{ .start = 0, .len = 1 } });
    var code = [_]b.Instruction{
        .{ .source = source, .op = .{ .constant = .{ .dst = 0, .value = .{ .integer = 42 } } } },
        .{ .source = source, .op = .{ .borrow = .{ .dst = 1, .place = .{ .root = 0, .path = &.{} } } } },
        .{ .source = source, .op = .{ .load = .{ .dst = 0, .place = .{ .root = 1, .path = &.{.dereference} } } } },
        .{ .source = source, .op = .{ .ret = &.{1} } },
    };
    const functions = [_]?b.Function{.{ .slots = &.{ @enumFromInt(0), @enumFromInt(1), @enumFromInt(2) }, .inputs = &.{}, .outputs = &.{1}, .code = &code }};
    const program = b.Program{ .graph = &graph, .functions = &functions };
    var executor = try vm.Vm.init(a, program, .{});
    defer executor.deinit();
    try std.testing.expectError(error.ExecutionDeadReference, executor.run(@enumFromInt(0), &.{}));
    code[2].op = .{ .store = .{ .place = .{ .root = 1, .path = &.{.dereference} }, .value = 0 } };
    try std.testing.expectError(error.InvalidBytecode, b.verify(a, program));
    code[2].op = .{ .borrow = .{ .dst = 2, .place = .{ .root = 1, .path = &.{.dereference} } } };
    try std.testing.expectError(error.InvalidBytecode, b.verify(a, program));
    code[2].op = .{ .readonly = .{ .dst = 2, .src = 1 } };
    try std.testing.expectError(error.InvalidBytecode, b.verify(a, program));
    code[1].op.borrow.place.root = 2;
    code[2].op = .{ .load = .{ .dst = 0, .place = .{ .root = 1, .path = &.{.dereference} } } };
    try std.testing.expectError(error.InvalidBytecode, b.verify(a, program));
}

test "bytecode reference fields keep pointees separate from copied records" {
    try std.testing.expectEqual(@as(i128, 42), try execute(
        \\Args: Type = (.target: $&Int32)
        \\View: Type = (.target: &Int32)
        \\update(.args: Args) -> () := { args.target& = 42 }
        \\main() -> (.status_code: Int32 = 0) := {
        \\    value :: Int32 = 1
        \\    args: Args = (.target = $&value)
        \\    update(.args = args)
        \\    view: View = (.target = $&value)
        \\    status_code = view.target&
        \\}
    , .{}));
}

test "bytecode matches choice payloads and borrows their storage" {
    try std.testing.expectEqual(@as(i128, 42), try execute(
        \\Result: Type = (..ok(.value: Int32), ..empty)
        \\main() -> (.status_code: Int32 = 0) := {
        \\    value :: Result = ..ok(.value = 1)
        \\    saved ::= value
        \\    match value {
        \\        ..ok $& payload { payload&.value = 42 }
        \\        ..empty { abort }
        \\    }
        \\    match saved {
        \\        ..ok payload { if payload.value != 1 { abort } }
        \\        ..empty { abort }
        \\    }
        \\    match value {
        \\        ..ok payload { status_code = payload.value }
        \\        ..empty { abort }
        \\    }
        \\}
    , .{}));
}

test "bytecode accesses proven active payloads across calls" {
    try std.testing.expectEqual(@as(i128, 42), try execute(
        \\Result: Type = (..ok Int32, ..empty)
        \\make(.value: Int32) -> (.result: Result) := { result = ..ok value }
        \\main() -> (.status_code: Int32 = 0) := {
        \\    result ::= make(.value = 42)
        \\    if result == ..ok { status_code = result..ok } else { abort }
        \\}
    , .{}));
}

test "bytecode choice verifier rejects foreign variants and incorrect payload types" {
    const g = @import("../4_semantics/global/graph.zig");
    var graph: g.GlobalSemanticGraph = .{};
    defer graph.deinit(std.testing.allocator);
    const a = std.testing.allocator;
    const source = @import("../4_semantics/primitives/schema.zig").SourceRef{ .file_index = 0, .offset = 0 };
    try graph.types.append(a, .{ .builtin = .Int32 });
    try graph.types.append(a, .{ .builtin = .Bool });
    try graph.types.append(a, .{ .structural_choice = .{ .variants = .{ .start = 0, .len = 2 } } });
    try graph.variants.append(a, .{ .name = .{ .start = 0, .len = 0 }, .payload_type = @enumFromInt(0), .source = source, .value = 0 });
    try graph.variants.append(a, .{ .name = .{ .start = 0, .len = 0 }, .source = source, .value = 1 });
    try graph.fields.append(a, .{ .name = .{ .start = 0, .len = 0 }, .ty = @enumFromInt(0), .source = source });
    try graph.functions.append(a, .{ .declaration = @enumFromInt(0), .input = .{ .start = 0, .len = 0 }, .output = .{ .start = 0, .len = 1 } });
    var code = [_]b.Instruction{
        .{ .source = source, .op = .{ .constant = .{ .dst = 0, .value = .{ .integer = 42 } } } },
        .{ .source = source, .op = .{ .constant = .{ .dst = 1, .value = .{ .boolean = true } } } },
        .{ .source = source, .op = .{ .choice = .{ .dst = 2, .variant = @enumFromInt(0), .payload = 0 } } },
        .{ .source = source, .op = .{ .payload = .{ .dst = 0, .src = 2, .variant = @enumFromInt(0) } } },
        .{ .source = source, .op = .{ .ret = &.{0} } },
    };
    const functions = [_]?b.Function{.{ .slots = &.{ @enumFromInt(0), @enumFromInt(1), @enumFromInt(2) }, .inputs = &.{}, .outputs = &.{0}, .code = &code }};
    const program = b.Program{ .graph = &graph, .functions = &functions };
    try b.verify(a, program);
    code[2].op.choice.payload = 1;
    try std.testing.expectError(error.InvalidBytecode, b.verify(a, program));
    code[2].op.choice.payload = null;
    try std.testing.expectError(error.InvalidBytecode, b.verify(a, program));
    code[2].op.choice.variant = @enumFromInt(99);
    try std.testing.expectError(error.InvalidBytecode, b.verify(a, program));
    code[2].op.choice.variant = @enumFromInt(1);
    // The payload instruction is well typed but names an inactive alternative.
    // Runtime checks backstop the frontend's proof of the active variant.
    var executor = try vm.Vm.init(a, program, .{});
    defer executor.deinit();
    try std.testing.expectError(error.ExecutionInactiveVariant, executor.run(@enumFromInt(0), &.{}));
}
