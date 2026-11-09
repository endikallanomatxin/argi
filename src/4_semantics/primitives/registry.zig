const std = @import("std");
const primitives = @import("schema.zig");
const syntax = @import("../../3_syntax/syntax_tree.zig");

/// Trusted declarations are identified only in the bundled core. Signature
/// text is compared without spacing and comments, so this table
/// describes the complete source-level interface, including generic type
/// parameters, argument names/modes and output shape. Runtime safety effects
/// are the Transfer below and are selected by the same primitive identity.
/// Metadata-only declarations set function flags without replacing body safety.
pub const Spec = struct {
    primitive: primitives.SafetyPrimitive = .none,
    flags: primitives.FunctionFlags = .{},
    path: []const u8,
    name: []const u8,
    signatures: []const []const u8,
    declaration: enum { body, extern_function } = .body,
    operating_systems: []const std.Target.Os.Tag = &.{},
};

pub const specs = [_]Spec{
    .{ .primitive = .execution_lend, .path = "core/memory/execution_access.rg", .name = "_execution_lend", .signatures = &.{"#(.t: Type)(.inputs: t) -> (.receipt: _ExecutionReceipt)"} },
    .{ .primitive = .execution_complete, .path = "core/memory/execution_access.rg", .name = "_execution_complete", .signatures = &.{"(.receipt: $&_ExecutionReceipt, .join: ?_ExecutionJoin = ..none) -> ()"} },
    .{ .primitive = .execution_input, .path = "core/memory/execution_access.rg", .name = "_execution_input", .signatures = &.{"#(.t: Type)(.invocation: _ExecutionInvocation, .anchor: &Any) -> (.reference: $&t)"} },
    .{ .primitive = .prepare_allocation_metadata, .path = "core/memory/heap_allocation/allocation_metadata.rg", .name = "_prepare_allocation_metadata", .signatures = &.{"#(.t: Type)(.allocation: &Allocation) -> (.state: UIntNative)"} },
    .{ .primitive = .allocation_metadata_layout, .path = "core/memory/heap_allocation/allocation_metadata.rg", .name = "_allocation_metadata_layout", .signatures = &.{"#(.t: Type)() -> (.layout: _AllocationMetadataLayout)"} },
    .{ .flags = .{ .is_source_location_id = true }, .path = "core/errors/source_location.rg", .name = "error_location_id", .signatures = &.{"() -> (.location: SourceLocationId)"} },
    .{ .flags = .{ .is_source_location_resolver = true }, .path = "core/errors/source_location.rg", .name = "source_location", .signatures = &.{"(.id: SourceLocationId) -> (.location: SourceLocation)"} },
    .{ .primitive = .float_math, .path = "core/numbers/math.rg", .name = "_float_math", .signatures = &.{"#(.t: Type: Float)(.operation: UInt32, .left: t, .right: t) -> (.result: t)"} },
    .{ .primitive = .establish_inherited_reference, .path = "core/memory/heap_allocation/RawPointer.rg", .name = "trusted_establish_inherited_reference", .signatures = &.{"#(.t: Type)(.raw: RawPointer#(.t: t), .root: &Any) -> (.reference: $&t)"} },
    .{ .primitive = .require_storage_capability, .path = "core/memory/heap_allocation/AcquiredStorage.rg", .name = "_require_storage_capability", .signatures = &.{"(.address: UIntNative) -> ()"} },
    .{ .primitive = .establish_inherited_storage, .path = "core/memory/heap_allocation/RawPointer.rg", .name = "trusted_establish_inherited_storage", .signatures = &.{"(.address: UIntNative, .root: &Any) -> (.raw: RawPointer#(.t: UInt8))"} },
    .{ .primitive = .reference_offset, .path = "core/memory/heap_allocation/RawPointer.rg", .name = "trusted_reference_offset", .signatures = &.{"#(.t: Type)(.base: &t, .elements: UIntNative) -> (.reference: &t)"} },
    .{ .primitive = .mutable_reference_offset, .path = "core/memory/heap_allocation/RawPointer.rg", .name = "trusted_mutable_reference_offset", .signatures = &.{"#(.t: Type)(.base: $&t, .elements: UIntNative) -> (.reference: $&t)"} },
    .{ .primitive = .reinterpret_reference, .path = "core/memory/heap_allocation/RawPointer.rg", .name = "trusted_reinterpret_reference", .signatures = &.{"#(.from: Type, .to: Type)(.base: &from) -> (.reference: &to)"} },
    .{ .primitive = .mutable_reinterpret_reference, .path = "core/memory/heap_allocation/RawPointer.rg", .name = "trusted_mutable_reinterpret_reference", .signatures = &.{"#(.from: Type, .to: Type)(.base: $&from) -> (.reference: $&to)"} },
    .{ .primitive = .read_reference, .path = "core/memory/heap_allocation/RawPointer.rg", .name = "read_reference", .signatures = &.{"#(.t: Type)(.base: $&t) -> (.reference: &t)"} },
    .{ .primitive = .establish_allocation, .path = "core/memory/heap_allocation/Allocation.rg", .name = "trusted_establish_allocation", .signatures = &.{"(.storage: UIntNative, .size: UIntNative, .alignment: UIntNative, .deallocator: Virtual#(Deallocator), .anchor: &Any = erase_reference#(.t: UInt8)(.base = &allocation_static_anchor).reference) -> (.allocation: Allocation)"} },
    .{ .primitive = .establish_allocation_slot, .path = "core/memory/heap_allocation/allocation_slots.rg", .name = "trusted_establish_allocation_slot", .signatures = &.{"#(.t: Type)(.allocation: &Allocation, .slot: RawPointer#(.t: t), .anchor: &Any, .index: ?UIntNative = ..none) -> (.reference: $&t)"} },
    .{ .primitive = .native_allocated_storage, .operating_systems = &.{ .linux, .macos }, .path = "core/platforms/posix/page_mapping.rg", .name = "_memory_map_anonymous", .signatures = &.{"(.length: UIntNative, .ffi: $&ForeignFunctionInterface) -> (.address: UIntNative)"} },
    .{ .primitive = .native_allocated_storage, .operating_systems = &.{.windows}, .path = "core/platforms/windows/page_mapping.rg", .name = "_memory_acquire_aligned", .signatures = &.{"(.length: UIntNative, .alignment: UIntNative) -> (.address: UIntNative)"}, .declaration = .extern_function },
    .{ .primitive = .acquisition_subaddress, .path = "core/memory/heap_allocation/Memory.rg", .name = "_trusted_acquisition_subaddress", .signatures = &.{"(.base: UIntNative, .address: UIntNative) -> (.result: UIntNative)"} },
    .{ .primitive = .relocate, .path = "core/memory/relocation.rg", .name = "relocate", .signatures = &.{"#(.t: Type)(.source: $&t, .destination: $&t) -> ()"} },
    .{ .primitive = .restrict_reference, .path = "core/memory/validity_dependency.rg", .name = "restrict_reference", .signatures = &.{"#(.t: Type)(.input: t, .on: &Any) -> (.reference: t)"} },
    .{ .primitive = .depend_on, .path = "core/memory/validity_dependency.rg", .name = "depend_on", .signatures = &.{"#(.t: Type)(.value: t, .on: &Any) -> (.result: t)"} },
    .{ .primitive = .trusted_opaque_move, .path = "core/memory/opaque_ownership.rg", .name = "trusted_opaque_move", .signatures = &.{"#(.t: Type)(.destination: $&t, .source: t) -> ()"} },
    .{ .primitive = .trusted_opaque_move_in, .path = "core/memory/opaque_ownership.rg", .name = "trusted_opaque_move_in", .signatures = &.{"#(.t: Type, .storage_type: Type)(.storage: $&storage_type, .destination: $&t, .source: t) -> ()"} },
    .{ .primitive = .trusted_opaque_move_out, .path = "core/memory/opaque_ownership.rg", .name = "trusted_opaque_move_out", .signatures = &.{"#(.t: Type, .storage_type: Type)(.storage: $&storage_type, .slot: $&t) -> (.result: t)"} },
    .{ .primitive = .trusted_opaque_relocate, .path = "core/memory/opaque_ownership.rg", .name = "trusted_opaque_relocate", .signatures = &.{"#(.t: Type)(.source: $&t, .destination: $&t) -> ()"} },
    .{ .primitive = .trusted_opaque_drop, .path = "core/memory/opaque_ownership.rg", .name = "trusted_opaque_drop", .signatures = &.{
        "#(.t: Type)(.slot: $&t) -> ()",
    } },
    .{ .primitive = .trusted_opaque_mark_empty, .path = "core/memory/opaque_ownership.rg", .name = "trusted_opaque_mark_empty", .signatures = &.{"#(.t: Type)(.storage: $&t) -> ()"} },
    .{ .primitive = .raw_released_storage, .path = "core/libc/libc.rg", .name = "_free", .signatures = &.{"(.address: UIntNative) -> ()"}, .declaration = .extern_function },
    .{ .primitive = .raw_released_storage, .path = "core/libc/libc.rg", .name = "_aligned_free", .signatures = &.{"(.address: UIntNative) -> ()"}, .declaration = .extern_function },
    .{ .primitive = .raw_allocated_storage, .path = "core/libc/libc.rg", .name = "_malloc", .signatures = &.{"(.size: UIntNative) -> (.address: UIntNative)"}, .declaration = .extern_function },
    .{ .primitive = .raw_allocated_storage, .path = "core/libc/libc.rg", .name = "_aligned_alloc", .signatures = &.{"(.alignment: UIntNative, .size: UIntNative) -> (.address: UIntNative)"}, .declaration = .extern_function },
};

