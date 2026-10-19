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
    const origin = c.LLVMGetInsertBlock(builder);
    const function = c.LLVMGetBasicBlockParent(origin);
    const present = c.LLVMAppendBasicBlock(function, "reference.present");
    const done = c.LLVMAppendBasicBlock(function, "reference.loaded");
    _ = c.LLVMBuildCondBr(builder, c.LLVMBuildIsNull(builder, storage, "reference.absent"), done, present);
    c.LLVMPositionBuilderAtEnd(builder, present);
    const value = c.LLVMBuildLoad2(builder, storageViewType(), storage, "reference.view");
    _ = c.LLVMBuildBr(builder, done);
    c.LLVMPositionBuilderAtEnd(builder, done);
    const result = c.LLVMBuildPhi(builder, storageViewType(), "reference.loaded.view");
    var values = [_]c.LLVMValueRef{ c.LLVMConstNull(storageViewType()), value };
    var blocks = [_]c.LLVMBasicBlockRef{ origin, present };
    c.LLVMAddIncoming(result, &values, &blocks, values.len);
    return result;
}

pub fn storeOptional(builder: c.LLVMBuilderRef, storage: c.LLVMValueRef, value: ?c.LLVMValueRef) void {
    const function = c.LLVMGetBasicBlockParent(c.LLVMGetInsertBlock(builder));
    const present = c.LLVMAppendBasicBlock(function, "reference.writable");
    const done = c.LLVMAppendBasicBlock(function, "reference.stored");
    _ = c.LLVMBuildCondBr(builder, c.LLVMBuildIsNull(builder, storage, "reference.absent"), done, present);
    c.LLVMPositionBuilderAtEnd(builder, present);
    _ = c.LLVMBuildStore(builder, value orelse c.LLVMConstNull(storageViewType()), storage);
    _ = c.LLVMBuildBr(builder, done);
    c.LLVMPositionBuilderAtEnd(builder, done);
}

pub fn valueType(layout: *references.Layout, allocator: std.mem.Allocator, graph: *const g.GlobalSemanticGraph, ty: g.GlobalTypeId) !?c.LLVMTypeRef {
    const count = try layout.count(allocator, graph, ty);
    if (count == 0) return null;
    return c.LLVMArrayType2(storageViewType(), count);
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
    if (try references.Layout.shape(graph, slice.ty) == .reference)
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

test "native reference evidence projects distinct sibling ranges through the private ABI" {
    const a = std.testing.allocator;
    var graph: g.GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    const source = @import("../../4_semantics/primitives/schema.zig").SourceRef{ .file_index = 0, .offset = 0 };
    try graph.types.appendSlice(a, &.{
        .{ .structural = .{ .fields = .{ .start = 0, .len = 0 } } },
        .{ .pointer = .{ .child = @enumFromInt(0), .mutability = .read_write } },
        .{ .structural = .{ .fields = .{ .start = 0, .len = 2 } } },
    });
    for (0..2) |_| try graph.fields.append(a, .{ .name = .{ .start = 0, .len = 0 }, .ty = @enumFromInt(1), .source = source });
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
    for (0..2) |index| {
        const projection: references.Projection = .{ .field = @intCast(index) };
        const input = (try projectStorage(builder, &layout, a, &graph, @enumFromInt(2), input_storage, projection)).?;
        const output = (try projectStorage(builder, &layout, a, &graph, @enumFromInt(2), output_storage, projection)).?;
        const value = loadOptional(builder, input);
        const forwarded = try storageView(builder, .{ .cleanup = try cleanupPointer(builder, value), .references = try referencesPointer(builder, value), .owner = try runtimeOwner(builder, value) });
        storeOptional(builder, output, forwarded);
    }
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
