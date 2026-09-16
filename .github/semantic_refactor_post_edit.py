import subprocess

subprocess.run([
    "zig", "fmt",
    "src/3_syntax/syntaxer.zig",
], check=True)
