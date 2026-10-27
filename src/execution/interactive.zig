const std = @import("std");
const submissions = @import("submissions.zig");
const compilation = @import("compilation_session.zig");
const execution = @import("session.zig");
const diagnostics_mod = @import("../1_base/diagnostic.zig");
const module_sg = @import("../4_semantics/module/graph.zig");
const sema = @import("../4_semantics/global/semantizer.zig");
const vm = @import("vm.zig");

/// High-level retained execution owner used by interactive frontends. Initialize
/// in final storage: diagnostics and runtime borrow fields at stable addresses.
/// Initial module graphs remain borrowed; submitted sources are owned here.
/// Explicit close/reset executes checked cleanup; deinit only frees host memory.
pub const Interactive = struct {
    allocator: std.mem.Allocator,
    diagnostic_arena: std.heap.ArenaAllocator,
    diagnostic_allocator: std.mem.Allocator,
    diagnostics: diagnostics_mod.Diagnostics,
    sources: submissions.Sources,
    compiler: compilation.CompilationSession,
    runtime: execution.Session,
    initial_files: []const @import("../1_base/source_files.zig").SourceFile,
    initial_modules: []const module_sg.ModuleSemanticGraph,
    initial_semantic: ?*const sema.Session = null,
    options: sema.Options,
    limits: vm.Limits,
    closed: bool = false,
    result_sequence: u64 = 0,
    submission_depth: usize = 0,
    source_checkpoint: ?submissions.Sources.Checkpoint = null,
    source_revision: u64 = 0,
    rejected_sources: ?submissions.Sources.Checkpoint = null,
    prelude: ?[]const u8 = null,
    imports: ?struct { io: std.Io, path: []const u8 } = null,

    pub fn init(self: *Interactive, allocator: std.mem.Allocator, modules: []const module_sg.ModuleSemanticGraph, options: sema.Options, limits: vm.Limits) !void {
        return self.initWithSources(allocator, &.{}, modules, options, limits);
    }

    /// Initial files and module graphs are borrowed together. Submitted sources
    /// extend this diagnostic index without changing initial file identities.
    pub fn initWithSources(self: *Interactive, allocator: std.mem.Allocator, files: []const @import("../1_base/source_files.zig").SourceFile, modules: []const module_sg.ModuleSemanticGraph, options: sema.Options, limits: vm.Limits) !void {
        return self.initBase(allocator, files, modules, options, limits, null);
    }

    /// Borrow an immutable prepared module template and its original sources.
    /// Both must outlive this controller, including every reset. Commands fork
    /// semantic state; they never modify the template or replay earlier input.
    pub fn initPrepared(self: *Interactive, allocator: std.mem.Allocator, files: []const @import("../1_base/source_files.zig").SourceFile, template: *const sema.Session, limits: vm.Limits) !void {
        return self.initBase(allocator, files, template.modules, template.options, limits, template);
    }

    fn initBase(self: *Interactive, allocator: std.mem.Allocator, files: []const @import("../1_base/source_files.zig").SourceFile, modules: []const module_sg.ModuleSemanticGraph, options: sema.Options, limits: vm.Limits, template: ?*const sema.Session) !void {
        self.allocator = allocator;
        self.initial_files = files;
        self.initial_modules = modules;
        self.initial_semantic = template;
        self.options = options;
        self.limits = limits;
        self.closed = false;
        self.result_sequence = 0;
        self.submission_depth = 0;
        self.source_checkpoint = null;
        self.rejected_sources = null;
        self.source_revision = 0;
        self.imports = null;
        self.prelude = null;
        self.diagnostic_arena = .init(allocator);
        errdefer self.diagnostic_arena.deinit();
        self.diagnostic_allocator = allocator;
        self.diagnostics = .init(&self.diagnostic_allocator, files);
        self.diagnostics.message_allocator = self.diagnostic_arena.allocator();
        errdefer self.diagnostics.deinit();
        self.sources = .init(allocator);
        errdefer self.sources.deinit();
        var selected = options;
        selected.diagnostics = &self.diagnostics;
        self.compiler = if (template) |prepared| try compilation.CompilationSession.initPrepared(allocator, prepared, &self.diagnostics) else try compilation.CompilationSession.init(allocator, modules, selected);
        self.runtime = .init(allocator, &self.compiler, limits);
    }
    pub fn enableImports(self: *Interactive, io: std.Io, directory: []const u8) !void {
        const cwd = try std.process.currentPathAlloc(io, self.allocator);
        defer self.allocator.free(cwd);
        const path = try std.fs.path.resolve(self.allocator, &.{ cwd, directory, "__argi_repl__.rg" });
        if (self.imports) |previous| self.allocator.free(previous.path);
        self.imports = .{ .io = io, .path = path };
    }

    /// A frontend installs ordinary checked statements before any user input.
    /// Keep their source outside submission storage so reset can execute it again.
    pub fn initializePrelude(self: *Interactive, source: []const u8) !void {
        if (self.closed) return error.InteractiveSessionClosed;
        if (self.prelude != null or self.compiler.revision != 0) return error.PreludeRequiresFreshSession;
        const retained = try self.allocator.dupe(u8, source);
        errdefer self.allocator.free(retained);
        try self.submitStatements(retained);
        self.prelude = retained;
    }

    pub fn deinit(self: *Interactive) void {
        if (self.prelude) |source| self.allocator.free(source);
        if (self.imports) |loader| self.allocator.free(loader.path);
        self.runtime.deinit();
        self.compiler.deinit();
        self.diagnostics.deinit();
        self.sources.deinit();
        self.diagnostic_arena.deinit();
        self.* = undefined;
    }

    fn prepareCommand(self: *Interactive, source: []const u8, origin: ?submissions.Sources.SourceOrigin) !submissions.Sources.PreparedCommand {
        var draft = try self.compiler.beginPreparation(&self.diagnostics);
        defer draft.deinit();
        const semantic = draft.semantic.?;
        const first_module = semantic.modules.len;
        if (self.imports) |loader| {
            try self.sources.loadImports(&self.diagnostics, loader.io, loader.path, source, semantic, self.options.target);
            try self.sources.selectModules(&self.diagnostics, semantic, first_module, loader.io, self.options.target);
        }
        const command = try self.sources.loadCommandOrigin(&self.diagnostics, source, origin);
        const modules = try self.sources.appendModuleViews(semantic.modules, command.module);
        const base = semantic.relocation.graph.functions.items.len;
        const raw = try std.math.add(usize, base, @intFromEnum(command.function));
        const function: @import("../4_semantics/global/graph.zig").GlobalFunctionId = @enumFromInt(std.math.cast(u32, raw) orelse return error.SubmissionIdentityLimit);
        return .{ .candidate = try draft.finishContinuation(modules, &self.diagnostics, function), .function = function };
    }

    pub fn submitStatements(self: *Interactive, statements: []const u8) !void {
        try self.beginSubmission();
        defer self.endSubmission();
        var command = try self.prepareCommand(statements, null);
        defer command.deinit();
        try self.runtime.executeCommand(&command.candidate);
    }

    pub const PresentedValue = struct {
        name: []const u8,
        ty: @import("../4_semantics/global/graph.zig").GlobalTypeId,
        value: union(enum) {
            runtime: @import("../5_codegen/bytecode/value.zig").Value,
            type_: @import("../4_semantics/global/graph.zig").GlobalTypeId,
        },
    };

    pub fn submit(self: *Interactive, source: []const u8) !void {
        _ = try self.submitInput(source);
    }

    /// Expressions become ordinary numbered session bindings. Their owners and
    /// loans survive presentation and receive normal checked reset/exit cleanup.
    /// Returned presentation views are borrowed until the next session mutation.
    pub fn submitInput(self: *Interactive, source: []const u8) !?PresentedValue {
        try self.beginSubmission();
        defer self.endSubmission();
        switch (try self.sources.classify(&self.diagnostics, source)) {
            .empty => {},
            .definitions => try self.submitDefinitions(source),
            .statements => try self.submitStatements(source),
            .expression => {
                const name = try self.nextResultName();
                const statement = try std.fmt.allocPrint(self.allocator, "{s} := {s}\n", .{ name, source });
                defer self.allocator.free(statement);
                var command = try self.prepareCommand(statement, .{
                    .text = source,
                    .offset = name.len + " := ".len,
                });
                defer command.deinit();
                try self.runtime.executeCommand(&command.candidate);
                const bindings = self.compiler.semantic.resolvers.expressions.session_bindings.items;
                const binding = bindings[bindings.len - 1];
                const graph = &self.compiler.semantic.relocation.graph;
                if (@import("../4_semantics/global/types.zig").staticTypeBinding(graph, binding)) |type_value|
                    return .{ .name = name, .ty = graph.binding(binding).ty, .value = .{ .type_ = type_value } };
                const frame = self.runtime.context.bindings.get(binding) orelse return error.UninitializedBinding;
                const slots = try self.runtime.context.storage.slots(frame);
                return .{ .name = name, .ty = self.compiler.semantic.relocation.graph.binding(binding).ty, .value = .{ .runtime = try slots.get(0) } };
            },
        }
        return null;
    }

    fn nextResultName(self: *Interactive) ![]const u8 {
        const graph = &self.compiler.semantic.relocation.graph;
        names: while (self.result_sequence < std.math.maxInt(u64)) {
            const sequence = self.result_sequence;
            self.result_sequence += 1;
            const name = try std.fmt.allocPrint(self.sources.arena.allocator(), "_{d}", .{sequence});
            for (self.compiler.semantic.resolvers.expressions.session_bindings.items) |binding|
                if (std.mem.eql(u8, graph.text(graph.binding(binding).name), name)) continue :names;
            if (self.compiler.semantic.resolvers.core.session_namespace) |namespace|
                for (namespace.declarations.items) |declaration|
                    if (std.mem.eql(u8, graph.text(graph.declaration(declaration).name), name)) continue :names;
            return name;
        }
        return error.SubmissionIdentityLimit;
    }

    pub fn submitDefinitions(self: *Interactive, source: []const u8) !void {
        try self.beginSubmission();
        defer self.endSubmission();
        const module = try self.sources.loadModule(&self.diagnostics, source);
        var draft = try self.compiler.beginPreparation(&self.diagnostics);
        defer draft.deinit();
        const semantic = draft.semantic.?;
        const first_module = semantic.modules.len;
        if (self.imports) |loader| {
            try self.sources.loadImports(&self.diagnostics, loader.io, loader.path, source, semantic, self.options.target);
            try self.sources.selectModules(&self.diagnostics, semantic, first_module, loader.io, self.options.target);
            try self.sources.resolveSubmissionImports(module, loader.io, loader.path);
        } else if (module.semantic.module_aliases.items.len != 0) {
            try self.diagnostics.add(.{ .file = self.diagnostics.source_db.fileId(self.diagnostics.source_files.len - 1), .offset = 0 }, .semantic, "interactive imports require a configured source loader", .{});
            return error.Reported;
        }
        const prefix = try self.sources.appendModuleViews(semantic.modules, module);
        var candidate = try draft.finishDefinitions(prefix, &self.diagnostics);
        defer candidate.deinit();
        try self.compiler.acceptDefinitions(&candidate);
    }

    fn beginSubmission(self: *Interactive) !void {
        if (self.closed) return error.InteractiveSessionClosed;
        if (self.runtime.context.state == .poisoned) return error.ExecutionContextPoisoned;
        if (self.submission_depth == 0) {
            self.diagnostics.list.clearRetainingCapacity();
            _ = self.diagnostic_arena.reset(.free_all);
            if (self.rejected_sources) |saved| {
                self.sources.rollbackBatch(&self.diagnostics, saved);
                self.rejected_sources = null;
            }
            self.source_checkpoint = try self.sources.beginBatch(&self.diagnostics);
            self.source_revision = self.compiler.revision;
        }
        self.submission_depth += 1;
    }

    fn endSubmission(self: *Interactive) void {
        std.debug.assert(self.submission_depth != 0);
        self.submission_depth -= 1;
        if (self.submission_depth == 0) {
            if (self.compiler.revision == self.source_revision) self.rejected_sources = self.source_checkpoint;
            self.source_checkpoint = null;
        }
    }

    pub fn close(self: *Interactive) !void {
        try self.beginSubmission();
        defer self.endSubmission();
        try self.cleanup();
        self.closed = true;
    }
    fn cleanup(self: *Interactive) !void {
        const command = try self.sources.loadCommand(&self.diagnostics, "");
        const prefix = try self.sources.appendModuleViews(self.compiler.semantic.modules, command.module);
        const base = self.compiler.semantic.relocation.graph.functions.items.len;
        const raw = try std.math.add(usize, base, @intFromEnum(command.function));
        const entry: @import("../4_semantics/global/graph.zig").GlobalFunctionId = @enumFromInt(std.math.cast(u32, raw) orelse return error.SubmissionIdentityLimit);
        var candidate = try self.compiler.prepareExit(prefix, &self.diagnostics, entry, self.compiler.semantic.resolvers.expressions.session_bindings.items);
        defer candidate.deinit();
        try self.runtime.executeCommand(&candidate);
    }

    pub fn reset(self: *Interactive) !void {
        if (self.closed) return error.InteractiveSessionClosed;
        // Allocate the replacement first: failure cannot discard live owners.
        var options = self.options;
        options.diagnostics = &self.diagnostics;
        var replacement = if (self.initial_semantic) |prepared| try compilation.CompilationSession.initPrepared(self.allocator, prepared, &self.diagnostics) else try compilation.CompilationSession.init(self.allocator, self.initial_modules, options);
        var transferred = false;
        errdefer if (!transferred) replacement.deinit();
        if (self.runtime.context.state != .poisoned) {
            self.diagnostics.list.clearRetainingCapacity();
            try self.cleanup();
        }
        // A trapped context has no safe user-code unwind. Its explicit reset
        // discards the poisoned execution and proof state together.
        const host_bindings = self.runtime.context.host_bindings;
        self.runtime.deinit();
        self.compiler.deinit();
        // No accepted graph or execution unit can refer to submitted source
        // now. Reset releases that history rather than retaining it until quit.
        self.diagnostics.deinit();
        self.sources.deinit();
        _ = self.diagnostic_arena.reset(.free_all);
        self.diagnostics = .init(&self.diagnostic_allocator, self.initial_files);
        self.diagnostics.message_allocator = self.diagnostic_arena.allocator();
        self.rejected_sources = null;
        self.source_checkpoint = null;
        self.sources = .init(self.allocator);
        self.compiler = replacement;
        transferred = true;
        self.runtime = .init(self.allocator, &self.compiler, self.limits);
        self.runtime.context.host_bindings = host_bindings;
        self.result_sequence = 0;
        self.diagnostics.list.clearRetainingCapacity();
        if (self.prelude) |source| try self.submitStatements(source);
    }
};

