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
        std.debug.print("execution fixture semantic failure: {s}\n", .{@errorName(err)});
        for (diagnostics.list.items) |d| std.debug.print("{s}\n", .{d.msg});
        return err;
    };
    for (graph.functions.items, 0..) |f, i| {
        if (!std.mem.eql(u8, graph.text(graph.declarationSourceName(f.declaration)), "main")) continue;
        var compiler = try lower.Lower.init(allocator, graph);
        compiler.mode = .runtime;
        const program = compiler.compile(@enumFromInt(i)) catch |err| {
            return err;
        };
        var executor = try vm.Vm.init(allocator, program, limits);
        defer executor.deinit();
        const result = try executor.run(@enumFromInt(i), &.{});
        return @import("../5_codegen/integer_arithmetic.zig").decode(result[0].integer, b.integerBounds(graph, graph.fields.items[f.output.start].ty).?);
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
        \\Mode: CEnum = (..one)
        \\main() -> (.status_code: Int32 = 0) := { message: Mode = ..one }
    , .{}));
}

test "bytecode wraps integer arithmetic at its declared width" {
    try std.testing.expectEqual(@as(i128, -2147483648), try execute(
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
    try std.testing.expectError(error.UninitializedBytecodeSlot, vm.Vm.init(a, program, .{}));
    code[1].op.branch.yes = 2;
    try b.verify(a, program);
    code[1].op.branch.yes = 99;
    try std.testing.expectError(error.InvalidBytecode, b.verify(a, program));
    code[1].op.branch.yes = 2;
    code[2].op.constant.value = .{ .boolean = false };
    try std.testing.expectError(error.InvalidBytecode, b.verify(a, program));
    graph.target.arch = if (@import("builtin").cpu.arch == .aarch64) .x86_64 else .aarch64;
    try std.testing.expectError(error.UnsupportedExecutionTarget, b.verify(a, program));
    try std.testing.expectError(error.UnsupportedExecutionTarget, vm.Vm.init(a, program, .{}));
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
        .{ .source = source, .op = .{ .index = .{ .dst = 3, .base = 2, .index = 0, .kind = .i32 } } },
        .{ .source = source, .op = .{ .ret = &.{3} } },
    };
    const functions = [_]?b.Function{.{ .slots = &.{ @enumFromInt(0), @enumFromInt(1), @enumFromInt(2), @enumFromInt(0) }, .inputs = &.{}, .outputs = &.{3}, .code = &code, .write_destinations = &.{@enumFromInt(0)} }};
    const program = b.Program{ .graph = &graph, .functions = &functions };
    try b.verify(a, program);
    code[2].op.array.elements = &.{};
    try std.testing.expectError(error.InvalidBytecode, b.verify(a, program));
    code[2].op.array.elements = &.{1};
    try std.testing.expectError(error.InvalidBytecode, b.verify(a, program));
    code[2].op.array.elements = &.{0};
    code[3].op.index.index = 1;
    try std.testing.expectError(error.InvalidBytecode, b.verify(a, program));
    code[3].op = .{ .capture_write = .{ .dst = 0, .place = .{ .root = 1, .path = &.{} } } };
    try std.testing.expectError(error.InvalidBytecode, b.verify(a, program));
    code[3].op = .{ .check_place = .{ .root = 2, .path = &.{.{ .field = 0 }} } };
    try std.testing.expectError(error.InvalidBytecode, b.verify(a, program));
    code[3].op = .{ .check_place = .{ .root = 2, .path = &.{.{ .element = .{ .slot = 99, .kind = .i32 } }} } };
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

test "bytecode validates the final destination before RHS effects" {
    try std.testing.expectError(error.ExecutionIndexOutOfBounds, execute(
        \\fail() -> (.result: Int32 = 0) := { abort }
        \\main() -> () := {
        \\    values :: [2]Int32 = (1, 2)
        \\    index :: UIntNative = 2
        \\    values[index] = fail()
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

test "bytecode VM retains invocations and resets poisoned execution contexts" {
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
    const context = executor.context().storage.context;
    result = try executor.invoke(@enumFromInt(0), result);
    try std.testing.expectEqual(context, executor.context().storage.context);
    try std.testing.expectEqual(@as(i128, 42), result[0].array[0].integer);
    const cells = executor.context().storage.cells;
    try std.testing.expectError(error.InvalidArguments, executor.invoke(@enumFromInt(0), &.{.{ .array = &.{.{ .boolean = false }} }}));
    try std.testing.expectError(error.InvalidEntry, executor.invoke(@enumFromInt(99), &.{}));
    try std.testing.expectEqual(cells, executor.context().storage.cells);
    executor.limits.instructions = 0;
    try std.testing.expectError(error.ExecutionInstructionLimit, executor.invoke(@enumFromInt(0), &.{.{ .array = &.{.{ .integer = 42 }} }}));
    for (executor.context().storage.frames.items) |frame_| try std.testing.expect(!frame_.alive);
    executor.limits.instructions = 100;
    try std.testing.expectError(error.ExecutionContextPoisoned, executor.invoke(@enumFromInt(0), &.{.{ .array = &.{.{ .integer = 42 }} }}));
    executor.reset();
    result = try executor.invoke(@enumFromInt(0), &.{.{ .array = &.{.{ .integer = 42 }} }});
    try std.testing.expect(context != executor.context().storage.context);
    try std.testing.expectEqual(@as(i128, 42), result[0].array[0].integer);
    executor.limits.call_depth = 0;
    try std.testing.expectError(error.ExecutionCallDepthLimit, executor.run(@enumFromInt(0), result));
    // Per-invocation fuel resets, whereas retained storage keeps its cumulative
    // allocation budget. Exhaustion poisons the context until explicit reset.
    var retained = try vm.Vm.init(a, .{ .graph = &graph, .functions = &functions }, .{ .instructions = 1, .value_cells = 9 });
    defer retained.deinit();
    const input = [_]b.Value{.{ .array = &.{.{ .integer = 42 }} }};
    _ = try retained.invoke(@enumFromInt(0), &input);
    try std.testing.expectEqual(@as(usize, 1), retained.steps);
    try std.testing.expectError(error.ExecutionMemoryLimit, retained.invoke(@enumFromInt(0), &input));
    try std.testing.expectError(error.ExecutionContextPoisoned, retained.invoke(@enumFromInt(0), &input));
    retained.reset();
    _ = try retained.invoke(@enumFromInt(0), &input);
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
    var storage = try Storage.init(arena.allocator(), 100);
    const first = try storage.enter(1);
    const slots = try storage.slots(first);
    try slots.put(0, .{ .integer = 42 });
    const reference = @import("../5_codegen/bytecode/value.zig").Reference{
        .context = storage.context,
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
    try std.testing.expectError(error.ExecutionDeadReference, slots.get(0));
    try std.testing.expectError(error.ExecutionDeadReference, slots.put(0, .unit));
    const second = try storage.enter(1);
    try std.testing.expect(first != second);
    try std.testing.expectError(error.ExecutionDeadReference, storage.read(reference));
    try std.testing.expectError(error.ExecutionDeadReference, storage.validateLive(&.{.{ .record = &.{readonly} }}));
}

test "bytecode storage separates vacant slots from initialized Void" {
    const Storage = @import("storage.zig").Storage;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var storage = try Storage.init(arena.allocator(), 100);
    const frame = try storage.enter(2);
    const slots = try storage.slots(frame);
    const Reference = @import("../5_codegen/bytecode/value.zig").Reference;
    const vacant = Reference{ .context = storage.context, .frame = frame, .root = 0, .path = &.{}, .mutability = .read_write };
    try std.testing.expectError(error.ExecutionUninitializedStorage, slots.get(0));
    try std.testing.expectError(error.ExecutionUninitializedStorage, storage.read(vacant));
    try std.testing.expectError(error.ExecutionUninitializedStorage, storage.borrow(vacant, .read_only));
    try std.testing.expectError(error.ExecutionUninitializedStorage, storage.store(vacant, .unit));
    try slots.put(0, .unit);
    try std.testing.expectEqual(.unit, try storage.read(vacant));
    _ = try storage.borrow(vacant, .read_only);
    try std.testing.expectError(error.ExecutionUninitializedStorage, slots.get(1));
}

test "bytecode cleanup identity follows storage across frames without reading vacant values" {
    const Storage = @import("storage.zig").Storage;
    const v = @import("../5_codegen/bytecode/value.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var storage = try Storage.init(arena.allocator(), 100);
    const layout = [_]b.Cleanup{
        .{ .root = 0, .path = &.{}, .flag = 2 },
        .{ .root = 0, .path = &.{.{ .field = 0 }}, .flag = 3 },
        .{ .root = 0, .path = &.{.{ .field = 1 }}, .flag = 4 },
    };
    const caller = try storage.enterCleanup(5, &layout);
    const slots = try storage.slots(caller);
    var path: [64]v.Projection = undefined;
    const owner = try storage.resolveCleanup(caller, .{ .root = 0, .path = &.{} }, &path);
    try std.testing.expect(!try storage.cleanupTest(owner));
    try std.testing.expectError(error.ExecutionUninitializedStorage, storage.read(owner));
    const vacant_field = try storage.resolveCleanup(caller, .{ .root = 0, .path = &.{.{ .field = 0 }} }, &path);
    try std.testing.expect(!try storage.cleanupTest(vacant_field));
    _ = try storage.cleanupSet(owner, true);
    try std.testing.expectError(error.ExecutionUninitializedStorage, storage.read(owner));
    _ = try storage.cleanupSet(owner, false);
    const record = b.Value{ .record = &.{ .{ .integer = 10 }, .{ .integer = 20 } } };
    try slots.put(0, record);
    _ = try storage.cleanupSet(owner, true);
    const borrowed = try storage.borrow(owner, .read_write);
    const callee = try storage.enter(1);
    try (try storage.slots(callee)).put(0, borrowed);
    const field = try storage.resolveCleanup(callee, .{ .root = 0, .path = &.{ .dereference, .{ .field = 0 } } }, &path);
    try std.testing.expect(try storage.cleanupTest(field));
    _ = try storage.cleanupSet(field, false);
    // The whole record is now incomplete; only the sibling may be cleaned.
    try std.testing.expect(!try storage.cleanupTest(owner));
    const sibling = try storage.resolveCleanup(caller, .{ .root = 0, .path = &.{.{ .field = 1 }} }, &path);
    try std.testing.expect(try storage.cleanupTest(sibling));
    var readonly = borrowed.reference;
    readonly.mutability = .read_only;
    try std.testing.expectError(error.ExecutionReadonlyReference, storage.cleanupSet(readonly, false));
    // A value snapshot does not copy the original storage's cleanup identity.
    try slots.put(1, record);
    const copy = try storage.resolveCleanup(caller, .{ .root = 1, .path = &.{} }, &path);
    try std.testing.expectError(error.ExecutionMissingCleanup, storage.cleanupTest(copy));
    storage.leave(callee);
    _ = try storage.cleanupSet(owner, false);
    try std.testing.expect(!try storage.cleanupTest(owner));
    storage.leave(caller);
    try std.testing.expectError(error.ExecutionDeadReference, storage.cleanupTest(owner));
}

test "bytecode lifecycle instructions update caller state through an ordinary reference argument" {
    const g = @import("../4_semantics/global/graph.zig");
    const a = std.testing.allocator;
    var graph: g.GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    try graph.types.appendSlice(a, &.{ .{ .builtin = .Int32 }, .{ .builtin = .Bool }, .{ .pointer = .{ .child = @enumFromInt(0), .mutability = .read_write } } });
    const source = @import("../4_semantics/primitives/schema.zig").SourceRef{ .file_index = 0, .offset = 0 };
    try graph.fields.appendSlice(a, &.{
        .{ .name = .{ .start = 0, .len = 0 }, .ty = @enumFromInt(1), .source = source },
        .{ .name = .{ .start = 0, .len = 0 }, .ty = @enumFromInt(2), .source = source },
    });
    try graph.functions.appendSlice(a, &.{
        .{ .declaration = @enumFromInt(0), .input = .{ .start = 0, .len = 0 }, .output = .{ .start = 0, .len = 1 } },
        .{ .declaration = @enumFromInt(0), .input = .{ .start = 1, .len = 1 }, .output = .{ .start = 0, .len = 0 } },
    });
    const caller = [_]b.Instruction{
        .{ .source = source, .op = .{ .cleanup_test = .{ .dst = 3, .place = .{ .root = 0, .path = &.{} } } } },
        .{ .source = source, .op = .{ .branch = .{ .condition = 3, .yes = 8, .no = 2 } } },
        .{ .source = source, .op = .{ .constant = .{ .dst = 0, .value = .{ .integer = 42 } } } },
        .{ .source = source, .op = .{ .borrow = .{ .dst = 1, .permission = .read_write, .place = .{ .root = 0, .path = &.{} } } } },
        .{ .source = source, .op = .{ .cleanup_set = .{ .place = .{ .root = 0, .path = &.{} }, .enabled = true } } },
        .{ .source = source, .op = .{ .call = .{ .function = @enumFromInt(1), .args = &.{1}, .outputs = &.{} } } },
        .{ .source = source, .op = .{ .cleanup_test = .{ .dst = 3, .place = .{ .root = 0, .path = &.{} } } } },
        .{ .source = source, .op = .{ .ret = &.{3} } },
        .{ .source = source, .op = .abort_ },
    };
    const callee = [_]b.Instruction{
        .{ .source = source, .op = .{ .cleanup_set = .{ .place = .{ .root = 0, .path = &.{.dereference} }, .enabled = false } } },
        .{ .source = source, .op = .{ .ret = &.{} } },
    };
    var functions = [_]?b.Function{
        .{ .slots = &.{ @enumFromInt(0), @enumFromInt(2), @enumFromInt(1), @enumFromInt(1) }, .inputs = &.{}, .outputs = &.{3}, .code = &caller, .cleanup = &.{.{ .root = 0, .path = &.{}, .flag = 2 }} },
        .{ .slots = &.{@enumFromInt(2)}, .inputs = &.{0}, .outputs = &.{}, .code = &callee },
    };
    const program = b.Program{ .graph = &graph, .functions = &functions };
    var executor = try vm.Vm.init(a, program, .{});
    defer executor.deinit();
    try std.testing.expect(!(try executor.run(@enumFromInt(0), &.{}))[0].boolean);
    var bounded = try vm.Vm.init(a, program, .{ .instructions = 10 });
    defer bounded.deinit();
    try std.testing.expectError(error.ExecutionInstructionLimit, bounded.run(@enumFromInt(0), &.{}));
    // Metadata cannot alias owner slots or reuse one flag for distinct paths.
    functions[0].?.cleanup = &.{.{ .root = 2, .path = &.{}, .flag = 2 }};
    try std.testing.expectError(error.InvalidBytecode, b.verify(a, program));
    functions[0].?.cleanup = &.{ .{ .root = 0, .path = &.{}, .flag = 2 }, .{ .root = 0, .path = &.{}, .flag = 3 } };
    try std.testing.expectError(error.InvalidBytecode, b.verify(a, program));
    functions[0].?.cleanup = &.{.{ .root = 0, .path = &.{.{ .field = 0 }}, .flag = 2 }};
    try std.testing.expectError(error.InvalidBytecode, b.verify(a, program));
    functions[0].?.cleanup = &.{.{ .root = 0, .path = &.{}, .flag = 2 }};
    graph.types.items[2].pointer.mutability = .read_only;
    try std.testing.expectError(error.InvalidBytecode, b.verify(a, program));
}

test "bytecode references cannot name another execution context" {
    const Storage = @import("storage.zig").Storage;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var first = try Storage.init(arena.allocator(), 100);
    var second = try Storage.init(arena.allocator(), 100);
    const frame = try first.enter(1);
    const old_slots = try first.slots(frame);
    const other_frame = try second.enter(1);
    try std.testing.expectEqual(frame, other_frame);
    try (try first.slots(frame)).put(0, .{ .integer = 42 });
    try (try second.slots(other_frame)).put(0, .{ .integer = 99 });
    var path: [64]@import("../5_codegen/bytecode/value.zig").Projection = undefined;
    const reference = try first.borrow(try first.resolve(frame, .{ .root = 0, .path = &.{} }, &path), .read_write);
    try std.testing.expectError(error.ExecutionForeignReference, second.read(reference.reference));
    try std.testing.expectError(error.ExecutionForeignReference, second.store(reference.reference, .unit));
    try std.testing.expectError(error.ExecutionForeignReference, second.borrow(reference.reference, .read_only));
    try std.testing.expectError(error.ExecutionForeignReference, second.cleanupTest(reference.reference));
    try std.testing.expectError(error.ExecutionForeignReference, second.cleanupSet(reference.reference, false));
    try std.testing.expectError(error.ExecutionForeignReference, second.validateLive(&.{.{ .record = &.{reference} }}));
    try std.testing.expectEqual(@as(i128, 99), (try (try second.slots(other_frame)).get(0)).integer);
    first.leave(frame);
    first = try Storage.init(arena.allocator(), 100);
    const reset_frame = try first.enter(1);
    try (try first.slots(reset_frame)).put(0, .{ .integer = 17 });
    try std.testing.expectEqual(frame, reset_frame);
    try std.testing.expectError(error.ExecutionForeignReference, first.read(reference.reference));
    try std.testing.expectError(error.ExecutionForeignReference, old_slots.get(0));
    try std.testing.expectError(error.ExecutionForeignReference, old_slots.put(0, .unit));
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
        .{ .source = source, .op = .{ .borrow = .{ .dst = 1, .permission = .read_only, .place = .{ .root = 0, .path = &.{} } } } },
        .{ .source = source, .op = .{ .load = .{ .dst = 0, .place = .{ .root = 1, .path = &.{.dereference} } } } },
        .{ .source = source, .op = .{ .ret = &.{1} } },
    };
    const functions = [_]?b.Function{.{ .slots = &.{ @enumFromInt(0), @enumFromInt(1), @enumFromInt(2) }, .inputs = &.{}, .outputs = &.{1}, .code = &code, .write_destinations = &.{@enumFromInt(0)} }};
    const program = b.Program{ .graph = &graph, .functions = &functions };
    var executor = try vm.Vm.init(a, program, .{});
    defer executor.deinit();
    try std.testing.expectError(error.ExecutionDeadReference, executor.run(@enumFromInt(0), &.{}));
    code[2].op = .{ .capture_write = .{ .dst = 0, .place = .{ .root = 1, .path = &.{.dereference} } } };
    try std.testing.expectError(error.InvalidBytecode, b.verify(a, program));
    code[2].op = .{ .borrow = .{ .dst = 2, .permission = .read_write, .place = .{ .root = 1, .path = &.{.dereference} } } };
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
        .{ .source = source, .op = .{ .choice = .{ .dst = 2, .ordinal = 0, .variant = @enumFromInt(0), .payload = 0 } } },
        .{ .source = source, .op = .{ .payload = .{ .dst = 0, .src = 2, .ordinal = 0, .variant = @enumFromInt(0) } } },
        .{ .source = source, .op = .{ .ret = &.{0} } },
    };
    const functions = [_]?b.Function{.{ .slots = &.{ @enumFromInt(0), @enumFromInt(1), @enumFromInt(2) }, .inputs = &.{}, .outputs = &.{0}, .code = &code }};
    const program = b.Program{ .graph = &graph, .functions = &functions };
    try b.verify(a, program);
    code[2].op.choice.ordinal = std.math.maxInt(u32);
    try std.testing.expectError(error.InvalidBytecode, b.verify(a, program));
    code[2].op.choice.ordinal = 0;
    code[3].op.payload.ordinal = 1;
    try std.testing.expectError(error.InvalidBytecode, b.verify(a, program));
    code[3].op = .{ .is_variant = .{ .dst = 1, .src = 2, .variant = @enumFromInt(0), .ordinal = 1, .invert = false } };
    try std.testing.expectError(error.InvalidBytecode, b.verify(a, program));
    code[3].op.is_variant.ordinal = 0;
    try b.verify(a, program);
    code[3].op = .{ .branch_variant = .{ .src = 2, .variant = @enumFromInt(0), .ordinal = 1, .yes = 4, .no = 4 } };
    try std.testing.expectError(error.InvalidBytecode, b.verify(a, program));
    code[3].op.branch_variant.ordinal = 0;
    try b.verify(a, program);
    code[3].op = .{ .payload = .{ .dst = 0, .src = 2, .variant = @enumFromInt(0), .ordinal = 0 } };
    code[2].op.choice.payload = 1;
    try std.testing.expectError(error.InvalidBytecode, b.verify(a, program));
    code[2].op.choice.payload = null;
    try std.testing.expectError(error.InvalidBytecode, b.verify(a, program));
    code[2].op.choice.variant = @enumFromInt(99);
    try std.testing.expectError(error.InvalidBytecode, b.verify(a, program));
    code[2].op.choice.variant = @enumFromInt(1);
    code[2].op.choice.ordinal = 1;
    // The payload instruction is well typed but names an inactive alternative.
    // Runtime checks backstop the frontend's proof of the active variant.
    var executor = try vm.Vm.init(a, program, .{});
    defer executor.deinit();
    try std.testing.expectError(error.ExecutionInactiveVariant, executor.run(@enumFromInt(0), &.{}));
}

test "bytecode calls return several typed outputs" {
    try std.testing.expectEqual(@as(i128, 42), try execute(
        \\split_number(.value: Int32) -> (.first: Int32, .second: Int32) := {
        \\    first = value * 10
        \\    second = value - 2
        \\}
        \\main() -> (.status_code: Int32 = 0) := {
        \\    result ::= split_number(.value = 4)
        \\    status_code = result.first + result.second
        \\}
    , .{}));
}

test "bytecode multiple outputs retain caller reference lifetimes" {
    try std.testing.expectEqual(@as(i128, 42), try execute(
        \\inspect(.value: &Int32) -> (.reference: &Int32, .present: Bool = true) := {
        \\    reference = value
        \\}
        \\main() -> (.status_code: Int32 = 0) := {
        \\    value :: Int32 = 42
        \\    result ::= inspect(.value = &value)
        \\    if result.present { status_code = result.reference& }
        \\}
    , .{}));
}

test "bytecode verifier checks every call output destination" {
    const g = @import("../4_semantics/global/graph.zig");
    var graph: g.GlobalSemanticGraph = .{};
    defer graph.deinit(std.testing.allocator);
    const a = std.testing.allocator;
    const source = @import("../4_semantics/primitives/schema.zig").SourceRef{ .file_index = 0, .offset = 0 };
    try graph.types.append(a, .{ .builtin = .Int32 });
    try graph.types.append(a, .{ .builtin = .Bool });
    for (0..2) |_| try graph.fields.append(a, .{ .name = .{ .start = 0, .len = 0 }, .ty = @enumFromInt(0), .source = source });
    try graph.functions.append(a, .{ .declaration = @enumFromInt(0), .input = .{ .start = 0, .len = 0 }, .output = .{ .start = 0, .len = 2 } });
    var code = [_]b.Instruction{
        .{ .source = source, .op = .{ .call = .{ .function = @enumFromInt(0), .args = &.{}, .outputs = &.{ 0, 2 } } } },
        .{ .source = source, .op = .{ .ret = &.{ 0, 2 } } },
    };
    const functions = [_]?b.Function{.{ .slots = &.{ @enumFromInt(0), @enumFromInt(1), @enumFromInt(0) }, .inputs = &.{}, .outputs = &.{ 0, 2 }, .code = &code }};
    const program = b.Program{ .graph = &graph, .functions = &functions };
    // Both output slots become initialized on the returning call edge.
    try b.verify(a, program);
    code[0].op.call.outputs = &.{0};
    try std.testing.expectError(error.InvalidBytecode, b.verify(a, program));
    code[0].op.call.outputs = &.{ 0, 0 };
    try std.testing.expectError(error.InvalidBytecode, b.verify(a, program));
    code[0].op.call.outputs = &.{ 0, 1 };
    try std.testing.expectError(error.InvalidBytecode, b.verify(a, program));
    code[0].op.call.outputs = &.{ 0, 99 };
    try std.testing.expectError(error.InvalidBytecode, b.verify(a, program));
}

test "bytecode write destinations capture aliases before later writes" {
    const g = @import("../4_semantics/global/graph.zig");
    const a = std.testing.allocator;
    var graph: g.GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    const source = @import("../4_semantics/primitives/schema.zig").SourceRef{ .file_index = 0, .offset = 0 };
    try graph.types.append(a, .{ .builtin = .Int32 });
    try graph.types.append(a, .{ .pointer = .{ .child = @enumFromInt(0), .mutability = .read_write } });
    try graph.types.append(a, .{ .builtin = .Bool });
    try graph.fields.append(a, .{ .name = .{ .start = 0, .len = 0 }, .ty = @enumFromInt(0), .source = source });
    try graph.functions.append(a, .{ .declaration = @enumFromInt(0), .input = .{ .start = 0, .len = 0 }, .output = .{ .start = 0, .len = 1 } });
    var code = [_]b.Instruction{
        .{ .source = source, .op = .{ .constant = .{ .dst = 0, .value = .{ .integer = 40 } } } },
        .{ .source = source, .op = .{ .constant = .{ .dst = 1, .value = .{ .integer = 1 } } } },
        .{ .source = source, .op = .{ .constant = .{ .dst = 3, .value = .{ .boolean = true } } } },
        .{ .source = source, .op = .{ .borrow = .{ .dst = 2, .permission = .read_write, .place = .{ .root = 0, .path = &.{} } } } },
        .{ .source = source, .op = .{ .jump = 5 } },
        .{ .source = source, .op = .{ .capture_write = .{ .dst = 0, .place = .{ .root = 2, .path = &.{.dereference} } } } },
        .{ .source = source, .op = .{ .borrow = .{ .dst = 2, .permission = .read_write, .place = .{ .root = 1, .path = &.{} } } } },
        .{ .source = source, .op = .{ .constant = .{ .dst = 1, .value = .{ .integer = 42 } } } },
        .{ .source = source, .op = .{ .check_write_cleanup = 0 } },
        .{ .source = source, .op = .{ .store = .{ .destination = 0, .value = 1 } } },
        .{ .source = source, .op = .{ .activate_write_cleanup = 0 } },
        .{ .source = source, .op = .{ .copy = .{ .dst = 4, .src = 3 } } },
        .{ .source = source, .op = .{ .ret = &.{0} } },
    };
    var functions = [_]?b.Function{.{ .slots = &.{ @enumFromInt(0), @enumFromInt(0), @enumFromInt(1), @enumFromInt(2), @enumFromInt(2) }, .inputs = &.{}, .outputs = &.{0}, .code = &code, .write_destinations = &.{@enumFromInt(0)} }};
    const program = b.Program{ .graph = &graph, .functions = &functions };
    var executor = try vm.Vm.init(a, program, .{});
    defer executor.deinit();
    try std.testing.expectEqual(@as(i128, 42), (try executor.run(@enumFromInt(0), &.{}))[0].integer);
    const check = code[8];
    code[8].op.check_write_cleanup = 1;
    try std.testing.expectError(error.InvalidBytecode, b.verify(a, program));
    code[8] = check;
    code[8].op = .{ .copy = .{ .dst = 4, .src = 3 } };
    try std.testing.expectError(error.UninitializedBytecodeDestination, b.verify(a, program));
    code[8] = check;
    const activation = code[10];
    code[10].op.activate_write_cleanup = 1;
    try std.testing.expectError(error.InvalidBytecode, b.verify(a, program));
    code[10] = activation;
    code[10].op = .{ .check_write_cleanup = 0 };
    try std.testing.expectError(error.UninitializedBytecodeDestination, b.verify(a, program));
    code[10] = activation;
    const original_copy = code[11];
    code[11].op = .{ .store = .{ .destination = 0, .value = 1 } };
    try std.testing.expectError(error.UninitializedBytecodeDestination, b.verify(a, program));
    code[11] = original_copy;
    // Captured cleanup is required before RHS execution and charged when the
    // activation executes, just like an explicit cleanup_set instruction.
    code[5].op.capture_write.activate_cleanup = true;
    try std.testing.expectError(error.ExecutionMissingCleanup, executor.run(@enumFromInt(0), &.{}));
    functions[0].?.cleanup = &.{.{ .root = 0, .path = &.{}, .flag = 3 }};
    code[2].op.constant.value = .{ .boolean = false };
    functions[0].?.outputs = &.{4};
    code[12].op = .{ .ret = &.{4} };
    graph.fields.items[0].ty = @enumFromInt(2);
    var tracked = try vm.Vm.init(a, program, .{});
    defer tracked.deinit();
    try std.testing.expect((try tracked.run(@enumFromInt(0), &.{}))[0].boolean);
    // Initialization flags also describe scalar fields. Replacing an already
    // initialized scalar must preserve activation without requiring destruction.
    code[2].op.constant.value = .{ .boolean = true };
    try std.testing.expectError(error.ExecutionPendingCleanup, tracked.run(@enumFromInt(0), &.{}));
    code[5].op.capture_write.require_cleanup = false;
    var scalar_replacement = try vm.Vm.init(a, program, .{});
    defer scalar_replacement.deinit();
    try std.testing.expect((try scalar_replacement.run(@enumFromInt(0), &.{}))[0].boolean);
    code[5].op.capture_write.require_cleanup = true;
    code[2].op.constant.value = .{ .boolean = false };
    var bounded = try vm.Vm.init(a, program, .{ .instructions = 11 });
    defer bounded.deinit();
    try std.testing.expectError(error.ExecutionInstructionLimit, bounded.run(@enumFromInt(0), &.{}));
    functions[0].?.cleanup = &.{};
    functions[0].?.outputs = &.{0};
    code[12].op = .{ .ret = &.{0} };
    graph.fields.items[0].ty = @enumFromInt(0);
    code[5].op.capture_write.activate_cleanup = false;
    // Even a branch that happens to capture at runtime must capture on every
    // incoming path before the store. Destination state is separate from values.
    code[4].op = .{ .branch = .{ .condition = 3, .yes = 5, .no = 6 } };
    try std.testing.expectError(error.UninitializedBytecodeDestination, b.verify(a, program));
    code[4].op = .{ .jump = 5 };
    code[9].op.store.destination = 1;
    try std.testing.expectError(error.InvalidBytecode, b.verify(a, program));
    code[9].op.store.destination = 0;
    code[9].op.store.value = 3;
    try std.testing.expectError(error.InvalidBytecode, b.verify(a, program));
    code[9].op.store.value = 1;
    functions[0].?.write_destinations = &.{@enumFromInt(2)};
    try std.testing.expectError(error.InvalidBytecode, b.verify(a, program));
}

test "bytecode captured write access retains bounds and storage liveness" {
    const Storage = @import("storage.zig").Storage;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var storage = try Storage.init(arena.allocator(), 100);
    const frame = try storage.enter(3);
    const slots = try storage.slots(frame);
    try slots.put(0, .{ .array = &.{ .{ .integer = 1 }, .{ .integer = 2 } } });
    try slots.put(1, .{ .integer = 0 });
    const destination = try storage.captureWrite(frame, .{ .root = 0, .path = &.{.{ .element = .{ .slot = 1, .kind = .i32 } }} }, false);
    try slots.put(1, .{ .integer = 1 });
    try std.testing.expectEqual(@as(usize, 0), try commitWrite(&storage, destination, .{ .integer = 42 }));
    try std.testing.expectEqual(@as(i128, 42), (try slots.get(0)).array[0].integer);
    try std.testing.expectEqual(@as(i128, 2), (try slots.get(0)).array[1].integer);
    try slots.put(1, .{ .integer = 2 });
    try std.testing.expectError(error.ExecutionIndexOutOfBounds, storage.captureWrite(frame, .{ .root = 0, .path = &.{.{ .element = .{ .slot = 1, .kind = .i32 } }} }, false));
    try std.testing.expectError(error.ExecutionUninitializedStorage, storage.captureWrite(frame, .{ .root = 2, .path = &.{} }, false));
    var path: [64]@import("../5_codegen/bytecode/value.zig").Projection = undefined;
    const array = try storage.resolve(frame, .{ .root = 0, .path = &.{} }, &path);
    try slots.put(2, try storage.borrow(array, .read_only));
    try std.testing.expectError(error.ExecutionReadonlyReference, storage.captureWrite(frame, .{ .root = 2, .path = &.{.dereference} }, false));
    var foreign = try Storage.init(arena.allocator(), 100);
    try std.testing.expectError(error.ExecutionForeignReference, commitWrite(&foreign, destination, .{ .integer = 0 }));
    try slots.put(0, .{ .array = &.{} });
    try std.testing.expectError(error.ExecutionIndexOutOfBounds, commitWrite(&storage, destination, .{ .integer = 0 }));
    storage.leave(frame);
    try std.testing.expectError(error.ExecutionDeadReference, commitWrite(&storage, destination, .{ .integer = 0 }));
}

test "bytecode captured writes activate referent cleanup across caller frames" {
    const Storage = @import("storage.zig").Storage;
    const v = @import("../5_codegen/bytecode/value.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var storage = try Storage.init(arena.allocator(), 100);
    const layout = [_]b.Cleanup{
        .{ .root = 0, .path = &.{}, .flag = 2 },
        .{ .root = 0, .path = &.{.{ .field = 0 }}, .flag = 3 },
        .{ .root = 0, .path = &.{.{ .field = 1 }}, .flag = 4 },
    };
    const caller = try storage.enterCleanup(5, &layout);
    const caller_slots = try storage.slots(caller);
    // Identical zero-sized values retain distinct projected cleanup identities.
    const empty = b.Value{ .record = &.{} };
    const pair = b.Value{ .record = &.{ empty, empty } };
    try caller_slots.put(0, pair);
    try caller_slots.put(1, pair);
    const callee = try storage.enterCleanup(2, &.{.{ .root = 0, .path = &.{}, .flag = 1 }});
    const callee_slots = try storage.slots(callee);
    var first_path: [64]v.Projection = undefined;
    var second_path: [64]v.Projection = undefined;
    const first = try storage.resolve(caller, .{ .root = 0, .path = &.{.{ .field = 0 }} }, &first_path);
    const second = try storage.resolve(caller, .{ .root = 0, .path = &.{.{ .field = 1 }} }, &second_path);
    try callee_slots.put(0, try storage.borrow(first, .read_write));
    const destination = try storage.captureWrite(callee, .{ .root = 0, .path = &.{.dereference} }, true);
    try callee_slots.put(0, try storage.borrow(second, .read_write));
    try std.testing.expectEqual(@as(usize, 1), try storage.checkWriteCleanup(destination));
    try storage.write(destination, empty);
    // The storage write itself changes neither the captured target's flag nor
    // the sibling's flag. Only the explicit activation publishes cleanup.
    try std.testing.expect(!try storage.cleanupTest(first));
    try std.testing.expect(!try storage.cleanupTest(second));
    // Activation also inspects ancestor readiness; charge that work without
    // confusing it with the number of flags whose state changes.
    try std.testing.expect(try storage.activateWriteCleanup(destination) > 1);
    try std.testing.expect(try storage.cleanupTest(first));
    try std.testing.expect(!try storage.cleanupTest(second));
    try std.testing.expect(!(try callee_slots.get(1)).boolean);
    try std.testing.expect(!(try caller_slots.get(2)).boolean);
    // A value copy has no obligation until the checked graph supplies one.
    try std.testing.expectError(error.ExecutionMissingCleanup, storage.captureWrite(caller, .{ .root = 1, .path = &.{.{ .field = 0 }} }, true));
    const plain = try storage.captureWrite(callee, .{ .root = 0, .path = &.{.dereference} }, false);
    try std.testing.expectEqual(@as(usize, 0), try commitWrite(&storage, plain, empty));
    try std.testing.expect(!try storage.cleanupTest(second));
    // Whole-value initialization activates exactly the captured owner's subtree.
    const owner = try storage.captureWrite(caller, .{ .root = 0, .path = &.{} }, true);
    try std.testing.expectError(error.ExecutionPendingCleanup, commitWrite(&storage, owner, pair));
    try std.testing.expect(!(try caller_slots.get(2)).boolean);
    _ = try storage.cleanupSet(first, false);
    try std.testing.expectEqual(@as(usize, 6), try commitWrite(&storage, owner, pair));
    try std.testing.expect((try caller_slots.get(2)).boolean);
    try std.testing.expect(try storage.cleanupTest(second));
    const replacement = b.Value{ .record = &.{ .{ .integer = 1 }, .{ .integer = 2 } } };
    try std.testing.expectError(error.ExecutionPendingCleanup, commitWrite(&storage, owner, replacement));
    try std.testing.expect((try caller_slots.get(0)).record[0] == .record);
    _ = try storage.cleanupSet(first, false);
    try caller_slots.put(0, .{ .record = &.{} });
    try std.testing.expectError(error.ExecutionInvalidReference, commitWrite(&storage, destination, empty));
    try std.testing.expect(!try storage.cleanupTest(first));
    storage.leave(caller);
    try std.testing.expectError(error.ExecutionDeadReference, commitWrite(&storage, destination, empty));
}

// Exercise the same explicit protocol as the executor, including failures
// before commit and activation only after a successful value write.
fn commitWrite(storage: *@import("storage.zig").Storage, destination: @import("storage.zig").WriteDestination, value: b.Value) !usize {
    const checked = try storage.checkWriteCleanup(destination);
    try storage.write(destination, value);
    return checked + try storage.activateWriteCleanup(destination);
}

test "compile-time evaluation exports aggregate constants and rejects escaping references" {
    const evaluate = @import("evaluate.zig").evaluate;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const files = [_]sf.SourceFile{
        .{ .path = "app/main.rg", .code =
        \\Pair: Type = (.sum: Int32, .items: [2]Int32)
        \\calculate(.base: Int32) -> (.result: Pair) := {
        \\    sum :: Int32 = base
        \\    index :: Int32 = 0
        \\    while index < 2 { sum = sum + 1 index = index + 1 }
        \\    result = (.sum = sum, .items = (base, sum))
        \\}
        \\borrow(.value: &Int32) -> (.result: &Int32) := { result = value }
        \\main() -> (.status_code: Int32 = 0) := {
        \\    result ::= calculate(.base = 40)
        \\    status_code = borrow(.value = &result.sum)&
        \\}
        },
        .{ .path = "arithmetic_core/scalar_arithmetic.rg", .origin = .bundled_core, .code = @import("../test_support.zig").arithmetic_core_source },
    };
    var diagnostics = diag.Diagnostics.init(&a, &files);
    defer diagnostics.deinit();
    var pipeline = frontend.FrontendPipeline.init(a, std.testing.io, &diagnostics, .{});
    defer pipeline.deinit();
    const graph_const = try pipeline.semantizeGlobalFiles(&files);
    const graph = @constCast(graph_const);
    const source = @import("../4_semantics/primitives/schema.zig").SourceRef{ .file_index = 0, .offset = 0 };
    var found = false;
    for (graph.functions.items, 0..) |function, index| {
        const name = graph.text(graph.declarationSourceName(function.declaration));
        const id: @import("../4_semantics/global/graph.zig").GlobalFunctionId = @enumFromInt(index);
        if (std.mem.eql(u8, name, "calculate")) {
            found = true;
            const result = try evaluate(a, graph, &diagnostics, id, &.{.{ .integer = 40 }}, source, .{});
            const record = graph.node(result[0]).content.struct_value_literal.fields;
            try std.testing.expectEqual(@as(i128, 42), graph.node(graph.value_fields.items[record.start].value).content.int_literal);
            const array = graph.node(graph.value_fields.items[record.start + 1].value).content.array_literal.elements;
            try std.testing.expectEqual(@as(i128, 40), graph.node(graph.node_refs.items[array.start]).content.int_literal);
            try std.testing.expectEqual(@as(i128, 42), graph.node(graph.node_refs.items[array.start + 1]).content.int_literal);
            var budget: vm.Limits = .{ .instructions = 1000, .value_cells = 1000 };
            _ = try @import("evaluate.zig").evaluateBudgeted(a, graph, &diagnostics, id, &.{.{ .integer = 40 }}, source, &budget);
            const spent_instructions = 1000 - budget.instructions;
            const spent_cells = 1000 - budget.value_cells;
            try std.testing.expect(spent_instructions != 0 and spent_cells != 0);
            _ = try @import("evaluate.zig").evaluateBudgeted(a, graph, &diagnostics, id, &.{.{ .integer = 40 }}, source, &budget);
            try std.testing.expectEqual(2 * spent_instructions, 1000 - budget.instructions);
            try std.testing.expectEqual(2 * spent_cells, 1000 - budget.value_cells);
            budget.instructions = 1;
            const nodes = graph.nodes.items.len;
            try std.testing.expectError(error.ExecutionInstructionLimit, @import("evaluate.zig").evaluateBudgeted(a, graph, &diagnostics, id, &.{.{ .integer = 40 }}, source, &budget));
            try std.testing.expectEqual(@as(usize, 0), budget.instructions);
            try std.testing.expectEqual(nodes, graph.nodes.items.len);
            try std.testing.expectError(error.ExecutionInstructionLimit, evaluate(a, graph, &diagnostics, id, &.{.{ .integer = 40 }}, source, .{ .instructions = 1 }));
            var cancellation: vm.Cancellation = .{};
            cancellation.cancel();
            try std.testing.expectError(error.ExecutionCancelled, evaluate(a, graph, &diagnostics, id, &.{.{ .integer = 40 }}, source, .{ .cancellation = &cancellation }));
            try std.testing.expectEqual(nodes, graph.nodes.items.len);
            try std.testing.expectEqual(nodes, graph.nodes.items.len);
        } else if (std.mem.eql(u8, name, "borrow")) {
            const nodes = graph.nodes.items.len;
            try std.testing.expectError(error.UnfreezableEvaluationInput, evaluate(a, graph, &diagnostics, id, &.{}, source, .{}));
            try std.testing.expectEqual(nodes, graph.nodes.items.len);
        }
    }
    try std.testing.expect(found);
}

test "bytecode retained lowering publishes stable programs for independent entries" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const files = [_]sf.SourceFile{
        .{ .path = "app/main.rg", .code =
        \\first() -> (.result: Int32 = 20) := {}
        \\second() -> (.result: Int32 = 22) := {}
        \\Mode: CEnum = (..one)
        \\unsupported() -> (.result: Int32 = 0) := { value: Mode = ..one }
        \\main() -> (.status_code: Int32 = 0) := {
        \\    status_code = first() + second()
        \\    unused ::= unsupported()
        \\}
        },
        .{ .path = "arithmetic_core/scalar_arithmetic.rg", .origin = .bundled_core, .code = @import("../test_support.zig").arithmetic_core_source },
    };
    var diagnostics = diag.Diagnostics.init(&a, &files);
    defer diagnostics.deinit();
    var pipeline = frontend.FrontendPipeline.init(a, std.testing.io, &diagnostics, .{});
    defer pipeline.deinit();
    const graph = try pipeline.semantizeGlobalFiles(&files);
    const Id = @import("../4_semantics/global/graph.zig").GlobalFunctionId;
    var first: ?Id = null;
    var second: ?Id = null;
    var unsupported: ?Id = null;
    var main: ?Id = null;
    for (graph.functions.items, 0..) |function, index| {
        const name = graph.text(graph.declarationSourceName(function.declaration));
        if (std.mem.eql(u8, name, "first")) first = @enumFromInt(index);
        if (std.mem.eql(u8, name, "second")) second = @enumFromInt(index);
        if (std.mem.eql(u8, name, "unsupported")) unsupported = @enumFromInt(index);
        if (std.mem.eql(u8, name, "main")) main = @enumFromInt(index);
    }
    var compiler = try lower.Lower.init(a, graph);
    const initial = try compiler.compile(first.?);
    try std.testing.expectEqual(compiler.functions.ptr, initial.functions.ptr);
    var executor = try vm.Vm.init(a, initial, .{});
    defer executor.deinit();
    const original_code = initial.functions[@intFromEnum(first.?)].?.code.ptr;
    // The pending queue allocates first; fail the subsequent table copy.
    var failing = std.testing.FailingAllocator.init(a, .{ .fail_index = 1 });
    compiler.allocator = failing.allocator();
    try std.testing.expectError(error.OutOfMemory, compiler.compile(second.?));
    compiler.allocator = a;
    try std.testing.expectEqual(initial.functions.ptr, compiler.functions.ptr);
    try std.testing.expect(initial.functions[@intFromEnum(second.?)] == null);
    try std.testing.expectError(error.InvalidEntry, compiler.compile(@enumFromInt(graph.functions.items.len)));
    try std.testing.expectError(error.UnsupportedExecution, compiler.compile(unsupported.?));
    try std.testing.expectError(error.UnsupportedExecution, compiler.compile(main.?));
    try std.testing.expectError(error.UnsupportedExecution, compiler.compile(main.?));
    try std.testing.expect(compiler.functions[@intFromEnum(main.?)] == null);
    const extended = try compiler.compile(second.?);
    try std.testing.expect(initial.functions.ptr != extended.functions.ptr);
    try std.testing.expect(initial.functions[@intFromEnum(second.?)] == null);
    try std.testing.expect(initial.functions[@intFromEnum(unsupported.?)] == null);
    try std.testing.expectEqual(original_code, extended.functions[@intFromEnum(first.?)].?.code.ptr);
    try std.testing.expectEqual(@as(i128, 20), (try executor.invoke(first.?, &.{}))[0].integer);
    try std.testing.expectError(error.InvalidEntry, executor.invoke(second.?, &.{}));
    var next = try vm.Vm.init(a, extended, .{});
    defer next.deinit();
    try std.testing.expectEqual(@as(i128, 22), (try next.invoke(second.?, &.{}))[0].integer);
    const repeated = try compiler.compile(first.?);
    try std.testing.expectEqual(extended.functions.ptr, repeated.functions.ptr);
    try std.testing.expectEqual(original_code, repeated.functions[@intFromEnum(first.?)].?.code.ptr);
}

test "compile-time evaluation proves its dependency unit before execution" {
    const evaluate = @import("evaluate.zig").evaluate;
    const g = @import("../4_semantics/global/graph.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const files = [_]sf.SourceFile{
        .{ .path = "app/main.rg", .code =
        \\seed() -> (.result: Int32 = 42) := {}
        \\good() -> (.result: Int32 = seed()) := {}
        \\bad() -> (.result: Int32 = 0) := {
        \\    fixed :: Int32 = 0
        \\    fixed = 1
        \\    result = fixed
        \\}
        \\wrapper() -> (.result: Int32 = bad()) := {}
        \\main() -> (.status_code: Int32 = 0) := {
        \\    status_code = good() + wrapper()
        \\}
        },
        .{ .path = "arithmetic_core/scalar_arithmetic.rg", .origin = .bundled_core, .code = @import("../test_support.zig").arithmetic_core_source },
    };
    var diagnostics = diag.Diagnostics.init(&a, &files);
    defer diagnostics.deinit();
    var pipeline = frontend.FrontendPipeline.init(a, std.testing.io, &diagnostics, .{});
    defer pipeline.deinit();
    const graph = @constCast(try pipeline.semantizeGlobalFiles(&files));
    var good: ?g.GlobalFunctionId = null;
    var wrapper: ?g.GlobalFunctionId = null;
    var bad: ?g.GlobalFunctionId = null;
    for (graph.functions.items, 0..) |function, raw| {
        const name = graph.text(graph.declarationSourceName(function.declaration));
        if (std.mem.eql(u8, name, "good")) good = @enumFromInt(raw);
        if (std.mem.eql(u8, name, "wrapper")) wrapper = @enumFromInt(raw);
        if (std.mem.eql(u8, name, "bad")) bad = @enumFromInt(raw);
    }
    // Introduce a temporal error after ordinary frontend completion. The
    // evaluator must prove its selected unit itself, not trust the old proof
    // or require every unrelated function body to be valid.
    var changed = false;
    for (graph.bindings.items) |*binding| {
        if (!std.mem.eql(u8, graph.text(binding.name), "fixed")) continue;
        binding.mutability = .constant;
        changed = true;
    }
    try std.testing.expect(changed);
    const source = @import("../4_semantics/primitives/schema.zig").SourceRef{ .file_index = 0, .offset = 0 };
    const result = try evaluate(a, graph, &diagnostics, good.?, &.{}, source, .{});
    try std.testing.expectEqual(@as(i128, 42), graph.node(result[0]).content.int_literal);
    try std.testing.expect(!diagnostics.hasErrors());
    const unit_mod = @import("../4_semantics/global/reachability.zig");
    var unit = try unit_mod.dependencyUnit(a, graph, &.{wrapper.?});
    defer unit.deinit();
    try std.testing.expect(unit.contains(bad.?));
    try std.testing.expect(!unit.contains(good.?));
    try std.testing.expectError(error.Reported, evaluate(a, graph, &diagnostics, wrapper.?, &.{}, source, .{}));
    try std.testing.expect(diagnostics.hasErrors());
}

test "compile-time evaluation retains selected cleanup in its dependency unit" {
    const evaluate = @import("evaluate.zig").evaluate;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const files = [_]sf.SourceFile{
        .{ .path = "app/main.rg", .code =
        \\Counter: Type = (.count: Int32)
        \\Resource: Type = (.counter: $&Counter)
        \\implement Deinit#(Resource) (
        \\    .deinit = (.self: $&Resource) -> () {
        \\        self&.counter&.count = self&.counter&.count + 1
        \\    }
        \\)
        \\calculate() -> (.result: Int32 = 0) := {
        \\    counter :: Counter = (.count = 41)
        \\    { owner :: Resource = (.counter = $&counter) }
        \\    result = counter.count
        \\}
        \\main() -> (.status_code: Int32 = calculate()) := {}
        },
        .{ .path = "arithmetic_core/scalar_arithmetic.rg", .origin = .bundled_core, .code = @import("../test_support.zig").arithmetic_core_source },
        .{ .path = "arithmetic_core/deinit.rg", .origin = .bundled_core, .code =
        \\Deinit#(.T: Type): Contract = (.deinit: (.self: $&T) -> ())
        },
    };
    var diagnostics = diag.Diagnostics.init(&a, &files);
    defer diagnostics.deinit();
    var pipeline = frontend.FrontendPipeline.init(a, std.testing.io, &diagnostics, .{});
    defer pipeline.deinit();
    const graph = @constCast(try pipeline.semantizeGlobalFiles(&files));
    const source = @import("../4_semantics/primitives/schema.zig").SourceRef{ .file_index = 0, .offset = 0 };
    var found = false;
    for (graph.functions.items, 0..) |function, raw| {
        if (!std.mem.eql(u8, graph.text(graph.declarationSourceName(function.declaration)), "calculate")) continue;
        found = true;
        const id: @import("../4_semantics/global/graph.zig").GlobalFunctionId = @enumFromInt(raw);
        var unit = try @import("../4_semantics/global/reachability.zig").dependencyUnit(a, graph, &.{id});
        defer unit.deinit();
        try std.testing.expect(unit.cleanup_functions.count() != 0);
        const result = try evaluate(a, graph, &diagnostics, id, &.{}, source, .{});
        try std.testing.expectEqual(@as(i128, 42), graph.node(result[0]).content.int_literal);
        // Checking again must remain valid after the evaluator storage ended.
        const again = try evaluate(a, graph, &diagnostics, id, &.{}, source, .{});
        try std.testing.expectEqual(@as(i128, 42), graph.node(again[0]).content.int_literal);
    }
    try std.testing.expect(found);
}

test "bytecode source run freezes loop results before runtime execution" {
    try std.testing.expectEqual(@as(i128, 42), try execute(
        \\calculate(.base: Int32) -> (.result: Int32 = 0) := {
        \\    result = base
        \\    while result < 42 { result = result + 1 }
        \\}
        \\main() -> (.status_code: Int32 = 0) := {
        \\    answer ::= #run () -> (.answer: Int32) { answer = calculate(.base = 40) }
        \\    status_code = answer
        \\}
    , .{ .instructions = 20 }));
}

test "bytecode source run evaluates nested requests in specialized bodies" {
    try std.testing.expectEqual(@as(i128, 42), try execute(
        \\calculate(.base: Int32) -> (.result: Int32 = 0) := {
        \\    result = base
        \\    while result < 42 { result = result + 1 }
        \\}
        \\prepared#(.N: Int32)() -> (.result: Int32 = 0) := {
        \\    result = #run () -> (.answer: Int32) { answer = calculate(.base = N) }
        \\}
        \\main() -> (.status_code: Int32 = 0) := {
        \\    status_code = #run () -> (.answer: Int32) { answer = prepared#(.N = 40)() }
        \\}
    , .{ .instructions = 20 }));
}

test "bytecode source run preserves several outputs and void boundaries" {
    try std.testing.expectEqual(@as(i128, 42), try execute(
        \\pair() -> (.left: Int32 = 20, .right: Int32 = 22) := {}
        \\check(.value: Int32) -> () := { if value != 42 { abort } }
        \\main() -> (.status_code: Int32 = 0) := {
        \\    values ::= #run () -> (.left: Int32, .right: Int32) {
        \\        pair_value ::= pair()
        \\        left = pair_value.left
        \\        right = pair_value.right
        \\    }
        \\    #run { check(.value = 42) }
        \\    status_code = values.left + values.right
        \\}
    , .{}));
    try std.testing.expectEqual(@as(i128, 42), try execute(
        \\answer(.value: Void) -> (.result: Int32 = 42) := {}
        \\main() -> (.status_code: Int32 = 0) := {
        \\    status_code = #run () -> (.computed: Int32) { computed = answer(.value = ()) }
        \\}
    , .{}));
}

test "bytecode anonymous compile-time entry executes an ordinary function body" {
    try std.testing.expectEqual(@as(i128, 42), try execute(
        \\calculate(.value: Int32) -> (.result: Int32) := { result = value + 1 }
        \\main() -> (.status_code: Int32) := {
        \\    answer ::= #run () -> (.result: Int32) {
        \\        local :: Int32 = 41
        \\        result = calculate(.value = local)
        \\    }
        \\    status_code = answer
        \\}
    , .{}));
}

test "bytecode nested anonymous entries retain their invocation environment" {
    try std.testing.expectEqual(@as(i128, 42), try execute(
        \\compute() -> (.value: Int32 = 40) := {}
        \\
        \\main() -> (.status_code: Int32) := {
        \\    known := compute()
        \\    captured := #run () -> (.answer: Int32) {
        \\        first := #run () -> (.answer: Int32) { answer = known + 1 }
        \\        second := #run () -> (.answer: Int32) { answer = first + 1 }
        \\        #if true { answer = second } #else { answer = missing() }
        \\    }
        \\    repeated := #run () -> (.answer: Int32) {
        \\        index :: Int32 = 0
        \\        total :: Int32 = 0
        \\        while index < 2 {
        \\            total = total + [#run () -> (.value: Int32) { value = index + 20 }]
        \\            index = index + 1
        \\        }
        \\        answer = total + 1
        \\    }
        \\    if captured != 42 or repeated != 42 { abort }
        \\    status_code = captured
        \\}
    , .{}));
}

test "bytecode generic anonymous entries transport retained lexical capture types" {
    try std.testing.expectEqual(@as(i128, 42), try execute(
        \\calculate#(.n: Int32)() -> (.result: Int32) := {
        \\    local := n
        \\    offset := 0
        \\    result = #run () -> (.value: Int32) {
        \\        value = #run () -> (.inner: Int32) { inner = local + offset }
        \\    }
        \\}
        \\main() -> (.status_code: Int32) := {
        \\    if calculate#(.n = 41)() != 41 { abort }
        \\    status_code = calculate#(.n = 42)()
        \\}
    , .{}));
}

