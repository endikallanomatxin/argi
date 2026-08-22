const std = @import("std");

const llvm = @import("../5_codegen/llvm.zig");
const c = llvm.c;

const sf = @import("../1_base/source_files.zig");
const diag = @import("../1_base/diagnostic.zig");
const token = @import("../2_tokens/token.zig");
const link = @import("../5_codegen/link.zig");
const codegen = @import("../5_codegen/codegen.zig");
const tokp = @import("../2_tokens/token_print.zig");
const frontend = @import("frontend_pipeline.zig");
const semantizer_mod = @import("../4_semantics/semantizer.zig");
const sg_mod = @import("../4_semantics/semantic_graph.zig");

pub const BuildFlags = struct {
    show_cascade: bool = false,
    show_syntax_tree: bool = false,
    show_semantic_graph: bool = false,
    show_token_list: bool = false,
    time_phases: bool = false,
    output_path: ?[]const u8 = null,
    llvm_ir_path: ?[]const u8 = null,
    object_path: ?[]const u8 = null,
    just_object_path: ?[]const u8 = null,
    sysroot_path: ?[]const u8 = null,
    executable_name: ?[]const u8 = null,
};

const ParsedBuildArgs = struct {
    target_path: []const u8 = ".",
    flags: BuildFlags = .{},
};

pub const BuildPlan = struct {
    target_path: []const u8,
    module_dir: []const u8,
    output_path: []const u8,
    executable_name: ?[]const u8 = null,
    module_root: ?[]const u8 = null,
};

const ManifestExecutable = struct {
    name: []const u8,
    path: ?[]const u8 = null,
};

const ModuleManifest = struct {
    name: ?[]const u8 = null,
    run_default: ?[]const u8 = null,
    executables: std.array_list.Managed(ManifestExecutable),

    fn init(allocator: std.mem.Allocator) ModuleManifest {
        return .{
            .executables = std.array_list.Managed(ManifestExecutable).init(allocator),
        };
    }
};

pub const CompileOptions = struct {
    frontend_options: frontend.FrontendPipeline.Options = .{},
    codegen_options: codegen.CodeGenerator.Options = .{},
    success_message: ?[]const u8 = "✔ Build completed\n",
};

/// Argi keeps project-local transient artifacts under `.argi-cache/`.
/// This stays separate from explicit user outputs like `build/output` or
/// `--output <path>`, and gives `argi test` a stable place to put generated
/// binaries without polluting source fixtures.
pub fn localCacheRoot(allocator: std.mem.Allocator) ![]u8 {
    return std.fs.path.resolve(allocator, &.{".argi-cache"});
}

const PhaseTimings = struct {
    collect_files_ns: u64 = 0,
    tokenize_ns: u64 = 0,
    syntax_ns: u64 = 0,
    semantizing_ns: u64 = 0,
    codegen_ns: u64 = 0,
    link_ns: u64 = 0,

    fn total(self: PhaseTimings) u64 {
        return self.collect_files_ns + self.tokenize_ns + self.syntax_ns + self.semantizing_ns + self.codegen_ns + self.link_ns;
    }
};

pub fn parseBuildArgs(args: []const []const u8) !ParsedBuildArgs {
    var parsed: ParsedBuildArgs = .{};
    var saw_target = false;
    var idx: usize = 0;
    while (idx < args.len) : (idx += 1) {
        const a = args[idx];
        if (std.mem.eql(u8, a, "--on-build-error-show-cascade")) {
            parsed.flags.show_cascade = true;
        } else if (std.mem.eql(u8, a, "--on-build-error-show-syntax-tree")) {
            parsed.flags.show_syntax_tree = true;
        } else if (std.mem.eql(u8, a, "--on-build-error-show-semantic-graph")) {
            parsed.flags.show_semantic_graph = true;
        } else if (std.mem.eql(u8, a, "--on-build-error-show-token-list")) {
            parsed.flags.show_token_list = true;
        } else if (std.mem.eql(u8, a, "--time-phases")) {
            parsed.flags.time_phases = true;
        } else if (std.mem.eql(u8, a, "--output")) {
            idx += 1;
            if (idx >= args.len) return error.MissingFlagValue;
            parsed.flags.output_path = args[idx];
        } else if (std.mem.eql(u8, a, "--emit-llvm")) {
            idx += 1;
            if (idx >= args.len) return error.MissingFlagValue;
            parsed.flags.llvm_ir_path = args[idx];
        } else if (std.mem.eql(u8, a, "--emit-obj")) {
            idx += 1;
            if (idx >= args.len) return error.MissingFlagValue;
            parsed.flags.object_path = args[idx];
        } else if (std.mem.eql(u8, a, "--just-emit-obj")) {
            idx += 1;
            if (idx >= args.len) return error.MissingFlagValue;
            parsed.flags.just_object_path = args[idx];
        } else if (std.mem.eql(u8, a, "--sysroot")) {
            idx += 1;
            if (idx >= args.len) return error.MissingFlagValue;
            parsed.flags.sysroot_path = args[idx];
        } else if (std.mem.eql(u8, a, "--exec") or std.mem.eql(u8, a, "--executable")) {
            idx += 1;
            if (idx >= args.len) return error.MissingFlagValue;
            parsed.flags.executable_name = args[idx];
        } else if (std.mem.startsWith(u8, a, "--")) {
            return error.UnknownFlag;
        } else {
            if (saw_target) return error.UnknownFlag;
            parsed.target_path = a;
            saw_target = true;
        }
    }
    if (parsed.flags.object_path != null and parsed.flags.just_object_path != null) return error.ConflictingObjectEmissionModes;
    return parsed;
}

