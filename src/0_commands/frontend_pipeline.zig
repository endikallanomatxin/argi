const std = @import("std");

const sf = @import("../1_base/source_files.zig");
const diag = @import("../1_base/diagnostic.zig");
const token = @import("../2_tokens/token.zig");
const tokenizer = @import("../2_tokens/tokenizer.zig");
const st = @import("../3_syntax/syntax_tree.zig");
const syntaxer = @import("../3_syntax/syntaxer.zig");
const sg = @import("../4_semantics/semantic_graph.zig");
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
    tokens: std.array_list.Managed(token.Token),
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
            .tokens = std.array_list.Managed(token.Token).init(allocator),
        };
    }

    pub fn deinit(self: *FrontendPipeline) void {
        if (self.safety_ctx) |*ctx| ctx.deinit();
        self.tokens.deinit();
    }

    pub fn tokenizeFiles(self: *FrontendPipeline, files: []const sf.SourceFile) !void {
        self.tokens.clearRetainingCapacity();

        for (files, 0..) |source_file, idx| {
            var tokenizer_ctx = tokenizer.Tokenizer.init(
                self.allocator,
                self.diagnostics,
                source_file.code,
                source_file.path,
            );
            const token_slice = try tokenizer_ctx.tokenize();

            const slice = if (idx == files.len - 1)
                token_slice
            else
                token_slice[0 .. token_slice.len - 1];

            try self.tokens.appendSlice(slice);
        }
    }

    pub fn syntax(self: *FrontendPipeline) ![]const *st.STNode {
        self.syntax_ctx = syntaxer.Syntaxer.init(self.allocator, self.tokens.items, self.diagnostics);
        self.st_nodes = try self.syntax_ctx.?.parse();
        self.st_node_count = self.syntax_ctx.?.nodeCount();
        return self.st_nodes;
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