comptime {
    @setEvalBranchQuota(5000);
    for (std.meta.fields(primitives.SafetyPrimitive)) |field| {
        const primitive: primitives.SafetyPrimitive = @enumFromInt(field.value);
        if (primitive == .none) continue;
        var count: usize = 0;
        for (specs) |spec| if (spec.primitive == primitive) {
            count += 1;
        };
        if (count == 0) @compileError("each safety primitive needs a registry specification");
    }
    for (specs, 0..) |spec, index| {
        for (specs[index + 1 ..]) |other| {
            if (std.mem.eql(u8, spec.path, other.path) and std.mem.eql(u8, spec.name, other.name))
                @compileError("safety primitive declarations must have unique paths and names");
        }
    }
}

pub fn findBundled(name: []const u8, path: []const u8) ?Spec {
    for (specs) |spec| {
        if (matchesPath(spec, path) and std.mem.eql(u8, name, spec.name))
            return spec;
    }
    return null;
}

pub fn matchesPath(spec: Spec, path: []const u8) bool {
    if (path.len < spec.path.len) return false;
    const start = path.len - spec.path.len;
    if (start > 0 and path[start - 1] != '/' and path[start - 1] != '\\') return false;
    for (path[start..], spec.path) |actual, expected| {
        if (actual == expected) continue;
        if (expected == '/' and actual == '\\') continue;
        return false;
    }
    return true;
}

