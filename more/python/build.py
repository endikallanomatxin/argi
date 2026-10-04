#!/usr/bin/env python3
"""Prepare the optional CPython adapter or build an Argi consumer with it."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import sysconfig
import tempfile

MODULE = Path(__file__).resolve().parent


def library_path(override):
    if override:
        candidate = Path(override).resolve()
        if not candidate.is_file():
            raise ValueError(f"Python embedding library does not exist: {candidate}")
        return candidate
    names = [sysconfig.get_config_var(key) for key in ("LDLIBRARY", "INSTSONAME")]
    candidates = []
    for root in (sysconfig.get_config_var("LIBDIR"), sysconfig.get_config_var("LIBPL"),
                 str(Path(sys.base_prefix) / "libs")):
        if root:
            candidates.extend(Path(root) / name for name in names if name)
    if os.name == "nt":
        candidates.append(Path(sys.base_prefix) / "libs" / f"python{sys.version_info.major}{sys.version_info.minor}.lib")
    framework = sysconfig.get_config_var("PYTHONFRAMEWORK")
    prefix = sysconfig.get_config_var("PYTHONFRAMEWORKPREFIX")
    version = sysconfig.get_config_var("VERSION")
    if framework and prefix and version:
        candidates.append(Path(prefix) / f"{framework}.framework" / "Versions" / version / framework)
    for candidate in candidates:
        if candidate.is_file() and candidate.suffix != ".a":
            return candidate.resolve()
    raise ValueError("Cannot find a shared CPython embedding library. Install the matching development "
                     "package or pass --library explicitly; static builds need explicit linker dependencies.")


def prepare(options):
    if sys.version_info < (3, 12) or sys.implementation.name != "cpython":
        raise ValueError("The adapter requires CPython 3.12 or newer")
    if sysconfig.get_config_var("Py_GIL_DISABLED"):
        raise ValueError("The adapter requires a standard GIL-enabled CPython build")
    driver = options.cc or os.environ.get("CC", "cc")
    resolved_driver = shutil.which(driver)
    if not resolved_driver:
        raise ValueError(f"C driver not found: {driver}. Use --cc with one driver executable.")
    resolved_driver = str(Path(resolved_driver).resolve())
    includes = [Path(path).resolve() for path in options.include_dir]
    if not includes:
        includes = list(dict.fromkeys(Path(path).resolve() for path in
                        (sysconfig.get_path("include"), sysconfig.get_path("platinclude")) if path))
    if not any((path / "Python.h").is_file() for path in includes):
        raise ValueError("Python.h is missing. Install Python development headers or pass --include-dir.")
    if not any((path / "pyconfig.h").is_file() for path in includes):
        raise ValueError("pyconfig.h is missing. Supply the matching Python configuration headers.")
    library = library_path(options.library)
    # The embedded default selects this exact installation/venv. It does not
    # change PYTHONHOME or interfere with an explicitly selected program_name.
    definition = "ARGI_PYTHON_DEFAULT_EXECUTABLE=" + json.dumps(sys.executable, ensure_ascii=False)
    compile_flags = ["-std=c11", "-O2", "-fPIC"] if os.name != "nt" else ["-std=c11", "-O2"]
    compile_flags += ["-I" + str(path) for path in includes]
    compile_flags += ["-D" + definition, "-DARGI_PYTHON_VERSION=" + hex(sys.hexversion), *options.cc_arg]
    identity = {"executable": sys.executable, "version": sys.version,
                "abi": sysconfig.get_config_var("SOABI"), "library": str(library),
                "driver": resolved_driver, "driver_stat": [os.stat(resolved_driver).st_size, os.stat(resolved_driver).st_mtime_ns],
                "flags": compile_flags}
    digest = hashlib.sha256(json.dumps(identity, sort_keys=True).encode())
    for source in sorted([*MODULE.glob("*.c"), *MODULE.glob("*.h")]):
        digest.update(source.name.encode())
        digest.update(source.read_bytes())
    # Fingerprint the selected headers too: a patched development bundle must
    # not silently reuse an object compiled with different declarations/macros.
    for include in includes:
        for header in sorted(include.rglob("*.h")):
            digest.update(str(header).encode())
            digest.update(header.read_bytes())
    cache = Path(options.cache_dir).resolve() / digest.hexdigest()
    cache.mkdir(parents=True, exist_ok=True)
    runtime = cache / ("runtime.obj" if os.name == "nt" else "runtime.o")
    if not runtime.is_file():
        with tempfile.TemporaryDirectory(prefix="compile-", dir=cache) as temporary:
            output = Path(temporary) / runtime.name
            command = [resolved_driver, *compile_flags, "-c", str(MODULE / "runtime.c"), "-o", str(output)]
            subprocess.run(command, check=True)
            os.replace(output, runtime)
    runtime_flags = [] if os.name == "nt" else ["-Xlinker", "-rpath", "-Xlinker", str(library.parent)]
    return {"runtime_object": str(runtime), "python_library": str(library),
            "python_executable": sys.executable, "cc": resolved_driver,
            "compile_flags": compile_flags, "runtime_link_flags": runtime_flags,
            "cc_args": [*options.cc_arg, *runtime_flags]}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cc", help="GCC-compatible C driver (default: CC or cc)")
    parser.add_argument("--cc-arg", action="append", default=[], help="Driver argument; use --cc-arg=-flag")
    parser.add_argument("--include-dir", action="append", default=[], help="Matching header directory (repeatable)")
    parser.add_argument("--library", help="Matching embedding library file")
    parser.add_argument("--cache-dir", default=".argi-cache/native/python")
    parser.add_argument("--argi", help="Argi executable (default: PATH or checkout installation)")
    parser.add_argument("--json", action="store_true", help="Emit preparation metadata as JSON")
    parser.add_argument("command", choices=("prepare", "build", "run", "test"))
    parser.add_argument("arguments", nargs=argparse.REMAINDER)
    options = parser.parse_args(argv)
    try:
        if any(argument == "--target" or argument.startswith("--target=") for argument in options.arguments):
            raise ValueError("Python autodiscovery prepares the native target; cross builds need explicit target headers and libraries")
        prepared = prepare(options)
        if options.command == "prepare":
            if options.arguments:
                raise ValueError("prepare does not accept Argi arguments")
            if options.json:
                print(json.dumps(prepared))
            else:
                for key in ("runtime_object", "python_library"):
                    print("[[native]]\nfile = " + json.dumps(prepared[key], ensure_ascii=False))
            return 0
        argi = options.argi or shutil.which("argi")
        if not argi:
            candidate = MODULE.parents[1] / "zig-out" / "bin" / ("argi.exe" if os.name == "nt" else "argi")
            if candidate.is_file():
                argi = str(candidate)
        if not argi:
            raise ValueError("Argi executable not found. Put it on PATH or pass --argi.")
        command = [argi, options.command, *options.arguments,
                   "--cc", prepared["cc"], "--link-file", prepared["runtime_object"],
                   "--link-file", prepared["python_library"]]
        for argument in prepared["cc_args"]:
            command += ["--cc-arg", argument]
        environment = os.environ.copy()
        if os.name == "nt":
            environment["PATH"] = sys.base_prefix + os.pathsep + environment.get("PATH", "")
        return subprocess.run(command, env=environment).returncode
    except (ValueError, OSError) as error:
        print(f"Python preparation error: {error}", file=sys.stderr)
        return 1
    except subprocess.CalledProcessError as error:
        print(f"Python adapter compilation failed (exit {error.returncode})", file=sys.stderr)
        return error.returncode or 1


if __name__ == "__main__":
    sys.exit(main())