test "interactive controller retains statements recovers rejected input and resets" {
    var session: Interactive = undefined;
    try session.init(std.testing.allocator, &.{}, .{ .exhaustive_function_bodies = false }, .{});
    defer session.deinit();
    try session.submitStatements("value :: Int32 = 42");
    const original_namespace = session.compiler.namespace;
    try std.testing.expectError(error.DuplicateSessionBinding, session.submitStatements("value :: Int32 = 99"));
    try session.submitStatements("value = 7");
    const binding = session.compiler.semantic.resolvers.expressions.session_bindings.items[0];
    const stored = try session.runtime.context.storage.slots(session.runtime.context.bindings.get(binding).?);
    try std.testing.expectEqual(@as(i128, 7), (try stored.get(0)).integer);
    try session.reset();
    try std.testing.expect(session.compiler.namespace != original_namespace);
    try std.testing.expectEqual(@as(usize, 0), session.compiler.semantic.resolvers.expressions.session_bindings.items.len);
    try std.testing.expectEqual(@as(usize, 0), session.sources.modules.items.len);
    try std.testing.expectEqual(@as(usize, 0), session.diagnostics.source_files.len);
    try session.submitStatements("value :: Int32 = 12");
    try session.close();
    try std.testing.expectEqual(.fresh, session.runtime.context.state);
    try std.testing.expectError(error.InteractiveSessionClosed, session.submitStatements("value = 1"));
}

test "interactive controller recovers poisoned contexts by reset" {
    var session: Interactive = undefined;
    try session.init(std.testing.allocator, &.{}, .{ .exhaustive_function_bodies = false }, .{ .instructions = 30 });
    defer session.deinit();
    try session.submitStatements("value ::= 42");
    try std.testing.expectError(error.ExecutionInstructionLimit, session.submitStatements("while true {}"));
    try std.testing.expectError(error.ExecutionContextPoisoned, session.submitStatements("value = 7"));
    try std.testing.expectError(error.ExecutionContextPoisoned, session.close());
    try session.reset();
    try session.submitStatements("fresh ::= 7");
    try session.close();
}

test "interactive definitions remain visible to subsequent definitions and statements" {
    var session: Interactive = undefined;
    try session.init(std.testing.allocator, &.{}, .{ .exhaustive_function_bodies = false }, .{});
    defer session.deinit();
    try session.submitDefinitions("answer := () -> (.result: Int32) { result = 42 }\n");
    try session.submitDefinitions("forward := () -> (.result: Int32) { result = answer() }\n");
    try session.submitStatements("value ::= forward()");
    try session.submitStatements("other ::= value");
    try session.submitDefinitions("later := () -> (.result: Int32) { result = answer() }\n");
    try session.submitDefinitions("identity := #(.T: Type) (.value: T) -> (.result: T) { result = value }\n");
    try session.submitStatements("generic_value ::= identity#(Int32)(.value = later())");
    const binding = session.compiler.semantic.resolvers.expressions.session_bindings.items[0];
    const stored = try session.runtime.context.storage.slots(session.runtime.context.bindings.get(binding).?);
    try std.testing.expectEqual(@as(i128, 42), (try stored.get(0)).integer);
    const generic_binding = session.compiler.semantic.resolvers.expressions.session_bindings.items[2];
    const generic_stored = try session.runtime.context.storage.slots(session.runtime.context.bindings.get(generic_binding).?);
    try std.testing.expectEqual(@as(i128, 42), (try generic_stored.get(0)).integer);
    const revision = session.compiler.revision;
    try std.testing.expectError(error.DuplicateSessionDeclaration, session.submitDefinitions("answer := () -> (.result: Int32) { result = 7 }\n"));
    try std.testing.expectEqual(revision, session.compiler.revision);
    try std.testing.expectError(error.DuplicateSessionDeclaration, session.submitStatements("answer ::= 7"));
    try std.testing.expectEqual(revision, session.compiler.revision);
    {
        // Loading an ordinary module must not grant the interactive namespace.
        const isolated = try session.sources.loadModule(&session.diagnostics, "outside := () -> (.result: Int32) { result = answer() }\n");
        const prefix = try session.sources.appendModuleViews(session.compiler.semantic.modules, isolated);
        var ordinary = try session.compiler.prepare(prefix, &session.diagnostics);
        defer ordinary.deinit();
        const core = &ordinary.semantic.?.resolvers.core;
        try std.testing.expect(!core.sameDeclarationNamespace(0, core.modules.len - 1));
        try std.testing.expect(core.sameDeclarationNamespace(0, 1));
        const declaration = for (core.session_namespace.?.declarations.items) |decl| {
            if (std.mem.eql(u8, core.graph.text(core.graph.declaration(decl).name), "answer")) break decl;
        } else return error.MissingDeclaration;
        try std.testing.expect(!core.declarationVisible(core.modules.len - 1, declaration, null));
        const later = for (core.session_namespace.?.declarations.items) |decl| {
            if (std.mem.eql(u8, core.graph.text(core.graph.declaration(decl).name), "later")) break decl;
        } else return error.MissingDeclaration;
        // Deferred specialization of an earlier definition cannot acquire names
        // introduced by a future submission merely because it materializes later.
        try std.testing.expect(!core.declarationVisible(0, later, null));
        try std.testing.expectEqual(revision, session.compiler.revision);
    }
    try session.close();
}

test "interactive contract definitions select implementations in later submissions" {
    var session: Interactive = undefined;
    try session.init(std.testing.allocator, &.{}, .{ .exhaustive_function_bodies = false }, .{});
    defer session.deinit();
    try session.submitDefinitions("Echo#(.T: Type): Contract = (.echo: (.value: T) -> (.result: T))\n");
    session.submitDefinitions("implement Echo#(Int32) (.echo = (.value: Int32) -> (.result: Int32) { result = value })\n") catch |err| {
        try session.diagnostics.dump();
        return err;
    };
    // Identical source offsets in different submissions must not make private
    // implementation-body identities collide in the source namespace.
    try session.submitDefinitions("implement Echo#(Int64) (.echo = (.value: Int64) -> (.result: Int64) { result = value })\n");
    try session.submitStatements("value ::= echo(.value = 42)");
    const binding = session.compiler.semantic.resolvers.expressions.session_bindings.items[0];
    const stored = try session.runtime.context.storage.slots(session.runtime.context.bindings.get(binding).?);
    try std.testing.expectEqual(@as(i128, 42), (try stored.get(0)).integer);
    try session.close();
}

test "interactive expression results retain names skip conflicts and reset" {
    var session: Interactive = undefined;
    try session.init(std.testing.allocator, &.{}, .{ .exhaustive_function_bodies = false }, .{});
    defer session.deinit();
    try session.submit("_0 ::= 7");
    const first = (try session.submitInput("42")).?;
    try std.testing.expectEqualStrings("_1", first.name);
    try std.testing.expectEqual(@as(i128, 42), first.value.runtime.integer);
    const second = (try session.submitInput("_1")).?;
    try std.testing.expectEqualStrings("_2", second.name);
    try std.testing.expectEqual(@as(i128, 42), second.value.runtime.integer);
    try session.submit("answer := () -> (.result: Int32) { result = 12 }");
    const call = (try session.submitInput("answer()")).?;
    try std.testing.expectEqual(@as(i128, 12), call.value.runtime.integer);
    try session.submit("called :: Bool = false");
    try session.submit("nothing := (.called: $&Bool) -> () { if called& { abort } called& = true }");
    const unit = (try session.submitInput("nothing(.called = $&called)")).?;
    try std.testing.expect(unit.value.runtime == .unit or (unit.value.runtime == .record and unit.value.runtime.record.len == 0));
    try std.testing.expect((try session.submitInput("called")).?.value.runtime.boolean);
    try session.reset();
    const reset = (try session.submitInput("true")).?;
    try std.testing.expectEqualStrings("_0", reset.name);
    try std.testing.expect(reset.value.runtime.boolean);
    try session.close();
}

test "interactive presented references retain checked session storage" {
    var session: Interactive = undefined;
    try session.init(std.testing.allocator, &.{}, .{ .exhaustive_function_bodies = false }, .{});
    defer session.deinit();
    try session.submit("source :: Int32 = 42");
    const borrowed = (try session.submitInput("&source")).?;
    try std.testing.expect(borrowed.value.runtime == .reference);
    const target = borrowed.value.runtime.reference;
    try std.testing.expectEqual(.session, session.runtime.context.storage.frames.items[@intFromEnum(target.frame)].duration);
    const read = (try session.submitInput("_0&")).?;
    try std.testing.expectEqual(@as(i128, 42), read.value.runtime.integer);
    try session.close();
}

test "interactive expression owners retain cleanup until checked exit" {
    const allocator = std.testing.allocator;
    var sources = submissions.Sources.init(allocator);
    defer sources.deinit();
    var diagnostics = diagnostics_mod.Diagnostics.init(&allocator, &.{});
    defer diagnostics.deinit();
    const loaded = try sources.loadModule(&diagnostics, "Deinit#(.T: Type): Contract = (.deinit: (.self: $&T) -> ())");
    // This isolated fixture supplies the standard lifecycle identity through
    // an initial bundled module, just as the CLI's core loader does.
    var core = loaded.*;
    core.is_bundled_core = true;
    var session: Interactive = undefined;
    try session.initWithSources(allocator, diagnostics.source_files, &.{core}, .{ .exhaustive_function_bodies = false }, .{});
    defer session.deinit();
    try session.submit("Resource: Type = ()");
    try session.submit("implement Deinit#(Resource) (.deinit = (.self: $&Resource) -> () {})");
    try session.submit("make := () -> (.result: Resource) { result = () }");
    const result = (try session.submitInput("make()")).?;
    try std.testing.expectEqualStrings("_0", result.name);
    const binding = session.compiler.semantic.resolvers.expressions.session_bindings.items[0];
    const frame = session.runtime.context.bindings.get(binding).?;
    const flags = session.runtime.context.storage.frames.items[@intFromEnum(frame)].cleanup_flags;
    const cleanup = session.runtime.context.storage.frames.items[@intFromEnum(frame)].cleanup;
    try std.testing.expect(cleanup.len != 0);
    try std.testing.expect(flags[cleanup[0].offset]);
    try session.close();
    try std.testing.expectEqual(.fresh, session.runtime.context.state);
}

test "interactive submissions share staged run and conditional execution" {
    var session: Interactive = undefined;
    try session.init(std.testing.allocator, &.{}, .{ .exhaustive_function_bodies = false }, .{});
    defer session.deinit();
    try session.submit("enabled := () -> (.result: Bool) { result = true }");
    try session.submit(
        "choose := () -> (.result: Int32) {\n" ++
            "    #if enabled() { result = 42 } else { result = missing() }\n" ++
            "}\n",
    );
    const runtime = (try session.submitInput("choose()")).?;
    try std.testing.expectEqual(@as(i128, 42), runtime.value.runtime.integer);
    const comptime_value = (try session.submitInput("#run () -> (.answer: Int32) { answer = choose() }")).?;
    try std.testing.expectEqual(@as(i128, 42), comptime_value.value.runtime.integer);
    try session.close();
}

test "interactive anonymous compile-time entries preserve accepted state across failures" {
    var session: Interactive = undefined;
    try session.init(std.testing.allocator, &.{}, .{ .exhaustive_function_bodies = false }, .{});
    defer session.deinit();
    try session.submit("calculate := () -> (.result: Int32) { result = 42 }");
    try session.submitStatements("saved ::= #run () -> (.result: Int32) { result = calculate() }");
    try std.testing.expectEqual(@as(i128, 42), (try session.submitInput("saved")).?.value.runtime.integer);
    try session.submitStatements("pair ::= #run () -> (.left: Int32 = 20, .right: Int32 = 22) {}");
    try std.testing.expectEqual(@as(i128, 20), (try session.submitInput("pair.left")).?.value.runtime.integer);
    try std.testing.expectEqual(@as(i128, 22), (try session.submitInput("pair.right")).?.value.runtime.integer);
    try session.submitStatements("runtime_value :: Int32 = 7");
    const revision = session.compiler.revision;
    try std.testing.expectError(error.Reported, session.submitInput("#run () -> (.result: Int32) { result = runtime_value }"));
    try std.testing.expectEqual(revision, session.compiler.revision);
    try std.testing.expectEqual(@as(i128, 7), (try session.submitInput("runtime_value")).?.value.runtime.integer);
    const after_read = session.compiler.revision;
    try std.testing.expectError(error.Reported, session.submitInput("#run () -> (.result: Int32) { abort }"));
    try std.testing.expectEqual(after_read, session.compiler.revision);
    try std.testing.expect(session.runtime.context.state != .poisoned);
    try std.testing.expectEqual(@as(i128, 42), (try session.submitInput("saved")).?.value.runtime.integer);
    try session.submitStatements("#run { local :: Int32 = 41\npointer ::= $&local\npointer&= 42 }");
    try session.reset();
    try std.testing.expectEqual(@as(i128, 42), (try session.submitInput("#run () -> (.result: Int32 = 42) {} ")).?.value.runtime.integer);
    try session.close();
}

test "interactive generic compile-time entries retain independent specializations" {
    var session: Interactive = undefined;
    try session.init(std.testing.allocator, &.{}, .{ .exhaustive_function_bodies = false }, .{});
    defer session.deinit();
    try session.submit("copy_value := #(.T: Type) (.value: T) -> (.result: T = value) {}");
    try session.submit("calculate := #(.T: Type, .n: Int32) () -> (.result: T) { local := copy_value#(.T: T)(.value = n)\nresult = #run () -> (.value: T) { value = #run () -> (.inner: T) { inner = local } } }");
    try std.testing.expectEqual(@as(i128, 42), (try session.submitInput("calculate#(.T: Int32, .n = 42)()")).?.value.runtime.integer);
    try std.testing.expectEqual(@as(i128, 41), (try session.submitInput("calculate#(.T: Int32, .n = 41)()")).?.value.runtime.integer);
    try session.submit("invalid := #(.T: Type) (.runtime_value: T) -> (.result: T) { result = #run () -> (.value: T) { value = runtime_value } }");
    const revision = session.compiler.revision;
    try std.testing.expectError(error.Reported, session.submitInput("invalid#(.T: Int32)(.runtime_value = 7)"));
    try std.testing.expectEqual(revision, session.compiler.revision);
    try std.testing.expectEqual(@as(i128, 42), (try session.submitInput("calculate#(.T: Int32, .n = 42)()")).?.value.runtime.integer);
    try session.close();
}

