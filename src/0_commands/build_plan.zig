const std = @import("std");
const link = @import("../5_codegen/link.zig");

pub const BuildFlags = struct {
    show_cascade: bool = false,
    show_syntax_tree: bool = false,
    show_semantic_graph: bool = false,
    show_token_list: bool = false,
    stats: bool = false,
    output_path: ?[]const u8 = null,
    llvm_ir_path: ?[]const u8 = null,
    object_path: ?[]const u8 = null,
    just_object_path: ?[]const u8 = null,
    sysroot_path: ?[]const u8 = null,
    executable_name: ?[]const u8 = null,
    optimization_mode: link.OptimizationMode = .development,
};

pub const ParsedBuildArgs = struct {
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
        return .{ .executables = std.array_list.Managed(ManifestExecutable).init(allocator) };
    }
};

pub fn parseBuildArgs(args: []const []const u8) !ParsedBuildArgs {
    var parsed: ParsedBuildArgs = .{};
    var saw_target = false;
    var idx: usize = 0;
    while (idx < args.len) : (idx += 1) {
        const arg = args[idx];
        if (std.mem.eql(u8, arg, "--on-build-error-show-cascade")) {
            parsed.flags.show_cascade = true;
        } else if (std.mem.eql(u8, arg, "--on-build-error-show-syntax-tree")) {
            parsed.flags.show_syntax_tree = true;
        } else if (std.mem.eql(u8, arg, "--on-build-error-show-semantic-graph")) {
            parsed.flags.show_semantic_graph = true;
        } else if (std.mem.eql(u8, arg, "--on-build-error-show-token-list")) {
            parsed.flags.show_token_list = true;
        } else if (std.mem.eql(u8, arg, "--stats")) {
            parsed.flags.stats = true;
        } else if (std.mem.eql(u8, arg, "--release")) {
            parsed.flags.optimization_mode = .release;
        } else if (std.mem.eql(u8, arg, "--output")) {
            idx += 1;
            if (idx >= args.len) return error.MissingFlagValue;
            parsed.flags.output_path = args[idx];
        } else if (std.mem.eql(u8, arg, "--emit-llvm")) {
            idx += 1;
            if (idx >= args.len) return error.MissingFlagValue;
            parsed.flags.llvm_ir_path = args[idx];
        } else if (std.mem.eql(u8, arg, "--emit-obj")) {
            idx += 1;
            if (idx >= args.len) return error.MissingFlagValue;
            parsed.flags.object_path = args[idx];
        } else if (std.mem.eql(u8, arg, "--just-emit-obj")) {
            idx += 1;
            if (idx >= args.len) return error.MissingFlagValue;
            parsed.flags.just_object_path = args[idx];
        } else if (std.mem.eql(u8, arg, "--sysroot")) {
            idx += 1;
            if (idx >= args.len) return error.MissingFlagValue;
            parsed.flags.sysroot_path = args[idx];
        } else if (std.mem.eql(u8, arg, "--exec") or std.mem.eql(u8, arg, "--executable")) {
            idx += 1;
            if (idx >= args.len) return error.MissingFlagValue;
            parsed.flags.executable_name = args[idx];
        } else if (std.mem.startsWith(u8, arg, "--")) {
            return error.UnknownFlag;
        } else {
            if (saw_target) return error.UnknownFlag;
            parsed.target_path = arg;
            saw_target = true;
        }
    }
    if (parsed.flags.object_path != null and parsed.flags.just_object_path != null)
        return error.ConflictingObjectEmissionModes;
    return parsed;
}

pub fn localCacheRoot(allocator: std.mem.Allocator) ![]u8 {
    return std.fs.path.resolve(allocator, &.{".argi-cache"});
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

pub fn defaultOutputPathForModuleDir(allocator: std.mem.Allocator, module_dir: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "{s}/build/output", .{module_dir});
}

