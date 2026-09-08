const std = @import("std");

const sf = @import("../1_base/source_files.zig");
const source_db = @import("../1_base/source_db.zig");
const diag = @import("../1_base/diagnostic.zig");
const token = @import("../2_tokens/token.zig");
const tokenizer = @import("../2_tokens/tokenizer.zig");
const st = @import("../3_syntax/syntax_tree.zig");
const syntaxer = @import("../3_syntax/syntaxer.zig");
const sg = @import("../4_semantics/semantic_graph.zig");
const module_sg = @import("../4_semantics/module_semantic_graph.zig");
const module_semantizer = @import("../4_semantics/module_semantizer.zig");
const global_semantic_graph_builder = @import("../4_semantics/global_semantic_graph_builder.zig");
const semantizer = @import("../4_semantics/semantizer.zig");
const safety_checker = @import("../4_semantics/safety_checker.zig");

// FrontendPipeline is the shared orchestration layer for the pre-codegen
// compiler phases. The intent is to keep `build` and `lsp` on exactly the same
// tokenizing/syntaxing/semantizing path so architectural changes in the
// compiler do not fork into subtly different command-specific pipelines.
pub const FrontendPipeline = struct {
    pub const Options = struct {
        semantizer: semantizer.SemantizerOptions = .{},
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
    global_builder: global_semantic_graph_builder.GlobalSemanticGraphBuilder = .{},
    syntax_ctx: ?syntaxer.Syntaxer = null,
    sem_ctx: ?semantizer.Semantizer = null,
    safety_ctx: ?safety_checker.SafetyChecker = null,
    semantize_timings: semantizer.Semantizer.SemantizeTimings = .{},
    safety_ns: u64 = 0,
    module_semantizing_ns: u64 = 0,
    global_merge_ns: u64 = 0,
    module_lowered_functions: u32 = 0,
    module_deferred_functions: u32 = 0,
    syntax_node_count: usize = 0,
    sg_node_count: usize = 0,
    syntax_roots: []const st.SyntaxRef = &.{},
    sg_nodes: []const *sg.SGNode = &.{},

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
        if (self.safety_ctx) |*ctx| ctx.deinit();
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
                // Keep the failed file's tokens for lexical LSP fallback.
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

    pub fn semantizeFiles(self: *FrontendPipeline, files: []const sf.SourceFile) ![]const *sg.SGNode {
        _ = try self.parseFiles(files);
        return try self.semantize();
    }

    pub fn semantize(self: *FrontendPipeline) ![]const *sg.SGNode {
        const module_start = std.Io.Timestamp.now(self.io, .boot).nanoseconds;
        self.clearModuleGraphs();
        errdefer self.clearModuleGraphs();
        self.module_lowered_functions = 0;
        self.module_deferred_functions = 0;
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
            });
        }
        try self.module_graphs.ensureTotalCapacity(self.allocator, groups.items.len);
        for (groups.items) |group| {
            var result = try module_semantizer.build(self.allocator, group.dir, group.files.items);
            self.module_lowered_functions += result.stats.lowered_functions;
            self.module_deferred_functions += result.stats.deferred_functions;
            self.module_graphs.appendAssumeCapacity(result.graph);
        }
        self.module_semantizing_ns = @intCast(std.Io.Timestamp.now(self.io, .boot).nanoseconds - module_start);
        const merge_start = std.Io.Timestamp.now(self.io, .boot).nanoseconds;
        self.global_builder = try global_semantic_graph_builder.mergeModuleGraphs(self.allocator, self.module_graphs.items, self.source_db);
        self.global_merge_ns = @intCast(std.Io.Timestamp.now(self.io, .boot).nanoseconds - merge_start);
        self.sg_node_count = 0;
        if (self.options.collect_stats) sg.beginNodeCounting(&self.sg_node_count);
        defer if (self.options.collect_stats) sg.endNodeCounting();
        self.sem_ctx = semantizer.Semantizer.init(&self.allocator, self.io, self.syntax_files.items, self.syntax_roots, &self.global_builder, self.diagnostics, self.options.semantizer);
        const result = try self.sem_ctx.?.semantizeWithTimings();
        self.sg_nodes = result.nodes;
        self.safety_ctx = safety_checker.SafetyChecker.init(&self.allocator, self.diagnostics);
        if (self.options.collect_stats) self.safety_ctx.?.enableStats();
        const safety_start = std.Io.Timestamp.now(self.io, .boot).nanoseconds;
        try self.safety_ctx.?.analyze(self.sg_nodes);
        self.safety_ns = @intCast(std.Io.Timestamp.now(self.io, .boot).nanoseconds - safety_start);
        self.semantize_timings = result.timings;
        return self.sg_nodes;
    }

    fn clearModuleGraphs(self: *FrontendPipeline) void {
        self.global_builder.deinit(self.allocator);
        for (self.module_graphs.items) |*graph| graph.deinit(self.allocator);
        self.module_graphs.clearRetainingCapacity();
    }

    pub fn moduleSemanticStorageBytes(self: *const FrontendPipeline) usize {
        var bytes: usize = 0;
        for (self.module_graphs.items) |*graph| bytes += graph.storageBytes();
        return bytes;
    }
};
