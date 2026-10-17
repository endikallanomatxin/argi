const std = @import("std");
const c = @import("llvm.zig").c;
const g = @import("../../4_semantics/global/graph.zig");
const references = @import("../reference_layout.zig");

// Each reference carries access to two independent parts of its referent's
// storage: its cleanup flags, and the evidence of reference-valued leaves
// stored inside it. Null describes absent state, never invented permission.
// This companion is private metadata; the language reference remains a pointer.
pub fn storageViewType() c.LLVMTypeRef {
    const pointer = c.LLVMPointerType(c.LLVMInt8Type(), 0);
    var fields = [_]c.LLVMTypeRef{ pointer, pointer };
    return c.LLVMStructType(&fields, fields.len, 0);
}

pub fn valueType(layout: *references.Layout, allocator: std.mem.Allocator, graph: *const g.GlobalSemanticGraph, ty: g.GlobalTypeId) !?c.LLVMTypeRef {
    const count = try layout.count(allocator, graph, ty);
    if (count == 0) return null;
    return c.LLVMArrayType2(storageViewType(), count);
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
        const value = c.LLVMBuildLoad2(builder, storageViewType(), input, "reference.storage.view");
        _ = c.LLVMBuildStore(builder, value, output);
    }
    const output = c.LLVMBuildLoad2(builder, sidecar, output_storage, "returned.evidence");
    try signature.returnWithEvidence(builder, function, signature.input(function), output);
    var message: [*c]u8 = null;
    defer if (message != null) c.LLVMDisposeMessage(message);
    const invalid = c.LLVMVerifyModule(module, c.LLVMReturnStatusAction, &message);
    if (invalid != 0) std.debug.print("{s}\n", .{message});
    try std.testing.expectEqual(@as(c_int, 0), invalid);
}