fn parseFlags(args: []const []const u8) !BuildFlags {
    const parsed = try parseBuildArgs(args);
    if (!std.mem.eql(u8, parsed.target_path, ".")) return error.UnknownFlag;
    return parsed.flags;
}

fn printTokenList(all: []const token.Token) void {
    std.debug.print("\nTOKENS\n", .{});
    for (all, 0..) |t, i| {
        std.debug.print("{d}: ", .{i});
        tokp.printTokenWithLocation(t, t.location);
    }
}

fn nowNs(io: std.Io) i96 {
    return std.Io.Timestamp.now(io, .boot).nanoseconds;
}

fn elapsedSince(io: std.Io, start_ns: i96) u64 {
    return @intCast(std.Io.Timestamp.now(io, .boot).nanoseconds - start_ns);
}

fn printPhaseTimings(timings: PhaseTimings) void {
    std.debug.print("phase timings:\n", .{});
    std.debug.print("  collect files: {d:.3} ms\n", .{@as(f64, @floatFromInt(timings.collect_files_ns)) / 1_000_000.0});
    std.debug.print("  tokenize:      {d:.3} ms\n", .{@as(f64, @floatFromInt(timings.tokenize_ns)) / 1_000_000.0});
    std.debug.print("  syntax:        {d:.3} ms\n", .{@as(f64, @floatFromInt(timings.syntax_ns)) / 1_000_000.0});
    std.debug.print("  semantizing:   {d:.3} ms\n", .{@as(f64, @floatFromInt(timings.semantizing_ns)) / 1_000_000.0});
    std.debug.print("  codegen:       {d:.3} ms\n", .{@as(f64, @floatFromInt(timings.codegen_ns)) / 1_000_000.0});
    std.debug.print("  link:          {d:.3} ms\n", .{@as(f64, @floatFromInt(timings.link_ns)) / 1_000_000.0});
    std.debug.print("  total:         {d:.3} ms\n", .{@as(f64, @floatFromInt(timings.total())) / 1_000_000.0});
}

