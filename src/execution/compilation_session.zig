const std = @import("std");
const sema = @import("../4_semantics/global/semantizer.zig");
const module_sg = @import("../4_semantics/module/graph.zig");
const diagnostics_mod = @import("../1_base/diagnostic.zig");
const bytecode = @import("../5_codegen/bytecode/bytecode.zig");
var next_namespace = std.atomic.Value(u64).init(0);

fn allocateNamespace() !bytecode.SessionNamespace {
    var next = next_namespace.load(.monotonic);
    while (true) {
        if (next == std.math.maxInt(u64)) return error.CompilationNamespaceLimit;
        next = next_namespace.cmpxchgWeak(next, next + 1, .monotonic, .monotonic) orelse return @enumFromInt(next);
    }
}

const once_verify = @import("../4_semantics/global/once_verify.zig");

const Safety = @import("../4_semantics/safety/checker.zig").SafetyChecker;

// Immutable facts can refer to preceding accepted facts. Each candidate owns
// its new arena and retains the parent proof; rejection releases only its tail.
const TemporalProof = struct {
    allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    state: Safety.ContinuationState = undefined,
    once: once_verify.Uses = undefined,
    parent: ?*TemporalProof,
    references: usize = 1,

    fn create(allocator: std.mem.Allocator, parent: ?*TemporalProof) !*TemporalProof {
        const proof = try allocator.create(TemporalProof);
        errdefer allocator.destroy(proof);
        proof.* = .{ .allocator = allocator, .arena = .init(allocator), .parent = parent };
        errdefer proof.arena.deinit();
        proof.once = if (parent) |previous| try previous.once.cloneWithAllocator(proof.arena.allocator()) else once_verify.Uses.init(proof.arena.allocator());
        errdefer proof.once.deinit();
        if (parent) |previous| {
            if (previous.references == std.math.maxInt(usize)) return error.TemporalProofLimit;
            try previous.state.fork(&proof.state, proof.arena.allocator());
            previous.references += 1;
        } else proof.state.init(proof.arena.allocator());
        return proof;
    }
    fn release(initial: *TemporalProof) void {
        var current: ?*TemporalProof = initial;
        while (current) |proof| {
            proof.references -= 1;
            if (proof.references != 0) return;
            current = proof.parent;
            proof.state.deinit();
            proof.once.deinit();
            proof.arena.deinit();
            const allocator = proof.allocator;
            allocator.destroy(proof);
        }
    }
};

pub const Version = struct {
    graph: @import("../4_semantics/global/graph.zig").GlobalSemanticGraph,
    stats: sema.Stats,
    // Non-continuation snapshots own all facts/annotations from their proof.
    // Continuation facts instead live in the retained TemporalProof chain.
    safety_arena: ?std.heap.ArenaAllocator = null,

    fn deinit(self: *Version, allocator: std.mem.Allocator) void {
        self.graph.deinit(allocator);
        if (self.safety_arena) |*arena| arena.deinit();
        self.* = undefined;
    }
};

