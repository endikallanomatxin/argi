//! Real-core source tests. Each check owns a compilation region, like the CLI;
//! sources and immutable module snapshots have separate, explicitly checked owners.
const std = @import("std");
const sf = @import("../1_base/source_files.zig");
const diag = @import("../1_base/diagnostic.zig");
const frontend = @import("../0_commands/frontend_pipeline.zig");
const vm = @import("../execution/vm.zig");
const lower = @import("../5_codegen/bytecode/lower.zig");
const bytecode = @import("../5_codegen/bytecode/bytecode.zig");

pub const ExpectedDiagnostic = struct {
    message: []const u8,
    kind: diag.Kind = .semantic,
    origin: sf.SourceFile.Origin = .user,
    file: ?[]const u8 = null,
    marker: ?[]const u8 = null,
    exact: bool = false,
    forbidden: []const []const u8 = &.{},
    no_syntax_noise: bool = true,
};

pub const Case = struct {
    name: []const u8,
    /// Paths are relative to this case's module root. Every supplied source is user code.
    files: []const sf.SourceFile,
    diagnostic: ?ExpectedDiagnostic = null,
};

pub const Stats = struct { cache_hits: usize, cache_misses: usize };

/// One explicit test-group lifetime; no process-global cache or semantic state.
/// The cache owns canonical module snapshots only, never a previous GlobalSG.
pub const Environment = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    core: std.array_list.Managed(sf.SourceFile),
    cache: frontend.cache.ModuleCache,

    pub fn init(allocator: std.mem.Allocator, io: std.Io) !Environment {
        // Internal tests must use the checkout being tested, not a stale installed core.
        const checkout = try std.fs.path.resolve(allocator, &.{"core"});
        defer allocator.free(checkout);
        const selected = try sf.resolveToolCoreDir(&allocator, io, .{});
        defer allocator.free(selected);
        if (!std.mem.eql(u8, checkout, selected)) return error.UnexpectedTestCore;
        return .{
            .allocator = allocator,
            .io = io,
            .core = try sf.collectCoreWithOptions(&allocator, io, .{}),
            .cache = frontend.cache.ModuleCache.init(allocator, .{}),
        };
    }

    pub fn deinit(self: *Environment) void {
        self.cache.deinit();
        sf.freeList(&self.allocator, &self.core);
        self.* = undefined;
    }

    pub fn check(self: *Environment, case: Case) !Stats {
        return self.checkWithExecution(case, null);
    }

    /// Execute a checked source case against real core without emitting or linking native code.
    pub fn execute(self: *Environment, case: Case, limits: vm.Limits) !i128 {
        if (case.diagnostic != null) return error.InvalidExecutionCase;
        var result: i128 = undefined;
        _ = try self.checkWithExecution(case, .{ .limits = limits, .result = &result });
        return result;
    }

    const Execution = struct { limits: vm.Limits, result: *i128 };

    fn checkWithExecution(self: *Environment, case: Case, execution: ?Execution) !Stats {
        errdefer std.debug.print("real-core source case: {s}\n", .{case.name});
        const a = self.allocator;
        const root = try std.fs.path.resolve(a, &.{ "frontend_test_cases", case.name });
        defer a.free(root);
        var files: std.ArrayList(sf.SourceFile) = .empty;
        defer files.deinit(a);
        try files.appendSlice(a, self.core.items);
        const user_start = files.items.len;
        defer for (files.items[user_start..]) |file| a.free(file.path);
        for (case.files) |file| {
            if (file.origin != .user) return error.InvalidTestSourceOrigin;
            const path = try std.fs.path.resolve(a, &.{ root, file.path });
            errdefer a.free(path);
            try files.append(a, .{ .path = path, .code = file.code });
        }
        return self.run(a, files.items, root, case.diagnostic, execution);
    }

    /// Use the ordinary source collector, including import discovery and core origins.
    /// Case buffers and compilation work belong to the caller; cached modules belong to self.
    pub fn checkModule(self: *Environment, allocator: std.mem.Allocator, directory: []const u8, expected: ?ExpectedDiagnostic) !Stats {
        errdefer std.debug.print("real-core module case: {s}\n", .{directory});
        const root = try std.fs.path.resolve(allocator, &.{directory});
        defer allocator.free(root);
        var files = try sf.collectModuleWithOptions(&allocator, self.io, .{ .source_overrides = self.core.items }, root);
        defer sf.freeList(&allocator, &files);
        return self.run(allocator, files.items, root, expected, null);
    }

    fn run(self: *Environment, a: std.mem.Allocator, files: []const sf.SourceFile, root: []const u8, expected_diagnostic: ?ExpectedDiagnostic, execution: ?Execution) !Stats {
        // Shared immutable facts intentionally borrow the compilation lifetime.
        // This is not an assertion that all inference scratch is freed individually.
        var invocation = std.heap.ArenaAllocator.init(a);
        defer invocation.deinit();
        const work = invocation.allocator();
        var diagnostics = try diag.Diagnostics.init(&work, files);
        defer diagnostics.deinit();
        var pipeline = frontend.FrontendPipeline.init(work, self.io, &diagnostics, .{
            .entry_module_dir = root,
            .module_cache = &self.cache,
        });
        defer pipeline.deinit();
        var failure: ?anyerror = null;
        const graph = pipeline.semantizeGlobalFiles(files) catch |err| blk: {
            if (err == error.OutOfMemory) return err;
            failure = err;
            break :blk null;
        };
        if (expected_diagnostic) |expected| {
            try std.testing.expect(failure != null);
            for (diagnostics.list.items) |item| {
                if (expected.no_syntax_noise and expected.kind != .syntax) try std.testing.expect(item.kind != .syntax);
                for (expected.forbidden) |noise| try std.testing.expect(std.mem.indexOf(u8, item.msg, noise) == null);
            }
            const found = try matchesDiagnostic(a, &diagnostics, root, expected);
            if (!found) {
                for (diagnostics.list.items) |item| std.debug.print("{s}: {s}\n", .{ diagnostics.path(item.loc), item.msg });
                std.debug.print("frontend result: {?s}; expected diagnostic: {s}\n", .{ if (failure) |err| @errorName(err) else null, expected.message });
                return error.MissingExpectedDiagnostic;
            }
        } else {
            if (failure) |err| {
                for (diagnostics.list.items) |item| std.debug.print("{s}: {s}\n", .{ diagnostics.path(item.loc), item.msg });
                return err;
            }
            try std.testing.expectEqual(@as(usize, 0), diagnostics.list.items.len);
            try std.testing.expect(pipeline.safety_ctx != null);
        }
        if (execution) |request| {
            const checked = graph orelse return error.MissingExecutionGraph;
            const entry = for (checked.functions.items, 0..) |function, index| {
                const declaration = checked.declarations.items[@intFromEnum(function.declaration)];
                if (std.mem.eql(u8, checked.text(checked.declarationSourceName(function.declaration)), "main") and
                    std.mem.eql(u8, std.fs.path.dirname(diagnostics.source_db.path(@enumFromInt(declaration.source.file_index))) orelse "", root)) break index;
            } else return error.MissingEntry;
            var compiler = try lower.Lower.init(work, checked, .{});
            compiler.annotations = &pipeline.safety_ctx.?.annotations;
            compiler.mode = .runtime;
            const program = try compiler.compile(@enumFromInt(entry));
            var executor = try vm.Vm.init(work, program, request.limits);
            defer executor.deinit();
            const result = try executor.run(@enumFromInt(entry), &.{});
            const function = checked.functions.items[entry];
            request.result.* = @import("../5_codegen/integer_arithmetic.zig").decode(result[0].integer, bytecode.integerBounds(checked, checked.fields.items[function.output.start].ty).?);
        }
        return .{ .cache_hits = pipeline.module_cache_hits, .cache_misses = pipeline.module_cache_misses };
    }
};

