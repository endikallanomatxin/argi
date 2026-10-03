const std = @import("std");
const module_sg = @import("graph.zig");
const registry = @import("../primitives/registry.zig");
const diagnostics_mod = @import("../../1_base/diagnostic.zig");

pub const Stats = struct {
    deinit_functions: u32 = 0,
    generic_deinit_functions: u32 = 0,
};

/// Resolve privileged identities from trusted declarations only after their
/// source signatures have passed the compiler/core contract. Safety and global
/// semantizing consume the metadata and never re-identify a callee by name.
pub fn lower(
    graph: *module_sg.ModuleSemanticGraph,
    files: []const module_sg.FileInput,
    diagnostics: ?*diagnostics_mod.Diagnostics,
) !Stats {
    var stats: Stats = .{};
    try validateBundledPrimitives(graph, files, diagnostics);

    for (graph.semantic.function_semantics.items) |*semantic| {
        const function = graph.functions.items[@intFromEnum(semantic.function)];
        const declaration = graph.declarations.items[@intFromEnum(function.declaration)];
        const file = files[declaration.module_file_index];
        const declaration_node = module_sg.declarationSyntaxNode(files, declaration) orelse continue;
        if (file.is_bundled_core) if (registry.findBundled(graph.text(declaration.name), file.path)) |spec| {
            semantic.safety_primitive = spec.primitive;
        };
        if (isDeinit(file, declaration_node)) {
            std.debug.assert(std.mem.eql(u8, graph.text(declaration.name), "deinit"));
            semantic.flags.is_deinit = true;
            stats.deinit_functions += 1;
        }
    }

    for (graph.semantic.parameterized_storage.parameterized_functions.items) |*parameterized| {
        const declaration = graph.declarations.items[@intFromEnum(parameterized.declaration)];
        const file = files[declaration.module_file_index];
        const declaration_node = module_sg.declarationSyntaxNode(files, declaration) orelse continue;
        if (file.is_bundled_core) if (registry.findBundled(graph.text(declaration.name), file.path)) |spec| {
            parameterized.safety_primitive = spec.primitive;
        };
        if (isDeinit(file, declaration_node)) {
            std.debug.assert(std.mem.eql(u8, graph.text(declaration.name), "deinit"));
            parameterized.is_deinit = true;
            stats.generic_deinit_functions += 1;
        }
    }
    return stats;
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

fn isDeinit(file: module_sg.FileInput, node: @import("../../3_syntax/syntax_tree.zig").NodeIndex) bool {
    const name = file.tree.functionNameFromSource(file.source, node) orelse return false;
    return switch (name) {
        .operator => false,
        .identifier => |token| std.mem.eql(u8, file.tree.tokenTextFromSource(file.source, token), "deinit"),
    };
}

test "function identity lowering keeps deinit as semantic metadata" {
    const flags: @import("../primitives/schema.zig").FunctionFlags = .{ .is_deinit = true };
    try std.testing.expect(flags.is_deinit);
}
