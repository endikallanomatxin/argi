#!/usr/bin/env python3
"""Exercise an extracted release away from the compiler checkout."""

import os
from pathlib import Path
import subprocess
import sys
import tempfile


def main():
    executable = (Path(sys.argv[1]) / "bin/argi").resolve()
    env = {key: value for key, value in os.environ.items()
           if not key.startswith(("ARGI_", "LLVM_", "DYLD_")) and
           key != "LD_LIBRARY_PATH"}
    with tempfile.TemporaryDirectory(prefix="argi-consumer-") as directory:
        def run(*args):
            return subprocess.check_output([str(executable), *args], cwd=directory,
                                           env=env, text=True, stderr=subprocess.STDOUT)
        print(run("--version").strip())
        run("init", "hello")
        source = Path(directory) / "hello/source/hello/main.rg"
        text = source.read_text()
        last_brace = text.rindex("}")
        source.write_text(text[:last_brace] + '    print("Release package works")\n' + text[last_brace:])
        output = run("run", str(Path(directory) / "hello"))
        if "Release package works" not in output:
            raise RuntimeError(f"The generated program did not run: {output}")
        run("build", str(Path(directory) / "hello"), "--release")
        print("Extracted package compiled and ran a program with core capabilities.")


if __name__ == "__main__":
    main()
