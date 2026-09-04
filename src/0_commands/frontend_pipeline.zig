const std = @import("std");

const sf = @import("../1_base/source_files.zig");
const source_db = @import("../1_base/source_db.zig");
const diag = @import("../1_base/diagnostic.zig");
const token = @import("../2_tokens/token.zig");
const tokenizer = @import("../2_tokens/tokenizer.zig");
const st = @import("../3_syntax/syntax_tree_legacy.zig");
const syntaxer = @import("../3_syntax/syntaxer_legacy.zig");
const sg = @import("../4_semantics/semantic_graph.zig");
const semantizer = @import("../4_semantics/semantizer.zig");
const safety_checker = @import("../4_semantics/safety_checker.zig");

// FrontendPipeline is the shared orchestration layer for the pre-codegen
// compiler phases. The intent is to keep `build` and `lsp` on exactly the same
// tokenizing/syntaxing/semantizing path so architectural changes in the
// compiler do not fork into subtly different command-specific pipelines.
pub const FrontendPipeline = struct {
    pub const FileTokens = struct {
        file_id: source_db.FileId,
        tokens: []const token.Token,
    };

    pub const Options = struct {
        semantizer: semantizer.SemantizerOptions = .{},
        collect_stats: bool = false,
    };

    allocator: std.mem.Allocator,
    io: std.Io,
    diagnostics: *diag.Diagnostics,
    options: Options,
    source_db: *const source_db.SourceDb,
    token_files: std.array_list.Managed(FileTokens),
    st_list: std.array_list.Managed(*st.STNode),
    syntax_ctx: ?syntaxer.Syntaxer = null,
    sem_ctx: ?semantizer.Semantizer = null,
    safety_ctx: ?safety_checker.SafetyChecker = null,
    semantize_timings: semantizer.Semantizer.SemantizeTimings = .{},
    safety_ns: u64 = 0,
    st_node_count: usize = 0,
    sg_node_count: usize = 0,
    st_nodes: []const *st.STNode = &.{},
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
            .token_files = std.array_list.Managed(FileTokens).init(allocator),
            .st_list = std.array_list.Managed(*st.STNode).init(allocator),
        };
    }

    pub fn deinit(self: *FrontendPipeline) void {
        if (self.safety_ctx) |*ctx| ctx.deinit();
        for (self.token_files.items) |file_tokens| self.allocator.free(file_tokens.tokens);
        self.token_files.deinit();
        self.st_list.deinit();
    }

    pub fn tokenizeFiles(self: *FrontendPipeline, files: []const sf.SourceFile) !void {
        for (self.token_files.items) |file_tokens| self.allocator.free(file_tokens.tokens);
        self.token_files.clearRetainingCapacity();

        for (files, 0..) |source_file, index| {
            var tokenizer_ctx = tokenizer.Tokenizer.init(
                self.allocator,
                self.diagnostics,
                source_file.code,
                self.source_db.fileId(index),
            );
            _ = try tokenizer_ctx.tokenize();
            try self.token_files.append(.{
                .file_id = self.source_db.fileId(index),
                .tokens = try tokenizer_ctx.takeTokens(),
            });
        }
    }

    pub fn syntax(self: *FrontendPipeline) ![]const *st.STNode {
        self.st_list.clearRetainingCapacity();
        self.st_node_count = 0;
        for (self.token_files.items) |file_tokens| {
            self.syntax_ctx = syntaxer.Syntaxer.init(
                self.allocator,
                file_tokens.tokens,
                self.source_db.get(file_tokens.file_id).source,
                self.diagnostics,
            );
            const nodes = try self.syntax_ctx.?.parse();
            try self.st_list.appendSlice(nodes);
            self.st_node_count += self.syntax_ctx.?.nodeCount();
        }
        self.st_nodes = self.st_list.items;
        return self.st_nodes;
    }

    pub fn tokenCount(self: *const FrontendPipeline) usize {
        var count: usize = 0;
        for (self.token_files.items) |file_tokens| count += file_tokens.tokens.len;
        return count;
    }

    pub fn tokenStorageBytes(self: *const FrontendPipeline) usize {
        return self.tokenCount() * @sizeOf(token.Token);
    }

    pub fn tokensForPath(self: *const FrontendPipeline, path: []const u8) ?[]const token.Token {
        const file_id = self.source_db.findPath(path) orelse return null;
        for (self.token_files.items) |file_tokens| {
            if (file_tokens.file_id == file_id) return file_tokens.tokens;
        }
        return null;
    }

    pub fn parseFiles(self: *FrontendPipeline, files: []const sf.SourceFile) ![]const *st.STNode {
        try self.tokenizeFiles(files);
        return try self.syntax();
    }

    pub fn semantizeFiles(self: *FrontendPipeline, files: []const sf.SourceFile) ![]const *sg.SGNode {
        _ = try self.parseFiles(files);
        return try self.semantize();
    }

    pub fn semantize(self: *FrontendPipeline) ![]const *sg.SGNode {
        self.sg_node_count = 0;
        if (self.options.collect_stats) sg.beginNodeCounting(&self.sg_node_count);
        defer if (self.options.collect_stats) sg.endNodeCounting();
        self.sem_ctx = semantizer.Semantizer.init(&self.allocator, self.io, self.st_nodes, self.diagnostics, self.options.semantizer);
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
};
