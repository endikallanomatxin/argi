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

// Candidate analysis can borrow preceding facts. Publication copies only its
// final fact graph and then releases that temporary parent dependency.
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
    // Retain only the final state, independently of parents and scratch facts.
    // The caller must first move graph annotations into graph-owned storage.
    fn seal(self: *TemporalProof, scratch: std.mem.Allocator) !void {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        errdefer arena.deinit();
        var state: Safety.ContinuationState = undefined;
        try self.state.snapshot(&state, arena.allocator(), scratch);
        errdefer state.deinit();
        var once = try self.once.cloneWithAllocator(arena.allocator());
        errdefer once.deinit();
        self.state.deinit();
        self.once.deinit();
        self.arena.deinit();
        self.arena = arena;
        self.state = state;
        self.state.rebindAllocator(self.arena.allocator());
        self.once = once;
        self.once.allocator = self.arena.allocator();
        const previous = self.parent;
        self.parent = null;
        if (previous) |parent| parent.release();
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
    unit: ?@import("../4_semantics/global/reachability.zig").FunctionSet = null,

    fn deinit(self: *Version, allocator: std.mem.Allocator) void {
        if (self.unit) |*unit| unit.deinit();
        self.graph.deinit(allocator);
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

    /// Unpublished construction state for source loading and staged selection. It
    /// cannot execute or publish until ordinary finalization produces a Candidate.
    pub const Draft = struct {
        owner: *const CompilationSession,
        revision: u64,
        semantic: ?*sema.Session,

        pub fn deinit(self: *Draft) void {
            if (self.semantic) |semantic| {
                semantic.deinit();
                self.owner.allocator.destroy(semantic);
            }
            self.* = undefined;
        }

        pub fn finishDefinitions(self: *Draft, modules: []const module_sg.ModuleSemanticGraph, diagnostics: *diagnostics_mod.Diagnostics) !Candidate {
            return self.owner.finishPreparation(self, modules, diagnostics, null, null, true);
        }
    };

    pub fn beginPreparation(self: *const CompilationSession, diagnostics: *diagnostics_mod.Diagnostics) !Draft {
        if (diagnostics.hasErrors()) return error.Reported;
        const semantic = try self.allocator.create(sema.Session);
        errdefer self.allocator.destroy(semantic);
        try self.semantic.fork(semantic, self.allocator, diagnostics);
        return .{ .owner = self, .revision = self.revision, .semantic = semantic };
    }

    pub fn init(allocator: std.mem.Allocator, modules: []const module_sg.ModuleSemanticGraph, options: sema.Options) !CompilationSession {
        const semantic = try allocator.create(sema.Session);
        errdefer allocator.destroy(semantic);
        try semantic.init(allocator, modules, options);
        errdefer semantic.deinit();
        try semantic.advance();
        return .{ .allocator = allocator, .semantic = semantic, .namespace = try allocateNamespace() };
    }

    /// Fork a prepared module template, retaining its graph identities and
    /// lexical namespaces. The template's borrowed modules must outlive us.
    pub fn initPrepared(allocator: std.mem.Allocator, template: *const sema.Session, diagnostics: *diagnostics_mod.Diagnostics) !CompilationSession {
        const semantic = try allocator.create(sema.Session);
        errdefer allocator.destroy(semantic);
        try template.fork(semantic, allocator, diagnostics);
        errdefer semantic.deinit();
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
        var draft = try self.beginPreparation(diagnostics);
        defer draft.deinit();
        return self.finishPreparation(&draft, modules, diagnostics, continuation, exit_bindings, definitions);
    }

    fn finishPreparation(self: *const CompilationSession, draft: *Draft, modules: []const module_sg.ModuleSemanticGraph, diagnostics: *diagnostics_mod.Diagnostics, continuation: ?@import("../4_semantics/global/graph.zig").GlobalFunctionId, exit_bindings: ?[]const @import("../4_semantics/global/graph.zig").GlobalBindingId, definitions: bool) !Candidate {
        if (diagnostics.hasErrors()) return error.Reported;
        if (draft.owner != self or draft.revision != self.revision) return error.StaleCompilationCandidate;
        const candidate = draft.semantic orelse return error.StaleCompilationCandidate;
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
        draft.semantic = null;
        return .{ .allocator = self.allocator, .owner = self, .revision = self.revision, .semantic = candidate, .checked = version, .temporal = proof, .is_exit = exit_bindings != null, .entry = continuation };
    }

    /// Publish only a checked candidate based on the current accepted revision.
    /// Reserve first: allocation failure leaves both owners unchanged. Retain
    /// older graphs because published bytecode can still borrow their metadata.
    pub fn accept(self: *CompilationSession, candidate: *Candidate) !void {
        return self.acceptChecked(candidate, .retain);
    }

    /// Publish checked semantic definitions without retaining an executable
    /// snapshot. No bytecode or external reader may borrow candidate.checked
    /// after this call. Previously retained executable graphs stay unchanged.
    pub fn acceptDefinitions(self: *CompilationSession, candidate: *Candidate) !void {
        if (candidate.entry != null or candidate.temporal != null or candidate.is_exit) return error.InvalidDefinitionCandidate;
        return self.acceptChecked(candidate, .discard);
    }

    fn acceptChecked(self: *CompilationSession, candidate: *Candidate, snapshot: enum { retain, discard }) !void {
        if (candidate.owner != self or candidate.revision != self.revision or candidate.semantic == null or candidate.checked == null)
            return error.StaleCompilationCandidate;
        if (self.revision == std.math.maxInt(u64)) return error.CompilationRevisionLimit;
        if (snapshot == .retain) try self.versions.ensureUnusedCapacity(self.allocator, 1);
        // Every fallible publication step has succeeded. Nested speculation
        // is closed, so accepted bodies no longer need their undo entries.
        candidate.semantic.?.relocation.graph.commitCompletions(self.allocator);
        const previous = self.semantic;
        self.semantic = candidate.semantic.?;
        if (snapshot == .retain) {
            self.versions.appendAssumeCapacity(candidate.checked.?);
        } else {
            const checked = candidate.checked.?;
            checked.deinit(self.allocator);
            self.allocator.destroy(checked);
        }
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
    errdefer result.deinit(allocator);
    var temporary = std.heap.ArenaAllocator.init(allocator);
    defer temporary.deinit();
    // Rejected analysis can leave its candidate tables in scratch storage.
    // Dispose them while that storage is alive; the caller then releases the
    // candidate's own arena and its retained parent in the ordinary error path.
    errdefer if (proof) |owned| {
        owned.state.deinit();
        owned.state.init(owned.arena.allocator());
    };
    const proof_allocator = temporary.allocator();
    if (proof) |owned| {
        // All mutable tables and namespace growth during checking use one
        // allocator. Immutable incoming facts remain borrowed until sealing.
        var working: Safety.ContinuationState = undefined;
        try owned.state.fork(&working, proof_allocator);
        owned.state.deinit();
        owned.state = working;
        owned.state.rebindAllocator(proof_allocator);
    }
    var safety = Safety.init(proof_allocator, diagnostics, &result.graph);
    safety.graph_allocator = allocator;
    safety.unit = if (result.unit) |*unit| unit else null;
    defer safety.deinit();
    if (continuation) |function| {
        const command = result.graph.function(function);
        // Ordinary helpers may forward an unresolved reached capability as a
        // logical input. A top-level command has no caller to supply it.
        if (command.input.len != 0) {
            const field = result.graph.fields.items[command.input.start];
            const source = result.graph.declaration(command.declaration).source;
            try diagnostics.add(@import("../4_semantics/global/source_location.zig").location(&result.graph, diagnostics, source), .semantic, "interactive command requires input '.{s}'; pass it explicitly or bind the required capability with assume before the call", .{result.graph.text(field.name)});
            return error.Reported;
        }
        try safety.analyzeContinuation(function, &proof.?.state);
        try once_verify.verifyContinuation(proof_allocator, &result.graph, diagnostics, function, &proof.?.once);
    } else try safety.analyze();
    try @import("comptime.zig").resolve(allocator, &result.graph, diagnostics);
    {
        // Checked calls outlive this analysis and can be used by older virtual
        // code units. Their annotation buffers belong to this graph version.
        var copy: @import("../4_semantics/safety/fact_snapshot.zig").Copy = .{
            .allocator = try result.graph.safetyAllocator(allocator),
            .scratch = temporary.allocator(),
        };
        defer copy.deinit();
        for (result.graph.nodes.items) |*node| if (node.content == .function_call) {
            node.content.function_call = try copy.value(@TypeOf(node.content.function_call), node.content.function_call);
        };
        for (result.graph.virtual_calls.items) |*call| call.* = try copy.value(@TypeOf(call.*), call.*);
    }
    if (proof) |owned| try owned.seal(temporary.allocator());
    result.graph.trimPoolCapacity(allocator);
    return .{ .graph = result.graph, .stats = result.stats, .unit = result.unit };
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
    var stale_draft = try session.beginPreparation(&diagnostics);
    defer stale_draft.deinit();
    try std.testing.expectEqual(@as(usize, 1), session.semantic.modules.len);
    try std.testing.expectEqual(@as(u64, 0), session.revision);
    try session.accept(&candidate);
    try std.testing.expectEqual(@as(usize, 2), session.semantic.modules.len);
    try std.testing.expectEqual(@as(u64, 1), session.revision);
    try std.testing.expectEqual(@as(usize, 1), session.versions.items.len);
    try std.testing.expectError(error.StaleCompilationCandidate, session.accept(&stale));
    try std.testing.expectError(error.StaleCompilationCandidate, stale_draft.finishDefinitions(&modules, &diagnostics));
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
    try std.testing.expectError(error.InvalidDefinitionCandidate, session.acceptDefinitions(&first));
    try std.testing.expectEqual(@as(u64, 0), session.revision);
    try std.testing.expect(session.temporal == null);
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
    try std.testing.expect(candidate.temporal.?.parent == null);
    try std.testing.expectEqual(@as(usize, 1), accepted.references);
    var stale = try session.prepareContinuation(&modules, &diagnostics, @enumFromInt(0));
    defer stale.deinit();
    const next_proof = candidate.temporal.?;
    try session.accept(&candidate);
    try std.testing.expect(session.temporal.? == next_proof);
    try std.testing.expect(session.temporal.?.parent == null);
    try std.testing.expect(stale.temporal.?.parent == null);
    try std.testing.expectEqual(@as(usize, 1), session.temporal.?.references);
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
            const name = graph.text(graph.binding(cleanup.ownerBinding().?).name);
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
    const stored = runtime.context.storage.frames.items[@intFromEnum(runtime.context.bindings.get(binding).?)];
    try std.testing.expect(stored.cleanup_flags[0]);
    var exit = try session.prepareExit(&modules, &diagnostics, @enumFromInt(@intFromEnum(exit_function)), &.{binding});
    defer exit.deinit();
    const exit_graph = &exit.checked.?.graph;
    const exit_body = exit_graph.blocks.items[@intFromEnum(exit_graph.functions.items[@intFromEnum(exit_function)].body.?)];
    try std.testing.expect(exit_body.nodes.len != 0);
    const first = exit_graph.node_refs.items[exit_body.nodes.start];
    try std.testing.expect(exit_graph.node(first).content == .auto_deinit_binding);
    try std.testing.expectEqual(binding, exit_graph.auto_deinits.items[@intFromEnum(exit_graph.node(first).content.auto_deinit_binding)].ownerBinding().?);
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
    const layouts = [_]bytecode.SessionBinding{.{ .binding = binding, .ty = checked.binding(binding).ty }};
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
    const layouts = [_]bytecode.SessionBinding{.{ .binding = binding, .ty = command.checked.?.graph.binding(binding).ty }};
    try runtime.execute(&command, @enumFromInt(0), &layouts);
    var update = try compiler.prepareContinuation(&modules, &diagnostics, @enumFromInt(first.functions.items.len));
    defer update.deinit();
    try runtime.execute(&update, @enumFromInt(first.functions.items.len), &layouts);
    const stored = try runtime.context.storage.slots(runtime.context.bindings.get(binding).?);
    try std.testing.expectEqual(@as(i128, 7), (try stored.get(0)).integer);
}

fn publishDefinitionWithAllocationFailures(allocator: std.mem.Allocator, retain: bool) !void {
    const a = std.testing.allocator;
    const source =
        "Deinit#(.T: Type): Contract = (.deinit: (.self: $&T) -> ())\n" ++
        "Resource: Type = ()\n" ++
        "implement Deinit#(Resource) (.deinit = (.self: $&Resource) -> () {})\n" ++
        "answer := () -> () { resource: Resource = ()\n deinit(.self = $&resource) }\n";
    var diagnostic_arena = std.heap.ArenaAllocator.init(a);
    defer diagnostic_arena.deinit();
    const diagnostic_allocator = diagnostic_arena.allocator();
    const files = [_]@import("../1_base/source_files.zig").SourceFile{.{ .path = "submission/main.rg", .code = source }};
    var diagnostics = diagnostics_mod.Diagnostics.init(&diagnostic_allocator, &files);
    defer diagnostics.deinit();
    var module = try sourceModule(a, source, &diagnostics);
    defer module.deinit(a);
    module.is_bundled_core = true;
    var session = try CompilationSession.init(allocator, &.{}, .{});
    defer session.deinit();
    var candidate = try session.prepare(&.{module}, &diagnostics);
    defer candidate.deinit();
    try std.testing.expect(candidate.checked != null);
    const graph = &candidate.checked.?.graph;
    var consumed: usize = 0;
    for (graph.nodes.items) |node| if (node.content == .function_call) {
        for (node.content.function_call.consumed_auto_deinits) |cleanup| {
            _ = graph.node(cleanup);
            consumed += 1;
        }
    };
    try std.testing.expect(consumed != 0);
    if (retain) try session.accept(&candidate) else try session.acceptDefinitions(&candidate);
    try std.testing.expectEqual(@as(usize, if (retain) 1 else 0), session.versions.items.len);
    try std.testing.expectEqual(@as(u64, 1), session.revision);
    try std.testing.expect(session.semantic.relocation.graph.functions.items.len != 0);
}

test "definition publication owns checked annotations and releases failure paths" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, publishDefinitionWithAllocationFailures, .{true});
}