test "concrete staged entries select captures across nested entry boundaries" {
    try std.testing.expectEqual(@as(i128, 42), try execute(
        \\compute() -> (.value: Int32 = 42) := {}
        \\
        \\main() -> (.status_code: Int32) := {
        \\    runtime :: Int32 = 7
        \\    known := compute()
        \\    first := #run () -> (.answer: Int32) {
        \\        #if true { answer = known } #else { answer = runtime }
        \\    }
        \\    second := #run () -> (.answer: Int32) {
        \\        #if known == 42 { answer = known } #else { answer = missing_value }
        \\    }
        \\    nested := #run () -> (.answer: Int32) {
        \\        answer = #run () -> (.value: Int32) {
        \\            #if true { value = known } #else { value = runtime }
        \\        }
        \\    }
        \\    if first != 42 or second != 42 or nested != 42 { abort }
        \\    status_code = first
        \\}
    , .{}));
}

test "generic compile-time entries ignore runtime captures in discarded branches" {
    try std.testing.expectEqual(@as(i128, 42), try execute(
        \\choose#(.n: Int32)(.runtime_value: Int32) -> (.result: Int32) := {
        \\    result = #run () -> (.value: Int32) {
        \\        #if n == 42 { value = n } #else { value = runtime_value }
        \\    }
        \\}
        \\main() -> (.status_code: Int32) := {
        \\    status_code = choose#(.n = 42)(.runtime_value = 7)
        \\}
    , .{}));
}

