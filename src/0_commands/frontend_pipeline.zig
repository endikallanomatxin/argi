const std = @import("std");

const sf = @import("../1_base/source_files.zig");
const diag = @import("../1_base/diagnostic.zig");
const token = @import("../2_tokens/token.zig");
const tokenizer = @import("../2_tokens/tokenizer.zig");
const st = @import("../3_syntax/syntax_tree.zig");
const syntaxer = @import("../3_syntax/syntaxer.zig");
const sg = @import("../4_semantics/semantic_graph.zig");
const semantizer = @import("../4_semantics/semantizer.zig");

// FrontendPipeline is the shared orchestration layer for the pre-codegen
// compiler phases. The intent is to keep `build` and `lsp` on exactly the same
// tokenizing/syntaxing/semantizing path so architectural changes in the
// compiler do not fork into subtly different command-specific pipelines.
pub const FrontendPipeline = struct {
    allocator: *const std.mem.Allocator,
    diagnostics: *diag.Diagnostics,
    tokens: std.array_list.Managed(token.Token),
    syntax_ctx: ?syntaxer.Syntaxer = null,
    sem_ctx: ?semantizer.Semantizer = null,
    semantize_timings: semantizer.Semantizer.SemantizeTimings = .{},
    st_nodes: []const *st.STNode = &.{},
    sg_nodes: []const *sg.SGNode = &.{},

    pub fn init(
        allocator: *const std.mem.Allocator,
        diagnostics: *diag.Diagnostics,
    ) FrontendPipeline {
        return .{
            .allocator = allocator,
            .diagnostics = diagnostics,
            .tokens = std.array_list.Managed(token.Token).init(allocator.*),
        };
    }

    pub fn deinit(self: *FrontendPipeline) void {
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
        return self.st_nodes;
    }

    pub fn semantize(self: *FrontendPipeline) ![]const *sg.SGNode {
        self.sem_ctx = semantizer.Semantizer.init(self.allocator, self.st_nodes, self.diagnostics);
        const result = try self.sem_ctx.?.semantizeWithTimings();
        self.sg_nodes = result.nodes;
        self.semantize_timings = result.timings;
        return self.sg_nodes;
    }
};
