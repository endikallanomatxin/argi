import subprocess

subprocess.run([
    "zig", "fmt",
    "src/4_semantics/module/entities.zig",
    "src/4_semantics/module/body_lowerer.zig",
    "src/4_semantics/global/expressions.zig",
    "src/4_semantics/global/semantizer.zig",
], check=True)
