const std = @import("std");
const primitives = @import("schema.zig");
const syntax = @import("../../3_syntax/syntax_tree.zig");

/// Trusted declarations are identified only in the bundled core. Signature
/// text is compared without spacing and comments, so this table
/// describes the complete source-level interface, including generic type
/// parameters, argument names/modes and output shape. Runtime safety effects
/// are the Transfer below and are selected by the same primitive identity.
pub const Spec = struct {
    primitive: primitives.SafetyPrimitive,
    path: []const u8,
    name: []const u8,
    signatures: []const []const u8,
    declaration: enum { body, extern_function } = .body,
};

pub const specs = [_]Spec{
    .{ .primitive = .establish_fresh_reference, .path = "core/memory/heap_allocation/RawPointer.rg", .name = "establish_fresh_reference", .signatures = &.{"#(.t: Type)(.raw: RawPointer#(.t: t)) -> (.reference: $&t)"} },
    .{ .primitive = .establish_inherited_reference, .path = "core/memory/heap_allocation/RawPointer.rg", .name = "establish_inherited_reference", .signatures = &.{"#(.t: Type)(.raw: RawPointer#(.t: t), .root: &Any) -> (.reference: $&t)"} },
    .{ .primitive = .establish_inherited_storage, .path = "core/memory/heap_allocation/RawPointer.rg", .name = "establish_inherited_storage", .signatures = &.{"#(.t: Type)(.address: UIntNative, .root: &Any) -> (.reference: $&t)"} },
    .{ .primitive = .reference_offset, .path = "core/memory/heap_allocation/RawPointer.rg", .name = "reference_offset", .signatures = &.{"#(.t: Type)(.base: &t, .elements: UIntNative) -> (.reference: &t)"} },
    .{ .primitive = .mutable_reference_offset, .path = "core/memory/heap_allocation/RawPointer.rg", .name = "mutable_reference_offset", .signatures = &.{"#(.t: Type)(.base: $&t, .elements: UIntNative) -> (.reference: $&t)"} },
    .{ .primitive = .reinterpret_reference, .path = "core/memory/heap_allocation/RawPointer.rg", .name = "reinterpret_reference", .signatures = &.{"#(.from: Type, .to: Type)(.base: &from) -> (.reference: &to)"} },
    .{ .primitive = .mutable_reinterpret_reference, .path = "core/memory/heap_allocation/RawPointer.rg", .name = "mutable_reinterpret_reference", .signatures = &.{"#(.from: Type, .to: Type)(.base: $&from) -> (.reference: $&to)"} },
    .{ .primitive = .read_reference, .path = "core/memory/heap_allocation/RawPointer.rg", .name = "read_reference", .signatures = &.{"#(.t: Type)(.base: $&t) -> (.reference: &t)"} },
    .{ .primitive = .establish_allocation, .path = "core/memory/heap_allocation/Allocator.rg", .name = "establish_allocation", .signatures = &.{"(.storage: UIntNative, .size: UIntNative, .deallocator: Virtual#(.abstract: Deallocator)) -> (.allocation: Allocation)"} },
    .{ .primitive = .relocate, .path = "core/memory/relocation.rg", .name = "relocate", .signatures = &.{"#(.t: Type)(.source: $&t, .destination: $&t) -> ()"} },
    .{ .primitive = .restrict_reference, .path = "core/memory/validity_dependency.rg", .name = "restrict_reference", .signatures = &.{"#(.t: Type)(.input: t, .on: &Any) -> (.reference: t)"} },
    .{ .primitive = .depend_on, .path = "core/memory/validity_dependency.rg", .name = "depend_on", .signatures = &.{"#(.t: Type)(.value: t, .on: &Any) -> (.result: t)"} },
    .{ .primitive = .trusted_opaque_move, .path = "core/memory/opaque_ownership.rg", .name = "trusted_opaque_move", .signatures = &.{"#(.t: Type)(.destination: $&t, .source: t) -> ()"} },
    .{ .primitive = .trusted_opaque_move_in, .path = "core/memory/opaque_ownership.rg", .name = "trusted_opaque_move_in", .signatures = &.{"#(.t: Type, .storage_type: Type)(.storage: $&storage_type, .destination: $&t, .source: t) -> ()"} },
    .{ .primitive = .trusted_opaque_move_out, .path = "core/memory/opaque_ownership.rg", .name = "trusted_opaque_move_out", .signatures = &.{"#(.t: Type, .storage_type: Type)(.storage: $&storage_type, .slot: $&t) -> (.result: t)"} },
    .{ .primitive = .trusted_opaque_relocate, .path = "core/memory/opaque_ownership.rg", .name = "trusted_opaque_relocate", .signatures = &.{"#(.t: Type)(.source: $&t, .destination: $&t) -> ()"} },
    .{ .primitive = .trusted_opaque_drop, .path = "core/memory/opaque_ownership.rg", .name = "trusted_opaque_drop", .signatures = &.{
        "#(.t: Type)(.slot: $&t) -> ()",
        "#(.t: Type)(.slot: $&t, .allocator: $&Allocator) -> ()",
    } },
    .{ .primitive = .trusted_opaque_mark_empty, .path = "core/memory/opaque_ownership.rg", .name = "trusted_opaque_mark_empty", .signatures = &.{"#(.t: Type)(.storage: $&t) -> ()"} },
    .{ .primitive = .raw_allocated_storage, .path = "core/libc/libc.rg", .name = "malloc", .signatures = &.{"(.size: UIntNative) -> (.address: UIntNative)"}, .declaration = .extern_function },
};

