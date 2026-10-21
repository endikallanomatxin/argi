const std = @import("std");
const sf = @import("../1_base/source_files.zig");
const diag = @import("../1_base/diagnostic.zig");
const frontend = @import("frontend_pipeline.zig");
const codegen = @import("../5_codegen/llvm/codegen.zig");
const llvm = @import("../5_codegen/llvm/llvm.zig").c;
const ModuleCache = frontend.cache.ModuleCache;

const Result = struct {
    hits: usize,
    misses: usize,
    failure: ?anyerror,
    diagnostics: []u8,
    ir: []u8,

    fn deinit(self: Result) void {
        std.testing.allocator.free(self.diagnostics);
        std.testing.allocator.free(self.ir);
    }
};

fn compile(files: []const sf.SourceFile, session: ?*ModuleCache, options: frontend.FrontendPipeline.SemantizingOptions) !Result {
    return compileForTarget(files, session, options, .{});
}

fn compileForTarget(files: []const sf.SourceFile, session: ?*ModuleCache, options: frontend.FrontendPipeline.SemantizingOptions, target: @import("../1_base/target.zig").Config) !Result {
    return compileWithExecution(files, session, options, target, std.testing.io, 1);
}

fn compileWithExecution(files: []const sf.SourceFile, session: ?*ModuleCache, options: frontend.FrontendPipeline.SemantizingOptions, target: @import("../1_base/target.zig").Config, io: std.Io, jobs: usize) !Result {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var diagnostics = diag.Diagnostics.init(&allocator, files);
    defer diagnostics.deinit();
    var pipeline = frontend.FrontendPipeline.init(allocator, io, &diagnostics, .{
        .module_cache = session,
        .module_jobs = jobs,
        .semantizing = options,
        .target = target,
    });
    defer pipeline.deinit();
    var failure: ?anyerror = null;
    _ = pipeline.semantizeGlobalFiles(files) catch |err| blk: {
        failure = err;
        break :blk null;
    };
    var ir: []const u8 = "";
    if (failure == null) {
        var generator = try codegen.CodeGenerator.init(allocator, std.testing.io, &pipeline.global_graph.?, &diagnostics, .{});
        defer generator.deinit();
        if (generator.generate()) |module| {
            const printed = llvm.LLVMPrintModuleToString(module);
            defer llvm.LLVMDisposeMessage(printed);
            ir = try allocator.dupe(u8, std.mem.span(printed));
        } else |err| {
            failure = err;
        }
    }
    var messages: std.ArrayList(u8) = .empty;
    for (diagnostics.list.items) |item| {
        const text = try std.fmt.allocPrint(allocator, "{s}:{d}:{s}\n", .{
            diagnostics.path(item.loc), item.loc.offset, item.msg,
        });
        try messages.appendSlice(allocator, text);
    }
    return .{
        .hits = pipeline.module_cache_hits,
        .misses = pipeline.module_cache_misses,
        .failure = failure,
        .diagnostics = try std.testing.allocator.dupe(u8, messages.items),
        .ir = try std.testing.allocator.dupe(u8, ir),
    };
}

fn expectCleanEquivalent(files: []const sf.SourceFile, session: *ModuleCache) !Result {
    const cached = try compile(files, session, .{});
    errdefer cached.deinit();
    const clean = try compile(files, null, .{});
    defer clean.deinit();
    try std.testing.expectEqual(clean.failure, cached.failure);
    try std.testing.expectEqualStrings(clean.diagnostics, cached.diagnostics);
    try std.testing.expectEqualStrings(clean.ir, cached.ir);
    return cached;
}

const main_source = "dep := import(\"../dep\")\nmain() -> (.status_code: Int32) := { status_code = dep.answer().result }\n";
const dep_source = "answer() -> (.result: Int32) := { result = 7 }\n";

test "frontend module cache reuses modules after source arenas are destroyed" {
    var session = ModuleCache.init(std.testing.allocator, .{});
    defer session.deinit();
    const files = [_]sf.SourceFile{
        .{ .path = "app/main.rg", .code = main_source },
        .{ .path = "dep/answer.rg", .code = dep_source },
    };
    const cold = try expectCleanEquivalent(&files, &session);
    defer cold.deinit();
    try std.testing.expectEqual(@as(usize, 2), cold.misses);
    const warm = try expectCleanEquivalent(&files, &session);
    defer warm.deinit();
    try std.testing.expectEqual(@as(usize, 2), warm.hits);
    try std.testing.expectEqual(@as(usize, 0), warm.misses);
    try std.testing.expectEqualStrings(cold.ir, warm.ir);

    var edited = files;
    edited[1].code = "answer() -> (.result: Int32) := { result = 9 }\n";
    const rebuilt = try expectCleanEquivalent(&edited, &session);
    defer rebuilt.deinit();
    try std.testing.expectEqual(@as(usize, 1), rebuilt.hits);
    try std.testing.expectEqual(@as(usize, 1), rebuilt.misses);
    try std.testing.expect(!std.mem.eql(u8, cold.ir, rebuilt.ir));
}

test "frontend module cache regenerates imported diagnostics and remaps source IDs" {
    var session = ModuleCache.init(std.testing.allocator, .{});
    defer session.deinit();
    const files = [_]sf.SourceFile{
        .{ .path = "app/main.rg", .code = main_source },
        .{ .path = "dep/answer.rg", .code = dep_source },
    };
    const valid = try expectCleanEquivalent(&files, &session);
    valid.deinit();
    var changed = files;
    changed[1].code = "answer() -> (.result: Bool) := { result = true }\n";
    const bad = try expectCleanEquivalent(&changed, &session);
    defer bad.deinit();
    try std.testing.expect(bad.failure != null);
    try std.testing.expect(bad.diagnostics.len != 0);
    const reversed = [_]sf.SourceFile{ changed[1], changed[0] };
    const reordered = try expectCleanEquivalent(&reversed, &session);
    defer reordered.deinit();
    try std.testing.expectEqualStrings(bad.diagnostics, reordered.diagnostics);
    try std.testing.expectEqual(@as(usize, 2), reordered.hits);
    const corrected = try expectCleanEquivalent(&files, &session);
    defer corrected.deinit();
    try std.testing.expect(corrected.failure == null);
}

