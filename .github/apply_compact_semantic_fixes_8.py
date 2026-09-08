from pathlib import Path

path = Path("src/0_commands/indexed_lsp_service.zig")
text = path.read_text()
old = "        _ = pipeline.semantizeGlobalFiles(files) catch return null;\n\n        var graph = pipeline.global_graph.?;"
new = """        _ = pipeline.semantizeGlobalFiles(files) catch {
            // Parsing/global semantic failures leave no graph. Safety failures,
            // however, happen after GlobalSG is complete and should not disable
            // editor navigation for otherwise-resolved symbols.
            if (pipeline.global_graph == null) return null;
        };

        var graph = pipeline.global_graph.?;"""
if new not in text:
    if old not in text:
        raise SystemExit("collectAnalysis semantize pattern not found")
    text = text.replace(old, new, 1)
path.write_text(text)
