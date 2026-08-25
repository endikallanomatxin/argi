const source_files = @import("1_base/source_files.zig");
const link = @import("5_codegen/link.zig");
const lsp = @import("0_commands/lsp.zig");
const tokenizer = @import("2_tokens/tokenizer.zig");
const safety_facts = @import("4_semantics/safety_facts.zig");

test {
    _ = source_files;
    _ = link;
    _ = lsp;
    _ = tokenizer;
    _ = safety_facts;
}
