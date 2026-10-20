const std = @import("std");
const c = @import("llvm.zig").c;
const g = @import("../../4_semantics/global/graph.zig");
const layout = @import("../cleanup_layout.zig");

// One helper per cleanup shape updates ancestor flags for a runtime projection.
// Types and offsets select logical flag ranges; value addresses play no role.
pub const RefreshFunctions = struct {
    functions: std.AutoHashMapUnmanaged(g.GlobalTypeId, c.LLVMValueRef) = .empty,

    pub fn deinit(self: *RefreshFunctions, allocator: std.mem.Allocator) void {
        self.functions.deinit(allocator);
    }

    pub fn functionType() c.LLVMTypeRef {
        var parameters = [_]c.LLVMTypeRef{ c.LLVMPointerType(c.LLVMInt1Type(), 0), c.LLVMInt64Type() };
        return c.LLVMFunctionType(c.LLVMVoidType(), &parameters, parameters.len, 0);
    }

    pub fn get(self: *RefreshFunctions, allocator: std.mem.Allocator, counts: *const layout.Counts, module: c.LLVMModuleRef, ty: g.GlobalTypeId) error{OutOfMemory}!c.LLVMValueRef {
        if (self.functions.get(ty)) |function| return function;
        const function = c.LLVMAddFunction(module, "cleanup.refresh", functionType());
        c.LLVMSetLinkage(function, c.LLVMInternalLinkage);
        try self.functions.put(allocator, ty, function);
        const builder = c.LLVMCreateBuilder();
        defer c.LLVMDisposeBuilder(builder);
        const entry = c.LLVMAppendBasicBlock(function, "entry");
        const parents = c.LLVMAppendBasicBlock(function, "parents");
        const done = c.LLVMAppendBasicBlock(function, "done");
        c.LLVMPositionBuilderAtEnd(builder, entry);
        const flags = c.LLVMGetParam(function, 0);
        const offset = c.LLVMGetParam(function, 1);
        const zero = c.LLVMConstInt(c.LLVMInt64Type(), 0, 0);
        _ = c.LLVMBuildCondBr(builder, c.LLVMBuildICmp(builder, c.LLVMIntEQ, offset, zero, "cleanup.whole"), done, parents);
        // A descendant's helper runs first. Only the selected subtree can
        // affect completion; siblings retain their independent flag ranges.
        c.LLVMPositionBuilderAtEnd(builder, parents);
        const description = counts.description(ty);
        for (description.children) |maybe_child| if (maybe_child) |child| {
            const count = counts.description(child.ty).count;
            if (count <= 1) continue;
            const run = c.LLVMAppendBasicBlock(function, "child");
            const next = c.LLVMAppendBasicBlock(function, "next");
            const start = c.LLVMConstInt(c.LLVMInt64Type(), child.offset, 0);
            const end = c.LLVMConstInt(c.LLVMInt64Type(), child.offset + count, 0);
            const selected = c.LLVMBuildAnd(builder, c.LLVMBuildICmp(builder, c.LLVMIntUGE, offset, start, "cleanup.after.start"), c.LLVMBuildICmp(builder, c.LLVMIntULT, offset, end, "cleanup.before.end"), "cleanup.in.child");
            _ = c.LLVMBuildCondBr(builder, selected, run, next);
            c.LLVMPositionBuilderAtEnd(builder, run);
            var indices = [_]c.LLVMValueRef{start};
            var arguments = [_]c.LLVMValueRef{
                c.LLVMBuildInBoundsGEP2(builder, c.LLVMInt1Type(), flags, &indices, 1, "cleanup.child.flags"),
                c.LLVMBuildSub(builder, offset, start, "cleanup.child.offset"),
            };
            _ = c.LLVMBuildCall2(builder, functionType(), try self.get(allocator, counts, module, child.ty), &arguments, arguments.len, "");
            _ = c.LLVMBuildBr(builder, next);
            c.LLVMPositionBuilderAtEnd(builder, next);
        };
        promoteRecord(builder, flags, description, 0);
        _ = c.LLVMBuildBr(builder, done);
        c.LLVMPositionBuilderAtEnd(builder, done);
        _ = c.LLVMBuildRetVoid(builder);
        return function;
    }
};

pub const RuntimeOwner = struct {
    flags: c.LLVMValueRef,
    refresh: c.LLVMValueRef,
    offset: c.LLVMValueRef,
};

