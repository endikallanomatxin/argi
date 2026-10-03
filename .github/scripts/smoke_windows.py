#!/usr/bin/env python3
"""Exercise a Windows source installation outside the compiler checkout."""

import os
from pathlib import Path
import subprocess
import sys
import tempfile


def main():
    executable = (Path(sys.argv[1]) / "bin/argi.exe").resolve()
    env = {key: value for key, value in os.environ.items()
           if not key.startswith(("ARGI_", "LLVM_"))}
    with tempfile.TemporaryDirectory(prefix="argi consumer \u00f1 ") as directory:
        def run(*args):
            result = subprocess.run([str(executable), *args], cwd=directory,
                                    env=env, stdout=subprocess.PIPE,
                                    stderr=subprocess.STDOUT)
            # Native linker diagnostics may use the Windows ANSI code page.
            # Preserve their content instead of hiding failures behind decoding.
            output = result.stdout.decode("utf-8", errors="backslashreplace")
            if result.returncode:
                raise RuntimeError(f"Command failed ({result.returncode}): {args}\n{output}")
            return output

        print(run("--version").strip())
        run("init", "hello")
        source = Path(directory) / "hello/source/hello/main.rg"
        text = source.read_text(encoding="utf-8")
        end = text.rindex("}")
        source.write_text(text[:end] + '    print("Windows installation works")\n' + text[end:],
                          encoding="utf-8")
        for flags in ((), ("--release",), ("--no-cache",)):
            output = run("run", str(Path(directory) / "hello"), *flags)
            if "Windows installation works" not in output:
                raise RuntimeError(f"Generated program did not run: {output}")
        if not (Path(directory) / "hello/build/debug/hello.exe").is_file():
            raise RuntimeError("Missing installed-project executable")
        print("Installed compiler/core work outside the checkout, including release builds.")


if __name__ == "__main__":
    main()
