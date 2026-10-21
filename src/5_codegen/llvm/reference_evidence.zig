const std = @import("std");
const c = @import("llvm.zig").c;
const g = @import("../../4_semantics/global/graph.zig");
const references = @import("../reference_layout.zig");

// Reference evidence separates cleanup state from reference-valued leaves.
// Cleanup includes the owner and logical projection so field writes can update
// ancestor initialization without recovering identity from value addresses.
// Null describes absent state, never invented permission.
// This companion is private metadata; the language reference remains a pointer.
pub fn storageViewType() c.LLVMTypeRef {
    const pointer = c.LLVMPointerType(c.LLVMInt8Type(), 0);
    var fields = [_]c.LLVMTypeRef{ pointer, pointer, pointer, pointer, c.LLVMInt64Type() };
    return c.LLVMStructType(&fields, fields.len, 0);
}

/// Construct the private view without turning missing state into permission.
pub const Storage = struct {
    cleanup: ?c.LLVMValueRef = null,
    references: ?c.LLVMValueRef = null,
    owner: ?@import("cleanup_state.zig").RuntimeOwner = null,
};

pub fn storageView(builder: c.LLVMBuilderRef, storage: Storage) !c.LLVMValueRef {
    var result = c.LLVMConstNull(storageViewType());
    for ([_]?c.LLVMValueRef{ storage.cleanup, storage.references }, 0..) |pointer, index| if (pointer) |value| {
        if (value == null) continue;
        if (c.LLVMGetTypeKind(c.LLVMTypeOf(value)) != c.LLVMPointerTypeKind) return error.InvalidReferenceEvidenceStorage;
        result = c.LLVMBuildInsertValue(builder, result, value, @intCast(index), "reference.storage.view");
    };
    if (storage.owner) |owner| {
        result = c.LLVMBuildInsertValue(builder, result, owner.flags, 2, "reference.owner.flags");
        result = c.LLVMBuildInsertValue(builder, result, owner.refresh, 3, "reference.owner.refresh");
        result = c.LLVMBuildInsertValue(builder, result, owner.offset, 4, "reference.owner.offset");
    }
    return result;
}

pub fn runtimeOwner(builder: c.LLVMBuilderRef, view: c.LLVMValueRef) !@import("cleanup_state.zig").RuntimeOwner {
    if (c.LLVMTypeOf(view) != storageViewType()) return error.InvalidReferenceEvidenceStorage;
    return .{
        .flags = c.LLVMBuildExtractValue(builder, view, 2, "reference.owner.flags"),
        .refresh = c.LLVMBuildExtractValue(builder, view, 3, "reference.owner.refresh"),
        .offset = c.LLVMBuildExtractValue(builder, view, 4, "reference.owner.offset"),
    };
}

pub fn cleanupPointer(builder: c.LLVMBuilderRef, view: c.LLVMValueRef) !c.LLVMValueRef {
    if (c.LLVMTypeOf(view) != storageViewType()) return error.InvalidReferenceEvidenceStorage;
    return c.LLVMBuildExtractValue(builder, view, 0, "reference.cleanup");
}

// An absent sidecar is legal at boundaries that do not transport evidence.
// Never dereference it speculatively: LLVM select does not guard a load/store.
pub fn referencesPointer(builder: c.LLVMBuilderRef, view: c.LLVMValueRef) !c.LLVMValueRef {
    if (c.LLVMTypeOf(view) != storageViewType()) return error.InvalidReferenceEvidenceStorage;
    return c.LLVMBuildExtractValue(builder, view, 1, "reference.leaves");
}

pub fn loadOptional(builder: c.LLVMBuilderRef, storage: c.LLVMValueRef) c.LLVMValueRef {
    return loadOptionalValue(builder, storage, storageViewType());
}

// Aggregate companions use the same guarded access as a single reference.
// The descriptor determines the SSA type; absent storage yields empty evidence.
pub fn loadOptionalValue(builder: c.LLVMBuilderRef, storage: c.LLVMValueRef, ty: c.LLVMTypeRef) c.LLVMValueRef {
    const origin = c.LLVMGetInsertBlock(builder);
    const function = c.LLVMGetBasicBlockParent(origin);
    const present = c.LLVMAppendBasicBlock(function, "reference.present");
    const done = c.LLVMAppendBasicBlock(function, "reference.loaded");
    _ = c.LLVMBuildCondBr(builder, c.LLVMBuildIsNull(builder, storage, "reference.absent"), done, present);
    c.LLVMPositionBuilderAtEnd(builder, present);
    const value = c.LLVMBuildLoad2(builder, ty, storage, "reference.view");
    _ = c.LLVMBuildBr(builder, done);
    c.LLVMPositionBuilderAtEnd(builder, done);
    const result = c.LLVMBuildPhi(builder, ty, "reference.loaded.view");
    var values = [_]c.LLVMValueRef{ c.LLVMConstNull(ty), value };
    var blocks = [_]c.LLVMBasicBlockRef{ origin, present };
    c.LLVMAddIncoming(result, &values, &blocks, values.len);
    return result;
}

