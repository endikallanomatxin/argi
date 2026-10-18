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
    options: sema.Options,
    limits: vm.Limits,
    closed: bool = false,
    result_sequence: u64 = 0,

    pub fn init(self: *Interactive, allocator: std.mem.Allocator, modules: []const module_sg.ModuleSemanticGraph, options: sema.Options, limits: vm.Limits) !void {
        return self.initWithSources(allocator, &.{}, modules, options, limits);
    }

    /// Initial files and module graphs are borrowed together. Submitted sources
    /// extend this diagnostic index without changing initial file identities.
    pub fn initWithSources(self: *Interactive, allocator: std.mem.Allocator, files: []const @import("../1_base/source_files.zig").SourceFile, modules: []const module_sg.ModuleSemanticGraph, options: sema.Options, limits: vm.Limits) !void {
        self.allocator = allocator;
        self.initial_files = files;
        self.initial_modules = modules;
        self.options = options;
        self.limits = limits;
        self.closed = false;
        self.result_sequence = 0;
        self.diagnostic_arena = .init(allocator);
        errdefer self.diagnostic_arena.deinit();
        self.diagnostic_allocator = self.diagnostic_arena.allocator();
        self.diagnostics = .init(&self.diagnostic_allocator, files);
        errdefer self.diagnostics.deinit();
        self.sources = .init(allocator);
        errdefer self.sources.deinit();
        var selected = options;
        selected.diagnostics = &self.diagnostics;
        self.compiler = try compilation.CompilationSession.init(allocator, modules, selected);
        self.runtime = .init(allocator, &self.compiler, limits);
    }
    pub fn deinit(self: *Interactive) void {
        self.runtime.deinit();
        self.compiler.deinit();
        self.diagnostics.deinit();
        self.sources.deinit();
        self.diagnostic_arena.deinit();
        self.* = undefined;
    }

    pub fn submitStatements(self: *Interactive, statements: []const u8) !void {
        try self.beginSubmission();
        var command = try self.sources.prepareCommand(&self.compiler, &self.diagnostics, statements);
        defer command.deinit();
        try self.runtime.executeCommand(&command.candidate);
    }

    pub const PresentedValue = struct {
        name: []const u8,
        value: @import("../5_codegen/bytecode/value.zig").Value,
    };

    pub fn submit(self: *Interactive, source: []const u8) !void {
        _ = try self.submitInput(source);
    }

    /// Expressions become ordinary numbered session bindings. Their owners and
    /// loans survive presentation and receive normal checked reset/exit cleanup.
    /// Returned presentation views are borrowed until the next session mutation.
    pub fn submitInput(self: *Interactive, source: []const u8) !?PresentedValue {
        try self.beginSubmission();
        switch (try self.sources.classify(&self.diagnostics, source)) {
            .empty => {},
            .definitions => try self.submitDefinitions(source),
            .statements => try self.submitStatements(source),
            .expression => {
                const name = try self.nextResultName();
                const statement = try std.fmt.allocPrint(self.allocator, "{s} ::= {s}\n", .{ name, source });
                defer self.allocator.free(statement);
                var command = try self.sources.prepareCommandOrigin(&self.compiler, &self.diagnostics, statement, .{
                    .text = source,
                    .offset = name.len + " ::= ".len,
                });
                defer command.deinit();
                try self.runtime.executeCommand(&command.candidate);
                const bindings = self.compiler.semantic.resolvers.expressions.session_bindings.items;
                const binding = bindings[bindings.len - 1];
                const frame = self.runtime.context.bindings.get(binding) orelse return error.UninitializedBinding;
                const slots = try self.runtime.context.storage.slots(frame);
                return .{ .name = name, .value = try slots.get(0) };
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
        const module = try self.sources.loadModule(&self.diagnostics, source);
        const prefix = try self.sources.appendSnapshot(self.compiler.semantic.modules, module);
        var candidate = try self.compiler.prepareDefinitions(prefix, &self.diagnostics);
        defer candidate.deinit();
        try self.compiler.accept(&candidate);
    }

    fn beginSubmission(self: *Interactive) !void {
        if (self.closed) return error.InteractiveSessionClosed;
        if (self.runtime.context.state == .poisoned) return error.ExecutionContextPoisoned;
        self.diagnostics.list.clearRetainingCapacity();
    }

    pub fn close(self: *Interactive) !void {
        try self.beginSubmission();
        try self.cleanup();
        self.closed = true;
    }
    fn cleanup(self: *Interactive) !void {
        const command = try self.sources.loadCommand(&self.diagnostics, "");
        const prefix = try self.sources.appendSnapshot(self.compiler.semantic.modules, command.module);
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
        var replacement = try compilation.CompilationSession.init(self.allocator, self.initial_modules, options);
        errdefer replacement.deinit();
        if (self.runtime.context.state != .poisoned) {
            self.diagnostics.list.clearRetainingCapacity();
            try self.cleanup();
        }
        // A trapped context has no safe user-code unwind. Its explicit reset
        // discards the poisoned execution and proof state together.
        self.runtime.deinit();
        self.compiler.deinit();
        // No accepted graph or execution unit can refer to submitted source
        // now. Reset releases that history rather than retaining it until quit.
        self.diagnostics.deinit();
        self.sources.deinit();
        _ = self.diagnostic_arena.reset(.free_all);
        self.diagnostics = .init(&self.diagnostic_allocator, self.initial_files);
        self.sources = .init(self.allocator);
        self.compiler = replacement;
        self.runtime = .init(self.allocator, &self.compiler, self.limits);
        self.result_sequence = 0;
        self.diagnostics.list.clearRetainingCapacity();
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
    try session.submitDefinitions("identity#(.T: Type) := (.value: T) -> (.result: T) { result = value }\n");
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
    // Loading an ordinary module must not grant the interactive namespace.
    const isolated = try session.sources.loadModule(&session.diagnostics, "outside := () -> (.result: Int32) { result = answer() }\n");
    const prefix = try session.sources.appendSnapshot(session.compiler.semantic.modules, isolated);
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
    try std.testing.expectEqual(@as(i128, 42), first.value.integer);
    const second = (try session.submitInput("_1")).?;
    try std.testing.expectEqualStrings("_2", second.name);
    try std.testing.expectEqual(@as(i128, 42), second.value.integer);
    try session.submit("answer := () -> (.result: Int32) { result = 12 }");
    const call = (try session.submitInput("answer()")).?;
    try std.testing.expectEqual(@as(i128, 12), call.value.integer);
    try session.submit("called :: Bool = false");
    try session.submit("nothing := (.called: $&Bool) -> () { if called& { abort } called& = true }");
    const unit = (try session.submitInput("nothing(.called = $&called)")).?;
    try std.testing.expect(unit.value == .unit or (unit.value == .record and unit.value.record.len == 0));
    try std.testing.expect((try session.submitInput("called")).?.value.boolean);
    try session.reset();
    const reset = (try session.submitInput("true")).?;
    try std.testing.expectEqualStrings("_0", reset.name);
    try std.testing.expect(reset.value.boolean);
    try session.close();
}

test "interactive presented references retain checked session storage" {
    var session: Interactive = undefined;
    try session.init(std.testing.allocator, &.{}, .{ .exhaustive_function_bodies = false }, .{});
    defer session.deinit();
    try session.submit("source :: Int32 = 42");
    const borrowed = (try session.submitInput("&source")).?;
    try std.testing.expect(borrowed.value == .reference);
    const target = borrowed.value.reference;
    try std.testing.expectEqual(.session, session.runtime.context.storage.frames.items[@intFromEnum(target.frame)].duration);
    const read = (try session.submitInput("_0&")).?;
    try std.testing.expectEqual(@as(i128, 42), read.value.integer);
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
    const slots = try session.runtime.context.storage.slots(frame);
    const cleanup = session.runtime.context.storage.frames.items[@intFromEnum(frame)].cleanup;
    try std.testing.expect(cleanup.len != 0);
    try std.testing.expect((try slots.get(cleanup[0].flag)).boolean);
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
    try std.testing.expectEqual(@as(i128, 42), runtime.value.integer);
    const comptime_value = (try session.submitInput("#run choose()")).?;
    try std.testing.expectEqual(@as(i128, 42), comptime_value.value.integer);
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
    try std.testing.expect(std.mem.indexOf(u8, session.diagnostics.list.items[0].msg, "imports in interactive submissions") != null);
    const result = (try session.submitInput("42")).?;
    try std.testing.expectEqual(@as(i128, 42), result.value.integer);
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

test "interactive execution diagnostics map expression and statement source" {
    var session: Interactive = undefined;
    try session.init(std.testing.allocator, &.{}, .{ .exhaustive_function_bodies = false }, .{});
    defer session.deinit();
    try session.submit("fraction := () -> (.result: Float32) { result = 1.5 }");
    const revision = session.compiler.revision;
    try std.testing.expectError(error.Reported, session.submitInput("fraction()"));
    try std.testing.expectEqual(revision, session.compiler.revision);
    try std.testing.expect(session.diagnostics.hasErrors());
    const unsupported = session.diagnostics.list.items[0];
    try std.testing.expect(std.mem.indexOf(u8, unsupported.msg, "bytecode execution does not support") != null);
    try std.testing.expect(std.mem.endsWith(u8, session.diagnostics.path(unsupported.loc), "/input.rg"));
    try std.testing.expectEqualStrings("fraction()", session.diagnostics.source_db.get(unsupported.loc.file).source);
    try std.testing.expectEqual(@as(u32, 1), session.diagnostics.lineColumn(unsupported.loc).column);
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
    try std.testing.expectError(error.Reported, session.submitInput("#run fail()"));
    try std.testing.expectEqual(revision, session.compiler.revision);
    try std.testing.expect(session.diagnostics.hasErrors());
    const diagnostic = session.diagnostics.list.items[0];
    const text = session.diagnostics.source_db.get(diagnostic.loc.file).source;
    try std.testing.expect(std.mem.indexOf(u8, text, "_session_command_") == null);
    try std.testing.expect(std.mem.indexOf(u8, diagnostic.msg, "aborted") != null);
    try session.submitStatements("value ::= 42");
    try session.close();
}