pub fn signatureMatches(spec: Spec, tree: *const syntax.FileSyntaxTree, source: []const u8, function: syntax.FunctionDeclaration) bool {
    if (function.is_once or (function.body != null) != (spec.declaration == .body)) return false;
    const name_index: usize = @intFromEnum(function.name_token);
    const name_start: usize = tree.tokenLocation(function.name_token).offset;
    var start = name_start + spec.name.len;
    skipWhitespaceAndComments(source, &start);
    if (std.mem.startsWith(u8, source[start..], ":=")) {
        start += 2;
        skipWhitespaceAndComments(source, &start);
    }
    const output_index: usize = @intFromEnum(tree.mainToken(function.output));
    if (output_index <= name_index or output_index >= tree.tokens.len) return false;
    var depth: usize = 0;
    for (output_index..tree.tokens.len) |index| {
        switch (tree.tokens.items(.content)[index]) {
            .open_parenthesis => depth += 1,
            .close_parenthesis => {
                if (depth == 0) return false;
                depth -= 1;
                if (depth == 0) {
                    const end: usize = tree.tokens.items(.location)[index].offset + 1;
                    if (end > source.len or start > end) return false;
                    for (spec.signatures) |expected| if (sameSignature(source[start..end], expected)) {
                        if (spec.declaration == .extern_function and !externTrailerMatches(source[end..])) return false;
                        return true;
                    };
                    return false;
                }
            },
            else => {},
        }
    }
    return false;
}