/// Retains accepted semantic construction and immutable checked graph versions.
/// Initialize in final storage before preparing candidates. ModuleSG prefixes
/// and their immutable source metadata are borrowed and must outlive this owner.
/// VM storage and execution are separate: preparing a candidate executes no
/// submission body, although explicit compile-time requests may be evaluated.
pub const CompilationSession = struct {
    allocator: std.mem.Allocator,
    semantic: *sema.Session,
    versions: std.ArrayList(*Version) = .empty,
    revision: u64 = 0,
    namespace: bytecode.SessionNamespace,
    temporal: ?*TemporalProof = null,

    pub const Candidate = struct {
        allocator: std.mem.Allocator,
        owner: *const CompilationSession,
        revision: u64,
        semantic: ?*sema.Session,
        checked: ?*Version,
        temporal: ?*TemporalProof = null,
        is_exit: bool = false,
        entry: ?@import("../4_semantics/global/graph.zig").GlobalFunctionId = null,

        pub fn deinit(self: *Candidate) void {
            if (self.temporal) |proof| proof.release();
            if (self.checked) |checked| {
                checked.deinit(self.allocator);
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
        return .{ .allocator = allocator, .semantic = semantic, .namespace = try allocateNamespace() };
    }

    pub fn deinit(self: *CompilationSession) void {
        if (self.temporal) |proof| proof.release();
        for (self.versions.items) |version| {
            version.deinit(self.allocator);
            self.allocator.destroy(version);
        }
        self.versions.deinit(self.allocator);
        self.semantic.deinit();
        self.allocator.destroy(self.semantic);
        self.* = undefined;
    }

    pub fn prepare(self: *const CompilationSession, modules: []const module_sg.ModuleSemanticGraph, diagnostics: *diagnostics_mod.Diagnostics) !Candidate {
        return self.prepareImpl(modules, diagnostics, null, null, false);
    }

    /// Prepare a checked input/output-free command with the accepted temporal
    /// state. The source coordinator supplies its finalized command scope.
    pub fn prepareContinuation(self: *const CompilationSession, modules: []const module_sg.ModuleSemanticGraph, diagnostics: *diagnostics_mod.Diagnostics, function: @import("../4_semantics/global/graph.zig").GlobalFunctionId) !Candidate {
        return self.prepareImpl(modules, diagnostics, function, null, false);
    }

    /// The loader supplies an empty command scope. Cleanup is selected from
    /// accepted ownership evidence and checked against accepted temporal facts.
    pub fn prepareExit(self: *const CompilationSession, modules: []const module_sg.ModuleSemanticGraph, diagnostics: *diagnostics_mod.Diagnostics, function: @import("../4_semantics/global/graph.zig").GlobalFunctionId, bindings: []const @import("../4_semantics/global/graph.zig").GlobalBindingId) !Candidate {
        return self.prepareImpl(modules, diagnostics, function, bindings, false);
    }

    /// Export declarations from explicitly submitted definition modules into
    /// the interactive namespace. Imported ordinary modules retain their normal
    /// visibility. The source coordinator appends dependencies first and the
    /// submitted definition module last.
    pub fn prepareDefinitions(self: *const CompilationSession, modules: []const module_sg.ModuleSemanticGraph, diagnostics: *diagnostics_mod.Diagnostics) !Candidate {
        return self.prepareImpl(modules, diagnostics, null, null, true);
    }

    fn prepareImpl(self: *const CompilationSession, modules: []const module_sg.ModuleSemanticGraph, diagnostics: *diagnostics_mod.Diagnostics, continuation: ?@import("../4_semantics/global/graph.zig").GlobalFunctionId, exit_bindings: ?[]const @import("../4_semantics/global/graph.zig").GlobalBindingId, definitions: bool) !Candidate {
        if (diagnostics.hasErrors()) return error.Reported;
        const candidate = try self.allocator.create(sema.Session);
        errdefer self.allocator.destroy(candidate);
        try self.semantic.fork(candidate, self.allocator, diagnostics);
        errdefer candidate.deinit();
        const previous_modules = candidate.modules.len;
        if (modules.len < previous_modules) return error.InvalidSemanticModuleViews;
        // A source batch ends with its submission module. Earlier new modules
        // are ordinary dependencies, not interactive namespace participants.
        if ((definitions or continuation != null) and modules.len > previous_modules) {
            const namespace = try candidate.resolvers.core.sessionNamespace();
            try namespace.modules.append(self.allocator, @enumFromInt(modules.len - 1));
        }
        try candidate.appendModules(modules);
        if (definitions and modules.len > previous_modules) {
            const graph = &candidate.relocation.graph;
            const exported = &(try candidate.resolvers.core.sessionNamespace()).declarations;
            for (graph.modules.items[modules.len - 1 ..], modules.len - 1..) |module, module_index| {
                declarations: for (module.declarations.start..module.declarations.start + module.declarations.len) |raw| {
                    const declaration = graph.declarations.items[raw];
                    if (declaration.kind != .function and declaration.kind != .type and declaration.kind != .contract_type and declaration.kind != .import_alias) continue;
                    // Inline implementation bodies have private identities, not
                    // source-level names to export or compare across submissions.
                    for (modules[module_index].semantic.parameterized_storage.contract_operations.items) |operation| {
                        if (operation.function == .module and @intFromEnum(operation.function.module) == raw - module.declarations.start)
                            continue :declarations;
                    }
                    const name = graph.text(declaration.name);
                    for (exported.items) |previous| if (std.mem.eql(u8, graph.text(graph.declaration(previous).name), name)) return error.DuplicateSessionDeclaration;
                    for (candidate.resolvers.expressions.session_bindings.items) |binding| if (std.mem.eql(u8, graph.text(graph.binding(binding).name), name)) return error.DuplicateSessionDeclaration;
                    try exported.append(self.allocator, @enumFromInt(raw));
                }
            }
        }
        if (continuation) |function| {
            if (exit_bindings) |bindings| try candidate.prepareExitScope(function, bindings) else try candidate.prepareContinuationScope(function);
        }
        try candidate.advance();
        if (continuation) |function| try candidate.retainContinuationBindings(function);
        const proof = if (continuation != null) try TemporalProof.create(self.allocator, self.temporal) else null;
        errdefer if (proof) |owned| owned.release();
        var checked = try checkedSnapshot(candidate, self.allocator, diagnostics, continuation, proof);
        errdefer checked.deinit(self.allocator);
        const version = try self.allocator.create(Version);
        version.* = checked;
        return .{ .allocator = self.allocator, .owner = self, .revision = self.revision, .semantic = candidate, .checked = version, .temporal = proof, .is_exit = exit_bindings != null, .entry = continuation };
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
        if (candidate.temporal) |proof| {
            if (self.temporal) |previous_proof| previous_proof.release();
            self.temporal = proof;
            candidate.temporal = null;
        }
        candidate.semantic = null;
        candidate.checked = null;
        previous.deinit();
        self.allocator.destroy(previous);
    }
};

// Keep mutable construction open for subsequent submissions. Finalization,
// temporal safety annotations and frozen constants belong to this independent
// executable snapshot, using the ordinary compiler's proof and evaluator.
fn checkedSnapshot(semantic: *const sema.Session, allocator: std.mem.Allocator, diagnostics: *diagnostics_mod.Diagnostics, continuation: ?@import("../4_semantics/global/graph.zig").GlobalFunctionId, proof: ?*TemporalProof) !Version {
    var publication: sema.Session = undefined;
    try semantic.fork(&publication, allocator, diagnostics);
    defer publication.deinit();
    var result = try publication.finish();
    errdefer result.graph.deinit(allocator);
    var safety_arena: ?std.heap.ArenaAllocator = if (proof == null) .init(allocator) else null;
    errdefer if (safety_arena) |*arena| arena.deinit();
    const proof_allocator = if (proof) |owned| owned.arena.allocator() else safety_arena.?.allocator();
    var safety = Safety.init(proof_allocator, diagnostics, &result.graph);
    safety.graph_allocator = allocator;
    defer safety.deinit();
    if (continuation) |function| {
        try safety.analyzeContinuation(function, &proof.?.state);
        try once_verify.verifyContinuation(proof_allocator, &result.graph, diagnostics, function, &proof.?.once);
    } else try safety.analyze();
    try @import("comptime.zig").resolve(allocator, &result.graph, diagnostics);
    return .{ .graph = result.graph, .stats = result.stats, .safety_arena = safety_arena };
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
    var independent = try CompilationSession.init(a, &.{}, .{});
    defer independent.deinit();
    const namespace = session.namespace;
    try std.testing.expect(namespace != independent.namespace);
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
    try std.testing.expectEqual(namespace, session.namespace);
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
    const source = "identity := (.value: Int32) -> (.result: Int32) { result = value }\n";
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
    const execution = @import("vm.zig");
    var context = execution.Context.init(a, 1_000_000);
    defer context.deinit();
    var old_vm = try execution.Vm.initShared(a, program, .{}, &context);
    defer old_vm.deinit();
    const previous = try old_vm.invoke(@enumFromInt(0), &.{.{ .integer = 42 }});
    const identity = context.storage.context;
    var current_compiler = try @import("../5_codegen/bytecode/lower.zig").Lower.init(a, &session.versions.items[session.versions.items.len - 1].graph);
    const current_program = try current_compiler.compile(@enumFromInt(0));
    var current_vm = try execution.Vm.initShared(a, current_program, .{}, &context);
    defer current_vm.deinit();
    const result = try current_vm.invoke(@enumFromInt(0), previous);
    try std.testing.expectEqual(@as(i128, 42), result[0].integer);
    try std.testing.expectEqual(identity, context.storage.context);
}

fn prepareContinuationsWithAllocationFailures(allocator: std.mem.Allocator) !void {
    const a = std.testing.allocator;
    const source = "command := () -> () { helper() }\nhelper := () -> () {}\n";
    const files = [_]@import("../1_base/source_files.zig").SourceFile{.{ .path = "submission/main.rg", .code = source }};
    var diagnostics = diagnostics_mod.Diagnostics.init(&a, &files);
    defer diagnostics.deinit();
    var module = try sourceModule(a, source, &diagnostics);
    defer module.deinit(a);
    const modules = [_]module_sg.ModuleSemanticGraph{module};
    var session = try CompilationSession.init(allocator, &.{}, .{ .exhaustive_function_bodies = false });
    defer session.deinit();
    var first = try session.prepareContinuation(&modules, &diagnostics, @enumFromInt(0));
    defer first.deinit();
    try std.testing.expect(session.temporal == null);
    try std.testing.expect(first.checked.?.graph.functions.items[0].body != null);
    try std.testing.expect(first.checked.?.graph.functions.items[1].body != null);
    try session.accept(&first);
    const accepted = session.temporal.?;
    const revision = session.revision;
    if (session.prepareContinuation(&modules, &diagnostics, @enumFromInt(99))) |unexpected| {
        var owned = unexpected;
        owned.deinit();
        return error.ExpectedInvalidContinuation;
    } else |err| {
        if (err == error.OutOfMemory) return err;
        try std.testing.expectEqual(error.InvalidSafetyContinuation, err);
    }
    try std.testing.expect(session.temporal.? == accepted);
    try std.testing.expectEqual(revision, session.revision);
    var candidate = try session.prepareContinuation(&modules, &diagnostics, @enumFromInt(0));
    defer candidate.deinit();
    try std.testing.expect(candidate.temporal.?.parent.? == accepted);
    try std.testing.expectEqual(@as(usize, 2), accepted.references);
    var stale = try session.prepareContinuation(&modules, &diagnostics, @enumFromInt(0));
    defer stale.deinit();
    try session.accept(&candidate);
    try std.testing.expect(session.temporal.?.parent.? == accepted);
    try std.testing.expectEqual(@as(usize, 2), accepted.references);
    try std.testing.expectError(error.StaleCompilationCandidate, session.accept(&stale));
}

test "compilation session publishes temporal continuations and releases rejected proof tails" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, prepareContinuationsWithAllocationFailures, .{});
}

