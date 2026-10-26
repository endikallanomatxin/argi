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

    for (graph.functions.items) |*semantic| {
        const function = semantic.*;
        const declaration = graph.declarations.items[@intFromEnum(function.declaration)];
        const file = files[declaration.module_file_index];
        if (file.is_bundled_core) if (registry.findBundled(graph.text(declaration.name), file.path)) |spec| {
            semantic.safety_primitive = spec.primitive;
            semantic.flags.is_source_location_id = spec.flags.is_source_location_id;
            semantic.flags.is_source_location_resolver = spec.flags.is_source_location_resolver;
            semantic.flags.is_error_context_view = spec.flags.is_error_context_view;
            semantic.flags.is_error_context_text = spec.flags.is_error_context_text;
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
                "bundled core primitive `{s}` has an incompatible signature; expected an approved signature",
                .{spec.name},
            );
    }
    return error.PrimitiveContractMismatch;
}

test "source metadata identities require canonical trusted declarations" {
    const source =
        "SourceLocationId := (.value: UInt32)\n" ++
        "SourceLocation := (.line: UIntNative)\n" ++
        "error_location_id := () -> (.location: SourceLocationId)  { location = (.value = 0) }\n" ++
        "source_location := (.id: SourceLocationId) -> (.location: SourceLocation)  { location = (.line = 42) }\n";
    const cases = [_]struct { path: []const u8, trusted: bool, selected: bool }{
        .{ .path = "core/errors/source_location.rg", .trusted = true, .selected = true },
        .{ .path = "core/errors/other.rg", .trusted = true, .selected = false },
        .{ .path = "core/errors/source_location.rg", .trusted = false, .selected = false },
    };
    for (cases) |case| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const files = [_]@import("../../1_base/source_files.zig").SourceFile{.{ .path = case.path, .code = source }};
        var diagnostics = diagnostics_mod.Diagnostics.init(&a, &files);
        defer diagnostics.deinit();
        var tokenizer = @import("../../2_tokens/tokenizer.zig").Tokenizer.init(a, &diagnostics, source, @enumFromInt(0));
        defer tokenizer.deinit();
        _ = try tokenizer.tokenize();
        var syntaxer = @import("../../3_syntax/syntaxer.zig").Syntaxer.initFile(a, @import("../../3_syntax/syntax_tree.zig").FileSyntaxTree.initOwnedTokens(@enumFromInt(0), tokenizer.takeTokens()), source, &diagnostics);
        defer syntaxer.deinit();
        var tree = try syntaxer.parse();
        defer tree.deinit(a);
        var built = try @import("semantizer.zig").build(a, "core", &.{.{ .path = case.path, .tree = &tree, .source = source, .is_bundled_core = case.trusted }});
        defer built.graph.deinit(a);
        var location_id = false;
        var resolver = false;
        for (built.graph.functions.items) |semantic| {
            location_id = location_id or semantic.flags.is_source_location_id;
            resolver = resolver or semantic.flags.is_source_location_resolver;
            try std.testing.expectEqual(.none, semantic.safety_primitive);
        }
        try std.testing.expectEqual(case.selected, location_id);
        try std.testing.expectEqual(case.selected, resolver);
    }
}

test "trace helper metadata requires the registered core path and keeps ordinary safety" {
    const source =
        "ErrorTracer<.T: Type>: Contract = ()\n" ++
        "SourceLocationId := (.value: UInt32)\n" ++
        "StringView := (.length: UIntNative)\n" ++
        "_add_error_context := (.tracer: $&Virtual<.contract: ErrorTracer>, .location: SourceLocationId, .context: StringView) -> ()  {}\n" ++
        "_add_error_context_text := (.tracer: $&Virtual<.contract: ErrorTracer>, .location: SourceLocationId, .context: &CChar) -> ()  {}\n";
    const cases = [_]struct { path: []const u8, trusted: bool, selected: bool }{
        .{ .path = "core/errors/error_tracer.rg", .trusted = true, .selected = true },
        .{ .path = "core/errors/unrelated.rg", .trusted = true, .selected = false },
        .{ .path = "core/errors/error_tracer.rg", .trusted = false, .selected = false },
    };
    for (cases) |case| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const files = [_]@import("../../1_base/source_files.zig").SourceFile{.{ .path = case.path, .code = source }};
        var diagnostics = diagnostics_mod.Diagnostics.init(&a, &files);
        defer diagnostics.deinit();
        var tokenizer = @import("../../2_tokens/tokenizer.zig").Tokenizer.init(a, &diagnostics, source, @enumFromInt(0));
        defer tokenizer.deinit();
        _ = try tokenizer.tokenize();
        var syntaxer = @import("../../3_syntax/syntaxer.zig").Syntaxer.initFile(a, @import("../../3_syntax/syntax_tree.zig").FileSyntaxTree.initOwnedTokens(@enumFromInt(0), tokenizer.takeTokens()), source, &diagnostics);
        defer syntaxer.deinit();
        var tree = try syntaxer.parse();
        defer tree.deinit(a);
        var built = try @import("semantizer.zig").build(a, "core", &.{.{ .path = case.path, .tree = &tree, .source = source, .is_bundled_core = case.trusted }});
        defer built.graph.deinit(a);
        var view = false;
        var text = false;
        for (built.graph.functions.items) |semantic| {
            view = view or semantic.flags.is_error_context_view;
            text = text or semantic.flags.is_error_context_text;
            try std.testing.expectEqual(.none, semantic.safety_primitive);
        }
        try std.testing.expectEqual(case.selected, view);
        try std.testing.expectEqual(case.selected, text);
    }
}