fn externTrailerMatches(remaining: []const u8) bool {
    const line_end = std.mem.indexOfScalar(u8, remaining, '\n') orelse remaining.len;
    return sameSignature(remaining[0..line_end], ": ExternFunction");
}

fn sameSignature(actual: []const u8, expected: []const u8) bool {
    var actual_index: usize = 0;
    var expected_index: usize = 0;
    while (true) {
        skipTrivia(actual, &actual_index);
        skipTrivia(expected, &expected_index);
        if (actual_index == actual.len or expected_index == expected.len)
            return actual_index == actual.len and expected_index == expected.len;
        if (actual[actual_index] != expected[expected_index]) return false;
        actual_index += 1;
        expected_index += 1;
    }
}

fn skipTrivia(source: []const u8, index: *usize) void {
    while (index.* < source.len) {
        skipWhitespaceAndComments(source, index);
        if (index.* < source.len and source[index.*] == ',') {
            var next = index.* + 1;
            skipWhitespaceAndComments(source, &next);
            if (next < source.len and source[next] == ')') {
                index.* = next;
            } else return;
        } else return;
    }
}

fn skipWhitespaceAndComments(source: []const u8, index: *usize) void {
    while (index.* < source.len) {
        if (std.ascii.isWhitespace(source[index.*])) {
            index.* += 1;
        } else if (index.* + 1 < source.len and source[index.*] == '-' and source[index.* + 1] == '-') {
            while (index.* < source.len and source[index.*] != '\n') index.* += 1;
        } else return;
    }
}

test "primitive signature comparison preserves operand order and modes" {
    const expected = "#(.t: Type)(.value: t, .on: &Any) -> (.result: t)";
    try std.testing.expect(sameSignature(
        "#(.t: Type)(.value: t, .on: &Any,) -> (.result: t)",
        expected,
    ));
    try std.testing.expect(!sameSignature(
        "#(.t: Type)(.on: &Any, .value: t) -> (.result: t)",
        expected,
    ));
    try std.testing.expect(!sameSignature(
        "#(.t: Type)(.value: t, .on: $&Any) -> (.result: t)",
        expected,
    ));
}

/// Primitive semantics shared by concrete checking and symbolic summary
/// inference. Each pass interprets these operations in its own state model;
/// adding a primitive requires deciding its effects in one place.
pub const Transfer = struct {
    value: Value,
    consumes_storage_input: ?u32 = null,
    requires_storage_input: ?u32 = null,
    input: Input = .none,
    opaque_state: Opaque = .none,

    pub const Value = enum {
        empty,
        raw_storage,
        inherited_reference,
        inherited_storage,
        allocation,
        allocation_slot,
        reference_copy,
        reference_view,
        restrict_reference,
        depend_on,
        relocate,
        opaque_move,
        opaque_move_out,
        opaque_relocate,
        opaque_mark_empty,
        opaque_drop,
        execution_lend,
        execution_complete,
        execution_input,
    };

    pub const Input = enum { none, consume_opaque_owner, relocate, ignore };
    pub const Opaque = enum { none, clear_empty, store_hidden, mark_empty };
};

