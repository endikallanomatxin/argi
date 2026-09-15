from pathlib import Path

path = Path("src/4_semantics/global/semantizer.zig")
text = path.read_text()
old = "                    const source = .{"
new = '                    const source: @import("../primitives/schema.zig").SourceRef = .{'
count = text.count(old)
if count != 2:
    raise RuntimeError(f"expected two unresolved choice source literals, found {count}")
path.write_text(text.replace(old, new))
