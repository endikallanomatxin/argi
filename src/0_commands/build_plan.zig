const std = @import("std");
const link = @import("../5_codegen/link.zig");

pub const BuildFlags = struct {
    target: @import("../1_base/target.zig").Config = .{},
    show_cascade: bool = false,
    show_syntax_tree: bool = false,
    show_semantic_graph: bool = false,
    stats: bool = false,
    use_cache: bool = true,
    cc: ?[]const u8 = null,
    cc_args: []const []const u8 = &.{},
    c_sysroot: ?[]const u8 = null,
    native_inputs: []const link.NativeInput = &.{},
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
    native_inputs: []const link.NativeInput = &.{},
};

const ManifestExecutable = struct {
    name: []const u8,
    path: ?[]const u8 = null,
};

const ModuleManifest = struct {
    name: ?[]const u8 = null,
    run_default: ?[]const u8 = null,
    executables: std.array_list.Managed(ManifestExecutable),
    native_inputs: std.ArrayList(link.NativeInput) = .empty,

    fn init(allocator: std.mem.Allocator) ModuleManifest {
        return .{ .executables = std.array_list.Managed(ManifestExecutable).init(allocator) };
    }
};

pub fn parseBuildArgs(allocator: std.mem.Allocator, args: []const []const u8) !ParsedBuildArgs {
    var driver_args: std.ArrayList([]const u8) = .empty;
    errdefer driver_args.deinit(allocator);
    var inputs: std.ArrayList(link.NativeInput) = .empty;
    errdefer inputs.deinit(allocator);
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
        } else if (std.mem.eql(u8, arg, "--stats")) {
            parsed.flags.stats = true;
        } else if (std.mem.eql(u8, arg, "--no-cache")) {
            parsed.flags.use_cache = false;
        } else if (std.mem.eql(u8, arg, "--link-library") or
            std.mem.eql(u8, arg, "--link-static-library") or
            std.mem.eql(u8, arg, "--link-shared-library") or
            std.mem.eql(u8, arg, "--library-path") or
            std.mem.eql(u8, arg, "--link-file"))
        {
            idx += 1;
            if (idx >= args.len) return error.MissingFlagValue;
            const value = args[idx];
            if (value.len == 0 or value[0] == '-') return error.InvalidNativeLinkInput;
            const input: link.NativeInput = if (std.mem.eql(u8, arg, "--link-library"))
                .{ .library = value }
            else if (std.mem.eql(u8, arg, "--link-static-library"))
                .{ .static_library = value }
            else if (std.mem.eql(u8, arg, "--link-shared-library"))
                .{ .shared_library = value }
            else if (std.mem.eql(u8, arg, "--library-path"))
                .{ .search_path = value }
            else
                .{ .file = value };
            try inputs.append(allocator, input);
        } else if (std.mem.eql(u8, arg, "--cc") or std.mem.eql(u8, arg, "--cc-arg") or std.mem.eql(u8, arg, "--c-sysroot")) {
            idx += 1;
            if (idx >= args.len or args[idx].len == 0) return error.MissingFlagValue;
            if (std.mem.eql(u8, arg, "--cc")) parsed.flags.cc = args[idx] else if (std.mem.eql(u8, arg, "--c-sysroot")) parsed.flags.c_sysroot = args[idx] else try driver_args.append(allocator, args[idx]);
        } else if (std.mem.eql(u8, arg, "--target")) {
            idx += 1;
            if (idx >= args.len) return error.MissingFlagValue;
            parsed.flags.target = @import("../1_base/target.zig").Config.parse(args[idx]) catch |err| {
                std.debug.print("Error: invalid or unsupported target '{s}'; use native or Linux x86_64/aarch64 with gnu ABI.\n", .{args[idx]});
                return err;
            };
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
    parsed.flags.cc_args = try driver_args.toOwnedSlice(allocator);
    parsed.flags.native_inputs = try inputs.toOwnedSlice(allocator);
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

fn executableSuffix() []const u8 {
    return if (@import("builtin").os.tag == .windows) ".exe" else "";
}

pub fn defaultOutputPathForModuleDir(allocator: std.mem.Allocator, module_dir: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "{s}/build/output{s}", .{ module_dir, executableSuffix() });
}

fn defaultOutputPathForExecutable(allocator: std.mem.Allocator, module_root: []const u8, executable_name: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "{s}/build/debug/{s}{s}", .{ module_root, executable_name, executableSuffix() });
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

fn enclosingPackageRoot(allocator: std.mem.Allocator, io: std.Io, module_dir: []const u8) !?[]u8 {
    var current = std.fs.path.dirname(module_dir) orelse return null;
    while (true) {
        if (try hasManifest(io, allocator, current)) return try allocator.dupe(u8, current);
        current = std.fs.path.dirname(current) orelse return null;
    }
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
    return parseManifest(allocator, module_root, text) catch |err| {
        if (err == error.InvalidNativeLinkInput) {
            std.debug.print("Error: invalid native link configuration in {s}; each [[native]] entry requires one library, static_library, shared_library, search_path, or file string.\n", .{path});
            return error.CompilationFailed;
        }
        return err;
    };
}