comptime {
    for (std.meta.fields(primitives.SafetyPrimitive)) |field| {
        const primitive: primitives.SafetyPrimitive = @enumFromInt(field.value);
        if (primitive == .none) continue;
        var count: usize = 0;
        for (specs) |spec| if (spec.primitive == primitive) {
            count += 1;
        };
        if (count != 1) @compileError("each safety primitive needs exactly one registry specification");
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
    return std.mem.endsWith(u8, path, spec.path);
}

pub fn signatureMatches(spec: Spec, tree: *const syntax.FileSyntaxTree, source: []const u8, function: syntax.FunctionDeclaration) bool {
    if (function.is_once or (function.body != null) != (spec.declaration == .body)) return false;
    const name_index: usize = @intFromEnum(function.name_token);
    const name_start: usize = tree.tokenLocation(function.name_token).offset;
    const start = name_start + spec.name.len;
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
/// adding a primitive requires deciding all three effects in one place.
pub const Transfer = struct {
    value: Value,
    input: Input = .none,
    opaque_state: Opaque = .none,

    pub const Value = enum {
        empty,
        raw_storage,
        fresh_reference,
        inherited_reference,
        inherited_storage,
        allocation,
        reference_copy,
        restrict_reference,
        depend_on,
        relocate,
        opaque_move,
        opaque_move_out,
        opaque_relocate,
        opaque_mark_empty,
        opaque_drop,
    };

    pub const Input = enum { none, consume_opaque_owner, relocate, ignore };
    pub const Opaque = enum { none, clear_empty, store_hidden, mark_empty };
};

pub fn forPrimitive(primitive: primitives.SafetyPrimitive) Transfer {
    return switch (primitive) {
        .none => .{ .value = .empty },
        .raw_allocated_storage => .{ .value = .raw_storage },
        .establish_fresh_reference => .{ .value = .fresh_reference },
        .establish_inherited_reference => .{ .value = .inherited_reference },
        .establish_inherited_storage => .{ .value = .inherited_storage },
        .establish_allocation => .{ .value = .allocation },
        .reference_offset, .mutable_reference_offset, .reinterpret_reference, .mutable_reinterpret_reference, .read_reference => .{ .value = .reference_copy },
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

/// A move with two arguments discovers its storage domain from the owner.
/// The three-argument form names the storage domain explicitly.
pub const OpaqueMoveOperands = struct {
    owner: usize,
    storage: ?usize,
};

pub fn opaqueMoveOperands(argument_count: usize) ?OpaqueMoveOperands {
    return switch (argument_count) {
        2 => .{ .owner = 1, .storage = null },
        3 => .{ .owner = 2, .storage = 0 },
        else => null,
    };
}