test "frontend module cache invalidates file sets, origins, options, and core inputs" {
    var session = ModuleCache.init(std.testing.allocator, .{});
    defer session.deinit();
    var files = [_]sf.SourceFile{
        .{ .path = "app/main.rg", .code = "main() -> (.status_code: Int32 = 0) := {}\n" },
        .{ .path = "core/config.rg", .code = "Config : Type = (.value: Int32)\n", .origin = .bundled_core },
    };
    const initial = try expectCleanEquivalent(&files, &session);
    initial.deinit();
    files[1].code = "Config : Type = (.value: Int32)\n-- changed configuration\n";
    const core_changed = try expectCleanEquivalent(&files, &session);
    defer core_changed.deinit();
    try std.testing.expectEqual(@as(usize, 2), core_changed.misses);
    const extra = [_]sf.SourceFile{ files[0], files[1], .{ .path = "app/helper.rg", .code = "helper() -> () := {}\n" } };
    const added = try expectCleanEquivalent(&extra, &session);
    defer added.deinit();
    try std.testing.expectEqual(@as(usize, 1), added.misses);
    var renamed = extra;
    renamed[2].path = "app/renamed.rg";
    const rename = try expectCleanEquivalent(&renamed, &session);
    defer rename.deinit();
    try std.testing.expectEqual(@as(usize, 1), rename.misses);
    const removed = try expectCleanEquivalent(&files, &session);
    defer removed.deinit();
    try std.testing.expectEqual(@as(usize, 1), removed.misses);
    const options = try compile(&files, &session, .{ .exhaustive_function_bodies = true });
    defer options.deinit();
    try std.testing.expectEqual(@as(usize, 2), options.misses);
    files[1].origin = .user;
    const origin = try expectCleanEquivalent(&files, &session);
    defer origin.deinit();
    try std.testing.expectEqual(@as(usize, 2), origin.misses);
}

test "frontend module cache does not store invalid syntax" {
    var session = ModuleCache.init(std.testing.allocator, .{});
    defer session.deinit();
    var files = [_]sf.SourceFile{.{ .path = "app/main.rg", .code = "broken(.input) -> () := {}\n" }};
    const bad = try expectCleanEquivalent(&files, &session);
    defer bad.deinit();
    try std.testing.expect(bad.failure != null);
    try std.testing.expectEqual(@as(usize, 0), session.entries.items.len);
    files[0].code = "main() -> (.status_code: Int32 = 0) := {}\n";
    const recovered = try expectCleanEquivalent(&files, &session);
    defer recovered.deinit();
    try std.testing.expect(recovered.failure == null);
    try std.testing.expectEqual(@as(usize, 1), recovered.misses);
}

test "frontend module cache reuses explicit qualified contract bounds without derivatives" {
    var session = ModuleCache.init(std.testing.allocator, .{});
    defer session.deinit();
    const files = [_]sf.SourceFile{
        .{ .path = "app/main.rg", .code = "dep := import(\"../dep\")\n" ++
            "use#(.Value: Type: dep.Contract)(.value: Value) -> (.result: Int32) := { result = 3 }\n" ++
            "main() -> (.status_code: Int32) := { status_code = use(.value = 1).result }\n" },
        .{ .path = "dep/contract.rg", .code = "Contract#(.Participant: Type): Contract = ()\nimplement Contract#(Int32) ()\n" },
    };
    const cold = try expectCleanEquivalent(&files, &session);
    defer cold.deinit();
    const warm = try expectCleanEquivalent(&files, &session);
    defer warm.deinit();
    try std.testing.expectEqual(@as(usize, 2), warm.hits);
    var changed = files;
    changed[1].code = "Contract#(.Participant: Type): Contract = ()\nimplement Contract#(UInt8) ()\n";
    const invalid = try expectCleanEquivalent(&changed, &session);
    defer invalid.deinit();
    try std.testing.expect(invalid.failure != null);
    try std.testing.expectEqual(@as(usize, 1), invalid.hits);
}

test "frontend module cache bounds memory and preserves leased snapshots" {
    var session = ModuleCache.init(std.testing.allocator, .{ .modules = 1 });
    defer session.deinit();
    const files = [_]sf.SourceFile{ .{ .path = "app/main.rg", .code = main_source }, .{ .path = "dep/answer.rg", .code = dep_source } };
    const first = try expectCleanEquivalent(&files, &session);
    first.deinit();
    try std.testing.expectEqual(@as(usize, 1), session.entries.items.len);
    const entry = session.entries.items[0];
    const leased = session.acquire(entry.graph.module_dir, entry.fingerprint).?;
    defer leased.release();
    const original_dir = try std.testing.allocator.dupe(u8, leased.graph.module_dir);
    defer std.testing.allocator.free(original_dir);
    const other = [_]sf.SourceFile{.{ .path = "other/main.rg", .code = "main() -> (.status_code: Int32 = 0) := {}\n" }};
    const replacement = try expectCleanEquivalent(&other, &session);
    replacement.deinit();
    try std.testing.expectEqualStrings(original_dir, leased.graph.module_dir);
    try std.testing.expect(session.retained_bytes <= session.limits.bytes);

    var disabled = ModuleCache.init(std.testing.allocator, .{ .bytes = 1 });
    defer disabled.deinit();
    const uncached = try expectCleanEquivalent(&files, &disabled);
    uncached.deinit();
    try std.testing.expectEqual(@as(usize, 0), disabled.entries.items.len);
}

test "frontend module cache reruns safety on cached ownership effects" {
    var session = ModuleCache.init(std.testing.allocator, .{});
    defer session.deinit();
    const files = [_]sf.SourceFile{
        .{ .path = "app/main.rg", .code = "Resource : Type = ()\n" ++
            "implement Deinit#(Resource) (.deinit = (.self: $&Resource) -> () {})\n" ++
            "consume(.res: Resource) -> (.result: Int32 = 0) := {}\n" ++
            "main() -> (.status_code: Int32) := {\n" ++
            "handle := Resource()\n" ++
            "status_code = consume(.res = ~handle).result\n" ++
            "status_code = consume(.res = handle).result\n}\n" },
        .{ .path = "core/lifecycle.rg", .origin = .bundled_core, .code = "Deinit#(.T: Type): Contract = (.deinit: (.self: $&T) -> () where consumes(self))\n" },
    };
    const first = try expectCleanEquivalent(&files, &session);
    defer first.deinit();
    try std.testing.expect(first.failure != null);
    try std.testing.expect(std.mem.indexOf(u8, first.diagnostics, "moved") != null);
    const again = try expectCleanEquivalent(&files, &session);
    defer again.deinit();
    try std.testing.expectEqual(files.len, again.hits);
    try std.testing.expectEqualStrings(first.diagnostics, again.diagnostics);
}

