const std = @import("std");
const c = @import("llvm.zig").c;
const g = @import("../../4_semantics/global/graph.zig");
const layout = @import("../cleanup_layout.zig");

// One helper per cleanup shape updates ancestor flags for a runtime projection.
// Types and offsets select logical flag ranges; value addresses play no role.
pub const RefreshFunctions = struct {
    functions: std.AutoHashMapUnmanaged(g.GlobalTypeId, c.LLVMValueRef) = .empty,
    batches: std.AutoHashMapUnmanaged(g.GlobalTypeId, c.LLVMValueRef) = .empty,

    pub fn deinit(self: *RefreshFunctions, allocator: std.mem.Allocator) void {
        self.functions.deinit(allocator);
        self.batches.deinit(allocator);
    }

    pub fn functionType() c.LLVMTypeRef {
        var parameters = [_]c.LLVMTypeRef{ c.LLVMPointerType(c.LLVMInt1Type(), 0), c.LLVMInt64Type() };
        return c.LLVMFunctionType(c.LLVMVoidType(), &parameters, parameters.len, 0);
    }

    // Flat acquired batches have independent owners, without an enclosing
    // array flag. Refresh only the selected element and its own descendants.
    pub fn getBatch(self: *RefreshFunctions, allocator: std.mem.Allocator, counts: *const layout.Counts, module: c.LLVMModuleRef, ty: g.GlobalTypeId) error{OutOfMemory}!c.LLVMValueRef {
        if (self.batches.get(ty)) |function| return function;
        const nested = try self.get(allocator, counts, module, ty);
        const function = c.LLVMAddFunction(module, "cleanup.refresh.batch", functionType());
        c.LLVMSetLinkage(function, c.LLVMInternalLinkage);
        try self.batches.put(allocator, ty, function);
        const builder = c.LLVMCreateBuilder();
        defer c.LLVMDisposeBuilder(builder);
        c.LLVMPositionBuilderAtEnd(builder, c.LLVMAppendBasicBlock(function, "entry"));
        const flags = c.LLVMGetParam(function, 0);
        const offset = c.LLVMGetParam(function, 1);
        const relative = c.LLVMBuildURem(builder, offset, c.LLVMConstInt(c.LLVMInt64Type(), counts.description(ty).count, 0), "cleanup.batch.relative");
        var indices = [_]c.LLVMValueRef{c.LLVMBuildSub(builder, offset, relative, "cleanup.batch.start")};
        var arguments = [_]c.LLVMValueRef{ c.LLVMBuildGEP2(builder, c.LLVMInt1Type(), flags, &indices, 1, "cleanup.batch.flags"), relative };
        _ = c.LLVMBuildCall2(builder, functionType(), nested, &arguments, arguments.len, "");
        _ = c.LLVMBuildRetVoid(builder);
        return function;
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
        if (description.repetition) |array| if (array.length != 0 and array.element.count > 1) {
            const stride = c.LLVMConstInt(c.LLVMInt64Type(), array.element.count, 0);
            const relative = c.LLVMBuildURem(builder, c.LLVMBuildSub(builder, offset, c.LLVMConstInt(c.LLVMInt64Type(), 1, 0), "cleanup.array.relative"), stride, "cleanup.element.offset");
            const start = c.LLVMBuildSub(builder, offset, relative, "cleanup.element.start");
            var indices = [_]c.LLVMValueRef{start};
            var arguments = [_]c.LLVMValueRef{
                c.LLVMBuildInBoundsGEP2(builder, c.LLVMInt1Type(), flags, &indices, 1, "cleanup.element.flags"),
                relative,
            };
            _ = c.LLVMBuildCall2(builder, functionType(), try self.get(allocator, counts, module, array.ty), &arguments, arguments.len, "");
        };
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
        // An unavailable descendant immediately disproves whole-owner
        // completeness. Destruction loops must not rescan every sibling.
        const unavailable = c.LLVMAppendBasicBlock(function, "cleanup.incomplete");
        const initialized = c.LLVMAppendBasicBlock(function, "cleanup.check.parents");
        var selected_index = [_]c.LLVMValueRef{offset};
        const selected_flag = c.LLVMBuildInBoundsGEP2(builder, c.LLVMInt1Type(), flags, &selected_index, 1, "cleanup.changed.flag");
        _ = c.LLVMBuildCondBr(builder, c.LLVMBuildLoad2(builder, c.LLVMInt1Type(), selected_flag, "cleanup.changed.ready"), initialized, unavailable);
        c.LLVMPositionBuilderAtEnd(builder, unavailable);
        _ = c.LLVMBuildStore(builder, c.LLVMConstInt(c.LLVMInt1Type(), 0, 0), flags);
        _ = c.LLVMBuildBr(builder, done);
        c.LLVMPositionBuilderAtEnd(builder, initialized);
        promoteAggregate(builder, flags, description, 0);
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

    pub fn presence(self: View, builder: c.LLVMBuilderRef) c.LLVMValueRef {
        if (!self.layouts.description(self.ty).is_choice) return self.flag_ref;
        var offset = [_]c.LLVMValueRef{c.LLVMConstInt(c.LLVMInt64Type(), 1, 0)};
        return c.LLVMBuildInBoundsGEP2(builder, c.LLVMInt1Type(), self.flag_ref, &offset, 1, "cleanup.discriminant.flag");
    }

    pub fn count(self: View) usize {
        return self.layouts.description(self.ty).count;
    }

    pub fn project(self: View, builder: c.LLVMBuilderRef, index: usize) ?View {
        const description = self.layouts.description(self.ty);
        const child = if (description.repetition != null)
            description.project(.{ .element = index }) orelse return null
        else if (index < description.children.len)
            description.children[index] orelse return null
        else
            return null;
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

    // The data access has already checked the element index. This selects the
    // same logical flag range without evaluating the index or value again.
    pub fn projectElement(self: View, builder: c.LLVMBuilderRef, index: c.LLVMValueRef, refresh: c.LLVMValueRef) !View {
        const array = self.layouts.description(self.ty).repetition orelse return error.InvalidCleanupEvidence;
        if (c.LLVMGetTypeKind(c.LLVMTypeOf(index)) != c.LLVMIntegerTypeKind or c.LLVMGetIntTypeWidth(c.LLVMTypeOf(index)) > 64) return error.InvalidCleanupEvidence;
        const widened = c.LLVMBuildIntCast2(builder, index, c.LLVMInt64Type(), 0, "cleanup.project.index");
        const offset = c.LLVMBuildAdd(builder, c.LLVMConstInt(c.LLVMInt64Type(), 1, 0), c.LLVMBuildMul(builder, widened, c.LLVMConstInt(c.LLVMInt64Type(), array.element.count, 0), "cleanup.project.stride"), "cleanup.project.offset");
        const owner = self.runtime_owner orelse RuntimeOwner{
            .flags = self.owner_flags orelse self.flag_ref,
            .refresh = refresh,
            .offset = c.LLVMConstInt(c.LLVMInt64Type(), self.offset, 0),
        };
        var indices = [_]c.LLVMValueRef{offset};
        return .{
            .flag_ref = c.LLVMBuildInBoundsGEP2(builder, c.LLVMInt1Type(), self.flag_ref, &indices, 1, "cleanup.project.flags"),
            .layouts = self.layouts,
            .ty = array.ty,
            .runtime_owner = .{ .flags = owner.flags, .refresh = owner.refresh, .offset = c.LLVMBuildAdd(builder, owner.offset, offset, "cleanup.project.owner.offset") },
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
        } else if (self.offset != 0) self.refreshAncestors(builder, self.owner_type.?, 0);
    }

    fn refreshAncestors(self: View, builder: c.LLVMBuilderRef, ty: g.GlobalTypeId, base: usize) void {
        if (base == self.offset) return;
        const description = self.layouts.description(ty);
        if (description.repetition) |array| {
            const index = (self.offset - base - 1) / array.element.count;
            if (index < array.length) self.refreshAncestors(builder, array.ty, base + 1 + index * array.element.count);
        }
        for (description.children) |maybe_child| if (maybe_child) |child| {
            const start = base + child.offset;
            if (self.offset >= start and self.offset < start + self.layouts.description(child.ty).count) {
                self.refreshAncestors(builder, child.ty, start);
                break;
            }
        };
        promoteAggregate(builder, self.owner_flags, description, base);
    }
};

fn promoteAggregate(builder: c.LLVMBuilderRef, flags: c.LLVMValueRef, description: layout.Counts.Description, base: usize) void {
    if (description.repetition) |array| {
        if (array.length == 0) return;
        const entry = c.LLVMGetInsertBlock(builder);
        const function = c.LLVMGetBasicBlockParent(entry);
        const loop = c.LLVMAppendBasicBlock(function, "cleanup.array.check");
        const done = c.LLVMAppendBasicBlock(function, "cleanup.array.checked");
        _ = c.LLVMBuildBr(builder, loop);
        c.LLVMPositionBuilderAtEnd(builder, loop);
        const index = c.LLVMBuildPhi(builder, c.LLVMInt64Type(), "cleanup.array.index");
        const ready = c.LLVMBuildPhi(builder, c.LLVMInt1Type(), "cleanup.array.ready");
        const zero = c.LLVMConstInt(c.LLVMInt64Type(), 0, 0);
        const yes = c.LLVMConstInt(c.LLVMInt1Type(), 1, 0);
        var start_index = [_]c.LLVMValueRef{zero};
        var start_ready = [_]c.LLVMValueRef{yes};
        var start_block = [_]c.LLVMBasicBlockRef{entry};
        c.LLVMAddIncoming(index, &start_index, &start_block, 1);
        c.LLVMAddIncoming(ready, &start_ready, &start_block, 1);
        const offset = c.LLVMBuildAdd(builder, c.LLVMConstInt(c.LLVMInt64Type(), base + 1, 0), c.LLVMBuildMul(builder, index, c.LLVMConstInt(c.LLVMInt64Type(), array.element.count, 0), "cleanup.array.stride"), "cleanup.array.position");
        var indices = [_]c.LLVMValueRef{offset};
        const pointer = c.LLVMBuildInBoundsGEP2(builder, c.LLVMInt1Type(), flags, &indices, 1, "cleanup.array.flag");
        const complete = c.LLVMBuildAnd(builder, ready, c.LLVMBuildLoad2(builder, c.LLVMInt1Type(), pointer, "cleanup.element.ready"), "cleanup.array.complete");
        const next = c.LLVMBuildAdd(builder, index, c.LLVMConstInt(c.LLVMInt64Type(), 1, 0), "cleanup.array.next");
        var next_index = [_]c.LLVMValueRef{next};
        var next_ready = [_]c.LLVMValueRef{complete};
        var loop_block = [_]c.LLVMBasicBlockRef{loop};
        c.LLVMAddIncoming(index, &next_index, &loop_block, 1);
        c.LLVMAddIncoming(ready, &next_ready, &loop_block, 1);
        _ = c.LLVMBuildCondBr(builder, c.LLVMBuildICmp(builder, c.LLVMIntULT, next, c.LLVMConstInt(c.LLVMInt64Type(), array.length, 0), "cleanup.array.more"), loop, done);
        c.LLVMPositionBuilderAtEnd(builder, done);
        var root_index = [_]c.LLVMValueRef{c.LLVMConstInt(c.LLVMInt64Type(), base, 0)};
        _ = c.LLVMBuildStore(builder, complete, c.LLVMBuildInBoundsGEP2(builder, c.LLVMInt1Type(), flags, &root_index, 1, "cleanup.array.owner"));
        return;
    }
    if (!description.is_record and !description.is_choice) return;
    if (description.is_record and description.children.len == 0) return;
    var complete = c.LLVMConstInt(c.LLVMInt1Type(), 1, 0);
    if (description.is_choice) {
        var tag_offset = [_]c.LLVMValueRef{c.LLVMConstInt(c.LLVMInt64Type(), base + 1, 0)};
        const tag = c.LLVMBuildInBoundsGEP2(builder, c.LLVMInt1Type(), flags, &tag_offset, 1, "cleanup.discriminant.flag");
        complete = c.LLVMBuildLoad2(builder, c.LLVMInt1Type(), tag, "cleanup.discriminant.ready");
    }
    for (description.children) |maybe_child| {
        const child = maybe_child orelse if (description.is_choice) continue else return;
        var offset = [_]c.LLVMValueRef{c.LLVMConstInt(c.LLVMInt64Type(), base + child.offset, 0)};
        const pointer = c.LLVMBuildInBoundsGEP2(builder, c.LLVMInt1Type(), flags, &offset, 1, "cleanup.field.flag");
        const ready = c.LLVMBuildLoad2(builder, c.LLVMInt1Type(), pointer, "cleanup.field.ready");
        complete = c.LLVMBuildAnd(builder, complete, ready, "cleanup.record.ready");
    }
    var offset = [_]c.LLVMValueRef{c.LLVMConstInt(c.LLVMInt64Type(), base, 0)};
    const pointer = c.LLVMBuildInBoundsGEP2(builder, c.LLVMInt1Type(), flags, &offset, 1, "cleanup.owner.flag");
    // A consumed descendant makes its aggregate incomplete. Choices keep
    // their independent discriminant flag so structural fallback can still
    // select the live payload. Reinitialization restores whole-value cleanup
    // only after all represented descendants are complete again.
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

test "native repeated cleanup refresh emits bounded loops and distinct element flags" {
    const a = std.testing.allocator;
    var graph: g.GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    try graph.types.appendSlice(a, &.{
        .{ .builtin = .Int32 },
        .{ .array = .{ .element = @enumFromInt(0), .length = 1_000_000 } },
        .{ .array = .{ .element = @enumFromInt(1), .length = 2 } },
    });
    var counts: layout.Counts = .{};
    defer counts.deinit(a);
    const module = c.LLVMModuleCreateWithName("repeated_cleanup_test");
    defer c.LLVMDisposeModule(module);
    const builder = c.LLVMCreateBuilder();
    defer c.LLVMDisposeBuilder(builder);
    const function = c.LLVMAddFunction(module, "reset_element", RefreshFunctions.functionType());
    const entry = c.LLVMAppendBasicBlock(function, "entry");
    c.LLVMPositionBuilderAtEnd(builder, entry);
    const view = try View.fromPointer(a, &graph, &counts, @enumFromInt(2), c.LLVMGetParam(function, 0));
    try std.testing.expectEqual(@as(usize, 2_000_003), view.count());
    const first = view.project(builder, 0).?;
    const second = view.project(builder, 1).?;
    try std.testing.expectEqual(@as(usize, 1), first.offset);
    try std.testing.expectEqual(@as(usize, 1_000_002), second.offset);
    first.project(builder, 999_999).?.set(builder, false);
    var refresh: RefreshFunctions = .{};
    defer refresh.deinit(a);
    const helper = try refresh.get(a, &counts, module, @enumFromInt(2));
    const dynamic = try view.projectElement(builder, c.LLVMGetParam(function, 1), helper);
    try std.testing.expectEqual(@as(g.GlobalTypeId, @enumFromInt(1)), dynamic.ty);
    try std.testing.expect(dynamic.runtime_owner != null);
    dynamic.set(builder, true);
    _ = c.LLVMBuildRetVoid(builder);
    var instruction_count: usize = 0;
    var current = c.LLVMGetFirstFunction(module);
    while (current != null) : (current = c.LLVMGetNextFunction(current)) {
        var block = c.LLVMGetFirstBasicBlock(current);
        while (block != null) : (block = c.LLVMGetNextBasicBlock(block)) {
            var instruction = c.LLVMGetFirstInstruction(block);
            while (instruction != null) : (instruction = c.LLVMGetNextInstruction(instruction)) instruction_count += 1;
        }
    }
    try std.testing.expect(instruction_count < 200);
    var message: [*c]u8 = null;
    defer if (message != null) c.LLVMDisposeMessage(message);
    const invalid = c.LLVMVerifyModule(module, c.LLVMReturnStatusAction, &message);
    if (invalid != 0) std.debug.print("{s}\n", .{message});
    try std.testing.expectEqual(@as(c_int, 0), invalid);
}
