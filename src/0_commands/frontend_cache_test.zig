const std = @import("std");
const sf = @import("../1_base/source_files.zig");
const diag = @import("../1_base/diagnostic.zig");
const frontend = @import("frontend_pipeline.zig");
const codegen = @import("../5_codegen/codegen.zig");
const llvm = @import("../5_codegen/llvm.zig").c;
const ModuleCache = frontend.cache.ModuleCache;

const Result = struct {
    hits: usize,
    misses: usize,
    derivatives: usize,
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
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var diagnostics = diag.Diagnostics.init(&allocator, files);
    defer diagnostics.deinit();
    var pipeline = frontend.FrontendPipeline.init(allocator, std.testing.io, &diagnostics, .{
        .module_cache = session,
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
        .derivatives = pipeline.linked_module_count,
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

test "frontend module cache retains qualified abstract derivatives as transient work" {
    var session = ModuleCache.init(std.testing.allocator, .{});
    defer session.deinit();
    const files = [_]sf.SourceFile{
        .{ .path = "app/main.rg", .code = "dep := import(\"../dep\")\n" ++
            "use(.value: dep.Contract) -> (.result: Int32) := { result = 3 }\n" ++
            "main() -> (.status_code: Int32) := { status_code = use(.value = 1).result }\n" },
        .{ .path = "dep/contract.rg", .code = "Contract : Abstract = ()\nInt32 implements Contract\n" },
    };
    const cold = try expectCleanEquivalent(&files, &session);
    defer cold.deinit();
    const warm = try expectCleanEquivalent(&files, &session);
    defer warm.deinit();
    try std.testing.expectEqual(@as(usize, 2), warm.hits);
    try std.testing.expectEqual(@as(usize, 1), warm.derivatives);
    var changed = files;
    changed[1].code = "Contract : Abstract = ()\nChar implements Contract\n";
    const invalid = try expectCleanEquivalent(&changed, &session);
    defer invalid.deinit();
    try std.testing.expect(invalid.failure != null);
    try std.testing.expectEqual(@as(usize, 1), invalid.hits);
    try std.testing.expectEqual(@as(usize, 1), invalid.derivatives);
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
    const files = [_]sf.SourceFile{.{ .path = "app/main.rg", .code = "Resource : Type = ()\n" ++
        "Resource init() -> (.result: Resource) := { result = () }\n" ++
        "Resource deinit(.res: $&Resource) -> () := {}\n" ++
        "consume(.res: Resource) -> (.result: Int32 = 0) := {}\n" ++
        "main() -> (.status_code: Int32) := {\n" ++
        "handle := Resource()\n" ++
        "status_code = consume(.res = ~handle).result\n" ++
        "status_code = consume(.res = handle).result\n}\n" }};
    const first = try expectCleanEquivalent(&files, &session);
    defer first.deinit();
    try std.testing.expect(first.failure != null);
    try std.testing.expect(std.mem.indexOf(u8, first.diagnostics, "moved") != null);
    const again = try expectCleanEquivalent(&files, &session);
    defer again.deinit();
    try std.testing.expectEqual(@as(usize, 1), again.hits);
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
        \\    multiply(.left: Left, .right: Right) -> (.value: Result) where {}
        \\    .Result: Type
        \\    .Count: Int
        \\)
        \\satisfies Product#(Int32, Int64) = (.Count = 2, .Result: Int32)
        \\multiply(.left: Int32, .right: Int64) -> (.value: Int32) := { value = 0 }
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
    invalid[0].code = try std.mem.replaceOwned(u8, std.testing.allocator, files[0].code, ".Result: Int32)", ".Result: Int64)");
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
    const files = [_]sf.SourceFile{.{ .path = "app/main.rg", .code =
        \\Shape#(.Input: Type): Contract = (
        \\    .Count: Int
        \\)
        \\Cell: Type = ()
        \\Buffer#(.n: Int): Type = (.values: Array#(.n = n, .t: Int32))
        \\satisfies Shape#(Cell) = (.Count = 2)
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
    invalid[0].code = try std.mem.replaceOwned(u8, std.testing.allocator, files[0].code, ".Count = 2", ".Count = -1");
    defer std.testing.allocator.free(invalid[0].code);
    const rejected = try expectCleanEquivalent(&invalid, &warm);
    defer rejected.deinit();
    try std.testing.expect(rejected.failure != null);
    try std.testing.expect(std.mem.indexOf(u8, rejected.diagnostics, "array length must be non-negative") != null);
}

test "frontend module cache preserves unary contract participant normalization" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try @import("../test_support.zig").tmpRootPath(&tmp);
    defer std.testing.allocator.free(root);
    const files = [_]sf.SourceFile{.{ .path = "app/main.rg", .code =
        \\Readable: Contract = (
        \\    .Other: Type
        \\
        \\    read(.other: &Other, .source: &Self) -> (.value: &Int32)
        \\        where depends_on(value, source)
        \\)
        \\Cell: Type = (.value: Int32)
        \\Cell satisfies Readable#(.Other: Cell)
        \\read(.other: &Cell, .source: &Cell) -> (.value: &Int32) := { value = &source&.value }
        \\consume#(.T: Type: Readable#(.Other: Cell))(.other: &Cell, .source: &T) -> (.value: &Int32) := { value = read(other, source).value }
        \\main() -> (.status_code: Int32 = 0) := {
        \\    other ::= Cell(7)
        \\    source ::= Cell(42)
        \\    if consume(&other, &source)& != 42 { abort }
        \\    handle ::= to_virtual#(.contract: Readable#(.Other: Cell))(.value = &source)
        \\    if read(&other, &handle)& != 42 { abort }
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
    const files = [_]sf.SourceFile{.{ .path = "app/main.rg", .code = source }};
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
    invalid[0].code = try std.mem.replaceOwned(u8, std.testing.allocator, source, ".n = 2, .T: Cell#(Int32)", ".n = 3, .T: Cell#(Int32)");
    defer std.testing.allocator.free(invalid[0].code);
    const rejected = try expectCleanEquivalent(&invalid, &warm);
    defer rejected.deinit();
    try std.testing.expect(rejected.failure != null);
    try std.testing.expect(std.mem.indexOf(u8, rejected.diagnostics, "constraint") != null);
}

test "frontend module cache preserves scoped implementation bodies" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try @import("../test_support.zig").tmpRootPath(&tmp);
    defer std.testing.allocator.free(root);
    const source = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "tests/feature_tests/contracts/115_inline_operation_bodies/main.rg", std.testing.allocator, .limited(64 * 1024));
    defer std.testing.allocator.free(source);
    const files = [_]sf.SourceFile{.{ .path = "app/main.rg", .code = source }};
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
    const changed = try std.mem.replaceOwned(u8, std.testing.allocator, source, ".multiply =\n        (.left: &Row, .right: &Column) -> (.result: Result) {\n        result = left&.value * right&.value * Scale\n    }", ".multiply = wrong_result");
    defer std.testing.allocator.free(changed);
    invalid[0].code = try std.fmt.allocPrint(std.testing.allocator, "{s}\nwrong_result := (.left: &Row, .right: &Column) -> (.result: UInt8) {{ result = 1 }}\n", .{changed});
    defer std.testing.allocator.free(invalid[0].code);
    const rejected = try expectCleanEquivalent(&invalid, &warm);
    defer rejected.deinit();
    try std.testing.expect(rejected.failure != null);
    try std.testing.expect(std.mem.indexOf(u8, rejected.diagnostics, "incompatible associated result") != null);
}