pub fn storeOptional(builder: c.LLVMBuilderRef, storage: c.LLVMValueRef, value: ?c.LLVMValueRef) void {
    storeOptionalValue(builder, storage, value orelse c.LLVMConstNull(storageViewType()));
}

pub fn storeOptionalValue(builder: c.LLVMBuilderRef, storage: c.LLVMValueRef, value: c.LLVMValueRef) void {
    const function = c.LLVMGetBasicBlockParent(c.LLVMGetInsertBlock(builder));
    const present = c.LLVMAppendBasicBlock(function, "reference.writable");
    const done = c.LLVMAppendBasicBlock(function, "reference.stored");
    _ = c.LLVMBuildCondBr(builder, c.LLVMBuildIsNull(builder, storage, "reference.absent"), done, present);
    c.LLVMPositionBuilderAtEnd(builder, present);
    _ = c.LLVMBuildStore(builder, value, storage);
    _ = c.LLVMBuildBr(builder, done);
    c.LLVMPositionBuilderAtEnd(builder, done);
}

pub fn valueType(layout: *references.Layout, allocator: std.mem.Allocator, graph: *const g.GlobalSemanticGraph, ty: g.GlobalTypeId) !?c.LLVMTypeRef {
    const count = try layout.count(allocator, graph, ty);
    if (count == 0) return null;
    return c.LLVMArrayType2(storageViewType(), count);
}

// Project a referent's companion without reading its fields. Null state stays
// absent even for a nonzero offset; it cannot become a fabricated flag address.
pub fn projectView(builder: c.LLVMBuilderRef, allocator: std.mem.Allocator, graph: *const g.GlobalSemanticGraph, layout: *references.Layout, counts: *@import("../cleanup_layout.zig").Counts, ty: g.GlobalTypeId, view: c.LLVMValueRef, projection: references.Projection) !c.LLVMValueRef {
    _ = try counts.count(allocator, graph, ty);
    const slice = try layout.project(allocator, graph, ty, projection);
    const index: u32 = switch (projection) {
        .field => |field| field,
        .variant => |variant| @intFromEnum(variant) - (@import("../../4_semantics/global/types.zig").variants(graph, ty) orelse return error.InvalidReferenceEvidenceStorage).start,
        .element => return error.InvalidReferenceEvidenceStorage,
    };
    const description = counts.description(ty);
    if (index >= description.children.len) return error.InvalidReferenceEvidenceStorage;
    const child = description.children[index] orelse return error.InvalidReferenceEvidenceStorage;
    const cleanup = try cleanupPointer(builder, view);
    const leaves = try referencesPointer(builder, view);
    var owner = try runtimeOwner(builder, view);
    owner.offset = c.LLVMBuildAdd(builder, owner.offset, c.LLVMConstInt(c.LLVMInt64Type(), child.offset, 0), "reference.owner.projected.offset");
    return storageView(builder, .{
        .cleanup = nullableOffset(builder, cleanup, c.LLVMInt1Type(), child.offset),
        .references = if (slice.count == 0) null else nullableOffset(builder, leaves, storageViewType(), slice.offset),
        .owner = owner,
    });
}

fn nullableOffset(builder: c.LLVMBuilderRef, pointer: c.LLVMValueRef, element: c.LLVMTypeRef, offset: usize) c.LLVMValueRef {
    return nullableOffsetValue(builder, pointer, element, c.LLVMConstInt(c.LLVMInt64Type(), offset, 0));
}

fn nullableOffsetValue(builder: c.LLVMBuilderRef, pointer: c.LLVMValueRef, element: c.LLVMTypeRef, offset: c.LLVMValueRef) c.LLVMValueRef {
    var indices = [_]c.LLVMValueRef{offset};
    const projected = c.LLVMBuildGEP2(builder, element, pointer, &indices, 1, "reference.storage.projection");
    return c.LLVMBuildSelect(builder, c.LLVMBuildIsNull(builder, pointer, "reference.storage.absent"), c.LLVMConstNull(c.LLVMTypeOf(pointer)), projected, "reference.storage.selected");
}