test "continuation scopes retain direct owners and clean nested owners" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source =
        "Deinit#(.T: Type): Contract = (.deinit: (.self: $&T) -> ())\n" ++
        "Resource: Type = ()\n" ++
        "implement Deinit#(Resource) (.deinit = (.self: $&Resource) -> () {})\n" ++
        "command := () -> () { retained: Resource = ()\n { temporary: Resource = () } }\n" ++
        "exit_command := () -> () {}\n";
    const files = [_]@import("../1_base/source_files.zig").SourceFile{.{ .path = "submission/main.rg", .code = source }};
    var diagnostics = diagnostics_mod.Diagnostics.init(&a, &files);
    defer diagnostics.deinit();
    var module = try sourceModule(a, source, &diagnostics);
    defer module.deinit(a);
    // This isolated fixture supplies its own standard Deinit identity.
    module.is_bundled_core = true;
    const modules = [_]module_sg.ModuleSemanticGraph{module};
    var session = try CompilationSession.init(a, &.{}, .{ .exhaustive_function_bodies = false });
    defer session.deinit();
    // Resolve the command's relocated function identity from its declaration.
    const command = for (module.declarations.items) |declaration| {
        if (std.mem.eql(u8, module.text(declaration.name), "command")) break declaration.function_id.?;
    } else return error.MissingCommand;
    var candidate = try session.prepareContinuation(&modules, &diagnostics, @enumFromInt(@intFromEnum(command)));
    defer candidate.deinit();
    const graph = &candidate.checked.?.graph;
    var persistent_cleanup: usize = 0;
    var temporary_cleanup: usize = 0;
    for (graph.blocks.items) |block| {
        for (graph.node_refs.items[block.nodes.start..][0..block.nodes.len]) |node| {
            if (graph.node(node).content != .auto_deinit_binding) continue;
            const cleanup = graph.auto_deinits.items[@intFromEnum(graph.node(node).content.auto_deinit_binding)];
            const name = graph.text(graph.binding(cleanup.binding).name);
            if (std.mem.eql(u8, name, "retained")) persistent_cleanup += 1;
            if (std.mem.eql(u8, name, "temporary")) temporary_cleanup += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 0), persistent_cleanup);
    try std.testing.expectEqual(@as(usize, 1), temporary_cleanup);
    const binding = for (graph.bindings.items, 0..) |record, index| {
        if (std.mem.eql(u8, graph.text(record.name), "retained")) break @as(@import("../4_semantics/global/graph.zig").GlobalBindingId, @enumFromInt(index));
    } else return error.MissingBinding;
    const exit_function = for (module.declarations.items) |declaration| {
        if (std.mem.eql(u8, module.text(declaration.name), "exit_command")) break declaration.function_id.?;
    } else return error.MissingExitCommand;
    var runtime = @import("session.zig").Session.init(a, &session, .{});
    defer runtime.deinit();
    try runtime.executeCommand(&candidate);
    const stored = try runtime.context.storage.slots(runtime.context.bindings.get(binding).?);
    try std.testing.expect((try stored.get(1)).boolean);
    var exit = try session.prepareExit(&modules, &diagnostics, @enumFromInt(@intFromEnum(exit_function)), &.{binding});
    defer exit.deinit();
    const exit_graph = &exit.checked.?.graph;
    const exit_body = exit_graph.blocks.items[@intFromEnum(exit_graph.functions.items[@intFromEnum(exit_function)].body.?)];
    try std.testing.expect(exit_body.nodes.len != 0);
    const first = exit_graph.node_refs.items[exit_body.nodes.start];
    try std.testing.expect(exit_graph.node(first).content == .auto_deinit_binding);
    try std.testing.expectEqual(binding, exit_graph.auto_deinits.items[@intFromEnum(exit_graph.node(first).content.auto_deinit_binding)].binding);
    try runtime.executeCommand(&exit);
    try std.testing.expectEqual(.fresh, runtime.context.state);
    try std.testing.expectError(error.InvalidSafetyContinuation, session.prepareExit(&modules, &diagnostics, @enumFromInt(@intFromEnum(command)), &.{binding}));
}