test "frontend module cache does not retain partially lowered modules" {
    var session = ModuleCache.init(std.testing.allocator, .{});
    defer session.deinit();
    const files = [_]sf.SourceFile{.{ .path = "app/main.rg", .code = "main() -> (.status_code: Int32) := { status_code = 99999999999999999999999999999 }\n" }};
    const bad = try expectCleanEquivalent(&files, &session);
    defer bad.deinit();
    try std.testing.expect(bad.failure != null);
    try std.testing.expect(bad.diagnostics.len != 0);
    try std.testing.expectEqual(@as(usize, 1), bad.misses);
    try std.testing.expectEqual(@as(usize, 0), session.entries.items.len);
}

test "frontend module cache persists canonical graphs across sessions" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try @import("../test_support.zig").tmpRootPath(&tmp);
    defer std.testing.allocator.free(root);
    const files = [_]sf.SourceFile{ .{ .path = "app/main.rg", .code = main_source }, .{ .path = "dep/answer.rg", .code = dep_source } };
    {
        var first = ModuleCache.init(std.testing.allocator, .{});
        defer first.deinit();
        try first.enablePersistence(std.testing.io, root);
        const cold = try expectCleanEquivalent(&files, &first);
        defer cold.deinit();
        try std.testing.expectEqual(@as(usize, 2), cold.misses);
        try std.testing.expectEqual(@as(usize, 0), first.disk_write_failures);
    }
    {
        var second = ModuleCache.init(std.testing.allocator, .{});
        defer second.deinit();
        try second.enablePersistence(std.testing.io, root);
        const warm = try expectCleanEquivalent(&files, &second);
        defer warm.deinit();
        try std.testing.expectEqual(@as(usize, 2), warm.hits);
        try std.testing.expectEqual(@as(usize, 2), second.disk_hits);
        try std.testing.expectEqual(@as(usize, 0), second.disk_rejections);
    }
    {
        var third = ModuleCache.init(std.testing.allocator, .{});
        defer third.deinit();
        try third.enablePersistence(std.testing.io, root);
        var edited = files;
        edited[1].code = "answer() -> (.result: Int32) := { result = 11 }\n";
        const changed = try expectCleanEquivalent(&edited, &third);
        defer changed.deinit();
        try std.testing.expectEqual(@as(usize, 1), changed.hits);
        try std.testing.expectEqual(@as(usize, 1), changed.misses);
        try std.testing.expectEqual(@as(usize, 1), third.disk_hits);
    }
}

test "frontend module cache rebuilds truncated corrupt and incompatible snapshots" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try @import("../test_support.zig").tmpRootPath(&tmp);
    defer std.testing.allocator.free(root);
    const files = [_]sf.SourceFile{.{ .path = "app/main.rg", .code = "main() -> (.status_code: Int32 = 0) := {}\n" }};
    for (0..4) |damage| {
        {
            var first = ModuleCache.init(std.testing.allocator, .{});
            defer first.deinit();
            try first.enablePersistence(std.testing.io, root);
            const valid = try expectCleanEquivalent(&files, &first);
            valid.deinit();
        }
        var dir = try tmp.dir.openDir(std.testing.io, "frontend/v1", .{ .iterate = true });
        defer dir.close(std.testing.io);
        var iterator = dir.iterate();
        const file = (try iterator.next(std.testing.io)).?;
        const data = try dir.readFileAlloc(std.testing.io, file.name, std.testing.allocator, .limited(32 * 1024 * 1024));
        defer std.testing.allocator.free(data);
        const changed = switch (damage) {
            0 => data[0 .. data.len / 2],
            1 => blk: {
                data[data.len - 1] ^= 1;
                break :blk data;
            },
            2 => blk: {
                data[8] ^= 1;
                break :blk data;
            },
            3 => blk: {
                data[12] ^= 1;
                break :blk data;
            },
            else => unreachable,
        };
        try dir.writeFile(std.testing.io, .{ .sub_path = file.name, .data = changed });
        var recovered = ModuleCache.init(std.testing.allocator, .{});
        defer recovered.deinit();
        try recovered.enablePersistence(std.testing.io, root);
        const rebuilt = try expectCleanEquivalent(&files, &recovered);
        defer rebuilt.deinit();
        try std.testing.expectEqual(@as(usize, 1), rebuilt.misses);
        try std.testing.expectEqual(@as(usize, 1), recovered.disk_rejections);
        try std.testing.expectEqual(@as(usize, 0), recovered.disk_write_failures);
    }
}

test "frontend module cache treats unwritable cache paths as optional" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "not-a-directory", .data = "" });
    const path = try @import("../test_support.zig").tmpFilePath(&tmp, "not-a-directory");
    defer std.testing.allocator.free(path);
    var session = ModuleCache.init(std.testing.allocator, .{});
    defer session.deinit();
    try session.enablePersistence(std.testing.io, path);
    const files = [_]sf.SourceFile{.{ .path = "app/main.rg", .code = "main() -> (.status_code: Int32 = 0) := {}\n" }};
    const result = try expectCleanEquivalent(&files, &session);
    defer result.deinit();
    try std.testing.expect(result.failure == null);
    try std.testing.expectEqual(@as(usize, 1), session.disk_write_failures);
}

test "frontend module cache preserves target selection and discarded source edits" {
    var session = ModuleCache.init(std.testing.allocator, .{});
    defer session.deinit();
    var files = [_]sf.SourceFile{.{ .path = "app/main.rg", .code = "#if target_arch(\"aarch64\") and target_arch(\"x86_64\") {\n" ++
        "bad := import(\"./missing\")\n" ++
        "} #else {\nmain() -> (.status_code: Int32 = 0) := {}\n}\n" }};
    const first = try expectCleanEquivalent(&files, &session);
    defer first.deinit();
    try std.testing.expect(first.failure == null);
    const reused = try expectCleanEquivalent(&files, &session);
    defer reused.deinit();
    try std.testing.expectEqual(@as(usize, 1), reused.hits);
    files[0].code = "#if target_arch(\"aarch64\") and target_arch(\"x86_64\") {\n" ++
        "bad := import(\"./another_missing\")\n" ++
        "} #else {\nmain() -> (.status_code: Int32 = 0) := {}\n}\n";
    const changed = try expectCleanEquivalent(&files, &session);
    defer changed.deinit();
    try std.testing.expect(changed.failure == null);
    try std.testing.expectEqual(@as(usize, 1), changed.misses);
}