// Value evidence is a flat immutable array. Packing and projection use the
// same semantic slices as addressable storage, without reading value memory.
pub fn insertValue(builder: c.LLVMBuilderRef, aggregate: c.LLVMValueRef, child: c.LLVMValueRef, offset: usize) !c.LLVMValueRef {
    const aggregate_type = c.LLVMTypeOf(aggregate);
    const child_type = c.LLVMTypeOf(child);
    if (c.LLVMGetTypeKind(aggregate_type) != c.LLVMArrayTypeKind) return error.InvalidReferenceEvidenceStorage;
    if (c.LLVMGetElementType(aggregate_type) != storageViewType()) return error.InvalidReferenceEvidenceStorage;
    const single = child_type == storageViewType();
    if (!single and c.LLVMGetTypeKind(child_type) != c.LLVMArrayTypeKind) return error.InvalidReferenceEvidenceStorage;
    if (!single and c.LLVMGetElementType(child_type) != storageViewType()) return error.InvalidReferenceEvidenceStorage;
    const count = if (single) 1 else c.LLVMGetArrayLength2(child_type);
    if (offset > c.LLVMGetArrayLength2(aggregate_type) or count > c.LLVMGetArrayLength2(aggregate_type) - offset)
        return error.InvalidReferenceEvidenceStorage;
    var result = aggregate;
    for (0..count) |index| {
        const value = if (single) child else c.LLVMBuildExtractValue(builder, child, @intCast(index), "reference.leaf");
        result = c.LLVMBuildInsertValue(builder, result, value, @intCast(offset + index), "reference.pack");
    }
    return result;
}

pub fn projectValue(builder: c.LLVMBuilderRef, layout: *references.Layout, allocator: std.mem.Allocator, graph: *const g.GlobalSemanticGraph, ty: g.GlobalTypeId, aggregate: c.LLVMValueRef, projection: references.Projection) !?c.LLVMValueRef {
    const slice = try layout.project(allocator, graph, ty, projection);
    if (slice.count == 0) return null;
    const expected = (try valueType(layout, allocator, graph, ty)).?;
    if (c.LLVMTypeOf(aggregate) != expected) return error.InvalidReferenceEvidenceStorage;
    const shape = try references.Layout.shape(graph, slice.ty);
    if (shape == .reference or shape == .virtual_reference)
        return c.LLVMBuildExtractValue(builder, aggregate, @intCast(slice.offset), "reference.project");
    var result = c.LLVMConstNull((try valueType(layout, allocator, graph, slice.ty)).?);
    for (0..slice.count) |index| {
        const value = c.LLVMBuildExtractValue(builder, aggregate, @intCast(slice.offset + index), "reference.leaf");
        result = c.LLVMBuildInsertValue(builder, result, value, @intCast(index), "reference.project");
    }
    return result;
}

// Project the sidecar by semantic identity, never by the physical value's
// address. The same projection is usable for caller storage and callee inputs.
// Bounds and active-payload checks belong to the checked value access; this
// helper only projects evidence and never reads a choice's inactive payload.
pub fn projectStorage(builder: c.LLVMBuilderRef, layout: *references.Layout, allocator: std.mem.Allocator, graph: *const g.GlobalSemanticGraph, ty: g.GlobalTypeId, storage: c.LLVMValueRef, projection: references.Projection) !?c.LLVMValueRef {
    const slice = try layout.project(allocator, graph, ty, projection);
    if (slice.count == 0) return null;
    if (c.LLVMGetTypeKind(c.LLVMTypeOf(storage)) != c.LLVMPointerTypeKind) return error.InvalidReferenceEvidenceStorage;
    const whole = (try valueType(layout, allocator, graph, ty)) orelse return error.InvalidReferenceEvidenceStorage;
    var indices = [_]c.LLVMValueRef{
        c.LLVMConstInt(c.LLVMInt64Type(), 0, 0),
        c.LLVMConstInt(c.LLVMInt64Type(), slice.offset, 0),
    };
    return c.LLVMBuildGEP2(builder, whole, storage, &indices, indices.len, "reference.evidence.projection");
}