test "execution session publishes commands and runs checked exit before reset" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source = "command := () -> () { retained: Int32 = 42 }\nexit_command := () -> () {}\n";
    const files = [_]@import("../1_base/source_files.zig").SourceFile{.{ .path = "submission/main.rg", .code = source }};
    var diagnostics = diagnostics_mod.Diagnostics.init(&a, &files);
    defer diagnostics.deinit();
    var module = try sourceModule(a, source, &diagnostics);
    defer module.deinit(a);
    const modules = [_]module_sg.ModuleSemanticGraph{module};
    var compiler = try CompilationSession.init(a, &.{}, .{ .exhaustive_function_bodies = false });
    defer compiler.deinit();
    var runtime = @import("session.zig").Session.init(a, &compiler, .{});
    defer runtime.deinit();
    var command = try compiler.prepareContinuation(&modules, &diagnostics, @enumFromInt(0));
    defer command.deinit();
    const checked = &command.checked.?.graph;
    const binding = for (checked.bindings.items, 0..) |record, index| {
        if (std.mem.eql(u8, checked.text(record.name), "retained")) break @as(@import("../4_semantics/global/graph.zig").GlobalBindingId, @enumFromInt(index));
    } else return error.MissingBinding;
    const layouts = [_]bytecode.SessionBinding{.{ .binding = binding, .slots = &.{checked.binding(binding).ty} }};
    try std.testing.expectError(error.InvalidExitCommand, runtime.executeExit(&command, @enumFromInt(0), &layouts));
    try std.testing.expectEqual(@as(u64, 0), compiler.revision);
    try runtime.execute(&command, @enumFromInt(0), &layouts);
    try std.testing.expectEqual(@as(u64, 1), compiler.revision);
    const frame = runtime.context.bindings.get(binding).?;
    const stored = try runtime.context.storage.slots(frame);
    try std.testing.expectEqual(@as(i128, 42), (try stored.get(0)).integer);
    var exit = try compiler.prepareExit(&modules, &diagnostics, @enumFromInt(1), &.{binding});
    defer exit.deinit();
    try runtime.executeExit(&exit, @enumFromInt(1), &layouts);
    try std.testing.expectEqual(.fresh, runtime.context.state);
    try std.testing.expectEqual(@as(usize, 0), runtime.context.bindings.count());
    try std.testing.expectEqual(@as(u64, 2), compiler.revision);
}