test "staged compile-time captures resolve types from instantiated outer bindings" {
    try std.testing.expectEqual(@as(i128, 42), try execute(
        \\identity(.value: Int32) -> (.result: Int32 = value) := {}
        \\compute#(.n: Int32)() -> (.result: Int32) := {
        \\    pending := identity(.value = n)
        \\    result = #run () -> (.value: Int32) { value = pending }
        \\}
        \\main() -> (.status_code: Int32) := {
        \\    if compute#(.n = 41)() != 41 { abort }
        \\    status_code = compute#(.n = 42)()
        \\}
    , .{}));
}

test "bytecode anonymous entries complete inferred capture types" {
    try std.testing.expectEqual(@as(i128, 42), try execute(
        \\compute() -> (.value: Int32 = 41) := {}
        \\main() -> (.status_code: Int32) := {
        \\    known := compute()
        \\    status_code = #run () -> (.answer: Int32) { answer = known + 1 }
        \\}
    , .{}));
}

test "bytecode anonymous entries capture only used constant values" {
    try std.testing.expectEqual(@as(i128, 42), try execute(
        \\main() -> (.status_code: Int32) := {
        \\    known: Int32 = 40
        \\    runtime :: Int32 = 99
        \\    status_code = #run () -> (.answer: Int32) {
        \\        answer = known + known - 38
        \\    }
        \\}
    , .{ .instructions = 1000 }));
}

