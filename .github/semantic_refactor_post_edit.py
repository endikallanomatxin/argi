from pathlib import Path
import subprocess

path = Path("src/4_semantics/global/generic_functions.zig")
text = path.read_text()
old = "    fn inferInputType(\n"
new = "    pub fn inferInputType(\n"
if text.count(old) != 1:
    raise RuntimeError(f"inferInputType visibility anchor changed: {text.count(old)}")
path.write_text(text.replace(old, new, 1))

subprocess.run([
    "zig", "fmt",
    "src/4_semantics/global/core.zig",
    "src/4_semantics/global/constructors.zig",
    "src/4_semantics/global/generic_functions.zig",
], check=True)
