from pathlib import Path

# Zig needs the globalized source literal typed explicitly.
path = Path("src/4_semantics/global/semantizer.zig")
text = path.read_text()
old = "                    const source = .{"
new = '                    const source: @import("../primitives/schema.zig").SourceRef = .{'
count = text.count(old)
if count != 2:
    raise RuntimeError(f"expected two unresolved choice source literals, found {count}")
path.write_text(text.replace(old, new))

# The invalid semantic unit in `value..variant` is the variant token, not the
# whole access expression. Preserve that provenance when ModuleSema creates the
# pending operation so diagnostics and later resolved nodes share one source.
path = Path("src/4_semantics/module/body_lowerer.zig")
text = path.read_text()
old = (
    "            .option_name = try self.writer.addString(self.tree.tokenTextFromSource(self.source, access.variant_token)),\n"
    "            .source = self.sourceRef(node),\n"
)
new = (
    "            .option_name = try self.writer.addString(self.tree.tokenTextFromSource(self.source, access.variant_token)),\n"
    "            .source = .{ .file_index = self.file_index, .offset = self.tree.tokenLocation(access.variant_token).offset },\n"
)
count = text.count(old)
if count != 1:
    raise RuntimeError(f"expected one choice payload source assignment, found {count}")
path.write_text(text.replace(old, new, 1))