test "bytecode anonymous compile-time entries retain defaults and independent scopes" {
    try std.testing.expectEqual(@as(i128, 42), try execute(
        \\main() -> (.status_code: Int32) := {
        \\    first ::= #run () -> (.result: Int32 = 20) {}
        \\    second ::= #run () -> (.result: Int32) {
        \\        local ::= #run () -> (.result: Int32 = 21) {}
        \\        result = local + 1
        \\    }
        \\    status_code = first + second
        \\}
    , .{}));
}

test "bytecode anonymous compile-time blocks support local storage and no outputs" {
    try std.testing.expectEqual(@as(i128, 42), try execute(
        \\main() -> (.status_code: Int32) := {
        \\    #run {
        \\        local :: Int32 = 41
        \\        pointer ::= $&local
        \\        pointer&= pointer& + 1
        \\        if local != 42 { abort }
        \\    }
        \\    status_code = #run () -> (.result: Int32) {
        \\        local :: Int32 = 42
        \\        pointer ::= &local
        \\        result = pointer&
        \\    }
        \\}
    , .{}));
}

test "bytecode generic anonymous entries capture compile-time parameters" {
    try std.testing.expectEqual(@as(i128, 42), try execute(
        \\calculate#(.T: Type, .n: Int32) := () -> (.result: T) {
        \\    result = #run () -> (.value: T) {
        \\        value = n
        \\    }
        \\}
        \\main() -> (.status_code: Int32) := {
        \\    narrow ::= calculate#(.T: Int8, .n = 41)()
        \\    if calculate#(.T: Int32, .n = 41)() != 41 { abort }
        \\    status_code = calculate#(.T: Int32, .n = 42)()
        \\}
    , .{}));
}

test "bytecode anonymous entries supply computed specialization arguments" {
    try std.testing.expectEqual(@as(i128, 42), try execute(
        \\identity#(.n: Int32) := () -> (.result: Int32) { result = n }
        \\forward#(.n: Int32) := () -> (.result: Int32) {
        \\    result = identity#(.n = #run () -> (.value: Int32) { value = n })()
        \\}
        \\main() -> (.status_code: Int32) := {
        \\    if forward#(.n = 41)() != 41 { abort }
        \\    if forward#(.n = 42)() != 42 { abort }
        \\    status_code = identity#(.n = #run () -> (.value: Int32) { value = 42 })()
        \\}
    , .{}));
}

test "bytecode anonymous entry results determine array dimensions" {
    try std.testing.expectEqual(@as(i128, 42), try execute(
        \\Items#(.n: Int32): Type = (.items: Array#(.n = n, .t: Int32))
        \\read#(.n: Int32) := () -> (.result: Int32) {
        \\    values: Items#(.n = #run () -> (.count: Int32) { count = n }) = (.items = (20, 22))
        \\    result = values.items[0] + values.items[1]
        \\}
        \\main() -> (.status_code: Int32) := { status_code = read#(.n = 2)() }
    , .{}));
}

test "bytecode generic anonymous entries retain nested parameter-dependent selection" {
    try std.testing.expectEqual(@as(i128, 42), try execute(
        \\calculate#(.n: Int32) := () -> (.result: Int32) {
        \\    result = #run () -> (.value: Int32) {
        \\        #if n == 42 {
        \\            value = #run () -> (.inner: Int32) { inner = n }
        \\        } #else { value = 41 }
        \\    }
        \\}
        \\main() -> (.status_code: Int32) := {
        \\    if calculate#(.n = 41)() != 41 { abort }
        \\    status_code = calculate#(.n = 42)()
        \\}
    , .{}));
}

test "bytecode anonymous compile-time entries consume known module values" {
    try std.testing.expectEqual(@as(i128, 42), try execute(
        \\base := 41
        \\main() -> (.status_code: Int32) := {
        \\    status_code = #run () -> (.result: Int32) { result = base + 1 }
        \\}
    , .{}));
}

test "anonymous compile-time entries reject runtime storage only on executed paths" {
    try std.testing.expectEqual(@as(i128, 42), try execute(
        \\runtime :: Int32 = 99
        \\choose(.access: Bool) -> (.value: Int32) := {
        \\    if access { value = runtime } else { value = 42 }
        \\}
        \\main() -> (.status_code: Int32) := {
        \\    status_code = #run () -> (.answer: Int32) {
        \\        answer = choose(.access = false)
        \\    }
        \\}
    , .{}));
}

test "anonymous compile-time entries cannot observe mutable runtime globals" {
    const bodies = [_][]const u8{
        "result = runtime_value",
        "result = read_runtime()",
        "result = alias",
        "runtime_value = 1\nresult = 42",
        "reference ::= &runtime_value\nresult = 42",
    };
    for (bodies) |body| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const source = try std.fmt.allocPrint(a, "runtime_value :: Int32 = 42\n" ++
            "alias := runtime_value\n" ++
            "read_runtime() -> (.result: Int32) := {{ result = runtime_value }}\n" ++
            "main() -> (.status_code: Int32) := {{ status_code = #run () -> (.result: Int32) {{ {s} }} }}", .{body});
        const files = [_]sf.SourceFile{.{ .path = "app/main.rg", .code = source }};
        var diagnostics = diag.Diagnostics.init(&a, &files);
        defer diagnostics.deinit();
        var pipeline = frontend.FrontendPipeline.init(a, std.testing.io, &diagnostics, .{});
        defer pipeline.deinit();
        try std.testing.expectError(error.Reported, pipeline.semantizeGlobalFiles(&files));
        var found = false;
        for (diagnostics.list.items) |diagnostic| if (std.mem.indexOf(u8, diagnostic.msg, "cannot access mutable runtime global storage") != null) {
            found = true;
        };
        try std.testing.expect(found);
    }
}

test "bytecode anonymous compile-time entries initialize module constants" {
    try std.testing.expectEqual(@as(i128, 42), try execute(
        \\answer ::= #run () -> (.result: Int32) {
        \\    local :: Int32 = 41
        \\    result = local + 1
        \\}
        \\Record: Type = (.value: Int32 = #run () -> (.result: Int32 = 42) {})
        \\main() -> (.status_code: Int32) := {
        \\    record ::= Record()
        \\    if record.value != answer { abort }
        \\    status_code = answer
        \\}
    , .{}));
}

test "bytecode anonymous compile-time entries select only their active branch" {
    try std.testing.expectEqual(@as(i128, 42), try execute(
        \\enabled() -> (.result: Bool) := { result = true }
        \\main() -> (.status_code: Int32) := {
        \\    status_code = #run () -> (.result: Int32) {
        \\        #if enabled() {
        \\            result = #run () -> (.value: Int32 = 42) {}
        \\        } #else { result = missing() }
        \\    }
        \\}
    , .{}));
}

test "bytecode anonymous compile-time entries preserve named multiple outputs" {
    try std.testing.expectEqual(@as(i128, 42), try execute(
        \\main() -> (.status_code: Int32) := {
        \\    pair ::= #run () -> (.left: Int32, .right: Int32) {
        \\        left = 20
        \\        right = 22
        \\    }
        \\    status_code = pair.left + pair.right
        \\}
    , .{}));
}

test "anonymous compile-time entries diagnose unsupported argument interfaces" {
    for ([_][]const u8{ ".value: Int32", ".system: Int32, .extra: Int32" }) |inputs| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const source = try std.fmt.allocPrint(a, "main() -> () := {{ #run ({s}) -> () {{}} }}", .{inputs});
        const files = [_]sf.SourceFile{.{ .path = "app/main.rg", .code = source }};
        var diagnostics = diag.Diagnostics.init(&a, &files);
        defer diagnostics.deinit();
        var pipeline = frontend.FrontendPipeline.init(a, std.testing.io, &diagnostics, .{});
        defer pipeline.deinit();
        try std.testing.expectError(error.Reported, pipeline.semantizeGlobalFiles(&files));
        var found = false;
        for (diagnostics.list.items) |diagnostic| if (std.mem.indexOf(u8, diagnostic.msg, "accept no inputs or one '.system: System' input") != null) {
            found = true;
        };
        try std.testing.expect(found);
    }
}