test "interactive conditional compile-time entries preserve selection across revisions" {
    var session: Interactive = undefined;
    try session.init(std.testing.allocator, &.{}, .{ .exhaustive_function_bodies = false }, .{});
    defer session.deinit();
    try session.submit("enabled := () -> (.result: Bool) { result = false }");
    try session.submitStatements("saved ::= #run () -> (.result: Int32) { #if enabled() { result = missing() } #else { result = 42 } }");
    try std.testing.expectEqual(@as(i128, 42), (try session.submitInput("saved")).?.value.runtime.integer);
    try session.submitStatements("fixed: Int32 = 42\nbranch_enabled: Bool = true\nruntime_value :: Int32 = 7");
    try std.testing.expectEqual(@as(i128, 42), (try session.submitInput("#run () -> (.result: Int32) { #if branch_enabled { result = fixed } #else { result = runtime_value } }")).?.value.runtime.integer);
    const revision = session.compiler.revision;
    try std.testing.expectError(error.Reported, session.submitInput("#run () -> (.result: Int32) { #if enabled() { result = 42 } #else { result = missing() } }"));
    try std.testing.expectEqual(revision, session.compiler.revision);
    try std.testing.expect(session.runtime.context.state != .poisoned);
    try std.testing.expectEqual(@as(i128, 42), (try session.submitInput("saved")).?.value.runtime.integer);
    try session.submitStatements("#run { #if enabled() { missing() } #else { local :: Int32 = 42 } }");
    try session.reset();
    try std.testing.expectEqual(@as(i128, 42), (try session.submitInput("#run () -> (.result: Int32) { #if false { result = missing() } #else { result = 42 } }")).?.value.runtime.integer);
    try session.close();
}

test "interactive classification rejects mixed submissions and unresolved imports atomically" {
    var session: Interactive = undefined;
    try session.init(std.testing.allocator, &.{}, .{ .exhaustive_function_bodies = false }, .{});
    defer session.deinit();
    const revision = session.compiler.revision;
    try std.testing.expectError(error.Reported, session.submit("answer := () -> (.result: Int32) { result = 42 }\nvalue ::= 7"));
    try std.testing.expectEqual(revision, session.compiler.revision);
    try std.testing.expectError(error.Reported, session.submit("module := import(\"./support\")"));
    try std.testing.expectEqual(revision, session.compiler.revision);
    try std.testing.expect(std.mem.indexOf(u8, session.diagnostics.list.items[0].msg, "interactive imports require a configured source loader") != null);
    const result = (try session.submitInput("42")).?;
    try std.testing.expectEqual(@as(i128, 42), result.value.runtime.integer);
    try session.close();
}

test "interactive command diagnostics use original submitted coordinates" {
    var session: Interactive = undefined;
    try session.init(std.testing.allocator, &.{}, .{ .exhaustive_function_bodies = false }, .{});
    defer session.deinit();
    try session.submitStatements("value: Int32 = 42");
    try std.testing.expectError(error.Reported, session.submitStatements("\nvalue = 7"));
    try std.testing.expect(session.diagnostics.hasErrors());
    const diagnostic = session.diagnostics.list.items[0];
    try std.testing.expect(std.mem.endsWith(u8, session.diagnostics.path(diagnostic.loc), "/input.rg"));
    const position = session.diagnostics.lineColumn(diagnostic.loc);
    try std.testing.expectEqual(@as(u32, 2), position.line);
    try std.testing.expectEqual(@as(u32, 1), position.column);
    try std.testing.expectEqualStrings("\nvalue = 7", session.diagnostics.source_db.get(diagnostic.loc.file).source);
    try session.close();
}

test "interactive floating values preserve concrete precision and survive submissions" {
    var session: Interactive = undefined;
    try session.init(std.testing.allocator, &.{}, .{ .exhaustive_function_bodies = false }, .{});
    defer session.deinit();
    try session.submit("f := 0.123123");
    try std.testing.expectEqual(@as(f32, 0.123123), (try session.submitInput("f")).?.value.runtime.float32);
    try session.submit("fraction := () -> (.result: Float32) { result = 1.5 }");
    try std.testing.expectEqual(@as(f32, 1.5), (try session.submitInput("fraction()")).?.value.runtime.float32);
    try session.submit("half :: Float16 = 1.5");
    try std.testing.expectEqual(@as(f16, 1.5), (try session.submitInput("half")).?.value.runtime.float16);
    try session.submit("wide :: Float64 = 16777217.0");
    try std.testing.expectEqual(@as(f64, 16777217), (try session.submitInput("wide")).?.value.runtime.float64);
    try session.close();
}

test "interactive execution diagnostics map expression and statement source" {
    var session: Interactive = undefined;
    try session.init(std.testing.allocator, &.{}, .{ .exhaustive_function_bodies = false }, .{});
    defer session.deinit();
    try std.testing.expectError(error.ExecutionAborted, session.submitStatements("\nabort"));
    const aborted = session.diagnostics.list.items[0];
    try std.testing.expect(std.mem.endsWith(u8, session.diagnostics.path(aborted.loc), "/input.rg"));
    const position = session.diagnostics.lineColumn(aborted.loc);
    try std.testing.expectEqual(@as(u32, 2), position.line);
    try std.testing.expectEqual(@as(u32, 1), position.column);
    try session.reset();
    try session.close();
}

test "interactive compile-time failures preserve definition source and accepted revision" {
    var session: Interactive = undefined;
    try session.init(std.testing.allocator, &.{}, .{ .exhaustive_function_bodies = false }, .{});
    defer session.deinit();
    try session.submit("fail := () -> (.result: Int32) { abort }");
    const revision = session.compiler.revision;
    try std.testing.expectError(error.Reported, session.submitInput("#run () -> (.answer: Int32) { answer = fail() }"));
    try std.testing.expectEqual(revision, session.compiler.revision);
    try std.testing.expect(session.diagnostics.hasErrors());
    const diagnostic = session.diagnostics.list.items[0];
    const text = session.diagnostics.source_db.get(diagnostic.loc.file).source;
    try std.testing.expect(std.mem.indexOf(u8, text, "_session_command_") == null);
    try std.testing.expect(std.mem.indexOf(u8, diagnostic.msg, "aborted") != null);
    try session.submitStatements("value ::= 42");
    try session.close();
}

test "interactive definition batches keep dependency modules outside the session namespace" {
    var session: Interactive = undefined;
    try session.init(std.testing.allocator, &.{}, .{ .exhaustive_function_bodies = false }, .{});
    defer session.deinit();
    const dependency = try session.sources.loadModule(&session.diagnostics, "helper := () -> (.result: Int32) { result = 7 }");
    const submitted = try session.sources.loadModule(&session.diagnostics, "answer := () -> (.result: Int32) { result = 42 }");
    const dependencies = try session.sources.appendModuleViews(session.compiler.semantic.modules, dependency);
    const prefix = try session.sources.appendModuleViews(dependencies, submitted);
    var candidate = try session.compiler.prepareDefinitions(prefix, &session.diagnostics);
    defer candidate.deinit();
    const resolver = &candidate.semantic.?.resolvers.core;
    const namespace = resolver.session_namespace.?;
    try std.testing.expectEqual(@as(usize, 1), namespace.modules.items.len);
    try std.testing.expectEqual(@as(usize, 1), namespace.declarations.items.len);
    try std.testing.expectEqualStrings("answer", resolver.graph.text(resolver.graph.declaration(namespace.declarations.items[0]).name));
    try std.testing.expect(!resolver.sameDeclarationNamespace(0, 1));
    try session.compiler.acceptDefinitions(&candidate);
    try std.testing.expectEqual(@as(i128, 42), (try session.submitInput("answer()")).?.value.runtime.integer);
    try session.close();
}

test "interactive imported aliases survive subsequent submissions without exporting dependency names" {
    var session: Interactive = undefined;
    try session.init(std.testing.allocator, &.{}, .{ .exhaustive_function_bodies = false }, .{});
    defer session.deinit();
    const dependency = try session.sources.loadModule(&session.diagnostics, "helper := () -> (.result: Int32) { result = 7 }");
    const import_source = try std.fmt.allocPrint(std.testing.allocator, "library := import(\"{s}\")", .{dependency.module_dir});
    defer std.testing.allocator.free(import_source);
    const submitted = try session.sources.loadModule(&session.diagnostics, import_source);
    const dependencies = try session.sources.appendModuleViews(session.compiler.semantic.modules, dependency);
    const prefix = try session.sources.appendModuleViews(dependencies, submitted);
    var candidate = try session.compiler.prepareDefinitions(prefix, &session.diagnostics);
    defer candidate.deinit();
    try session.compiler.acceptDefinitions(&candidate);
    try std.testing.expectEqual(@as(i128, 7), (try session.submitInput("library.helper()")).?.value.runtime.integer);
    const resolver = &session.compiler.semantic.resolvers.core;
    const namespace = resolver.session_namespace.?;
    try std.testing.expectEqualStrings("library", resolver.graph.text(resolver.graph.declaration(namespace.declarations.items[0]).name));
    try std.testing.expect(!resolver.sameDeclarationNamespace(0, 1));
    try std.testing.expectError(error.UnknownModuleReference, resolver.findModuleForQualifier(0, "library"));
    const revision = session.compiler.revision;
    try std.testing.expectError(error.DuplicateSessionDeclaration, session.submitStatements("library ::= 99"));
    try std.testing.expectEqual(revision, session.compiler.revision);
    try session.close();
}

test "interactive assumptions persist without leaking nested scopes or rejected commands" {
    var session: Interactive = undefined;
    try session.init(std.testing.allocator, &.{}, .{ .exhaustive_function_bodies = false }, .{});
    defer session.deinit();
    try session.submitDefinitions("observe := (.capability: &Bool) -> (.result: Bool) { result = capability& }\n");
    try session.submitStatements("enabled ::= true\nassume capability ::= &enabled");
    try std.testing.expect((try session.submitInput("observe()")).?.value.runtime.boolean);
    try session.submitStatements("nested_result :: Bool = true\nif true {\nlocal ::= false\nassume capability ::= &local\nnested_result = observe()\n}");
    try std.testing.expect(!(try session.submitInput("nested_result")).?.value.runtime.boolean);
    try std.testing.expectError(error.Reported, session.submitStatements("if true {\ncapability ::= &enabled\nignored ::= observe()\n}"));
    try std.testing.expect((try session.submitInput("observe()")).?.value.runtime.boolean);
    const assumptions = session.compiler.semantic.resolvers.core.session_namespace.?.assumptions.items.len;
    try std.testing.expectError(error.Reported, session.submitStatements("assume rejected ::= true\nmissing()"));
    try std.testing.expectEqual(assumptions, session.compiler.semantic.resolvers.core.session_namespace.?.assumptions.items.len);
    try std.testing.expect((try session.submitInput("observe()")).?.value.runtime.boolean);
    try session.reset();
    try session.submitDefinitions("observe := (.capability: &Bool) -> (.result: Bool) { result = capability& }\n");
    try std.testing.expectError(error.Reported, session.submitInput("observe()"));
    try session.close();
}

test "interactive inherited assumptions supply selected nested cleanup" {
    const allocator = std.testing.allocator;
    var sources = submissions.Sources.init(allocator);
    defer sources.deinit();
    var diagnostics = diagnostics_mod.Diagnostics.init(&allocator, &.{});
    defer diagnostics.deinit();
    const loaded = try sources.loadModule(&diagnostics, "Deinit#(.T: Type): Contract = (.deinit: (.self: $&T) -> ())");
    var core = loaded.*;
    core.is_bundled_core = true;
    var session: Interactive = undefined;
    try session.initWithSources(allocator, diagnostics.source_files, &.{core}, .{ .exhaustive_function_bodies = false }, .{});
    defer session.deinit();
    try session.submit("Resource: Type = ()");
    try session.submit("Capability := (.used: Bool)");
    try session.submit("implement Deinit#(Resource) (.deinit = (.self: $&Resource, .capability: $&Capability = reach capability) -> () { capability&.used = true })");
    try session.submitStatements("state :: Capability = (.used = false)\nassume capability ::= $&state");
    try session.submitStatements("if true {\nresource :: Resource = ()\n}");
    try std.testing.expect((try session.submitInput("state.used")).?.value.runtime.boolean);
    try session.close();
}

test "interactive virtual values retain their creation unit across submissions" {
    var session: Interactive = undefined;
    try session.init(std.testing.allocator, &.{}, .{ .exhaustive_function_bodies = false }, .{});
    defer session.deinit();
    try session.submit("Readable#(.Source: Type): Contract = (.read: (.source: &Source) -> (.result: Int32) where {})");
    try session.submit("Box := (.value: Int32)");
    try session.submit("read_box := (.source: &Box) -> (.result: Int32) { result = source&.value }");
    try session.submit("implement Readable#(Box) (.read = read_box)");
    try session.submitStatements("box :: Box = (.value = 42)\nerased ::= to_virtual#(.contract: Readable)(.value = &box)");
    const first = (try session.submitInput("Readable#().read(&erased).result")).?;
    try std.testing.expectEqual(@as(i128, 42), first.value.runtime.integer);
    try session.submitStatements("box.value = 7");
    const second = (try session.submitInput("Readable#().read(&erased).result")).?;
    try std.testing.expectEqual(@as(i128, 7), second.value.runtime.integer);
    try session.close();
}

