const std = @import("std");
const llvm = @import("../5_codegen/llvm.zig");
const c = llvm.c;
const sf = @import("../1_base/source_files.zig");
const diag = @import("../1_base/diagnostic.zig");
const link = @import("../5_codegen/link.zig");
const frontend = @import("frontend_pipeline.zig");
const codegen = @import("../5_codegen/global_codegen.zig");
const graph_mod = @import("../4_semantics/global_semantic_graph.zig");
const types = @import("../4_semantics/global_semantic_types.zig");
const graph_print = @import("../4_semantics/global_semantic_print.zig");
const planning = @import("build_plan.zig");

pub const BuildFlags = planning.BuildFlags;
pub const BuildPlan = planning.BuildPlan;
pub const parseBuildArgs = planning.parseBuildArgs;
pub const resolveBuildModuleDir = planning.resolveBuildModuleDir;
pub const resolveBuildPlans = planning.resolveBuildPlans;
pub const resolveBuildPlan = planning.resolveBuildPlan;
pub const resolveRunPlan = planning.resolveRunPlan;
pub const localCacheRoot = planning.localCacheRoot;

pub const CompileOptions = struct {
    frontend_options: frontend.FrontendPipeline.Options = .{},
    codegen_options: codegen.CodeGenerator.Options = .{},
    success_message: ?[]const u8 = "✔ Build completed\n",
    check_only: bool = false,
};

fn nowNs(io: std.Io) i96 {
    return std.Io.Timestamp.now(io, .boot).nanoseconds;
}

fn elapsedSince(io: std.Io, start: i96) u64 {
    return @intCast(std.Io.Timestamp.now(io, .boot).nanoseconds - start);
}

fn ensureParentDir(io: std.Io, path: []const u8) !void {
    const parent = std.fs.path.dirname(path) orelse return;
    if (parent.len == 0 or std.mem.eql(u8, parent, ".")) return;
    try std.Io.Dir.cwd().createDirPath(io, parent);
}

fn replaceFile(io: std.Io, src: []const u8, dst: []const u8) !void {
    std.Io.Dir.deleteFileAbsolute(io, dst) catch |err| switch (err) {
        error.FileNotFound => {},
        else => return err,
    };
    try std.Io.Dir.renameAbsolute(src, dst, io);
}

fn hasExecutableMain(graph: *const graph_mod.GlobalSemanticGraph) bool {
    for (graph.functions.items) |function| {
        const declaration = graph.declarations.items[@intFromEnum(function.declaration)];
        if (!std.mem.eql(u8, graph.text(declaration.name), "main")) continue;
        if (function.output.len != 1) continue;
        const output = graph.fields.items[function.output.start];
        if (!std.mem.eql(u8, graph.text(output.name), "status_code")) continue;
        if (types.isBuiltin(graph, output.ty, .Int32)) return true;
    }
    return false;
}

fn printMissingMainError(module_dir: []const u8, from_manifest: bool) void {
    if (from_manifest)
        std.debug.print("Error: executable module has no valid main function:\n  {s}\n\n", .{module_dir})
    else
        std.debug.print("Error: module has no executable main function:\n  {s}\n\n", .{module_dir});
    std.debug.print("Expected main() -> (.status_code: Int32).\n", .{});
}

fn dumpDiagnostics(diagnostics: *diag.Diagnostics, flags: BuildFlags) void {
    diagnostics.dumpWithLimit(if (flags.show_cascade) std.math.maxInt(usize) else 1) catch |err|
        std.debug.print("failed to print diagnostics: {s}\n", .{@errorName(err)});
}

