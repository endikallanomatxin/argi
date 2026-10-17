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
        .{ .source = source, .op = .{ .index = .{ .dst = 3, .base = 2, .index = 0 } } },
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
    try std.testing.expect(try storage.cleanupTest(owner));
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
        .{ .source = source, .op = .{ .borrow = .{ .dst = 1, .place = .{ .root = 0, .path = &.{} } } } },
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
        .{ .source = source, .op = .{ .borrow = .{ .dst = 1, .place = .{ .root = 0, .path = &.{} } } } },
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
        .{ .source = source, .op = .{ .borrow = .{ .dst = 2, .place = .{ .root = 0, .path = &.{} } } } },
        .{ .source = source, .op = .{ .jump = 5 } },
        .{ .source = source, .op = .{ .capture_write = .{ .dst = 0, .place = .{ .root = 2, .path = &.{.dereference} } } } },
        .{ .source = source, .op = .{ .borrow = .{ .dst = 2, .place = .{ .root = 1, .path = &.{} } } } },
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
    const destination = try storage.captureWrite(frame, .{ .root = 0, .path = &.{.{ .element = 1 }} }, false);
    try slots.put(1, .{ .integer = 1 });
    try std.testing.expectEqual(@as(usize, 0), try commitWrite(&storage, destination, .{ .integer = 42 }));
    try std.testing.expectEqual(@as(i128, 42), (try slots.get(0)).array[0].integer);
    try std.testing.expectEqual(@as(i128, 2), (try slots.get(0)).array[1].integer);
    try slots.put(1, .{ .integer = 2 });
    try std.testing.expectError(error.ExecutionIndexOutOfBounds, storage.captureWrite(frame, .{ .root = 0, .path = &.{.{ .element = 1 }} }, false));
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
    try std.testing.expectEqual(@as(usize, 1), try storage.activateWriteCleanup(destination));
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