test "frontend module cache separates platform branches by compilation target" {
    var session = ModuleCache.init(std.testing.allocator, .{});
    defer session.deinit();
    const files = [_]sf.SourceFile{.{ .path = "app/main.rg", .code = "#if target_os(\"windows\") {\n" ++
        "main() -> (.status_code: Int32 = 11) := {}\n" ++
        "} #else {\nmain() -> (.status_code: Int32 = 22) := {}\n}\n" }};
    const linux = try compileForTarget(&files, &session, .{}, .{ .arch = .x86_64, .os = .linux, .abi = .gnu });
    defer linux.deinit();
    const windows = try compileForTarget(&files, &session, .{}, .{ .arch = .x86_64, .os = .windows, .abi = .gnu });
    defer windows.deinit();
    try std.testing.expect(linux.failure == null);
    try std.testing.expect(windows.failure == null);
    try std.testing.expectEqual(@as(usize, 1), windows.misses);
    try std.testing.expect(!std.mem.eql(u8, linux.ir, windows.ir));
    const reused = try compileForTarget(&files, &session, .{}, .{ .arch = .x86_64, .os = .windows, .abi = .gnu });
    defer reused.deinit();
    try std.testing.expect(reused.failure == null);
    try std.testing.expectEqual(@as(usize, 1), reused.hits);
    try std.testing.expectEqualStrings(windows.ir, reused.ir);
}

test "frontend module cache preserves associated projections and participant tuples" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try @import("../test_support.zig").tmpRootPath(&tmp);
    defer std.testing.allocator.free(root);
    const files = [_]sf.SourceFile{.{ .path = "app/main.rg", .code =
        \\Product#(.Left: Type, .Right: Type): Contract = (
        \\    .multiply: (.left: Left, .right: Right) -> (.value: Result) where {}
        \\    .Result: Type
        \\    .Count: Int
        \\)
        \\implement Product#(Int32, Int64) (.Count: Int = 2, .Result: Type = Int32, .multiply = _multiply)
        \\_multiply(.left: Int32, .right: Int64) -> (.value: Int32) := { value = 0 }
        \\projected() -> (.value: Product#(Int32, Int64).Result) := { value = 0 }
        \\Box#(.T: Type): Type = (.value: Product#(T, Int64).Result)
        \\read_box(.box: &Box#(Int32)) -> (.value: Int32) := { value = box&.value }
        \\forward#(.A: Type, .B: Type)(.left: A, .right: B) -> (.value: Product#(A, B).Result) := { value = multiply(left, right).value }
        \\main() -> (.status_code: Int32) := {
        \\    box ::= Box#(Int32)(0)
        \\    status_code = forward#(Int32, Int64)(read_box(&box).value, 7).value
        \\}
        \\
    }};
    {
        var cold = ModuleCache.init(std.testing.allocator, .{});
        defer cold.deinit();
        try cold.enablePersistence(std.testing.io, root);
        const result = try expectCleanEquivalent(&files, &cold);
        defer result.deinit();
        try std.testing.expectEqual(@as(?anyerror, null), result.failure);
        try std.testing.expectEqual(@as(usize, 0), cold.disk_write_failures);
    }
    var warm = ModuleCache.init(std.testing.allocator, .{});
    defer warm.deinit();
    try warm.enablePersistence(std.testing.io, root);
    const result = try expectCleanEquivalent(&files, &warm);
    defer result.deinit();
    try std.testing.expectEqual(@as(?anyerror, null), result.failure);
    try std.testing.expectEqual(@as(usize, 1), result.hits);
    try std.testing.expectEqual(@as(usize, 0), result.misses);
    try std.testing.expectEqual(@as(usize, 0), warm.disk_rejections);

    var invalid = files;
    invalid[0].code = try std.mem.replaceOwned(u8, std.testing.allocator, files[0].code, ".Result: Type = Int32", ".Result: Type = Int64");
    defer std.testing.allocator.free(invalid[0].code);
    const rejected = try expectCleanEquivalent(&invalid, &warm);
    defer rejected.deinit();
    try std.testing.expect(rejected.failure != null);
    try std.testing.expect(std.mem.indexOf(u8, rejected.diagnostics, "incompatible associated result") != null);
}

