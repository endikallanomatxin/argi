const std = @import("std");
const c = @import("llvm.zig").c;
const g = @import("../../4_semantics/global/graph.zig");
const layout = @import("../cleanup_layout.zig");

// A compiler-owned view of a runtime flag range. Building a view allocates only
// compilation metadata: it neither initializes flags nor acquires obligations.
// Local owners allocate flags; borrowed views retain the caller's flag storage.
pub const View = struct {
    flag_ref: c.LLVMValueRef = null,
    flag_count: usize = 0,
    fields: []View = &.{},

    pub fn allocate(allocator: std.mem.Allocator, graph: *const g.GlobalSemanticGraph, counts: *layout.Counts, ty: g.GlobalTypeId, builder: c.LLVMBuilderRef) !*View {
        const count = try counts.count(allocator, graph, ty);
        const flags = c.LLVMBuildAlloca(builder, c.LLVMArrayType2(c.LLVMInt1Type(), count), "cleanup.flags");
        return fromPointer(allocator, graph, counts, ty, builder, flags);
    }

    // The selected evidence must establish a present range of the checked
    // type's size. A nullable/missing evidence pointer is not such a proof.
    // Crucially, constructing a borrowed view emits no alloca or flag writes.
    pub fn fromPointer(allocator: std.mem.Allocator, graph: *const g.GlobalSemanticGraph, counts: *layout.Counts, ty: g.GlobalTypeId, builder: c.LLVMBuilderRef, flags: c.LLVMValueRef) !*View {
        if (c.LLVMGetTypeKind(c.LLVMTypeOf(flags)) != c.LLVMPointerTypeKind or c.LLVMIsNull(flags) != 0)
            return error.InvalidCleanupEvidence;
        const count = try counts.count(allocator, graph, ty);
        const state = try allocator.create(View);
        errdefer allocator.destroy(state);
        var next: usize = 0;
        try state.build(allocator, graph, ty, builder, flags, c.LLVMArrayType2(c.LLVMInt1Type(), count), &next);
        std.debug.assert(next == count);
        return state;
    }

    fn build(self: *View, allocator: std.mem.Allocator, graph: *const g.GlobalSemanticGraph, ty: g.GlobalTypeId, builder: c.LLVMBuilderRef, flags: c.LLVMValueRef, flag_type: c.LLVMTypeRef, next: *usize) anyerror!void {
        const start = next.*;
        var indices = [_]c.LLVMValueRef{ c.LLVMConstInt(c.LLVMInt32Type(), 0, 0), c.LLVMConstInt(c.LLVMInt64Type(), start, 0) };
        self.* = .{ .flag_ref = c.LLVMBuildInBoundsGEP2(builder, flag_type, flags, &indices, indices.len, "needs.deinit") };
        next.* += 1;
        const shape = layout.Shape.of(graph, ty);
        self.fields = try allocator.alloc(View, shape.len());
        for (self.fields, 0..) |*field, index| {
            if (shape.child(graph, index)) |child| {
                try field.build(allocator, graph, child.ty, builder, flags, flag_type, next);
            } else field.* = .{};
        }
        self.flag_count = next.* - start;
    }

    pub fn set(self: *const View, builder: c.LLVMBuilderRef, enabled: bool) void {
        self.setValue(builder, c.LLVMConstInt(c.LLVMInt1Type(), if (enabled) 1 else 0, 0));
    }

    pub fn setValue(self: *const View, builder: c.LLVMBuilderRef, enabled: c.LLVMValueRef) void {
        std.debug.assert(c.LLVMTypeOf(enabled) == c.LLVMInt1Type());
        if (self.flag_count == 0) return;
        if (self.flag_count == 1) {
            _ = c.LLVMBuildStore(builder, enabled, self.flag_ref);
        } else {
            const byte = c.LLVMBuildZExt(builder, enabled, c.LLVMInt8Type(), "cleanup.flag.byte");
            _ = c.LLVMBuildMemSet(builder, self.flag_ref, byte, c.LLVMConstInt(c.LLVMInt64Type(), self.flag_count, 0), 1);
        }
    }
};