test "nested compile-time entries retain their output representation boundary" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const files = [_]sf.SourceFile{.{ .path = "app/main.rg", .code =
        \\main() -> (.status_code: Int32) := {
        \\    status_code = #run () -> (.answer: Int32) {
        \\        local :: Int32 = 42
        \\        pointer ::= &local
        \\        borrowed := #run () -> (.value: &Int32) { value = pointer }
        \\        answer = borrowed&
        \\    }
        \\}
    }};
    var diagnostics = diag.Diagnostics.init(&a, &files);
    defer diagnostics.deinit();
    var pipeline = frontend.FrontendPipeline.init(a, std.testing.io, &diagnostics, .{});
    defer pipeline.deinit();
    try std.testing.expectError(error.Reported, pipeline.semantizeGlobalFiles(&files));
    var found = false;
    for (diagnostics.list.items) |message|
        if (std.mem.indexOf(u8, message.msg, "cannot return references or values requiring cleanup") != null) {
            found = true;
        };
    try std.testing.expect(found);
}

test "anonymous compile-time entries cannot export temporary references" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const files = [_]sf.SourceFile{.{ .path = "app/main.rg", .code =
        \\main() -> () := {
        \\    pointer ::= #run () -> (.result: &Int32) {
        \\        local :: Int32 = 42
        \\        result = &local
        \\    }
        \\}
    }};
    var diagnostics = diag.Diagnostics.init(&a, &files);
    defer diagnostics.deinit();
    var pipeline = frontend.FrontendPipeline.init(a, std.testing.io, &diagnostics, .{});
    defer pipeline.deinit();
    try std.testing.expectError(error.Reported, pipeline.semantizeGlobalFiles(&files));
    try std.testing.expect(diagnostics.hasErrors());
}

test "bytecode source run evaluates closed argument calls through selected operations" {
    try std.testing.expectEqual(@as(i128, 42), try execute(
        \\identity(.value: Int32) -> (.result: Int32) := { result = value }
        \\increment(.value: Int32) -> (.result: Int32) := { result = value + 1 }
        \\main() -> (.status_code: Int32 = 0) := {
        \\    status_code = #run () -> (.answer: Int32) { answer = identity(.value = increment(.value = 20 + 21)) }
        \\}
    , .{ .instructions = 20 }));
}

test "bytecode expression entries share validation and retained execution" {
    const g = @import("../4_semantics/global/graph.zig");
    const a = std.testing.allocator;
    var graph: g.GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    try graph.types.appendSlice(a, &.{ .{ .builtin = .Int32 }, .{ .builtin = .Bool } });
    const source = @import("../4_semantics/primitives/schema.zig").SourceRef{ .file_index = 0, .offset = 0 };
    var code = [_]b.Instruction{
        .{ .source = source, .op = .{ .binary = .{ .dst = 2, .left = 0, .right = 1, .operator = .addition, .kind = .i32 } } },
        .{ .source = source, .op = .{ .ret = &.{2} } },
    };
    const program: b.Program = .{ .graph = &graph, .functions = &.{}, .expression = &.{
        .slots = &.{ @enumFromInt(0), @enumFromInt(0), @enumFromInt(0) },
        .inputs = &.{ 0, 1 },
        .outputs = &.{2},
        .code = &code,
    } };
    {
        var executor = try vm.Vm.init(a, program, .{});
        defer executor.deinit();
        const args = [_]b.Value{ .{ .integer = 20 }, .{ .integer = 22 } };
        try std.testing.expectEqual(@as(i128, 42), (try executor.invokeExpression(&args))[0].integer);
        const context = executor.context().storage.context;
        const cells = executor.context().storage.cells;
        try std.testing.expectError(error.InvalidArguments, executor.invokeExpression(&.{ .{ .boolean = true }, .{ .integer = 22 } }));
        try std.testing.expectEqual(cells, executor.context().storage.cells);
        try std.testing.expectError(error.InvalidEntry, executor.invoke(@enumFromInt(0), &args));
        try std.testing.expectEqual(@as(i128, 42), (try executor.invokeExpression(&args))[0].integer);
        try std.testing.expectEqual(context, executor.context().storage.context);
        try std.testing.expectEqual(@as(i128, 42), (try executor.runExpression(&args))[0].integer);
        try std.testing.expect(context != executor.context().storage.context);
    }
    code[0].op.binary.left = 99;
    try std.testing.expectError(error.InvalidBytecode, vm.Vm.init(a, program, .{}));
}

test "bytecode source run leaves implicit argument calls in runtime bindings" {
    try std.testing.expectError(error.ExecutionInstructionLimit, execute(
        \\compute() -> (.result: Int32 = 0) := {
        \\    while result < 1000 { result = result + 1 }
        \\}
        \\identity(.value: Int32) -> (.result: Int32) := { result = value }
        \\main() -> (.status_code: Int32 = 0) := {
        \\    computed: Int32 = compute()
        \\    status_code = #run () -> (.answer: Int32) { answer = identity(.value = computed) }
        \\}
    , .{ .instructions = 50 }));
}

test "bytecode source run admits a single argument computation below its budget" {
    try std.testing.expectEqual(@as(i128, 42), try execute(
        \\compute(.count: Int32) -> (.result: Int32 = 0) := {
        \\    while result < count { result = result + 1 }
        \\}
        \\main() -> (.status_code: Int32 = 0) := {
        \\    value ::= #run () -> (.answer: Int32) { answer = compute(.count = 100000) }
        \\    if value != 100000 { abort }
        \\    status_code = 42
        \\}
    , .{ .instructions = 50 }));
}

test "bytecode source run evaluates concrete output defaults in function scope" {
    try std.testing.expectEqual(@as(i128, 42), try execute(
        \\increment(.value: Int32) -> (.result: Int32 = value + 1) := {}
        \\compute(.value: Int32) -> (.first: Int32 = value | increment(_), .second: Int32 = first + 1) := {}
        \\main() -> (.status_code: Int32 = 0) := {
        \\    values := #run () -> (.first: Int32, .second: Int32) {
        \\        pair_value ::= compute(.value = 40)
        \\        first = pair_value.first
        \\        second = pair_value.second
        \\    }
        \\    status_code = values.second
        \\}
    , .{ .instructions = 50 }));
}

test "bytecode source run projects aggregate argument expressions" {
    try std.testing.expectEqual(@as(i128, 42), try execute(
        \\values() -> (.data: (.items: [2]Int32)) := {
        \\    data = (.items = (20, 42))
        \\}
        \\identity(.value: Int32) -> (.result: Int32 = value) := {}
        \\main() -> (.status_code: Int32 = 0) := {
        \\    status_code = #run () -> (.answer: Int32) { answer = identity(.value = values().items[1]) }
        \\}
    , .{ .instructions = 50 }));
}

test "bytecode source run determines specialization arguments" {
    try std.testing.expectEqual(@as(i128, 42), try execute(
        \\compute() -> (.result: Int32 = 0) := {
        \\    while result < 6 { result = result + 1 }
        \\}
        \\scale#(.n: Int32)(.value: Int32) -> (.result: Int32 = value * n) := {}
        \\main() -> (.status_code: Int32 = 0) := {
        \\    status_code = scale#(.n = #run () -> (.answer: Int32) { answer = compute() })(.value = 7)
        \\}
    , .{ .instructions = 50 }));
}

test "bytecode source run determines type arguments" {
    try std.testing.expectEqual(@as(i128, 42), try execute(
        \\compute() -> (.result: Int32 = 2) := {}
        \\Holder#(.n: Int32): Type = (.items: Array#(.n = n, .t: Int32))
        \\main() -> (.status_code: Int32 = 0) := {
        \\    data :: Holder#(.n = #run () -> (.answer: Int32) { answer = compute() }) = (.items = (20, 42))
        \\    status_code = data.items[1]
        \\}
    , .{ .instructions = 50 }));
}

test "bytecode source run keys generic requests by bound arguments" {
    try std.testing.expectEqual(@as(i128, 42), try execute(
        \\increment(.value: Int32) -> (.result: Int32 = value + 1) := {}
        \\result#(.n: Int32)() -> (.value: Int32 = n) := {}
        \\compute#(.n: Int32)() -> (.value: Int32) := {
        \\    value = result#(.n = #run () -> (.answer: Int32) { answer = increment(.value = n) })()
        \\}
        \\main() -> (.status_code: Int32 = 0) := {
        \\    if compute#(.n = 3)() != 4 { abort }
        \\    status_code = compute#(.n = 41)()
        \\}
    , .{ .instructions = 80 }));
}

test "bytecode staged dependencies survive default argument suspension" {
    try std.testing.expectEqual(@as(i128, 42), try execute(
        \\compute() -> (.value: Int32 = 42) := {}
        \\result#(.n: Int32)() -> (.value: Int32 = n) := {}
        \\defaulted#(.T: Type)(.ignored: T, .value: Int32 = result#(.n = #run () -> (.value: Int32) { value = compute() })(), .tail: Int32 = 0) -> (.output: Int32 = [value + tail]) := {}
        \\main() -> (.status_code: Int32 = 0) := {
        \\    status_code = defaulted(.ignored = 0)
        \\}
    , .{ .instructions = 50 }));
}

test "bytecode program instances share context identity storage and trap state" {
    const g = @import("../4_semantics/global/graph.zig");
    const a = std.testing.allocator;
    var graph: g.GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    try graph.types.append(a, .{ .builtin = .Int32 });
    try graph.types.append(a, .{ .array = .{ .length = 1, .element = @enumFromInt(0) } });
    const source = @import("../4_semantics/primitives/schema.zig").SourceRef{ .file_index = 0, .offset = 0 };
    try graph.fields.append(a, .{ .name = .{ .start = 0, .len = 0 }, .ty = @enumFromInt(1), .source = source });
    try graph.functions.append(a, .{ .declaration = @enumFromInt(0), .input = .{ .start = 0, .len = 1 }, .output = .{ .start = 0, .len = 1 } });
    const code = [_]b.Instruction{.{ .source = source, .op = .{ .ret = &.{0} } }};
    const functions = [_]?b.Function{.{ .slots = &.{@enumFromInt(1)}, .inputs = &.{0}, .outputs = &.{0}, .code = &code }};
    const program = b.Program{ .graph = &graph, .functions = &functions };
    var context = vm.Context.init(a, 1000);
    defer context.deinit();
    const persistent = try context.sessionSlots(1, &.{});
    try context.storage.initializeSession(persistent, 0, .{ .integer = 99 });
    const limits = vm.Limits{ .value_cells = 1000 };
    var first = try vm.Vm.initShared(a, program, limits, &context);
    var first_live = true;
    defer if (first_live) first.deinit();
    var second = try vm.Vm.initShared(a, program, limits, &context);
    defer second.deinit();
    var result = try first.invoke(@enumFromInt(0), &.{.{ .array = &.{.{ .integer = 42 }} }});
    const identity = context.storage.context;
    const cells = context.storage.cells;
    first.deinit();
    first_live = false;
    result = try second.invoke(@enumFromInt(0), result);
    try std.testing.expectEqual(@as(i128, 42), result[0].array[0].integer);
    try std.testing.expectEqual(identity, context.storage.context);
    try std.testing.expect(context.storage.cells > cells);
    try std.testing.expectEqual(@as(i128, 99), (try persistent.get(0)).integer);
    try std.testing.expectError(error.SharedExecutionContext, second.run(@enumFromInt(0), result));
    try std.testing.expectEqual(identity, context.storage.context);
    context.running = true;
    try std.testing.expectError(error.ExecutionContextBusy, second.invoke(@enumFromInt(0), result));
    context.running = false;
    try std.testing.expectEqual(.ready, context.state);
    var trapping = try vm.Vm.initShared(a, program, .{ .value_cells = 1000, .instructions = 0 }, &context);
    defer trapping.deinit();
    try std.testing.expectError(error.ExecutionInstructionLimit, trapping.invoke(@enumFromInt(0), result));
    try std.testing.expectError(error.ExecutionContextPoisoned, second.invoke(@enumFromInt(0), result));
    context.reset();
    result = try second.invoke(@enumFromInt(0), &.{.{ .array = &.{.{ .integer = 7 }} }});
    try std.testing.expectEqual(@as(i128, 7), result[0].array[0].integer);
    try std.testing.expect(identity != context.storage.context);
    try std.testing.expectError(error.ExecutionForeignReference, persistent.get(0));
    try std.testing.expectError(error.ExecutionContextLimitMismatch, vm.Vm.initShared(a, program, .{}, &context));
}

test "bytecode session storage retains data and forbids call-frame publication" {
    const a = std.testing.allocator;
    var context = vm.Context.init(a, 1000);
    defer context.deinit();
    var cleanup = [_]b.Cleanup{.{ .root = 0, .path = &.{}, .flag = 1 }};
    const session = try context.sessionSlots(3, &cleanup);
    // Layout ownership belongs to the execution context, not this input array.
    cleanup[0].flag = 99;
    var original = [_]b.Value{.{ .integer = 42 }};
    try context.storage.initializeSession(session, 0, .{ .array = &original });
    original[0] = .{ .integer = 7 };
    const reference = @import("../5_codegen/bytecode/value.zig").Reference{
        .context = context.storage.context,
        .frame = session.frame,
        .root = 0,
        .path = &.{},
        .mutability = .read_write,
    };
    try std.testing.expectError(error.ExecutionInitializedStorage, context.storage.initializeSession(session, 0, .{ .integer = 7 }));
    try std.testing.expectError(error.ExecutionInvalidReference, context.storage.initializeSession(session, 1, .{ .boolean = false }));
    const temporary = try context.storage.enter(1);
    const locals = try context.storage.slots(temporary);
    try locals.put(0, .{ .integer = 9 });
    var local_ref = reference;
    local_ref.frame = temporary;
    try std.testing.expectError(error.ExecutionTemporaryReference, context.storage.initializeSession(session, 2, .{ .record = &.{.{ .reference = local_ref }} }));
    try std.testing.expectError(error.ExecutionUninitializedStorage, session.get(2));
    context.storage.leave(temporary);
    try std.testing.expectEqual(@as(i128, 42), (try session.get(0)).array[0].integer);
    var path = [_]@import("../5_codegen/bytecode/value.zig").Projection{.{ .element = 0 }};
    var projected = reference;
    projected.path = &path;
    try context.storage.initializeSession(session, 2, .{ .reference = projected });
    path[0] = .{ .element = 99 };
    try std.testing.expectEqual(@as(i128, 42), (try context.storage.read((try session.get(2)).reference)).integer);
    try context.storage.validateLive(&.{try session.get(2)});
    _ = try context.storage.cleanupSet(reference, true);
    try std.testing.expectError(error.ExecutionActiveCleanup, context.storage.releaseSession(session));
    _ = try context.storage.cleanupSet(reference, false);
    try context.storage.releaseSession(session);
    try std.testing.expectError(error.ExecutionDeadReference, context.storage.read(reference));
    const old_context = context.storage.context;
    context.reset();
    _ = try context.sessionSlots(1, &.{});
    try std.testing.expect(old_context != context.storage.context);
    try std.testing.expectError(error.ExecutionForeignReference, session.get(0));
}

test "bytecode failed session initialization leaves storage vacant" {
    var context = vm.Context.init(std.testing.allocator, 20);
    defer context.deinit();
    const session = try context.sessionSlots(1, &.{});
    const too_large = [_]b.Value{.{ .integer = 0 }} ** 32;
    try std.testing.expectError(error.ExecutionMemoryLimit, context.storage.initializeSession(session, 0, .{ .array = &too_large }));
    try std.testing.expectError(error.ExecutionUninitializedStorage, session.get(0));
    try context.storage.initializeSession(session, 0, .{ .integer = 42 });
    try std.testing.expectEqual(@as(i128, 42), (try session.get(0)).integer);
}