fn printSemantizingTimings(timings: semantizer_mod.Semantizer.SemantizeTimings) void {
    std.debug.print("semantizing breakdown:\n", .{});
    std.debug.print("  initial pass:          {d:.3} ms\n", .{@as(f64, @floatFromInt(timings.initial_pass_ns)) / 1_000_000.0});
    std.debug.print("    support top-level:   {d:.3} ms\n", .{@as(f64, @floatFromInt(timings.support_top_level_ns)) / 1_000_000.0});
    std.debug.print("    function interface:  {d:.3} ms\n", .{@as(f64, @floatFromInt(timings.function_interface_ns)) / 1_000_000.0});
    std.debug.print("    function in defaults:{d:.3} ms\n", .{@as(f64, @floatFromInt(timings.function_input_defaults_ns)) / 1_000_000.0});
    std.debug.print("    function out defs:   {d:.3} ms\n", .{@as(f64, @floatFromInt(timings.function_output_defaults_ns)) / 1_000_000.0});
    std.debug.print("    function bodies:     {d:.3} ms\n", .{@as(f64, @floatFromInt(timings.function_body_ns)) / 1_000_000.0});
    std.debug.print("  retry passes:          {d:.3} ms\n", .{@as(f64, @floatFromInt(timings.retry_passes_ns)) / 1_000_000.0});
    std.debug.print("  initial retry nodes:   {d}\n", .{timings.initial_retry_count});
    std.debug.print("  retry rounds:          {d}\n", .{timings.retry_round_count});
    std.debug.print("  retry enqueue dedupe:  {d}/{d}\n", .{ timings.retry_enqueue_unique, timings.retry_enqueue_attempts });
    std.debug.print("  retry node kinds:      fn={d} type={d} symbol={d} other={d}\n", .{
        timings.retry_function_nodes,
        timings.retry_type_nodes,
        timings.retry_symbol_nodes,
        timings.retry_other_nodes,
    });
    std.debug.print("  final retry resolve:   {d:.3} ms\n", .{@as(f64, @floatFromInt(timings.final_retry_resolution_ns)) / 1_000_000.0});
    std.debug.print("  verify abstracts:      {d:.3} ms\n", .{@as(f64, @floatFromInt(timings.abstract_verify_ns)) / 1_000_000.0});
    std.debug.print("  verify once:           {d:.3} ms\n", .{@as(f64, @floatFromInt(timings.once_verify_ns)) / 1_000_000.0});
    std.debug.print("  infer error reasons:   {d:.3} ms\n", .{@as(f64, @floatFromInt(timings.error_reason_inference_ns)) / 1_000_000.0});
    std.debug.print("  semantizing total:     {d:.3} ms\n", .{@as(f64, @floatFromInt(timings.total())) / 1_000_000.0});
}

fn dumpDiagnosticsOrWarn(
    diagnostics: *diag.Diagnostics,
    limit: usize,
) void {
    diagnostics.dumpWithLimit(limit) catch |err| {
        std.debug.print("failed to print diagnostics: {s}\n", .{@errorName(err)});
    };
}

pub fn resolveBuildModuleDir(allocator: std.mem.Allocator, io: std.Io, path: []const u8) ![]u8 {
    const cwd_path = try std.process.currentPathAlloc(io, allocator);
    defer allocator.free(cwd_path);
    const cwd = std.Io.Dir.cwd();
    if (cwd.openDir(io, path, .{})) |opened_dir| {
        opened_dir.close(io);
        return std.fs.path.resolve(allocator, &.{ cwd_path, path });
    } else |dir_err| switch (dir_err) {
        error.NotDir, error.FileNotFound => {},
        else => return dir_err,
    }

    _ = try cwd.statFile(io, path, .{});
    const dir = std.fs.path.dirname(path) orelse ".";
    return std.fs.path.resolve(allocator, &.{ cwd_path, dir });
}

fn ensureParentDir(io: std.Io, path: []const u8) !void {
    const parent = std.fs.path.dirname(path) orelse return;
    if (parent.len == 0 or std.mem.eql(u8, parent, ".")) return;
    try std.Io.Dir.cwd().createDirPath(io, parent);
}

pub fn defaultOutputPathForModuleDir(allocator: std.mem.Allocator, module_dir: []const u8) ![]u8 {
    return std.fmt.allocPrint(
        allocator,
        "{s}/build/output",
        .{module_dir},
    );
}

fn defaultOutputPathForExecutable(
    allocator: std.mem.Allocator,
    module_root: []const u8,
    executable_name: []const u8,
) ![]u8 {
    return std.fmt.allocPrint(
        allocator,
        "{s}/build/debug/{s}",
        .{ module_root, executable_name },
    );
}

fn manifestPath(allocator: std.mem.Allocator, module_root: []const u8) ![]u8 {
    return try std.fs.path.join(allocator, &.{ module_root, "argi.toml" });
}

fn hasManifest(io: std.Io, allocator: std.mem.Allocator, module_root: []const u8) !bool {
    const path = try manifestPath(allocator, module_root);
    defer allocator.free(path);
    std.Io.Dir.cwd().access(io, path, .{}) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return err,
    };
    return true;
}

fn parseQuotedValue(line: []const u8) ?[]const u8 {
    const eq_idx = std.mem.indexOfScalar(u8, line, '=') orelse return null;
    var value = std.mem.trim(u8, line[eq_idx + 1 ..], " \t\r\n");
    if (std.mem.indexOfScalar(u8, value, '#')) |comment_idx| {
        value = std.mem.trim(u8, value[0..comment_idx], " \t\r\n");
    }
    if (value.len < 2 or value[0] != '"' or value[value.len - 1] != '"') return null;
    return value[1 .. value.len - 1];
}