pub fn forPrimitive(primitive: primitives.SafetyPrimitive) Transfer {
    return switch (primitive) {
        .require_storage_capability => .{ .value = .empty, .requires_storage_input = 0 },
        .execution_lend => .{ .value = .execution_lend },
        .execution_complete => .{ .value = .execution_complete },
        .execution_input => .{ .value = .execution_input },
        .none, .float_math, .allocation_metadata_layout, .prepare_allocation_metadata => .{ .value = .empty },
        // Physical release identity selects an execution boundary. Language
        // consumption remains in checked allocation-owner cleanup, not raw ABI.
        .raw_released_storage => .{ .value = .empty },
        .raw_allocated_storage => .{ .value = .raw_storage },
        // Body-backed page acquisition retains the Argi UIntNative ABI;
        // libc acquisition identity also selects its pointer-return ABI.
        .native_allocated_storage => .{ .value = .raw_storage },
        .acquisition_subaddress => .{ .value = .reference_copy },
        .establish_inherited_reference => .{ .value = .inherited_reference },
        .establish_inherited_storage => .{ .value = .inherited_storage, .consumes_storage_input = 0 },
        .establish_allocation => .{ .value = .allocation, .consumes_storage_input = 0 },
        .establish_allocation_slot => .{ .value = .allocation_slot },
        .reference_offset, .mutable_reference_offset, .reinterpret_reference, .mutable_reinterpret_reference => .{ .value = .reference_view },
        .read_reference => .{ .value = .reference_copy },
        .restrict_reference => .{ .value = .restrict_reference },
        .depend_on => .{ .value = .depend_on },
        .relocate => .{ .value = .relocate, .input = .relocate },
        .trusted_opaque_move => .{
            .value = .opaque_move,
            .input = .consume_opaque_owner,
            .opaque_state = .clear_empty,
        },
        .trusted_opaque_move_in => .{
            .value = .opaque_move,
            .input = .consume_opaque_owner,
            .opaque_state = .store_hidden,
        },
        .trusted_opaque_move_out => .{ .value = .opaque_move_out },
        .trusted_opaque_relocate => .{ .value = .opaque_relocate, .input = .ignore },
        .trusted_opaque_drop => .{ .value = .opaque_drop },
        .trusted_opaque_mark_empty => .{ .value = .opaque_mark_empty, .opaque_state = .mark_empty },
    };
}

/// Ordinary memory touched by the primitive itself, independently of ownership
/// and validity transitions. Null preserves unknown/latent accesses. Empty means
/// no access through arguments; argument evaluation still has its own effects.
pub const MemoryAccess = struct { input: u32, write: bool = false };

pub fn memoryAccesses(primitive: primitives.SafetyPrimitive) ?[]const MemoryAccess {
    return switch (primitive) {
        .float_math,
        .allocation_metadata_layout,
        .establish_inherited_reference,
        .establish_inherited_storage,
        .require_storage_capability,
        .reference_offset,
        .mutable_reference_offset,
        .reinterpret_reference,
        .mutable_reinterpret_reference,
        .read_reference,
        .establish_allocation,
        .acquisition_subaddress,
        .restrict_reference,
        .depend_on,
        .execution_lend,
        .execution_input,
        .trusted_opaque_mark_empty,
        => &.{},
        // Slot establishment checks the receipt's authenticated bounds and
        // logical index. It does not read or initialize the addressed bytes.
        .establish_allocation_slot => &.{.{ .input = 0 }},
        .execution_complete, .trusted_opaque_move => &.{.{ .input = 0, .write = true }},
        .trusted_opaque_move_in, .trusted_opaque_move_out => &.{.{ .input = 1, .write = true }},
        .relocate, .trusted_opaque_relocate => &.{
            .{ .input = 0, .write = true },
            .{ .input = 1, .write = true },
        },
        // Allocation companions and selected cleanup may touch captured or
        // opaque resources beyond their direct input slots. Raw storage ABI
        // operations also lack a language storage identity for their addresses.
        .none,
        .prepare_allocation_metadata,
        .trusted_opaque_drop,
        .native_allocated_storage,
        .raw_allocated_storage,
        .raw_released_storage,
        => null,
    };
}

/// A universal whole-reference identity guarantee. Offsets and type-changing
/// views may retain backing, but cannot publish this stronger relation.
pub fn forwardsIdenticalReference(graph: *const @import("../global/graph.zig").GlobalSemanticGraph, function: @import("../global/graph.zig").Function) bool {
    if (!preservesReferenceStorage(graph, function)) return false;
    return @import("../global/types.zig").equal(graph, graph.fields.items[function.input.start].ty, graph.fields.items[function.output.start].ty);
}

