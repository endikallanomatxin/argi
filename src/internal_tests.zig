const source_files = @import("1_base/source_files.zig");
const link = @import("5_codegen/link.zig");
const lsp = @import("0_commands/lsp.zig");
const tokenizer = @import("2_tokens/tokenizer.zig");
const safety_facts = @import("4_semantics/safety_facts.zig");
const safety_checker = @import("4_semantics/safety_checker.zig");
const syntax_tree = @import("3_syntax/syntax_tree.zig");
const syntaxer = @import("3_syntax/syntaxer.zig");
const syntaxer_test = @import("3_syntax/syntaxer_test.zig");
const module_semantic_graph_test = @import("4_semantics/module_semantic_graph_test.zig");
const global_semantic_graph_builder = @import("4_semantics/global_semantic_graph_builder.zig");

const semantic_primitives = @import("4_semantics/semantic_primitives.zig");
const module_semantic_entities = @import("4_semantics/module_semantic_entities.zig");
const module_semantic_storage = @import("4_semantics/module_semantic_storage.zig");
const module_semantic_templates = @import("4_semantics/module_semantic_templates.zig");
const module_semantic_views = @import("4_semantics/module_semantic_views.zig");
const semantic_verify = @import("4_semantics/semantic_verify.zig");
const semantic_payload_verify = @import("4_semantics/semantic_payload_verify.zig");
const module_semantic_verify = @import("4_semantics/module_semantic_verify.zig");
const module_semantic_template_verify = @import("4_semantics/module_semantic_template_verify.zig");
const module_semantic_complete_verify = @import("4_semantics/module_semantic_complete_verify.zig");
const global_semantic_graph = @import("4_semantics/global_semantic_graph.zig");
const global_semantic_verify = @import("4_semantics/global_semantic_verify.zig");
const semantic_globalizer = @import("4_semantics/semantic_globalizer.zig");
const semantic_representation_test = @import("4_semantics/semantic_representation_test.zig");

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
    _ = module_semantic_graph_test;
    _ = global_semantic_graph_builder;

    _ = semantic_primitives;
    _ = module_semantic_entities;
    _ = module_semantic_storage;
    _ = module_semantic_templates;
    _ = module_semantic_views;
    _ = semantic_verify;
    _ = semantic_payload_verify;
    _ = module_semantic_verify;
    _ = module_semantic_template_verify;
    _ = module_semantic_complete_verify;
    _ = global_semantic_graph;
    _ = global_semantic_verify;
    _ = semantic_globalizer;
    _ = semantic_representation_test;
}