fn matchesDiagnostic(a: std.mem.Allocator, diagnostics: *const diag.Diagnostics, root: []const u8, expected: ExpectedDiagnostic) !bool {
    return for (diagnostics.list.items) |item| {
        const matches = if (expected.exact) std.mem.eql(u8, item.msg, expected.message) else std.mem.indexOf(u8, item.msg, expected.message) != null;
        if (!matches or item.kind != expected.kind) continue;
        const location = diagnostics.presentedLocation(item.loc);
        if (@intFromEnum(location.file) >= diagnostics.source_db.files.len) continue;
        const source = diagnostics.source_db.get(location.file);
        if (source.origin != expected.origin) continue;
        const path = source.path;
        if (expected.file) |relative| {
            const wanted = try std.fs.path.resolve(a, &.{ root, relative });
            defer a.free(wanted);
            const actual = try std.fs.path.resolve(a, &.{path});
            defer a.free(actual);
            if (!std.mem.eql(u8, wanted, actual)) continue;
        }
        if (expected.marker) |marker| {
            const offset = std.mem.indexOf(u8, source.source, marker) orelse return error.InvalidTestMarker;
            if (offset != location.offset) continue;
        }
        break true;
    } else false;
}

test "frontend diagnostic matching checks all candidate locations and source origins" {
    var messages = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer messages.deinit();
    const a = messages.allocator();
    const files = [_]sf.SourceFile{.{ .path = "case/main.rg", .code = "first second" }};
    var diagnostics = try diag.Diagnostics.init(&a, &files);
    defer diagnostics.deinit();
    const file = diagnostics.source_db.fileId(0);
    try diagnostics.add(.{ .file = file, .offset = 0 }, .semantic, "same diagnostic", .{});
    try diagnostics.add(.{ .file = file, .offset = 6 }, .semantic, "same diagnostic", .{});
    try std.testing.expect(try matchesDiagnostic(std.testing.allocator, &diagnostics, "case", .{
        .message = "same diagnostic",
        .file = "main.rg",
        .marker = "second",
    }));
    try std.testing.expect(!try matchesDiagnostic(std.testing.allocator, &diagnostics, "case", .{
        .message = "same diagnostic",
        .origin = .bundled_core,
    }));
}