test "bytecode typed session bindings persist across verified program revisions" {
    const g = @import("../4_semantics/global/graph.zig");
    const a = std.testing.allocator;
    var graph: g.GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    try graph.types.appendSlice(a, &.{ .{ .builtin = .Int32 }, .{ .pointer = .{ .child = @enumFromInt(0), .mutability = .read_write } }, .{ .pointer = .{ .child = @enumFromInt(1), .mutability = .read_write } } });
    const source = @import("../4_semantics/primitives/schema.zig").SourceRef{ .file_index = 0, .offset = 0 };
    try graph.bindings.append(a, .{ .name = .{ .start = 0, .len = 0 }, .ty = @enumFromInt(0), .source = source, .mutability = .constant });
    try graph.bindings.append(a, .{ .name = .{ .start = 0, .len = 0 }, .ty = @enumFromInt(1), .source = source, .mutability = .constant });
    try graph.fields.append(a, .{ .name = .{ .start = 0, .len = 0 }, .ty = @enumFromInt(0), .source = source });
    for (0..2) |_| try graph.functions.append(a, .{ .declaration = @enumFromInt(0), .input = .{ .start = 0, .len = 0 }, .output = .{ .start = 0, .len = 1 } });
    const slots = [_]b.Type{ @enumFromInt(0), @enumFromInt(1), @enumFromInt(2) };
    const bindings = [_]b.SessionBinding{ .{ .binding = @enumFromInt(0), .slots = slots[0..1] }, .{ .binding = @enumFromInt(1), .slots = slots[1..2] } };
    const interface = b.Session{ .namespace = @enumFromInt(1), .bindings = &bindings };
    const initialize = [_]b.Instruction{
        .{ .source = source, .op = .{ .constant = .{ .dst = 0, .value = .{ .integer = 42 } } } },
        .{ .source = source, .op = .{ .session_initialize = .{ .binding = 0, .value = 0 } } },
        .{ .source = source, .op = .{ .borrow_storage = .{ .dst = 1, .permission = .read_write, .place = .{ .region = .session, .root = 0, .path = &.{} } } } },
        .{ .source = source, .op = .{ .session_initialize = .{ .binding = 1, .value = 1 } } },
        .{ .source = source, .op = .{ .ret = &.{0} } },
    };
    const read = [_]b.Instruction{
        .{ .source = source, .op = .{ .borrow_storage = .{ .dst = 1, .permission = .read_write, .place = .{ .region = .session, .root = 0, .path = &.{} } } } },
        .{ .source = source, .op = .{ .load = .{ .dst = 0, .place = .{ .root = 1, .path = &.{.dereference} } } } },
        .{ .source = source, .op = .{ .ret = &.{0} } },
    };
    const read_reference = [_]b.Instruction{
        .{ .source = source, .op = .{ .borrow_storage = .{ .dst = 2, .permission = .read_write, .place = .{ .region = .session, .root = 1, .path = &.{} } } } },
        .{ .source = source, .op = .{ .load = .{ .dst = 1, .place = .{ .root = 2, .path = &.{.dereference} } } } },
        .{ .source = source, .op = .{ .load = .{ .dst = 0, .place = .{ .root = 1, .path = &.{.dereference} } } } },
        .{ .source = source, .op = .{ .ret = &.{0} } },
    };
    const write = [_]b.Instruction{
        .{ .source = source, .op = .{ .borrow_storage = .{ .dst = 1, .permission = .read_write, .place = .{ .region = .session, .root = 0, .path = &.{} } } } },
        .{ .source = source, .op = .{ .capture_write = .{ .dst = 0, .place = .{ .root = 0, .region = .session, .path = &.{} } } } },
        .{ .source = source, .op = .{ .constant = .{ .dst = 0, .value = .{ .integer = 7 } } } },
        .{ .source = source, .op = .{ .check_write_cleanup = 0 } },
        .{ .source = source, .op = .{ .store = .{ .destination = 0, .value = 0 } } },
        .{ .source = source, .op = .{ .activate_write_cleanup = 0 } },
        .{ .source = source, .op = .{ .ret = &.{0} } },
    };
    const first_functions = [_]?b.Function{ .{ .slots = &slots, .inputs = &.{}, .outputs = &.{0}, .code = &initialize }, null };
    const read_functions = [_]?b.Function{ null, .{ .slots = &slots, .inputs = &.{}, .outputs = &.{0}, .code = &read } };
    const reference_functions = [_]?b.Function{ null, .{ .slots = &slots, .inputs = &.{}, .outputs = &.{0}, .code = &read_reference } };
    const write_functions = [_]?b.Function{ null, .{ .slots = &slots, .inputs = &.{}, .outputs = &.{0}, .code = &write, .write_destinations = slots[0..1] } };
    var context = vm.Context.init(a, 1000);
    defer context.deinit();
    const limits = vm.Limits{ .value_cells = 1000 };
    var first = try vm.Vm.initShared(a, .{ .graph = &graph, .functions = &first_functions, .session = interface }, limits, &context);
    defer first.deinit();
    var reader = try vm.Vm.initShared(a, .{ .graph = &graph, .functions = &read_functions, .session = interface }, limits, &context);
    defer reader.deinit();
    var writer = try vm.Vm.initShared(a, .{ .graph = &graph, .functions = &write_functions, .session = interface }, limits, &context);
    defer writer.deinit();
    var reference_reader = try vm.Vm.initShared(a, .{ .graph = &graph, .functions = &reference_functions, .session = interface }, limits, &context);
    defer reference_reader.deinit();
    _ = try first.invoke(@enumFromInt(0), &.{});
    try std.testing.expectEqual(@as(i128, 42), (try reference_reader.invoke(@enumFromInt(1), &.{}))[0].integer);
    try std.testing.expectEqual(@as(i128, 42), (try reader.invoke(@enumFromInt(1), &.{}))[0].integer);
    // Lower a retained binding expression through the compiler's ordinary
    // expression entry, without manufacturing local slots or pointer types.
    const node: g.GlobalNodeId = @enumFromInt(graph.nodes.items.len);
    try graph.nodes.append(a, .{ .source = source, .ty = @enumFromInt(0), .content = .{ .binding_use = @enumFromInt(0) } });
    var compilation_arena = std.heap.ArenaAllocator.init(a);
    defer compilation_arena.deinit();
    var compiler = try lower.Lower.initSession(compilation_arena.allocator(), &graph, interface);
    const expression_program = try compiler.compileExpression(node, &.{});
    try std.testing.expectEqual(b.Place{ .root = 0, .region = .session, .path = &.{} }, expression_program.expression.?.code[0].op.load.place);
    var expression_vm = try vm.Vm.initShared(a, expression_program, limits, &context);
    defer expression_vm.deinit();
    try std.testing.expectEqual(@as(i128, 42), (try expression_vm.invokeExpression(&.{}))[0].integer);
    _ = try writer.invoke(@enumFromInt(1), &.{});
    try std.testing.expectEqual(@as(i128, 7), (try expression_vm.invokeExpression(&.{}))[0].integer);
    try std.testing.expectEqual(@as(i128, 7), (try reference_reader.invoke(@enumFromInt(1), &.{}))[0].integer);
    try std.testing.expectEqual(@as(i128, 7), (try reader.invoke(@enumFromInt(1), &.{}))[0].integer);
    var foreign = try vm.Vm.initShared(a, .{ .graph = &graph, .functions = &read_functions, .session = .{ .namespace = @enumFromInt(2), .bindings = &bindings } }, limits, &context);
    defer foreign.deinit();
    const cells = context.storage.cells;
    try std.testing.expectError(error.ExecutionForeignSession, foreign.invoke(@enumFromInt(1), &.{}));
    try std.testing.expectEqual(cells, context.storage.cells);
    try std.testing.expectEqual(@as(i128, 7), (try reader.invoke(@enumFromInt(1), &.{}))[0].integer);
    var malformed = b.Program{ .graph = &graph, .functions = &read_functions, .session = null };
    try std.testing.expectError(error.InvalidBytecode, b.verify(a, malformed));
    const duplicates = [_]b.SessionBinding{ bindings[0], bindings[0] };
    malformed.session = .{ .namespace = interface.namespace, .bindings = &duplicates };
    try std.testing.expectError(error.InvalidBytecode, b.verify(a, malformed));
    const wrong_type = [_]b.SessionBinding{.{ .binding = @enumFromInt(0), .slots = slots[1..] }};
    malformed.session = .{ .namespace = interface.namespace, .bindings = &wrong_type };
    try std.testing.expectError(error.InvalidBytecode, b.verify(a, malformed));
    var missing_binding_code = read;
    missing_binding_code[0].op.borrow_storage.place.root = 99;
    const missing_functions = [_]?b.Function{ null, .{ .slots = &slots, .inputs = &.{}, .outputs = &.{0}, .code = &missing_binding_code } };
    malformed = .{ .graph = &graph, .functions = &missing_functions, .session = interface };
    try std.testing.expectError(error.InvalidBytecode, b.verify(a, malformed));
    const uninitialized_functions = [_]?b.Function{ .{ .slots = &slots, .inputs = &.{}, .outputs = &.{0}, .code = initialize[1..] }, null };
    malformed = .{ .graph = &graph, .functions = &uninitialized_functions, .session = interface };
    try std.testing.expectError(error.UninitializedBytecodeSlot, b.verify(a, malformed));
    context.reset();
    try std.testing.expectError(error.ExecutionUninitializedStorage, reader.invoke(@enumFromInt(1), &.{}));
    try std.testing.expectError(error.ExecutionContextPoisoned, first.invoke(@enumFromInt(0), &.{}));
    context.reset();
    _ = try first.invoke(@enumFromInt(0), &.{});
    try std.testing.expectEqual(@as(i128, 42), (try reader.invoke(@enumFromInt(1), &.{}))[0].integer);
}

test "bytecode session moves update persistent cleanup rather than frame flags" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const g = @import("../4_semantics/global/graph.zig");
    var graph: g.GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    try graph.types.appendSlice(a, &.{ .{ .builtin = .Int32 }, .{ .builtin = .Bool } });
    const source = @import("../4_semantics/primitives/schema.zig").SourceRef{ .file_index = 0, .offset = 0 };
    try graph.bindings.append(a, .{ .name = .{ .start = 0, .len = 0 }, .ty = @enumFromInt(0), .source = source, .mutability = .constant });
    try graph.nodes.append(a, .{ .source = source, .ty = @enumFromInt(0), .content = .{ .binding_use = @enumFromInt(0) } });
    try graph.nodes.append(a, .{ .source = source, .ty = @enumFromInt(0), .content = .{ .move_value = @enumFromInt(0) } });
    const bindings = [_]b.SessionBinding{.{ .binding = @enumFromInt(0), .slots = &.{ @enumFromInt(0), @enumFromInt(1) }, .cleanup = &.{.{ .root = 0, .flag = 1, .path = &.{} }} }};
    const interface = b.Session{ .namespace = @enumFromInt(9), .bindings = &bindings };
    var compiler = try lower.Lower.initSession(a, &graph, interface);
    const program = try compiler.compileExpression(@enumFromInt(1), &.{});
    try std.testing.expectEqual(@as(usize, 0), program.expression.?.cleanup.len);
    var context = vm.Context.init(a, 1000);
    defer context.deinit();
    const persistent = try context.sessionSlots(2, bindings[0].cleanup);
    try context.storage.initializeSession(persistent, 0, .{ .integer = 42 });
    try context.bindings.put(context.arena.allocator(), @enumFromInt(0), persistent.frame);
    context.namespace = interface.namespace;
    const reference = @import("../5_codegen/bytecode/value.zig").Reference{ .context = context.storage.context, .frame = persistent.frame, .root = 0, .path = &.{}, .mutability = .read_write };
    _ = try context.storage.cleanupSet(reference, true);
    var executor = try vm.Vm.initShared(a, program, .{ .value_cells = 1000 }, &context);
    defer executor.deinit();
    try std.testing.expectEqual(@as(i128, 42), (try executor.invokeExpression(&.{}))[0].integer);
    try std.testing.expect(!try context.storage.cleanupTest(reference));
    // Explicit exit uses the same selected cleanup descriptor and flag state.
    _ = try context.storage.cleanupSet(reference, true);
    const cleanup_node: g.GlobalNodeId = @enumFromInt(graph.nodes.items.len);
    try graph.auto_deinits.append(a, .{ .storage = .{ .binding = @enumFromInt(0) }, .deinit_fn = null });
    try graph.nodes.append(a, .{ .source = source, .ty = null, .content = .{ .auto_deinit_binding = @enumFromInt(0) } });
    var exit_compiler = try lower.Lower.initSession(a, &graph, interface);
    const exit_program = try exit_compiler.compileSessionCleanup(&.{cleanup_node});
    var exit_vm = try vm.Vm.initShared(a, exit_program, .{ .value_cells = 1000 }, &context);
    defer exit_vm.deinit();
    _ = try exit_vm.invokeExpression(&.{});
    try std.testing.expect(!try context.storage.cleanupTest(reference));
    _ = try exit_vm.invokeExpression(&.{});
    try context.storage.releaseSession(persistent);
}

test "bytecode session declarations initialize persistent storage without local owners" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const g = @import("../4_semantics/global/graph.zig");
    const p = @import("../4_semantics/primitives/schema.zig");
    var graph: g.GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    try graph.types.appendSlice(a, &.{ .{ .builtin = .Int32 }, .{ .builtin = .Bool } });
    const source = p.SourceRef{ .file_index = 0, .offset = 0 };
    try graph.nodes.append(a, .{ .source = source, .ty = @enumFromInt(0), .content = .{ .int_literal = 42 } });
    try graph.bindings.append(a, .{ .name = .{ .start = 0, .len = 0 }, .ty = @enumFromInt(0), .source = source, .mutability = .constant, .initialization = @enumFromInt(0) });
    try graph.nodes.append(a, .{ .source = source, .ty = null, .content = .{ .binding_declaration = @enumFromInt(0) } });
    try graph.node_refs.append(a, @enumFromInt(1));
    try graph.blocks.append(a, .{ .nodes = .{ .start = 0, .len = 1 } });
    try graph.declarations.append(a, .{ .kind = .function, .name = .{ .start = 0, .len = 0 }, .source = source });
    try graph.functions.append(a, .{ .declaration = @enumFromInt(0), .input = .{ .start = 0, .len = 0 }, .output = .{ .start = 0, .len = 0 }, .body = @enumFromInt(0) });
    const bindings = [_]b.SessionBinding{.{ .binding = @enumFromInt(0), .slots = &.{ @enumFromInt(0), @enumFromInt(1) }, .cleanup = &.{.{ .root = 0, .flag = 1, .path = &.{} }} }};
    const interface = b.Session{ .namespace = @enumFromInt(12), .bindings = &bindings };
    var compiler = try lower.Lower.initSession(a, &graph, interface);
    const program = try compiler.compile(@enumFromInt(0));
    try std.testing.expectEqual(@as(usize, 0), program.functions[0].?.cleanup.len);
    var context = vm.Context.init(a, 1000);
    defer context.deinit();
    var executor = try vm.Vm.initShared(a, program, .{ .value_cells = 1000 }, &context);
    defer executor.deinit();
    _ = try executor.invoke(@enumFromInt(0), &.{});
    const frame = context.bindings.get(@enumFromInt(0)).?;
    const persistent = try context.storage.slots(frame);
    try std.testing.expectEqual(@as(i128, 42), (try persistent.get(0)).integer);
    const reference = @import("../5_codegen/bytecode/value.zig").Reference{ .context = context.storage.context, .frame = frame, .root = 0, .path = &.{}, .mutability = .read_write };
    try std.testing.expect(try context.storage.cleanupTest(reference));
    try std.testing.expectError(error.ExecutionActiveCleanup, context.storage.releaseSession(persistent));
    try std.testing.expectError(error.ExecutionInitializedStorage, executor.invoke(@enumFromInt(0), &.{}));
}

test "comptime evaluation releases transient proofs with a retained graph allocator" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const files = [_]sf.SourceFile{.{
        .path = "evaluation/main.rg",
        .code = "answer := () -> (.result: Int32) { result = 42 }\n" ++
            "main := () -> (.status_code: Int32) { status_code = answer() }\n",
    }};
    var diagnostics = diag.Diagnostics.init(&allocator, &files);
    defer diagnostics.deinit();
    var pipeline = frontend.FrontendPipeline.init(allocator, std.testing.io, &diagnostics, .{});
    defer pipeline.deinit();
    const source = try pipeline.semantizeGlobalFiles(&files);
    var graph = try source.clone(std.testing.allocator);
    defer graph.deinit(std.testing.allocator);
    const entry: @import("../4_semantics/global/graph.zig").GlobalFunctionId = for (graph.functions.items, 0..) |function, index| {
        if (std.mem.eql(u8, graph.text(graph.declarationSourceName(function.declaration)), "main")) break @enumFromInt(index);
    } else return error.MissingEntry;
    const before = graph.nodes.items.len;
    const result = try @import("evaluate.zig").evaluate(std.testing.allocator, &graph, &diagnostics, entry, &.{}, graph.declaration(graph.function(entry).declaration).source, .{});
    defer std.testing.allocator.free(result);
    try std.testing.expectEqual(@as(usize, 1), result.len);
    try std.testing.expectEqual(@as(i128, 42), graph.node(result[0]).content.int_literal);
    try std.testing.expectEqual(before + 1, graph.nodes.items.len);
    // Source annotations remain borrowed from the original checked graph;
    // evaluation publishes only its frozen constant, never scratch proof data.
    for (graph.nodes.items[0..before], source.nodes.items) |retained, original|
        try std.testing.expectEqualDeep(original, retained);
}

test "bytecode string literal backing survives completed calls" {
    try std.testing.expectEqual(@as(i128, 65), try execute(
        \\StringView: Type = (._data: &UInt8, ._length: UIntNative)
        \\text := () -> (.result: StringView) { result = "A" }
        \\main := () -> (.status_code: Int32) {
        \\    value ::= text()
        \\    byte ::= value._data&
        \\    if byte == 65 { status_code = 65 } else { status_code = 1 }
        \\}
    , .{}));
}

