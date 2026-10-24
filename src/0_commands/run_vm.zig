const std = @import("std");
const sf = @import("../1_base/source_files.zig");
const diag = @import("../1_base/diagnostic.zig");
const frontend = @import("frontend_pipeline.zig");
const lower = @import("../5_codegen/bytecode/lower.zig");
const vm = @import("../execution/vm.zig");
const g = @import("../4_semantics/global/graph.zig");
const p = @import("../4_semantics/primitives/schema.zig");

// Deliberately no runtime capabilities, native calls, or host I/O are exposed to
// interpreted code. Source collection still uses the normal checked frontend.
pub fn run(io: std.Io, environ: ?*const std.process.Environ.Map, args: []const []const u8) !u8 {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var path: ?[]const u8 = null;
    var jobs: usize = 1;
    var limits: vm.Limits = .{};
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
        if (std.mem.eql(u8, arg, "--vm")) continue;
        if (std.mem.eql(u8, arg, "--help")) {
            std.debug.print("Usage: argi run --vm <directory> [--frontend-jobs N] [execution limits]\nLimits: {s}\nCtrl+C requests cooperative cancellation (exit status 130).\n", .{@import("execution_options.zig").help});
            return 0;
        }
        if (try @import("execution_options.zig").consume(&limits, args, &index)) continue;
        if (std.mem.eql(u8, arg, "--frontend-jobs")) {
            index += 1;
            if (index >= args.len) return error.InvalidVmArguments;
            jobs = std.fmt.parseInt(usize, args[index], 10) catch return error.InvalidVmArguments;
            if (jobs == 0 or jobs > 64) return error.InvalidVmArguments;
            continue;
        }
        if (path != null or std.mem.startsWith(u8, arg, "--")) return error.InvalidVmArguments;
        path = arg;
    }
    const directory = path orelse return error.InvalidVmArguments;
    const files = try sf.collectModuleWithOptions(&allocator, io, .{ .environ_map = environ }, directory);
    var diagnostics = diag.Diagnostics.init(&allocator, files.items);
    defer diagnostics.deinit();
    var pipeline = frontend.FrontendPipeline.init(allocator, io, &diagnostics, .{ .entry_module_dir = directory, .module_jobs = jobs });
    defer pipeline.deinit();
    const graph = pipeline.semantizeGlobalFiles(files.items) catch {
        try diagnostics.dump();
        return error.CompilationFailed;
    };
    var entry: ?g.GlobalFunctionId = null;
    const module_path = try std.fs.path.resolve(allocator, &.{directory});
    // The normal host wrapper stays checked, but it constructs runtime tracing
    // capabilities. Execute the user entry directly in this pure subset.
    for (graph.functions.items, 0..) |f, i| {
        if (!std.mem.eql(u8, graph.text(graph.declarationSourceName(f.declaration)), "main")) continue;
        const owner = graph.moduleForDeclaration(f.declaration) orelse continue;
        const owner_path = try std.fs.path.resolve(allocator, &.{graph.text(graph.modules.items[@intFromEnum(owner)].dir)});
        if (!std.mem.eql(u8, module_path, owner_path)) continue;
        if (entry != null) return error.AmbiguousEntry;
        entry = @enumFromInt(i);
    }
    const id = entry orelse return error.MissingEntry;
    const function = graph.function(id);
    const source = graph.declaration(function.declaration).source;
    if (function.input.len != 0 or function.output.len > 1) {
        try report(&diagnostics, graph, source, "VM entry requires main with no inputs and no result or status_code: Int32");
        return error.CompilationFailed;
    }
    if (function.output.len == 1) {
        const output = graph.fields.items[function.output.start];
        const ty = graph.semanticType(output.ty);
        if (ty != .builtin or ty.builtin != .Int32 or !std.mem.eql(u8, graph.text(output.name), "status_code")) {
            try report(&diagnostics, graph, source, "VM entry result must be status_code: Int32");
            return error.CompilationFailed;
        }
    }
    var compiler = try lower.Lower.init(allocator, graph);
    compiler.mode = .runtime;
    if (pipeline.safety_ctx) |*safety| compiler.annotations = &safety.annotations;
    compiler.diagnostics = &diagnostics;
    const program = compiler.compile(id) catch |err| {
        const message = try std.fmt.allocPrint(allocator, "VM cannot lower {s}: {s}", .{ compiler.unsupported, @errorName(err) });
        try report(&diagnostics, graph, compiler.source, message);
        return error.CompilationFailed;
    };
    const interrupts = try @import("execution_interrupt.zig").Guard.init();
    defer interrupts.deinit();
    limits.cancellation = interrupts.token();
    var executor = vm.Vm.init(allocator, program, limits) catch |err| {
        if (err == error.MissingHostBinding or err == error.IncompatibleHostBinding or err == error.AmbiguousHostBinding) {
            const host = @import("../execution/host.zig");
            if (host.findFailure(program, &.{})) |failure| {
                const message = try std.fmt.allocPrint(allocator, "VM host binding for '{s}' is unavailable: {s}", .{ host.symbol(graph, failure.function), @errorName(failure.reason) });
                try report(&diagnostics, graph, failure.source, message);
                return error.CompilationFailed;
            }
        }
        const message = try std.fmt.allocPrint(allocator, "VM initialization failed: {s}", .{@errorName(err)});
        try report(&diagnostics, graph, compiler.source, message);
        return error.CompilationFailed;
    };
    defer executor.deinit();
    const result = executor.run(id, &.{}) catch |err| {
        try @import("../execution/failure.zig").report(allocator, &diagnostics, &executor, graph, "VM execution failed", err);
        try diagnostics.dump();
        if (err == error.ExecutionCancelled) return 130;
        return error.CompilationFailed;
    };
    if (result.len == 0) return 0;
    // Match process exit status truncation without a host-dependent integer cast.
    return @intCast(@mod(result[0].integer, 256));
}
fn report(diagnostics: *diag.Diagnostics, graph: *const g.GlobalSemanticGraph, source: p.SourceRef, message: []const u8) !void {
    const location = @import("../4_semantics/global/source_location.zig").location(graph, diagnostics, source);
    try diagnostics.add(location, .semantic, "{s}", .{message});
    try diagnostics.dump();
}