test "frontend module cache preserves associated constant dimensions" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try @import("../test_support.zig").tmpRootPath(&tmp);
    defer std.testing.allocator.free(root);
    const files = [_]sf.SourceFile{
        .{ .path = "app/main.rg", .code =
        \\Shape#(.Input: Type): Contract = (
        \\    .Count: Int
        \\)
        \\Cell: Type = ()
        \\Buffer#(.n: Int): Type = (.values: Array#(.n = n, .t: Int32))
        \\implement Shape#(Cell) (.Count: Int = 2)
        \\Box#(.T: Type): Type = (.values: Array#(.n = Shape#(T).Count, .t: Int32))
        \\read(.values: &Array#(.n = Shape#(Cell).Count, .t: Int32)) -> (.value: Int32) := { value = values&[0] + values&[1] }
        \\take#(.n: Int)(.values: &Array#(.n = n, .t: Int32)) -> (.value: Int32) := { value = values&[0] + values&[1] }
        \\forward#(.T: Type)(.tag: T, .values: &Array#(.n = Shape#(T).Count, .t: Int32)) -> (.value: Int32) := { value = take#(.n = Shape#(T).Count)(values).value }
        \\main() -> (.status_code: Int32) := {
        \\    buffer ::= Buffer#(.n = Shape#(Cell).Count)((20, 22))
        \\    box ::= Box#(Cell)(buffer.values)
        \\    status_code = forward(Cell(), &box.values).value + take#(.n = Shape#(Cell).Count)(&box.values).value - 84
        \\}
        \\
        },
        .{ .path = "arithmetic_core/scalar_arithmetic.rg", .origin = .bundled_core, .code = @import("../test_support.zig").arithmetic_core_source },
    };
    {
        var cold = ModuleCache.init(std.testing.allocator, .{});
        defer cold.deinit();
        try cold.enablePersistence(std.testing.io, root);
        const result = try expectCleanEquivalent(&files, &cold);
        defer result.deinit();
        try std.testing.expectEqual(@as(?anyerror, null), result.failure);
        try std.testing.expectEqual(@as(usize, 0), cold.disk_write_failures);
    }
    var warm = ModuleCache.init(std.testing.allocator, .{});
    defer warm.deinit();
    try warm.enablePersistence(std.testing.io, root);
    const result = try expectCleanEquivalent(&files, &warm);
    defer result.deinit();
    try std.testing.expectEqual(@as(?anyerror, null), result.failure);
    try std.testing.expectEqual(@as(usize, 2), result.hits);
    try std.testing.expectEqual(@as(usize, 0), result.misses);
    try std.testing.expectEqual(@as(usize, 0), warm.disk_rejections);
    var invalid = files;
    invalid[0].code = try std.mem.replaceOwned(u8, std.testing.allocator, files[0].code, ".Count: Int = 2", ".Count: Int = -1");
    defer std.testing.allocator.free(invalid[0].code);
    const rejected = try expectCleanEquivalent(&invalid, &warm);
    defer rejected.deinit();
    try std.testing.expect(rejected.failure != null);
    try std.testing.expect(std.mem.indexOf(u8, rejected.diagnostics, "array length must be non-negative") != null);
}

test "frontend module cache preserves explicit unary contract participants" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try @import("../test_support.zig").tmpRootPath(&tmp);
    defer std.testing.allocator.free(root);
    const files = [_]sf.SourceFile{
        .{ .path = "app/main.rg", .code =
        \\Readable#(.Participant: Type): Contract = (
        \\    .Other: Type
        \\
        \\    .read: (.other: &Other, .source: &Participant) -> (.value: &Int32)
        \\        where depends_on(value, source)
        \\)
        \\Cell: Type = (.value: Int32)
        \\implement Readable#(Cell) (.Other: Type = Cell, .read = _read)
        \\_read(.other: &Cell, .source: &Cell) -> (.value: &Int32) := { value = &source&.value }
        \\consume#(.T: Type: Readable#(.Other: Cell))(.other: &Cell, .source: &T) -> (.value: &Int32) := { value = read(other, source).value }
        \\main() -> (.status_code: Int32 = 0) := {
        \\    other ::= Cell(7)
        \\    source ::= Cell(42)
        \\    if consume(&other, &source)& != 42 { abort }
        \\    handle ::= to_virtual#(.contract: Readable#(.Other: Cell))(.value = &source)
        \\    if read(&other, &handle)& != 42 { abort }
        \\}
        \\
        },
        .{ .path = "arithmetic_core/scalar_arithmetic.rg", .origin = .bundled_core, .code = @import("../test_support.zig").arithmetic_core_source },
    };
    {
        var cold = ModuleCache.init(std.testing.allocator, .{});
        defer cold.deinit();
        try cold.enablePersistence(std.testing.io, root);
        const result = try expectCleanEquivalent(&files, &cold);
        defer result.deinit();
        try std.testing.expectEqual(@as(?anyerror, null), result.failure);
        try std.testing.expectEqual(@as(usize, 0), cold.disk_write_failures);
    }
    var warm = ModuleCache.init(std.testing.allocator, .{});
    defer warm.deinit();
    try warm.enablePersistence(std.testing.io, root);
    const result = try expectCleanEquivalent(&files, &warm);
    defer result.deinit();
    try std.testing.expectEqual(@as(?anyerror, null), result.failure);
    try std.testing.expectEqual(@as(usize, 2), result.hits);
    try std.testing.expectEqual(@as(usize, 0), result.misses);
    try std.testing.expectEqual(@as(usize, 0), warm.disk_rejections);

    var invalid = files;
    invalid[0].code = try std.mem.replaceOwned(u8, std.testing.allocator, files[0].code, "value = &source&.value", "value = &other&.value");
    defer std.testing.allocator.free(invalid[0].code);
    const rejected = try expectCleanEquivalent(&invalid, &warm);
    defer rejected.deinit();
    try std.testing.expect(rejected.failure != null);
    try std.testing.expect(std.mem.indexOf(u8, rejected.diagnostics, "safety contract") != null);
}

test "frontend module cache preserves shared unary conformance selection" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try @import("../test_support.zig").tmpRootPath(&tmp);
    defer std.testing.allocator.free(root);
    const source = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "tests/feature_tests/contracts/107_shared_unary_selection/main.rg", std.testing.allocator, .limited(64 * 1024));
    defer std.testing.allocator.free(source);
    const files = [_]sf.SourceFile{ .{ .path = "app/main.rg", .code = source }, .{ .path = "arithmetic_core/scalar_arithmetic.rg", .origin = .bundled_core, .code = @import("../test_support.zig").arithmetic_core_source } };
    {
        var cold = ModuleCache.init(std.testing.allocator, .{});
        defer cold.deinit();
        try cold.enablePersistence(std.testing.io, root);
        const result = try expectCleanEquivalent(&files, &cold);
        defer result.deinit();
        try std.testing.expectEqual(@as(?anyerror, null), result.failure);
        try std.testing.expectEqual(@as(usize, 0), cold.disk_write_failures);
    }
    var warm = ModuleCache.init(std.testing.allocator, .{});
    defer warm.deinit();
    try warm.enablePersistence(std.testing.io, root);
    const result = try expectCleanEquivalent(&files, &warm);
    defer result.deinit();
    try std.testing.expectEqual(@as(?anyerror, null), result.failure);
    try std.testing.expectEqual(@as(usize, 2), result.hits);
    try std.testing.expectEqual(@as(usize, 0), result.misses);
    try std.testing.expectEqual(@as(usize, 0), warm.disk_rejections);
    var invalid = files;
    invalid[0].code = try std.mem.replaceOwned(u8, std.testing.allocator, source, ".n = 2, .T: Cell#(Int32)", ".n = 3, .T: Cell#(Int32)");
    defer std.testing.allocator.free(invalid[0].code);
    const rejected = try expectCleanEquivalent(&invalid, &warm);
    defer rejected.deinit();
    try std.testing.expect(rejected.failure != null);
    try std.testing.expect(std.mem.indexOf(u8, rejected.diagnostics, "constraint") != null);
}