fn parseKey(line: []const u8) []const u8 {
    const eq_idx = std.mem.indexOfScalar(u8, line, '=') orelse return "";
    return std.mem.trim(u8, line[0..eq_idx], " \t\r\n");
}

fn findExecutable(manifest: *ModuleManifest, name: []const u8) ?*ManifestExecutable {
    for (manifest.executables.items) |*exe| {
        if (std.mem.eql(u8, exe.name, name)) return exe;
    }
    return null;
}

fn readManifest(allocator: std.mem.Allocator, io: std.Io, module_root: []const u8) !ModuleManifest {
    const path = try manifestPath(allocator, module_root);
    defer allocator.free(path);

    const text = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(1024 * 1024));
    var manifest = ModuleManifest.init(allocator);
    var current_executable: ?*ManifestExecutable = null;
    var in_run = false;

    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r\n");
        if (line.len == 0 or line[0] == '#') continue;

        if (line[0] == '[' and line[line.len - 1] == ']') {
            const section = line[1 .. line.len - 1];
            in_run = std.mem.eql(u8, section, "run");
            current_executable = null;
            if (std.mem.startsWith(u8, section, "executables.")) {
                const name = section["executables.".len..];
                try manifest.executables.append(.{ .name = try allocator.dupe(u8, name) });
                current_executable = &manifest.executables.items[manifest.executables.items.len - 1];
            }
            continue;
        }

        const key = parseKey(line);
        const value = parseQuotedValue(line) orelse continue;
        if (current_executable) |exe| {
            if (std.mem.eql(u8, key, "path")) {
                exe.path = try allocator.dupe(u8, value);
            }
        } else if (in_run) {
            if (std.mem.eql(u8, key, "default")) {
                manifest.run_default = try allocator.dupe(u8, value);
            }
        } else {
            if (std.mem.eql(u8, key, "name")) {
                manifest.name = try allocator.dupe(u8, value);
            }
        }
    }

    return manifest;
}

fn printAvailableExecutables(executables: []const ManifestExecutable) void {
    std.debug.print("Available executables:\n", .{});
    for (executables) |exe| {
        std.debug.print("  - {s}\n", .{exe.name});
    }
}

fn printNoExecutablesError() void {
    std.debug.print(
        \\Error: package has no executables to build.
        \\
        \\Add one to argi.toml:
        \\
        \\  [executables.app]
        \\  path = "source/entrypoints/app"
        \\
        \\Or create a library package with:
        \\  argi init --lib <name>
        \\
    , .{});
}

fn printUnknownExecutableError(name: []const u8, executables: []const ManifestExecutable) void {
    std.debug.print("Error: unknown executable '{s}'.\n\n", .{name});
    if (executables.len > 0) printAvailableExecutables(executables);
}

fn printAmbiguousRunDefaultError(executables: []const ManifestExecutable) void {
    std.debug.print("Error: package has multiple executables and no default run target.\n\n", .{});
    printAvailableExecutables(executables);
    std.debug.print("\nUse:\n  argi run {s}\n\n", .{executables[0].name});
    std.debug.print("Or set in argi.toml:\n  [run]\n  default = \"{s}\"\n", .{executables[0].name});
}

fn selectExecutable(manifest: *ModuleManifest, requested: []const u8) !*ManifestExecutable {
    return findExecutable(manifest, requested) orelse {
        printUnknownExecutableError(requested, manifest.executables.items);
        return error.CompilationFailed;
    };
}

fn selectRunExecutable(manifest: *ModuleManifest, requested: ?[]const u8) !*ManifestExecutable {
    if (requested) |name| return try selectExecutable(manifest, name);
    if (manifest.run_default) |name| return try selectExecutable(manifest, name);
    if (manifest.executables.items.len == 1) return &manifest.executables.items[0];
    printAmbiguousRunDefaultError(manifest.executables.items);
    return error.CompilationFailed;
}

fn ensureDirExists(io: std.Io, path: []const u8) !void {
    var dir = std.Io.Dir.cwd().openDir(io, path, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            return error.FileNotFound;
        },
        else => return err,
    };
    dir.close(io);
}

