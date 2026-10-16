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
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
        if (std.mem.eql(u8, arg, "--vm")) continue;
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
    const program = compiler.compile(id) catch |err| {
        const message = try std.fmt.allocPrint(allocator, "VM cannot lower {s}: {s}", .{ compiler.unsupported, @errorName(err) });
        try report(&diagnostics, graph, compiler.source, message);
        return error.CompilationFailed;
    };
    var executor = try vm.Vm.init(allocator, program, .{});
    defer executor.deinit();
    const result = executor.run(id, &.{}) catch |err| {
        const message = try std.fmt.allocPrint(allocator, "VM execution failed: {s}", .{@errorName(err)});
        try report(&diagnostics, graph, executor.source, message);
        return error.CompilationFailed;
    };
    if (result.len == 0) return 0;
    // Match process exit status truncation without a host-dependent integer cast.
    return @intCast(@mod(result[0].integer, 256));
}
fn report(diagnostics: *diag.Diagnostics, graph: *const g.GlobalSemanticGraph, source: p.SourceRef, message: []const u8) !void {
    var location = @import("../2_tokens/token.zig").Location{ .file = @enumFromInt(0), .offset = source.offset };
    if (source.file_index < graph.files.items.len) {
        const file = graph.files.items[source.file_index];
        const dir = graph.text(graph.modules.items[@intFromEnum(file.module)].dir);
        for (diagnostics.source_db.files, 0..) |candidate, i| {
            if (std.mem.eql(u8, std.fs.path.basename(candidate.path), graph.text(file.path)) and std.mem.eql(u8, std.fs.path.dirname(candidate.path) orelse ".", dir)) {
                location.file = diagnostics.source_db.fileId(i);
                break;
            }
        }
    }
    try diagnostics.add(location, .semantic, "{s}", .{message});
    try diagnostics.dump();
}