fn printStats(
    frontend_ns: u64,
    codegen_ns: u64,
    link_ns: u64,
    pipeline: *const frontend.FrontendPipeline,
    generator: ?*const codegen.CodeGenerator,
) void {
    std.debug.print("Timing\n", .{});
    std.debug.print("  indexed frontend: {d:.3} ms\n", .{@as(f64, @floatFromInt(frontend_ns)) / 1_000_000.0});
    std.debug.print("    ModuleSema:     {d:.3} ms\n", .{@as(f64, @floatFromInt(pipeline.module_semantizing_ns)) / 1_000_000.0});
    std.debug.print("    GlobalSema:     {d:.3} ms\n", .{@as(f64, @floatFromInt(pipeline.global_semantic_ns)) / 1_000_000.0});
    std.debug.print("    GlobalSafety:   {d:.3} ms\n", .{@as(f64, @floatFromInt(pipeline.safety_ns)) / 1_000_000.0});
    std.debug.print("  codegen:          {d:.3} ms\n", .{@as(f64, @floatFromInt(codegen_ns)) / 1_000_000.0});
    std.debug.print("  link:             {d:.3} ms\n", .{@as(f64, @floatFromInt(link_ns)) / 1_000_000.0});

    std.debug.print("Indexed frontend\n", .{});
    std.debug.print("  tokens:                       {d}\n", .{pipeline.tokenCount()});
    std.debug.print("  syntax nodes:                 {d}\n", .{pipeline.syntax_node_count});
    std.debug.print("  ModuleSemanticGraph bytes:    {d}\n", .{pipeline.moduleSemanticStorageBytes()});
    std.debug.print("  GlobalSemanticGraph bytes:    {d}\n", .{pipeline.globalSemanticStorageBytes()});
    std.debug.print("  ModuleSema precise functions: {d}\n", .{pipeline.module_lowered_functions});
    std.debug.print("  ModuleSema fallback functions:{d}\n", .{pipeline.module_fallback_functions});
    std.debug.print("  pending global operations:    {d}\n", .{pipeline.global_stats.pending_total});
    std.debug.print("  resolved global operations:   {d}\n", .{pipeline.global_stats.pending_resolved});

    const safety = pipeline.global_safety_stats;
    std.debug.print("Safety\n", .{});
    std.debug.print("  functions:            {d}\n", .{safety.functions});
    std.debug.print("  calls:                {d}\n", .{safety.calls});
    std.debug.print("  state clones:         {d}\n", .{safety.state_clones});
    std.debug.print("  state elements copied:{d}\n", .{safety.state_elements_copied});
    std.debug.print("  primitive calls:      {d}\n", .{safety.primitive_calls});
    std.debug.print("  recursive edges:      {d}\n", .{safety.recursive_edges});

    if (generator) |gen| if (gen.collectStats()) |stats| {
        std.debug.print("Codegen\n", .{});
        std.debug.print("  semantic functions: {d}\n", .{stats.semantic_functions});
        std.debug.print("  LLVM functions:     {d}\n", .{stats.llvm_functions_with_body});
        std.debug.print("  basic blocks:       {d}\n", .{stats.basic_blocks});
        std.debug.print("  instructions:       {d}\n", .{stats.instructions});
        std.debug.print("  IR bytes:           {d}\n", .{stats.ir_bytes});
    } else |_| {};
}

pub fn compileTarget(
    target_path: []const u8,
    flags: BuildFlags,
    options: CompileOptions,
    io: std.Io,
    environ_map: ?*const std.process.Environ.Map,
) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const plans = try planning.resolveBuildPlans(allocator, io, target_path, flags);
    if (plans.items.len > 1 and flags.output_path != null) {
        std.debug.print("Error: --output is ambiguous when building multiple executables.\n", .{});
        return error.CompilationFailed;
    }
    for (plans.items) |plan| try compileResolvedPlan(allocator, plan, flags, options, io, environ_map);
}