test "interactive virtual calls can enter older and newer code units" {
    var session: Interactive = undefined;
    try session.init(std.testing.allocator, &.{}, .{ .exhaustive_function_bodies = false }, .{});
    defer session.deinit();
    try session.submit("Readable#(.Source: Type): Contract = (.read: (.source: &Source) -> (.result: Int32) where {})");
    try session.submit("Relay#(.Source: Type): Contract = (.relay: (.source: &Source, .target: &Virtual#(.contract: Readable)) -> (.result: Int32) where {})");
    try session.submit("RelayState: Type = ()");
    try session.submit("implement Relay#(RelayState) (.relay = (.source: &RelayState, .target: &Virtual#(.contract: Readable)) -> (.result: Int32) { result = Readable#().read(target).result })");
    try session.submitStatements("relay_state :: RelayState = ()\nrelay_handle ::= to_virtual#(.contract: Relay)(.value = &relay_state)");
    try session.submit("Box := (.value: Int32)");
    try session.submit("implement Readable#(Box) (.read = (.source: &Box) -> (.result: Int32) { result = source&.value })");
    try session.submitStatements("box :: Box = (.value = 42)\nreader_handle ::= to_virtual#(.contract: Readable)(.value = &box)");
    const result = (try session.submitInput("Relay#().relay(&relay_handle, &reader_handle).result")).?;
    try std.testing.expectEqual(@as(i128, 42), result.value.runtime.integer);
    try session.close();
}

test "interactive source IDs retain original metadata across commands" {
    const allocator = std.testing.allocator;
    var sources = submissions.Sources.init(allocator);
    defer sources.deinit();
    var diagnostics = diagnostics_mod.Diagnostics.init(&allocator, &.{});
    defer diagnostics.deinit();
    const loaded = try sources.loadModule(&diagnostics, "ImplicitlyCopyable#(.T: Type): Contract = ()\n" ++
        "SourceLocationId := (.value: UInt32)\n" ++
        "implement ImplicitlyCopyable#(SourceLocationId) ()\n" ++
        "SourceLocation := (.source_file: &CChar, .source_line: &CChar, .line: UIntNative, .column: UIntNative)\n" ++
        "source_location := (.id: SourceLocationId) -> (.location: SourceLocation) { abort }\n" ++
        "error_location_id := () -> (.location: SourceLocationId) { location = (.value = 0) }\n" ++
        "core_located := (.location: SourceLocationId = error_location_id()) -> (.value: UInt32) { value = location.value }\n");
    var core = loaded.*;
    core.is_bundled_core = true;
    // This isolated fixture supplies explicit checked metadata identities.
    for (core.functions.items) |*semantic| {
        const declaration = core.declarations.items[@intFromEnum(semantic.declaration)];
        semantic.flags.is_source_location_id = std.mem.eql(u8, core.text(declaration.name), "error_location_id");
        semantic.flags.is_source_location_resolver = std.mem.eql(u8, core.text(declaration.name), "source_location");
    }
    var session: Interactive = undefined;
    try session.initWithSources(allocator, diagnostics.source_files, &.{core}, .{ .exhaustive_function_bodies = false }, .{});
    defer session.deinit();
    const first = (try session.submitInput("error_location_id()")).?.value.runtime.record[0].integer;
    try std.testing.expectEqual(@as(usize, 1), session.runtime.context.trace_locations.items.len);
    const original = session.runtime.context.trace_locations.items[@intCast(first)];
    try std.testing.expectEqualStrings("error_location_id()", original.source_line);
    try std.testing.expectEqual(@as(u32, 1), original.line);
    try std.testing.expectEqual(@as(u32, 1), original.column);
    _ = try session.submitInput("error_location_id()");
    try std.testing.expectEqual(@as(usize, 2), session.runtime.context.trace_locations.items.len);
    try std.testing.expectEqualStrings(original.path, session.runtime.context.trace_locations.items[@intCast(first)].path);
    try session.submit("located := (.location: SourceLocationId = error_location_id()) -> (.value: UInt32) { value = location.value }");
    _ = try session.submitInput("located()");
    const defaulted = session.runtime.context.trace_locations.items[2];
    try std.testing.expect(std.mem.startsWith(u8, defaulted.source_line, "located :="));
    _ = try session.submitInput("core_located()");
    const core_default = session.runtime.context.trace_locations.items[3];
    try std.testing.expectEqualStrings("core_located()", core_default.source_line);
    try std.testing.expectEqual(@as(u32, 1), core_default.column);
    const recovered = (try session.submitInput("source_location(_0)")).?.value.runtime.record;
    try std.testing.expectEqual(@as(i128, 1), recovered[2].integer);
    try std.testing.expectEqual(@as(i128, 1), recovered[3].integer);
    for ("error_location_id()", 0..) |byte, index| {
        try std.testing.expectEqual(@as(i128, byte), (try session.runtime.context.storage.readOffset(recovered[1].reference, @intCast(index))).integer);
    }
    try std.testing.expectError(error.Reported, session.submitInput("#run () -> (.answer: SourceLocationId) { answer = error_location_id() }"));
    try session.reset();
    try std.testing.expectEqual(@as(usize, 0), session.runtime.context.trace_locations.items.len);
    try session.close();
}

test "interactive imports load folder dependencies transactionally and retain accepted source" {
    const a = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(io, "library");
    try tmp.dir.createDirPath(io, "dependency");
    try tmp.dir.createDirPath(io, "later");
    try tmp.dir.createDirPath(io, "broken");
    try tmp.dir.createDirPath(io, "cycle_a");
    try tmp.dir.createDirPath(io, "cycle_b");
    try tmp.dir.writeFile(io, .{ .sub_path = "dependency/main.rg", .data = "answer := () -> (.result: Int32) { result = 42 }" });
    try tmp.dir.writeFile(io, .{ .sub_path = "library/main.rg", .data = "dep := import(\"../dependency\")\nanswer := () -> (.result: Int32) { result = dep.answer() }" });
    try tmp.dir.writeFile(io, .{ .sub_path = "library/extra.rg", .data = "extra := () -> (.result: Int32) { result = 7 }" });
    try tmp.dir.writeFile(io, .{ .sub_path = "later/main.rg", .data = "dep := import(\"../dependency\")\nanswer := () -> (.result: Int32) { result = dep.answer() }" });
    try tmp.dir.writeFile(io, .{ .sub_path = "broken/main.rg", .data = "broken := () -> () {" });
    try tmp.dir.writeFile(io, .{ .sub_path = "cycle_a/main.rg", .data = "other := import(\"../cycle_b\")" });
    try tmp.dir.writeFile(io, .{ .sub_path = "cycle_b/main.rg", .data = "other := import(\"../cycle_a\")" });
    const base = try tmp.dir.realPathFileAlloc(io, ".", a);
    defer a.free(base);
    var session: Interactive = undefined;
    try session.init(a, &.{}, .{ .exhaustive_function_bodies = false }, .{});
    defer session.deinit();
    try session.enableImports(io, base);
    try session.submit("library := import(\"./library\")");
    try std.testing.expectEqual(@as(i128, 42), (try session.submitInput("library.answer()")).?.value.runtime.integer);
    try std.testing.expectEqual(@as(i128, 7), (try session.submitInput("library.extra()")).?.value.runtime.integer);
    // Already-published dependencies are immutable, even when another new
    // module imports them after the files have changed or become invalid.
    try tmp.dir.writeFile(io, .{ .sub_path = "dependency/main.rg", .data = "broken := () -> () {" });
    try session.submit("again := import(\"./library\")");
    try session.submit("later := import(\"./later\")");
    try std.testing.expectEqual(@as(i128, 42), (try session.submitInput("again.answer()")).?.value.runtime.integer);
    try std.testing.expectEqual(@as(i128, 42), (try session.submitInput("later.answer()")).?.value.runtime.integer);
    const revision = session.compiler.revision;
    try std.testing.expectError(error.ExpectedRightBrace, session.submit("bad := import(\"./broken\")"));
    try std.testing.expectEqual(revision, session.compiler.revision);
    try std.testing.expectError(error.ImportCycle, session.submit("cycle := import(\"./cycle_a\")"));
    try std.testing.expectEqual(revision, session.compiler.revision);
    try std.testing.expectError(error.UnknownModuleReference, session.compiler.semantic.resolvers.core.findModuleForQualifier(0, "bad"));
    try std.testing.expectError(error.Reported, session.submitInput("answer()"));
    try std.testing.expectEqual(@as(i128, 42), (try session.submitInput("library.answer()")).?.value.runtime.integer);
    try tmp.dir.writeFile(io, .{ .sub_path = "broken/main.rg", .data = "answer := () -> (.result: Int32) { result = 11 }" });
    try session.submit("bad := import(\"./broken\")");
    try std.testing.expectEqual(@as(i128, 11), (try session.submitInput("bad.answer()")).?.value.runtime.integer);
    try tmp.dir.writeFile(io, .{ .sub_path = "dependency/main.rg", .data = "answer := () -> (.result: Int32) { result = 99 }" });
    try session.reset();
    try session.submit("library := import(\"./library\")");
    try std.testing.expectEqual(@as(i128, 99), (try session.submitInput("library.answer()")).?.value.runtime.integer);
    try session.close();
}

test "interactive imported globals initialize once and retain mutation across units" {
    const a = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(io, "library");
    try tmp.dir.writeFile(io, .{ .sub_path = "library/main.rg", .data = "counter :: Int32 = 41\nadvance := () -> (.result: Int32) { result = counter\ncounter = 42 }" });
    const base = try tmp.dir.realPathFileAlloc(io, ".", a);
    defer a.free(base);
    var session: Interactive = undefined;
    try session.init(a, &.{}, .{ .exhaustive_function_bodies = false }, .{});
    defer session.deinit();
    try session.enableImports(io, base);
    try session.submit("library := import(\"./library\")");
    try std.testing.expectEqual(@as(i128, 41), (try session.submitInput("library.advance()")).?.value.runtime.integer);
    try session.submit("again := import(\"./library\")");
    try std.testing.expectEqual(@as(i128, 42), (try session.submitInput("again.advance()")).?.value.runtime.integer);
    try session.reset();
    try session.submit("library := import(\"./library\")");
    try std.testing.expectEqual(@as(i128, 41), (try session.submitInput("library.advance()")).?.value.runtime.integer);
    try session.close();
}

test "interactive prelude executes checked assumptions again after reset" {
    var session: Interactive = undefined;
    try session.init(std.testing.allocator, &.{}, .{ .exhaustive_function_bodies = false }, .{});
    defer session.deinit();
    try std.testing.expectError(error.Reported, session.initializePrelude("missing()"));
    try std.testing.expectEqual(@as(?[]const u8, null), session.prelude);
    try std.testing.expectEqual(@as(u64, 0), session.compiler.revision);
    const source = "enabled :: Bool = true\nassume capability ::= &enabled";
    try session.initializePrelude(source);
    try session.submit("observe := (.capability: &Bool) -> (.result: Bool) { result = capability& }");
    try std.testing.expect((try session.submitInput("observe()")).?.value.runtime.boolean);
    try session.submitStatements("enabled = false");
    try std.testing.expect(!(try session.submitInput("observe()")).?.value.runtime.boolean);
    try std.testing.expectError(error.PreludeRequiresFreshSession, session.initializePrelude("unwanted ::= true"));
    try session.reset();
    try std.testing.expectEqualStrings(source, session.prelude.?);
    try session.submit("observe := (.capability: &Bool) -> (.result: Bool) { result = capability& }");
    const result = (try session.submitInput("observe()")).?;
    try std.testing.expect(result.value.runtime.boolean);
    try std.testing.expectEqualStrings("_0", result.name);
    try session.close();
}

test "interactive reset retains the new compiler when prelude execution traps" {
    var session: Interactive = undefined;
    try session.init(std.testing.allocator, &.{}, .{ .exhaustive_function_bodies = false }, .{});
    defer session.deinit();
    try session.initializePrelude("enabled ::= true");
    // The old runtime can finish cleanup; only the replacement receives the
    // reduced instruction allowance and traps while evaluating the prelude.
    session.limits.instructions = 1;
    try std.testing.expectError(error.ExecutionInstructionLimit, session.reset());
    try std.testing.expectEqual(.poisoned, session.runtime.context.state);
    session.limits.instructions = 1_000_000;
    try session.reset();
    try std.testing.expect((try session.submitInput("enabled")).?.value.runtime.boolean);
    try session.close();
}

test "interactive once consumption survives commands and rejected candidates" {
    var session: Interactive = undefined;
    try session.init(std.testing.allocator, &.{}, .{ .exhaustive_function_bodies = false }, .{});
    defer session.deinit();
    const definition = "once acquire := () -> (.result: Int32) { result = 42 }";
    try session.submit(definition);
    try std.testing.expectError(error.Reported, session.submitInput("#run () -> (.answer: Int32) { answer = acquire() }"));
    // Neither unresolved commands nor repeated uses in a rejected candidate
    // may consume the once identity retained by the accepted session.
    try std.testing.expectError(error.Reported, session.submitStatements("unused ::= acquire()\nmissing()"));
    try std.testing.expectError(error.Reported, session.submitStatements("first ::= acquire()\nsecond ::= acquire()"));
    try session.submit("helper := () -> (.result: Int32) { result = acquire() }");
    try std.testing.expectError(error.Reported, session.submitStatements("first ::= helper()\nsecond ::= helper()"));
    try std.testing.expectEqual(@as(i128, 42), (try session.submitInput("acquire()")).?.value.runtime.integer);
    const revision = session.compiler.revision;
    try std.testing.expectError(error.Reported, session.submitInput("acquire()"));
    try std.testing.expectEqual(revision, session.compiler.revision);
    try std.testing.expectEqual(.ready, session.runtime.context.state);
    try std.testing.expect(std.mem.indexOf(u8, session.diagnostics.list.items[0].msg, "consumed more than once") != null);
    try session.submit("again := () -> (.result: Int32) { result = acquire() }");
    try std.testing.expectError(error.Reported, session.submitInput("again()"));
    try std.testing.expectEqual(@as(i128, 7), (try session.submitInput("7")).?.value.runtime.integer);
    try session.reset();
    try session.submit(definition);
    try std.testing.expectEqual(@as(i128, 42), (try session.submitInput("acquire()")).?.value.runtime.integer);
    try session.close();
}

test "interactive once capabilities retain deferred temporary storage" {
    var session: Interactive = undefined;
    try session.init(std.testing.allocator, &.{}, .{ .exhaustive_function_bodies = false }, .{});
    defer session.deinit();
    try session.submitDefinitions("Token := (.value: Int32)\nonce acquire := () -> (.result: Token) { result = (.value = 42) }\nobserve := (.capability: &Token) -> (.result: Int32) { result = capability&.value }");
    try session.submitStatements("assume capability ::= $&acquire()");
    try std.testing.expectEqual(@as(i128, 42), (try session.submitInput("observe()")).?.value.runtime.integer);
    try std.testing.expectEqual(@as(i128, 42), (try session.submitInput("observe()")).?.value.runtime.integer);
    try std.testing.expectError(error.Reported, session.submitInput("acquire()"));
    try session.close();
}