test "literal storage is immutable compact and survives session publication" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var storage = try @import("storage.zig").Storage.init(arena.allocator(), 100);
    const reference = try storage.staticBytes("hello");
    try std.testing.expectEqualStrings("hello", try storage.literalBytes(reference));
    try std.testing.expectEqual(@as(i128, 'h'), (try storage.read(reference)).integer);
    var forged = reference;
    forged.mutability = .read_write;
    try std.testing.expectError(error.ExecutionReadonlyReference, storage.store(forged, .{ .integer = 0 }));
    try std.testing.expectError(error.ExecutionReadonlyReference, storage.captureResolvedWrite(forged, false));
    try std.testing.expectError(error.ExecutionReadonlyReference, storage.borrow(forged, .read_write));
    const session = try storage.enterSession(1, &.{});
    try storage.initializeSession(session, 0, .{ .reference = reference });
    try std.testing.expectEqual(@as(i128, 'h'), (try storage.read((try session.get(0)).reference)).integer);
    const empty = try storage.staticBytes("");
    try std.testing.expectEqualStrings("", try storage.literalBytes(empty));
    try std.testing.expectEqual(@as(i128, 0), (try storage.read(empty)).integer);
}

test "bounded reference offsets preserve literal backing and permissions" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var storage = try @import("storage.zig").Storage.init(arena.allocator(), 100);
    const reference = try storage.staticBytes("hello");
    const last = try storage.offsetReference(reference, 4);
    try std.testing.expectEqual(@as(i128, 'o'), (try storage.read(last)).integer);
    try std.testing.expectEqual(reference.frame, last.frame);
    try std.testing.expectEqual(.read_only, last.mutability);
    try std.testing.expectError(error.ExecutionIndexOutOfBounds, storage.offsetReference(reference, 6));
    try std.testing.expectError(error.ExecutionIndexOutOfBounds, storage.offsetReference(reference, -1));
}

test "bytecode verifier rejects mutable literal references" {
    const a = std.testing.allocator;
    var graph: @import("../4_semantics/global/graph.zig").GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    try graph.types.append(a, .{ .builtin = .UInt8 });
    try graph.types.append(a, .{ .pointer = .{ .child = @enumFromInt(0), .mutability = .read_write } });
    const source = @import("../4_semantics/primitives/schema.zig").SourceRef{ .file_index = 0, .offset = 0 };
    const expression = b.Function{
        .slots = &.{@enumFromInt(1)},
        .inputs = &.{},
        .outputs = &.{0},
        .code = &.{
            .{ .source = source, .op = .{ .static_bytes = .{ .dst = 0, .bytes = "x" } } },
            .{ .source = source, .op = .{ .ret = &.{0} } },
        },
    };
    try std.testing.expectError(error.InvalidBytecode, b.verify(a, .{ .graph = &graph, .functions = &.{}, .expression = &expression }));
}

test "bytecode executes preselected virtual operations" {
    try std.testing.expectEqual(@as(i128, 42), try execute(
        \\Readable#(.Source: Type): Contract = (.read: (.source: &Source) -> (.result: Int32) where {})
        \\Box: Type = (.value: Int32)
        \\implement Readable#(Box) (.read = (.source: &Box) -> (.result: Int32) { result = source&.value })
        \\main := () -> (.status_code: Int32 = 0) {
        \\    box :: Box = (.value = 42)
        \\    erased ::= to_virtual#(.contract: Readable)(.value = &box)
        \\    status_code = Readable#().read(&erased).result
        \\}
    , .{}));
}

test "virtual values cannot publish temporary receivers or cross contexts" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const storage_mod = @import("storage.zig");
    var storage = try storage_mod.Storage.init(arena.allocator(), 100);
    var graph: @import("../4_semantics/global/graph.zig").GlobalSemanticGraph = .{};
    const program = b.Program{ .graph = &graph, .functions = &.{} };
    const frame = try storage.enter(1);
    try (try storage.slots(frame)).put(0, .{ .integer = 42 });
    const receiver = @import("../5_codegen/bytecode/value.zig").Reference{
        .context = storage.context,
        .frame = frame,
        .root = 0,
        .path = &.{},
        .mutability = .read_only,
    };
    const erased = try storage.virtualize(receiver, &program, &.{ .virtual_type = @enumFromInt(0), .concrete_type = @enumFromInt(0), .methods = &.{} });
    const retained = try storage.enterSession(1, &.{});
    try std.testing.expectError(error.ExecutionTemporaryReference, storage.initializeSession(retained, 0, erased));
    var other = try storage_mod.Storage.init(arena.allocator(), 100);
    try std.testing.expectError(error.ExecutionForeignReference, other.cloneValues(&.{erased}));
    storage.leave(frame);
    try std.testing.expectError(error.ExecutionDeadReference, storage.validateLive(&.{erased}));
}

test "bytecode verifier rejects forged virtual constants and invalid tables" {
    const a = std.testing.allocator;
    var graph: @import("../4_semantics/global/graph.zig").GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    try graph.types.append(a, .{ .builtin = .Int32 });
    try graph.types.append(a, .{ .virtual = @enumFromInt(0) });
    try graph.types.append(a, .{ .pointer = .{ .child = @enumFromInt(0), .mutability = .read_only } });
    const source = @import("../4_semantics/primitives/schema.zig").SourceRef{ .file_index = 0, .offset = 0 };
    const forged: @import("../5_codegen/bytecode/value.zig").Virtual = undefined;
    const instructions = [_]b.Instruction{
        .{ .source = source, .op = .{ .constant = .{ .dst = 1, .value = .{ .virtual_ = &forged } } } },
        .{ .source = source, .op = .{ .virtualize = .{ .dst = 1, .receiver = 0, .table = &.{ .virtual_type = @enumFromInt(99), .concrete_type = @enumFromInt(0), .methods = &.{} } } } },
    };
    for (instructions) |instruction| {
        const expression = b.Function{
            .slots = &.{ @enumFromInt(2), @enumFromInt(1) },
            .inputs = &.{0},
            .outputs = &.{1},
            .code = &.{ instruction, .{ .source = source, .op = .{ .ret = &.{1} } } },
        };
        try std.testing.expectError(error.InvalidBytecode, b.verify(a, .{ .graph = &graph, .functions = &.{}, .expression = &expression }));
    }
}

test "bytecode trace metadata requires an unsigned source ID and valid coordinates" {
    const a = std.testing.allocator;
    var graph: @import("../4_semantics/global/graph.zig").GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    try graph.types.appendSlice(a, &.{ .{ .builtin = .UInt32 }, .{ .builtin = .Int32 } });
    const source = @import("../4_semantics/primitives/schema.zig").SourceRef{ .file_index = 0, .offset = 0 };
    const metadata = [_]b.TraceLocation{
        .{ .path = "input.rg", .offset = 0, .line = 0, .column = 1, .source_line = "" },
        .{ .path = "input.rg", .offset = 0, .line = 1, .column = 0, .source_line = "" },
        .{ .path = "input.rg", .offset = 0, .line = 1, .column = 1, .source_line = "" },
    };
    for (&metadata, 0..) |*location, index| {
        const expression = b.Function{
            .slots = &.{@enumFromInt(@as(u32, if (index == 2) 1 else 0))},
            .inputs = &.{},
            .outputs = &.{0},
            .code = &.{
                .{ .source = source, .op = .{ .trace_location = .{ .dst = 0, .location = location } } },
                .{ .source = source, .op = .{ .ret = &.{0} } },
            },
        };
        try std.testing.expectError(error.InvalidBytecode, b.verify(a, .{ .graph = &graph, .functions = &.{}, .expression = &expression }));
    }
}

test "resolved source text respects signed byte loads" {
    const a = std.testing.allocator;
    var graph: @import("../4_semantics/global/graph.zig").GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    const source = @import("../4_semantics/primitives/schema.zig").SourceRef{ .file_index = 0, .offset = 0 };
    try graph.types.appendSlice(a, &.{
        .{ .builtin = .Int8 },                                                   .{ .builtin = .UInt32 },                                     .{ .builtin = .UIntNative },
        .{ .pointer = .{ .child = @enumFromInt(0), .mutability = .read_only } }, .{ .structural = .{ .fields = .{ .start = 0, .len = 4 } } },
    });
    for ([_][]const u8{ "source_file", "source_line", "line", "column" }, 0..) |name, index|
        try graph.fields.append(a, .{ .source = source, .name = try graph.addString(a, name), .ty = @enumFromInt(@as(u32, if (index < 2) 3 else 2)) });
    const metadata = b.TraceLocation{ .path = "input.rg", .offset = 0, .line = 1, .column = 1, .source_line = "ñ" };
    const expression = b.Function{
        .slots = &.{ @enumFromInt(1), @enumFromInt(4), @enumFromInt(3), @enumFromInt(0) },
        .inputs = &.{},
        .outputs = &.{3},
        .code = &.{
            .{ .source = source, .op = .{ .trace_location = .{ .dst = 0, .location = &metadata } } },
            .{ .source = source, .op = .{ .resolve_location = .{ .dst = 1, .id = 0 } } },
            .{ .source = source, .op = .{ .field = .{ .dst = 2, .base = 1, .index = 1 } } },
            .{ .source = source, .op = .{ .load = .{ .dst = 3, .interpretation = .signed_byte, .place = .{ .root = 2, .path = &.{.dereference} } } } },
            .{ .source = source, .op = .{ .ret = &.{3} } },
        },
    };
    var executor = try vm.Vm.init(a, .{ .graph = &graph, .functions = &.{}, .expression = &expression }, .{});
    defer executor.deinit();
    for (0..4) |_| {
        try std.testing.expectEqual(@as(i128, -61), @import("../5_codegen/integer_arithmetic.zig").decode((try executor.runExpression(&.{}))[0].integer, b.integerBounds(&graph, expression.slots[expression.outputs[0]]).?));
        try std.testing.expectEqual(@as(usize, 1), executor.context().trace_locations.items.len);
        try std.testing.expectEqual(@as(u32, 2), executor.context().literal_bytes.count());
    }
}

test "fresh execution retires literal cache and rejects previous references" {
    const a = std.testing.allocator;
    var graph: @import("../4_semantics/global/graph.zig").GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    const source = @import("../4_semantics/primitives/schema.zig").SourceRef{ .file_index = 0, .offset = 0 };
    try graph.types.appendSlice(a, &.{
        .{ .builtin = .UInt8 },
        .{ .pointer = .{ .child = @enumFromInt(0), .mutability = .read_only } },
    });
    const expression: b.Function = .{
        .slots = &.{@enumFromInt(1)},
        .inputs = &.{},
        .outputs = &.{0},
        .code = &.{
            .{ .source = source, .op = .{ .static_bytes = .{ .dst = 0, .bytes = "retained" } } },
            .{ .source = source, .op = .{ .ret = &.{0} } },
        },
    };
    var executor = try vm.Vm.init(a, .{ .graph = &graph, .functions = &.{}, .expression = &expression }, .{});
    defer executor.deinit();
    const first = (try executor.runExpression(&.{}))[0].reference;
    const second = (try executor.runExpression(&.{}))[0].reference;
    try std.testing.expect(first.context != second.context);
    try std.testing.expectEqualStrings("retained", try executor.context().storage.literalBytes(second));
    try std.testing.expectError(error.ExecutionForeignReference, executor.context().storage.read(first));
    try std.testing.expectEqual(@as(u32, 1), executor.context().literal_bytes.count());
}

test "equivalent borrowed choices use representation tags rather than semantic IDs" {
    const a = std.testing.allocator;
    var graph: @import("../4_semantics/global/graph.zig").GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    const source = @import("../4_semantics/primitives/schema.zig").SourceRef{ .file_index = 0, .offset = 0 };
    const name = try graph.addString(a, "some");
    try graph.types.appendSlice(a, &.{
        .{ .builtin = .Int32 },
        .{ .structural_choice = .{ .variants = .{ .start = 0, .len = 1 } } },
        .{ .structural_choice = .{ .variants = .{ .start = 1, .len = 1 } } },
        .{ .pointer = .{ .child = @enumFromInt(1), .mutability = .read_only } },
        .{ .pointer = .{ .child = @enumFromInt(2), .mutability = .read_only } },
        .{ .pointer = .{ .child = @enumFromInt(0), .mutability = .read_only } },
    });
    for (0..2) |_| try graph.variants.append(a, .{ .name = name, .source = source, .payload_type = @enumFromInt(0), .value = 0 });
    const expression: b.Function = .{
        .slots = &.{ @enumFromInt(0), @enumFromInt(1), @enumFromInt(3), @enumFromInt(4), @enumFromInt(2), @enumFromInt(0), @enumFromInt(5) },
        .inputs = &.{},
        .outputs = &.{5},
        .code = &.{
            .{ .source = source, .op = .{ .constant = .{ .dst = 0, .value = .{ .integer = 42 } } } },
            .{ .source = source, .op = .{ .choice = .{ .dst = 1, .ordinal = 0, .variant = @enumFromInt(0), .payload = 0 } } },
            .{ .source = source, .op = .{ .borrow = .{ .dst = 2, .permission = .read_only, .place = .{ .root = 1, .path = &.{} } } } },
            .{ .source = source, .op = .{ .copy = .{ .dst = 3, .src = 2 } } },
            .{ .source = source, .op = .{ .load = .{ .dst = 4, .place = .{ .root = 3, .path = &.{.dereference} } } } },
            .{ .source = source, .op = .{ .payload = .{ .dst = 5, .src = 4, .ordinal = 0, .variant = @enumFromInt(1) } } },
            .{ .source = source, .op = .{ .borrow = .{ .dst = 6, .permission = .read_only, .place = .{ .root = 3, .path = &.{ .dereference, .{ .variant = .{ .identity = @enumFromInt(1), .ordinal = 0 } } } } } } },
            .{ .source = source, .op = .{ .load = .{ .dst = 5, .place = .{ .root = 6, .path = &.{.dereference} } } } },
            .{ .source = source, .op = .{ .ret = &.{5} } },
        },
    };
    var executor = try vm.Vm.init(a, .{ .graph = &graph, .functions = &.{}, .expression = &expression }, .{});
    defer executor.deinit();
    try std.testing.expectEqual(@as(i128, 42), (try executor.runExpression(&.{}))[0].integer);
    const code = try a.dupe(b.Instruction, expression.code);
    defer a.free(code);
    var malformed = expression;
    malformed.code = code;
    const program: b.Program = .{ .graph = &graph, .functions = &.{}, .expression = &malformed };
    code[6].op.borrow.place.path = &.{ .dereference, .{ .variant = .{ .identity = @enumFromInt(1), .ordinal = 1 } } };
    try std.testing.expectError(error.InvalidBytecode, b.verify(a, program));
    code[6].op.borrow.place.path = &.{ .dereference, .{ .variant = .{ .identity = @enumFromInt(1) } } };
    try std.testing.expectError(error.InvalidBytecode, b.verify(a, program));
}

test "bytecode cleanup branches refine only the active storage edge" {
    const g = @import("../4_semantics/global/graph.zig");
    const a = std.testing.allocator;
    var graph: g.GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    const source = @import("../4_semantics/primitives/schema.zig").SourceRef{ .file_index = 0, .offset = 0 };
    try graph.types.append(a, .{ .builtin = .Int32 });
    try graph.types.append(a, .{ .builtin = .Bool });
    var code = [_]b.Instruction{
        .{ .source = source, .op = .{ .branch_cleanup = .{ .place = .{ .root = 0, .path = &.{} }, .yes = 1, .no = 3 } } },
        .{ .source = source, .op = .{ .copy = .{ .dst = 2, .src = 0 } } },
        .{ .source = source, .op = .{ .jump = 4 } },
        .{ .source = source, .op = .{ .constant = .{ .dst = 2, .value = .{ .integer = 42 } } } },
        .{ .source = source, .op = .{ .ret = &.{2} } },
    };
    const expression: b.Function = .{ .slots = &.{ @enumFromInt(0), @enumFromInt(1), @enumFromInt(0) }, .inputs = &.{}, .outputs = &.{2}, .code = &code, .cleanup = &.{.{ .root = 0, .path = &.{}, .flag = 1 }} };
    const program: b.Program = .{ .graph = &graph, .functions = &.{}, .expression = &expression };
    var executor = try vm.Vm.init(a, program, .{});
    defer executor.deinit();
    try std.testing.expectEqual(@as(i128, 42), (try executor.runExpression(&.{}))[0].integer);
    code[3].op = .{ .copy = .{ .dst = 2, .src = 0 } };
    try std.testing.expectError(error.UninitializedBytecodeSlot, b.verify(a, program));
    code[3].op = .{ .constant = .{ .dst = 2, .value = .{ .integer = 42 } } };
    code[4].op = .{ .ret = &.{0} };
    try std.testing.expectError(error.UninitializedBytecodeSlot, b.verify(a, program));
}

