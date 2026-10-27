const std = @import("std");

// These helpers only build/read one fixture's outputs or run its executable.
// Unknown helpers stay serial until their shared-state behavior is audited.
const safe_helpers = [_][]const u8{
    "expectSuccessfulBuild", "buildExpectFail",                  "buildExpectFailWithoutNoise",
    "buildExpectFailExact",  "buildExpectFailWithoutParseNoise", "run",
    "runExpect",             "runExpectFailure",                 "runExpectStdout",
    "runExpectStderr",       "runExpectStdoutWithArgs",          "runExpectStdoutWithArgsAndStdin",
};

pub fn fixtureKey(tree: *const std.zig.Ast, node: std.zig.Ast.Node.Index) ?[]const u8 {
    if (tree.nodeTag(node) != .test_decl) return null;
    const name_token, const body = tree.nodeData(node).opt_token_and_node;
    const name = tree.tokenSlice(name_token.unwrap() orelse return null);
    if (!std.mem.startsWith(u8, name, "\"feature_tests/") and
        !std.mem.startsWith(u8, name, "\"tests/feature_tests/")) return null;
    var key: ?[]const u8 = null;
    const first = tree.firstToken(body);
    const last = tree.lastToken(body);
    for (first..last + 1) |raw| {
        const token: std.zig.Ast.TokenIndex = @intCast(raw);
        const text = tree.tokenSlice(token);
        if (tree.tokenTag(token) == .identifier and raw < last and tree.tokenTag(token + 1) == .l_paren) {
            var safe = false;
            for (safe_helpers) |helper| if (std.mem.eql(u8, text, helper)) {
                safe = true;
                break;
            };
            if (!safe) return null;
        }
        if (tree.tokenTag(token) != .string_literal or !std.mem.startsWith(u8, text, "\"tests/feature_tests/")) continue;
        const path = text[1 .. text.len - 1];
        const category_start = "tests/feature_tests/".len;
        const category_end = std.mem.indexOfScalarPos(u8, path, category_start, '/') orelse return null;
        const category = path[category_start..category_end];
        var audited = false;
        for ([_][]const u8{ "basics", "collections", "contracts", "control_flow", "functions", "numbers", "ownership", "pointers", "polymorphism", "text", "types" }) |parallel_category|
            if (std.mem.eql(u8, category, parallel_category)) {
                audited = true;
                break;
            };
        if (!audited) return null;
        if (key) |previous| {
            if (!std.mem.eql(u8, previous, path)) return null;
        } else key = path;
    }
    const fixture = key orelse return null;
    var block_buffer: [2]std.zig.Ast.Node.Index = undefined;
    const statements = tree.blockStatements(&block_buffer, body) orelse return null;
    var binding: ?[]const u8 = null;
    for (statements) |statement| {
        if (tree.fullVarDecl(statement)) |decl| {
            if (binding != null or tree.tokenTag(decl.ast.mut_token) != .keyword_const) return null;
            const value = decl.ast.init_node.unwrap() orelse return null;
            if (tree.nodeTag(value) != .string_literal) return null;
            const literal = tree.tokenSlice(tree.nodeMainToken(value));
            if (!std.mem.eql(u8, fixture, literal[1 .. literal.len - 1])) return null;
            binding = tree.tokenSlice(decl.ast.mut_token + 1);
            continue;
        }
        if (tree.nodeTag(statement) != .@"try") return null;
        const expression = tree.nodeData(statement).node;
        var call_buffer: [1]std.zig.Ast.Node.Index = undefined;
        const call = tree.fullCall(&call_buffer, expression) orelse return null;
        if (tree.nodeTag(call.ast.fn_expr) != .identifier or call.ast.params.len == 0) return null;
        const argument = call.ast.params[0];
        const text = tree.tokenSlice(tree.nodeMainToken(argument));
        switch (tree.nodeTag(argument)) {
            .identifier => if (binding == null or !std.mem.eql(u8, text, binding.?)) return null,
            .string_literal => if (!std.mem.eql(u8, fixture, text[1 .. text.len - 1])) return null,
            else => return null,
        }
    }
    return fixture;
}