test "interactive deferred owners retain their checked cleanup" {
    const allocator = std.testing.allocator;
    var sources = submissions.Sources.init(allocator);
    defer sources.deinit();
    var diagnostics = diagnostics_mod.Diagnostics.init(&allocator, &.{});
    defer diagnostics.deinit();
    const loaded = try sources.loadModule(&diagnostics, "Deinit#(.T: Type): Contract = (.deinit: (.self: $&T) -> ())");
    var core = loaded.*;
    core.is_bundled_core = true;
    var session: Interactive = undefined;
    try session.initWithSources(allocator, diagnostics.source_files, &.{core}, .{ .exhaustive_function_bodies = false }, .{});
    defer session.deinit();
    try session.submitDefinitions("Resource := (.value: Int32)\nonce acquire := () -> (.result: Resource) { result = (.value = 42) }\nobserve := (.resource: &Resource) -> (.result: Int32) { result = resource&.value }");
    try session.submitDefinitions("implement Deinit#(Resource) (.deinit = (.self: $&Resource) -> () {})");
    try session.submitStatements("assume resource ::= $&acquire()");
    try std.testing.expectEqual(@as(i128, 42), (try session.submitInput("observe()")).?.value.runtime.integer);
    const binding = session.compiler.semantic.resolvers.expressions.session_bindings.items[0];
    const frame = session.runtime.context.bindings.get(binding).?;
    const flags = session.runtime.context.storage.frames.items[@intFromEnum(frame)].cleanup_flags;
    const cleanup = session.runtime.context.storage.frames.items[@intFromEnum(frame)].cleanup;
    try std.testing.expect(cleanup.len != 0);
    const flag = cleanup[0].offset;
    try std.testing.expect(flags[flag]);
    try session.close();
    try std.testing.expect(!flags[flag]);
}

test "interactive deferred condition storage can be initialized repeatedly" {
    var session: Interactive = undefined;
    try session.init(std.testing.allocator, &.{}, .{ .exhaustive_function_bodies = false }, .{});
    defer session.deinit();
    try session.submitDefinitions("State := (.used: Bool)\nproduce := (.state: $&State) -> (.result: Bool) { if state&.used { result = false } else { state&.used = true\nresult = true } }\nobserve := (.value: &Bool) -> (.result: Bool) { result = value& }");
    try session.submitStatements("state :: State = (.used = false)");
    try session.submitStatements("while observe(.value = &produce(.state = $&state)) {}");
    try std.testing.expect((try session.submitInput("state.used")).?.value.runtime.boolean);
    try session.close();
}

test "interactive once defaults consume only completed call arguments" {
    var session: Interactive = undefined;
    try session.init(std.testing.allocator, &.{}, .{ .exhaustive_function_bodies = false }, .{});
    defer session.deinit();
    try session.submitDefinitions("once acquire := () -> (.result: Int32) { result = 42 }\nwith_default := (.value: Int32 = acquire()) -> (.result: Int32) { result = value }");
    try std.testing.expectEqual(@as(i128, 7), (try session.submitInput("with_default(.value = 7)")).?.value.runtime.integer);
    try std.testing.expectEqual(@as(i128, 42), (try session.submitInput("with_default()")).?.value.runtime.integer);
    try std.testing.expectError(error.Reported, session.submitInput("acquire()"));
    try session.close();
}

test "interactive generic diagnostics explain omitted reachable capabilities" {
    for ([_]bool{ false, true }) |bundled| {
        const allocator = std.testing.allocator;
        var sources = submissions.Sources.init(allocator);
        defer sources.deinit();
        var diagnostics = diagnostics_mod.Diagnostics.init(&allocator, &.{});
        defer diagnostics.deinit();
        const definition = "emit := #(.Stream: Type) (.value: Int32, .writer: $&Stream = reach writer) -> (.result: Int32) { result = value }";
        const loaded = try sources.loadModule(&diagnostics, definition);
        var core = loaded.*;
        core.is_bundled_core = true;
        var session: Interactive = undefined;
        if (bundled) {
            try session.initWithSources(allocator, diagnostics.source_files, &.{core}, .{ .exhaustive_function_bodies = false }, .{});
        } else {
            try session.init(allocator, &.{}, .{ .exhaustive_function_bodies = false }, .{});
        }
        defer session.deinit();
        if (!bundled) try session.submitDefinitions(definition);
        const revision = session.compiler.revision;
        try std.testing.expectError(error.Reported, session.submitInput("emit(.value = 42)"));
        try std.testing.expectEqual(revision, session.compiler.revision);
        const message = session.diagnostics.list.items[0].msg;
        try std.testing.expect(std.mem.indexOf(u8, message, ".writer uses reach writer") != null);
        try std.testing.expect(std.mem.indexOf(u8, message, "explicitly") != null);
        try session.submitStatements("destination :: (.used: Bool) = (.used = false)");
        try std.testing.expectEqual(@as(i128, 42), (try session.submitInput("emit(.value = 42, .writer = $&destination)")).?.value.runtime.integer);
        try session.submitStatements("assume writer ::= $&destination");
        try std.testing.expectEqual(@as(i128, 42), (try session.submitInput("emit(.value = 42)")).?.value.runtime.integer);
        try session.close();
    }
}

test "interactive scalar host calls require explicit bindings before publication" {
    const allocator = std.testing.allocator;
    var sources = submissions.Sources.init(allocator);
    defer sources.deinit();
    var diagnostics = diagnostics_mod.Diagnostics.init(&allocator, &.{});
    defer diagnostics.deinit();
    const loaded = try sources.loadModule(&diagnostics, "ForeignFunctionInterface: Type = ()\nhost_increment(.value: Int32) -> (.result: Int32): ExternFunction\nhost_reference(.value: &Int32) -> (.result: Int32): ExternFunction");
    var core = loaded.*;
    core.is_bundled_core = true;
    var session: Interactive = undefined;
    try session.initWithSources(allocator, diagnostics.source_files, &.{core}, .{ .exhaustive_function_bodies = false }, .{});
    defer session.deinit();
    try session.submitStatements("capability :: ForeignFunctionInterface = ()\nassume ffi ::= $&capability\nnumber :: Int32 = 41");
    const revision = session.compiler.revision;
    try std.testing.expectError(error.Reported, session.submitInput("host_reference(.value = &number)"));
    try std.testing.expectEqual(revision, session.compiler.revision);
    try std.testing.expect(std.mem.indexOf(u8, session.diagnostics.list.items[0].msg, "scalar host boundary") != null);
    try std.testing.expectError(error.Reported, session.submitInput("host_increment(.value = 41)"));
    try std.testing.expectEqual(revision, session.compiler.revision);
    try std.testing.expectEqual(.ready, session.runtime.context.state);
    try std.testing.expect(std.mem.indexOf(u8, session.diagnostics.list.items[0].msg, "host binding") != null);
    const Host = @import("host.zig");
    const State = struct {
        calls: usize = 0,
        invalid_result: bool = false,
        fail: bool = false,
        fn invoke(data: ?*anyopaque, inputs: []const i128, outputs: []i128) !void {
            const self: *@This() = @ptrCast(@alignCast(data.?));
            try std.testing.expectEqual(@as(usize, 1), inputs.len);
            try std.testing.expectEqual(@as(usize, 1), outputs.len);
            self.calls += 1;
            if (self.fail) return error.TestHostFailure;
            if (!self.invalid_result) outputs[0] = inputs[0] + 1;
        }
    };
    var state: State = .{};
    const range = @import("../4_semantics/primitives/schema.zig").integerRangeForWidth(32, true);
    var bindings = [_]Host.Binding{.{ .symbol = "host_increment", .inputs = &.{range}, .outputs = &.{range}, .data = &state, .call = State.invoke }};
    bindings[0].inputs = &.{@import("../4_semantics/primitives/schema.zig").integerRangeForWidth(64, true)};
    session.runtime.context.host_bindings = &bindings;
    try std.testing.expectError(error.Reported, session.submitInput("host_increment(.value = 41)"));
    try std.testing.expectEqual(revision, session.compiler.revision);
    try std.testing.expectEqual(@as(usize, 0), state.calls);
    bindings[0].inputs = &.{range};
    const duplicated = [_]Host.Binding{ bindings[0], bindings[0] };
    session.runtime.context.host_bindings = &duplicated;
    try std.testing.expectError(error.Reported, session.submitInput("host_increment(.value = 41)"));
    try std.testing.expectEqual(revision, session.compiler.revision);
    try std.testing.expectEqual(@as(usize, 0), state.calls);
    session.runtime.context.host_bindings = &bindings;
    try std.testing.expectEqual(@as(i128, 42), (try session.submitInput("host_increment(.value = 41)")).?.value.runtime.integer);
    try std.testing.expectEqual(@as(usize, 1), state.calls);
    try std.testing.expectError(error.Reported, session.submitInput("#run () -> (.answer: Int32) { answer = host_increment(.value = 41) }"));
    try std.testing.expectEqual(@as(usize, 1), state.calls);
    const negative = (try session.submitInput("host_increment(.value = -42)")).?.value.runtime.integer;
    try std.testing.expectEqual(@as(i128, -41), @import("../5_codegen/integer_arithmetic.zig").decode(negative, range));
    const minimum = (try session.submitInput("host_increment(.value = -2147483648)")).?.value.runtime.integer;
    try std.testing.expectEqual(range.minimum + 1, @import("../5_codegen/integer_arithmetic.zig").decode(minimum, range));
    state.invalid_result = true;
    try std.testing.expectError(error.ExecutionInvalidHostResult, session.submitInput("host_increment(.value = 41)"));
    try std.testing.expectEqual(.poisoned, session.runtime.context.state);
    try session.reset();
    try std.testing.expectEqual(@as(usize, 1), session.runtime.context.host_bindings.len);
    const calls_before_missing_capability = state.calls;
    try std.testing.expectError(error.Reported, session.submitInput("host_increment(.value = 41)"));
    try std.testing.expectEqual(calls_before_missing_capability, state.calls);
    try std.testing.expectEqual(.fresh, session.runtime.context.state);
    try session.submitStatements("capability :: ForeignFunctionInterface = ()\nassume ffi ::= $&capability");
    state.invalid_result = false;
    try std.testing.expectEqual(@as(i128, 42), (try session.submitInput("host_increment(.value = 41)")).?.value.runtime.integer);
    state.fail = true;
    try std.testing.expectError(error.TestHostFailure, session.submitInput("host_increment(.value = 41)"));
    try std.testing.expectEqual(.poisoned, session.runtime.context.state);
    try session.reset();
    try session.close();
}

test "interactive vacant records retain partial initialization across commands" {
    var session: Interactive = undefined;
    try session.init(std.testing.allocator, &.{}, .{ .exhaustive_function_bodies = false }, .{});
    defer session.deinit();
    try session.submitStatements("pair :: (.first: Int32, .second: Int32)");
    const revision = session.compiler.revision;
    try std.testing.expectError(error.Reported, session.submitInput("pair.first"));
    try std.testing.expectEqual(revision, session.compiler.revision);
    try session.submitStatements("pair.first = 41");
    try std.testing.expectEqual(@as(i128, 41), (try session.submitInput("pair.first")).?.value.runtime.integer);
    try std.testing.expectError(error.Reported, session.submitInput("pair.second"));
    try std.testing.expectError(error.Reported, session.submitInput("pair"));
    try session.submitStatements("pair.second = 42");
    const complete = (try session.submitInput("pair")).?;
    try std.testing.expectEqual(@as(i128, 42), complete.value.runtime.record[1].integer);
    try session.submitStatements("number :: Int32");
    try std.testing.expectError(error.Reported, session.submitInput("number"));
    try session.submitStatements("number = 42");
    try std.testing.expectEqual(@as(i128, 42), (try session.submitInput("number")).?.value.runtime.integer);
    try session.submitStatements("empty :: (.leaf: ())");
    try std.testing.expectError(error.Reported, session.submitInput("empty"));
    try session.submitStatements("empty.leaf = ()");
    try std.testing.expectEqual(@as(usize, 1), (try session.submitInput("empty")).?.value.runtime.record.len);
    try session.close();
}

test "interactive partial records clean initialized owners at exit" {
    const allocator = std.testing.allocator;
    var sources = submissions.Sources.init(allocator);
    defer sources.deinit();
    var diagnostics = diagnostics_mod.Diagnostics.init(&allocator, &.{});
    defer diagnostics.deinit();
    const loaded = try sources.loadModule(&diagnostics, "Deinit#(.T: Type): Contract = (.deinit: (.self: $&T) -> ())");
    var core = loaded.*;
    core.is_bundled_core = true;
    var session: Interactive = undefined;
    try session.initWithSources(allocator, diagnostics.source_files, &.{core}, .{ .exhaustive_function_bodies = false }, .{});
    defer session.deinit();
    try session.submitDefinitions("Resource: Type = ()\nmake := () -> (.result: Resource) { result = () }");
    try session.submitDefinitions("implement Deinit#(Resource) (.deinit = (.self: $&Resource) -> () {})");
    try session.submitStatements("pair :: (.first: Resource, .second: Resource)");
    try session.submitStatements("pair.first = make()");
    const binding = session.compiler.semantic.resolvers.expressions.session_bindings.items[0];
    const frame = session.runtime.context.bindings.get(binding).?;
    const flags = session.runtime.context.storage.frames.items[@intFromEnum(frame)].cleanup_flags;
    var active: usize = 0;
    for (flags) |enabled| if (enabled) {
        active += 1;
    };
    try std.testing.expectEqual(@as(usize, 1), active);
    try session.close();
    for (flags) |enabled| try std.testing.expect(!enabled);
}