test "native cleanup views borrow incoming evidence without allocating or initializing flags" {
    const a = std.testing.allocator;
    var graph: g.GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    const source = @import("../../4_semantics/primitives/schema.zig").SourceRef{ .file_index = 0, .offset = 0 };
    try graph.types.appendSlice(a, &.{
        .{ .structural = .{ .fields = .{ .start = 0, .len = 0 } } },
        .{ .structural = .{ .fields = .{ .start = 0, .len = 2 } } },
    });
    for (0..2) |_| try graph.fields.append(a, .{
        .name = .{ .start = 0, .len = 0 },
        .source = source,
        .ty = @enumFromInt(0),
    });
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    var counts: layout.Counts = .{};
    defer counts.deinit(arena.allocator());
    const module = c.LLVMModuleCreateWithName("borrowed_cleanup_evidence_test");
    defer c.LLVMDisposeModule(module);
    const builder = c.LLVMCreateBuilder();
    defer c.LLVMDisposeBuilder(builder);
    const evidence = @import("reference_evidence.zig");
    const signature = @import("argi_abi.zig").Signature.initWithEvidence(
        c.LLVMStructType(null, 0, 0),
        c.LLVMInt1Type(),
        false,
        .{ .input = evidence.storageViewType() },
    );
    const function = c.LLVMAddFunction(module, "consume_selected_child", signature.function_type);
    const block = c.LLVMAppendBasicBlock(function, "entry");
    c.LLVMPositionBuilderAtEnd(builder, block);
    const flags = c.LLVMBuildExtractValue(builder, signature.inputEvidence(function).?, 0, "incoming.cleanup.flags");
    const view = try View.fromPointer(arena.allocator(), &graph, &counts, @enumFromInt(1), builder, flags);
    try std.testing.expectEqual(@as(usize, 3), view.flag_count);
    try std.testing.expectEqual(@as(usize, 2), view.fields.len);
    try std.testing.expectEqual(@as(usize, 1), view.fields[0].flag_count);
    try std.testing.expectEqual(@as(usize, 1), view.fields[1].flag_count);
    // The values of these empty siblings may share a physical address. Their
    // flags are nevertheless distinct projections of the incoming owner block.
    try std.testing.expectEqual(@as(c_ulonglong, 1), c.LLVMConstIntGetZExtValue(c.LLVMGetOperand(view.fields[0].flag_ref, 2)));
    try std.testing.expectEqual(@as(c_ulonglong, 2), c.LLVMConstIntGetZExtValue(c.LLVMGetOperand(view.fields[1].flag_ref, 2)));
    var instruction = c.LLVMGetFirstInstruction(block);
    while (instruction != null) : (instruction = c.LLVMGetNextInstruction(instruction)) {
        const opcode = c.LLVMGetInstructionOpcode(instruction);
        try std.testing.expect(opcode != c.LLVMAlloca and opcode != c.LLVMStore and opcode != c.LLVMLoad);
    }
    const before = c.LLVMGetLastInstruction(block);
    try std.testing.expectError(error.InvalidCleanupEvidence, View.fromPointer(arena.allocator(), &graph, &counts, @enumFromInt(1), builder, c.LLVMConstNull(c.LLVMPointerType(c.LLVMInt1Type(), 0))));
    try std.testing.expectError(error.InvalidCleanupEvidence, View.fromPointer(arena.allocator(), &graph, &counts, @enumFromInt(1), builder, c.LLVMConstInt(c.LLVMInt32Type(), 0, 0)));
    try std.testing.expectEqual(before, c.LLVMGetLastInstruction(block));
    view.fields[1].set(builder, false);
    const preserved = c.LLVMBuildLoad2(builder, c.LLVMInt1Type(), view.fields[0].flag_ref, "sibling.cleanup.preserved");
    try signature.returnValue(builder, function, preserved);
    var message: [*c]u8 = null;
    defer if (message != null) c.LLVMDisposeMessage(message);
    const invalid = c.LLVMVerifyModule(module, c.LLVMReturnStatusAction, &message);
    if (invalid != 0) std.debug.print("{s}\n", .{message});
    try std.testing.expectEqual(@as(c_int, 0), invalid);
}