// Runtime views may deliberately have no companion. Keep that absence when
// projecting; a nonzero logical offset must never manufacture a pointer.
pub fn projectOptionalStorage(builder: c.LLVMBuilderRef, layout: *references.Layout, allocator: std.mem.Allocator, graph: *const g.GlobalSemanticGraph, ty: g.GlobalTypeId, storage: c.LLVMValueRef, projection: references.Projection) !?c.LLVMValueRef {
    const slice = try layout.project(allocator, graph, ty, projection);
    if (slice.count == 0) return null;
    return nullableOffset(builder, storage, storageViewType(), slice.offset);
}

// The caller has already checked this index for the data access. Reuse its
// SSA value; this projection introduces neither another evaluation nor flags
// for indexed cleanup, which has a separate frontend representation obligation.
pub fn elementStorage(builder: c.LLVMBuilderRef, layout: *references.Layout, allocator: std.mem.Allocator, graph: *const g.GlobalSemanticGraph, ty: g.GlobalTypeId, storage: c.LLVMValueRef, index: c.LLVMValueRef) !?c.LLVMValueRef {
    const element = @import("../../4_semantics/global/types.zig").arrayElement(graph, ty) orelse return error.InvalidReferenceEvidenceStorage;
    _ = try layout.count(allocator, graph, ty);
    const stride = try layout.count(allocator, graph, element);
    if (stride == 0) return null;
    if (c.LLVMGetTypeKind(c.LLVMTypeOf(index)) != c.LLVMIntegerTypeKind or c.LLVMGetIntTypeWidth(c.LLVMTypeOf(index)) > 64) return error.InvalidReferenceEvidenceStorage;
    const widened = c.LLVMBuildIntCast2(builder, index, c.LLVMInt64Type(), 0, "reference.element.index");
    const offset = c.LLVMBuildMul(builder, widened, c.LLVMConstInt(c.LLVMInt64Type(), stride, 0), "reference.element.offset");
    return nullableOffsetValue(builder, storage, storageViewType(), offset);
}