fn parseManifest(allocator: std.mem.Allocator, module_root: []const u8, text: []const u8) !ModuleManifest {
    var manifest = ModuleManifest.init(allocator);
    var current_executable: ?*ManifestExecutable = null;
    var in_run = false;
    var in_native = false;
    var native_has_input = false;
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r\n");
        if (line.len == 0 or line[0] == '#') continue;
        if (line[0] == '[' and line[line.len - 1] == ']') {
            if (in_native and !native_has_input) return error.InvalidNativeLinkInput;
            const section = line[1 .. line.len - 1];
            in_run = std.mem.eql(u8, section, "run");
            in_native = std.mem.eql(u8, line, "[[native]]");
            native_has_input = false;
            current_executable = null;
            if (std.mem.startsWith(u8, section, "executables.")) {
                const name = section["executables.".len..];
                try manifest.executables.append(.{ .name = try allocator.dupe(u8, name) });
                current_executable = &manifest.executables.items[manifest.executables.items.len - 1];
            }
            continue;
        }
        const key = parseKey(line);
        if (in_native) {
            if (native_has_input) return error.InvalidNativeLinkInput;
            const value = parseNativeString(line) orelse return error.InvalidNativeLinkInput;
            if (value.len == 0 or value[0] == '-') return error.InvalidNativeLinkInput;
            const input: link.NativeInput = if (std.mem.eql(u8, key, "library"))
                .{ .library = try allocator.dupe(u8, value) }
            else if (std.mem.eql(u8, key, "static_library"))
                .{ .static_library = try allocator.dupe(u8, value) }
            else if (std.mem.eql(u8, key, "shared_library"))
                .{ .shared_library = try allocator.dupe(u8, value) }
            else if (std.mem.eql(u8, key, "search_path"))
                .{ .search_path = try std.fs.path.resolve(allocator, &.{ module_root, value }) }
            else if (std.mem.eql(u8, key, "file"))
                .{ .file = try std.fs.path.resolve(allocator, &.{ module_root, value }) }
            else
                return error.InvalidNativeLinkInput;
            try manifest.native_inputs.append(allocator, input);
            native_has_input = true;
            continue;
        }
        const value = parseQuotedValue(line) orelse continue;
        if (current_executable) |executable| {
            if (std.mem.eql(u8, key, "path")) executable.path = try allocator.dupe(u8, value);
        } else if (in_run) {
            if (std.mem.eql(u8, key, "default")) manifest.run_default = try allocator.dupe(u8, value);
        } else if (std.mem.eql(u8, key, "name")) {
            manifest.name = try allocator.dupe(u8, value);
        }
    }
    if (in_native and !native_has_input) return error.InvalidNativeLinkInput;
    return manifest;
}

// Native link configuration accepts single-line literal or basic strings.
// Literal strings preserve backslashes; basic strings with escapes require a
// TOML parser rather than silently passing a different filename to the linker.
fn parseNativeString(line: []const u8) ?[]const u8 {
    const equals = std.mem.indexOfScalar(u8, line, '=') orelse return null;
    const value = std.mem.trim(u8, line[equals + 1 ..], " \t\r");
    if (value.len < 2 or (value[0] != '"' and value[0] != '\'')) return null;
    const close = std.mem.indexOfScalarPos(u8, value, 1, value[0]) orelse return null;
    const rest = std.mem.trim(u8, value[close + 1 ..], " \t\r");
    if (rest.len != 0 and rest[0] != '#') return null;
    const content = value[1..close];
    if (value[0] == '"' and std.mem.indexOfScalar(u8, content, '\\') != null) return null;
    return content;
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
        \\  path = "source/app"
        \\
        \\Or create a library package with:
        \\  argi init --lib [name]
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
    native_inputs: []const link.NativeInput,
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
        .native_inputs = native_inputs,
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
            try appendExecutablePlan(allocator, io, &plans, target_path, target_dir, executable, manifest.native_inputs.items);
            return plans;
        }
        for (manifest.executables.items) |*executable|
            try appendExecutablePlan(allocator, io, &plans, target_path, target_dir, executable, manifest.native_inputs.items);
        return plans;
    }

    // An explicitly selected entry module still belongs to its package. Use
    // the declared executable's output rather than creating a second build
    // directory under source/. The nearest manifest defines this boundary;
    // unrelated modules keep the standalone-module behavior.
    if (try enclosingPackageRoot(allocator, io, target_dir)) |package_root| {
        errdefer allocator.free(package_root);
        const manifest = try readManifest(allocator, io, package_root);
        for (manifest.executables.items) |*executable| {
            if (flags.executable_name) |name|
                if (!std.mem.eql(u8, name, executable.name)) continue;
            const executable_dir = try std.fs.path.resolve(allocator, &.{ package_root, executable.path orelse executable.name });
            defer allocator.free(executable_dir);
            if (!std.mem.eql(u8, executable_dir, target_dir)) continue;
            try appendExecutablePlan(allocator, io, &plans, target_path, package_root, executable, manifest.native_inputs.items);
        }
        if (plans.items.len != 0) return plans;
        allocator.free(package_root);
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
    try appendExecutablePlan(allocator, io, &plans, ".", target_dir, executable, manifest.native_inputs.items);
    return plans.items[0];
}

