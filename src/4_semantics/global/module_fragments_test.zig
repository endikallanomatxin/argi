const std = @import("std");
const sema = @import("semantizer.zig");
const g = @import("graph.zig");
const module = @import("../module/graph.zig");
const diagnostics_mod = @import("../../1_base/diagnostic.zig");

fn build(allocator: std.mem.Allocator, path: []const u8, source: []const u8) !module.ModuleSemanticGraph {
    const sources = [_]@import("../../1_base/source_files.zig").SourceFile{.{ .path = path, .code = source }};
    var diagnostics = diagnostics_mod.Diagnostics.init(&allocator, &sources);
    defer diagnostics.deinit();
    var tokenizer = @import("../../2_tokens/tokenizer.zig").Tokenizer.init(allocator, &diagnostics, source, diagnostics.source_db.fileId(0));
    defer tokenizer.deinit();
    _ = try tokenizer.tokenize();
    var parser = @import("../../3_syntax/syntaxer.zig").Syntaxer.initFile(allocator, @import("../../3_syntax/syntax_tree.zig").FileSyntaxTree.initOwnedTokens(diagnostics.source_db.fileId(0), tokenizer.takeTokens()), source, &diagnostics);
    defer parser.deinit();
    var tree = try parser.parse();
    defer tree.deinit(allocator);
    const inputs = [_]module.FileInput{.{ .path = path, .source = source, .tree = &tree }};
    const result = try @import("../module/semantizer.zig").build(allocator, std.fs.path.dirname(path).?, &inputs);
    return result.graph;
}

test "module fragments retain declaration identities and share lexical and qualified lookup" {
    const a = std.testing.allocator;
    const base_source = "Secret: Type = (._value: Int32)\n_hidden := () -> (.result: Int32) { result = 42 }";
    const fragment_source = "answer := () -> (.result: Int32) { value :: Secret = (._value = _hidden())\nresult = value._value }";
    const client_source = "pkg := import(\"../pkg\")\nuse := () -> (.result: Int32) { result = pkg.answer() }";
    const sources = [_]@import("../../1_base/source_files.zig").SourceFile{
        .{ .path = "/project/pkg/base.rg", .code = base_source },
        .{ .path = "/project/pkg/selected.rg", .code = fragment_source },
        .{ .path = "/project/client/main.rg", .code = client_source },
    };
    var source_diagnostics = diagnostics_mod.Diagnostics.init(&a, &sources);
    defer source_diagnostics.deinit();
    var base = try build(a, sources[0].path, base_source);
    defer base.deinit(a);
    var fragment = try build(a, sources[1].path, fragment_source);
    defer fragment.deinit(a);
    var client = try build(a, sources[2].path, client_source);
    defer client.deinit(a);
    const modules = [_]module.ModuleSemanticGraph{ base, fragment, client };
    var session: sema.Session = undefined;
    try session.init(a, modules[0..1], .{ .diagnostics = &source_diagnostics });
    defer session.deinit();
    try session.advance();
    const before = session.relocation.graph.modules.items[0].declarations;
    const original = session.relocation.graph.functions.items[0].declaration;
    try session.appendModuleFragment(modules[0..2], @enumFromInt(0));
    try session.advance();
    try std.testing.expectEqual(before, session.relocation.graph.modules.items[0].declarations);
    try std.testing.expectEqual(original, session.relocation.graph.functions.items[0].declaration);
    try session.appendModules(&modules);
    try std.testing.expect(session.resolvers.core.declarationVisible(1, original, null));
    try std.testing.expect(!session.resolvers.core.declarationVisible(2, original, @enumFromInt(0)));
    try session.advance();
    var result = try session.finish();
    defer result.graph.deinit(a);
    try std.testing.expectEqual(@as(g.GlobalModuleId, @enumFromInt(0)), result.graph.moduleNamespace(@enumFromInt(1)));
    try std.testing.expectEqual(@as(g.GlobalModuleId, @enumFromInt(0)), result.graph.module_aliases.items[0].target);
    try std.testing.expectEqual(@as(g.GlobalModuleId, @enumFromInt(1)), result.graph.moduleForDeclaration(result.graph.functions.items[1].declaration).?);

    var scratch = std.heap.ArenaAllocator.init(a);
    defer scratch.deinit();
    var diagnostics = diagnostics_mod.Diagnostics.init(&a, &.{});
    defer diagnostics.deinit();
    var safety = @import("../safety/checker.zig").SafetyChecker.init(scratch.allocator(), &diagnostics, &result.graph);
    defer safety.deinit();
    try safety.analyze();
    var lower = try @import("../../5_codegen/bytecode/lower.zig").Lower.init(scratch.allocator(), &result.graph);
    const program = try lower.compile(@enumFromInt(2));
    var vm = try @import("../../execution/vm.zig").Vm.init(a, program, .{});
    defer vm.deinit();
    try std.testing.expectEqual(@as(i128, 42), (try vm.invoke(@enumFromInt(2), &.{}))[0].integer);
}