test "execution session resolves accepted bindings in later command modules" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const first_source = "command := () -> () { retained :: Int32 = 42 }\n";
    const second_source = "update := () -> () { retained = 7 }\n";
    const files = [_]@import("../1_base/source_files.zig").SourceFile{.{ .path = "submission/main.rg", .code = first_source }};
    var diagnostics = diagnostics_mod.Diagnostics.init(&a, &files);
    defer diagnostics.deinit();
    var first = try sourceModule(a, first_source, &diagnostics);
    defer first.deinit(a);
    var second = try sourceModule(a, second_source, &diagnostics);
    defer second.deinit(a);
    const modules = [_]module_sg.ModuleSemanticGraph{ first, second };
    var compiler = try CompilationSession.init(a, &.{}, .{ .exhaustive_function_bodies = false });
    defer compiler.deinit();
    var runtime = @import("session.zig").Session.init(a, &compiler, .{});
    defer runtime.deinit();
    var command = try compiler.prepareContinuation(modules[0..1], &diagnostics, @enumFromInt(0));
    defer command.deinit();
    const binding = command.semantic.?.resolvers.expressions.session_bindings.items[0];
    const layouts = [_]bytecode.SessionBinding{.{ .binding = binding, .slots = &.{command.checked.?.graph.binding(binding).ty} }};
    try runtime.execute(&command, @enumFromInt(0), &layouts);
    var update = try compiler.prepareContinuation(&modules, &diagnostics, @enumFromInt(first.functions.items.len));
    defer update.deinit();
    try runtime.execute(&update, @enumFromInt(first.functions.items.len), &layouts);
    const stored = try runtime.context.storage.slots(runtime.context.bindings.get(binding).?);
    try std.testing.expectEqual(@as(i128, 7), (try stored.get(0)).integer);
}

