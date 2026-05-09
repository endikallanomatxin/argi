const std = @import("std");

const sf = @import("../1_base/source_files.zig");
const diag = @import("../1_base/diagnostic.zig");
const frontend = @import("frontend_pipeline.zig");
const build_cmd = @import("build.zig");
const syn = @import("../3_syntax/syntax_tree.zig");

const DiscoverTest = struct {
    name: []const u8,
    location: @import("../2_tokens/token.zig").Location,
};

const ParsedArgs = struct {
    target: []const u8,
    filter: ?[]const u8 = null,
    sysroot_path: ?[]const u8 = null,
};

fn parseArgs(args: []const []const u8) !ParsedArgs {
    if (args.len == 0) return error.MissingTestTarget;

    var parsed = ParsedArgs{ .target = args[0] };
    var idx: usize = 1;
    while (idx < args.len) : (idx += 1) {
        if (std.mem.eql(u8, args[idx], "--filter")) {
            idx += 1;
            if (idx >= args.len) return error.MissingFlagValue;
            parsed.filter = args[idx];
            continue;
        }
        if (std.mem.eql(u8, args[idx], "--sysroot")) {
            idx += 1;
            if (idx >= args.len) return error.MissingFlagValue;
            parsed.sysroot_path = args[idx];
            continue;
        }
        return error.UnknownFlag;
    }
    return parsed;
}

fn discoverTests(
    io: std.Io,
    allocator: std.mem.Allocator,
    options: sf.CoreResolutionOptions,
    module_dir: []const u8,
) ![]DiscoverTest {
    const files = try sf.collectModuleWithOptions(&allocator, io, options, module_dir);
    var diagnostics = diag.Diagnostics.init(&allocator, files.items);

    var pipeline = frontend.FrontendPipeline.init(&allocator, io, &diagnostics, .{});
    defer pipeline.deinit();

    const st_nodes = try pipeline.parseFiles(files.items);

    if (diagnostics.hasErrors()) {
        try diagnostics.dumpWithLimit(std.math.maxInt(usize));
        return error.CompilationFailed;
    }

    var discovered = std.array_list.Managed(DiscoverTest).init(allocator);
    for (st_nodes) |node| {
        switch (node.content) {
            .test_declaration => |td| try discovered.append(.{
                .name = try allocator.dupe(u8, td.decl.name.string),
                .location = node.location,
            }),
            else => {},
        }
    }

    return try discovered.toOwnedSlice();
}

fn sanitizeTestName(allocator: std.mem.Allocator, name: []const u8) ![]u8 {
    var out = try allocator.alloc(u8, name.len);
    for (name, 0..) |ch, idx| {
        out[idx] = if (std.ascii.isAlphanumeric(ch) or ch == '_' or ch == '-') ch else '_';
    }
    return out;
}

fn outputPathForTest(allocator: std.mem.Allocator, module_dir: []const u8, test_name: []const u8) ![]u8 {
    var hasher = std.hash.Wyhash.init(0);
    hasher.update(module_dir);
    const module_hash = hasher.final();
    const safe_name = try sanitizeTestName(allocator, test_name);
    defer allocator.free(safe_name);
    const cache_root = try build_cmd.localCacheRoot(allocator);
    return try std.fmt.allocPrint(allocator, "{s}/tests/{x}/{s}", .{ cache_root, module_hash, safe_name });
}

fn printResultLine(status: []const u8, test_name: []const u8) void {
    std.debug.print("{s} {s}\n", .{ status, test_name });
}

fn printCapturedOutput(result: std.process.RunResult) void {
    if (result.stdout.len > 0) std.debug.print("{s}", .{result.stdout});
    if (result.stderr.len > 0) std.debug.print("{s}", .{result.stderr});
}

pub fn run(
    io: std.Io,
    environ_map: ?*const std.process.Environ.Map,
    args: []const []const u8,
) !u8 {
    const parsed = try parseArgs(args);

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const module_dir = try build_cmd.resolveBuildModuleDir(allocator, io, parsed.target);
    const core_options = sf.CoreResolutionOptions{
        .explicit_sysroot = parsed.sysroot_path,
        .environ_map = environ_map,
    };
    const core_dir = try sf.resolveToolCoreDir(&allocator, io, core_options);
    const testing_module_dir = try std.fs.path.join(allocator, &.{ core_dir, "testing" });
    const discovered = try discoverTests(io, allocator, core_options, module_dir);

    var ran_any = false;
    var had_failure = false;

    for (discovered) |test_decl| {
        if (parsed.filter) |filter| {
            if (std.mem.indexOf(u8, test_decl.name, filter) == null) continue;
        }
        ran_any = true;

        const output_path = try outputPathForTest(allocator, module_dir, test_decl.name);
        const flags = build_cmd.BuildFlags{
            .output_path = output_path,
            .sysroot_path = parsed.sysroot_path,
        };

        build_cmd.compileTarget(module_dir, flags, .{
            .frontend_options = .{
                .semantizer = .{
                    .include_tests = true,
                    .selected_test_name = test_decl.name,
                    .implicit_testing_module_dir = testing_module_dir,
                },
            },
            .codegen_options = .{
                .selected_test_name = test_decl.name,
            },
            .success_message = null,
        }, io, environ_map) catch {
            printResultLine("FAIL", test_decl.name);
            had_failure = true;
            continue;
        };

        const result = try std.process.run(allocator, io, .{
            .argv = &.{output_path},
        });

        switch (result.term) {
            .exited => |code| switch (code) {
                0 => {
                    printResultLine("PASS", test_decl.name);
                },
                77 => {
                    printResultLine("SKIP", test_decl.name);
                    printCapturedOutput(result);
                },
                else => {
                    printResultLine("FAIL", test_decl.name);
                    printCapturedOutput(result);
                    had_failure = true;
                },
            },
            else => {
                printResultLine("FAIL", test_decl.name);
                printCapturedOutput(result);
                had_failure = true;
            },
        }
    }

    if (!ran_any) {
        std.debug.print("No tests found\n", .{});
        return 1;
    }

    return if (had_failure) 1 else 0;
}

test "test output path lives under local argi cache" {
    const output_path = try outputPathForTest(std.testing.allocator, "/tmp/module", "my test");
    defer std.testing.allocator.free(output_path);

    try std.testing.expect(std.mem.indexOf(u8, output_path, "/.argi-cache/tests/") != null);
    try std.testing.expect(std.mem.endsWith(u8, output_path, "/my_test"));
}