test "module fragments reject cross-fragment ordinary overloads" {
    const a = std.testing.allocator;
    var base = try build(a, "/project/pkg/base.rg", "work := () -> () {}");
    defer base.deinit(a);
    var fragment = try build(a, "/project/pkg/selected.rg", "work#(.T: Type) := (.value: T) -> () {}");
    defer fragment.deinit(a);
    const modules = [_]module.ModuleSemanticGraph{ base, fragment };
    var session: sema.Session = undefined;
    try session.init(a, modules[0..1], .{});
    defer session.deinit();
    try session.advance();
    try std.testing.expectError(error.DuplicateOrdinaryFunction, session.appendModuleFragment(&modules, @enumFromInt(0)));
    try std.testing.expectError(error.InvalidSemanticSessionState, session.advance());
}

test "module fragments require explicit same-directory and trust ownership" {
    const a = std.testing.allocator;
    var base = try build(a, "/project/pkg/base.rg", "answer := () -> (.result: Int32) { result = 42 }");
    defer base.deinit(a);
    var other = try build(a, "/project/other/main.rg", "other := () -> () {}");
    defer other.deinit(a);
    var modules = [_]module.ModuleSemanticGraph{ base, other };
    var session: sema.Session = undefined;
    try session.init(a, modules[0..1], .{});
    defer session.deinit();
    try session.advance();
    try std.testing.expectError(error.InvalidModuleFragment, session.appendModuleFragment(&modules, @enumFromInt(0)));
    try std.testing.expectEqual(@as(usize, 1), session.relocation.graph.modules.items.len);
    try std.testing.expectError(error.InvalidModuleFragment, session.appendModuleFragment(&modules, @enumFromInt(1)));
    modules[1].module_dir = base.module_dir;
    modules[1].is_bundled_core = true;
    try std.testing.expectError(error.InvalidModuleFragment, session.appendModuleFragment(&modules, @enumFromInt(0)));
}

test "module fragments keep path coincidence separate from explicit namespace ownership" {
    const a = std.testing.allocator;
    var graph: g.GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    const dir = try graph.addString(a, "/project/pkg");
    try graph.modules.appendNTimes(a, .{ .dir = dir, .files = .{ .start = 0, .len = 0 }, .declarations = .{ .start = 0, .len = 0 } }, 2);
    const modules = [_]module.ModuleSemanticGraph{ .{ .module_dir = "/project/pkg" }, .{ .module_dir = "/project/pkg" } };
    const linker = @import("module_linker.zig");
    try std.testing.expect(!graph.sameModuleNamespace(@enumFromInt(0), @enumFromInt(1)));
    try std.testing.expectError(error.AmbiguousModuleReference, linker.resolveImportPath(a, &graph, &modules, 0, "./"));
    graph.modules.items[1].namespace = @enumFromInt(0);
    try std.testing.expectEqual(@as(g.GlobalModuleId, @enumFromInt(0)), try linker.resolveImportPath(a, &graph, &modules, 0, "./"));
    try @import("verify.zig").verifyGlobal(&graph);
    graph.modules.items[1].namespace = @enumFromInt(1);
    try std.testing.expectError(error.InvalidGlobalSemanticGraph, @import("verify.zig").verifyGlobal(&graph));
    graph.modules.items[1].namespace = @enumFromInt(0);
    graph.modules.items[1].is_bundled_core = true;
    try std.testing.expectError(error.InvalidGlobalSemanticGraph, @import("verify.zig").verifyGlobal(&graph));
}