test "semantic-only definition publication releases checked graphs and failure paths" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, publishDefinitionWithAllocationFailures, .{false});
}

test "unit selection retains dormant bodies and checks them when selected later" {
    const a = std.testing.allocator;
    var diagnostic_arena = std.heap.ArenaAllocator.init(a);
    defer diagnostic_arena.deinit();
    const diagnostic_allocator = diagnostic_arena.allocator();
    var diagnostics = diagnostics_mod.Diagnostics.init(&diagnostic_allocator, &.{});
    defer diagnostics.deinit();
    var module = try sourceModule(a,
        \\unused := () -> (.result: &Int32) {
        \\    local :: Int32 = 7
        \\    result = &local
        \\}
        \\main := () -> (.status_code: Int32) { status_code = 0 }
    , &diagnostics);
    defer module.deinit(a);
    var session = try CompilationSession.init(a, &.{module}, .{ .diagnostics = &diagnostics, .exhaustive_function_bodies = false });
    defer session.deinit();
    var candidate = try session.prepare(&.{module}, &diagnostics);
    defer candidate.deinit();
    const checked = candidate.checked.?;
    var dormant: ?@import("../4_semantics/global/graph.zig").GlobalFunctionId = null;
    for (checked.graph.functions.items, 0..) |function, index| {
        if (!std.mem.eql(u8, checked.graph.text(checked.graph.declaration(function.declaration).name), "unused")) continue;
        dormant = @enumFromInt(index);
        try std.testing.expect(function.body != null);
        try std.testing.expect(!checked.unit.?.contains(dormant.?));
    }
    try std.testing.expect(dormant != null);
    try std.testing.expect(!diagnostics.hasErrors());
    try session.accept(&candidate);
    var draft = try session.beginPreparation(&diagnostics);
    defer draft.deinit();
    try draft.semantic.?.includeExecutionRoot(dormant.?);
    try std.testing.expectError(error.Reported, draft.finishDefinitions(&.{module}, &diagnostics));
    try std.testing.expect(diagnostics.hasErrors());
    try std.testing.expect(session.semantic.relocation.graph.function(dormant.?).body != null);
    try std.testing.expect(!session.versions.items[0].unit.?.contains(dormant.?));
}