test "frontend module cache preserves generated compile-time entry provenance" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try @import("../test_support.zig").tmpRootPath(&tmp);
    defer std.testing.allocator.free(root);
    const source = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "tests/feature_tests/execution/152_anonymous_comptime_entry/main.rg", std.testing.allocator, .limited(64 * 1024));
    defer std.testing.allocator.free(source);
    const files = [_]sf.SourceFile{
        .{ .path = "app/main.rg", .code = source },
        .{ .path = "arithmetic_core/scalar_arithmetic.rg", .origin = .bundled_core, .code = @import("../test_support.zig").arithmetic_core_source },
    };
    {
        var cold = ModuleCache.init(std.testing.allocator, .{});
        defer cold.deinit();
        try cold.enablePersistence(std.testing.io, root);
        const result = try expectCleanEquivalent(&files, &cold);
        defer result.deinit();
        try std.testing.expectEqual(@as(?anyerror, null), result.failure);
        try std.testing.expectEqual(@as(usize, 0), cold.disk_write_failures);
    }
    var warm = ModuleCache.init(std.testing.allocator, .{});
    defer warm.deinit();
    try warm.enablePersistence(std.testing.io, root);
    const result = try expectCleanEquivalent(&files, &warm);
    defer result.deinit();
    try std.testing.expectEqual(@as(?anyerror, null), result.failure);
    try std.testing.expectEqual(@as(usize, 2), result.hits);
    try std.testing.expectEqual(@as(usize, 0), result.misses);
    try std.testing.expectEqual(@as(usize, 0), warm.disk_rejections);
    const changed = try std.mem.replaceOwned(u8, std.testing.allocator, source, "local ::= 42", "local ::= missing()");
    defer std.testing.allocator.free(changed);
    try std.testing.expect(!std.mem.eql(u8, source, changed));
    var invalid = files;
    invalid[0].code = changed;
    const rejected = try expectCleanEquivalent(&invalid, &warm);
    defer rejected.deinit();
    try std.testing.expect(rejected.failure != null);
    const restored = try expectCleanEquivalent(&files, &warm);
    defer restored.deinit();
    try std.testing.expectEqual(@as(?anyerror, null), restored.failure);
}

test "frontend module cache preserves scoped implementation bodies" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try @import("../test_support.zig").tmpRootPath(&tmp);
    defer std.testing.allocator.free(root);
    const raw_source = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "tests/feature_tests/contracts/115_inline_operation_bodies/main.rg", std.testing.allocator, .limited(64 * 1024));
    defer std.testing.allocator.free(raw_source);
    // Keep the multiline edit identical for LF and CRLF checkouts.
    const source = try std.mem.replaceOwned(u8, std.testing.allocator, raw_source, "\r\n", "\n");
    defer std.testing.allocator.free(source);
    const files = [_]sf.SourceFile{
        .{ .path = "app/main.rg", .code = source },
        .{ .path = "arithmetic_core/scalar_arithmetic.rg", .origin = .bundled_core, .code = @import("../test_support.zig").arithmetic_core_source },
    };
    {
        var cold = ModuleCache.init(std.testing.allocator, .{});
        defer cold.deinit();
        try cold.enablePersistence(std.testing.io, root);
        const result = try expectCleanEquivalent(&files, &cold);
        defer result.deinit();
        try std.testing.expectEqual(@as(?anyerror, null), result.failure);
        try std.testing.expectEqual(@as(usize, 0), cold.disk_write_failures);
    }
    var warm = ModuleCache.init(std.testing.allocator, .{});
    defer warm.deinit();
    try warm.enablePersistence(std.testing.io, root);
    const result = try expectCleanEquivalent(&files, &warm);
    defer result.deinit();
    try std.testing.expectEqual(@as(?anyerror, null), result.failure);
    try std.testing.expectEqual(@as(usize, 2), result.hits);
    try std.testing.expectEqual(@as(usize, 0), result.misses);
    try std.testing.expectEqual(@as(usize, 0), warm.disk_rejections);
    var invalid = files;
    const changed = try std.mem.replaceOwned(u8, std.testing.allocator, source, ".multiply =\n        (.left: &Row, .right: &Column) -> (.result: Result) {\n        result = left&.value * right&.value * Scale\n    }", ".multiply = wrong_result");
    defer std.testing.allocator.free(changed);
    try std.testing.expect(!std.mem.eql(u8, source, changed));
    invalid[0].code = try std.fmt.allocPrint(std.testing.allocator, "{s}\nwrong_result := (.left: &Row, .right: &Column) -> (.result: UInt8) {{ result = 1 }}\n", .{changed});
    defer std.testing.allocator.free(invalid[0].code);
    const rejected = try expectCleanEquivalent(&invalid, &warm);
    defer rejected.deinit();
    try std.testing.expect(rejected.failure != null);
    try std.testing.expect(std.mem.indexOf(u8, rejected.diagnostics, "incompatible associated result") != null);
}

test "parallel module semantics preserves IR across cache lifetimes and edits" {
    var threaded = std.Io.Threaded.init(std.heap.page_allocator, .{ .async_limit = .limited(3) });
    defer threaded.deinit();
    const io = threaded.io();
    var session = ModuleCache.init(std.testing.allocator, .{});
    defer session.deinit();
    const files = [_]sf.SourceFile{
        .{ .path = "app/main.rg", .code = main_source },
        .{ .path = "dep/answer.rg", .code = dep_source },
        .{ .path = "other/extra.rg", .code = "extra() -> (.result: Int32) := { result = 11 }" },
    };
    const serial = try compileWithExecution(&files, null, .{}, .{}, io, 1);
    defer serial.deinit();
    const cold = try compileWithExecution(&files, &session, .{}, .{}, io, 4);
    defer cold.deinit();
    try std.testing.expectEqual(null, cold.failure);
    try std.testing.expectEqualStrings(serial.ir, cold.ir);
    try std.testing.expectEqualStrings(serial.diagnostics, cold.diagnostics);
    try std.testing.expectEqual(@as(usize, 3), cold.misses);
    const warm = try compileWithExecution(&files, &session, .{}, .{}, io, 4);
    defer warm.deinit();
    try std.testing.expectEqual(@as(usize, 3), warm.hits);
    try std.testing.expectEqualStrings(serial.ir, warm.ir);
    var edited = files;
    edited[1].code = "answer() -> (.result: Int32) := { result = 9 }";
    const changed = try compileWithExecution(&edited, &session, .{}, .{}, io, 4);
    defer changed.deinit();
    const changed_serial = try compileWithExecution(&edited, null, .{}, .{}, io, 1);
    defer changed_serial.deinit();
    try std.testing.expectEqual(@as(usize, 2), changed.hits);
    try std.testing.expectEqual(@as(usize, 1), changed.misses);
    try std.testing.expectEqual(null, changed.failure);
    try std.testing.expectEqualStrings(changed_serial.ir, changed.ir);
}

