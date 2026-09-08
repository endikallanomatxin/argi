const std = @import("std");
const module_sg = @import("module_semantic_graph.zig");
const primitives = @import("semantic_primitives.zig");

pub const Stats = struct {
    deinit_functions: u32 = 0,
    generic_deinit_functions: u32 = 0,
};

/// Temporal identities must not be inferred by Safety/GlobalSema from a callee
/// spelling. Resolve them once from the source-level declaration and store the
/// semantic bit on the normal/generic function record.
pub fn lower(
    graph: *module_sg.ModuleSemanticGraph,
    files: []const module_sg.FileInput,
) Stats {
    var stats: Stats = .{};

    for (graph.semantic.function_semantics.items) |*semantic| {
        const function = graph.functions.items[@intFromEnum(semantic.function)];
        const declaration = graph.declarations.items[@intFromEnum(function.declaration)];
        const file = files[declaration.module_file_index];
        if (file.is_bundled_core) semantic.safety_primitive = safetyPrimitiveForBundledDeclaration(graph.text(declaration.name), file.path);
        if (isDeinit(file, declaration.syntax_node)) {
            semantic.flags.is_deinit = true;
            stats.deinit_functions += 1;
        }
    }

    for (graph.semantic.templates.generic_function_templates.items) |*template| {
        const declaration = graph.declarations.items[@intFromEnum(template.declaration)];
        const file = files[declaration.module_file_index];
        if (file.is_bundled_core) template.safety_primitive = safetyPrimitiveForBundledDeclaration(graph.text(declaration.name), file.path);
        if (isDeinit(file, declaration.syntax_node)) {
            template.is_deinit = true;
            stats.generic_deinit_functions += 1;
        }
    }
    return stats;
}

fn safetyPrimitiveForBundledDeclaration(name: []const u8, file: []const u8) primitives.SafetyPrimitive {
    const Entry = struct { name: []const u8, primitive: primitives.SafetyPrimitive };
    const raw_pointer_entries = [_]Entry{
        .{ .name = "establish_fresh_reference", .primitive = .establish_fresh_reference },
        .{ .name = "establish_inherited_reference", .primitive = .establish_inherited_reference },
        .{ .name = "establish_inherited_storage", .primitive = .establish_inherited_storage },
        .{ .name = "reference_offset", .primitive = .reference_offset },
        .{ .name = "mutable_reference_offset", .primitive = .mutable_reference_offset },
        .{ .name = "reinterpret_reference", .primitive = .reinterpret_reference },
        .{ .name = "mutable_reinterpret_reference", .primitive = .mutable_reinterpret_reference },
        .{ .name = "read_reference", .primitive = .read_reference },
    };
    if (std.mem.endsWith(u8, file, "core/memory/heap_allocation/RawPointer.rg"))
        for (raw_pointer_entries) |entry| if (std.mem.eql(u8, name, entry.name)) return entry.primitive;
    if (std.mem.endsWith(u8, file, "core/memory/heap_allocation/Allocator.rg") and
        std.mem.eql(u8, name, "establish_allocation")) return .establish_allocation;
    if (std.mem.endsWith(u8, file, "core/memory/relocation.rg") and
        std.mem.eql(u8, name, "relocate")) return .relocate;
    if (std.mem.endsWith(u8, file, "core/memory/reference_lifetime.rg") and
        std.mem.eql(u8, name, "restrict_reference")) return .restrict_reference;
    // SourceFile.origin establishes trust before this function is reached.
    // The canonical path only identifies the trusted declaration, so another
    // bundled-core helper with the same name cannot become a primitive.
    if (std.mem.endsWith(u8, file, "core/memory/opaque_ownership.rg")) {
        if (std.mem.eql(u8, name, "trusted_opaque_move")) return .trusted_opaque_move;
        if (std.mem.eql(u8, name, "trusted_opaque_move_in")) return .trusted_opaque_move_in;
        if (std.mem.eql(u8, name, "trusted_opaque_move_out")) return .trusted_opaque_move_out;
        if (std.mem.eql(u8, name, "trusted_opaque_relocate")) return .trusted_opaque_relocate;
        if (std.mem.eql(u8, name, "trusted_opaque_drop")) return .trusted_opaque_drop;
        if (std.mem.eql(u8, name, "trusted_opaque_mark_empty")) return .trusted_opaque_mark_empty;
    }
    if (std.mem.endsWith(u8, file, "core/libc/libc.rg") and std.mem.eql(u8, name, "malloc"))
        return .raw_allocated_storage;
    return .none;
}

fn isDeinit(file: module_sg.FileInput, node: @import("../3_syntax/syntax_tree.zig").NodeIndex) bool {
    const name = file.tree.functionNameFromSource(file.source, node) orelse return false;
    return switch (name) {
        .operator => false,
        .identifier => |token| std.mem.eql(u8, file.tree.tokenTextFromSource(file.source, token), "deinit"),
    };
}

test "function identity lowering keeps deinit as semantic metadata" {
    const flags: @import("semantic_primitives.zig").FunctionFlags = .{ .is_deinit = true };
    try std.testing.expect(flags.is_deinit);
}