fn compileResolvedPlan(
    allocator: std.mem.Allocator,
    plan: BuildPlan,
    flags: BuildFlags,
    options: CompileOptions,
    io: std.Io,
    environ_map: ?*const std.process.Environ.Map,
) !void {
    const cwd = try std.process.currentPathAlloc(io, allocator);
    const final_output = if (flags.output_path) |path| try std.fs.path.resolve(allocator, &.{ cwd, path }) else plan.output_path;
    const final_ir = if (flags.llvm_ir_path) |path| try std.fs.path.resolve(allocator, &.{ cwd, path }) else null;
    const final_obj = if (flags.just_object_path) |path|
        try std.fs.path.resolve(allocator, &.{ cwd, path })
    else if (flags.object_path) |path|
        try std.fs.path.resolve(allocator, &.{ cwd, path })
    else
        null;
    const object_only = flags.just_object_path != null;
    if (!options.check_only) {
        if (!object_only) try ensureParentDir(io, final_output);
        if (final_ir) |path| try ensureParentDir(io, path);
        if (final_obj) |path| try ensureParentDir(io, path);
    }

    const files = try sf.collectModuleWithOptions(&allocator, io, .{
        .explicit_sysroot = flags.sysroot_path,
        .environ_map = environ_map,
    }, plan.module_dir);
    var diagnostics = diag.Diagnostics.init(&allocator, files.items);
    var frontend_options = options.frontend_options;
    frontend_options.collect_stats = flags.stats;
    var pipeline = frontend.FrontendPipeline.init(allocator, io, &diagnostics, frontend_options);
    defer pipeline.deinit();

    const frontend_start = nowNs(io);
    const graph = pipeline.semantizeGlobalFiles(files.items) catch |err| {
        if (flags.show_syntax_tree) if (pipeline.syntax_ctx) |*ctx| ctx.printST();
        if (flags.show_semantic_graph) if (pipeline.global_graph) |*built| graph_print.print(built);
        dumpDiagnostics(&diagnostics, flags);
        if (!diagnostics.hasErrors()) std.debug.print("indexed semantizing failed without a diagnostic: {s}\n", .{@errorName(err)});
        return error.CompilationFailed;
    };
    const frontend_ns = elapsedSince(io, frontend_start);

    if (flags.show_semantic_graph) graph_print.print(graph);
    if (diagnostics.hasErrors()) {
        dumpDiagnostics(&diagnostics, flags);
        return error.CompilationFailed;
    }
    if (options.check_only) {
        if (flags.stats) printStats(frontend_ns, 0, 0, &pipeline, null);
        if (options.success_message) |message| std.debug.print("{s}", .{message});
        return;
    }

    const codegen_start = nowNs(io);
    var generator = codegen.CodeGenerator.init(allocator, io, graph, &diagnostics, options.codegen_options) catch |err| {
        std.debug.print("failed to initialize indexed codegen: {s}\n", .{@errorName(err)});
        return error.CompilationFailed;
    };
    defer generator.deinit();
    const module = generator.generate() catch |err| {
        if (flags.show_semantic_graph) graph_print.print(graph);
        dumpDiagnostics(&diagnostics, flags);
        if (!diagnostics.hasErrors()) std.debug.print("indexed codegen failed without a diagnostic: {s}\n", .{@errorName(err)});
        return error.CompilationFailed;
    };
    const codegen_ns = elapsedSince(io, codegen_start);

    if (!object_only and options.codegen_options.selected_test_name == null and !hasExecutableMain(graph)) {
        printMissingMainError(plan.module_dir, plan.module_root != null);
        return error.CompilationFailed;
    }

    const stem_base = if (object_only) final_obj.? else final_output;
    const temp_stem = try std.fmt.allocPrint(allocator, "{s}.tmp.{d}", .{ stem_base, nowNs(io) });
    const temp_ir = if (final_ir != null) try std.fmt.allocPrint(allocator, "{s}.ll", .{temp_stem}) else null;
    const temp_obj = try std.fmt.allocPrint(allocator, "{s}.o", .{temp_stem});
    try ensureParentDir(io, temp_stem);
    if (temp_ir) |path| try ensureParentDir(io, path);
    try ensureParentDir(io, temp_obj);

    if (temp_ir) |path| {
        var message: [*c]u8 = null;
        const path_z = try allocator.dupeZ(u8, path);
        if (c.LLVMPrintModuleToFile(module, path_z.ptr, &message) != 0) {
            if (message != null) std.debug.print("Failed to write LLVM module: {s}\n", .{message});
            return error.WriteFailed;
        }
    }

    const triple_message = c.LLVMGetDefaultTargetTriple();
    defer c.LLVMDisposeMessage(triple_message);
    const triple = std.mem.span(triple_message);
    const link_start = nowNs(io);
    if (object_only)
        try link.emitObjectFile(module, triple, temp_obj, flags.optimization_mode)
    else
        try link.linkWithLibc(module, triple, temp_stem, &allocator, io, environ_map, flags.optimization_mode);
    const link_ns = elapsedSince(io, link_start);

    if (temp_ir) |src| try replaceFile(io, src, final_ir.?);
    if (!object_only) try replaceFile(io, temp_stem, final_output);
    if (final_obj) |dst| {
        try replaceFile(io, temp_obj, dst);
    } else {
        std.Io.Dir.deleteFileAbsolute(io, temp_obj) catch |err| if (err != error.FileNotFound) return err;
    }

    if (flags.stats) printStats(frontend_ns, codegen_ns, link_ns, &pipeline, &generator);
    if (options.success_message) |message| std.debug.print("{s}", .{message});
}

pub fn compile(io: std.Io, environ_map: ?*const std.process.Environ.Map, args: []const []const u8) !void {
    const parsed = try planning.parseBuildArgs(args);
    try compileTarget(parsed.target_path, parsed.flags, .{}, io, environ_map);
}

pub fn check(io: std.Io, environ_map: ?*const std.process.Environ.Map, args: []const []const u8) !void {
    const parsed = try planning.parseBuildArgs(args);
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const core_dir = try sf.resolveToolCoreDir(&allocator, io, .{
        .explicit_sysroot = parsed.flags.sysroot_path,
        .environ_map = environ_map,
    });
    const testing_module_dir = try std.fs.path.join(allocator, &.{ core_dir, "testing" });
    try compileTarget(parsed.target_path, parsed.flags, .{
        .frontend_options = .{ .semantizer = .{
            .include_tests = true,
            .implicit_testing_module_dir = testing_module_dir,
            .exhaustive_function_bodies = true,
        } },
        .success_message = "✔ Check completed\n",
        .check_only = true,
    }, io, environ_map);
}

test "indexed build recognizes GlobalSG main signatures" {
    const allocator = std.testing.allocator;
    var graph: graph_mod.GlobalSemanticGraph = .{};
    defer graph.deinit(allocator);
    const main_name = try graph.addString(allocator, "main");
    const status_name = try graph.addString(allocator, "status_code");
    try graph.types.append(allocator, .{ .builtin = .Int32 });
    try graph.declarations.append(allocator, .{ .kind = .function, .name = main_name, .source = .{ .file_index = 0, .offset = 0 }, .function_id = @enumFromInt(0) });
    try graph.fields.append(allocator, .{ .name = status_name, .ty = @enumFromInt(0), .source = .{ .file_index = 0, .offset = 0 } });
    try graph.functions.append(allocator, .{ .declaration = @enumFromInt(0), .input = .{ .start = 0, .len = 0 }, .output = .{ .start = 0, .len = 1 } });
    try std.testing.expect(hasExecutableMain(&graph));
}