test "interactive owning arrays complete cleanup across submissions" {
    const allocator = std.testing.allocator;
    var sources = submissions.Sources.init(allocator);
    defer sources.deinit();
    var diagnostics = diagnostics_mod.Diagnostics.init(&allocator, &.{});
    defer diagnostics.deinit();
    const loaded = try sources.loadModule(&diagnostics, "Deinit#(.T: Type): Contract = (.deinit: (.self: $&T) -> ())");
    var core = loaded.*;
    core.is_bundled_core = true;
    var session: Interactive = undefined;
    try session.initWithSources(allocator, diagnostics.source_files, &.{core}, .{ .exhaustive_function_bodies = false }, .{});
    defer session.deinit();
    try session.submitDefinitions("Resource: Type = ()\nmake := () -> (.result: Resource) { result = () }");
    try session.submitDefinitions("implement Deinit#(Resource) (.deinit = (.self: $&Resource) -> () {})");
    try session.submitStatements("resources :: [2]Resource");
    try session.submitStatements("resources[0] = make()");
    const revision = session.compiler.revision;
    try std.testing.expectError(error.Reported, session.submitInput("resources[1]"));
    try std.testing.expectEqual(revision, session.compiler.revision);
    try session.submitStatements("resources[1] = make()");
    const binding = session.compiler.semantic.resolvers.expressions.session_bindings.items[0];
    const frame = session.runtime.context.bindings.get(binding).?;
    const flags = session.runtime.context.storage.frames.items[@intFromEnum(frame)].cleanup_flags;
    try std.testing.expectEqual(@as(usize, 3), flags.len);
    for (flags) |enabled| try std.testing.expect(enabled);
    try session.close();
    for (flags) |enabled| try std.testing.expect(!enabled);
}

test "interactive arrays retain initialized elements across commands" {
    var session: Interactive = undefined;
    try session.init(std.testing.allocator, &.{}, .{ .exhaustive_function_bodies = false }, .{});
    defer session.deinit();
    try session.submitStatements("numbers :: [2]Int32");
    session.submitStatements("numbers[0] = 40") catch |err| {
        try session.diagnostics.dump();
        return err;
    };
    try std.testing.expectEqual(@as(i128, 40), (try session.submitInput("numbers[0]")).?.value.runtime.integer);
    const revision = session.compiler.revision;
    try std.testing.expectError(error.Reported, session.submitInput("numbers[1]"));
    try std.testing.expectError(error.Reported, session.submitInput("numbers"));
    try std.testing.expectEqual(revision, session.compiler.revision);
    try session.submitStatements("numbers[1] = 42");
    const complete = (try session.submitInput("numbers")).?;
    try std.testing.expectEqual(@as(i128, 42), complete.value.runtime.array[1].integer);
    try session.close();
}

test "interactive computed imports share staged selection without replaying accepted state" {
    const a = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    for ([_][]const u8{ "library", "dependency", "broken", "cycle" }) |dir| try tmp.dir.createDirPath(io, dir);
    try tmp.dir.writeFile(io, .{ .sub_path = "dependency/main.rg", .data = "enabled := () -> (.ok: Bool) { ok = true }\nanswer := () -> (.value: Int32) { value = 42 }" });
    try tmp.dir.writeFile(io, .{ .sub_path = "library/main.rg", .data = "choose := () -> (.ok: Bool) { ok = true }\n#if choose() { dep := import(\"../dependency\")\n#if dep.enabled() { answer := () -> (.value: Int32) { value = dep.answer() } } } #else { missing := import(\"../missing\") }" });
    try tmp.dir.writeFile(io, .{ .sub_path = "broken/main.rg", .data = "choose := () -> (.value: Int32) { value = 1 }\n#if choose() { answer := () -> (.value: Int32) { value = 11 } }" });
    try tmp.dir.writeFile(io, .{ .sub_path = "cycle/main.rg", .data = "choose := () -> (.ok: Bool) { ok = true }\n#if choose() { self := import(\"./\") }" });
    const base = try tmp.dir.realPathFileAlloc(io, ".", a);
    defer a.free(base);
    var session: Interactive = undefined;
    try session.init(a, &.{}, .{ .exhaustive_function_bodies = false, .root_selection = .requests_only }, .{});
    defer session.deinit();
    try session.enableImports(io, base);
    try session.submitStatements("retained :: Int32 = 7");
    try session.submit("library := import(\"./library\")");
    try std.testing.expectEqual(@as(i128, 42), (try session.submitInput("library.answer()")).?.value.runtime.integer);
    try std.testing.expectEqual(@as(i128, 7), (try session.submitInput("retained")).?.value.runtime.integer);
    const revision = session.compiler.revision;
    const module_count = session.compiler.semantic.modules.len;
    try std.testing.expectError(error.Reported, session.submit("bad := import(\"./broken\")"));
    try std.testing.expectEqual(revision, session.compiler.revision);
    try std.testing.expectEqual(module_count, session.compiler.semantic.modules.len);
    const unsafe_revision = "\n\nchoose := () -> (.ok: Bool) { flag: Bool\n ok = flag }\n#if choose() { answer := () -> (.value: Int32) { value = 11 } }";
    try tmp.dir.writeFile(io, .{ .sub_path = "broken/main.rg", .data = unsafe_revision });
    try std.testing.expectError(error.Reported, session.submit("bad := import(\"./broken\")"));
    var found_current_source = false;
    for (session.diagnostics.list.items) |diagnostic| {
        const file = session.diagnostics.source_db.get(diagnostic.loc.file);
        if (std.mem.eql(u8, std.fs.path.basename(file.path), "main.rg") and
            std.mem.eql(u8, std.fs.path.basename(std.fs.path.dirname(file.path) orelse ""), "broken"))
        {
            try std.testing.expectEqualStrings(unsafe_revision, file.source);
            found_current_source = true;
        }
    }
    try std.testing.expect(found_current_source);
    try std.testing.expectEqual(revision, session.compiler.revision);
    try std.testing.expectError(error.Reported, session.submit("cycle := import(\"./cycle\")"));
    try std.testing.expectEqual(revision, session.compiler.revision);
    try std.testing.expectEqual(module_count, session.compiler.semantic.modules.len);
    try tmp.dir.writeFile(io, .{ .sub_path = "broken/main.rg", .data = "choose := () -> (.ok: Bool) { ok = true }\n#if choose() { answer := () -> (.value: Int32) { value = 11 } }" });
    try session.submit("fixed := import(\"./broken\")");
    try std.testing.expectEqual(@as(i128, 11), (try session.submitInput("fixed.answer()")).?.value.runtime.integer);
    try tmp.dir.writeFile(io, .{ .sub_path = "library/main.rg", .data = "broken := () -> () {" });
    try session.submit("again := import(\"./library\")");
    try std.testing.expectEqual(@as(i128, 42), (try session.submitInput("again.answer()")).?.value.runtime.integer);
    try session.close();
}

test "interactive unknown names report original input without publishing bindings" {
    var session: Interactive = undefined;
    try session.init(std.testing.allocator, &.{}, .{ .exhaustive_function_bodies = false }, .{});
    defer session.deinit();
    try session.submitStatements("retained :: Int32 = 42");
    for ([_][]const u8{ "unknown_value", "copy ::= unknown_value", "retained = unknown_value" }) |input| {
        const revision = session.compiler.revision;
        const count = session.compiler.semantic.resolvers.expressions.session_bindings.items.len;
        try std.testing.expectError(error.Reported, session.submitInput(input));
        try std.testing.expectEqual(revision, session.compiler.revision);
        try std.testing.expectEqual(count, session.compiler.semantic.resolvers.expressions.session_bindings.items.len);
        const diagnostic = session.diagnostics.list.items[0];
        try std.testing.expectEqualStrings("unknown name 'unknown_value' in this scope", diagnostic.msg);
        const original = session.diagnostics.source_db.get(diagnostic.loc.file);
        try std.testing.expectEqualStrings(input, original.source);
        try std.testing.expectEqual(@as(u32, @intCast(std.mem.indexOf(u8, input, "unknown_value").?)), diagnostic.loc.offset);
        try std.testing.expectEqual(@as(i128, 42), (try session.submitInput("retained")).?.value.runtime.integer);
    }
    // Ordinary lazy checking still permits an unused definition. Calling it
    // checks its body and reports the original definition's missing name.
    try session.submitDefinitions("unused := () -> (.value: Int32) { value = unknown_value }");
    const revision = session.compiler.revision;
    try std.testing.expectError(error.Reported, session.submitInput("unused()"));
    try std.testing.expectEqual(revision, session.compiler.revision);
    try std.testing.expectEqualStrings("unknown name 'unknown_value' in this scope", session.diagnostics.list.items[0].msg);
    try std.testing.expectEqual(@as(i128, 42), (try session.submitInput("retained")).?.value.runtime.integer);
    try session.close();
}

test "interactive generic functions use explicit inputs without capturing retained values" {
    var session: Interactive = undefined;
    try session.init(std.testing.allocator, &.{}, .{ .exhaustive_function_bodies = false }, .{});
    defer session.deinit();
    try session.submitStatements("retained :: Int32 = 42");
    try session.submitDefinitions("identity := #(.T: Type) (.value: T) -> (.result: T) { result = value }");
    try session.submitDefinitions("read := #(.T: Type) (.value: T) -> (.result: Int32) { result = retained }");
    try std.testing.expectEqual(@as(i128, 42), (try session.submitInput("identity(.value = retained)")).?.value.runtime.integer);
    try session.submitStatements("fixed: Int32 = 7");
    try std.testing.expectEqual(@as(i128, 7), (try session.submitInput("#run () -> (.answer: Int32) { answer = identity(.value = fixed) }")).?.value.runtime.integer);
    try session.submitStatements("loan ::= identity(.value = &retained)");
    const revision = session.compiler.revision;
    try std.testing.expectError(error.Reported, session.submitInput("read(.value = true)"));
    try std.testing.expectEqualStrings("unknown name 'retained' in this scope", session.diagnostics.list.items[0].msg);
    try std.testing.expectEqual(revision, session.compiler.revision);
    try std.testing.expectError(error.Reported, session.submitInput("#run () -> (.answer: Int32) { answer = identity(.value = retained) }"));
    try std.testing.expect(std.mem.indexOf(u8, session.diagnostics.list.items[0].msg, "runtime values cannot be used") != null);
    try std.testing.expectEqual(revision, session.compiler.revision);
    try std.testing.expectEqual(@as(i128, 42), (try session.submitInput("loan&")).?.value.runtime.integer);
    try session.submitStatements("retained = 7");
    try std.testing.expectEqual(@as(i128, 7), (try session.submitInput("loan&")).?.value.runtime.integer);
    try std.testing.expectEqual(@as(i128, 7), (try session.submitInput("identity(.value = retained)")).?.value.runtime.integer);
    try session.close();
}

test "interactive computed conditions retain reconstructed type bindings across commands" {
    var session: Interactive = undefined;
    try session.init(std.testing.allocator, &.{}, .{ .exhaustive_function_bodies = false }, .{});
    defer session.deinit();
    try session.submitDefinitions(
        "Cell := (.value: Int32)\n" ++
            "decide := #(.T: Type) () -> (.ok: Bool) { width ::= size_of(.type = T)\n ok = true }\n" ++
            "choose := #(.T: Type) (.value: T) -> (.result: Int32) { #if decide#(.T: T)() { result = 42 } #else { result = 0 } }\n" ++
            "outer := #(.T: Type) (.value: T) -> (.result: Int32) { result = choose#(.T: &T)(.value = &value) }",
    );
    try session.submitStatements("cell :: Cell = (.value = 1)");
    try std.testing.expectEqual(@as(i128, 42), (try session.submitInput("outer(.value = cell)")).?.value.runtime.integer);
    const revision = session.compiler.revision;
    try std.testing.expectError(error.Reported, session.submitInput("missing_value"));
    try std.testing.expectEqual(revision, session.compiler.revision);
    try std.testing.expectEqual(@as(i128, 42), (try session.submitInput("outer(.value = cell)")).?.value.runtime.integer);
    try session.submitDefinitions("Other := (.flag: Bool)");
    try session.submitStatements("other :: Other = (.flag = true)");
    try std.testing.expectEqual(@as(i128, 42), (try session.submitInput("outer(.value = other)")).?.value.runtime.integer);
    try session.close();
}

test "interactive computed conditions retain choice defaults in temporary type bindings" {
    var session: Interactive = undefined;
    try session.init(std.testing.allocator, &.{}, .{ .exhaustive_function_bodies = false }, .{});
    defer session.deinit();
    errdefer for (session.diagnostics.list.items) |diagnostic| {
        std.debug.print("choice-default session: {s}\n", .{diagnostic.msg});
    };
    try session.submitDefinitions(
        "Choice: Type = (..present(.value: Int32), ..empty)\n" ++
            "decide := #(.T: Type) () -> (.ok: Bool) { width ::= size_of(.type = T)\n ok = true }\n" ++
            "choose := #(.T: Type) (.value: T) -> (.result: Int32) { #if decide#(.T: T)() { match value.selection { ..present selected { result = selected.value } ..empty { result = 0 } } } #else { result = 0 } }\n" ++
            "outer := #(.T: Type) (.value: T) -> (.result: Int32) { result = choose#(.T: (.value: T, .selection: Choice = #run () -> (.result: Choice) { result = ..present(.value = 42) }))(.value = (.value = value)) }",
    );
    try std.testing.expectEqual(@as(u64, 42), (try session.submitInput("outer(.value = 7)")).?.value.runtime.integer);
    const revision = session.compiler.revision;
    try std.testing.expectError(error.Reported, session.submitInput("missing_choice_default"));
    try std.testing.expectEqual(revision, session.compiler.revision);
    try std.testing.expectEqual(@as(u64, 42), (try session.submitInput("outer(.value = true)")).?.value.runtime.integer);
    try session.close();
}

