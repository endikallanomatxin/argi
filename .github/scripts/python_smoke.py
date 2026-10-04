#!/usr/bin/env python3
"""Exercise the optional Python adapter with the selected native installation."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import tomllib

REPO = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--argi", required=True)
    parser.add_argument("--cc")
    parser.add_argument("--include-dir", action="append", default=[])
    parser.add_argument("--library")
    parser.add_argument("--numpy", action="store_true")
    options = parser.parse_args()
    argi = str(Path(options.argi).resolve())
    with tempfile.TemporaryDirectory(prefix="argi-python-smoke-") as directory:
        root = Path(directory)
        helper = [sys.executable, str(REPO / "more/python/build.py"), "--argi", argi,
                  "--cache-dir", str(root / "cache")]
        if options.cc:
            helper += ["--cc", options.cc]
        for include in options.include_dir:
            helper += ["--include-dir", str(Path(include).resolve())]
        if options.library:
            helper += ["--library", str(Path(options.library).resolve())]
        metadata = json.loads(subprocess.check_output([*helper, "--json", "prepare"], cwd=root, text=True))
        object_path = Path(metadata["runtime_object"])
        first_stamp = object_path.stat().st_mtime_ns
        again = json.loads(subprocess.check_output([*helper, "--json", "prepare"], cwd=root, text=True))
        fragment = tomllib.loads(subprocess.check_output([*helper, "prepare"], cwd=root, text=True))
        assert [entry["file"] for entry in fragment["native"]] == [metadata["runtime_object"], metadata["python_library"]]
        assert again == metadata and object_path.stat().st_mtime_ns == first_stamp
        probe = root / ("probe.exe" if os.name == "nt" else "probe")
        probe_flags = ["-Wall", "-Wextra", "-Werror"]
        if os.name != "nt":
            probe_flags += ["-pthread"]
        subprocess.run([metadata["cc"], *metadata["compile_flags"], *probe_flags,
                        str(REPO / "tests/python_native.c"), metadata["python_library"], *metadata["runtime_link_flags"],
                        "-o", str(probe)], check=True, cwd=root)
        subprocess.run([str(probe)], check=True, cwd=root)
        for fixture in sorted((REPO / "tests/feature_tests/python").iterdir()):
            if "X" in fixture.name:
                continue
            for flags in ([], ["--release", "--no-cache"]):
                output = root / (fixture.name + (".exe" if os.name == "nt" else ""))
                subprocess.run([*helper, "build", str(fixture), "--output", str(output), *flags], check=True, cwd=root)
                executed = subprocess.run([str(output)], capture_output=True, text=True, cwd=root)
                assert executed.returncode == 0, (fixture.name, executed.stderr)
                assert executed.stderr == "", (fixture.name, executed.stderr)
        # The helper embeds its Python executable as the default. Assert actual
        # runtime discovery, rather than merely inspecting the compiler define.
        consumer = root / "environment"
        consumer.mkdir()
        source = (REPO / "tests/feature_tests/python/01_json/main.rg").read_text()
        insertion = source.index("\n", source.index("interpreter ::="))
        expected = json.dumps(sys.prefix, ensure_ascii=False)
        source = source[:insertion] + f'''
    sys_module ::= unwrap_or_abort(.value = python.import_module(.self = &interpreter, .name = "sys")).result
    prefix_object ::= unwrap_or_abort(.value = python.attribute(.self = &sys_module, .name = "prefix")).result
    prefix_text ::= unwrap_or_abort(.value = python.to_string(.self = &prefix_object, .allocator = system.page_allocator)).result
    if contains(.self = as_view(.self = &prefix_text).view, .pattern = {expected}).ok == false {{ abort }}
''' + source[insertion:]
        (consumer / "main.rg").write_text(source, encoding="utf-8")
        output = root / ("environment.exe" if os.name == "nt" else "environment-app")
        subprocess.run([*helper, "build", str(consumer), "--output", str(output)], check=True, cwd=root)
        subprocess.run([str(output)], check=True, cwd=root)
        if options.numpy:
            subprocess.run([*helper, "build", str(REPO / "more/python/examples/numpy"),
                            "--output", str(output), "--release"], check=True, cwd=root)
            subprocess.run([str(output)], check=True, cwd=root)
        # Exercise preparation from an installed source bundle as well.
        installed_helper = Path(argi).parent.parent / "lib/argi/more/python/build.py"
        if not installed_helper.is_file():
            raise AssertionError("The installed more bundle must include the Python helper")
        installed_command = helper.copy()
        installed_command[1] = str(installed_helper)
        subprocess.run([*installed_command, "build", str(consumer), "--output", str(output)], check=True, cwd=root)
        subprocess.run([str(output)], check=True, cwd=root)
        print(f"Python adapter smoke passed: {sys.version.split()[0]} on {sys.platform}")


if __name__ == "__main__":
    main()