pub fn workerFor(key: []const u8, workers: u32) u32 {
    std.debug.assert(workers != 0);
    return @intCast(std.hash.Wyhash.hash(0, key) % workers);
}

pub fn verifyIsolation() !void {
    const cases = [_]struct { source: [:0]const u8, parallel: bool }{
        .{ .source = "test \"feature_tests/contracts/one\" { const path = \"tests/feature_tests/contracts/one\"; try expectSuccessfulBuild(path); try run(path); }", .parallel = true },
        .{ .source = "test \"tests/feature_tests/contracts/alias\" { try buildExpectFail(\"tests/feature_tests/contracts/one\", \"constraint\"); }", .parallel = true },
        .{ .source = "test \"feature_tests/contracts/one\" { try buildExpectFail(\"tests/feature_tests/contracts/one\", \"constraint\"); try run(\"tests/feature_tests/contracts/two\"); }", .parallel = false },
        .{ .source = "test \"feature_tests/contracts/one\" { try deleteCache(\"tests/feature_tests/contracts/one\"); }", .parallel = false },
        .{ .source = "test \"feature_tests/contracts/one\" { shared_state = 1; try run(\"tests/feature_tests/contracts/one\"); }", .parallel = false },
        .{ .source = "test \"feature_tests/contracts/one\" { for (cases) |case| { try run(case); } }", .parallel = false },
        .{ .source = "test \"feature_tests/contracts/one\" { const path = \"tests/feature_tests/contracts/one\"; try run(other_path); }", .parallel = false },
        .{ .source = "test \"feature_tests/system/one\" { try run(\"tests/feature_tests/system/one\"); }", .parallel = false },
        .{ .source = "test \"feature_tests/testing/one\" { try run(\"tests/feature_tests/testing/one\"); }", .parallel = false },
        .{ .source = "test \"feature_tests/new_category/one\" { try run(\"tests/feature_tests/new_category/one\"); }", .parallel = false },
        .{ .source = "test \"arbitrary CLI test\" { try run(\"tests/feature_tests/contracts/one\"); }", .parallel = false },
    };
    for (cases) |case| {
        var tree = try std.zig.Ast.parse(std.testing.allocator, case.source, .zig);
        defer tree.deinit(std.testing.allocator);
        try std.testing.expectEqual(@as(usize, 0), tree.errors.len);
        try std.testing.expectEqual(case.parallel, fixtureKey(&tree, tree.rootDecls()[0]) != null);
    }
    for ([_]u32{ 1, 2, 4, 8, 16, 64 }) |workers| {
        const fixture = "tests/feature_tests/contracts/one";
        const worker = workerFor(fixture, workers);
        try std.testing.expect(worker < workers);
        var selected: u32 = 0;
        for (0..workers) |candidate| if (candidate == worker) {
            selected += 1;
        };
        try std.testing.expectEqual(@as(u32, 1), selected);
    }
}

pub fn verifyInventory(source: [:0]const u8) !void {
    var tree = try std.zig.Ast.parse(std.testing.allocator, source, .zig);
    defer tree.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.errors.len);
    var parallel: usize = 0;
    var serial: usize = 0;
    var counts: [4]usize = @splat(0);
    for (tree.rootDecls()) |node| {
        if (tree.nodeTag(node) != .test_decl) continue;
        if (fixtureKey(&tree, node)) |key| {
            parallel += 1;
            counts[workerFor(key, 4)] += 1;
        } else serial += 1;
    }
    // Keep the classifier useful, while failing closed for unknown test bodies.
    try std.testing.expect(parallel > 1000);
    try std.testing.expect(serial > 0);
    for (counts) |count| try std.testing.expect(count > 200);
}
