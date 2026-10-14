const std = @import("std");
const module_sg = @import("graph.zig");
const registry = @import("../primitives/registry.zig");
const diagnostics_mod = @import("../../1_base/diagnostic.zig");

/// Resolve privileged identities from trusted declarations only after their
/// source signatures have passed the compiler/core contract. Safety and global
/// semantizing consume the metadata and never re-identify a callee by name.
pub fn lower(
    graph: *module_sg.ModuleSemanticGraph,
    files: []const module_sg.FileInput,
    diagnostics: ?*diagnostics_mod.Diagnostics,
) !void {
    try validateBundledPrimitives(graph, files, diagnostics);

    for (graph.semantic.function_semantics.items) |*semantic| {
        const function = graph.functions.items[@intFromEnum(semantic.function)];
        const declaration = graph.declarations.items[@intFromEnum(function.declaration)];
        const file = files[declaration.module_file_index];
        if (file.is_bundled_core) if (registry.findBundled(graph.text(declaration.name), file.path)) |spec| {
            semantic.safety_primitive = spec.primitive;
        };
    }

    for (graph.semantic.parameterized_storage.parameterized_functions.items) |*parameterized| {
        const declaration = graph.declarations.items[@intFromEnum(parameterized.declaration)];
        const file = files[declaration.module_file_index];
        if (file.is_bundled_core) if (registry.findBundled(graph.text(declaration.name), file.path)) |spec| {
            parameterized.safety_primitive = spec.primitive;
        };
    }
}

pub fn validateOrdinaryIdentities(graph: *const module_sg.ModuleSemanticGraph, files: []const module_sg.FileInput, diagnostics: ?*diagnostics_mod.Diagnostics) !void {
    for (graph.declarations.items, 0..) |declaration, index| {
        if (declaration.kind != .function) continue;
        const file = files[declaration.module_file_index];
        const node = module_sg.declarationSyntaxNode(files, declaration) orelse continue;
        const function = file.tree.functionDeclaration(node) orelse continue;
        // Ordinary identities are unique regardless of declaration spelling,
        // runtime inputs or compile-time parameter arity.
        for (graph.declarations.items, 0..) |other, other_index| {
            if (index == other_index or other.kind != .function) continue;
            if (!std.mem.eql(u8, graph.text(declaration.name), graph.text(other.name))) continue;
            if (diagnostics) |bag| try bag.add(file.tree.tokenLocation(function.name_token), .semantic, "ordinary function '{s}' has more than one declaration; provide specialized behavior through a contract implementation", .{graph.text(declaration.name)});
            return error.DuplicateOrdinaryFunction;
        }
    }
}

fn validateBundledPrimitives(
    graph: *const module_sg.ModuleSemanticGraph,
    files: []const module_sg.FileInput,
    diagnostics: ?*diagnostics_mod.Diagnostics,
) !void {
    for (files, 0..) |file, file_index| {
        if (!file.is_bundled_core) continue;
        for (registry.specs) |spec| {
            if (spec.operating_systems.len != 0 and std.mem.indexOfScalar(std.Target.Os.Tag, spec.operating_systems, graph.target.os) == null) continue;
            if (!registry.matchesPath(spec, file.path)) continue;
            var found = false;
            for (graph.declarations.items) |declaration| {
                if (declaration.module_file_index != file_index) continue;
                if (declaration.kind != .function) continue;
                if (std.mem.eql(u8, graph.text(declaration.name), spec.name)) {
                    const declaration_node = module_sg.declarationSyntaxNode(files, declaration) orelse return error.PrimitiveContractMismatch;
                    try validatePrimitiveDeclaration(spec, file, declaration_node, diagnostics);
                    found = true;
                }
            }
            if (found) continue;
            if (diagnostics) |bag| try bag.add(
                .{ .file = file.tree.file_id, .offset = 0 },
                .internal,
                "bundled core primitive `{s}` is missing from its canonical file",
                .{spec.name},
            );
            return error.PrimitiveContractMismatch;
        }
    }
}

fn validatePrimitiveDeclaration(
    spec: registry.Spec,
    file: module_sg.FileInput,
    declaration_node: @import("../../3_syntax/syntax_tree.zig").NodeIndex,
    diagnostics: ?*diagnostics_mod.Diagnostics,
) !void {
    const function = file.tree.functionDeclaration(declaration_node) orelse return error.PrimitiveContractMismatch;
    if (registry.signatureMatches(spec, file.tree, file.source, function)) return;
    if (diagnostics) |bag| {
        const location = file.tree.tokenLocation(function.name_token);
        if (spec.signatures.len == 1)
            try bag.add(
                location,
                .internal,
                "bundled core primitive `{s}` has an incompatible signature; expected `{s}`",
                .{ spec.name, spec.signatures[0] },
            )
        else
            try bag.add(
                location,
                .internal,
                "bundled core primitive `{s}` has an incompatible signature; expected an approved overload",
                .{spec.name},
            );
    }
    return error.PrimitiveContractMismatch;
}
