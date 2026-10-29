#!/usr/bin/env python3
"""Exercise an extracted release away from the compiler checkout."""

import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("prefix", type=Path)
    parser.add_argument("--usecases", required=True, type=Path)
    args = parser.parse_args()
    executable = (args.prefix / "bin/argi").resolve()
    fixtures = args.usecases.resolve()
    env = {key: value for key, value in os.environ.items()
           if not key.startswith(("ARGI_", "LLVM_", "DYLD_")) and
           key != "LD_LIBRARY_PATH"}
    with tempfile.TemporaryDirectory(prefix="argi-consumer-") as directory:
        def execute(command, *, data=None, expected=0):
            result = subprocess.run(command, cwd=directory, env=env, input=data,
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                    timeout=180)
            if result.returncode != expected:
                raise RuntimeError(f"Command failed: {command}\n"
                                   f"stdout: {result.stdout!r}\nstderr: {result.stderr!r}")
            return result.stdout

        def run(*args):
            return execute([str(executable), *map(str, args)]).decode("utf-8")
        run("--version")
        run("init", "hello")
        source = Path(directory) / "hello/source/hello/main.rg"
        text = source.read_text(encoding="utf-8")
        last_brace = text.rindex("}")
        source.write_text(text[:last_brace] + '    print("Release package works")\n' + text[last_brace:], encoding="utf-8")
        output = run("run", str(Path(directory) / "hello"))
        if "Release package works" not in output:
            raise RuntimeError(f"The generated program did not run: {output}")
        run("build", str(Path(directory) / "hello"), "--release")
        project = Path(directory) / "hello"
        tests = source.with_name("smoke_test.rg")
        tests.write_text("test installed_test := (.error_tracer: $&Virtual#(ErrorTracer)) -> !() {\n"
                         "    assume error_tracer\n"
                         "    testing.expect(.condition = true)!\n}\n", encoding="utf-8")
        run("format", project)
        before = {path: path.read_bytes() for path in project.rglob("*.rg")}
        run("format", "--check", project)
        if any(path.read_bytes() != content for path, content in before.items()):
            raise RuntimeError("format --check modified project sources")
        run("check", project, "--no-cache")
        run("test", source.parent)

        # Copy source fixtures only: no checkout caches or previously built binaries.
        cases = Path(directory) / "examples"
        for name in ("01_cat", "02_echo_until_empty", "03_word_count",
                     "04_tree", "06_weighted_regression"):
            target = cases / name
            shutil.copytree(fixtures / name, target,
                            ignore=shutil.ignore_patterns("build", ".argi-cache"))
            run("format", "--check", target)
            run("check", target, "--no-cache")
            for flags in ((), ("--release",)):
                run("build", target, "--no-cache", *flags)
                binary = target / "build/output"
                if name == "01_cat":
                    data = b"binary\x00bytes\xff\n" * 2048
                    assert execute([str(binary)], data=data) == data
                    missing = execute([str(binary), "missing-input"], expected=1)
                    assert missing == b""
                elif name == "02_echo_until_empty":
                    assert execute([str(binary)], data=b"hello\nworld\n\nignored\n") == b"hello\nworld\n"
                elif name == "03_word_count":
                    inputs = Path(directory) / "words"
                    inputs.mkdir(exist_ok=True)
                    (inputs / "first.txt").write_text("café tea café\n", encoding="utf-8")
                    (inputs / "second.txt").write_text("tea café\n", encoding="utf-8")
                    output = execute([str(binary), str(inputs), "64"])
                    assert set(output.decode("utf-8").splitlines()) == {"3\tcafé", "2\ttea"}
                    assert execute([str(binary), str(inputs), "1"], expected=1) == b""
                elif name == "04_tree":
                    tree = Path(directory) / "tree"
                    (tree / "nested").mkdir(parents=True, exist_ok=True)
                    (tree / "first.txt").touch()
                    (tree / "nested/second.txt").touch()
                    output = execute([str(binary), "--root", str(tree), "--depth", "2"])
                    assert {Path(line).relative_to(tree).as_posix() for line in output.decode().splitlines()} == {
                        "first.txt", "nested", "nested/second.txt"}
                else:
                    execute([str(binary)])
            print(f"Installed usecase passed in debug and release: {name}")
        print("Extracted package passed project tooling and usecase validation.")


if __name__ == "__main__":
    main()
