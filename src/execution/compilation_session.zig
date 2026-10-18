const std = @import("std");
const sema = @import("../4_semantics/global/semantizer.zig");
const module_sg = @import("../4_semantics/module/graph.zig");
const diagnostics_mod = @import("../1_base/diagnostic.zig");

/// Retains accepted semantic construction and immutable checked graph versions.
/// Initialize in final storage before preparing candidates. ModuleSG prefixes
/// and their immutable source metadata are borrowed and must outlive this owner.
/// VM storage and execution are separate: preparing a candidate executes no
/// submission body, although explicit compile-time requests may be evaluated.
pub const CompilationSession = struct {
    allocator: std.mem.Allocator,
    semantic: *sema.Session,
    versions: std.ArrayList(*sema.Result) = .empty,
    revision: u64 = 0,

    pub const Candidate = struct {
        allocator: std.mem.Allocator,
        owner: *const CompilationSession,
        revision: u64,
        semantic: ?*sema.Session,
        checked: ?*sema.Result,

        pub fn deinit(self: *Candidate) void {
            if (self.checked) |checked| {
                checked.graph.deinit(self.allocator);
                self.allocator.destroy(checked);
            }
            if (self.semantic) |semantic| {
                semantic.deinit();
                self.allocator.destroy(semantic);
            }
            self.* = undefined;
        }
    };

    pub fn init(allocator: std.mem.Allocator, modules: []const module_sg.ModuleSemanticGraph, options: sema.Options) !CompilationSession {
        const semantic = try allocator.create(sema.Session);
        errdefer allocator.destroy(semantic);
        try semantic.init(allocator, modules, options);
        errdefer semantic.deinit();
        try semantic.advance();
        return .{ .allocator = allocator, .semantic = semantic };
    }

    pub fn deinit(self: *CompilationSession) void {
        for (self.versions.items) |version| {
            version.graph.deinit(self.allocator);
            self.allocator.destroy(version);
        }
        self.versions.deinit(self.allocator);
        self.semantic.deinit();
        self.allocator.destroy(self.semantic);
        self.* = undefined;
    }

    pub fn prepare(self: *const CompilationSession, modules: []const module_sg.ModuleSemanticGraph, diagnostics: *diagnostics_mod.Diagnostics) !Candidate {
        if (diagnostics.hasErrors()) return error.Reported;
        const candidate = try self.allocator.create(sema.Session);
        errdefer self.allocator.destroy(candidate);
        try self.semantic.fork(candidate, self.allocator, diagnostics);
        errdefer candidate.deinit();
        try candidate.appendModules(modules);
        try candidate.advance();
        var checked = try checkedSnapshot(candidate, self.allocator, diagnostics);
        errdefer checked.graph.deinit(self.allocator);
        const version = try self.allocator.create(sema.Result);
        version.* = checked;
        return .{ .allocator = self.allocator, .owner = self, .revision = self.revision, .semantic = candidate, .checked = version };
    }

    /// Publish only a checked candidate based on the current accepted revision.
    /// Reserve first: allocation failure leaves both owners unchanged. Retain
    /// older graphs because published bytecode can still borrow their metadata.
    pub fn accept(self: *CompilationSession, candidate: *Candidate) !void {
        if (candidate.owner != self or candidate.revision != self.revision or candidate.semantic == null or candidate.checked == null)
            return error.StaleCompilationCandidate;
        if (self.revision == std.math.maxInt(u64)) return error.CompilationRevisionLimit;
        try self.versions.ensureUnusedCapacity(self.allocator, 1);
        const previous = self.semantic;
        self.semantic = candidate.semantic.?;
        self.versions.appendAssumeCapacity(candidate.checked.?);
        self.revision += 1;
        candidate.semantic = null;
        candidate.checked = null;
        previous.deinit();
        self.allocator.destroy(previous);
    }
};

