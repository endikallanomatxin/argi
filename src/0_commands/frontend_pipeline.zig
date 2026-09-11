const std = @import("std");

const sf = @import("../1_base/source_files.zig");
const source_db = @import("../1_base/source_db.zig");
const diag = @import("../1_base/diagnostic.zig");
const token = @import("../2_tokens/token.zig");
const tokenizer = @import("../2_tokens/tokenizer.zig");
const st = @import("../3_syntax/syntax_tree.zig");
const syntaxer = @import("../3_syntax/syntaxer.zig");
const module_sg = @import("../4_semantics/module/graph.zig");
const module_semantizer = @import("../4_semantics/module/semantizer.zig");
const global_sg = @import("../4_semantics/global/graph.zig");
const global_semantizer = @import("../4_semantics/global/semantizer.zig");
const global_once_verify = @import("../4_semantics/global/once_verify.zig");
const module_test_validate = @import("../4_semantics/module/test_validate.zig");
const global_safety_checker = @import("../4_semantics/safety/checker.zig");

pub const FrontendPipeline = struct {
    /// Indexed-frontend command options. The `semantizer` field name is kept
    /// temporarily so build/test call sites can migrate independently from the
    /// removal of the old pointer Semantizer implementation.
    pub const SemanticOptions = struct {
        include_tests: bool = false,
        selected_test_name: ?[]const u8 = null,
        implicit_testing_module_dir: ?[]const u8 = null,
        exhaustive_function_bodies: bool = true,
    };

    pub const Options = struct {
        semantizer: SemanticOptions = .{},
        collect_stats: bool = false,
    };

    allocator: std.mem.Allocator,
    io: std.Io,
    diagnostics: *diag.Diagnostics,
    options: Options,
    source_db: *const source_db.SourceDb,
    syntax_files: std.array_list.Managed(st.FileSyntaxTree),
    syntax_root_list: std.array_list.Managed(st.SyntaxRef),
    module_graphs: std.ArrayList(module_sg.ModuleSemanticGraph) = .empty,
    /// Authoritative whole-program semantic artifact. No pointer SemanticGraph
    /// can be materialized by this pipeline anymore.
    global_graph: ?global_sg.GlobalSemanticGraph = null,
    global_stats: global_semantizer.Stats = .{},
    global_safety_stats: global_safety_checker.SafetyChecker.Stats = .{},
    syntax_ctx: ?syntaxer.Syntaxer = null,
    safety_ctx: ?global_safety_checker.SafetyChecker = null,
    safety_ns: u64 = 0,
    module_semantizing_ns: u64 = 0,
    global_semantic_ns: u64 = 0,
    module_lowered_functions: u32 = 0,
    module_fallback_functions: u32 = 0,
    syntax_node_count: usize = 0,
    syntax_roots: []const st.SyntaxRef = &.{},

    pub fn init(
        allocator: std.mem.Allocator,
        io: std.Io,
        diagnostics: *diag.Diagnostics,
        options: Options,
    ) FrontendPipeline {
        return .{
            .allocator = allocator,
            .io = io,
            .diagnostics = diagnostics,
            .options = options,
            .source_db = &diagnostics.source_db,
            .syntax_files = std.array_list.Managed(st.FileSyntaxTree).init(allocator),
            .syntax_root_list = std.array_list.Managed(st.SyntaxRef).init(allocator),
        };
    }

    pub fn deinit(self: *FrontendPipeline) void {
        self.clearModuleGraphs();
        self.module_graphs.deinit(self.allocator);
        for (self.syntax_files.items) |*file| file.deinit(self.allocator);
        self.syntax_files.deinit();
        self.syntax_root_list.deinit();
    }

    pub fn tokenizeFiles(self: *FrontendPipeline, files: []const sf.SourceFile) !void {
        self.clearModuleGraphs();
        for (self.syntax_files.items) |*file| file.deinit(self.allocator);
        self.syntax_files.clearRetainingCapacity();

        for (files, 0..) |source_file, index| {
            var tokenizer_ctx = tokenizer.Tokenizer.init(
                self.allocator,
                self.diagnostics,
                source_file.code,
                self.source_db.fileId(index),
            );
            defer tokenizer_ctx.deinit();
            _ = try tokenizer_ctx.tokenize();
            var file = st.FileSyntaxTree.initOwnedTokens(self.source_db.fileId(index), tokenizer_ctx.takeTokens());
            errdefer file.deinit(self.allocator);
            try self.syntax_files.append(file);
        }
    }

    pub fn syntax(self: *FrontendPipeline) ![]const st.SyntaxRef {
        self.syntax_root_list.clearRetainingCapacity();
        self.syntax_node_count = 0;
        for (self.syntax_files.items) |*file| {
            const file_id = file.file_id;
            self.syntax_ctx = syntaxer.Syntaxer.initFile(self.allocator, file.*, self.source_db.get(file_id).source, self.diagnostics);
            file.* = .{ .file_id = file_id };
            file.* = self.syntax_ctx.?.parse() catch |err| {
                file.* = self.syntax_ctx.?.file;
                self.syntax_ctx.?.file = .{ .file_id = file_id };
                return err;
            };
            self.syntax_node_count += file.nodes.len;
            for (file.roots) |node| try self.syntax_root_list.append(file.ref(node));
        }
        self.syntax_roots = self.syntax_root_list.items;
        return self.syntax_roots;
    }

    pub fn syntaxStorageMetrics(self: *const FrontendPipeline) st.FileSyntaxTree.StorageMetrics {
        var result = st.FileSyntaxTree.StorageMetrics{ .token_bytes = 0, .node_base_bytes = 0, .extra_data_bytes = 0, .root_bytes = 0 };
        for (self.syntax_files.items) |*file| {
            const metrics = file.storageMetrics();
            result.token_bytes += metrics.token_bytes;
            result.node_base_bytes += metrics.node_base_bytes;
            result.extra_data_bytes += metrics.extra_data_bytes;
            result.root_bytes += metrics.root_bytes;
        }
        return result;
    }

    pub fn tokenCount(self: *const FrontendPipeline) usize {
        var count: usize = 0;
        for (self.syntax_files.items) |file| count += file.tokens.len;
        return count;
    }

    pub fn tokenStorageBytes(self: *const FrontendPipeline) usize {
        return self.tokenCount() * @sizeOf(token.Token);
    }

    pub fn tokensForPath(self: *const FrontendPipeline, path: []const u8) ?token.View {
        const file_id = self.source_db.findPath(path) orelse return null;
        for (self.syntax_files.items) |*file| {
            if (file.file_id == file_id) return token.View.init(&file.tokens);
        }
        return null;
    }

    pub fn parseFiles(self: *FrontendPipeline, files: []const sf.SourceFile) ![]const st.SyntaxRef {
        try self.tokenizeFiles(files);
        return try self.syntax();
    }

    /// Produce and safety-check the final indexed semantic graph. This is the
    /// sole semantic output API of the frontend.
    pub fn semantizeGlobalFiles(self: *FrontendPipeline, files: []const sf.SourceFile) !*const global_sg.GlobalSemanticGraph {
        _ = try self.parseFiles(files);
        try module_test_validate.validate(
            self.syntax_files.items,
            self.source_db,
            self.diagnostics,
            self.options.semantizer.include_tests,
            self.options.semantizer.selected_test_name,
        );
        try self.buildGlobalGraph();
        try self.analyzeGlobalSafety();
        return &self.global_graph.?;
    }

    fn analyzeGlobalSafety(self: *FrontendPipeline) !void {
        if (self.safety_ctx) |*ctx| ctx.deinit();
        self.safety_ctx = null;
        const graph = &self.global_graph.?;
        self.safety_ctx = global_safety_checker.SafetyChecker.init(self.allocator, self.diagnostics, graph);
        if (self.options.collect_stats) self.safety_ctx.?.enableStats();
        const safety_start = std.Io.Timestamp.now(self.io, .boot).nanoseconds;
        try self.safety_ctx.?.analyze();
        self.safety_ns = @intCast(std.Io.Timestamp.now(self.io, .boot).nanoseconds - safety_start);
        self.global_safety_stats = self.safety_ctx.?.stats;
    }

    fn buildGlobalGraph(self: *FrontendPipeline) !void {
        const module_start = std.Io.Timestamp.now(self.io, .boot).nanoseconds;
        self.clearModuleGraphs();
        errdefer self.clearModuleGraphs();
        self.module_lowered_functions = 0;
        self.module_fallback_functions = 0;

        const ModuleInputs = struct {
            dir: []const u8,
            files: std.ArrayList(module_sg.FileInput) = .empty,
        };
        var groups: std.ArrayList(ModuleInputs) = .empty;
        defer {
            for (groups.items) |*group| group.files.deinit(self.allocator);
            groups.deinit(self.allocator);
        }
        for (self.syntax_files.items) |*file| {
            const source = self.source_db.get(file.file_id);
            const dir = std.fs.path.dirname(source.path) orelse ".";
            var group_index: ?usize = null;
            for (groups.items, 0..) |group, index| if (std.mem.eql(u8, group.dir, dir)) {
                group_index = index;
                break;
            };
            if (group_index == null) {
                try groups.append(self.allocator, .{ .dir = dir });
                group_index = groups.items.len - 1;
            }
            try groups.items[group_index.?].files.append(self.allocator, .{
                .path = source.path,
                .tree = file,
                .source = source.source,
                .is_bundled_core = source.origin == .bundled_core,
            });
        }
        try self.module_graphs.ensureTotalCapacity(self.allocator, groups.items.len);
        for (groups.items) |group| {
            const result = try module_semantizer.build(self.allocator, group.dir, group.files.items);
            self.module_lowered_functions += result.stats.lowered_functions;
            self.module_fallback_functions += result.stats.fallback_functions;
            self.module_graphs.appendAssumeCapacity(result.graph);
        }
        self.module_semantizing_ns = @intCast(std.Io.Timestamp.now(self.io, .boot).nanoseconds - module_start);

        const global_start = std.Io.Timestamp.now(self.io, .boot).nanoseconds;
        const result = try global_semantizer.semantize(self.allocator, self.module_graphs.items);
        self.global_graph = result.graph;
        self.global_stats = result.stats;
        try global_once_verify.verify(
            self.allocator,
            &self.global_graph.?,
            self.diagnostics,
            self.options.semantizer.selected_test_name,
        );
        self.global_semantic_ns = @intCast(std.Io.Timestamp.now(self.io, .boot).nanoseconds - global_start);
    }

    fn clearModuleGraphs(self: *FrontendPipeline) void {
        if (self.safety_ctx) |*ctx| ctx.deinit();
        self.safety_ctx = null;
        if (self.global_graph) |*graph| graph.deinit(self.allocator);
        self.global_graph = null;
        for (self.module_graphs.items) |*graph| graph.deinit(self.allocator);
        self.module_graphs.clearRetainingCapacity();
    }

    pub fn moduleSemanticStorageBytes(self: *const FrontendPipeline) usize {
        var bytes: usize = 0;
        for (self.module_graphs.items) |*graph| bytes += graph.storageBytes();
        return bytes;
    }

    pub fn globalSemanticStorageBytes(self: *const FrontendPipeline) usize {
        return if (self.global_graph) |*graph| graph.storageBytes() else 0;
    }
};
