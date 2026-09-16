import subprocess

subprocess.run([
    "zig", "fmt",
    "src/4_semantics/global/core.zig",
    "src/4_semantics/global/generic_functions.zig",
    "src/4_semantics/global/control.zig",
    "src/4_semantics/global/semantizer.zig",
], check=True)