test "interactive virtual methods link host calls against their retained code unit" {
    const allocator = std.testing.allocator;
    var sources = submissions.Sources.init(allocator);
    defer sources.deinit();
    var diagnostics = diagnostics_mod.Diagnostics.init(&allocator, &.{});
    defer diagnostics.deinit();
    const loaded = try sources.loadModule(&diagnostics, "ForeignFunctionInterface: Type = ()\n" ++
        "host_increment(.value: Int32) -> (.result: Int32): ExternFunction\n" ++
        "host_identity(.value: Int32) -> (.result: Int32): ExternFunction");
    var core = loaded.*;
    core.is_bundled_core = true;
    var session: Interactive = undefined;
    try session.initWithSources(allocator, diagnostics.source_files, &.{core}, .{ .exhaustive_function_bodies = false }, .{});
    defer session.deinit();
    const State = struct {
        calls: usize = 0,
        fn increment(data: ?*anyopaque, inputs: []const i128, outputs: []i128) !void {
            const self: *@This() = @ptrCast(@alignCast(data.?));
            self.calls += 1;
            outputs[0] = inputs[0] + 1;
        }
        fn identity(_: ?*anyopaque, inputs: []const i128, outputs: []i128) !void {
            outputs[0] = inputs[0];
        }
    };
    var state: State = .{};
    const host = @import("host.zig");
    const range = @import("../4_semantics/primitives/schema.zig").integerRangeForWidth(32, true);
    const bindings = [_]host.Binding{
        .{ .symbol = "host_increment", .inputs = &.{range}, .outputs = &.{range}, .data = &state, .call = State.increment },
        .{ .symbol = "host_identity", .inputs = &.{range}, .outputs = &.{range}, .call = State.identity },
    };
    session.runtime.context.host_bindings = &bindings;
    try session.submitDefinitions("Readable#(.Source: Type): Contract = (.read: (.source: &Source, .ffi: $&ForeignFunctionInterface) -> (.result: Int32) where {})\nBox: Type = ()\nimplement Readable#(Box) (.read = (.source: &Box, .ffi: $&ForeignFunctionInterface) -> (.result: Int32) { first ::= host_increment(.value = 40, .ffi = ffi)\nresult = host_increment(.value = first, .ffi = ffi) })");
    try session.submitStatements("capability :: ForeignFunctionInterface = ()\nassume ffi ::= $&capability\nbox :: Box = ()\nerased ::= to_virtual#(.contract: Readable)(.value = &box)");
    try session.submitDefinitions("invoke := (.handle: &Virtual#(.contract: Readable), .ffi: $&ForeignFunctionInterface) -> (.result: Int32) { unused ::= host_identity(.value = 7, .ffi = ffi)\nresult = Readable#().read(handle, .ffi = ffi).result }");
    try std.testing.expectEqual(@as(u64, 42), (try session.submitInput("invoke(.handle = &erased, .ffi = ffi)")).?.value.runtime.integer);
    try std.testing.expectEqual(@as(usize, 2), state.calls);
    try std.testing.expectEqual(@as(u64, 42), (try session.submitInput("invoke(.handle = &erased, .ffi = ffi)")).?.value.runtime.integer);
    try std.testing.expectEqual(@as(usize, 4), state.calls);
    try session.close();
}

test "interactive cancellation preserves completed effects and stops later host calls" {
    const a = std.testing.allocator;
    var sources = submissions.Sources.init(a);
    defer sources.deinit();
    var diagnostics = diagnostics_mod.Diagnostics.init(&a, &.{});
    defer diagnostics.deinit();
    const loaded = try sources.loadModule(&diagnostics, "ForeignFunctionInterface: Type = ()\nhost_step() -> (): ExternFunction");
    var core = loaded.*;
    core.is_bundled_core = true;
    var cancellation: vm.Cancellation = .{};
    var session: Interactive = undefined;
    try session.initWithSources(a, diagnostics.source_files, &.{core}, .{ .exhaustive_function_bodies = false }, .{ .cancellation = &cancellation });
    defer session.deinit();
    const HostState = struct {
        cancellation: *vm.Cancellation,
        calls: usize = 0,
        cancel: bool = true,
        fn step(data: ?*anyopaque, _: []const i128, _: []i128) !void {
            const self: *@This() = @ptrCast(@alignCast(data.?));
            self.calls += 1;
            if (self.cancel) self.cancellation.cancel();
        }
    };
    var host_state: HostState = .{ .cancellation = &cancellation };
    const bindings = [_]@import("host.zig").Binding{.{ .symbol = "host_step", .inputs = &.{}, .outputs = &.{}, .data = &host_state, .call = HostState.step }};
    session.runtime.context.host_bindings = &bindings;
    try session.submitStatements("capability :: ForeignFunctionInterface = ()\nassume ffi ::= $&capability\nnumber :: Int32 = 1");
    const number = session.compiler.semantic.resolvers.expressions.session_bindings.items[2];
    const revision = session.compiler.revision;
    try std.testing.expectError(error.ExecutionCancelled, session.submitStatements("number = 7\nhost_step()\nnumber = 99\nhost_step()"));
    try std.testing.expectEqual(@as(usize, 1), host_state.calls);
    // Published effects are not rolled back on cancellation. The context is
    // inspectable by its host, but cannot execute any more language code.
    const slots = try session.runtime.context.storage.slots(session.runtime.context.bindings.get(number).?);
    try std.testing.expectEqual(@as(i128, 7), (try slots.get(0)).integer);
    try std.testing.expectEqual(revision + 1, session.compiler.revision);
    try std.testing.expectEqual(.poisoned, session.runtime.context.state);
    try std.testing.expectError(error.ExecutionContextPoisoned, session.submitInput("number"));
    cancellation.reset();
    try session.reset();
    host_state.cancel = false;
    try session.submitStatements("capability :: ForeignFunctionInterface = ()\nassume ffi ::= $&capability");
    try session.submitStatements("host_step()");
    try std.testing.expectEqual(@as(usize, 2), host_state.calls);
    try session.close();
}

test "interactive choice payload writes preserve vacant record siblings and snapshots" {
    var session: Interactive = undefined;
    try session.init(std.testing.allocator, &.{}, .{ .exhaustive_function_bodies = false }, .{});
    defer session.deinit();
    try session.submitDefinitions("Choice: Type = (..empty, ..some(.value: Int32))\nRecord := (.choice: Choice, .later: Int32)");
    try session.submitStatements("record :: Record\nrecord.choice = ..some(.value = 41)\nsaved ::= record.choice");
    try session.submitStatements("match record.choice { ..empty { abort } ..some $&payload { payload&.value = 42 } }");
    const revision = session.compiler.revision;
    try std.testing.expectError(error.Reported, session.submitInput("record.later"));
    try std.testing.expectEqual(revision, session.compiler.revision);
    try session.submitStatements("observed :: Int32 = 0\nmatch saved { ..empty { abort } ..some payload { observed = payload.value } }");
    try std.testing.expectEqual(@as(i128, 41), (try session.submitInput("observed")).?.value.runtime.integer);
    try session.submitStatements("record.later = 7\nmatch record.choice { ..empty { abort } ..some payload { observed = payload.value } }");
    try std.testing.expectEqual(@as(i128, 42), (try session.submitInput("observed")).?.value.runtime.integer);
    try session.submitStatements("record.choice = ..empty\nmatch record.choice { ..empty {} ..some payload { abort } }");
    try std.testing.expectEqual(@as(i128, 7), (try session.submitInput("record.later")).?.value.runtime.integer);
    try session.close();
}

test "interactive introspection retains compiler type constants without runtime storage" {
    var session: Interactive = undefined;
    try session.init(std.testing.allocator, &.{}, .{ .exhaustive_function_bodies = false }, .{});
    defer session.deinit();
    try session.submitStatements("a :: Int32 = 42");
    const result = session.submitInput("type_of(a)") catch |err| {
        try session.diagnostics.dump();
        return err;
    };
    const reflected = if (result.?.value == .type_) result.?.value.type_ else return error.MissingTypePresentation;
    try std.testing.expect(@import("../4_semantics/global/types.zig").isBuiltin(&session.compiler.semantic.relocation.graph, reflected, .Int32));
    try std.testing.expectEqual(@as(usize, 1), session.runtime.context.bindings.count());
    const size = (try session.submitInput("size_of(a)")).?;
    try std.testing.expectEqual(@as(i128, 4), size.value.runtime.integer);
    try std.testing.expectEqual(@as(i128, 4), (try session.submitInput("size_of(.type = _0)")).?.value.runtime.integer);
    try std.testing.expectEqual(@as(i128, 4), (try session.submitInput("alignment_of(_0)")).?.value.runtime.integer);
    const again = (try session.submitInput("_0")).?;
    try std.testing.expect(again.value == .type_);
    try session.reset();
    try session.close();
}

test "interactive exit cleans the live sibling of an incomplete choice payload" {
    const allocator = std.testing.allocator;
    var sources = submissions.Sources.init(allocator);
    defer sources.deinit();
    var diagnostics = diagnostics_mod.Diagnostics.init(&allocator, &.{});
    defer diagnostics.deinit();
    const loaded = try sources.loadModule(&diagnostics, "Deinit#(.T: Type): Contract = (.deinit: (.self: $&T) -> ())");
    var core = loaded.*;
    core.is_bundled_core = true;
    var session: Interactive = undefined;
    try session.initWithSources(allocator, diagnostics.source_files, &.{core}, .{ .exhaustive_function_bodies = false }, .{});
    defer session.deinit();
    try session.submitDefinitions("Resource := (.right: Bool)\nChoice: Type = (..pair(.left: Resource, .right: Resource), ..empty)\nimplement Deinit#(Resource) (.deinit = (.self: $&Resource) -> () {})\nimplement Deinit#(Choice) (.deinit = (.self: $&Choice) -> () { abort })");
    try session.submitStatements("choice :: Choice = ..pair(.left = (.right = false), .right = (.right = true))");
    try session.submitStatements("match choice { ..pair $&payload { deinit(.self = $&payload&.left) } ..empty {} }");
    const binding = session.compiler.semantic.resolvers.expressions.session_bindings.items[0];
    const frame = session.runtime.context.bindings.get(binding).?;
    const storage = &session.runtime.context.storage;
    const flags = storage.frames.items[@intFromEnum(frame)].cleanup_flags;
    const cleanup = storage.frames.items[@intFromEnum(frame)].cleanup;
    try std.testing.expect(!flags[cleanup[0].offset]);
    try std.testing.expect(flags[cleanup[0].offset + 1]);
    const payload = cleanup[0].layout.project(.{ .variant = 0 }).?;
    const first = payload.layout.project(.{ .field = 0 }).?;
    const second = payload.layout.project(.{ .field = 1 }).?;
    try std.testing.expect(!flags[cleanup[0].offset + payload.offset + first.offset]);
    try std.testing.expect(flags[cleanup[0].offset + payload.offset + second.offset]);
    // Close runs retained fallback rather than the aborting whole destructor.
    try session.close();
    try std.testing.expectEqual(.fresh, session.runtime.context.state);
}

test "interactive Init wrappers retain assumed capabilities from earlier commands" {
    const allocator = std.testing.allocator;
    var sources = submissions.Sources.init(allocator);
    defer sources.deinit();
    var diagnostics = diagnostics_mod.Diagnostics.init(&allocator, &.{});
    defer diagnostics.deinit();
    const loaded = try sources.loadModule(&diagnostics, "Init#(.T: Type, .Args: Type): Contract = (.Result: Type\n.init: (.args: Args) -> (.result: Result))");
    var core = loaded.*;
    core.is_bundled_core = true;
    var session: Interactive = undefined;
    try session.initWithSources(allocator, diagnostics.source_files, &.{core}, .{ .exhaustive_function_bodies = false }, .{});
    defer session.deinit();
    try session.submitDefinitions("Capability := (.value: Int32)\nBox := (.value: Int32)\nread_capability := (.permission: &Capability = reach permission) -> (.value: Int32) { value = permission&.value }\nimplement Init#(Box, ()) (.Result: Type = Box\n.init = (.args: ()) -> (.result: Result) { result = (.value = read_capability()) })");
    try session.submitStatements("token :: Capability = (.value = 42)\nassume permission ::= &token");
    try std.testing.expectEqual(@as(u64, 42), (try session.submitInput("Box().value")).?.value.runtime.integer);
    try std.testing.expectError(error.Reported, session.submitInput("missing_capability_command"));
    try std.testing.expectEqual(@as(u64, 42), (try session.submitInput("Box().value")).?.value.runtime.integer);
    try session.close();
}

test "interactive definitions preserve semantic identities without retaining executable graphs" {
    var session: Interactive = undefined;
    try session.init(std.testing.allocator, &.{}, .{ .exhaustive_function_bodies = false }, .{});
    defer session.deinit();
    try session.submitDefinitions("answer := () -> (.value: Int32) { value = 42 }");
    const shared_graph = &session.compiler.semantic.relocation.graph;
    try std.testing.expectEqual(@as(i128, 42), (try session.submitInput("answer()")).?.value.runtime.integer);
    try std.testing.expectEqual(@as(usize, 1), session.runtime.units.items.len);
    const executable = session.runtime.units.items[0];
    const answer = for (shared_graph.functions.items, 0..) |function, raw| {
        if (std.mem.eql(u8, shared_graph.text(shared_graph.declarationSourceName(function.declaration)), "answer"))
            break @as(@import("../4_semantics/global/graph.zig").GlobalFunctionId, @enumFromInt(raw));
    } else return error.MissingAnswer;
    const origin = session.runtime.bodies.entries.get(answer).?.origin;
    try std.testing.expect(shared_graph == &session.compiler.semantic.relocation.graph);
    try session.submitDefinitions("forward := () -> (.value: Int32) { value = answer() }");
    try std.testing.expectEqual(@as(usize, 1), session.runtime.units.items.len);
    try std.testing.expect(session.runtime.units.items[0] == executable);
    const revision = session.compiler.revision;
    try std.testing.expectError(error.DuplicateSessionDeclaration, session.submitDefinitions("answer := () -> (.value: Int32) { value = 7 }"));
    try std.testing.expectEqual(revision, session.compiler.revision);
    try std.testing.expect(session.runtime.bodies.entries.get(answer).?.origin == origin);
    try std.testing.expectEqual(@as(i128, 42), (try session.submitInput("forward()")).?.value.runtime.integer);
    try std.testing.expectEqual(@as(usize, 2), session.runtime.units.items.len);
    try std.testing.expect(session.runtime.bodies.entries.get(answer).?.origin == origin);
    try session.close();
}

test "interactive generic specializations retain completed evidence while new types see later implementations" {
    var session: Interactive = undefined;
    try session.init(std.testing.allocator, &.{}, .{ .exhaustive_function_bodies = false }, .{});
    defer session.deinit();
    try session.submitDefinitions("Identify#(.T: Type): Contract = (.identify: (.value: T) -> (.result: Int32))\n" ++
        "First := (.value: Int32)\nSecond := (.value: Int32)\n" ++
        "dispatch := #(.T: Type) (.value: T) -> (.result: Int32) { result = Identify#(T).identify(.value = value) }");
    // Definition lookup is already fixed, but concrete conformance selection
    // must remain possible after a later implementation becomes available.
    try session.submitDefinitions("implement#(.T: Type) Identify#(T) (.identify = (.value: T) -> (.result: Int32) { result = 7 })");
    try std.testing.expectEqual(@as(u64, 7), (try session.submitInput("dispatch#(First)(.value = First(.value = 0))")).?.value.runtime.integer);
    const graph = &session.compiler.semantic.relocation.graph;
    const first = for (graph.generic_function_instances.items) |instance| {
        if (std.mem.eql(u8, graph.text(graph.declarationSourceName(graph.familyDeclaration(instance.parameterized_definition))), "dispatch")) break instance.function;
    } else return error.MissingDispatchSpecialization;
    const body = graph.function(first).body;
    const proof = session.compiler.body_cache.entries.get(first);
    try session.submitDefinitions("implement Identify#(Second) (.identify = (.value: Second) -> (.result: Int32) { result = 42 })");
    try std.testing.expectEqual(@as(u64, 42), (try session.submitInput("dispatch#(Second)(.value = Second(.value = 0))")).?.value.runtime.integer);
    try std.testing.expectEqual(@as(u64, 7), (try session.submitInput("dispatch#(First)(.value = First(.value = 0))")).?.value.runtime.integer);
    try std.testing.expectEqual(body, graph.function(first).body);
    try std.testing.expect(proof == session.compiler.body_cache.entries.get(first));
    try session.close();
}