test "build planning parses output and sysroot flags without compiler dependencies" {
    const parsed = try parseBuildArgs(std.testing.allocator, &.{ "--output", "bin/app", "--sysroot", "/opt/argi", "--release" });
    defer std.testing.allocator.free(parsed.flags.native_inputs);
    try std.testing.expectEqualStrings("bin/app", parsed.flags.output_path.?);
    try std.testing.expectEqualStrings("/opt/argi", parsed.flags.sysroot_path.?);
    try std.testing.expectEqual(link.OptimizationMode.release, parsed.flags.optimization_mode);
}

test "build planning validates and preserves native link input order" {
    const allocator = std.testing.allocator;
    const parsed = try parseBuildArgs(allocator, &.{ "--library-path", "native libs", "--link-file", "libfirst.a", "--link-library", "second", "--link-file", "last.o" });
    defer allocator.free(parsed.flags.native_inputs);
    const inputs = parsed.flags.native_inputs;
    try std.testing.expectEqual(@as(usize, 4), inputs.len);
    try std.testing.expectEqualStrings("native libs", inputs[0].search_path);
    try std.testing.expectEqualStrings("libfirst.a", inputs[1].file);
    try std.testing.expectEqualStrings("second", inputs[2].library);
    try std.testing.expectEqualStrings("last.o", inputs[3].file);
    try std.testing.expectError(error.MissingFlagValue, parseBuildArgs(allocator, &.{"--link-library"}));
    try std.testing.expectError(error.InvalidNativeLinkInput, parseBuildArgs(allocator, &.{ "--link-file", "-Wl,bad" }));
}

test "native manifest inputs preserve order and resolve package paths" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const root = try std.fs.path.resolve(allocator, &.{"native package"});
    const manifest = try parseManifest(allocator, root,
        \\[[native]]
        \\search_path = "native # libs" # comment
        \\[[native]]
        \\file = 'lib first.a'
        \\[[native]]
        \\library = "second"
        \\[executables.app]
        \\path = "source/app"
    );
    try std.testing.expectEqual(@as(usize, 3), manifest.native_inputs.items.len);
    try std.testing.expectEqualStrings(try std.fs.path.resolve(allocator, &.{ root, "native # libs" }), manifest.native_inputs.items[0].search_path);
    try std.testing.expectEqualStrings(try std.fs.path.resolve(allocator, &.{ root, "lib first.a" }), manifest.native_inputs.items[1].file);
    try std.testing.expectEqualStrings("second", manifest.native_inputs.items[2].library);
}

test "native manifest inputs reject missing duplicate and unknown fields" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    for ([_][]const u8{
        "[[native]]",
        "[[native]]\nlibrary = 3",
        "[[native]]\nlibrary = \"\"",
        "[[native]]\nlibrary = \"one\"\nfile = \"two.a\"",
        "[[native]]\nlibary = \"one\"",
        "[[native]]\nfile = \"-Wl,bad\"",
        "[[native]]\nfile = \"one.a\" trailing",
    }) |text| try std.testing.expectError(error.InvalidNativeLinkInput, parseManifest(arena.allocator(), ".", text));
}

test "native library modes are explicit in CLI and manifests" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const parsed = try parseBuildArgs(allocator, &.{ "--link-static-library", "one", "--link-shared-library", "two" });
    try std.testing.expectEqualStrings("one", parsed.flags.native_inputs[0].static_library);
    try std.testing.expectEqualStrings("two", parsed.flags.native_inputs[1].shared_library);
    const manifest = try parseManifest(allocator, ".", "[[native]]\nstatic_library = \"one\"\n[[native]]\nshared_library = \"two\"\n");
    try std.testing.expectEqualStrings("one", manifest.native_inputs.items[0].static_library);
    try std.testing.expectEqualStrings("two", manifest.native_inputs.items[1].shared_library);
    try std.testing.expectError(error.InvalidNativeLinkInput, parseManifest(allocator, ".", "[[native]]\nlibrary = \"one\"\nstatic_library = \"one\""));
    try std.testing.expectError(error.MissingFlagValue, parseBuildArgs(allocator, &.{"--link-shared-library"}));
}

test "build flags keep target C driver arguments separate from Argi sysroot" {
    const allocator = std.testing.allocator;
    const parsed = try parseBuildArgs(allocator, &.{ "--target", "aarch64-linux-gnu", "--cc", "clang", "--cc-arg", "--target=aarch64-linux-gnu", "--c-sysroot", "/target", "--sysroot", "/argi" });
    defer allocator.free(parsed.flags.native_inputs);
    defer allocator.free(parsed.flags.cc_args);
    try std.testing.expectEqualStrings("clang", parsed.flags.cc.?);
    try std.testing.expectEqualStrings("--target=aarch64-linux-gnu", parsed.flags.cc_args[0]);
    try std.testing.expectEqualStrings("/target", parsed.flags.c_sysroot.?);
    try std.testing.expectEqualStrings("/argi", parsed.flags.sysroot_path.?);
}
