const std = @import("std");
const c = @import("llvm.zig").c;
const g = @import("../../4_semantics/global/graph.zig");
const layout = @import("../cleanup_layout.zig");

// A small value describing a range in an owner's runtime flags. Type layouts
// are shared across owners; projections allocate no compiler-owned view tree.
pub const View = struct {
    flag_ref: c.LLVMValueRef,
    layouts: *const layout.Counts,
    ty: g.GlobalTypeId,

    pub fn allocate(allocator: std.mem.Allocator, graph: *const g.GlobalSemanticGraph, counts: *layout.Counts, ty: g.GlobalTypeId, builder: c.LLVMBuilderRef) !View {
        const flag_count = try counts.count(allocator, graph, ty);
        const flags = c.LLVMBuildAlloca(builder, c.LLVMArrayType2(c.LLVMInt1Type(), flag_count), "cleanup.flags");
        return fromPointer(allocator, graph, counts, ty, flags);
    }

    // Borrowing a range neither allocates nor initializes runtime flag storage.
    pub fn fromPointer(allocator: std.mem.Allocator, graph: *const g.GlobalSemanticGraph, counts: *layout.Counts, ty: g.GlobalTypeId, flags: c.LLVMValueRef) !View {
        if (c.LLVMGetTypeKind(c.LLVMTypeOf(flags)) != c.LLVMPointerTypeKind or c.LLVMIsNull(flags) != 0)
            return error.InvalidCleanupEvidence;
        _ = try counts.count(allocator, graph, ty);
        return .{ .flag_ref = flags, .layouts = counts, .ty = ty };
    }

    pub fn count(self: View) usize {
        return self.layouts.description(self.ty).count;
    }

    pub fn project(self: View, builder: c.LLVMBuilderRef, index: usize) ?View {
        const children = self.layouts.description(self.ty).children;
        if (index >= children.len) return null;
        const child = children[index] orelse return null;
        var offset = [_]c.LLVMValueRef{c.LLVMConstInt(c.LLVMInt64Type(), child.offset, 0)};
        return .{
            .flag_ref = c.LLVMBuildInBoundsGEP2(builder, c.LLVMInt1Type(), self.flag_ref, &offset, offset.len, "needs.deinit"),
            .layouts = self.layouts,
            .ty = child.ty,
        };
    }

    pub fn set(self: View, builder: c.LLVMBuilderRef, enabled: bool) void {
        self.setValue(builder, c.LLVMConstInt(c.LLVMInt1Type(), if (enabled) 1 else 0, 0));
    }

    pub fn setValue(self: View, builder: c.LLVMBuilderRef, enabled: c.LLVMValueRef) void {
        std.debug.assert(c.LLVMTypeOf(enabled) == c.LLVMInt1Type());
        if (self.count() == 0) return;
        if (self.count() == 1) {
            _ = c.LLVMBuildStore(builder, enabled, self.flag_ref);
        } else {
            const byte = c.LLVMBuildZExt(builder, enabled, c.LLVMInt8Type(), "cleanup.flag.byte");
            _ = c.LLVMBuildMemSet(builder, self.flag_ref, byte, c.LLVMConstInt(c.LLVMInt64Type(), self.count(), 0), 1);
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
    const view = try View.fromPointer(arena.allocator(), &graph, &counts, @enumFromInt(1), flags);
    // Owner views borrow cached type descriptions. Creating another view must
    // not allocate, and growing the cache must not invalidate an existing one.
    const borrowed = try View.fromPointer(std.testing.failing_allocator, &graph, &counts, @enumFromInt(1), flags);
    for (0..64) |_| {
        const ty: g.GlobalTypeId = @enumFromInt(graph.types.items.len);
        try graph.types.append(a, .{ .builtin = .Int32 });
        _ = try counts.count(arena.allocator(), &graph, ty);
    }
    try std.testing.expectEqual(view.count(), borrowed.count());
    try std.testing.expect(view.project(builder, 2) == null);
    const first = view.project(builder, 0).?;
    const second = view.project(builder, 1).?;
    try std.testing.expectEqual(@as(usize, 3), view.count());
    try std.testing.expectEqual(@as(usize, 1), first.count());
    try std.testing.expectEqual(@as(usize, 1), second.count());
    // The values of these empty siblings may share a physical address. Their
    // flags are nevertheless distinct projections of the incoming owner block.
    try std.testing.expectEqual(@as(c_ulonglong, 1), c.LLVMConstIntGetZExtValue(c.LLVMGetOperand(first.flag_ref, 1)));
    try std.testing.expectEqual(@as(c_ulonglong, 2), c.LLVMConstIntGetZExtValue(c.LLVMGetOperand(second.flag_ref, 1)));
    var instruction = c.LLVMGetFirstInstruction(block);
    while (instruction != null) : (instruction = c.LLVMGetNextInstruction(instruction)) {
        const opcode = c.LLVMGetInstructionOpcode(instruction);
        try std.testing.expect(opcode != c.LLVMAlloca and opcode != c.LLVMStore and opcode != c.LLVMLoad);
    }
    const before = c.LLVMGetLastInstruction(block);
    try std.testing.expectError(error.InvalidCleanupEvidence, View.fromPointer(arena.allocator(), &graph, &counts, @enumFromInt(1), c.LLVMConstNull(c.LLVMPointerType(c.LLVMInt1Type(), 0))));
    try std.testing.expectError(error.InvalidCleanupEvidence, View.fromPointer(arena.allocator(), &graph, &counts, @enumFromInt(1), c.LLVMConstInt(c.LLVMInt32Type(), 0, 0)));
    try std.testing.expectEqual(before, c.LLVMGetLastInstruction(block));
    second.set(builder, false);
    const preserved = c.LLVMBuildLoad2(builder, c.LLVMInt1Type(), first.flag_ref, "sibling.cleanup.preserved");
    try signature.returnValue(builder, function, preserved);
    var message: [*c]u8 = null;
    defer if (message != null) c.LLVMDisposeMessage(message);
    const invalid = c.LLVMVerifyModule(module, c.LLVMReturnStatusAction, &message);
    if (invalid != 0) std.debug.print("{s}\n", .{message});
    try std.testing.expectEqual(@as(c_int, 0), invalid);
}