test "native reference evidence projects distinct sibling ranges through the private ABI" {
    const a = std.testing.allocator;
    var graph: g.GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    const source = @import("../../4_semantics/primitives/schema.zig").SourceRef{ .file_index = 0, .offset = 0 };
    try graph.types.appendSlice(a, &.{
        .{ .structural = .{ .fields = .{ .start = 0, .len = 0 } } },
        .{ .pointer = .{ .child = @enumFromInt(0), .mutability = .read_write } },
        .{ .structural = .{ .fields = .{ .start = 0, .len = 2 } } },
        .{ .structural_choice = .{ .variants = .{ .start = 1, .len = 3 } } },
    });
    for (0..2) |_| try graph.fields.append(a, .{ .name = .{ .start = 0, .len = 0 }, .ty = @enumFromInt(1), .source = source });
    for ([_]?g.GlobalTypeId{ null, @enumFromInt(1), null, @enumFromInt(2) }, 0..) |payload, index|
        try graph.variants.append(a, .{ .name = .{ .start = 0, .len = 0 }, .source = source, .value = @intCast(index), .payload_type = payload });
    var layout: references.Layout = .{};
    defer layout.deinit(a);
    try std.testing.expect(try valueType(&layout, a, &graph, @enumFromInt(0)) == null);
    const sidecar = (try valueType(&layout, a, &graph, @enumFromInt(2))).?;
    try std.testing.expectEqual(@as(c_ulonglong, 2), c.LLVMGetArrayLength2(sidecar));
    const module = c.LLVMModuleCreateWithName("reference_evidence_test");
    defer c.LLVMDisposeModule(module);
    const builder = c.LLVMCreateBuilder();
    defer c.LLVMDisposeBuilder(builder);
    const signature = @import("argi_abi.zig").Signature.initWithEvidence(
        c.LLVMStructType(null, 0, 0),
        c.LLVMStructType(null, 0, 0),
        false,
        .{ .input = sidecar, .output = sidecar },
    );
    const function = c.LLVMAddFunction(module, "forward_evidence", signature.function_type);
    c.LLVMPositionBuilderAtEnd(builder, c.LLVMAppendBasicBlock(function, "entry"));
    const input_storage = c.LLVMBuildAlloca(builder, sidecar, "input.evidence");
    _ = c.LLVMBuildStore(builder, signature.inputEvidence(function).?, input_storage);
    const output_storage = signature.outputEvidenceStorage(function).?;
    var cleanup_counts: @import("../cleanup_layout.zig").Counts = .{};
    defer cleanup_counts.deinit(a);
    const choice_sidecar = (try valueType(&layout, a, &graph, @enumFromInt(3))).?;
    const choice_storage = c.LLVMBuildAlloca(builder, choice_sidecar, "choice.evidence");
    _ = c.LLVMBuildStore(builder, c.LLVMConstNull(choice_sidecar), choice_storage);
    const choice_root = try storageView(builder, .{ .references = choice_storage });
    const projected_choice = try projectView(builder, a, &graph, &layout, &cleanup_counts, @enumFromInt(3), choice_root, .{ .variant = @enumFromInt(3) });
    // Inspect the emitted addition rather than assuming LLVM folds extracts
    // from a dynamically assembled view into constants.
    try std.testing.expectEqual(@as(c_uint, c.LLVMInsertValue), c.LLVMGetInstructionOpcode(projected_choice));
    const offset = c.LLVMGetOperand(projected_choice, 1);
    try std.testing.expectEqual(@as(c_uint, c.LLVMAdd), c.LLVMGetInstructionOpcode(offset));
    const increment = c.LLVMGetOperand(offset, 1);
    try std.testing.expect(c.LLVMIsAConstantInt(increment) != null);
    try std.testing.expectEqual(@as(u64, 3), c.LLVMConstIntGetZExtValue(increment));
    try std.testing.expectError(error.InvalidReferenceProjection, projectView(builder, a, &graph, &layout, &cleanup_counts, @enumFromInt(3), choice_root, .{ .variant = @enumFromInt(2) }));
    const root_view = try storageView(builder, .{ .references = input_storage });
    const child_view = try projectView(builder, a, &graph, &layout, &cleanup_counts, @enumFromInt(2), root_view, .{ .field = 1 });
    const absent_projection = nullableOffset(builder, c.LLVMConstNull(c.LLVMPointerType(c.LLVMInt1Type(), 0)), c.LLVMInt1Type(), 2);
    try std.testing.expect(c.LLVMIsNull(absent_projection) != 0 or c.LLVMGetInstructionOpcode(absent_projection) == c.LLVMSelect);
    const absent_leaves = c.LLVMConstNull(c.LLVMPointerType(storageViewType(), 0));
    const absent_child = (try projectOptionalStorage(builder, &layout, a, &graph, @enumFromInt(2), absent_leaves, .{ .field = 1 })).?;
    try std.testing.expect(c.LLVMIsNull(absent_child) != 0);
    const child_leaves = try referencesPointer(builder, child_view);
    try std.testing.expect(child_leaves != input_storage);
    for (0..2) |index| {
        const projection: references.Projection = .{ .field = @intCast(index) };
        const input = (try projectStorage(builder, &layout, a, &graph, @enumFromInt(2), input_storage, projection)).?;
        const output = (try projectStorage(builder, &layout, a, &graph, @enumFromInt(2), output_storage, projection)).?;
        const value = loadOptional(builder, input);
        const forwarded = try storageView(builder, .{ .cleanup = try cleanupPointer(builder, value), .references = try referencesPointer(builder, value), .owner = try runtimeOwner(builder, value) });
        storeOptional(builder, output, forwarded);
    }
    const aggregate_copy = loadOptionalValue(builder, input_storage, sidecar);
    storeOptionalValue(builder, output_storage, aggregate_copy);
    const absent_copy = loadOptionalValue(builder, c.LLVMConstNull(c.LLVMPointerType(sidecar, 0)), sidecar);
    const scratch = c.LLVMBuildAlloca(builder, sidecar, "absent.evidence");
    storeOptionalValue(builder, scratch, absent_copy);
    const output = c.LLVMBuildLoad2(builder, sidecar, output_storage, "returned.evidence");
    var reassembled = c.LLVMConstNull(sidecar);
    for (0..2) |index| {
        const leaf = (try projectValue(builder, &layout, a, &graph, @enumFromInt(2), output, .{ .field = @intCast(index) })).?;
        reassembled = try insertValue(builder, reassembled, leaf, index);
    }
    try std.testing.expectError(error.InvalidReferenceEvidenceStorage, insertValue(builder, reassembled, reassembled, 1));
    try signature.returnWithEvidence(builder, function, signature.input(function), reassembled);
    var message: [*c]u8 = null;
    defer if (message != null) c.LLVMDisposeMessage(message);
    const invalid = c.LLVMVerifyModule(module, c.LLVMReturnStatusAction, &message);
    if (invalid != 0) std.debug.print("{s}\n", .{message});
    try std.testing.expectEqual(@as(c_int, 0), invalid);
}