fn appendExecutablePlan(
    allocator: std.mem.Allocator,
    io: std.Io,
    plans: *std.array_list.Managed(BuildPlan),
    target_path: []const u8,
    module_root: []const u8,
    executable: *const ManifestExecutable,
) !void {
    const rel_path = executable.path orelse executable.name;
    const executable_path = try std.fs.path.resolve(allocator, &.{ module_root, rel_path });
    ensureDirExists(io, executable_path) catch |err| switch (err) {
        error.FileNotFound => {
            std.debug.print("Error: executable '{s}' points to missing path:\n  {s}\n", .{ executable.name, rel_path });
            return error.CompilationFailed;
        },
        else => return err,
    };
    try plans.append(.{
        .target_path = target_path,
        .module_root = module_root,
        .module_dir = executable_path,
        .executable_name = executable.name,
        .output_path = try defaultOutputPathForExecutable(allocator, module_root, executable.name),
    });
}

pub fn resolveBuildPlans(
    allocator: std.mem.Allocator,
    io: std.Io,
    target_path: []const u8,
    flags: BuildFlags,
) !std.array_list.Managed(BuildPlan) {
    var plans = std.array_list.Managed(BuildPlan).init(allocator);
    errdefer plans.deinit();

    const target_dir = try resolveBuildModuleDir(allocator, io, target_path);

    if (try hasManifest(io, allocator, target_dir)) {
        var manifest = try readManifest(allocator, io, target_dir);
        if (manifest.executables.items.len == 0) {
            printNoExecutablesError();
            return error.CompilationFailed;
        }
        if (flags.executable_name) |name| {
            const executable = try selectExecutable(&manifest, name);
            try appendExecutablePlan(allocator, io, &plans, target_path, target_dir, executable);
            return plans;
        }
        for (manifest.executables.items) |*executable| {
            try appendExecutablePlan(allocator, io, &plans, target_path, target_dir, executable);
        }
        return plans;
    }

    if (flags.executable_name != null) {
        std.debug.print("Error: --exec requires argi.toml in the selected package root.\n", .{});
        return error.CompilationFailed;
    }

    try plans.append(.{
        .target_path = target_path,
        .module_dir = target_dir,
        .output_path = try defaultOutputPathForModuleDir(allocator, target_dir),
    });
    return plans;
}

pub fn resolveBuildPlan(
    allocator: std.mem.Allocator,
    io: std.Io,
    target_path: []const u8,
    flags: BuildFlags,
) !BuildPlan {
    const plans = try resolveBuildPlans(allocator, io, target_path, flags);
    if (plans.items.len != 1) return error.AmbiguousBuildPlan;
    return plans.items[0];
}

pub fn resolveRunPlan(
    allocator: std.mem.Allocator,
    io: std.Io,
    requested_executable: ?[]const u8,
) !BuildPlan {
    const target_dir = try resolveBuildModuleDir(allocator, io, ".");
    if (!try hasManifest(io, allocator, target_dir)) {
        return .{
            .target_path = ".",
            .module_dir = target_dir,
            .output_path = try defaultOutputPathForModuleDir(allocator, target_dir),
        };
    }

    var manifest = try readManifest(allocator, io, target_dir);
    if (manifest.executables.items.len == 0) {
        printNoExecutablesError();
        return error.CompilationFailed;
    }
    const executable = try selectRunExecutable(&manifest, requested_executable);
    var plans = std.array_list.Managed(BuildPlan).init(allocator);
    try appendExecutablePlan(allocator, io, &plans, ".", target_dir, executable);
    return plans.items[0];
}

fn isWrappableMainCandidate(f: *const sg_mod.FunctionDeclaration) bool {
    if (!std.mem.eql(u8, f.name, "main")) return false;
    if (f.output.fields.len != 1) return false;
    const fld = f.output.fields[0];
    if (!std.mem.eql(u8, fld.name, "status_code")) return false;
    return switch (fld.ty) {
        .builtin => |bt| bt == .Int32,
        else => false,
    };
}

fn hasExecutableMain(nodes: []const *sg_mod.SGNode) bool {
    for (nodes) |node| {
        if (node.content != .function_declaration) continue;
        if (isWrappableMainCandidate(node.content.function_declaration)) return true;
    }
    return false;
}

fn printMissingMainError(module_dir: []const u8, from_manifest: bool) void {
    if (from_manifest) {
        std.debug.print("Error: executable module has no valid main function:\n  {s}\n\n", .{module_dir});
        std.debug.print("Expected main() -> (.status_code: Int32).\n", .{});
    } else {
        std.debug.print("Error: module has no executable main function:\n  {s}\n\n", .{module_dir});
        std.debug.print("Expected main() -> (.status_code: Int32).\n", .{});
    }
}