// Keep mutable construction open for subsequent submissions. Finalization,
// temporal safety annotations and frozen constants belong to this independent
// executable snapshot, using the ordinary compiler's proof and evaluator.
fn checkedSnapshot(semantic: *const sema.Session, allocator: std.mem.Allocator, diagnostics: *diagnostics_mod.Diagnostics) !sema.Result {
    var publication: sema.Session = undefined;
    try semantic.fork(&publication, allocator, diagnostics);
    defer publication.deinit();
    var result = try publication.finish();
    errdefer result.graph.deinit(allocator);
    var safety = @import("../4_semantics/safety/checker.zig").SafetyChecker.init(allocator, diagnostics, &result.graph);
    defer safety.deinit();
    try safety.analyze();
    try @import("comptime.zig").resolve(allocator, &result.graph, diagnostics);
    return result;
}

test "compilation session publishes checked candidates and rejects stale revisions" {
    const a = std.testing.allocator;
    var diagnostics = diagnostics_mod.Diagnostics.init(&a, &.{});
    defer diagnostics.deinit();
    var first: module_sg.ModuleSemanticGraph = .{ .module_dir = try a.dupe(u8, "first") };
    defer first.deinit(a);
    try first.semantic.types.append(a, .{ .resolved = .{ .builtin = .Int32 } });
    var second: module_sg.ModuleSemanticGraph = .{ .module_dir = try a.dupe(u8, "second") };
    defer second.deinit(a);
    try second.semantic.types.append(a, .{ .resolved = .{ .builtin = .UInt8 } });
    const modules = [_]module_sg.ModuleSemanticGraph{ first, second };
    var session = try CompilationSession.init(a, modules[0..1], .{});
    defer session.deinit();
    var candidate = try session.prepare(&modules, &diagnostics);
    defer candidate.deinit();
    var stale = try session.prepare(&modules, &diagnostics);
    defer stale.deinit();
    try std.testing.expectEqual(@as(usize, 1), session.semantic.modules.len);
    try std.testing.expectEqual(@as(u64, 0), session.revision);
    try session.accept(&candidate);
    try std.testing.expectEqual(@as(usize, 2), session.semantic.modules.len);
    try std.testing.expectEqual(@as(u64, 1), session.revision);
    try std.testing.expectEqual(@as(usize, 1), session.versions.items.len);
    try std.testing.expectError(error.StaleCompilationCandidate, session.accept(&stale));
    try std.testing.expectError(error.StaleCompilationCandidate, session.accept(&candidate));
    var next = try session.prepare(&modules, &diagnostics);
    defer next.deinit();
    try session.accept(&next);
    try std.testing.expectEqual(@as(usize, 2), session.versions.items.len);
    try std.testing.expectEqual(@as(usize, 2), session.versions.items[0].graph.modules.items.len);
    try std.testing.expectEqual(@as(u64, 2), session.revision);
}

fn sourceModule(allocator: std.mem.Allocator, source: []const u8, diagnostics: *diagnostics_mod.Diagnostics) !module_sg.ModuleSemanticGraph {
    var tokenizer = @import("../2_tokens/tokenizer.zig").Tokenizer.init(allocator, diagnostics, source, @enumFromInt(0));
    defer tokenizer.deinit();
    _ = try tokenizer.tokenize();
    var syntaxer = @import("../3_syntax/syntaxer.zig").Syntaxer.initFile(allocator, @import("../3_syntax/syntax_tree.zig").FileSyntaxTree.initOwnedTokens(@enumFromInt(0), tokenizer.takeTokens()), source, diagnostics);
    defer syntaxer.deinit();
    var tree = try syntaxer.parse();
    defer tree.deinit(allocator);
    return (try @import("../4_semantics/module/semantizer.zig").build(allocator, "submission", &.{.{ .path = "submission/main.rg", .tree = &tree, .source = source }})).graph;
}