test "unit selection preserves pending binding types for later materialization" {
    const a = std.testing.allocator;
    var diagnostics = diagnostics_mod.Diagnostics.init(&a, &.{});
    defer diagnostics.deinit();
    var module = try sourceModule(a,
        \\identity#(.T: Type) := (.value: T) -> (.result: T) { result = value }
        \\helper := () -> (.result: Int32) {
        \\    local ::= identity#(.T: Int32)(.value = 7)
        \\    result = local
        \\}
        \\main := () -> (.status_code: Int32) { status_code = 0 }
    , &diagnostics);
    defer module.deinit(a);
    var session = try CompilationSession.init(a, &.{module}, .{ .diagnostics = &diagnostics, .exhaustive_function_bodies = false });
    defer session.deinit();
    var candidate = try session.prepare(&.{module}, &diagnostics);
    defer candidate.deinit();
    const checked = candidate.checked.?;
    const helper: @import("../4_semantics/global/graph.zig").GlobalFunctionId = for (checked.graph.functions.items, 0..) |function, raw| {
        if (std.mem.eql(u8, checked.graph.text(checked.graph.declaration(function.declaration).name), "helper")) break @enumFromInt(raw);
    } else return error.MissingHelper;
    try std.testing.expect(checked.graph.hasUnresolvedBindingTypes());
    var pending: ?@import("../4_semantics/global/graph.zig").GlobalBindingId = null;
    for (checked.graph.bindings.items, 0..) |binding, raw| {
        if (!std.mem.eql(u8, checked.graph.text(binding.name), "local")) continue;
        pending = @enumFromInt(raw);
        try std.testing.expect(checked.graph.isBindingTypeUnresolved(pending.?));
        try std.testing.expect(!checked.unit.?.containsBinding(pending.?));
    }
    try std.testing.expect(pending != null);
    const verify = @import("../4_semantics/global/verify.zig");
    try verify.verifyUnit(&checked.graph, &checked.unit.?);
    try std.testing.expectError(error.InvalidGlobalSemanticGraph, verify.verifyGlobal(&checked.graph));
    var invalid_unit = try checked.unit.?.clone(a);
    defer invalid_unit.deinit();
    try invalid_unit.bindings.put(pending.?, {});
    try std.testing.expectError(error.InvalidGlobalSemanticGraph, verify.verifyUnit(&checked.graph, &invalid_unit));
    try session.accept(&candidate);
    var draft = try session.beginPreparation(&diagnostics);
    defer draft.deinit();
    try draft.semantic.?.includeExecutionRoot(helper);
    var selected = try draft.finishDefinitions(&.{module}, &diagnostics);
    defer selected.deinit();
    try std.testing.expect(selected.checked.?.unit.?.contains(helper));
    try std.testing.expect(!selected.checked.?.graph.isBindingTypeUnresolved(pending.?));
    try std.testing.expect(checked.graph.isBindingTypeUnresolved(pending.?));
    try std.testing.expect(selected.semantic.?.relocation.graph.checkpoint().function_completions_len != 0);
    try session.accept(&selected);
    try std.testing.expectEqual(@as(usize, 0), session.semantic.relocation.graph.checkpoint().function_completions_len);
    try std.testing.expect(!diagnostics.hasErrors());
}

