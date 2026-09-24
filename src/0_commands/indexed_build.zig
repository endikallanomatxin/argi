const std = @import("std");
const llvm = @import("../5_codegen/llvm.zig");
const c = llvm.c;
const sf = @import("../1_base/source_files.zig");
const diag = @import("../1_base/diagnostic.zig");
const link = @import("../5_codegen/link.zig");
const frontend = @import("frontend_pipeline.zig");
const codegen = @import("../5_codegen/global_codegen.zig");
const graph_mod = @import("../4_semantics/global/graph.zig");
const types = @import("../4_semantics/global/types.zig");
const graph_print = @import("../4_semantics/global/print.zig");
const global_semantizer = @import("../4_semantics/global/semantizer.zig");
const global_dispatch = @import("../4_semantics/global/dispatch.zig");
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
    const semantic = pipeline.global_stats;
    const semantic_timings = semantic.timings;
    std.debug.print("Timing\n", .{});
    std.debug.print("  indexed frontend: {d:.3} ms\n", .{@as(f64, @floatFromInt(frontend_ns)) / 1_000_000.0});
    std.debug.print("    ModuleSema:     {d:.3} ms\n", .{@as(f64, @floatFromInt(pipeline.module_semantizing_ns)) / 1_000_000.0});
    std.debug.print("    GlobalSema:     {d:.3} ms\n", .{@as(f64, @floatFromInt(pipeline.global_semantic_ns)) / 1_000_000.0});
    std.debug.print("    GlobalSafety:   {d:.3} ms\n", .{@as(f64, @floatFromInt(pipeline.safety_ns)) / 1_000_000.0});
    std.debug.print("  codegen:          {d:.3} ms\n", .{@as(f64, @floatFromInt(codegen_ns)) / 1_000_000.0});
    std.debug.print("  link:             {d:.3} ms\n", .{@as(f64, @floatFromInt(link_ns)) / 1_000_000.0});

    std.debug.print("Global semantizing\n", .{});
    std.debug.print("  relocate and link:           {d:.3} ms\n", .{milliseconds(semantic_timings.relocation_ns)});
    std.debug.print("  setup:                       {d:.3} ms\n", .{milliseconds(semantic_timings.setup_ns)});
    std.debug.print("  fixed point:                 {d:.3} ms ({d} rounds, {d} pending attempts)\n", .{
        milliseconds(semantic_timings.fixed_point_ns), semantic.rounds, semantic.pending_attempts,
    });
    std.debug.print("    pending resolution:        {d:.3} ms\n", .{milliseconds(semantic_timings.pending_ns)});
    std.debug.print("      by owner (initial/attempts/deferred/resolved/invalid, ms):\n", .{});
    inline for (std.meta.fields(global_semantizer.PendingOwner), 0..) |field, index| {
        const item = semantic.pending_by_owner[index];
        if (item.initial_operations != 0) {
            std.debug.print("        {s}: {d}/{d}/{d}/{d}/{d}, {d:.3} ms ({d:.3} deferred)\n", .{
                field.name,            item.initial_operations,        item.attempts,
                item.deferred,         item.resolved,                  item.invalid,
                milliseconds(item.ns), milliseconds(item.deferred_ns),
            });
        }
    }
    std.debug.print("      by operation (initial/attempts/deferred/resolved/invalid, ms):\n", .{});
    inline for (std.meta.fields(global_semantizer.PendingTag), 0..) |field, index| {
        const item = semantic.pending_by_operation[index];
        if (item.initial_operations != 0) {
            std.debug.print("        {s}: {d}/{d}/{d}/{d}/{d}, {d:.3} ms ({d:.3} deferred)\n", .{
                field.name,            item.initial_operations,        item.attempts,
                item.deferred,         item.resolved,                  item.invalid,
                milliseconds(item.ns), milliseconds(item.deferred_ns),
            });
        }
    }
    std.debug.print("      call strategies (attempts/resolved/deferred, ms):\n", .{});
    inline for (std.meta.fields(global_dispatch.PendingCallStage), 0..) |field, index| {
        const item = semantic.pending_call_stages[index];
        if (item.attempts != 0) {
            std.debug.print("        {s}: {d}/{d}/{d}, {d:.3} ms\n", .{
                field.name, item.attempts, item.resolved, item.deferred, milliseconds(item.ns),
            });
        }
    }
    std.debug.print("      generic source calls: selection {d:.3} ms, completion {d:.3} ms\n", .{
        milliseconds(semantic_timings.source_generic_selection_ns),
        milliseconds(semantic_timings.source_generic_completion_ns),
    });
    std.debug.print("      generic instantiate: {d:.3} ms, {d} calls, {d} existing\n", .{
        milliseconds(semantic_timings.generic_instantiation_ns),
        semantic.generic_instantiation_calls,
        semantic.generic_existing_instances,
    });
    std.debug.print("        existing lookup {d:.3} ms, context init {d:.3} ms, body lowering {d:.3} ms\n", .{
        milliseconds(semantic_timings.generic_instantiation_lookup_ns),
        milliseconds(semantic_timings.generic_instance_context_init_ns),
        milliseconds(semantic_timings.generic_instantiation_body_ns),
    });
    const call_blockers = semantic.call_blockers;
    std.debug.print("      deferred calls observed: {d} without ID, {d} one type, {d} one binding, {d} multiple IDs\n", .{
        call_blockers.deferred_without_observed_id,
        call_blockers.deferred_with_one_type,
        call_blockers.deferred_with_one_binding,
        call_blockers.deferred_with_multiple_ids,
    });
    std.debug.print("      repeated single ID: {d} same, {d} changed, {d} overflowed observations\n", .{
        call_blockers.repeated_same_single_id,
        call_blockers.changed_single_id,
        call_blockers.observations_overflowed,
    });
    std.debug.print("    full-pool materialization:\n", .{});
    std.debug.print("      type reconciliation:     {d:.3} ms\n", .{milliseconds(semantic_timings.type_reconciliation_ns)});
    std.debug.print("      binding reconciliation:  {d:.3} ms\n", .{milliseconds(semantic_timings.binding_reconciliation_ns)});
    std.debug.print("      binding defaults:        {d:.3} ms\n", .{milliseconds(semantic_timings.runtime_binding_defaults_ns)});
    std.debug.print("      string literal types:    {d:.3} ms\n", .{milliseconds(semantic_timings.string_literal_types_ns)});
    std.debug.print("      binding types:           {d:.3} ms\n", .{milliseconds(semantic_timings.binding_types_ns)});
    std.debug.print("      assignment values:       {d:.3} ms\n", .{milliseconds(semantic_timings.assignment_values_ns)});
    std.debug.print("      dereferences:            {d:.3} ms\n", .{milliseconds(semantic_timings.dereferences_ns)});
    std.debug.print("      addresses:               {d:.3} ms\n", .{milliseconds(semantic_timings.addresses_ns)});
    std.debug.print("      generic types:           {d:.3} ms\n", .{milliseconds(semantic_timings.known_generic_types_ns)});
    std.debug.print("      abstract field storage:  {d:.3} ms\n", .{milliseconds(semantic_timings.abstract_field_storage_ns)});
    std.debug.print("      sugar types:             {d:.3} ms\n", .{milliseconds(semantic_timings.sugar_types_ns)});
    std.debug.print("    error reason inference:    {d:.3} ms\n", .{milliseconds(semantic_timings.error_inference_ns)});
    std.debug.print("    implicit generic constraints: {d:.3} ms\n", .{milliseconds(semantic_timings.generic_constraints_ns)});
    std.debug.print("    ownership cleanup:         {d:.3} ms ({d} attempts)\n", .{
        milliseconds(semantic_timings.cleanup_ns), semantic.cleanup_attempts,
    });
    std.debug.print("      implicit destructors:    {d:.3} ms ({d} lookups)\n", .{
        milliseconds(semantic_timings.implicit_destructor_ns), semantic.destructor_lookups,
    });
    std.debug.print("      generic lookup:          {d:.3} ms\n", .{milliseconds(semantic_timings.implicit_generic_lookup_ns)});
    const implicit = semantic.implicit_lookup;
    std.debug.print("  implicit function lookup (matching time excludes completion):\n", .{});
    std.debug.print("    ordinary: {d:.3} ms, {d} calls, {d} resolved, {d} deferred, {d} no match, {d} ambiguous\n", .{
        milliseconds(implicit.ordinary_matching_ns), implicit.ordinary_calls,
        implicit.ordinary_resolved,                  implicit.ordinary_deferred,
        implicit.ordinary_no_match,                  implicit.ordinary_ambiguous,
    });
    std.debug.print("    abstract-compatible: {d:.3} ms, {d} calls, {d} resolved, {d} deferred, {d} no match, {d} ambiguous\n", .{
        milliseconds(implicit.abstract_compatible_matching_ns), implicit.abstract_compatible_calls,
        implicit.abstract_compatible_resolved,                  implicit.abstract_compatible_deferred,
        implicit.abstract_compatible_no_match,                  implicit.abstract_compatible_ambiguous,
    });
    std.debug.print("    generic: {d:.3} ms, {d} calls, {d} resolved, {d} deferred, {d} no match, {d} ambiguous\n", .{
        milliseconds(implicit.generic_matching_ns), implicit.generic_calls,
        implicit.generic_resolved,                  implicit.generic_deferred,
        implicit.generic_no_match,                  implicit.generic_ambiguous,
    });
    std.debug.print("    completion: {d:.3} ms, {d} calls, {d} deferred\n", .{
        milliseconds(implicit.ordinary_completion_ns + implicit.abstract_compatible_completion_ns + implicit.generic_completion_ns),
        implicit.ordinary_completion_calls + implicit.abstract_compatible_completion_calls + implicit.generic_completion_calls,
        implicit.ordinary_completion_deferred + implicit.abstract_compatible_completion_deferred + implicit.generic_completion_deferred,
    });
    const destructor = semantic.ownership;
    std.debug.print("  destructor resolution: {d} success, {d} failed, {d} repeated target TypeId lookups\n", .{
        destructor.destructor_successes,                    destructor.destructor_failures,
        destructor.destructor_repeated_target_type_lookups,
    });
    std.debug.print("    pointer/address {d:.3} ms, receivers {d:.3} ms, inputs {d:.3} ms, dispatch {d:.3} ms\n", .{
        milliseconds(destructor.destructor_pointer_address_ns),
        milliseconds(destructor.destructor_receiver_discovery_ns),
        milliseconds(destructor.destructor_input_construction_ns),
        milliseconds(destructor.destructor_dispatch_ns),
    });
    std.debug.print("    appended on success: {d} nodes, {d} value fields, {d} string bytes\n", .{
        destructor.destructor_successful_nodes,   destructor.destructor_successful_value_fields,
        destructor.destructor_successful_strings,
    });
    std.debug.print("    appended on failure: {d} nodes, {d} value fields, {d} string bytes\n", .{
        destructor.destructor_failed_nodes,   destructor.destructor_failed_value_fields,
        destructor.destructor_failed_strings,
    });
    std.debug.print("  post-resolution:             {d:.3} ms\n", .{milliseconds(semantic_timings.post_resolution_ns)});
    std.debug.print("  verify:                      {d:.3} ms\n", .{milliseconds(semantic_timings.verify_ns)});
    std.debug.print("  abstract implementation cache hits: {d} positive, {d} negative\n", .{
        semantic.cached_implementation_hits, semantic.cached_nonimplementation_hits,
    });
    std.debug.print("  abstract implementation scans: {d:.3} ms, {d} over {d} candidates\n", .{
        milliseconds(semantic.abstracts.implementation_scan_ns), semantic.abstracts.implementation_scans,
        semantic.abstracts.implementation_candidates,
    });
    std.debug.print("  type interning: {d:.3} ms, {d} calls, {d} candidates\n", .{
        milliseconds(semantic.generics.type_intern_ns), semantic.generics.type_intern_calls,
        semantic.generics.type_intern_candidates,
    });
    std.debug.print("  pointer type lookup: {d:.3} ms, {d} calls, {d} candidates\n", .{
        milliseconds(semantic.core.pointer_type_ns), semantic.core.pointer_type_calls,
        semantic.core.pointer_type_candidates,
    });

    std.debug.print("Indexed frontend\n", .{});
    std.debug.print("  tokens:                       {d}\n", .{pipeline.tokenCount()});
    std.debug.print("  syntax nodes:                 {d}\n", .{pipeline.syntax_node_count});
    std.debug.print("  ModuleSemanticGraph bytes:    {d}\n", .{pipeline.moduleSemanticStorageBytes()});
    std.debug.print("  GlobalSemanticGraph bytes:    {d}\n", .{pipeline.globalSemanticStorageBytes()});
    std.debug.print("  ModuleSema precise functions: {d}\n", .{pipeline.module_lowered_functions});
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

fn milliseconds(ns: u64) f64 {
    return @as(f64, @floatFromInt(ns)) / 1_000_000.0;
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
        .frontend_options = .{ .semantizing = .{
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