test "parallel module semantics retains deterministic local failure diagnostics" {
    var threaded = std.Io.Threaded.init(std.heap.page_allocator, .{ .async_limit = .limited(3) });
    defer threaded.deinit();
    const io = threaded.io();
    const files = [_]sf.SourceFile{
        .{ .path = "app/main.rg", .code = "main() -> () := {}" },
        .{ .path = "first/bad.rg", .code = "same() -> () := {}\nsame() -> () := {}" },
        .{ .path = "second/bad.rg", .code = "duplicate() -> () := {}\nduplicate() -> () := {}" },
    };
    const serial = try compileWithExecution(&files, null, .{}, .{}, io, 1);
    defer serial.deinit();
    try std.testing.expect(serial.failure != null);
    try std.testing.expect(serial.diagnostics.len != 0);
    var session = ModuleCache.init(std.testing.allocator, .{});
    defer session.deinit();
    for (0..3) |_| {
        const parallel = try compileWithExecution(&files, &session, .{}, .{}, io, 4);
        defer parallel.deinit();
        try std.testing.expectEqual(serial.failure, parallel.failure);
        try std.testing.expectEqualStrings(serial.diagnostics, parallel.diagnostics);
        try std.testing.expectEqual(@as(usize, 0), session.entries.items.len);
    }
}

test "parallel module semantics permits inline execution when async is unavailable" {
    var threaded = std.Io.Threaded.init(std.heap.page_allocator, .{ .async_limit = .nothing });
    defer threaded.deinit();
    const files = [_]sf.SourceFile{
        .{ .path = "app/main.rg", .code = main_source },
        .{ .path = "dep/answer.rg", .code = dep_source },
    };
    const parallel = try compileWithExecution(&files, null, .{}, .{}, threaded.io(), 4);
    defer parallel.deinit();
    const serial = try compile(files[0..], null, .{});
    defer serial.deinit();
    try std.testing.expectEqual(null, parallel.failure);
    try std.testing.expectEqualStrings(serial.ir, parallel.ir);
}

test "module frontend initializes interactive execution without a program entry" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const files = [_]sf.SourceFile{.{
        .path = "/interactive_core/main.rg",
        .code = "answer := () -> (.result: Int32) { result = 42 }\n",
        .origin = .bundled_core,
    }};
    var diagnostics = diag.Diagnostics.init(&allocator, &files);
    defer diagnostics.deinit();
    var pipeline = frontend.FrontendPipeline.init(allocator, std.testing.io, &diagnostics, .{});
    defer pipeline.deinit();
    const prepared = try pipeline.prepareSessionFiles(&files);
    try std.testing.expectEqual(@as(usize, 1), prepared.modules.len);
    try std.testing.expect(pipeline.global_graph == null);
    var session: @import("../execution/interactive.zig").Interactive = undefined;
    try session.initPrepared(allocator, diagnostics.source_files, prepared, .{});
    defer session.deinit();
    try session.submitStatements("value ::= answer()");
    const binding = session.compiler.semantic.resolvers.expressions.session_bindings.items[0];
    const stored = try session.runtime.context.storage.slots(session.runtime.context.bindings.get(binding).?);
    try std.testing.expectEqual(@as(i128, 42), (try stored.get(0)).integer);
    try session.close();
}

fn retainFrontendSelections(allocator: std.mem.Allocator) !void {
    const source = "choose := () -> (.ok: Bool) { ok = true }\n#if choose() { selected := import(\"./later\") } #else { discarded := import(\"./missing\") }";
    const files = [_]sf.SourceFile{.{ .path = "/project/main.rg", .code = source }};
    var diagnostic_arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer diagnostic_arena.deinit();
    const diagnostic_allocator = diagnostic_arena.allocator();
    var diagnostics = diag.Diagnostics.init(&diagnostic_allocator, &files);
    defer diagnostics.deinit();
    var pipeline = frontend.FrontendPipeline.init(allocator, std.testing.io, &diagnostics, .{});
    defer pipeline.deinit();
    _ = try pipeline.parseFiles(&files);
    try std.testing.expectEqual(@as(usize, 1), pipeline.source_selections.items.len);
    var selected = &pipeline.source_selections.items[0];
    const pending = try selected.imports(allocator);
    defer pending.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), pending.pending.len);
    try selected.resolve(pending.pending[0], true);
    const rendered = try selected.imports(allocator);
    defer rendered.deinit(allocator);
    try std.testing.expect(std.mem.indexOf(u8, rendered.source, "./later") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered.source, "./missing") == null);
    try std.testing.expectEqualStrings(source, pipeline.source_db.get(pipeline.source_db.fileId(0)).source);
    // Retokenizing starts a fresh decision owner instead of reusing a previous
    // compilation's choice for unchanged source offsets.
    _ = try pipeline.parseFiles(&files);
    try std.testing.expectEqual(@as(usize, 1), pipeline.source_selections.items.len);
    try std.testing.expect(pipeline.source_selections.items[0].decisions[0] == null);
}

test "frontend retains source selection plans and releases failed preparation" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, retainFrontendSelections, .{});
}