fn defaultOutputPathForExecutable(allocator: std.mem.Allocator, module_root: []const u8, executable_name: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "{s}/build/debug/{s}", .{ module_root, executable_name });
}

fn manifestPath(allocator: std.mem.Allocator, module_root: []const u8) ![]u8 {
    return std.fs.path.join(allocator, &.{ module_root, "argi.toml" });
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
    if (std.mem.indexOfScalar(u8, value, '#')) |comment_idx|
        value = std.mem.trim(u8, value[0..comment_idx], " \t\r\n");
    if (value.len < 2 or value[0] != '"' or value[value.len - 1] != '"') return null;
    return value[1 .. value.len - 1];
}

fn parseKey(line: []const u8) []const u8 {
    const eq_idx = std.mem.indexOfScalar(u8, line, '=') orelse return "";
    return std.mem.trim(u8, line[0..eq_idx], " \t\r\n");
}

fn findExecutable(manifest: *ModuleManifest, name: []const u8) ?*ManifestExecutable {
    for (manifest.executables.items) |*executable|
        if (std.mem.eql(u8, executable.name, name)) return executable;
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
        if (current_executable) |executable| {
            if (std.mem.eql(u8, key, "path")) executable.path = try allocator.dupe(u8, value);
        } else if (in_run) {
            if (std.mem.eql(u8, key, "default")) manifest.run_default = try allocator.dupe(u8, value);
        } else if (std.mem.eql(u8, key, "name")) {
            manifest.name = try allocator.dupe(u8, value);
        }
    }
    return manifest;
}

fn printAvailableExecutables(executables: []const ManifestExecutable) void {
    std.debug.print("Available executables:\n", .{});
    for (executables) |executable| std.debug.print("  - {s}\n", .{executable.name});
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
    if (requested) |name| return selectExecutable(manifest, name);
    if (manifest.run_default) |name| return selectExecutable(manifest, name);
    if (manifest.executables.items.len == 1) return &manifest.executables.items[0];
    printAmbiguousRunDefaultError(manifest.executables.items);
    return error.CompilationFailed;
}

fn ensureDirExists(io: std.Io, path: []const u8) !void {
    var dir = std.Io.Dir.cwd().openDir(io, path, .{}) catch |err| switch (err) {
        error.FileNotFound => return error.FileNotFound,
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
    const relative_path = executable.path orelse executable.name;
    const executable_path = try std.fs.path.resolve(allocator, &.{ module_root, relative_path });
    ensureDirExists(io, executable_path) catch |err| switch (err) {
        error.FileNotFound => {
            std.debug.print("Error: executable '{s}' points to missing path:\n  {s}\n", .{ executable.name, relative_path });
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

pub fn resolveBuildPlans(allocator: std.mem.Allocator, io: std.Io, target_path: []const u8, flags: BuildFlags) !std.array_list.Managed(BuildPlan) {
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
        for (manifest.executables.items) |*executable|
            try appendExecutablePlan(allocator, io, &plans, target_path, target_dir, executable);
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

pub fn resolveBuildPlan(allocator: std.mem.Allocator, io: std.Io, target_path: []const u8, flags: BuildFlags) !BuildPlan {
    const plans = try resolveBuildPlans(allocator, io, target_path, flags);
    if (plans.items.len != 1) return error.AmbiguousBuildPlan;
    return plans.items[0];
}

pub fn resolveRunPlan(allocator: std.mem.Allocator, io: std.Io, requested_executable: ?[]const u8) !BuildPlan {
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

test "build planning parses output and sysroot flags without compiler dependencies" {
    const parsed = try parseBuildArgs(&.{ "--output", "bin/app", "--sysroot", "/opt/argi", "--release" });
    try std.testing.expectEqualStrings("bin/app", parsed.flags.output_path.?);
    try std.testing.expectEqualStrings("/opt/argi", parsed.flags.sysroot_path.?);
    try std.testing.expectEqual(link.OptimizationMode.release, parsed.flags.optimization_mode);
}