// A small value describing a range in an owner's runtime flags. Type layouts
// are shared across owners; projections allocate no compiler-owned view tree.
pub const View = struct {
    flag_ref: c.LLVMValueRef,
    layouts: *const layout.Counts,
    ty: g.GlobalTypeId,
    owner_flags: c.LLVMValueRef = null,
    owner_type: ?g.GlobalTypeId = null,
    offset: usize = 0,
    runtime_owner: ?RuntimeOwner = null,

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
        return .{ .flag_ref = flags, .layouts = counts, .ty = ty, .owner_flags = flags, .owner_type = ty };
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
            .owner_flags = self.owner_flags orelse self.flag_ref,
            .owner_type = self.owner_type orelse self.ty,
            .offset = self.offset + child.offset,
            .runtime_owner = if (self.runtime_owner) |owner| .{
                .flags = owner.flags,
                .refresh = owner.refresh,
                .offset = c.LLVMBuildAdd(builder, owner.offset, offset[0], "cleanup.projected.offset"),
            } else null,
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
        if (self.runtime_owner) |owner| {
            const function = c.LLVMGetBasicBlockParent(c.LLVMGetInsertBlock(builder));
            const run = c.LLVMAppendBasicBlock(function, "cleanup.refresh.owner");
            const done = c.LLVMAppendBasicBlock(function, "cleanup.refreshed");
            _ = c.LLVMBuildCondBr(builder, c.LLVMBuildIsNull(builder, owner.refresh, "cleanup.no.owner"), done, run);
            c.LLVMPositionBuilderAtEnd(builder, run);
            var arguments = [_]c.LLVMValueRef{ owner.flags, owner.offset };
            _ = c.LLVMBuildCall2(builder, RefreshFunctions.functionType(), owner.refresh, &arguments, arguments.len, "");
            _ = c.LLVMBuildBr(builder, done);
            c.LLVMPositionBuilderAtEnd(builder, done);
        } else if (self.offset != 0) self.promoteRecords(builder, self.owner_type.?, 0);
    }

    fn promoteRecords(self: View, builder: c.LLVMBuilderRef, ty: g.GlobalTypeId, base: usize) void {
        if (base == self.offset) return;
        const description = self.layouts.description(ty);
        for (description.children) |maybe_child| if (maybe_child) |child| {
            const start = base + child.offset;
            if (self.offset >= start and self.offset < start + self.layouts.description(child.ty).count) {
                self.promoteRecords(builder, child.ty, start);
                break;
            }
        };
        promoteRecord(builder, self.owner_flags, description, base);
    }
};

fn promoteRecord(builder: c.LLVMBuilderRef, flags: c.LLVMValueRef, description: layout.Counts.Description, base: usize) void {
    if (!description.is_record or description.children.len == 0) return;
    var complete = c.LLVMConstInt(c.LLVMInt1Type(), 1, 0);
    for (description.children) |maybe_child| {
        const child = maybe_child orelse return;
        var offset = [_]c.LLVMValueRef{c.LLVMConstInt(c.LLVMInt64Type(), base + child.offset, 0)};
        const pointer = c.LLVMBuildInBoundsGEP2(builder, c.LLVMInt1Type(), flags, &offset, 1, "cleanup.field.flag");
        const ready = c.LLVMBuildLoad2(builder, c.LLVMInt1Type(), pointer, "cleanup.field.ready");
        complete = c.LLVMBuildAnd(builder, complete, ready, "cleanup.record.ready");
    }
    var offset = [_]c.LLVMValueRef{c.LLVMConstInt(c.LLVMInt64Type(), base, 0)};
    const pointer = c.LLVMBuildInBoundsGEP2(builder, c.LLVMInt1Type(), flags, &offset, 1, "cleanup.owner.flag");
    // A consumed descendant makes the record incomplete as well. Keeping an
    // earlier whole-value flag would call its nominal destructor on vacant
    // storage; reinitialization recomputes completeness from the same children.
    _ = c.LLVMBuildStore(builder, complete, pointer);
}

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
    var refresh: RefreshFunctions = .{};
    defer refresh.deinit(a);
    const helper = try refresh.get(a, &counts, module, @enumFromInt(1));
    try std.testing.expectEqual(helper, try refresh.get(std.testing.failing_allocator, &counts, module, @enumFromInt(1)));
    var runtime = borrowed;
    runtime.runtime_owner = .{ .flags = flags, .refresh = helper, .offset = c.LLVMConstInt(c.LLVMInt64Type(), 0, 0) };
    runtime.project(builder, 1).?.set(builder, false);
    const preserved = c.LLVMBuildLoad2(builder, c.LLVMInt1Type(), first.flag_ref, "sibling.cleanup.preserved");
    try signature.returnValue(builder, function, preserved);
    var message: [*c]u8 = null;
    defer if (message != null) c.LLVMDisposeMessage(message);
    const invalid = c.LLVMVerifyModule(module, c.LLVMReturnStatusAction, &message);
    if (invalid != 0) std.debug.print("{s}\n", .{message});
    try std.testing.expectEqual(@as(c_int, 0), invalid);
}
