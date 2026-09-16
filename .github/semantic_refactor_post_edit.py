import subprocess

subprocess.run([
    "zig", "fmt",
    "src/3_syntax/syntaxer.zig",
    "src/0_commands/frontend_pipeline.zig",
], check=True)