/// The exact storage footprint can survive changing only reference mutability.
/// Readonly Any erasure retains the source as a conservative footprint.
/// Other referent types may select a different extent or layout instead.
pub fn preservesReferenceStorage(graph: *const @import("../global/graph.zig").GlobalSemanticGraph, function: @import("../global/graph.zig").Function) bool {
    switch (function.safety_primitive) {
        .reinterpret_reference, .mutable_reinterpret_reference, .read_reference => {},
        else => return false,
    }
    if (function.input.len != 1 or function.output.len != 1) return false;
    const input = graph.semanticType(graph.fields.items[function.input.start].ty);
    const output = graph.semanticType(graph.fields.items[function.output.start].ty);
    if (input != .pointer or output != .pointer) return false;
    if (@import("../global/types.zig").equal(graph, input.pointer.child, output.pointer.child)) return true;
    // Readonly erasure cannot select fields or enlarge the observed extent.
    // Retaining the original footprint is conservative, not pointer-type identity.
    const child = graph.semanticType(output.pointer.child);
    return output.pointer.mutability == .read_only and child == .builtin and child.builtin == .Any;
}

/// Allocation establishment publishes one fresh storage root and borrows its
/// anchor and virtual deallocator. Both interpreters use this field mapping;
/// raw byte ownership must not erase the deallocator's receiver lifetime.
pub const AllocationTransfer = struct {
    pub fn fieldCount(graph: *const @import("../global/graph.zig").GlobalSemanticGraph, callee: @import("../global/graph.zig").GlobalFunctionId) !u32 {
        const function = graph.function(callee);
        if (function.output.len != 1) return error.InvalidAllocationPrimitive;
        const output = graph.fields.items[function.output.start].ty;
        const fields = @import("../global/types.zig").fields(graph, output) orelse return error.InvalidAllocationPrimitive;
        if (fields.len <= data_field) return error.InvalidAllocationPrimitive;
        for (borrowed_fields) |borrowed| if (fields.len <= borrowed.field) return error.InvalidAllocationPrimitive;
        return fields.len;
    }
    pub const data_field = 0;
    pub const backing_reference_field = 11;
    pub const borrowed_fields = [_]struct { field: u32, input: u32 }{
        .{ .field = 3, .input = 4 }, // anchor
        .{ .field = 4, .input = 3 }, // deallocator
    };
};

// Successful opaque transfers change obligations on the evaluated referent,
// never on the slot holding its reference. Data initialization remains separate.
pub fn opaqueCleanupTransition(primitive: primitives.SafetyPrimitive) ?struct { input: u32, enabled: bool } {
    return switch (primitive) {
        .trusted_opaque_move => .{ .input = 0, .enabled = true },
        .trusted_opaque_move_in => .{ .input = 1, .enabled = true },
        .trusted_opaque_move_out => .{ .input = 1, .enabled = false },
        .trusted_opaque_drop => .{ .input = 0, .enabled = false },
        else => null,
    };
}

/// Operand positions come from primitive identity, not completed arity.
/// Auxiliary capability inputs do not change the represented operand positions.
pub const OpaqueMoveOperands = struct {
    owner: usize,
    storage: ?usize,
};

pub fn opaqueMoveOperands(primitive: primitives.SafetyPrimitive, argument_count: usize) ?OpaqueMoveOperands {
    const operands: OpaqueMoveOperands = switch (primitive) {
        .trusted_opaque_move => .{ .owner = 1, .storage = null },
        .trusted_opaque_move_in => .{ .owner = 2, .storage = 0 },
        else => return null,
    };
    return if (argument_count > operands.owner) operands else null;
}