fn replaceFile(io: std.Io, src: []const u8, dst: []const u8) !void {
    std.Io.Dir.deleteFileAbsolute(io, dst) catch |err| switch (err) {
        error.FileNotFound => {},
        else => return err,
    };
    try std.Io.Dir.renameAbsolute(src, dst, io);
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

    const plans = try resolveBuildPlans(allocator, io, target_path, flags);
    if (plans.items.len > 1 and flags.output_path != null) {
        std.debug.print("Error: --output is ambiguous when building multiple executables.\n", .{});
        return error.CompilationFailed;
    }
    for (plans.items) |plan| {
        try compileResolvedPlan(allocator, plan, flags, options, io, environ_map);
    }
}

fn compileResolvedPlan(
    allocator: std.mem.Allocator,
    plan: BuildPlan,
    flags: BuildFlags,
    options: CompileOptions,
    io: std.Io,
    environ_map: ?*const std.process.Environ.Map,
) !void {
    const module_dir = plan.module_dir;
    var timings: PhaseTimings = .{};
    const cwd_path = try std.process.currentPathAlloc(io, allocator);
    defer allocator.free(cwd_path);

    // Salidas finales por defecto dentro del módulo compilado.
    const final_output_path = if (flags.output_path) |path|
        try std.fs.path.resolve(allocator, &.{ cwd_path, path })
    else
        plan.output_path;
    const final_ir_path = if (flags.llvm_ir_path) |path|
        try std.fs.path.resolve(allocator, &.{ cwd_path, path })
    else
        null;
    const final_obj_path = if (flags.just_object_path) |path|
        try std.fs.path.resolve(allocator, &.{ cwd_path, path })
    else if (flags.object_path) |path|
        try std.fs.path.resolve(allocator, &.{ cwd_path, path })
    else
        null;
    const emit_object_only = flags.just_object_path != null;

    if (!emit_object_only) try ensureParentDir(io, final_output_path);
    if (final_ir_path) |path| try ensureParentDir(io, path);
    if (final_obj_path) |path| try ensureParentDir(io, path);

    // 1. Reunir ficheros ──────────────────────────────────────────────────
    const collect_start = nowNs(io);
    const files = try sf.collectModuleWithOptions(&allocator, io, .{
        .explicit_sysroot = flags.sysroot_path,
        .environ_map = environ_map,
    }, module_dir);
    timings.collect_files_ns = elapsedSince(io, collect_start);

    // 2. Diagnósticos globales ────────────────────────────────────────────
    var diagnostics = diag.Diagnostics.init(&allocator, files.items);

    var pipeline = frontend.FrontendPipeline.init(allocator, io, &diagnostics, options.frontend_options);
    defer pipeline.deinit();

    // 3. Tokenizar todos (fusionando EOF) ─────────────────────────────────
    const tokenize_start = nowNs(io);
    pipeline.tokenizeFiles(files.items) catch {
        timings.tokenize_ns = elapsedSince(io, tokenize_start);
        if (flags.show_token_list) printTokenList(pipeline.tokens.items);
        dumpDiagnosticsOrWarn(&diagnostics, if (flags.show_cascade) std.math.maxInt(usize) else 1);
        return error.CompilationFailed;
    };
    timings.tokenize_ns = elapsedSince(io, tokenize_start);

    // 4. Sintaxis ──────────────────────────────────────────────────────────
    const syntax_start = nowNs(io);
    _ = pipeline.syntax() catch {
        timings.syntax_ns = elapsedSince(io, syntax_start);
        if (flags.show_token_list) printTokenList(pipeline.tokens.items);
        if (pipeline.syntax_ctx) |*syntax_ctx| {
            if (flags.show_syntax_tree) syntax_ctx.printST();
        }
        dumpDiagnosticsOrWarn(&diagnostics, if (flags.show_cascade) std.math.maxInt(usize) else 1);
        return error.CompilationFailed;
    };
    timings.syntax_ns = elapsedSince(io, syntax_start);

    // 5. Semántica ────────────────────────────────────────────────────────
    const semantizing_start = nowNs(io);
    const sg = pipeline.semantize() catch |err| {
        timings.semantizing_ns = elapsedSince(io, semantizing_start);
        if (flags.show_token_list) printTokenList(pipeline.tokens.items);
        if (pipeline.syntax_ctx) |*syntax_ctx| {
            if (flags.show_syntax_tree) syntax_ctx.printST();
        }
        if (pipeline.sem_ctx) |*semantizer_ctx| {
            if (flags.show_semantic_graph) semantizer_ctx.printSG();
        }
        dumpDiagnosticsOrWarn(&diagnostics, if (flags.show_cascade) std.math.maxInt(usize) else 1);
        if (!diagnostics.hasErrors()) {
            std.debug.print("frontend failed during semantizing or memory-safety analysis: {s}\n", .{@errorName(err)});
        }
        return error.CompilationFailed;
    };
    timings.semantizing_ns = elapsedSince(io, semantizing_start);

    // 6. Si hubo errores semánticos, parar antes de codegen ───────────────
    if (diagnostics.hasErrors()) {
        if (flags.show_token_list) printTokenList(pipeline.tokens.items);
        if (pipeline.syntax_ctx) |*syntax_ctx| {
            if (flags.show_syntax_tree) syntax_ctx.printST();
        }
        if (pipeline.sem_ctx) |*semantizer_ctx| {
            if (flags.show_semantic_graph) semantizer_ctx.printSG();
        }
        dumpDiagnosticsOrWarn(&diagnostics, if (flags.show_cascade) std.math.maxInt(usize) else 1);
        return error.CompilationFailed;
    }

    // 7. Generación de código ──────────────────────────────────────────────
    const codegen_start = nowNs(io);
    var gen = codegen.CodeGenerator.init(&allocator, io, sg, &diagnostics, options.codegen_options) catch |err| {
        std.debug.print("failed to initialize codegen: {s}\n", .{@errorName(err)});
        return err;
    };
    defer gen.deinit();
    const module = gen.generate() catch |err| {
        timings.codegen_ns = elapsedSince(io, codegen_start);
        if (flags.show_token_list) printTokenList(pipeline.tokens.items);
        if (pipeline.sem_ctx) |*semantizer_ctx| {
            if (flags.show_semantic_graph) semantizer_ctx.printSG();
        }
        dumpDiagnosticsOrWarn(&diagnostics, if (flags.show_cascade) std.math.maxInt(usize) else 1);
        if (!diagnostics.hasErrors()) {
            std.debug.print("codegen failed: {s}\n", .{@errorName(err)});
        }
        return error.CompilationFailed;
    };
    timings.codegen_ns = elapsedSince(io, codegen_start);

    if (!emit_object_only and options.codegen_options.selected_test_name == null and !hasExecutableMain(sg)) {
        printMissingMainError(module_dir, plan.module_root != null);
        return error.CompilationFailed;
    }

    // Temporales en el mismo directorio final.
    const temp_stem_base = if (emit_object_only) final_obj_path.? else final_output_path;
    const temp_stem = try std.fmt.allocPrint(
        allocator,
        "{s}.tmp.{d}",
        .{ temp_stem_base, nowNs(io) },
    );
    const temp_ir_path = if (final_ir_path != null)
        try std.fmt.allocPrint(
            allocator,
            "{s}.ll",
            .{temp_stem},
        )
    else
        null;
    const temp_obj_path = try std.fmt.allocPrint(
        allocator,
        "{s}.o",
        .{temp_stem},
    );

    try ensureParentDir(io, temp_stem);
    if (temp_ir_path) |path| try ensureParentDir(io, path);
    try ensureParentDir(io, temp_obj_path);

    if (temp_ir_path) |path| {
        std.Io.Dir.deleteFileAbsolute(io, path) catch |err| {
            if (err != error.FileNotFound) return err;
        };
    }
    std.Io.Dir.deleteFileAbsolute(io, temp_stem) catch |err| {
        if (err != error.FileNotFound) return err;
    };
    std.Io.Dir.deleteFileAbsolute(io, temp_obj_path) catch |err| {
        if (err != error.FileNotFound) return err;
    };

    // 8. Escribir el módulo LLVM a un fichero .ll ─────────────────────────
    if (temp_ir_path) |path| {
        var err_msg: [*c]u8 = null;
        const temp_ir_path_c = try allocator.dupeZ(u8, path);
        if (c.LLVMPrintModuleToFile(module, temp_ir_path_c.ptr, &err_msg) != 0) {
            std.debug.print("Failed to write LLVM module: {s}\n", .{err_msg});
            return error.WriteFailed;
        }
    }

    // 9. Emitir objeto y, si hace falta, enlazar con libc ─────────────────
    const triple_message = c.LLVMGetDefaultTargetTriple();
    defer c.LLVMDisposeMessage(triple_message);
    const triple = std.mem.span(triple_message);

    const link_start = nowNs(io);
    if (emit_object_only)
        try link.emitObjectFile(module, triple, temp_obj_path)
    else
        try link.linkWithLibc(module, triple, temp_stem, &allocator, io, environ_map);
    timings.link_ns = elapsedSince(io, link_start);

    // 10. Mover a nombres finales ─────────────────────────────────────────
    if (temp_ir_path) |src| {
        const dst = final_ir_path.?;
        if (std.Io.Dir.cwd().statFile(io, src, .{})) |_| {} else |err| switch (err) {
            error.FileNotFound => {
                std.debug.print("missing temp ir before rename: {s}\n", .{src});
                return err;
            },
            else => return err,
        }
        try replaceFile(io, src, dst);
    }

    if (!emit_object_only) {
        if (std.Io.Dir.cwd().statFile(io, temp_stem, .{})) |_| {} else |err| switch (err) {
            error.FileNotFound => {
                std.debug.print("missing temp output before rename: {s}\n", .{temp_stem});
                return err;
            },
            else => return err,
        }
        try replaceFile(io, temp_stem, final_output_path);
    }

    if (final_obj_path) |obj_dst| {
        if (std.Io.Dir.cwd().statFile(io, temp_obj_path, .{})) |_| {} else |err| switch (err) {
            error.FileNotFound => {
                std.debug.print("missing temp obj before rename: {s}\n", .{temp_obj_path});
                return err;
            },
            else => return err,
        }
        try replaceFile(io, temp_obj_path, obj_dst);
    } else {
        std.Io.Dir.deleteFileAbsolute(io, temp_obj_path) catch |err| {
            if (err != error.FileNotFound) return err;
        };
    }

    if (flags.time_phases) {
        printPhaseTimings(timings);
        printSemantizingTimings(pipeline.semantize_timings);
    }

    if (options.success_message) |message| {
        std.debug.print("{s}", .{message});
    }
}