test "frontend evaluates module conditions before selecting main and program entry" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source = "noop_error_tracer :: () = ()\nchoose := () -> (.ok: Bool) { ok = true }\n#if choose() { main := () -> (.status_code: Int32) { status_code = 42 } } #else { main := () -> () { missing()!!! } }";
    const files = [_]sf.SourceFile{.{ .path = "/project/main.rg", .code = source }};
    var diagnostics = diag.Diagnostics.init(&a, &files);
    defer diagnostics.deinit();
    var pipeline = frontend.FrontendPipeline.init(a, std.testing.io, &diagnostics, .{ .entry_module_dir = "/project" });
    defer pipeline.deinit();
    const graph = pipeline.semantizeGlobalFiles(&files) catch |err| {
        try diagnostics.dump();
        return err;
    };
    try std.testing.expectEqual(@as(usize, 1), (try @constCast(graph).functionsNamed(a, "main")).len);
    try std.testing.expectEqual(@as(usize, 1), (try @constCast(graph).functionsNamed(a, "__argi_entry")).len);
}

test "frontend module condition cache reuse preserves selected declarations" {
    const files = [_]sf.SourceFile{.{
        .path = "/project/main.rg",
        .code = "choose := () -> (.ok: Bool) { ok = true }\n#if choose() { main := () -> (.status_code: Int32) { status_code = 42 } } #else { main := () -> () { missing() } }",
    }};
    var cache = ModuleCache.init(std.testing.allocator, .{});
    defer cache.deinit();
    const first = try expectCleanEquivalent(&files, &cache);
    defer first.deinit();
    const second = try expectCleanEquivalent(&files, &cache);
    defer second.deinit();
    try std.testing.expectEqual(@as(usize, 1), second.hits);
}

fn stagedFrontendAllocationFailures(allocator: std.mem.Allocator) !void {
    const source = "#if true { main := () -> (.status_code: Int32) { status_code = 42 } }";
    const files = [_]sf.SourceFile{.{ .path = "/project/main.rg", .code = source }};
    var diagnostic_arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer diagnostic_arena.deinit();
    const diagnostic_allocator = diagnostic_arena.allocator();
    var diagnostics = diag.Diagnostics.init(&diagnostic_allocator, &files);
    defer diagnostics.deinit();
    // Frontend safety facts share the invocation arena, as in CLI compilation.
    // Inject failure into arena growth and verify the whole invocation releases.
    var invocation = std.heap.ArenaAllocator.init(allocator);
    defer invocation.deinit();
    var pipeline = frontend.FrontendPipeline.init(invocation.allocator(), std.testing.io, &diagnostics, .{});
    defer pipeline.deinit();
    _ = try pipeline.semantizeGlobalFiles(&files);
}

test "staged frontend releases failed module condition preparation" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, stagedFrontendAllocationFailures, .{});
}

test "computed test discovery excludes main and dormant test bodies" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source = "choose := () -> (.ok: Bool) { ok = true }\nmain := () -> () { missing_main() }\n#if choose() { test selected() -> () := { missing_test() } } #else { test discarded() -> () := {} }";
    const files = [_]sf.SourceFile{.{ .path = "/project/main.rg", .code = source }};
    var diagnostics = diag.Diagnostics.init(&a, &files);
    defer diagnostics.deinit();
    var pipeline = frontend.FrontendPipeline.init(a, std.testing.io, &diagnostics, .{ .semantizing = .{ .root_selection = .requests_only, .exhaustive_function_bodies = true } });
    defer pipeline.deinit();
    try pipeline.prepareTestDiscovery(&files);
    var count: usize = 0;
    for (pipeline.syntax_files.items) |*file| for (file.roots) |root| {
        const declaration = file.testDeclaration(root) orelse continue;
        try std.testing.expectEqualStrings("selected", file.tokenText(&diagnostics.source_db, declaration.function.name_token));
        count += 1;
    };
    try std.testing.expectEqual(@as(usize, 1), count);
    try std.testing.expect(!diagnostics.hasErrors());
}

test "prepared interactive modules retain selected namespaces across commands and reset" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source = "choose := () -> (.ok: Bool) { ok = true }\nmain := () -> () { unused_main() }\n#if choose() { answer := () -> (.result: Int32) { result = 42 } } #else { missing := import(\"./missing\") }";
    const files = [_]sf.SourceFile{.{ .path = "/project/main.rg", .code = source, .origin = .bundled_core }};
    var diagnostics = diag.Diagnostics.init(&a, &files);
    defer diagnostics.deinit();
    var pipeline = frontend.FrontendPipeline.init(a, std.testing.io, &diagnostics, .{});
    defer pipeline.deinit();
    const prepared = try pipeline.prepareSessionFiles(&files);
    const node_count = prepared.relocation.graph.nodes.items.len;
    var session: @import("../execution/interactive.zig").Interactive = undefined;
    try session.initPrepared(std.testing.allocator, diagnostics.source_files, prepared, .{});
    defer session.deinit();
    try session.submitStatements("value ::= answer()");
    try std.testing.expectEqual(@as(i128, 42), (try session.submitInput("value")).?.value.runtime.integer);
    const revision = session.compiler.revision;
    try std.testing.expectError(error.Reported, session.submitStatements("bad ::= missing()"));
    try std.testing.expectEqual(revision, session.compiler.revision);
    try session.reset();
    try std.testing.expectEqual(@as(i128, 42), (try session.submitInput("answer()")).?.value.runtime.integer);
    try std.testing.expectEqual(node_count, prepared.relocation.graph.nodes.items.len);
    try session.close();
}

fn preparedSessionAllocationFailures(allocator: std.mem.Allocator) !void {
    const files = [_]sf.SourceFile{.{
        .path = "/project/main.rg",
        .code = "choose := () -> (.ok: Bool) { ok = true }\n#if choose() { answer := () -> (.value: Int32) { value = 42 } }",
    }};
    var diagnostic_arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer diagnostic_arena.deinit();
    const diagnostic_allocator = diagnostic_arena.allocator();
    var diagnostics = diag.Diagnostics.init(&diagnostic_allocator, &files);
    defer diagnostics.deinit();
    var invocation = std.heap.ArenaAllocator.init(allocator);
    defer invocation.deinit();
    var pipeline = frontend.FrontendPipeline.init(invocation.allocator(), std.testing.io, &diagnostics, .{});
    defer pipeline.deinit();
    _ = try pipeline.prepareSessionFiles(&files);
}

test "prepared interactive modules release failed template construction" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, preparedSessionAllocationFailures, .{});
}