fn publishDefinitionWithAllocationFailures(allocator: std.mem.Allocator) !void {
    const a = std.testing.allocator;
    const source = "answer := () -> (.result: Int32) { result = 42 }\n";
    var diagnostic_arena = std.heap.ArenaAllocator.init(a);
    defer diagnostic_arena.deinit();
    const diagnostic_allocator = diagnostic_arena.allocator();
    const files = [_]@import("../1_base/source_files.zig").SourceFile{.{ .path = "submission/main.rg", .code = source }};
    var diagnostics = diagnostics_mod.Diagnostics.init(&diagnostic_allocator, &files);
    defer diagnostics.deinit();
    var module = try sourceModule(a, source, &diagnostics);
    defer module.deinit(a);
    var session = try CompilationSession.init(allocator, &.{}, .{});
    defer session.deinit();
    var candidate = try session.prepare(&.{module}, &diagnostics);
    defer candidate.deinit();
    try std.testing.expect(candidate.checked.?.safety_arena != null);
    try session.accept(&candidate);
    try std.testing.expectEqual(@as(usize, 1), session.versions.items.len);
    try std.testing.expect(session.versions.items[0].safety_arena != null);
}

test "definition publication retains safety allocations and releases failure paths" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, publishDefinitionWithAllocationFailures, .{});
}
