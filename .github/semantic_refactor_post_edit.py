import subprocess

subprocess.run([
    "zig", "fmt",
    "src/4_semantics/global/control.zig",
], check=True)
