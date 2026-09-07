const source_files = @import("1_base/source_files.zig");
const link = @import("5_codegen/link.zig");
const lsp = @import("0_commands/lsp.zig");
const tokenizer = @import("2_tokens/tokenizer.zig");
const safety_facts = @import("4_semantics/safety_facts.zig");
const safety_checker = @import("4_semantics/safety_checker.zig");
const syntax_tree = @import("3_syntax/syntax_tree.zig");
const syntaxer = @import("3_syntax/syntaxer.zig");
const syntaxer_test = @import("3_syntax/syntaxer_test.zig");
const file_semantic_graph_test = @import("4_semantics/file_semantic_graph_test.zig");
const global_declarations = @import("4_semantics/global_declarations.zig");

test {
    _ = source_files;
    _ = link;
    _ = lsp;
    _ = tokenizer;
    _ = safety_facts;
    _ = safety_checker;
    _ = syntax_tree;
    _ = syntaxer;
    _ = syntaxer_test;
    _ = file_semantic_graph_test;
    _ = global_declarations;
}