pub fn compile(io: std.Io, environ_map: ?*const std.process.Environ.Map, args: []const []const u8) !void {
    const parsed = try parseBuildArgs(args);
    try compileTarget(parsed.target_path, parsed.flags, .{}, io, environ_map);
}

test "parse build flags keeps diagnostics toggles and output paths" {
    const flags = try parseFlags(&.{
        "--on-build-error-show-cascade",
        "--on-build-error-show-token-list",
        "--time-phases",
        "--output",
        "bin/app",
        "--emit-llvm",
        "ir/app.ll",
        "--emit-obj",
        "obj/app.o",
        "--sysroot",
        "/opt/argi",
    });

    try std.testing.expect(flags.show_cascade);
    try std.testing.expect(flags.show_token_list);
    try std.testing.expect(flags.time_phases);
    try std.testing.expectEqualStrings("bin/app", flags.output_path.?);
    try std.testing.expectEqualStrings("ir/app.ll", flags.llvm_ir_path.?);
    try std.testing.expectEqualStrings("obj/app.o", flags.object_path.?);
    try std.testing.expectEqualStrings("/opt/argi", flags.sysroot_path.?);
    try std.testing.expect(flags.just_object_path == null);
}

test "parse build flags rejects missing path value" {
    try std.testing.expectError(error.MissingFlagValue, parseFlags(&.{"--output"}));
    try std.testing.expectError(error.MissingFlagValue, parseFlags(&.{"--sysroot"}));
}

test "parse build flags rejects unknown flag" {
    try std.testing.expectError(error.UnknownFlag, parseFlags(&.{"--unknown"}));
    try std.testing.expectError(error.UnknownFlag, parseFlags(&.{
        "--sysroot",
        "/tmp/argi",
        "--unknown",
    }));
}

test "parse build flags keeps just emit obj path" {
    const flags = try parseFlags(&.{
        "--just-emit-obj",
        "obj-only/app.o",
    });

    try std.testing.expectEqualStrings("obj-only/app.o", flags.just_object_path.?);
    try std.testing.expect(flags.object_path == null);
}

test "parse build flags rejects conflicting object emission modes" {
    try std.testing.expectError(error.ConflictingObjectEmissionModes, parseFlags(&.{
        "--emit-obj",
        "obj/app.o",
        "--just-emit-obj",
        "obj-only/app.o",
    }));
}

test "local cache root resolves to dot argi cache" {
    const cache_root = try localCacheRoot(std.testing.allocator);
    defer std.testing.allocator.free(cache_root);

    try std.testing.expect(std.mem.endsWith(u8, cache_root, "/.argi-cache") or std.mem.eql(u8, cache_root, ".argi-cache"));
}