test "interactive dormant operation signatures complete at first selected use without freezing definition evidence" {
    var session: Interactive = undefined;
    try session.init(std.testing.allocator, &.{}, .{ .exhaustive_function_bodies = false }, .{});
    defer session.deinit();
    try session.submitDefinitions("Identify#(.T: Type): Contract = (.identify: (.value: T) -> (.result: Int32))\nEcho#(.T: Type): Contract = (.echo: (.value: T) -> (.result: Int32))\nBox := (.value: Int32)\nforward := #(.T: Type) (.value: T) -> (.result: Int32) { result = Identify#(T).identify(.value = value) }");
    try session.submitDefinitions("implement Echo#(Box) (.echo = forward)");
    const graph = &session.compiler.semantic.relocation.graph;
    const method = for (graph.generic_function_instances.items) |instance| {
        if (std.mem.eql(u8, graph.text(graph.declarationSourceName(graph.familyDeclaration(instance.parameterized_definition))), "forward")) break instance.function;
    } else return error.MissingForwardSignature;
    try std.testing.expect(graph.function(method).body == null);
    try std.testing.expect(!session.compiler.body_cache.entries.contains(method));
    const saved = graph.checkpoint();
    const revision = session.compiler.revision;
    try std.testing.expectError(error.Reported, session.submitInput("Echo#(Box).echo(.value = Box(.value = 0))"));
    try std.testing.expectEqual(revision, session.compiler.revision);
    try std.testing.expectEqualDeep(saved, graph.checkpoint());
    try std.testing.expect(graph.function(method).body == null);
    try std.testing.expect(!session.compiler.body_cache.entries.contains(method));
    // Merely registering a signature has not resolved its body. The selected
    // use can rely on evidence introduced after the generic definition.
    try session.submitDefinitions("implement Identify#(Box) (.identify = (.value: Box) -> (.result: Int32) { result = 42 })");
    try std.testing.expect(graph.function(method).body == null);
    try std.testing.expectEqual(@as(u64, 42), (try session.submitInput("Echo#(Box).echo(.value = Box(.value = 0))")).?.value.runtime.integer);
    const body = graph.function(method).body;
    try std.testing.expect(body != null);
    try session.submitDefinitions("Unrelated := (.flag: Bool)");
    try std.testing.expectEqual(@as(u64, 42), (try session.submitInput("Echo#(Box).echo(.value = Box(.value = 0))")).?.value.runtime.integer);
    try std.testing.expectEqual(body, graph.function(method).body);
    try session.close();
}

fn rejectedSourceLifetimeFailures(allocator: std.mem.Allocator) !void {
    var session: Interactive = undefined;
    try session.init(allocator, &.{}, .{ .exhaustive_function_bodies = false }, .{});
    defer session.deinit();
    try session.submitStatements("value :: Int32 = 42");
    const accepted_modules = session.sources.modules.items.len;
    const accepted_files = session.diagnostics.source_files.len;
    const original = session.diagnostics.source_db.files[0].source;
    const revision = session.compiler.revision;
    const saved = session.compiler.semantic.relocation.graph.checkpoint();
    for (0..2) |_| {
        session.submitStatements("temporary :: Int32 = 7\nmissing_function()") catch |err| {
            if (err != error.Reported) return err;
            try std.testing.expectEqual(revision, session.compiler.revision);
            try std.testing.expectEqualDeep(saved, session.compiler.semantic.relocation.graph.checkpoint());
            try std.testing.expect(session.rejected_sources != null);
            try std.testing.expect(session.diagnostics.list.items.len != 0);
            const diagnostic = session.diagnostics.list.items[0];
            const source = session.diagnostics.source_db.get(diagnostic.loc.file).source;
            try std.testing.expect(std.mem.indexOf(u8, source, "missing_function()") != null);
            try std.testing.expect(session.sources.modules.items.len <= accepted_modules + 1);
            try std.testing.expect(session.diagnostics.source_files.len <= accepted_files + 2);
            continue;
        };
        return error.RejectedSubmissionAccepted;
    }
    try session.submitStatements("value = 42");
    try std.testing.expect(session.rejected_sources == null);
    try std.testing.expectEqual(@as(usize, accepted_modules + 1), session.sources.modules.items.len);
    try std.testing.expectEqual(@as(usize, accepted_files + 2), session.diagnostics.source_files.len);
    try std.testing.expectEqualStrings(original, session.diagnostics.source_db.files[0].source);
    try session.close();
}

test "interactive rejected source batches retain only the latest diagnostic and release allocation failures" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, rejectedSourceLifetimeFailures, .{});
}

test "interactive generic contract operations retain instances across rejected submissions" {
    var session: Interactive = undefined;
    try session.init(std.testing.allocator, &.{}, .{ .exhaustive_function_bodies = false }, .{});
    defer session.deinit();
    try session.submitDefinitions(
        \\Identity#(.Owner: Type): Contract = (
        \\    .apply: #(.Value: Type) (.owner: &Owner, .value: Value) -> (.result: Value) where { depends_on(result, value) }
        \\)
        \\Owner := (.flag: Bool)
        \\implement Identity#(Owner) (
        \\    .apply = #(.Item: Type) (.owner: &Owner, .value: Item) -> (.result: Item) { result = value }
        \\)
    );
    try session.submitStatements("owner: Owner = (.flag = true)");
    try std.testing.expect((try session.submitInput("apply#(Bool)(.owner = &owner, .value = true).result")).?.value.runtime.boolean);
    const instances = session.compiler.semantic.resolvers.core.graph.generic_function_instances.items.len;
    const revision = session.compiler.revision;
    try std.testing.expectError(error.Reported, session.submitStatements("rejected ::= apply#(Int32)(.owner = &owner, .value = 42).result\nmissing()"));
    try std.testing.expectEqual(revision, session.compiler.revision);
    try std.testing.expectEqual(instances, session.compiler.semantic.resolvers.core.graph.generic_function_instances.items.len);
    try std.testing.expectEqual(@as(i128, 42), (try session.submitInput("apply#(Int32)(.owner = &owner, .value = 42).result")).?.value.runtime.integer);
    try std.testing.expect((try session.submitInput("apply#(Bool)(.owner = &owner, .value = true).result")).?.value.runtime.boolean);
    try session.close();
}

test "interactive specialized definition values preserve captures across rejection" {
    var session: Interactive = undefined;
    try session.init(std.testing.allocator, &.{}, .{ .exhaustive_function_bodies = false }, .{});
    defer session.deinit();
    try session.submitDefinitions("identity := #(.T: Type) (.value: T) -> (.result: T) { result = value }");
    try session.submitStatements("selected := identity#(Int32)");
    try std.testing.expectEqual(@as(i128, 42), (try session.submitInput("selected(.value = 42)")).?.value.runtime.integer);
    const revision = session.compiler.revision;
    const arguments = session.compiler.semantic.resolvers.core.graph.generic_arguments.items.len;
    try std.testing.expectError(error.Reported, session.submitInput("selected#(Bool)(.value = true)"));
    try std.testing.expectEqual(revision, session.compiler.revision);
    try std.testing.expectEqual(arguments, session.compiler.semantic.resolvers.core.graph.generic_arguments.items.len);
    try std.testing.expectEqual(@as(i128, 7), (try session.submitInput("selected(.value = 7)")).?.value.runtime.integer);
    try session.submitDefinitions("Record := (.value: Int32)");
    try session.submitStatements("record_identity := identity#(Record)");
    try session.submitStatements("record ::= record_identity(.value = (.value = 42))");
    try std.testing.expectEqual(@as(i128, 42), (try session.submitInput("record.value")).?.value.runtime.integer);
    try session.close();
}

test "interactive associated family arguments survive rejected selections" {
    var session: Interactive = undefined;
    try session.init(std.testing.allocator, &.{}, .{ .exhaustive_function_bodies = false }, .{});
    defer session.deinit();
    try session.submitDefinitions("Owner := (.flag: Bool)");
    try session.submitDefinitions("Arguments := #(.Item: Type) (.value: Item)");
    try session.submitDefinitions("Factory#(.Participant: Type): Contract = (.Args: #(.Item: Type) Type, .Element: Type)");
    try session.submitDefinitions("implement Factory#(Owner) (.Args: #(.Item: Type) Type = Arguments, .Element: Type = Int32)");
    try session.submitDefinitions("make := #(.Family: #(.Item: Type) Type) (.value: Int32) -> (.result: Family#(Int32)) { result = (.value = value) }");
    try session.submitStatements("first ::= make#(.Family = Factory#(Owner).Args)(.value = 42)");
    try std.testing.expectEqual(@as(i128, 42), (try session.submitInput("first.value")).?.value.runtime.integer);
    const revision = session.compiler.revision;
    const arguments = session.compiler.semantic.resolvers.core.graph.generic_arguments.items.len;
    try std.testing.expectError(error.Reported, session.submitInput("make#(.Family = Factory#(Owner).Element)(.value = 7)"));
    try std.testing.expectEqual(revision, session.compiler.revision);
    try std.testing.expectEqual(arguments, session.compiler.semantic.resolvers.core.graph.generic_arguments.items.len);
    try session.submitStatements("second ::= make#(.Family = Factory#(Owner).Args)(.value = 7)");
    try std.testing.expectEqual(@as(i128, 7), (try session.submitInput("second.value")).?.value.runtime.integer);
    try std.testing.expectEqual(@as(i128, 42), (try session.submitInput("first.value")).?.value.runtime.integer);
    try session.close();
}

test "interactive implementation-defined operations retain selected signatures across rejection" {
    var session: Interactive = undefined;
    try session.init(std.testing.allocator, &.{}, .{ .exhaustive_function_bodies = false }, .{});
    defer session.deinit();
    try session.submitDefinitions("Factory#(.T: Type): Contract = (.make: _)");
    try session.submitDefinitions("Record := (.value: Int32)");
    try session.submitDefinitions("implement Factory#(Record) (.make = #(.Provider: Type) (.value: Int32, .provider: &Provider) -> (.result: Record) { result = (.value = value) })");
    try session.submitStatements("provider := true");
    try session.submitStatements("first ::= Factory#(Record).make(.value = 42, .provider = &provider)");
    try std.testing.expectEqual(@as(i128, 42), (try session.submitInput("first.value")).?.value.runtime.integer);
    const revision = session.compiler.revision;
    const arguments = session.compiler.semantic.resolvers.core.graph.generic_arguments.items.len;
    try std.testing.expectError(error.Reported, session.submitInput("Factory#(Record).make(.unknown = 7, .provider = &provider)"));
    try std.testing.expectEqual(revision, session.compiler.revision);
    try std.testing.expectEqual(arguments, session.compiler.semantic.resolvers.core.graph.generic_arguments.items.len);
    try session.submitStatements("second ::= Factory#(Record).make(.value = 7, .provider = &provider)");
    try std.testing.expectEqual(@as(i128, 7), (try session.submitInput("second.value")).?.value.runtime.integer);
    try std.testing.expectEqual(@as(i128, 42), (try session.submitInput("first.value")).?.value.runtime.integer);
    try session.close();
}

test "interactive Init selects target before inferring implementation parameters" {
    const allocator = std.testing.allocator;
    var sources = submissions.Sources.init(allocator);
    defer sources.deinit();
    var diagnostics = diagnostics_mod.Diagnostics.init(&allocator, &.{});
    defer diagnostics.deinit();
    const loaded = try sources.loadModule(&diagnostics, "Init#(.T: Type): Contract = (.init: _)");
    var core = loaded.*;
    core.is_bundled_core = true;
    var session: Interactive = undefined;
    try session.initWithSources(allocator, diagnostics.source_files, &.{core}, .{ .exhaustive_function_bodies = false }, .{});
    defer session.deinit();
    try session.submitDefinitions(
        \\Point := (.value: Int32)
        \\Other := (.value: Int32)
        \\Provider := (.flag: Bool)
        \\Container := #(.T: Type) (.value: T)
        \\implement#(.T: Type) Init#(Container#(T)) (
        \\    .init = #(.P: Type) (.provider: &P, .value: T) -> (.result: Container#(T)) {
        \\        result = (.value = ~value)
        \\    }
        \\)
        \\implement Init#(Point) (
        \\    .init = #(.P: Type) (.provider: &P, .value: Int32 = 42) -> (.result: Point) {
        \\        result = (.value = value)
        \\    }
        \\)
        \\implement Init#(Other) (
        \\    .init = (.value: Int32 = 7) -> (.result: Other) { result = (.value = value) }
        \\)
    );
    try session.submitStatements("provider: Provider = (.flag = true)\nfirst ::= Point(.provider = &provider)");
    try std.testing.expectEqual(@as(u64, 42), (try session.submitInput("first.value")).?.value.runtime.integer);
    try std.testing.expectEqual(@as(u64, 7), (try session.submitInput("Other().value")).?.value.runtime.integer);
    try session.submitStatements("container ::= Container#(Int32)(.provider = &provider, .value = 19)");
    try std.testing.expectEqual(@as(u64, 19), (try session.submitInput("container.value")).?.value.runtime.integer);
    try session.submitStatements("known ::= #run () -> (.result: Int32) { result = Other().value }");
    try std.testing.expectEqual(@as(u64, 7), (try session.submitInput("known")).?.value.runtime.integer);
    const revision = session.compiler.revision;
    try std.testing.expectError(error.Reported, session.submitInput("Point(.unknown = 1)"));
    try std.testing.expectEqual(revision, session.compiler.revision);
    try std.testing.expectEqual(@as(u64, 9), (try session.submitInput("Point(.provider = &provider, .value = 9).value")).?.value.runtime.integer);
    try session.close();
}