test "virtual signature completion is stable across repeated unit preparation" {
    const a = std.testing.allocator;
    var diagnostics = diagnostics_mod.Diagnostics.init(&a, &.{});
    defer diagnostics.deinit();
    var module = try sourceModule(a,
        \\Readable#(.Source: Type): Contract = (.read: (.source: &Source) -> (.result: Int32) where {})
        \\Box: Type = (.value: Int32)
        \\implement Readable#(Box) (.read = (.source: &Box) -> (.result: Int32) { result = source&.value })
        \\main := () -> (.status_code: Int32 = 0) {
        \\    box :: Box = (.value = 42)
        \\    erased ::= to_virtual#(.contract: Readable)(.value = &box)
        \\    status_code = Readable#().read(&erased).result
        \\}
    , &diagnostics);
    defer module.deinit(a);
    var session: sema.Session = undefined;
    try session.init(a, &.{module}, .{ .diagnostics = &diagnostics, .exhaustive_function_bodies = false });
    defer session.deinit();
    try session.advance();
    try session.resolvers.contracts.closeVirtualMethodRegistries();
    const graph = &session.relocation.graph;
    try std.testing.expect(graph.virtual_registries.items.len != 0);
    const signature = graph.virtual_registries.items[0];
    try std.testing.expect(signature.contract_input_count != null);
    try std.testing.expect(signature.safety_contract != null);
    const saved = graph.checkpoint();
    try session.resolvers.contracts.closeVirtualMethodRegistries();
    try std.testing.expectEqualDeep(saved, graph.checkpoint());
    try std.testing.expectEqualDeep(signature, graph.virtual_registries.items[0]);
    // Pool growth must not turn a completed descriptor into a new per-unit
    // implementation table or require updating existing references.
    for (0..64) |_| try graph.functions.append(a, graph.functions.items[0]);
    const grown = graph.checkpoint();
    try session.resolvers.contracts.closeVirtualMethodRegistries();
    try std.testing.expectEqualDeep(grown, graph.checkpoint());
    try std.testing.expectEqualDeep(signature, graph.virtual_registries.items[0]);
    try std.testing.expect(!diagnostics.hasErrors());
}