test "opaque move operand identity survives additional capability inputs" {
    try std.testing.expectEqual(@as(usize, 1), opaqueMoveOperands(.trusted_opaque_move, 4).?.owner);
    try std.testing.expectEqual(@as(usize, 2), opaqueMoveOperands(.trusted_opaque_move_in, 4).?.owner);
    try std.testing.expectEqual(@as(?usize, 0), opaqueMoveOperands(.trusted_opaque_move_in, 4).?.storage);
    try std.testing.expectEqual(null, opaqueMoveOperands(.trusted_opaque_move_in, 2));
    try std.testing.expectEqual(null, opaqueMoveOperands(.relocate, 4));
}

test "trusted primitive paths accept native separators without weakening identity" {
    const name = "trusted_reinterpret_reference";
    try std.testing.expect(findBundled(name, "C:\\argi\\lib\\argi\\core\\memory\\heap_allocation\\RawPointer.rg") != null);
    try std.testing.expect(findBundled(name, "/opt/argi/core/memory/heap_allocation/RawPointer.rg") != null);
    try std.testing.expect(findBundled(name, "/opt/argi/othercore/memory/heap_allocation/RawPointer.rg") == null);
    try std.testing.expect(findBundled(name, "C:\\argi\\core\\memory\\RawPointer.rg") == null);
}

test "reference identity classification excludes offsets and representation changes" {
    const graph_mod = @import("../global/graph.zig");
    const a = std.testing.allocator;
    var graph: graph_mod.GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    try graph.types.appendSlice(a, &.{
        .{ .builtin = .Int32 },
        .{ .builtin = .UInt8 },
        .{ .pointer = .{ .child = @enumFromInt(0), .mutability = .read_only } },
        .{ .pointer = .{ .child = @enumFromInt(0), .mutability = .read_write } },
        .{ .pointer = .{ .child = @enumFromInt(1), .mutability = .read_only } },
        .{ .builtin = .Any },
        .{ .pointer = .{ .child = @enumFromInt(5), .mutability = .read_only } },
    });
    for ([_]graph_mod.GlobalTypeId{ @enumFromInt(2), @enumFromInt(2) }) |ty| try graph.fields.append(a, .{
        .name = .{ .start = 0, .len = 0 },
        .source = .{ .file_index = 0, .offset = 0 },
        .ty = ty,
    });
    var function = graph_mod.Function{
        .declaration = @enumFromInt(0),
        .input = .{ .start = 0, .len = 1 },
        .output = .{ .start = 1, .len = 1 },
        .safety_primitive = .reinterpret_reference,
    };
    try std.testing.expect(forwardsIdenticalReference(&graph, function));
    try std.testing.expect(preservesReferenceStorage(&graph, function));
    for ([_]primitives.SafetyPrimitive{ .reference_offset, .mutable_reference_offset, .establish_inherited_reference, .establish_allocation_slot, .none }) |primitive| {
        function.safety_primitive = primitive;
        try std.testing.expect(!forwardsIdenticalReference(&graph, function));
        try std.testing.expect(!preservesReferenceStorage(&graph, function));
    }
    function.safety_primitive = .reinterpret_reference;
    graph.fields.items[1].ty = @enumFromInt(4);
    try std.testing.expect(!forwardsIdenticalReference(&graph, function));
    try std.testing.expect(!preservesReferenceStorage(&graph, function));
    function.safety_primitive = .read_reference;
    graph.fields.items[0].ty = @enumFromInt(3);
    graph.fields.items[1].ty = @enumFromInt(2);
    try std.testing.expect(!forwardsIdenticalReference(&graph, function));
    try std.testing.expect(preservesReferenceStorage(&graph, function));
    function.safety_primitive = .mutable_reinterpret_reference;
    graph.fields.items[1].ty = @enumFromInt(3);
    try std.testing.expect(forwardsIdenticalReference(&graph, function));
    graph.fields.items[1].ty = @enumFromInt(6);
    try std.testing.expect(preservesReferenceStorage(&graph, function));
    try std.testing.expect(!forwardsIdenticalReference(&graph, function));
    graph.fields.items[0].ty = @enumFromInt(6);
    graph.fields.items[1].ty = @enumFromInt(3);
    try std.testing.expect(!preservesReferenceStorage(&graph, function));
    function.output.len = 0;
    try std.testing.expect(!forwardsIdenticalReference(&graph, function));
}