test "module fragments select contract implementations in the shared namespace" {
    const a = std.testing.allocator;
    var base = try build(a, "/project/pkg/base.rg", "Echo#(.T: Type): Contract = (.echo: (.value: T) -> (.result: T))");
    defer base.deinit(a);
    var fragment = try build(a, "/project/pkg/selected.rg", "implement Echo#(Int32) (.echo = (.value: Int32) -> (.result: Int32) { result = value })\nanswer := () -> (.result: Int32) { result = echo(.value = 42) }");
    defer fragment.deinit(a);
    const modules = [_]module.ModuleSemanticGraph{ base, fragment };
    var session: sema.Session = undefined;
    try session.init(a, modules[0..1], .{});
    defer session.deinit();
    try session.advance();
    try session.appendModuleFragment(&modules, @enumFromInt(0));
    try session.advance();
    var result = try session.finish();
    defer result.graph.deinit(a);
    const functions = try result.graph.functionsNamed(a, "answer");
    try std.testing.expectEqual(@as(usize, 1), functions.len);
    var scratch = std.heap.ArenaAllocator.init(a);
    defer scratch.deinit();
    var diagnostics = diagnostics_mod.Diagnostics.init(&a, &.{});
    defer diagnostics.deinit();
    var safety = @import("../safety/checker.zig").SafetyChecker.init(scratch.allocator(), &diagnostics, &result.graph);
    defer safety.deinit();
    try safety.analyze();
    var lower = try @import("../../5_codegen/bytecode/lower.zig").Lower.init(scratch.allocator(), &result.graph);
    const program = try lower.compile(functions[0]);
    var vm = try @import("../../execution/vm.zig").Vm.init(a, program, .{});
    defer vm.deinit();
    try std.testing.expectEqual(@as(i128, 42), (try vm.invoke(functions[0], &.{}))[0].integer);
}

fn appendFragmentWithAllocationFailures(allocator: std.mem.Allocator, modules: *const [2]module.ModuleSemanticGraph) !void {
    var session: sema.Session = undefined;
    try session.init(allocator, modules[0..1], .{});
    defer session.deinit();
    try session.advance();
    try session.appendModuleFragment(modules, @enumFromInt(0));
    try session.advance();
    var result = try session.finish();
    defer result.graph.deinit(allocator);
    try std.testing.expectEqual(@as(g.GlobalModuleId, @enumFromInt(0)), result.graph.moduleNamespace(@enumFromInt(1)));
}

test "module fragments release failed extension construction" {
    const a = std.testing.allocator;
    var base = try build(a, "/project/pkg/base.rg", "");
    defer base.deinit(a);
    var fragment = try build(a, "/project/pkg/selected.rg", "work := () -> () {}");
    defer fragment.deinit(a);
    const modules = [_]module.ModuleSemanticGraph{ base, fragment };
    try std.testing.checkAllAllocationFailures(a, appendFragmentWithAllocationFailures, .{&modules});
}

test "module fragment candidates preserve namespaces without publishing rejected tails" {
    const a = std.testing.allocator;
    var base = try build(a, "/project/pkg/base.rg", "before := () -> () {}");
    defer base.deinit(a);
    var fragment = try build(a, "/project/pkg/selected.rg", "after := () -> () { before() }");
    defer fragment.deinit(a);
    const modules = [_]module.ModuleSemanticGraph{ base, fragment };
    var session: sema.Session = undefined;
    try session.init(a, modules[0..1], .{});
    defer session.deinit();
    try session.advance();
    var candidate: sema.Session = undefined;
    try session.fork(&candidate, a, null);
    defer candidate.deinit();
    try candidate.appendModuleFragment(&modules, @enumFromInt(0));
    try candidate.advance();
    try std.testing.expectEqual(@as(usize, 1), session.relocation.graph.modules.items.len);
    try std.testing.expectEqual(@as(usize, 2), candidate.relocation.graph.modules.items.len);
    var publication: sema.Session = undefined;
    try candidate.fork(&publication, a, null);
    defer publication.deinit();
    try std.testing.expect(publication.resolvers.core.sameDeclarationNamespace(0, 1));
    var checked = try publication.finish();
    defer checked.graph.deinit(a);
    try std.testing.expect(checked.graph.sameModuleNamespace(@enumFromInt(0), @enumFromInt(1)));
}