test "semantic unit completion keeps the same graph open for later roots" {
    const a = std.testing.allocator;
    var diagnostics = diagnostics_mod.Diagnostics.init(&a, &.{});
    defer diagnostics.deinit();
    var module = try sourceModule(a,
        \\identity#(.T: Type) := (.value: T) -> (.result: T) { result = value }
        \\helper := () -> (.result: Int32) {
        \\    local ::= identity#(.T: Int32)(.value = 7)
        \\    result = local
        \\}
        \\main := () -> (.status_code: Int32 = 0) {}
    , &diagnostics);
    defer module.deinit(a);
    var session: sema.Session = undefined;
    try session.init(a, &.{module}, .{ .diagnostics = &diagnostics, .exhaustive_function_bodies = false });
    defer session.deinit();
    try session.advance();
    _ = try session.completeUnit();
    const graph = &session.relocation.graph;
    try std.testing.expect(graph.hasUnresolvedBindingTypes());
    try std.testing.expect(!graph.constructionStateEmpty());
    const saved = graph.checkpoint();
    _ = try session.completeUnit();
    try std.testing.expectEqualDeep(saved, graph.checkpoint());
    const helper: @import("../4_semantics/global/graph.zig").GlobalFunctionId = for (graph.functions.items, 0..) |function, raw| {
        if (std.mem.eql(u8, graph.text(graph.declaration(function.declaration).name), "helper")) break @enumFromInt(raw);
    } else return error.MissingHelper;
    const body = graph.function(helper).body;
    try session.includeExecutionRoot(helper);
    try session.advance();
    _ = try session.completeUnit();
    try std.testing.expectEqual(body, graph.function(helper).body);
    try std.testing.expect(!graph.hasUnresolvedBindingTypes());
    try @import("../4_semantics/global/verify.zig").verifyGlobal(graph);
    var result = try session.finish();
    defer result.deinit(a);
    try std.testing.expectEqual(body, result.graph.function(helper).body);
    try std.testing.expect(result.graph.constructionStateEmpty());
    try std.testing.expect(!diagnostics.hasErrors());
}