test "compilation session rejects unsafe source without publishing definitions" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source = "escape := () -> (.result: &Int32) { value ::= 7\n result = &value }\n";
    const files = [_]@import("../1_base/source_files.zig").SourceFile{.{ .path = "submission/main.rg", .code = source }};
    var diagnostics = diagnostics_mod.Diagnostics.init(&a, &files);
    defer diagnostics.deinit();
    var module = try sourceModule(a, source, &diagnostics);
    defer module.deinit(a);
    var session = try CompilationSession.init(a, &.{}, .{});
    defer session.deinit();
    const saved = session.semantic.relocation.graph.checkpoint();
    try std.testing.expectError(error.Reported, session.prepare(&.{module}, &diagnostics));
    try std.testing.expect(diagnostics.hasErrors());
    var local_escape = false;
    for (diagnostics.list.items) |diagnostic| {
        if (std.mem.indexOf(u8, diagnostic.msg, "function output cannot depend on a local storage generation") != null) local_escape = true;
    }
    try std.testing.expect(local_escape);
    try std.testing.expectEqualDeep(saved, session.semantic.relocation.graph.checkpoint());
    try std.testing.expectEqual(@as(u64, 0), session.revision);
    try std.testing.expectEqual(@as(usize, 0), session.versions.items.len);
    diagnostics.list.clearRetainingCapacity();
    var retry = try session.prepare(&.{}, &diagnostics);
    defer retry.deinit();
    try session.accept(&retry);
    try std.testing.expectEqual(@as(u64, 1), session.revision);
}

fn prepareWithAllocationFailures(allocator: std.mem.Allocator) !void {
    const a = std.testing.allocator;
    var diagnostics = diagnostics_mod.Diagnostics.init(&a, &.{});
    defer diagnostics.deinit();
    var module: module_sg.ModuleSemanticGraph = .{ .module_dir = try a.dupe(u8, "candidate") };
    defer module.deinit(a);
    try module.semantic.types.append(a, .{ .resolved = .{ .builtin = .Int32 } });
    var session = try CompilationSession.init(allocator, &.{}, .{});
    defer session.deinit();
    var candidate = try session.prepare(&.{module}, &diagnostics);
    defer candidate.deinit();
    session.accept(&candidate) catch |err| {
        try std.testing.expectEqual(@as(u64, 0), session.revision);
        try std.testing.expectEqual(@as(usize, 0), session.versions.items.len);
        try std.testing.expectEqual(@as(usize, 0), session.semantic.modules.len);
        try std.testing.expect(candidate.semantic != null and candidate.checked != null);
        return err;
    };
    try std.testing.expectEqual(@as(u64, 1), session.revision);
    try std.testing.expectEqual(@as(usize, 1), session.versions.items.len);
    try std.testing.expect(candidate.semantic == null and candidate.checked == null);
}

test "compilation session preparation and acceptance release allocation failures" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, prepareWithAllocationFailures, .{});
}

test "compilation session retains executable graph addresses across publications" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source = "answer := () -> (.result: Int32) { result = 42 }\n";
    const files = [_]@import("../1_base/source_files.zig").SourceFile{.{ .path = "submission/main.rg", .code = source }};
    var diagnostics = diagnostics_mod.Diagnostics.init(&a, &files);
    defer diagnostics.deinit();
    var module = try sourceModule(a, source, &diagnostics);
    defer module.deinit(a);
    const modules = [_]module_sg.ModuleSemanticGraph{module};
    var session = try CompilationSession.init(a, &.{}, .{});
    defer session.deinit();
    var first = try session.prepare(&modules, &diagnostics);
    defer first.deinit();
    try session.accept(&first);
    const graph = &session.versions.items[0].graph;
    var compiler = try @import("../5_codegen/bytecode/lower.zig").Lower.init(a, graph);
    const program = try compiler.compile(@enumFromInt(0));
    // Force several version-table reallocations after bytecode captured graph.
    for (0..12) |_| {
        var next = try session.prepare(&modules, &diagnostics);
        defer next.deinit();
        try session.accept(&next);
    }
    try std.testing.expect(graph == &session.versions.items[0].graph);
    var vm = try @import("vm.zig").Vm.init(a, program, .{});
    defer vm.deinit();
    const result = try vm.invoke(@enumFromInt(0), &.{});
    try std.testing.expectEqual(@as(i128, 42), result[0].integer);
}