test "bytecode failed lowering does not retain host requirements" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const files = [_]sf.SourceFile{
        .{ .path = "app/main.rg", .code =
        \\Mode: CEnum = (..one)
        \\foreign_value(.value: Int32) -> (.result: Int32): ExternFunction
        \\unsupported(.ffi: $&ForeignFunctionInterface) -> (.result: Int32) := {
        \\    result = foreign_value(.value = 41)
        \\    value: Mode = ..one
        \\}
        \\main() -> (.status_code: Int32 = 0) := {
        \\    capability :: ForeignFunctionInterface = ()
        \\    status_code = unsupported(.ffi = $&capability)
        \\}
        },
        .{ .path = "ffi_core/main.rg", .origin = .bundled_core, .code = "ForeignFunctionInterface: Type = ()" },
    };
    var diagnostics = diag.Diagnostics.init(&a, &files);
    defer diagnostics.deinit();
    var pipeline = frontend.FrontendPipeline.init(a, std.testing.io, &diagnostics, .{});
    defer pipeline.deinit();
    const graph = try pipeline.semantizeGlobalFiles(&files);
    var compiler = try lower.Lower.init(a, graph);
    compiler.mode = .runtime;
    const entry = for (graph.functions.items, 0..) |function, index| {
        if (std.mem.eql(u8, graph.text(graph.declarationSourceName(function.declaration)), "main"))
            break @as(@import("../4_semantics/global/graph.zig").GlobalFunctionId, @enumFromInt(index));
    } else return error.TestMissingEntry;
    try std.testing.expectError(error.UnsupportedExecution, compiler.compile(entry));
    try std.testing.expectEqual(@as(usize, 0), compiler.host_functions.items.len);
}

test "bytecode partial record reservation never permits unavailable field reads" {
    const g = @import("../4_semantics/global/graph.zig");
    const a = std.testing.allocator;
    var graph: g.GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    const source = @import("../4_semantics/primitives/schema.zig").SourceRef{ .file_index = 0, .offset = 0 };
    try graph.types.append(a, .{ .builtin = .Int32 });
    try graph.fields.append(a, .{ .name = .{ .start = 0, .len = 0 }, .ty = @enumFromInt(0), .source = source });
    try graph.types.append(a, .{ .structural = .{ .fields = .{ .start = 0, .len = 1 } } });
    const layout = try @import("../5_codegen/bytecode/storage_layout.zig").compile(a, &graph, @enumFromInt(1));
    defer a.free(layout.nodes);
    var code = [_]b.Instruction{
        .{ .source = source, .op = .{ .reserve_storage = .{ .dst = 0, .layout = layout } } },
        .{ .source = source, .op = .{ .load = .{ .dst = 1, .place = .{ .root = 0, .path = &.{.{ .field = 0 }} } } } },
        .{ .source = source, .op = .{ .ret = &.{1} } },
    };
    const expression: b.Function = .{ .slots = &.{ @enumFromInt(1), @enumFromInt(0) }, .inputs = &.{}, .outputs = &.{1}, .code = &code };
    const program: b.Program = .{ .graph = &graph, .functions = &.{}, .expression = &expression };
    var executor = try vm.Vm.init(a, program, .{});
    defer executor.deinit();
    try std.testing.expectError(error.ExecutionUninitializedStorage, executor.runExpression(&.{}));
    code[0].op.reserve_storage.layout = .{ .nodes = &.{.{}} };
    try std.testing.expectError(error.InvalidBytecode, b.verify(a, program));
}

test "bytecode partial records allow borrowed reads of initialized siblings" {
    try std.testing.expectEqual(@as(i128, 42), try execute(
        \\Pair: Type = (.first: Int32, .second: Int32)
        \\first := (.pair: &Pair) -> (.result: Int32) { result = pair&.first }
        \\make := () -> (.result: Pair) {
        \\    result.first = 41
        \\    result.second = first(.pair = &result) + 1
        \\}
        \\main := () -> (.status_code: Int32 = 0) { status_code = make().second }
    , .{}));
}

test "bytecode reserved scalar storage rejects reads before initialization" {
    const g = @import("../4_semantics/global/graph.zig");
    const a = std.testing.allocator;
    var graph: g.GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    try graph.types.append(a, .{ .builtin = .Int32 });
    const source = @import("../4_semantics/primitives/schema.zig").SourceRef{ .file_index = 0, .offset = 0 };
    const code = [_]b.Instruction{
        .{ .source = source, .op = .{ .reserve_storage = .{ .dst = 0, .layout = .{ .nodes = &.{.{}} } } } },
        .{ .source = source, .op = .{ .copy = .{ .dst = 1, .src = 0 } } },
        .{ .source = source, .op = .{ .ret = &.{1} } },
    };
    const expression: b.Function = .{ .slots = &.{ @enumFromInt(0), @enumFromInt(0) }, .inputs = &.{}, .outputs = &.{1}, .code = &code };
    var executor = try vm.Vm.init(a, .{ .graph = &graph, .functions = &.{}, .expression = &expression }, .{});
    defer executor.deinit();
    try std.testing.expectError(error.ExecutionUninitializedStorage, executor.runExpression(&.{}));
}

test "bytecode cooperative cancellation poisons execution and permits explicit reset" {
    const a = std.testing.allocator;
    var graph: @import("../4_semantics/global/graph.zig").GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    try graph.types.append(a, .{ .builtin = .Int32 });
    try graph.fields.append(a, .{ .name = .{ .start = 0, .len = 0 }, .ty = @enumFromInt(0), .source = .{ .file_index = 0, .offset = 0 } });
    try graph.functions.append(a, .{ .declaration = @enumFromInt(0), .input = .{ .start = 0, .len = 1 }, .output = .{ .start = 0, .len = 1 } });
    const code = [_]b.Instruction{.{ .source = .{ .file_index = 0, .offset = 17 }, .op = .{ .ret = &.{0} } }};
    const functions = [_]?b.Function{.{ .slots = &.{@enumFromInt(0)}, .inputs = &.{0}, .outputs = &.{0}, .code = &code }};
    var cancellation: vm.Cancellation = .{};
    var executor = try vm.Vm.init(a, .{ .graph = &graph, .functions = &functions }, .{ .cancellation = &cancellation });
    defer executor.deinit();
    cancellation.cancel();
    try std.testing.expectError(error.ExecutionCancelled, executor.run(@enumFromInt(0), &.{.{ .integer = 42 }}));
    try std.testing.expectEqual(@as(usize, 0), executor.steps);
    try std.testing.expectEqual(@as(u32, 17), executor.source.offset);
    try std.testing.expectEqual(.poisoned, executor.context().state);
    cancellation.reset();
    try std.testing.expectError(error.ExecutionContextPoisoned, executor.invoke(@enumFromInt(0), &.{.{ .integer = 42 }}));
    executor.reset();
    const values = try executor.invoke(@enumFromInt(0), &.{.{ .integer = 42 }});
    try std.testing.expectEqual(@as(i128, 42), values[0].integer);
}

test "execution context reset retires acquisition identities without refunding live quotas" {
    var context = vm.Context.init(std.testing.allocator, 20);
    defer context.deinit();
    const old = try context.acquireRegion(8, 8);
    const charged = context.storage.cells;
    try context.releaseRegion(old);
    try std.testing.expectEqual(charged, context.storage.cells);
    const live = try context.acquireRegion(8, 8);
    try std.testing.expect(live.region != old.region);
    try context.writeRegion(live, 0, &.{ 41, 42 });
    var bytes: [2]u8 = undefined;
    try context.readRegion(live, 0, &bytes);
    try std.testing.expectEqualSlices(u8, &.{ 41, 42 }, &bytes);
    context.running = true;
    try std.testing.expectError(error.ExecutionContextBusy, context.acquireRegion(0, 1));
    try std.testing.expectError(error.ExecutionContextBusy, context.releaseRegion(live));
    context.running = false;
    context.reset();
    const fresh = try context.acquireRegion(8, 8);
    try std.testing.expect(fresh.context != live.context);
    try std.testing.expectError(error.ExecutionForeignReference, context.releaseRegion(live));
    try std.testing.expectError(error.ExecutionForeignReference, context.readRegion(live, 0, &bytes));
    try std.testing.expectError(error.ExecutionUninitializedStorage, context.readRegion(fresh, 0, &bytes));
    try context.releaseRegion(fresh);
}

test "bytecode acquired establishment requires a checked primitive and matching numeric layout" {
    const a = std.testing.allocator;
    var graph: @import("../4_semantics/global/graph.zig").GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    try graph.types.appendSlice(a, &.{ .{ .builtin = .UIntNative }, .{ .builtin = .Int32 }, .{ .pointer = .{ .child = @enumFromInt(1), .mutability = .read_write } } });
    const source: @import("../4_semantics/primitives/schema.zig").SourceRef = .{ .file_index = 0, .offset = 0 };
    try graph.fields.appendSlice(a, &.{
        .{ .name = .{ .start = 0, .len = 0 }, .ty = @enumFromInt(0), .source = source },
        .{ .name = .{ .start = 0, .len = 0 }, .ty = @enumFromInt(2), .source = source },
    });
    try graph.functions.append(a, .{ .declaration = @enumFromInt(0), .input = .{ .start = 0, .len = 1 }, .output = .{ .start = 1, .len = 1 } });
    var layout: @import("../5_codegen/bytecode/numeric_layout.zig").Layout = .{ .size = 4, .alignment = 4, .shape = .{ .integer = .{ .signed = true } } };
    var code = [_]b.Instruction{
        .{ .source = source, .op = .{ .acquired_reference = .{ .dst = 1, .address = 0, .layout = &layout, .permission = .read_write, .endian = graph.target.stdTarget().cpu.arch.endian() } } },
        .{ .source = source, .op = .{ .ret = &.{1} } },
    };
    const functions = [_]?b.Function{.{ .slots = &.{ @enumFromInt(0), @enumFromInt(2) }, .inputs = &.{0}, .outputs = &.{1}, .code = &code }};
    const program: b.Program = .{ .graph = &graph, .functions = &functions };
    try std.testing.expectError(error.InvalidBytecode, b.verify(a, program));
    graph.functions.items[0].safety_primitive = .establish_inherited_reference;
    try b.verify(a, program);
    layout.size = 8;
    try std.testing.expectError(error.InvalidBytecode, b.verify(a, program));
    layout.size = 4;
    code[0].op.acquired_reference.permission = .read_only;
    try std.testing.expectError(error.InvalidBytecode, b.verify(a, program));
    code[0].op.acquired_reference.permission = .read_write;
    code[0].op.acquired_reference.endian = if (graph.target.stdTarget().cpu.arch.endian() == .little) .big else .little;
    try std.testing.expectError(error.InvalidBytecode, b.verify(a, program));
}

test "bytecode memory adapters consume registered identities rather than declaration names" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const files = [_]sf.SourceFile{
        .{ .path = "app/main.rg", .code = "_free(.address: UIntNative) -> (): ExternFunction\nmain := () -> () {}" },
        .{ .path = "core/libc/libc.rg", .origin = .bundled_core, .code = "_free(.address: UIntNative) -> (): ExternFunction\n_aligned_free(.address: UIntNative) -> (): ExternFunction\n_malloc(.size: UIntNative) -> (.address: UIntNative): ExternFunction\n_aligned_alloc(.alignment: UIntNative, .size: UIntNative) -> (.address: UIntNative): ExternFunction" },
        .{ .path = "ffi_core/main.rg", .origin = .bundled_core, .code = "ForeignFunctionInterface: Type = ()" },
    };
    var diagnostics = diag.Diagnostics.init(&a, &files);
    defer diagnostics.deinit();
    var pipeline = frontend.FrontendPipeline.init(a, std.testing.io, &diagnostics, .{});
    defer pipeline.deinit();
    const graph = pipeline.semantizeGlobalFiles(&files) catch |err| {
        try diagnostics.dump();
        return err;
    };
    const memory = @import("../5_codegen/bytecode/memory_boundary.zig");
    var releases: usize = 0;
    var ordinary: usize = 0;
    for (graph.functions.items, 0..) |function, index| {
        const name = graph.text(graph.declaration(function.declaration).name);
        if (!std.mem.eql(u8, name, "_free") and !std.mem.eql(u8, name, "_aligned_free")) continue;
        const id: @import("../4_semantics/global/graph.zig").GlobalFunctionId = @enumFromInt(index);
        if (function.safety_primitive == .raw_released_storage) {
            try std.testing.expect(memory.classify(graph, id).? == .release);
            const source = function.input;
            const argument_types = try a.alloc(b.Type, source.len);
            const arguments = try a.alloc(b.Slot, source.len);
            for (argument_types, arguments, graph.fields.items[source.start..][0..source.len], 0..) |*ty, *slot, field, position| {
                ty.* = field.ty;
                slot.* = @intCast(position);
            }
            var code = [_]b.Instruction{
                .{ .source = .{ .file_index = 0, .offset = 0 }, .op = .{ .memory_call = .{ .outputs = &.{}, .function = id, .operation = .release, .args = arguments } } },
                .{ .source = .{ .file_index = 0, .offset = 0 }, .op = .{ .ret = &.{} } },
            };
            const expression: b.Function = .{ .slots = argument_types, .inputs = arguments, .outputs = &.{}, .code = &code };
            const functions = try a.alloc(?b.Function, graph.functions.items.len);
            @memset(functions, null);
            const program: b.Program = .{ .graph = graph, .functions = functions, .expression = &expression };
            try b.verify(a, program);
            code[0].op.memory_call.operation = .{ .allocate = .{ .size = 0, .alignment = null } };
            try std.testing.expectError(error.InvalidBytecode, b.verify(a, program));
            releases += 1;
            // Classification remains valid with no filename or declaration-name
            // spelling available after the frontend has selected the identity.
            const declaration = &graph.declarations.items[@intFromEnum(function.declaration)];
            declaration.name = .{ .start = 0, .len = 0 };
            declaration.source.file_index = std.math.maxInt(u32);
            try std.testing.expect(memory.classify(graph, id).? == .release);
        } else {
            try std.testing.expect(memory.classify(graph, id) == null);
            ordinary += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 2), releases);
    try std.testing.expectEqual(@as(usize, 1), ordinary);
}

test "negative narrow indices cannot address positive array elements" {
    const a = std.testing.allocator;
    const g = @import("../4_semantics/global/graph.zig");
    var graph: g.GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    try graph.types.appendSlice(a, &.{
        .{ .builtin = .Int32 },
        .{ .builtin = .Int8 },
        .{ .array = .{ .element = @enumFromInt(0), .length = 300 } },
    });
    const source = @import("../4_semantics/primitives/schema.zig").SourceRef{ .file_index = 0, .offset = 0 };
    const values: [300]b.Value = @splat(.{ .integer = 42 });
    var code = [_]b.Instruction{
        .{ .source = source, .op = .{ .constant = .{ .dst = 0, .value = .{ .array = &values } } } },
        .{ .source = source, .op = .{ .constant = .{ .dst = 1, .value = .{ .integer = 255 } } } },
        .{ .source = source, .op = .{ .index = .{ .dst = 2, .base = 0, .index = 1, .kind = .i8 } } },
        .{ .source = source, .op = .{ .ret = &.{2} } },
    };
    const expression: b.Function = .{ .slots = &.{ @enumFromInt(2), @enumFromInt(1), @enumFromInt(0) }, .inputs = &.{}, .outputs = &.{2}, .code = &code };
    const program: b.Program = .{ .graph = &graph, .functions = &.{}, .expression = &expression };
    code[2].op.index.kind = .u8;
    try std.testing.expectError(error.InvalidBytecode, b.verify(a, program));
    code[2].op.index.kind = .unresolved;
    try std.testing.expectError(error.InvalidBytecode, b.verify(a, program));
    code[2].op.index.kind = .i8;
    var executor = try vm.Vm.init(a, program, .{});
    defer executor.deinit();
    try std.testing.expectError(error.ExecutionIndexOutOfBounds, executor.runExpression(&.{}));
    code[2].op = .{ .load = .{ .dst = 2, .place = .{ .root = 0, .path = &.{.{ .element = .{ .slot = 1, .kind = .u8 } }} } } };
    try std.testing.expectError(error.InvalidBytecode, b.verify(a, program));
    code[2].op.load.place.path = &.{.{ .element = .{ .slot = 1 } }};
    try std.testing.expectError(error.InvalidBytecode, b.verify(a, program));
    code[2].op.load.place.path = &.{.{ .element = .{ .slot = 1, .kind = .i8 } }};
    var projected = try vm.Vm.init(a, program, .{});
    defer projected.deinit();
    try std.testing.expectError(error.ExecutionIndexOutOfBounds, projected.runExpression(&.{}));
}
